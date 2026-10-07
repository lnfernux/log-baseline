[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($RootPath)
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
    'shared-table-sources.json' = 'shared-table-sources.schema.json'
    'sources.json' = 'sources.schema.json'
    'manifest.json' = 'manifest.schema.json'
}

foreach ($mapping in $schemaMappings.GetEnumerator()) {
    Test-Schema -DataFile $mapping.Key -SchemaFile $mapping.Value
}

$manifestFileNames = @()
$manifest = Read-BaselineJson (Join-Path $dataPath 'manifest.json')
if ($null -ne $manifest) {
    $requiredReleaseFiles = @(
        'auxiliary-plan-tables.json',
        'basic-plan-tables.json',
        'custom-classifications-example.json',
        'field-frequency-stats.json',
        'high-value-fields.json',
        'implicit-consumers.json',
        'log-classifications.json',
        'shared-table-sources.json',
        'sources.json',
        'taxonomy.json'
    )
    $manifestFileNames = @($manifest.files.PSObject.Properties.Name | Sort-Object)
    Assert-Baseline (@(Compare-Object $requiredReleaseFiles $manifestFileNames).Count -eq 0) 'Manifest must list exactly the required release data files'
    $actualDataFiles = @(Get-ChildItem -LiteralPath $dataPath -File -Filter '*.json' | ForEach-Object Name | Where-Object { $_ -ne 'manifest.json' } | Sort-Object)
    Assert-Baseline (@(Compare-Object $manifestFileNames $actualDataFiles).Count -eq 0) 'Every data JSON file must be listed in the manifest'

    foreach ($fileProperty in $manifest.files.PSObject.Properties) {
        $isSafeFileName = $fileProperty.Name -match '^[A-Za-z0-9][A-Za-z0-9.-]*\.json$' -and
            [System.IO.Path]::GetFileName($fileProperty.Name) -eq $fileProperty.Name
        Assert-Baseline $isSafeFileName "Manifest contains an unsafe file name: $($fileProperty.Name)"
        if (-not $isSafeFileName) { continue }

        $file = Join-Path $dataPath $fileProperty.Name
        Assert-Baseline (Test-Path -LiteralPath $file -PathType Leaf) "Manifest file is missing: $($fileProperty.Name)"
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            $actualHash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
            Assert-Baseline ($actualHash -eq $fileProperty.Value) "Checksum mismatch: $($fileProperty.Name)"
        }
    }
}

