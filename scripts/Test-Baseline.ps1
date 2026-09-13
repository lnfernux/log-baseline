[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dataPath = Join-Path $root 'data'
$schemaPath = Join-Path $root 'schemas'
$failures = [System.Collections.Generic.List[string]]::new()
$checks = 0

function Assert-Baseline {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $script:checks++
    if (-not $Condition) {
        $script:failures.Add($Message)
    }
}

function Read-BaselineJson {
    param([Parameter(Mandatory)][string]$Path)

    Assert-Baseline (Test-Path -LiteralPath $Path -PathType Leaf) "Missing file: $Path"
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        $script:failures.Add("Invalid JSON in ${Path}: $($_.Exception.Message)")
        return $null
    }
}

function Test-Schema {
    param(
        [Parameter(Mandatory)][string]$DataFile,
        [Parameter(Mandatory)][string]$SchemaFile
    )

    $jsonPath = Join-Path $dataPath $DataFile
    $jsonSchemaPath = Join-Path $schemaPath $SchemaFile
    try {
        $valid = Test-Json -Path $jsonPath -SchemaFile $jsonSchemaPath -ErrorAction Stop
        Assert-Baseline $valid "$DataFile does not match $SchemaFile"
    }
    catch {
        $script:failures.Add("Schema validation failed for ${DataFile}: $($_.Exception.Message)")
    }
}

$schemaMappings = @{
    'log-classifications.json' = 'log-classifications.schema.json'
    'basic-plan-tables.json' = 'plan-tables.schema.json'
    'auxiliary-plan-tables.json' = 'plan-tables.schema.json'
    'implicit-consumers.json' = 'implicit-consumers.schema.json'
    'high-value-fields.json' = 'high-value-fields.schema.json'
    'field-frequency-stats.json' = 'field-frequency-stats.schema.json'
    'custom-classifications-example.json' = 'log-classifications.schema.json'
    'taxonomy.json' = 'taxonomy.schema.json'
    'manifest.json' = 'manifest.schema.json'
}

foreach ($mapping in $schemaMappings.GetEnumerator()) {
    Test-Schema -DataFile $mapping.Key -SchemaFile $mapping.Value
}

$manifest = Read-BaselineJson (Join-Path $dataPath 'manifest.json')
if ($null -ne $manifest) {
    foreach ($fileProperty in $manifest.files.PSObject.Properties) {
        $file = Join-Path $dataPath $fileProperty.Name
        Assert-Baseline (Test-Path -LiteralPath $file -PathType Leaf) "Manifest file is missing: $($fileProperty.Name)"
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            $actualHash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
            Assert-Baseline ($actualHash -eq $fileProperty.Value) "Checksum mismatch: $($fileProperty.Name)"
        }
    }
}

$classifications = @(Read-BaselineJson (Join-Path $dataPath 'log-classifications.json'))
$tableNames = @($classifications.tableName)
$allowedCategories = @(
    'Application Logs', 'Cloud Control Plane', 'Cloud Security', 'Configuration Management',
    'Container & Kubernetes', 'Data Platform', 'Data Security', 'Email Security',
    'Endpoint Detection', 'Endpoint Telemetry', 'Identity & Access', 'Infrastructure Diagnostics',
    'IoT/OT Security', 'Network Flow', 'Network Security', 'Platform Health',
    'Posture Management', 'SAP Security', 'Security Alerts', 'Storage Access',
    'Threat Intelligence', 'Vulnerability Management'
)

Assert-Baseline ($classifications.Count -ge 480) 'Expected at least 480 classification entries'
Assert-Baseline (@($tableNames | Sort-Object -Unique).Count -eq $tableNames.Count) 'Classification table names must be unique'

$taxonomy = Read-BaselineJson (Join-Path $dataPath 'taxonomy.json')
$domainIds = @($taxonomy.domains.id)
$logTypeIds = @($taxonomy.logTypes.id)
Assert-Baseline (@($domainIds | Sort-Object -Unique).Count -eq $domainIds.Count) 'Taxonomy domain IDs must be unique'
Assert-Baseline (@($logTypeIds | Sort-Object -Unique).Count -eq $logTypeIds.Count) 'Taxonomy log type IDs must be unique'
foreach ($category in $allowedCategories) {
    Assert-Baseline ($taxonomy.categoryMappings.PSObject.Properties.Name -contains $category) "Taxonomy is missing category: $category"
}
foreach ($mappingProperty in @($taxonomy.categoryMappings.PSObject.Properties) + @($taxonomy.tableOverrides.PSObject.Properties)) {
    $mapping = $mappingProperty.Value
    Assert-Baseline ($mapping.domainId -in $domainIds) "Taxonomy references unknown domain: $($mapping.domainId)"
    Assert-Baseline ($mapping.logTypeId -in $logTypeIds) "Taxonomy references unknown log type: $($mapping.logTypeId)"
}
foreach ($tableOverride in $taxonomy.tableOverrides.PSObject.Properties) {
    Assert-Baseline ($tableOverride.Name -in $tableNames) "Taxonomy override references unknown table: $($tableOverride.Name)"
}

