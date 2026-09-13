[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InputPath,

    [Parameter(Mandatory)]
    [datetime]$ObservedOn
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dataPath = Join-Path $root 'data'
$sourceUrl = 'https://learn.microsoft.com/azure/azure-monitor/reference/tables-features'
$lines = Get-Content -LiteralPath $InputPath
$basicTables = [System.Collections.Generic.List[string]]::new()
$auxiliaryTables = [System.Collections.Generic.List[string]]::new()

foreach ($line in $lines) {
    if ($line -notmatch '^\| \[([^\]]+)\]\([^\)]+\) \|') { continue }
    $columns = $line.Split('|')
    if ($columns.Count -lt 6) { continue }

    $tableName = $Matches[1]
    if ($columns[2] -match 'basic-table\.svg') { $basicTables.Add($tableName) }
    if ($columns[3] -match 'auxiliary-table\.svg') { $auxiliaryTables.Add($tableName) }
}

if ($basicTables.Count -eq 0 -or $auxiliaryTables.Count -eq 0) {
    throw 'The input does not contain the expected Microsoft Learn table feature matrix.'
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
foreach ($plan in @(
    @{ FileName = 'basic-plan-tables.json'; Tables = $basicTables },
    @{ FileName = 'auxiliary-plan-tables.json'; Tables = $auxiliaryTables }
)) {
    $document = [ordered]@{
        source = $sourceUrl
        generatedOn = $ObservedOn.ToString('yyyy-MM-dd')
        tables = @($plan.Tables | Sort-Object -Unique)
    }
    $json = (($document | ConvertTo-Json -Depth 5) + "`n").Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText((Join-Path $dataPath $plan.FileName), $json, $utf8NoBom)
}

$sourcesPath = Join-Path $dataPath 'sources.json'
$sources = Get-Content -LiteralPath $sourcesPath -Raw | ConvertFrom-Json
$source = @($sources.sources | Where-Object id -eq 'microsoft-learn-table-features')
if ($source.Count -ne 1) { throw 'Plan-table provenance record is missing or duplicated.' }
$source[0].revision = "observed-$($ObservedOn.ToString('yyyy-MM-dd'))"
$source[0].observedOn = $ObservedOn.ToString('yyyy-MM-dd')
$sourcesJson = (($sources | ConvertTo-Json -Depth 20) + "`n").Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText($sourcesPath, $sourcesJson, $utf8NoBom)

& (Join-Path $PSScriptRoot 'Update-Manifest.ps1')
& (Join-Path $PSScriptRoot 'Test-Baseline.ps1')
