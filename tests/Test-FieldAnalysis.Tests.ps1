[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'scripts' 'New-FieldAnalysis.ps1'
$fixturePath = Join-Path $PSScriptRoot 'fixtures' 'azure-sentinel'
$classificationPath = Join-Path $PSScriptRoot 'fixtures' 'field-analysis-classifications.json'
$existingHighValuePath = Join-Path $PSScriptRoot 'fixtures' 'high-value-fields.json'
$outputPath = Join-Path ([System.IO.Path]::GetTempPath()) "log-baseline-field-analysis-$([guid]::NewGuid().ToString('N'))"
$failures = [System.Collections.Generic.List[string]]::new()
$checks = 0

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    $script:checks++
    if (-not $Condition) { $script:failures.Add($Message) }
}

try {
    New-Item -ItemType Directory -Path $outputPath | Out-Null
    $frequencyPath = Join-Path $outputPath 'field-frequency-stats.json'
    $highValuePath = Join-Path $outputPath 'high-value-fields.json'
    $summaryPath = Join-Path $outputPath 'field-analysis-summary.md'

    & $scriptPath `
        -AzureSentinelPath $fixturePath `
        -ClassificationsPath $classificationPath `
        -ExistingHighValueFieldsPath $existingHighValuePath `
        -FieldFrequencyOutputPath $frequencyPath `
        -HighValueFieldsOutputPath $highValuePath `
        -SummaryOutputPath $summaryPath `
        -SourceRevision ('a' * 40) `
        -GeneratedAt ([datetimeoffset]'2026-09-22T00:00:00Z')

    Assert-Test (Test-Path -LiteralPath $frequencyPath) 'Field-frequency output was not created'
    Assert-Test (Test-Path -LiteralPath $highValuePath) 'High-value candidate output was not created'
    Assert-Test (Test-Path -LiteralPath $summaryPath) 'Review summary was not created'

    if (Test-Path -LiteralPath $frequencyPath) {
        $frequency = Get-Content -LiteralPath $frequencyPath -Raw | ConvertFrom-Json
        Assert-Test ($frequency.generatedAt -eq '2026-09-22T00:00:00.0000000+00:00') 'Generated timestamp was not deterministic'
        Assert-Test ($frequency.totalRulesParsed -eq 5) 'Expected five parsed rules'
        Assert-Test ($frequency.totalTables -eq 2) 'Expected two discovered tables'
        Assert-Test (@($frequency.universalFields) -contains 'TimeGenerated') 'TimeGenerated should be universal in the fixture'
        Assert-Test ($frequency.perTable.FixtureSecurity_CL.Account -eq 4) 'Account frequency should be counted once per matching rule'
        Assert-Test ($frequency.perTable.FixtureSecurity_CL.EventID -eq 4) 'EventID frequency should be counted once per matching rule'
        Assert-Test ($frequency.perTable.PSObject.Properties.Name -notcontains 'FixtureSignin_CL') 'Tables below the rule threshold should not appear in perTable'
    }

    if (Test-Path -LiteralPath $highValuePath) {
        $highValue = Get-Content -LiteralPath $highValuePath -Raw | ConvertFrom-Json
        Assert-Test ($null -ne $highValue.CuratedTable) 'Curated high-value entries must be preserved'
        Assert-Test ($null -ne $highValue.FixtureSecurity_CL) 'Eligible mined tables should be added as candidates'
        Assert-Test (@($highValue.FixtureSecurity_CL.highValueFields).Count -ge 3) 'Mined candidates need at least three fields'
        Assert-Test (@($highValue.FixtureSecurity_CL.splitHints).Count -eq 0) 'Automation must not invent split hints'
    }

    Assert-Test (Test-Json -Path $frequencyPath -SchemaFile (Join-Path $root 'schemas' 'field-frequency-stats.schema.json')) 'Field-frequency output failed schema validation'
    Assert-Test (Test-Json -Path $highValuePath -SchemaFile (Join-Path $root 'schemas' 'high-value-fields.schema.json')) 'High-value candidate output failed schema validation'
}
finally {
    Remove-Item -LiteralPath $outputPath -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Error ("Field-analysis tests failed with {0} error(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
    exit 1
}

Write-Host "Field-analysis tests passed: $checks checks."