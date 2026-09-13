[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dataPath = Join-Path $root 'data'
$schemaPath = Join-Path $root 'schemas'
$manifestPath = Join-Path $dataPath 'manifest.json'

& (Join-Path $PSScriptRoot 'Test-Baseline.ps1')

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$version = [version]$manifest.dataVersion
$artifactName = "log-baseline-$version"
$stagingPath = Join-Path $OutputPath $artifactName
$archivePath = Join-Path $OutputPath "$artifactName.zip"
$checksumPath = "$archivePath.sha256"

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

if (Test-Path -LiteralPath $archivePath) {
    Remove-Item -LiteralPath $archivePath -Force
}

Compress-Archive -Path (Join-Path $stagingPath '*') -DestinationPath $archivePath -CompressionLevel Optimal
$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
Set-Content -LiteralPath $checksumPath -Value "$archiveHash  $([System.IO.Path]::GetFileName($archivePath))" -Encoding utf8
Remove-Item -LiteralPath $stagingPath -Recurse -Force

Write-Host "Created $archivePath"
Write-Host "SHA256 $archiveHash"
