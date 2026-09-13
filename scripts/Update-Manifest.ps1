[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot),
    [datetime]$ImportedOn
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($RootPath)
$dataPath = Join-Path $root 'data'
$manifestPath = Join-Path $dataPath 'manifest.json'
$releaseFiles = @(
    'auxiliary-plan-tables.json',
    'basic-plan-tables.json',
    'custom-classifications-example.json',
    'field-frequency-stats.json',
    'high-value-fields.json',
    'implicit-consumers.json',
    'log-classifications.json',
    'sources.json',
    'taxonomy.json'
)

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
foreach ($fileName in $releaseFiles) {
    $path = Join-Path $dataPath $fileName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required release file is missing: $fileName"
    }

    $content = [System.IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($PSBoundParameters.ContainsKey('ImportedOn')) {
    $manifest.importedOn = $ImportedOn.ToString('yyyy-MM-dd')
}

$files = [ordered]@{}
foreach ($fileName in $releaseFiles) {
    $files[$fileName] = (Get-FileHash -LiteralPath (Join-Path $dataPath $fileName) -Algorithm SHA256).Hash
}
$manifest.files = [pscustomobject]$files

$manifestJson = (($manifest | ConvertTo-Json -Depth 10) + "`n").Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText($manifestPath, $manifestJson, $utf8NoBom)

Write-Host "Updated manifest checksums for $($releaseFiles.Count) files."