$sourcesDocument = Read-BaselineJson (Join-Path $dataPath 'sources.json')
$sourceIds = @()
if ($null -ne $sourcesDocument) {
    $sourceIds = @($sourcesDocument.sources.id)
    Assert-Baseline (@($sourceIds | Sort-Object -Unique).Count -eq $sourceIds.Count) 'Source IDs must be unique'
    foreach ($source in $sourcesDocument.sources) {
        foreach ($appliesTo in @($source.appliesTo)) {
            Assert-Baseline ($appliesTo -in $manifestFileNames) "$($source.id): source references an unknown release file $appliesTo"
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

$baselinePath = Join-Path $root 'baselines'
$previousBaselineNames = @()
foreach ($baselineProperty in $manifest.baselines.PSObject.Properties) {
    $file = Join-Path $baselinePath $baselineProperty.Name
    Assert-Baseline (Test-Path -LiteralPath $file -PathType Leaf) "Pre-made baseline is missing: $($baselineProperty.Name)"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
    Assert-Baseline ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -eq $baselineProperty.Value) "Checksum mismatch: baselines/$($baselineProperty.Name)"
    try {
        Assert-Baseline (Test-Json -Path $file -SchemaFile (Join-Path $schemaPath 'log-classifications.schema.json') -ErrorAction Stop) "$($baselineProperty.Name) does not match the classification schema"
        $baselineRecords = @(Get-Content -LiteralPath $file -Raw | ConvertFrom-Json)
        $baselineNames = @($baselineRecords.tableName)
        Assert-Baseline (@($baselineNames | Where-Object { $_ -notin $tableNames }).Count -eq 0) "$($baselineProperty.Name) references unknown tables"
        Assert-Baseline (@($previousBaselineNames | Where-Object { $_ -notin $baselineNames }).Count -eq 0) "$($baselineProperty.Name) is not cumulative"
        $previousBaselineNames = $baselineNames
    }
    catch {
        $script:failures.Add("Pre-made baseline validation failed for $($baselineProperty.Name): $($_.Exception.Message)")
    }
}

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

$auxiliaryPlan = Read-BaselineJson (Join-Path $dataPath 'auxiliary-plan-tables.json')
$lakeTables = [System.Collections.Generic.HashSet[string]]::new([string[]]@($auxiliaryPlan.tables), [System.StringComparer]::Ordinal)

foreach ($entry in $classifications) {
    Assert-Baseline ($entry.classification -in @('primary', 'secondary')) "$($entry.tableName): invalid classification"
    Assert-Baseline ($entry.category -in $allowedCategories) "$($entry.tableName): invalid category"
    Assert-Baseline ($entry.recommendedTier -in @('analytics', 'datalake')) "$($entry.tableName): invalid recommended tier"
    if ($entry.recommendedTier -eq 'datalake' -and $entry.tableName -notlike '*_CL') {
        Assert-Baseline $lakeTables.Contains([string]$entry.tableName) "$($entry.tableName): datalake recommended but the table has no Auxiliary/Lake support"
    }
    Assert-Baseline (@('volumeClass', 'volumeDriver' | Where-Object { $entry.PSObject.Properties.Name -notcontains $_ }).Count -eq 0) "$($entry.tableName): volumeClass and volumeDriver are required"
    $hasRules = @('valueRule', 'tierRule' | Where-Object { $entry.PSObject.Properties.Name -notcontains $_ }).Count -eq 0
    Assert-Baseline $hasRules "$($entry.tableName): valueRule and tierRule are required"
    if ($hasRules) {
        Assert-Baseline (($entry.valueRule -eq 'C9') -eq ($entry.classification -eq 'secondary')) "$($entry.tableName): valueRule $($entry.valueRule) does not match classification $($entry.classification)"
        $expectedTier = if ($entry.tierRule -in 'T3', 'T4') { 'datalake' } else { 'analytics' }
        Assert-Baseline ($expectedTier -eq $entry.recommendedTier) "$($entry.tableName): tierRule $($entry.tierRule) does not match recommendedTier $($entry.recommendedTier)"
        Assert-Baseline (-not ($entry.valueRule -eq 'C9' -and $entry.tierRule -in 'T1', 'T3')) "$($entry.tableName): secondary tables cannot use $($entry.tierRule)"
        if ($entry.tierRule -eq 'T5') {
            Assert-Baseline ($entry.tableName -notlike '*_CL' -and -not $lakeTables.Contains([string]$entry.tableName)) "$($entry.tableName): T5 requires a built-in table without Auxiliary/Lake support"
        }
    }
    Assert-Baseline ($entry.recommendedRetentionDays -in @(90, 180, 365)) "$($entry.tableName): invalid retention"
    foreach ($sourceId in @($entry.sourceIds)) {
        Assert-Baseline ($sourceId -in $sourceIds) "$($entry.tableName): unknown source ID $sourceId"
    }

    $hasStatus = $entry.PSObject.Properties.Name -contains 'status'
    $hasReplacement = $entry.PSObject.Properties.Name -contains 'replacedBy'
    Assert-Baseline ($hasStatus -eq $hasReplacement) "$($entry.tableName): status and replacedBy must appear together"
    if ($hasStatus) {
        Assert-Baseline ($entry.status -in @('deprecated', 'legacy')) "$($entry.tableName): invalid lifecycle status"
        foreach ($replacement in @($entry.replacedBy)) {
            Assert-Baseline ($replacement -in $tableNames) "$($entry.tableName): missing replacement table $replacement"
        }
    }
    if ($entry.PSObject.Properties.Name -contains 'logAnalyticsTable') {
        Assert-Baseline ($entry.logAnalyticsTable -eq $false) "$($entry.tableName): set logAnalyticsTable only to false"
        Assert-Baseline ($entry.PSObject.Properties.Name -contains 'defenderNative' -and $entry.defenderNative) "$($entry.tableName): a table without a Log Analytics table must be defenderNative"
        Assert-Baseline (-not ($entry.PSObject.Properties.Name -contains 'xdrStreamable' -and $entry.xdrStreamable)) "$($entry.tableName): a table without a Log Analytics table cannot stream to Sentinel"
        Assert-Baseline (-not $lakeTables.Contains([string]$entry.tableName) -and $entry.tableName -notlike '*_CL') "$($entry.tableName): a table without a Log Analytics table cannot have plan support"
    }
}

$sharedSources = @(Read-BaselineJson (Join-Path $dataPath 'shared-table-sources.json'))
# Transformations reject in~, has_any, has_all, hasprefix, and hassuffix.
$unsupportedTransformKql = '(?i)in~|\bhas_(any|all)\b|\bhas(prefix|suffix)'

function Test-TopLevelOr {
    param([string]$Kql)
    # Consumers combine filters with and/or, so a bare top-level `or` changes meaning.
    $depth = 0
    $tokens = [regex]::Replace($Kql, '"(?:[^"\\]|\\.)*"', '""') -split '(\(|\)|\bor\b)'
    foreach ($token in $tokens) {
        if ($token -eq '(') { $depth++ }
        elseif ($token -eq ')') { $depth-- }
        elseif ($token -eq 'or' -and $depth -eq 0) { return $true }
    }
    return $false
}
$sharedSourceIds = @($sharedSources | ForEach-Object { $_.sourceId })
Assert-Baseline (@($sharedSourceIds | Sort-Object -Unique).Count -eq $sharedSourceIds.Count) 'Shared-table source IDs must be unique'
foreach ($entry in $sharedSources) {
    $label = "shared source $($entry.sourceId)"
    Assert-Baseline ($entry.table -cin $tableNames) "${label}: unknown shared table $($entry.table)"
    Assert-Baseline (($entry.valueRule -eq 'C9') -eq ($entry.classification -eq 'secondary')) "${label}: valueRule $($entry.valueRule) does not match classification $($entry.classification)"
    $expectedTier = if ($entry.tierRule -in 'T3', 'T4') { 'datalake' } else { 'analytics' }
    Assert-Baseline ($expectedTier -eq $entry.recommendedTier) "${label}: tierRule $($entry.tierRule) does not match recommendedTier $($entry.recommendedTier)"
    Assert-Baseline (-not ($entry.valueRule -eq 'C9' -and $entry.tierRule -in 'T1', 'T3')) "${label}: secondary sources cannot use $($entry.tierRule)"
    $tableSupportsLake = $entry.table -like '*_CL' -or $lakeTables.Contains([string]$entry.table)
    if ($entry.recommendedTier -eq 'datalake') { Assert-Baseline $tableSupportsLake "${label}: datalake recommended but $($entry.table) has no Auxiliary/Lake support" }
    if ($entry.tierRule -eq 'T5') { Assert-Baseline (-not $tableSupportsLake) "${label}: T5 requires a shared table without Auxiliary/Lake support" }
    $splitHintKql = @(if ($entry.PSObject.Properties['splitHints']) { @($entry.splitHints) | ForEach-Object { $_.kql } })
    if ($splitHintKql.Count -gt 0) { Assert-Baseline ($entry.recommendedTier -eq 'datalake') "${label}: split hints keep rows in Analytics and need a datalake recommendation" }
    foreach ($kql in @($entry.filter) + $splitHintKql) {
        Assert-Baseline ($kql -notmatch $unsupportedTransformKql) "${label}: KQL uses an operator that transformations do not support: $kql"
        Assert-Baseline (-not (Test-TopLevelOr $kql)) "${label}: wrap KQL with a top-level or in parentheses: $kql"
    }
    foreach ($sourceId in @($entry.sourceIds)) {
        Assert-Baseline ($sourceId -in $sourceIds) "${label}: unknown source ID $sourceId"
    }
}

$customClassifications = @(Read-BaselineJson (Join-Path $dataPath 'custom-classifications-example.json'))
foreach ($entry in $customClassifications) {
    Assert-Baseline ($entry.category -in $allowedCategories) "$($entry.tableName): invalid custom example category"
    foreach ($sourceId in @($entry.sourceIds)) {
        Assert-Baseline ($sourceId -in $sourceIds) "$($entry.tableName): unknown custom example source ID $sourceId"
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
        foreach ($hint in @($table.Value.splitHints)) {
            Assert-Baseline ($hint.kql -notmatch $unsupportedTransformKql) "$($table.Name): split hint uses an operator that transformations do not support"
        }
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