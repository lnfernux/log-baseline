[CmdletBinding(DefaultParameterSetName = 'Online')]
param(
    [Parameter(ParameterSetName = 'Offline', Mandatory)]
    [string]$MetadataPath,

    [Parameter(ParameterSetName = 'Online')]
    [uri]$MetadataUri = 'https://api.loganalytics.io/v1/metadata',

    [Parameter(Mandatory)]
    [string]$SnapshotPath,

    [Parameter(Mandatory)]
    [string]$ReportPath,

    [Parameter(Mandatory)]
    [string]$ResultPath,

    [datetime]$ObservedOn = (Get-Date),

    [ValidateRange(1, [int]::MaxValue)]
    [int]$MinimumTableCount = 500,

    [switch]$InitializeSnapshot,

    [switch]$UpdateSnapshot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON file not found: $Path"
    }

    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
}

function Write-Utf8File {
    param([string]$Path, [string]$Content)

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $normalized = $Content -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($Path, $normalized, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-CatalogTable {
    param([object]$Table)

    $name = if ($Table.PSObject.Properties.Name -contains 'name') { [string]$Table.name } else { '' }
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw 'Metadata contains a table without a name.'
    }

    [pscustomobject][ordered]@{
        name          = $name
        tableType     = if ($Table.PSObject.Properties.Name -contains 'tableType') { [string]$Table.tableType } else { '' }
        tableAPIState = if ($Table.PSObject.Properties.Name -contains 'tableAPIState') { [string]$Table.tableAPIState } else { '' }
        description   = if ($Table.PSObject.Properties.Name -contains 'description') { [string]$Table.description } else { '' }
    }
}

if ($PSCmdlet.ParameterSetName -eq 'Offline') {
    $metadata = Read-JsonFile -Path $MetadataPath
    $source = (Resolve-Path -LiteralPath $MetadataPath).Path
}
else {
    $headers = @{
        Accept       = 'application/json'
        'User-Agent' = 'log-baseline-table-review/1.0'
    }
    $metadata = Invoke-RestMethod -Uri $MetadataUri -Method Get -Headers $headers
    $source = $MetadataUri.AbsoluteUri
}

if ($metadata.PSObject.Properties.Name -notcontains 'tables') {
    throw "Metadata response from '$source' does not contain a tables property."
}

$catalogTables = @($metadata.tables | ForEach-Object { ConvertTo-CatalogTable -Table $_ } | Sort-Object name -Unique)
if ($catalogTables.Count -lt $MinimumTableCount) {
    throw "Metadata response from '$source' contained $($catalogTables.Count) tables; expected at least $MinimumTableCount. Refusing to calculate removals."
}

$initialized = -not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)
if ($initialized) {
    if (-not $InitializeSnapshot) {
        throw "Snapshot not found: $SnapshotPath. Use -InitializeSnapshot only when intentionally creating the first review snapshot."
    }
    $previousNames = @()
}
else {
    $snapshot = Read-JsonFile -Path $SnapshotPath
    if ($snapshot.PSObject.Properties.Name -notcontains 'tables') {
        throw "Snapshot '$SnapshotPath' does not contain a tables property."
    }

    $previousNames = @($snapshot.tables | ForEach-Object { [string]$_.name } | Where-Object { $_ } | Sort-Object -Unique)
    if ($previousNames.Count -eq 0) {
        throw "Snapshot '$SnapshotPath' contains no table names. Refusing to calculate drift."
    }
}

$currentNames = @($catalogTables.name)
$added = @($(if (-not $initialized) { $currentNames | Where-Object { $_ -notin $previousNames } }))
$removed = @($(if (-not $initialized) { $previousNames | Where-Object { $_ -notin $currentNames } }))
$changed = $added.Count -gt 0 -or $removed.Count -gt 0
$observedDate = $ObservedOn.ToString('yyyy-MM-dd')

$addedDetails = @($catalogTables | Where-Object { $_.name -in $added })
$reportLines = [System.Collections.Generic.List[string]]::new()
$reportLines.Add('# Microsoft Sentinel table catalog review')
$reportLines.Add('')
$reportLines.Add("Observed: $observedDate")
$reportLines.Add("Source: $source")
$reportLines.Add("Previous tables: $($previousNames.Count)")
$reportLines.Add("Current tables: $($currentNames.Count)")
$reportLines.Add("Added: $($added.Count)")
$reportLines.Add("Removed from catalog: $($removed.Count)")
$reportLines.Add('')
if ($initialized) {
    $reportLines.Add('This is the initial source snapshot. Review and merge it before catalog drift can be calculated.')
    $reportLines.Add('')
}
$reportLines.Add('A table disappearing from this catalog does not prove that the service or table was removed. Confirm every change against public documentation before editing the baseline.')
$reportLines.Add('')
$reportLines.Add('## Added tables')
$reportLines.Add('')
if ($addedDetails.Count -eq 0) {
    $reportLines.Add('None.')
}
else {
    foreach ($table in $addedDetails) {
        $description = if ($table.description) { $table.description -replace '[\r\n]+', ' ' } else { 'No description returned.' }
        $reportLines.Add("### $($table.name)")
        $reportLines.Add('')
        $reportLines.Add("- Type: $($table.tableType)")
        $reportLines.Add("- API state: $($table.tableAPIState)")
        $reportLines.Add("- Description: $description")
        $reportLines.Add('')
    }
}
$reportLines.Add('## Removed from catalog')
$reportLines.Add('')
if ($removed.Count -eq 0) {
    $reportLines.Add('None.')
}
else {
    foreach ($name in $removed) { $reportLines.Add("- $name") }
}
$reportLines.Add('')
$reportLines.Add('## Classification review')
$reportLines.Add('')
$reportLines.Add('- Verify each table against Microsoft Learn and its connector or solution source.')
$reportLines.Add('- Separate documented facts from classification judgment.')
$reportLines.Add('- Use the baseline curator automatic proposal or human review flow before changing canonical data.')

$result = [ordered]@{
    observedOn   = $observedDate
    source       = $source
    initialized  = $initialized
    changed      = $changed
    previousCount = $previousNames.Count
    currentCount = $currentNames.Count
    addedCount   = $added.Count
    removedCount = $removed.Count
    added        = $added
    removed      = $removed
}

Write-Utf8File -Path $ReportPath -Content (($reportLines -join "`n") + "`n")
Write-Utf8File -Path $ResultPath -Content (($result | ConvertTo-Json -Depth 10) + "`n")

if ($UpdateSnapshot) {
    $nextSnapshot = [ordered]@{
        source     = $source
        observedOn = $observedDate
        tables     = $catalogTables
    }
    Write-Utf8File -Path $SnapshotPath -Content (($nextSnapshot | ConvertTo-Json -Depth 10) + "`n")
}

[pscustomobject]$result