foreach ($entry in $classifications) {
    Assert-Baseline ($entry.classification -in @('primary', 'secondary')) "$($entry.tableName): invalid classification"
    Assert-Baseline ($entry.category -in $allowedCategories) "$($entry.tableName): invalid category"
    Assert-Baseline ($entry.recommendedTier -in @('analytics', 'datalake')) "$($entry.tableName): invalid recommended tier"
    Assert-Baseline ($entry.recommendedRetentionDays -in @(90, 180, 365)) "$($entry.tableName): invalid retention"

    $hasStatus = $entry.PSObject.Properties.Name -contains 'status'
    $hasReplacement = $entry.PSObject.Properties.Name -contains 'replacedBy'
    Assert-Baseline ($hasStatus -eq $hasReplacement) "$($entry.tableName): status and replacedBy must appear together"
    if ($hasStatus) {
        Assert-Baseline ($entry.status -in @('deprecated', 'legacy')) "$($entry.tableName): invalid lifecycle status"
        foreach ($replacement in @($entry.replacedBy)) {
            Assert-Baseline ($replacement -in $tableNames) "$($entry.tableName): missing replacement table $replacement"
        }
    }
}

foreach ($planFile in 'basic-plan-tables.json', 'auxiliary-plan-tables.json') {
    $plan = Read-BaselineJson (Join-Path $dataPath $planFile)
    if ($null -eq $plan) { continue }
    $uniqueTables = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($tableName in @($plan.tables)) {
        [void]$uniqueTables.Add($tableName)
    }
    Assert-Baseline ($uniqueTables.Count -eq @($plan.tables).Count) "$planFile must contain unique tables"
    $orderingMismatch = $false
    for ($index = 1; $index -lt @($plan.tables).Count; $index++) {
        if ([string]::CompareOrdinal($plan.tables[$index - 1], $plan.tables[$index]) -gt 0) {
            $orderingMismatch = $true
            break
        }
    }
    Assert-Baseline (-not $orderingMismatch) "$planFile must be sorted ordinally"
    Assert-Baseline ($plan.source -match '^https://learn\.microsoft\.com/.*/tables-features$') "$planFile has an unexpected source URL"
}

$implicitConsumers = Read-BaselineJson (Join-Path $dataPath 'implicit-consumers.json')
if ($null -ne $implicitConsumers) {
    foreach ($ruleKind in $implicitConsumers.ruleKinds.PSObject.Properties) {
        foreach ($tableName in @($ruleKind.Value)) {
            Assert-Baseline ($tableName -in $tableNames) "$($ruleKind.Name): unknown table $tableName"
        }
    }

    $expectedPlatformTables = @($implicitConsumers.platformTables | Where-Object { $_ -in $tableNames } | Sort-Object)
    $actualPlatformTables = @(
        $classifications |
            Where-Object { $_.PSObject.Properties.Name -contains 'platform' -and $_.platform -eq $true } |
            ForEach-Object tableName |
            Sort-Object
    )
    Assert-Baseline (@(Compare-Object $expectedPlatformTables $actualPlatformTables).Count -eq 0) 'Platform flags must match implicit-consumers.json'
}

$highValueFields = Read-BaselineJson (Join-Path $dataPath 'high-value-fields.json')
if ($null -ne $highValueFields) {
    foreach ($table in $highValueFields.PSObject.Properties) {
        Assert-Baseline (@($table.Value.highValueFields).Count -gt 0) "$($table.Name): highValueFields cannot be empty"
    }
}

$fieldStats = Read-BaselineJson (Join-Path $dataPath 'field-frequency-stats.json')
if ($null -ne $fieldStats) {
    Assert-Baseline ($fieldStats.totalRulesParsed -gt 0) 'Field statistics must include parsed rules'
    Assert-Baseline ($fieldStats.totalTables -gt 0) 'Field statistics must include tables'
    $perTableCount = @($fieldStats.perTable.PSObject.Properties).Count
    Assert-Baseline ($perTableCount -gt 0) 'Field statistics must include per-table entries'
    Assert-Baseline ($perTableCount -le $fieldStats.totalTables) 'Per-table statistics cannot exceed total discovered tables'
}

if ($failures.Count -gt 0) {
    Write-Error ("Baseline validation failed with {0} error(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
    exit 1
}

Write-Host "Baseline validation passed: $checks checks, $($classifications.Count) classifications."