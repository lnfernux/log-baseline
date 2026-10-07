[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AzureSentinelPath,

    [string]$ClassificationsPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'data' 'log-classifications.json'),

    [Parameter(Mandatory)]
    [string]$TableCatalogPath,

    [string]$ExistingHighValueFieldsPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'data' 'high-value-fields.json'),

    # Log Analytics metadata API document (tables[].name, tables[].columns[].name) used to keep only real columns.
    [string]$TableSchemaPath,

    # Tables whose columns vary by source, so the metadata column list is incomplete.
    [string[]]$DynamicSchemaTables = @('AzureDiagnostics'),

    # Writes review candidates for sources inside shared tables (vendor or process filters).
    [string]$SharedSourceCandidatesOutputPath,

    [string[]]$SharedTables = @('CommonSecurityLog', 'Syslog'),

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
$functionQueryRegex = [regex]::new('^(?<indent>\s*)FunctionQuery\s*:\s*(?<value>.*)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, $regexTimeout)
$functionAliasRegex = [regex]::new('^\s*FunctionAlias\s*:\s*[''"]?([A-Za-z_][A-Za-z0-9_]*)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline, $regexTimeout)
$functionCallRegex = [regex]::new('(?<![\w.$])([A-Za-z_][A-Za-z0-9_]*)\s*\(', [System.Text.RegularExpressions.RegexOptions]::None, $regexTimeout)
$sourcePredicateRegex = [regex]::new('\b(DeviceVendor|DeviceProduct|ProcessName|Facility)\s*(==|=~|in~|in|has_any|has|contains|startswith)\s*(\((?:[^()]|\([^()]*\))*\)|"[^"]*"|''[^'']*''|```[^`]*```)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, $regexTimeout)
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
    param([Parameter(Mandatory)][string]$Path, [regex]$KeyRegex = $yamlQueryRegex)

    $lines = [System.IO.File]::ReadAllLines($Path)
    $queries = @()
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $match = $KeyRegex.Match($lines[$lineIndex])
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

function New-NameSet {
    param([string[]]$Names)
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($Names)) { if ($name) { [void]$set.Add($name) } }
    return , $set
}

function Get-ParserOutputColumns {
    param([Parameter(Mandatory)][string]$Alias)

    # Azure-Sentinel registers parser output schemas for KQL validation, either as functions or as pseudo-tables.
    $validationRoot = Join-Path $sourceRoot '.script' 'tests' 'KqlvalidationsTests'
    $functionPath = Join-Path $validationRoot 'CustomFunctions' "$Alias.json"
    if (Test-Path -LiteralPath $functionPath -PathType Leaf) {
        $definition = Get-Content -LiteralPath $functionPath -Raw | ConvertFrom-Json
        if ($definition.PSObject.Properties.Name -contains 'FunctionResultColumns') { return , (New-NameSet @($definition.FunctionResultColumns.Name)) }
    }
    $tablePath = Join-Path $validationRoot 'CustomTables' "$Alias.json"
    if (Test-Path -LiteralPath $tablePath -PathType Leaf) {
        $definition = Get-Content -LiteralPath $tablePath -Raw | ConvertFrom-Json
        if ($definition.PSObject.Properties.Name -contains 'Properties') { return , (New-NameSet @($definition.Properties.Name)) }
    }
    return $null
}

function Select-KnownColumns {
    param([string[]]$Fields, $Columns)
    if ($null -eq $Columns -or $Columns.Count -eq 0) { return @($Fields) }
    # Return the schema's spelling so casing does not depend on which rule is read first.
    $known = foreach ($field in $Fields) {
        $actual = $null
        if ($Columns.TryGetValue($field, [ref]$actual)) { $actual }
    }
    return @($known)
}

function Select-CommonFields {
    param([string[]]$Tables, [double]$Share)
    $names = @($Tables | Sort-Object | ForEach-Object { $tableStats[$_].Fields.Keys })
    $common = foreach ($group in @($names | Group-Object { $_.ToLowerInvariant() } | Where-Object Count -gt ($Tables.Count * $Share))) {
        # Most frequent spelling wins, then ordinal order, so output does not depend on hash order.
        @($group.Group | Group-Object -CaseSensitive | Sort-Object @{ Expression = 'Count'; Descending = $true }, @{ Expression = { $_.Name }; Descending = $false } -CaseSensitive)[0].Name
    }
    return @($common | Sort-Object)
}

function Add-FieldCounts {
    param([Parameter(Mandatory)][hashtable]$Stats, [Parameter(Mandatory)][string]$Name, [string[]]$Fields)
    if (-not $Stats.ContainsKey($Name)) { $Stats[$Name] = [pscustomobject]@{ RuleCount = 0; Fields = @{} } }
    $Stats[$Name].RuleCount++
    foreach ($field in @($Fields | Where-Object { $_ })) {
        if (-not $Stats[$Name].Fields.ContainsKey($field)) { $Stats[$Name].Fields[$field] = 0 }
        $Stats[$Name].Fields[$field]++
    }
}

function ConvertTo-RankedFields {
    param([Parameter(Mandatory)][hashtable]$Fields)
    $ranked = [ordered]@{}
    foreach ($field in @($Fields.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Key'; Descending = $false })) {
        $ranked[$field.Key] = $field.Value
    }
    return $ranked
}

function Get-SourceFilter {
    param([Parameter(Mandatory)][string]$Kql)

    # First predicate per source field, joined into one filter that identifies the source's rows.
    $parts = [ordered]@{}
    foreach ($match in $sourcePredicateRegex.Matches($Kql)) {
        $field = $match.Groups[1].Value
        if ($parts.Contains($field)) { continue }
        $value = $match.Groups[3].Value
        if ($value.StartsWith('```')) { $value = '"' + $value.Trim('`') + '"' }
        elseif ($value.StartsWith("'")) { $value = '"' + $value.Trim("'") + '"' }
        $parts[$field] = "$field $($match.Groups[2].Value) $value"
    }
    if ($parts.Count -eq 0) { return $null }
    return (@($parts.Values) -join ' and ')
}

function Add-SharedSource {
    param([hashtable]$Candidates, [string]$Table, [string]$Filter, [string]$Parser, [int]$ParserRules, [int]$DirectRules)
    $key = "$Table|$($Filter.ToLowerInvariant())"
    if (-not $Candidates.ContainsKey($key)) {
        $Candidates[$key] = [pscustomobject]@{ Table = $Table; Filter = $Filter; Parsers = (New-NameSet @()); ParserRules = 0; DirectRules = 0 }
    }
    if ($Parser) { [void]$Candidates[$key].Parsers.Add($Parser) }
    $Candidates[$key].ParserRules += $ParserRules
    $Candidates[$key].DirectRules += $DirectRules
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
if ($TableSchemaPath -and -not (Test-Path -LiteralPath $TableSchemaPath -PathType Leaf)) {
    throw "Table schema file does not exist: $TableSchemaPath"
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

$tableSchemas = @{}
if ($TableSchemaPath) {
    $schemaDocument = Get-Content -LiteralPath $TableSchemaPath -Raw | ConvertFrom-Json
    foreach ($schemaTable in @($schemaDocument.tables)) {
        if ($schemaTable.PSObject.Properties.Name -notcontains 'columns' -or [string]$schemaTable.name -in $DynamicSchemaTables) { continue }
        $columns = @($schemaTable.columns | ForEach-Object { [string]$_.name } | Where-Object { $_ })
        if ($columns.Count -gt 0) { $tableSchemas[[string]$schemaTable.name] = New-NameSet $columns }
    }
}

# Parsers: FunctionAlias definitions under Parsers folders. Rules that call a parser are attributed to the parser.
$parserFiles = @(@('Parsers', 'Solutions') | ForEach-Object { Join-Path $sourceRoot $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | ForEach-Object {
    [System.IO.Directory]::EnumerateFiles($_, '*.yaml', [System.IO.SearchOption]::AllDirectories)
    [System.IO.Directory]::EnumerateFiles($_, '*.yml', [System.IO.SearchOption]::AllDirectories)
} | Where-Object { $_ -match '[\\/]Parsers[\\/]' } | Sort-Object -Unique)
$parserQueries = @{}
foreach ($file in $parserFiles) {
    $aliasMatch = $functionAliasRegex.Match([System.IO.File]::ReadAllText($file))
    if (-not $aliasMatch.Success) { continue }
    $alias = $aliasMatch.Groups[1].Value
    if ($catalogTableNames -contains $alias -or $alias -match '_CL$') { continue }
    $functionQuery = @(Get-YamlQueries -Path $file -KeyRegex $functionQueryRegex) -join "`n"
    if (-not $parserQueries.ContainsKey($alias)) { $parserQueries[$alias] = $functionQuery }
}
$parserAliases = New-NameSet @($parserQueries.Keys)

$trustedTables = New-NameSet (@($classifications | ForEach-Object { [string]$_.tableName }) + $catalogTableNames)
$classifiedParsers = @($classifications | ForEach-Object { [string]$_.tableName } | Where-Object { $parserAliases.Contains($_) } | Sort-Object -Unique)
foreach ($alias in $classifiedParsers) { [void]$trustedTables.Remove($alias) }

function Test-IsTable {
    param([string]$Name)
    return (-not $parserAliases.Contains($Name)) -and ($trustedTables.Contains($Name) -or $Name -match '_CL$')
}

$parserInfo = @{}
foreach ($alias in $parserQueries.Keys) {
    $sourceTables = @(Get-KqlTables -Kql $parserQueries[$alias] | Where-Object { Test-IsTable $_ })
    $sourceColumns = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    $knownSources = @($sourceTables | Where-Object { $tableSchemas.ContainsKey($_) })
    if ($knownSources.Count -gt 0) {
        foreach ($field in @(Get-KqlFields -Kql $parserQueries[$alias] -TableNames $sourceTables)) {
            if (@($knownSources | Where-Object { $tableSchemas[$_].Contains($field) }).Count -gt 0) { [void]$sourceColumns.Add($field) }
        }
    }
    $parserInfo[$alias] = [pscustomobject]@{ Tables = $sourceTables; SourceColumns = @($sourceColumns); OutputColumns = (Get-ParserOutputColumns -Alias $alias) }
}

$tableStats = @{}
$parserStats = @{}
$sharedSources = @{}
$sharedTableSet = New-NameSet $SharedTables
$totalRulesParsed = 0
foreach ($file in $yamlFiles) {
    foreach ($query in @(Get-YamlQueries -Path $file)) {
        $totalRulesParsed++
        $referenced = @(Get-KqlTables -Kql $query)
        $tables = @($referenced | Where-Object { Test-IsTable $_ })
        $localSymbols = New-NameSet @($letSymbolRegex.Matches($query) | ForEach-Object { $_.Groups[1].Value })
        $parsers = @(@($referenced) + @($functionCallRegex.Matches($query) | ForEach-Object { $_.Groups[1].Value }) |
            Where-Object { $parserAliases.Contains($_) -and -not $localSymbols.Contains($_) } | Sort-Object -Unique)
        if ($tables.Count -eq 0 -and $parsers.Count -eq 0) { continue }
        $fields = @(Get-KqlFields -Kql $query -TableNames @($tables + $parsers))
        foreach ($table in $tables) {
            # Assign directly: an if-expression would enumerate the set into a case-sensitive array.
            $schema = $null
            if ($tableSchemas.ContainsKey($table)) { $schema = $tableSchemas[$table] }
            Add-FieldCounts -Stats $tableStats -Name $table -Fields (Select-KnownColumns -Fields $fields -Columns $schema)
        }
        foreach ($parser in $parsers) {
            Add-FieldCounts -Stats $parserStats -Name $parser -Fields (Select-KnownColumns -Fields $fields -Columns $parserInfo[$parser].OutputColumns)
        }
        $directShared = @($tables | Where-Object { $sharedTableSet.Contains($_) })
        if ($directShared.Count -gt 0) {
            $filter = Get-SourceFilter -Kql $query
            if ($filter) { foreach ($table in $directShared) { Add-SharedSource -Candidates $sharedSources -Table $table -Filter $filter -DirectRules 1 } }
        }
    }
}
foreach ($alias in $parserQueries.Keys) {
    $sharedSourceTables = @($parserInfo[$alias].Tables | Where-Object { $sharedTableSet.Contains($_) })
    if ($sharedSourceTables.Count -eq 0) { continue }
    $filter = Get-SourceFilter -Kql $parserQueries[$alias]
    if (-not $filter) { continue }
    $parserRules = if ($parserStats.ContainsKey($alias)) { $parserStats[$alias].RuleCount } else { 0 }
    foreach ($table in $sharedSourceTables) { Add-SharedSource -Candidates $sharedSources -Table $table -Filter $filter -Parser $alias -ParserRules $parserRules }
}
if ($totalRulesParsed -eq 0 -or $tableStats.Count -eq 0) {
    throw 'No query-bearing rules or referenced tables were found.'
}

$categoryByTable = @{}
foreach ($entry in $classifications) { $categoryByTable[$entry.tableName] = $entry.category }

$universalFields = @(Select-CommonFields -Tables @($tableStats.Keys) -Share 0.5)
$categoryDefaults = [ordered]@{}
foreach ($category in @($categoryByTable.Values | Sort-Object -Unique)) {
    $categoryTables = @($tableStats.Keys | Where-Object { $categoryByTable.ContainsKey($_) -and $categoryByTable[$_] -eq $category })
    if ($categoryTables.Count -eq 0) { continue }
    $categoryFields = @(Select-CommonFields -Tables $categoryTables -Share 0.4)
    if ($categoryFields.Count -gt 0) { $categoryDefaults[$category] = $categoryFields }
}

$perTable = [ordered]@{}
foreach ($tableEntry in @($tableStats.GetEnumerator() | Sort-Object Key)) {
    if ($tableEntry.Value.RuleCount -lt $MinimumRulesPerTable) { continue }
    $perTable[[string]$tableEntry.Key] = ConvertTo-RankedFields -Fields $tableEntry.Value.Fields
}
$unverifiedTables = @($perTable.Keys | Where-Object { -not $tableSchemas.ContainsKey($_) } | Sort-Object)

$parsers = [ordered]@{}
foreach ($parserEntry in @($parserStats.GetEnumerator() | Sort-Object Key)) {
    $info = $parserInfo[[string]$parserEntry.Key]
    $parsers[[string]$parserEntry.Key] = [ordered]@{
        tables = @($info.Tables)
        ruleCount = $parserEntry.Value.RuleCount
        outputColumnsVerified = $null -ne $info.OutputColumns
        sourceColumns = @($info.SourceColumns)
        fields = ConvertTo-RankedFields -Fields $parserEntry.Value.Fields
    }
}

$frequencyDocument = [ordered]@{
    generatedAt = $GeneratedAt.ToString('o')
    totalRulesParsed = $totalRulesParsed
    totalTables = $tableStats.Count
    universalFields = $universalFields
    categoryDefaults = $categoryDefaults
    perTable = $perTable
    unverifiedTables = $unverifiedTables
    parsers = $parsers
}
Write-JsonFile -Path $FieldFrequencyOutputPath -Value $frequencyDocument

if ($SharedSourceCandidatesOutputPath) {
    $sharedCandidates = @($sharedSources.Values | Sort-Object Table, Filter | ForEach-Object {
        [ordered]@{
            table = $_.Table
            filter = $_.Filter
            parsers = @($_.Parsers | Sort-Object)
            parserRuleCount = $_.ParserRules
            directRuleCount = $_.DirectRules
        }
    })
    Write-JsonFile -Path $SharedSourceCandidatesOutputPath -Value ([ordered]@{ sourceRevision = $SourceRevision; sharedTables = @($SharedTables); candidates = $sharedCandidates })
}

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
    $verification = if ($tableSchemas.ContainsKey($table)) { '' } else { ', fields not schema-verified' }
    $candidateHighValue[$table] = [ordered]@{
        description = "$category - Mined from $($tableStats[$table].RuleCount) public rules$verification"
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
    "- Table schemas loaded: $($tableSchemas.Count)",
    "- Tables discovered: $($tableStats.Count)",
    "- Tables meeting the $MinimumRulesPerTable-rule threshold: $($perTable.Count) ($($unverifiedTables.Count) without a known schema)",
    "- Parsers defined: $($parserQueries.Count), called by rules: $($parsers.Count)",
    "- Shared-table source candidates: $($sharedSources.Count)",
    "- New high-value candidates: $($addedTables.Count)",
    ''
)
if ($classifiedParsers.Count -gt 0) {
    $summary += @('## Classified names that are parsers', '', 'These are parser aliases, not tables. Their rules are attributed to the parser and its source tables.', '')
    $summary += @($classifiedParsers | ForEach-Object { "- ``$_`` -> " + ((@($parserInfo[$_].Tables) | ForEach-Object { "``$_``" }) -join ', ') })
    $summary += ''
}
$summary += @(
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