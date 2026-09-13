[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts'),

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string]$SourceRevision
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dataPath = Join-Path $root 'data'
$schemaPath = Join-Path $root 'schemas'
$manifestPath = Join-Path $dataPath 'manifest.json'

$headRevision = (& git -C $root rev-parse HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or $headRevision -notmatch '^[a-fA-F0-9]{40}$') {
    throw 'Release artifacts require a Git checkout with a committed HEAD.'
}
if ($headRevision -ne $SourceRevision) {
    throw "SourceRevision $SourceRevision does not match repository HEAD $headRevision."
}
$releaseChanges = @(& git -C $root status --porcelain -- data schemas scripts LICENSE.md)
if ($releaseChanges.Count -gt 0) {
    throw "Release inputs contain uncommitted changes:`n$($releaseChanges -join "`n")"
}

& (Join-Path $PSScriptRoot 'Test-Baseline.ps1')

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$version = [version]$manifest.dataVersion
$artifactName = "log-baseline-$version"
$stagingPath = Join-Path $OutputPath $artifactName
$archivePath = Join-Path $OutputPath "$artifactName.zip"
$checksumPath = "$archivePath.sha256"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

if (Test-Path -LiteralPath $stagingPath) {
    Remove-Item -LiteralPath $stagingPath -Recurse -Force
}

New-Item -ItemType Directory -Path (Join-Path $stagingPath 'data') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingPath 'schemas') -Force | Out-Null

Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $stagingPath 'data')
foreach ($fileProperty in $manifest.files.PSObject.Properties) {
    Copy-Item -LiteralPath (Join-Path $dataPath $fileProperty.Name) -Destination (Join-Path $stagingPath 'data')
}
Copy-Item -Path (Join-Path $schemaPath '*.json') -Destination (Join-Path $stagingPath 'schemas')
Copy-Item -LiteralPath (Join-Path $root 'LICENSE.md') -Destination $stagingPath

$stagedManifestPath = Join-Path $stagingPath 'data' 'manifest.json'
$stagedManifest = Get-Content -LiteralPath $stagedManifestPath -Raw | ConvertFrom-Json
$stagedManifest.source.revision = $SourceRevision.ToLowerInvariant()

$stagedSourcesPath = Join-Path $stagingPath 'data' 'sources.json'
$stagedSources = Get-Content -LiteralPath $stagedSourcesPath -Raw | ConvertFrom-Json
$taxonomySource = @($stagedSources.sources | Where-Object id -eq 'log-baseline-taxonomy')
if ($taxonomySource.Count -ne 1) {
    throw 'Taxonomy provenance record is missing or duplicated.'
}
$taxonomySource[0].revision = $SourceRevision.ToLowerInvariant()
$taxonomySource[0].url = "https://github.com/lnfernux/log-baseline/blob/$($SourceRevision.ToLowerInvariant())/data/taxonomy.json"
$sourcesJson = (($stagedSources | ConvertTo-Json -Depth 20) + "`n").Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText($stagedSourcesPath, $sourcesJson, $utf8NoBom)
$stagedManifest.files.'sources.json' = (Get-FileHash -LiteralPath $stagedSourcesPath -Algorithm SHA256).Hash
$manifestJson = (($stagedManifest | ConvertTo-Json -Depth 20) + "`n").Replace("`r`n", "`n").Replace("`r", "`n")
[System.IO.File]::WriteAllText($stagedManifestPath, $manifestJson, $utf8NoBom)

& (Join-Path $PSScriptRoot 'Test-Baseline.ps1') -RootPath $stagingPath

if (Test-Path -LiteralPath $archivePath) {
    Remove-Item -LiteralPath $archivePath -Force
}

Add-Type -AssemblyName System.IO.Compression
$archive = [System.IO.Compression.ZipFile]::Open($archivePath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $files = @(Get-ChildItem -LiteralPath $stagingPath -File -Recurse | Sort-Object FullName)
    foreach ($file in $files) {
        $relativePath = [System.IO.Path]::GetRelativePath($stagingPath, $file.FullName).Replace('\', '/')
        $entry = $archive.CreateEntry($relativePath, [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [datetimeoffset]::new(2000, 1, 1, 0, 0, 0, [timespan]::Zero)
        $entryStream = $entry.Open()
        $fileStream = $file.OpenRead()
        try {
            $fileStream.CopyTo($entryStream)
        }
        finally {
            $fileStream.Dispose()
            $entryStream.Dispose()
        }
    }
}
finally {
    $archive.Dispose()
}

$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
[System.IO.File]::WriteAllText($checksumPath, "$archiveHash  $([System.IO.Path]::GetFileName($archivePath))`n", $utf8NoBom)
Remove-Item -LiteralPath $stagingPath -Recurse -Force

Write-Host "Created $archivePath"
Write-Host "SHA256 $archiveHash"
