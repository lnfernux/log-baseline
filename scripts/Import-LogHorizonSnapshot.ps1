[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourcePath,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string]$Revision
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$resolvedSourcePath = [System.IO.Path]::GetFullPath($SourcePath)
$sourceHead = (& git -C $resolvedSourcePath rev-parse HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or $sourceHead -notmatch '^[a-fA-F0-9]{40}$') {
    throw 'SourcePath must be a Git checkout with a committed HEAD.'
}
if ($sourceHead -ne $Revision) {
    throw "SourcePath is at $sourceHead, not declared revision $Revision."
}
$sourceDataPath = Join-Path $resolvedSourcePath 'Data'
$dataPath = Join-Path $root 'data'
$filesToCopy = @(
    'auxiliary-plan-tables.json',
    'basic-plan-tables.json',
    'field-frequency-stats.json',
    'high-value-fields.json',
    'implicit-consumers.json'
)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

foreach ($fileName in $filesToCopy) {
    $sourceFile = Join-Path $sourceDataPath $fileName
    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
        throw "Log Horizon snapshot is missing Data/$fileName"
    }
    $content = [System.IO.File]::ReadAllText($sourceFile).Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText((Join-Path $dataPath $fileName), $content, $utf8NoBom)
}

$classifications = @(Get-Content -LiteralPath (Join-Path $sourceDataPath 'log-classifications.json') -Raw | ConvertFrom-Json)
foreach ($entry in $classifications) {
    $entry | Add-Member -NotePropertyName sourceIds -NotePropertyValue @('log-horizon-classifications') -Force
}
$classificationJson = (($classifications | ConvertTo-Json -Depth 20) + "`n").Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText((Join-Path $dataPath 'log-classifications.json'), $classificationJson, $utf8NoBom)

$customExamples = @(Get-Content -LiteralPath (Join-Path $sourceDataPath 'custom-classifications-example.json') -Raw | ConvertFrom-Json)
foreach ($entry in $customExamples) {
    # The inherited example predates the canonical category label.
    if ($entry.category -eq 'Infrastructure Diag') {
        $entry.category = 'Infrastructure Diagnostics'
    }
    $entry | Add-Member -NotePropertyName sourceIds -NotePropertyValue @('log-horizon-custom-example') -Force
}
$customJson = (($customExamples | ConvertTo-Json -Depth 20) + "`n").Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText((Join-Path $dataPath 'custom-classifications-example.json'), $customJson, $utf8NoBom)

$sourcesPath = Join-Path $dataPath 'sources.json'
$sources = Get-Content -LiteralPath $sourcesPath -Raw | ConvertFrom-Json
$sourceMappings = @{
    'log-horizon-classifications' = 'Data/log-classifications.json'
    'log-horizon-implicit-consumers' = 'Data/implicit-consumers.json'
    'log-horizon-custom-example' = 'Data/custom-classifications-example.json'
}
foreach ($mapping in $sourceMappings.GetEnumerator()) {
    $source = @($sources.sources | Where-Object id -eq $mapping.Key)
    if ($source.Count -ne 1) { throw "Provenance record is missing or duplicated: $($mapping.Key)" }
    $history = (& git -C $resolvedSourcePath log -1 --format='%H|%cs' -- $mapping.Value)
    if ($LASTEXITCODE -ne 0 -or $history -notmatch '^([a-fA-F0-9]{40})\|(\d{4}-\d{2}-\d{2})$') {
        throw "Cannot resolve source history for $($mapping.Value)"
    }
    $source[0].revision = $Matches[1].ToLowerInvariant()
    $source[0].observedOn = $Matches[2]
    $source[0].url = "https://github.com/lnfernux/log-horizon/commit/$($Matches[1].ToLowerInvariant())"
}
$sourcesJson = (($sources | ConvertTo-Json -Depth 20) + "`n").Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText($sourcesPath, $sourcesJson, $utf8NoBom)

& (Join-Path $PSScriptRoot 'Update-Manifest.ps1')
& (Join-Path $PSScriptRoot 'Test-Baseline.ps1')
