[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CandidatesPath,

    [Parameter(Mandatory)]
    [string]$DecisionsPath,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string]$AzureSentinelRevision,

    [Parameter(Mandatory)]
    [datetime]$ObservedOn,

    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$DataVersion,

    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($RootPath)
$dataPath = Join-Path $root 'data'
$classificationsPath = Join-Path $dataPath 'log-classifications.json'
$sourcesPath = Join-Path $dataPath 'sources.json'
$manifestPath = Join-Path $dataPath 'manifest.json'
$schemaPath = Join-Path $root 'schemas' 'log-classifications.schema.json'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

foreach ($path in $CandidatesPath, $DecisionsPath, $classificationsPath, $sourcesPath, $manifestPath, $schemaPath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file does not exist: $path" }
}

$candidates = @(Get-Content -LiteralPath $CandidatesPath -Raw | ConvertFrom-Json -Depth 100)
$decisionDocument = Get-Content -LiteralPath $DecisionsPath -Raw | ConvertFrom-Json -Depth 100
$decisions = @($decisionDocument.decisions)
if ($decisions.Count -eq 0) { throw 'The decision file contains no decisions.' }
if (@($decisions.tableName | Sort-Object -Unique).Count -ne $decisions.Count) { throw 'Decision table names must be unique.' }

$candidateByName = @{}
foreach ($candidate in $candidates) { $candidateByName[[string]$candidate.tableName] = $candidate }
$approved = [System.Collections.Generic.List[object]]::new()
foreach ($decision in $decisions) {
    if ($decision.decision -notin @('accept', 'edit')) { throw "$($decision.tableName): only accept and edit decisions can be imported." }
    if (-not $candidateByName.ContainsKey([string]$decision.tableName)) { throw "$($decision.tableName): decision has no matching candidate." }

    $record = $candidateByName[[string]$decision.tableName].proposed.PSObject.Copy()
    if ($decision.decision -eq 'edit') {
        if ($decision.PSObject.Properties.Name -notcontains 'changes') { throw "$($decision.tableName): edit decision has no changes." }
        foreach ($change in $decision.changes.PSObject.Properties) {
            if ($record.PSObject.Properties.Name -notcontains $change.Name) { throw "$($decision.tableName): unknown field '$($change.Name)'." }
            $record.$($change.Name) = $change.Value
        }
    }
    $approved.Add($record)
}

$current = @(Get-Content -LiteralPath $classificationsPath -Raw | ConvertFrom-Json -Depth 100)
$currentNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $current) { [void]$currentNames.Add([string]$entry.tableName) }
foreach ($record in $approved) {
    if ($currentNames.Contains([string]$record.tableName)) { throw "$($record.tableName): classification already exists." }
}

$merged = @($current + $approved)
$temporaryPath = Join-Path ([System.IO.Path]::GetTempPath()) "log-baseline-classifications-$([guid]::NewGuid().ToString('N')).json"
try {
    $mergedJson = (($merged | ConvertTo-Json -Depth 30) + "`n").Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText($temporaryPath, $mergedJson, $utf8NoBom)
    if (-not (Test-Json -Path $temporaryPath -SchemaFile $schemaPath)) { throw 'Merged classifications do not match the schema.' }
    [System.IO.File]::WriteAllText($classificationsPath, $mergedJson, $utf8NoBom)
}
finally {
    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
}

$sources = Get-Content -LiteralPath $sourcesPath -Raw | ConvertFrom-Json -Depth 100
$source = @($sources.sources | Where-Object id -eq 'azure-sentinel-rule-corpus')
if ($source.Count -ne 1) { throw 'Azure-Sentinel provenance record is missing or duplicated.' }
$source[0].title = 'Azure-Sentinel public content corpus'
$source[0].url = "https://github.com/Azure/Azure-Sentinel/commit/$($AzureSentinelRevision.ToLowerInvariant())"
$source[0].revision = $AzureSentinelRevision.ToLowerInvariant()
$source[0].observedOn = $ObservedOn.ToString('yyyy-MM-dd')
$source[0].appliesTo = @($source[0].appliesTo + 'log-classifications.json' | Sort-Object -Unique)
$source[0].scope = 'Table identity and usage evidence from public analytics rules, hunting queries, parsers, and solution content. Classification, tier, retention, and billing recommendations require human review.'
$sourcesJson = (($sources | ConvertTo-Json -Depth 30) + "`n").Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText($sourcesPath, $sourcesJson, $utf8NoBom)

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ([version]$DataVersion -le [version]$manifest.dataVersion) { throw "DataVersion must be greater than $($manifest.dataVersion)." }
$manifest.dataVersion = $DataVersion
$manifest.importedOn = $ObservedOn.ToString('yyyy-MM-dd')
$manifestJson = (($manifest | ConvertTo-Json -Depth 20) + "`n").Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText($manifestPath, $manifestJson, $utf8NoBom)

& (Join-Path $root 'scripts' 'Update-Manifest.ps1') -RootPath $root
& (Join-Path $root 'scripts' 'Test-Baseline.ps1') -RootPath $root

Write-Host "Imported $($approved.Count) reviewed classifications at Azure-Sentinel revision $($AzureSentinelRevision.ToLowerInvariant())."
