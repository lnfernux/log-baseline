[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'scripts' 'New-FieldAnalysis.ps1'
$fixturePath = Join-Path $PSScriptRoot 'fixtures' 'azure-sentinel'
$classificationPath = Join-Path $PSScriptRoot 'fixtures' 'field-analysis-classifications.json'
$tableCatalogPath = Join-Path $PSScriptRoot 'fixtures' 'field-analysis-table-catalog.json'
$tableSchemaPath = Join-Path $PSScriptRoot 'fixtures' 'field-analysis-table-schema.json'
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
    $sharedPath = Join-Path $outputPath 'shared-table-source-candidates.json'

    & $scriptPath `
        -AzureSentinelPath $fixturePath `
        -ClassificationsPath $classificationPath `
        -TableCatalogPath $tableCatalogPath `
        -TableSchemaPath $tableSchemaPath `
        -ExistingHighValueFieldsPath $existingHighValuePath `
        -FieldFrequencyOutputPath $frequencyPath `
        -HighValueFieldsOutputPath $highValuePath `
        -SummaryOutputPath $summaryPath `
        -SharedSourceCandidatesOutputPath $sharedPath `
        -SourceRevision ('a' * 40) `
        -GeneratedAt ([datetimeoffset]'2026-09-22T00:00:00Z')

    Assert-Test (Test-Path -LiteralPath $frequencyPath) 'Field-frequency output was not created'
    Assert-Test (Test-Path -LiteralPath $highValuePath) 'High-value candidate output was not created'
    Assert-Test (Test-Path -LiteralPath $summaryPath) 'Review summary was not created'

    if (Test-Path -LiteralPath $frequencyPath) {
        $frequency = Get-Content -LiteralPath $frequencyPath -Raw | ConvertFrom-Json
        Assert-Test ($frequency.generatedAt -eq '2026-09-22T00:00:00.0000000+00:00') 'Generated timestamp was not deterministic'
        Assert-Test ($frequency.totalRulesParsed -eq 14) 'Expected fourteen parsed rules'
        Assert-Test ($frequency.totalTables -eq 4) 'Expected four discovered tables; parsers and legacy-only names are not tables'
        Assert-Test (@($frequency.universalFields) -contains 'TimeGenerated') 'TimeGenerated should be universal in the fixture'
        Assert-Test ($frequency.perTable.FixtureSecurity_CL.Account -eq 4) 'Account frequency should be counted once per matching rule'
        Assert-Test ($frequency.perTable.FixtureSecurity_CL.EventID -eq 4) 'EventID frequency should be counted once per matching rule'
        Assert-Test ($frequency.perTable.PSObject.Properties.Name -notcontains 'FixtureSignin_CL') 'Tables below the rule threshold should not appear in perTable'
        Assert-Test ($null -ne $frequency.perTable.FixtureStandardTable) 'Catalog-listed standard tables must remain discoverable before classification'
        Assert-Test ($frequency.perTable.PSObject.Properties.Name -notcontains 'against') 'KQL aliases must not be admitted by catalog-backed discovery'
        Assert-Test ($frequency.perTable.FixtureStandardTable.PSObject.Properties.Name -notcontains 'RiskScore') 'Calculated fields must be dropped for tables with a known schema'
        Assert-Test ($frequency.perTable.FixtureStandardTable.SourceAddress -ge 3) 'Real columns must be kept for tables with a known schema'
        Assert-Test ('SourceAddress' -cin @($frequency.perTable.FixtureStandardTable.PSObject.Properties.Name)) 'Known columns must use the schema spelling, not the first rule spelling'
        Assert-Test (@($frequency.unverifiedTables) -contains 'FixtureSecurity_CL') 'Tables without a known schema must be listed as unverified'
        Assert-Test (@($frequency.unverifiedTables) -notcontains 'FixtureStandardTable') 'Schema-backed tables must not be listed as unverified'
        Assert-Test ($frequency.perTable.PSObject.Properties.Name -notcontains 'FixtureParser') 'Parser aliases must not appear as tables, even when classified'
        $parser = $frequency.parsers.FixtureParser
        Assert-Test ($null -ne $parser) 'Parsers called by rules must be listed'
        if ($null -ne $parser) {
            Assert-Test ($parser.ruleCount -eq 3) 'Parser calls by name, with parentheses, and through let must all count'
            Assert-Test ((@($parser.tables) -join ',') -eq 'FixtureSecurity_CL,FixtureStandardTable') 'Parser source tables must be mapped'
            Assert-Test ($parser.outputColumnsVerified -eq $true) 'Parser output columns should come from the KQL validation definition'
            Assert-Test ($parser.fields.PSObject.Properties.Name -notcontains 'Calculated') 'Parser fields must be limited to parser output columns'
            Assert-Test ($parser.fields.UserName -eq 2) 'Parsed fields must be counted for the parser'
            Assert-Test (@($parser.sourceColumns) -contains 'SourceAddress') 'Source columns the parser reads must be listed when the source schema is known'
            Assert-Test (@($parser.sourceColumns) -notcontains 'UserName') 'Parsed column names must not be listed as source columns'
        }
    }

    if (Test-Path -LiteralPath $highValuePath) {
        $highValue = Get-Content -LiteralPath $highValuePath -Raw | ConvertFrom-Json
        Assert-Test ($null -ne $highValue.CuratedTable) 'Curated high-value entries must be preserved'
        Assert-Test ($null -ne $highValue.FixtureSecurity_CL) 'Eligible mined tables should be added as candidates'
        Assert-Test ($null -ne $highValue.FixtureStandardTable) 'Catalog-listed standard tables should become review candidates'
        Assert-Test (@($highValue.FixtureSecurity_CL.highValueFields).Count -ge 3) 'Mined candidates need at least three fields'
        Assert-Test (@($highValue.FixtureSecurity_CL.splitHints).Count -eq 0) 'Automation must not invent split hints'
        Assert-Test ($highValue.FixtureSecurity_CL.description -match 'not schema-verified') 'Unverified candidates must say so in the description'
        Assert-Test ($highValue.PSObject.Properties.Name -notcontains 'FixtureParser') 'Parsers must not become high-value table candidates'
    }

    Assert-Test (Test-Json -Path $frequencyPath -SchemaFile (Join-Path $root 'schemas' 'field-frequency-stats.schema.json')) 'Field-frequency output failed schema validation'

    Assert-Test (Test-Path -LiteralPath $sharedPath) 'Shared-table source candidates were not created'
    if (Test-Path -LiteralPath $sharedPath) {
        $shared = @((Get-Content -LiteralPath $sharedPath -Raw | ConvertFrom-Json).candidates)
        $viaParser = @($shared | Where-Object { $_.table -eq 'CommonSecurityLog' -and $_.filter -eq 'DeviceVendor =~ "fixturevendor"' })
        Assert-Test ($viaParser.Count -eq 1) 'Parser filters over shared tables must become source candidates'
        if ($viaParser.Count -eq 1) {
            Assert-Test ((@($viaParser[0].parsers) -join ',') -eq 'FixtureCefParser') 'Source candidates must name the parser'
            Assert-Test ($viaParser[0].parserRuleCount -eq 1) 'Rules that call the parser must count for the source'
        }
        $direct = @($shared | Where-Object { $_.filter -eq 'DeviceVendor == "OtherVendor" and DeviceProduct == "Gateway"' })
        Assert-Test ($direct.Count -eq 1 -and $direct[0].directRuleCount -eq 1) 'Direct vendor filters on shared tables must become source candidates'
        Assert-Test (@($shared | Where-Object { $_.table -ne 'CommonSecurityLog' }).Count -eq 0) 'Only shared tables produce source candidates'
    }
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