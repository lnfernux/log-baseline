[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AzureSentinelPath,

    [string]$ClassificationsPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'data' 'log-classifications.json'),

    [Parameter(Mandatory)]
    [string]$TableCatalogPath,

    [string]$ExistingHighValueFieldsPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'data' 'high-value-fields.json'),

    [string]$ExistingFieldFrequencyPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'data' 'field-frequency-stats.json'),

    [Parameter(Mandatory)]
    [string]$FieldFrequencyOutputPath,

    [Parameter(Mandatory)]
    [string]$HighValueFieldsOutputPath,

    [Parameter(Mandatory)]
    [string]$SummaryOutputPath,

    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string]$SourceRevision,

    [datetimeoffset]$GeneratedAt,

    [ValidateRange(1, 100)]
    [int]$MinimumRulesPerTable = 3,

    [ValidateRange(1, 100)]
    [int]$MinimumFieldsPerTable = 3,

    [ValidateRange(1, 100)]
    [int]$MaximumFieldsPerTable = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sourceRoot = [System.IO.Path]::GetFullPath($AzureSentinelPath)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$ignoredNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
@(
    'and', 'or', 'not', 'where', 'project', 'project-away', 'project-keep', 'extend',
    'summarize', 'join', 'union', 'let', 'by', 'on', 'kind', 'count', 'distinct',
    'ago', 'datetime', 'timespan', 'dynamic', 'true', 'false', 'null', 'source',
    'isnotempty', 'isempty', 'isnotnull', 'isnull', 'has', 'contains', 'startswith',
    'endswith', 'between', 'in', 'has_any', 'has_all', 'render', 'order', 'sort',
    'take', 'top', 'limit', 'materialize', 'toscalar', 'datatable', 'externaldata'
) | ForEach-Object { [void]$ignoredNames.Add($_) }
$regexTimeout = [timespan]::FromSeconds(2)
$yamlQueryRegex = [regex]::new('^(?<indent>\s*)query\s*:\s*(?<value>.*)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, $regexTimeout)
$letSymbolRegex = [regex]::new('^\s*let\s+([A-Za-z_][A-Za-z0-9_]*)\s*=', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline, $regexTimeout)
$tableRegexes = @(
    [regex]::new('^\s*([A-Z][A-Za-z0-9_]*)\s*(?:\r?\n)?\s*\|', [System.Text.RegularExpressions.RegexOptions]::Multiline, $regexTimeout),
    [regex]::new('^\s*let\s+\w+\s*=\s*([A-Z][A-Za-z0-9_]*)\b(?!\s*\()', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline, $regexTimeout),
    [regex]::new('\bjoin\s+(?:kind\s*=\s*\w+\s+)?\(?\s*([A-Z][A-Za-z0-9_]*)\b(?!\s*\()', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, $regexTimeout),
    [regex]::new('\bunion\s+(?:(?:isfuzzy|withsource|kind)\s*=\s*[^,\s]+[,\s]+)*([A-Z][A-Za-z0-9_]*)\b(?!\s*\()', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, $regexTimeout)
)
$fieldExpressionRegex = [regex]::new('\b([A-Za-z_][A-Za-z0-9_]*)\s*(?:==|!=|<>|<=|>=|<|>|=~|!~|\bin\s*\(|\bhas\b|\bcontains\b|\bstartswith\b|\bendswith\b|\bbetween\b|\bhas_any\b|\bhas_all\b)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, $regexTimeout)
$projectRegex = [regex]::new('\|\s*project(?:-keep|-away)?\s+([^|;]+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline, $regexTimeout)
$byRegex = [regex]::new('\bby\s+([^|;]+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, $regexTimeout)
$nullCheckRegex = [regex]::new('\b(?:isnotempty|isempty|isnotnull|isnull)\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, $regexTimeout)

function Write-JsonFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Value)

    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $json = (($Value | ConvertTo-Json -Depth 30) + "`n").Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function Get-YamlQueries {
    param([Parameter(Mandatory)][string]$Path)

    $lines = [System.IO.File]::ReadAllLines($Path)
    $queries = @()
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $match = $yamlQueryRegex.Match($lines[$lineIndex])
        if (-not $match.Success) { continue }

        $value = $match.Groups['value'].Value.Trim()
        if ($value -match '^[|>]') {
            $baseIndent = $match.Groups['indent'].Value.Length
            $block = @()
            $minimumIndent = [int]::MaxValue
            $cursor = $lineIndex + 1
            while ($cursor -lt $lines.Count) {
                $candidate = $lines[$cursor]
                if ($candidate -notmatch '\S') {
                    $block += ''
                    $cursor++
                    continue
                }

                $indent = $candidate.Length - $candidate.TrimStart().Length
                if ($indent -le $baseIndent) { break }
                $minimumIndent = [Math]::Min($minimumIndent, $indent)
                $block += $candidate
                $cursor++
            }

            if ($block.Count -gt 0) {
                if ($minimumIndent -eq [int]::MaxValue) { $minimumIndent = $baseIndent + 1 }
                $normalized = $block | ForEach-Object {
                    if ($_.Length -ge $minimumIndent) { $_.Substring($minimumIndent) } else { '' }
                }
                $queries += ($normalized -join "`n")
            }
            $lineIndex = $cursor - 1
            continue
        }

        if ($value.Length -gt 1 -and (($value[0] -eq '"' -and $value[-1] -eq '"') -or ($value[0] -eq "'" -and $value[-1] -eq "'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if (-not [string]::IsNullOrWhiteSpace($value)) { $queries += $value }
    }

    return @($queries)
}

function Get-KqlTables {
    param([Parameter(Mandatory)][string]$Kql)

    $tables = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $localSymbols = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($match in $letSymbolRegex.Matches($Kql)) {
        [void]$localSymbols.Add($match.Groups[1].Value)
    }
    foreach ($regex in $tableRegexes) {
        foreach ($match in $regex.Matches($Kql)) {
            $name = $match.Groups[1].Value
            if ($name.Length -gt 2 -and -not $ignoredNames.Contains($name) -and -not $localSymbols.Contains($name)) {
                [void]$tables.Add($name)
            }
        }
    }

    return @($tables | Sort-Object)
}

function Get-KqlFields {
    param([Parameter(Mandatory)][string]$Kql, [string[]]$TableNames)

    $fields = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $expressions = [System.Collections.Generic.List[string]]::new()
    foreach ($match in $fieldExpressionRegex.Matches($Kql)) {
        [void]$expressions.Add($match.Groups[1].Value)
    }
    foreach ($match in $projectRegex.Matches($Kql)) {
        $match.Groups[1].Value -split ',' | ForEach-Object { [void]$expressions.Add((($_.Trim() -split '\s|=')[0])) }
    }
    foreach ($match in $byRegex.Matches($Kql)) {
        $match.Groups[1].Value -split ',' | ForEach-Object { [void]$expressions.Add((($_.Trim() -split '\s|\(')[0])) }
    }
    foreach ($match in $nullCheckRegex.Matches($Kql)) {
        [void]$expressions.Add($match.Groups[1].Value)
    }

    foreach ($name in $expressions) {
        $field = $name.Trim(' ', '(', ')')
        if ($field -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { continue }
        if ($field.Length -le 1 -or $ignoredNames.Contains($field) -or $field -in $TableNames) { continue }
        if ($field -cnotmatch '[A-Z]') { continue }
        if ($field -match 'CustomEntity$|^(TI|ILE)_\w+Entity$|^\d+[smhd]$') { continue }
        [void]$fields.Add($field)
    }

    return @($fields | Sort-Object)
}

if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "Azure-Sentinel path does not exist: $sourceRoot"
}
if (-not (Test-Path -LiteralPath $ClassificationsPath -PathType Leaf)) {
    throw "Classification file does not exist: $ClassificationsPath"
}
if (-not (Test-Path -LiteralPath $TableCatalogPath -PathType Leaf)) {
    throw "Table catalog file does not exist: $TableCatalogPath"
}
if (-not (Test-Path -LiteralPath $ExistingHighValueFieldsPath -PathType Leaf)) {
    throw "Existing high-value field file does not exist: $ExistingHighValueFieldsPath"
}
if (-not (Test-Path -LiteralPath $ExistingFieldFrequencyPath -PathType Leaf)) {
    throw "Existing field-frequency file does not exist: $ExistingFieldFrequencyPath"
}

if (-not $SourceRevision) {
    $SourceRevision = (& git -C $sourceRoot rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or $SourceRevision -notmatch '^[a-fA-F0-9]{40}$') {
        throw 'AzureSentinelPath must be a Git checkout with a committed HEAD, or SourceRevision must be supplied.'
    }
}
$SourceRevision = $SourceRevision.ToLowerInvariant()

if (-not $PSBoundParameters.ContainsKey('GeneratedAt')) {
    $commitDate = (& git -C $sourceRoot show -s --format=%cI $SourceRevision 2>$null)
    [datetimeoffset]$parsedCommitDate = [datetimeoffset]::MinValue
    if ($LASTEXITCODE -ne 0 -or -not [datetimeoffset]::TryParse([string]$commitDate, [ref]$parsedCommitDate)) {
        throw 'GeneratedAt must be supplied when the source commit timestamp cannot be resolved.'
    }
    $GeneratedAt = $parsedCommitDate
}

$contentRoots = @('Detections', 'Hunting Queries', 'Solutions') |
    ForEach-Object { Join-Path $sourceRoot $_ } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Container }
if ($contentRoots.Count -eq 0) {
    throw 'AzureSentinelPath does not contain Detections, Hunting Queries, or Solutions content.'
}

$yamlFiles = @($contentRoots | ForEach-Object {
    [System.IO.Directory]::EnumerateFiles($_, '*.yaml', [System.IO.SearchOption]::AllDirectories)
    [System.IO.Directory]::EnumerateFiles($_, '*.yml', [System.IO.SearchOption]::AllDirectories)
} | Sort-Object -Unique)
if ($yamlFiles.Count -eq 0) { throw 'No YAML content was found in the supported Azure-Sentinel paths.' }

$classifications = @(Get-Content -LiteralPath $ClassificationsPath -Raw | ConvertFrom-Json)
$tableCatalog = Get-Content -LiteralPath $TableCatalogPath -Raw | ConvertFrom-Json
if ($tableCatalog.PSObject.Properties.Name -notcontains 'tables') {
    throw "Table catalog '$TableCatalogPath' does not contain a tables property."
}
$catalogTableNames = @($tableCatalog.tables | ForEach-Object { [string]$_.name } | Where-Object { $_ } | Sort-Object -Unique)
if ($catalogTableNames.Count -eq 0) {
    throw "Table catalog '$TableCatalogPath' contains no table names."
}
$existingHighValue = Get-Content -LiteralPath $ExistingHighValueFieldsPath -Raw | ConvertFrom-Json
$existingFrequency = Get-Content -LiteralPath $ExistingFieldFrequencyPath -Raw | ConvertFrom-Json
$trustedTables = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $classifications) { [void]$trustedTables.Add([string]$entry.tableName) }
foreach ($property in $existingHighValue.PSObject.Properties) { [void]$trustedTables.Add($property.Name) }
foreach ($property in $existingFrequency.perTable.PSObject.Properties) { [void]$trustedTables.Add($property.Name) }
foreach ($tableName in $catalogTableNames) { [void]$trustedTables.Add($tableName) }

$tableStats = @{}
$totalRulesParsed = 0
foreach ($file in $yamlFiles) {
    foreach ($query in @(Get-YamlQueries -Path $file)) {
        $totalRulesParsed++
        $tables = @(Get-KqlTables -Kql $query | Where-Object { $trustedTables.Contains($_) -or $_ -match '_CL$' })
        if ($tables.Count -eq 0) { continue }
        $fields = @(Get-KqlFields -Kql $query -TableNames $tables)
        foreach ($table in $tables) {
            if (-not $tableStats.ContainsKey($table)) {
                $tableStats[$table] = [pscustomobject]@{ RuleCount = 0; Fields = @{} }
            }
            $tableStats[$table].RuleCount++
            foreach ($field in $fields) {
                if (-not $tableStats[$table].Fields.ContainsKey($field)) { $tableStats[$table].Fields[$field] = 0 }
                $tableStats[$table].Fields[$field]++
            }
        }
    }
}
if ($totalRulesParsed -eq 0 -or $tableStats.Count -eq 0) {
    throw 'No query-bearing rules or referenced tables were found.'
}

$categoryByTable = @{}
foreach ($entry in $classifications) { $categoryByTable[$entry.tableName] = $entry.category }

$universalFields = @($tableStats.Values | ForEach-Object { $_.Fields.Keys } | Group-Object | Where-Object Count -gt ($tableStats.Count * 0.5) | Sort-Object Name | ForEach-Object Name)
$categoryDefaults = [ordered]@{}
foreach ($category in @($categoryByTable.Values | Sort-Object -Unique)) {
    $categoryTables = @($tableStats.Keys | Where-Object { $categoryByTable.ContainsKey($_) -and $categoryByTable[$_] -eq $category })
    if ($categoryTables.Count -eq 0) { continue }
    $categoryFields = @($categoryTables | ForEach-Object { $tableStats[$_].Fields.Keys } | Group-Object | Where-Object Count -gt ($categoryTables.Count * 0.4) | Sort-Object Name | ForEach-Object Name)
    if ($categoryFields.Count -gt 0) { $categoryDefaults[$category] = $categoryFields }
}

$perTable = [ordered]@{}
foreach ($tableEntry in @($tableStats.GetEnumerator() | Sort-Object Key)) {
    $table = [string]$tableEntry.Key
    $statistics = $tableEntry.Value
    if ($statistics.RuleCount -lt $MinimumRulesPerTable) { continue }
    $fields = [ordered]@{}
    foreach ($field in @($statistics.Fields.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Key'; Descending = $false })) {
        $fields[$field.Key] = $field.Value
    }
    $perTable[$table] = $fields
}

$frequencyDocument = [ordered]@{
    generatedAt = $GeneratedAt.ToString('o')
    totalRulesParsed = $totalRulesParsed
    totalTables = $tableStats.Count
    universalFields = $universalFields
    categoryDefaults = $categoryDefaults
    perTable = $perTable
}
Write-JsonFile -Path $FieldFrequencyOutputPath -Value $frequencyDocument

$candidateHighValue = [ordered]@{}
foreach ($property in @($existingHighValue.PSObject.Properties | Sort-Object Name)) {
    $candidateHighValue[$property.Name] = [ordered]@{
        description = $property.Value.description
        highValueFields = @($property.Value.highValueFields)
        splitHints = @($property.Value.splitHints)
    }
}

$addedTables = [System.Collections.Generic.List[string]]::new()
foreach ($table in @($perTable.Keys | Sort-Object)) {
    if ($candidateHighValue.Contains($table)) { continue }
    $rankedFields = @($perTable[$table].GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Key'; Descending = $false } | Select-Object -First $MaximumFieldsPerTable | ForEach-Object Key)
    if ($rankedFields.Count -lt $MinimumFieldsPerTable) { continue }
    $category = if ($categoryByTable.ContainsKey($table)) { $categoryByTable[$table] } else { 'Unclassified' }
    $candidateHighValue[$table] = [ordered]@{
        description = "$category - Mined from $($tableStats[$table].RuleCount) public rules"
        highValueFields = $rankedFields
        splitHints = @()
    }
    [void]$addedTables.Add($table)
}

$sortedHighValue = [ordered]@{}
foreach ($table in @($candidateHighValue.Keys | Sort-Object)) { $sortedHighValue[$table] = $candidateHighValue[$table] }
Write-JsonFile -Path $HighValueFieldsOutputPath -Value $sortedHighValue

$summaryParent = Split-Path -Parent $SummaryOutputPath
if ($summaryParent) { New-Item -ItemType Directory -Path $summaryParent -Force | Out-Null }
$summary = @(
    '# Field analysis candidate',
    '',
    "- Azure-Sentinel revision: ``$SourceRevision``",
    "- Generated at: ``$($GeneratedAt.ToString('o'))``",
    "- YAML files scanned: $($yamlFiles.Count)",
    "- Query blocks parsed: $totalRulesParsed",
    "- Catalog tables trusted: $($catalogTableNames.Count)",
    "- Tables discovered: $($tableStats.Count)",
    "- Tables meeting the $MinimumRulesPerTable-rule threshold: $($perTable.Count)",
    "- New high-value candidates: $($addedTables.Count)",
    '',
    '## New high-value candidates',
    ''
)
if ($addedTables.Count -eq 0) {
    $summary += 'None.'
}
else {
    $summary += @($addedTables | Sort-Object | ForEach-Object { "- ``$_`` - $($tableStats[$_].RuleCount) rules" })
}
$summary += @('', '> Candidate fields are frequency-derived. Review descriptions, fields, and split hints before importing canonical data.', '')
[System.IO.File]::WriteAllText($SummaryOutputPath, (($summary -join "`n").Replace("`r`n", "`n")), $utf8NoBom)

if (-not (Test-Json -Path $FieldFrequencyOutputPath -SchemaFile (Join-Path $root 'schemas' 'field-frequency-stats.schema.json'))) {
    throw 'Generated field-frequency output does not match its schema.'
}
if (-not (Test-Json -Path $HighValueFieldsOutputPath -SchemaFile (Join-Path $root 'schemas' 'high-value-fields.schema.json'))) {
    throw 'Generated high-value candidate output does not match its schema.'
}

Write-Host "Analyzed $totalRulesParsed queries across $($tableStats.Count) tables at Azure-Sentinel revision $SourceRevision."
Write-Host "Created $FieldFrequencyOutputPath"
Write-Host "Created $HighValueFieldsOutputPath"
Write-Host "Created $SummaryOutputPath"