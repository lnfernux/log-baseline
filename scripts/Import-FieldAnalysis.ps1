[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$FieldFrequencyPath,

    [Parameter(Mandatory)]
    [string]$HighValueFieldsPath,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string]$AzureSentinelRevision,

    [Parameter(Mandatory)]
    [datetime]$ObservedOn
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dataPath = Join-Path $root 'data'
$schemaPath = Join-Path $root 'schemas'
$imports = @(
    @{ Source = $FieldFrequencyPath; FileName = 'field-frequency-stats.json'; Schema = 'field-frequency-stats.schema.json' },
    @{ Source = $HighValueFieldsPath; FileName = 'high-value-fields.json'; Schema = 'high-value-fields.schema.json' }
)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

foreach ($import in $imports) {
    if (-not (Test-Json -Path $import.Source -SchemaFile (Join-Path $schemaPath $import.Schema))) {
        throw "$($import.Source) does not match $($import.Schema)"
    }
    $content = [System.IO.File]::ReadAllText($import.Source).Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText((Join-Path $dataPath $import.FileName), $content, $utf8NoBom)
}

$sourcesPath = Join-Path $dataPath 'sources.json'
$sources = Get-Content -LiteralPath $sourcesPath -Raw | ConvertFrom-Json
$source = @($sources.sources | Where-Object id -eq 'azure-sentinel-rule-corpus')
if ($source.Count -ne 1) { throw 'Field-analysis provenance record is missing or duplicated.' }
$source[0].revision = $AzureSentinelRevision.ToLowerInvariant()
$source[0].observedOn = $ObservedOn.ToString('yyyy-MM-dd')
$sourcesJson = (($sources | ConvertTo-Json -Depth 20) + "`n").Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText($sourcesPath, $sourcesJson, $utf8NoBom)

& (Join-Path $PSScriptRoot 'Update-Manifest.ps1')
& (Join-Path $PSScriptRoot 'Test-Baseline.ps1')