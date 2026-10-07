[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
$failures = [System.Collections.Generic.List[string]]::new()
$checks = 0

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    $script:checks++
    if (-not $Condition) { $script:failures.Add($Message) }
}

function Invoke-Validation {
    param([string]$FixtureRoot)

    $outputPath = [System.IO.Path]::GetTempFileName()
    $errorPath = [System.IO.Path]::GetTempFileName()
    $arguments = @(
        '-NoProfile',
        '-File', (Join-Path $root 'scripts' 'Test-Baseline.ps1'),
        '-RootPath', $FixtureRoot
    )
    try {
        $process = Start-Process -FilePath $pwshPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath
        $output = ((Get-Content -LiteralPath $outputPath -Raw -ErrorAction SilentlyContinue) + (Get-Content -LiteralPath $errorPath -Raw -ErrorAction SilentlyContinue))
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output }
    }
    finally {
        Remove-Item -LiteralPath $outputPath, $errorPath -Force -ErrorAction SilentlyContinue
    }
}

function New-Fixture {
    $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) "log-baseline-test-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'baselines') -Destination $fixtureRoot -Recurse
    Copy-Item -LiteralPath (Join-Path $root 'data') -Destination $fixtureRoot -Recurse
    Copy-Item -LiteralPath (Join-Path $root 'schemas') -Destination $fixtureRoot -Recurse
    return $fixtureRoot
}

function Write-FixtureJson {
    param([string]$Path, [object]$Value)
    $json = (($Value | ConvertTo-Json -Depth 30) + "`n").Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

$temporaryPaths = [System.Collections.Generic.List[string]]::new()
try {
    $valid = Invoke-Validation -FixtureRoot $root
    Assert-Test ($valid.ExitCode -eq 0) "Valid baseline failed validation: $($valid.Output)"

    $fixture = New-Fixture
    $temporaryPaths.Add($fixture)
    $examplesPath = Join-Path $fixture 'data' 'custom-classifications-example.json'
    $examples = @(Get-Content -LiteralPath $examplesPath -Raw | ConvertFrom-Json)
    $examples[0].category = 'Invalid category'
    Write-FixtureJson -Path $examplesPath -Value $examples
    & (Join-Path $root 'scripts' 'Update-Manifest.ps1') -RootPath $fixture | Out-Null
    $invalidCategory = Invoke-Validation -FixtureRoot $fixture
    Assert-Test ($invalidCategory.ExitCode -ne 0) 'Invalid custom example category was accepted'

    $fixture = New-Fixture
    $temporaryPaths.Add($fixture)
    $manifestPath = Join-Path $fixture 'data' 'manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.files.PSObject.Properties.Remove('sources.json')
    Write-FixtureJson -Path $manifestPath -Value $manifest
    $missingManifestEntry = Invoke-Validation -FixtureRoot $fixture
    Assert-Test ($missingManifestEntry.ExitCode -ne 0) 'Missing required manifest entry was accepted'

    $fixture = New-Fixture
    $temporaryPaths.Add($fixture)
    $manifestPath = Join-Path $fixture 'data' 'manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.files | Add-Member -NotePropertyName '../outside.json' -NotePropertyValue ('0' * 64)
    Write-FixtureJson -Path $manifestPath -Value $manifest
    $unsafeManifestName = Invoke-Validation -FixtureRoot $fixture
    Assert-Test ($unsafeManifestName.ExitCode -ne 0) 'Unsafe manifest file name was accepted'

    $fixture = New-Fixture
    $temporaryPaths.Add($fixture)
    $classificationsPath = Join-Path $fixture 'data' 'log-classifications.json'
    $classifications = @(Get-Content -LiteralPath $classificationsPath -Raw | ConvertFrom-Json)
    $classifications[0].sourceIds = @('unknown-source')
    Write-FixtureJson -Path $classificationsPath -Value $classifications
    & (Join-Path $root 'scripts' 'Update-Manifest.ps1') -RootPath $fixture | Out-Null
    $unknownSource = Invoke-Validation -FixtureRoot $fixture
    Assert-Test ($unknownSource.ExitCode -ne 0) 'Unknown classification source ID was accepted'

    $fixture = New-Fixture
    $temporaryPaths.Add($fixture)
    $classificationsPath = Join-Path $fixture 'data' 'log-classifications.json'
    $classifications = @(Get-Content -LiteralPath $classificationsPath -Raw | ConvertFrom-Json)
    @($classifications | Where-Object tableName -eq 'Perf')[0].recommendedTier = 'datalake'
    Write-FixtureJson -Path $classificationsPath -Value $classifications
    & (Join-Path $root 'scripts' 'Update-Manifest.ps1') -RootPath $fixture | Out-Null
    $unsupportedLake = Invoke-Validation -FixtureRoot $fixture
    Assert-Test ($unsupportedLake.ExitCode -ne 0) 'Datalake recommendation without Auxiliary/Lake support was accepted'

    $fixture = New-Fixture
    $temporaryPaths.Add($fixture)
    $classificationsPath = Join-Path $fixture 'data' 'log-classifications.json'
    $classifications = @(Get-Content -LiteralPath $classificationsPath -Raw | ConvertFrom-Json)
    $classifications[0].PSObject.Properties.Remove('volumeClass')
    Write-FixtureJson -Path $classificationsPath -Value $classifications
    & (Join-Path $root 'scripts' 'Update-Manifest.ps1') -RootPath $fixture | Out-Null
    $missingVolume = Invoke-Validation -FixtureRoot $fixture
    Assert-Test ($missingVolume.ExitCode -ne 0) 'Classification without volumeClass was accepted'

    $fixture = New-Fixture
    $temporaryPaths.Add($fixture)
    $classificationsPath = Join-Path $fixture 'data' 'log-classifications.json'
    $classifications = @(Get-Content -LiteralPath $classificationsPath -Raw | ConvertFrom-Json)
    @($classifications | Where-Object tableName -eq 'SigninLogs')[0].tierRule = 'T3'
    Write-FixtureJson -Path $classificationsPath -Value $classifications
    & (Join-Path $root 'scripts' 'Update-Manifest.ps1') -RootPath $fixture | Out-Null
    $mismatchedRule = Invoke-Validation -FixtureRoot $fixture
    Assert-Test ($mismatchedRule.ExitCode -ne 0) 'Tier rule that contradicts recommendedTier was accepted'

    $fixture = New-Fixture
    $temporaryPaths.Add($fixture)
    [System.IO.File]::WriteAllText((Join-Path $fixture 'data' 'untracked.json'), "{}`n", [System.Text.UTF8Encoding]::new($false))
    $untrackedData = Invoke-Validation -FixtureRoot $fixture
    Assert-Test ($untrackedData.ExitCode -ne 0) 'Untracked data JSON file was accepted'

    $fixture = New-Fixture
    $temporaryPaths.Add($fixture)
    $sharedPath = Join-Path $fixture 'data' 'shared-table-sources.json'
    $shared = @(Get-Content -LiteralPath $sharedPath -Raw | ConvertFrom-Json)
    $shared[0].table = 'NotAClassifiedTable'
    Write-FixtureJson -Path $sharedPath -Value $shared
    & (Join-Path $root 'scripts' 'Update-Manifest.ps1') -RootPath $fixture | Out-Null
    $unknownSharedTable = Invoke-Validation -FixtureRoot $fixture
    Assert-Test ($unknownSharedTable.ExitCode -ne 0) 'Shared-table source on an unclassified table was accepted'

    $fixture = New-Fixture
    $temporaryPaths.Add($fixture)
    $sharedPath = Join-Path $fixture 'data' 'shared-table-sources.json'
    $shared = @(Get-Content -LiteralPath $sharedPath -Raw | ConvertFrom-Json)
    $shared[0].tierRule = 'T5'
    Write-FixtureJson -Path $sharedPath -Value $shared
    & (Join-Path $root 'scripts' 'Update-Manifest.ps1') -RootPath $fixture | Out-Null
    $staleT5 = Invoke-Validation -FixtureRoot $fixture
    Assert-Test ($staleT5.ExitCode -ne 0) 'T5 on a shared table with lake support was accepted'

    $fixture = New-Fixture
    $temporaryPaths.Add($fixture)
    $sharedPath = Join-Path $fixture 'data' 'shared-table-sources.json'
    $shared = @(Get-Content -LiteralPath $sharedPath -Raw | ConvertFrom-Json)
    $shared[0].filter = 'DeviceVendor in~ ("Fixture", "FixtureTwo")'
    Write-FixtureJson -Path $sharedPath -Value $shared
    & (Join-Path $root 'scripts' 'Update-Manifest.ps1') -RootPath $fixture | Out-Null
    $unsupportedOperator = Invoke-Validation -FixtureRoot $fixture
    Assert-Test ($unsupportedOperator.ExitCode -ne 0) 'Shared-table filter with an operator transformations reject was accepted'

    $fixture = New-Fixture
    $temporaryPaths.Add($fixture)
    $sharedPath = Join-Path $fixture 'data' 'shared-table-sources.json'
    $shared = @(Get-Content -LiteralPath $sharedPath -Raw | ConvertFrom-Json)
    $shared[0].filter = 'DeviceVendor =~ "Fixture" or DeviceVendor =~ "(FixtureTwo)"'
    Write-FixtureJson -Path $sharedPath -Value $shared
    & (Join-Path $root 'scripts' 'Update-Manifest.ps1') -RootPath $fixture | Out-Null
    $bareOr = Invoke-Validation -FixtureRoot $fixture
    Assert-Test ($bareOr.ExitCode -ne 0) 'Shared-table filter with a bare top-level or was accepted'

    $fixture = New-Fixture
    $temporaryPaths.Add($fixture)
    $sharedPath = Join-Path $fixture 'data' 'shared-table-sources.json'
    $shared = @(Get-Content -LiteralPath $sharedPath -Raw | ConvertFrom-Json)
    $analyticsSource = @($shared | Where-Object recommendedTier -eq 'analytics')[0]
    $analyticsSource | Add-Member -NotePropertyName splitHints -NotePropertyValue @([pscustomobject]@{ description = 'Fixture'; kql = 'DeviceAction =~ "deny"' }) -Force
    Write-FixtureJson -Path $sharedPath -Value $shared
    & (Join-Path $root 'scripts' 'Update-Manifest.ps1') -RootPath $fixture | Out-Null
    $analyticsSplit = Invoke-Validation -FixtureRoot $fixture
    Assert-Test ($analyticsSplit.ExitCode -ne 0) 'Split hints on an Analytics shared-table source were accepted'

    $fixture = New-Fixture
    $temporaryPaths.Add($fixture)
    $highValuePath = Join-Path $fixture 'data' 'high-value-fields.json'
    $highValue = Get-Content -LiteralPath $highValuePath -Raw | ConvertFrom-Json
    @($highValue.PSObject.Properties)[0].Value.splitHints = @([pscustomobject]@{ description = 'Fixture'; kql = 'OperationName has_any ("a", "b")' })
    Write-FixtureJson -Path $highValuePath -Value $highValue
    & (Join-Path $root 'scripts' 'Update-Manifest.ps1') -RootPath $fixture | Out-Null
    $tableSplitOperator = Invoke-Validation -FixtureRoot $fixture
    Assert-Test ($tableSplitOperator.ExitCode -ne 0) 'Table split hint with an operator transformations reject was accepted'

    $artifactRootA = Join-Path ([System.IO.Path]::GetTempPath()) "log-baseline-artifact-a-$([guid]::NewGuid().ToString('N'))"
    $artifactRootB = Join-Path ([System.IO.Path]::GetTempPath()) "log-baseline-artifact-b-$([guid]::NewGuid().ToString('N'))"
    $temporaryPaths.Add($artifactRootA)
    $temporaryPaths.Add($artifactRootB)
    $revision = (& git -C $root rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $revision -match '^[a-fA-F0-9]{40}$') {
        & (Join-Path $root 'scripts' 'New-ReleaseArtifact.ps1') -OutputPath $artifactRootA -SourceRevision $revision | Out-Null
        & (Join-Path $root 'scripts' 'New-ReleaseArtifact.ps1') -OutputPath $artifactRootB -SourceRevision $revision | Out-Null
        $archiveA = Get-ChildItem -LiteralPath $artifactRootA -Filter '*.zip' | Select-Object -First 1
        $archiveB = Get-ChildItem -LiteralPath $artifactRootB -Filter '*.zip' | Select-Object -First 1
        Assert-Test ((Get-FileHash $archiveA.FullName -Algorithm SHA256).Hash -eq (Get-FileHash $archiveB.FullName -Algorithm SHA256).Hash) 'Release artifact is not deterministic'
        $archiveEntries = [System.IO.Compression.ZipFile]::OpenRead($archiveA.FullName)
        try {
            $entryNames = @($archiveEntries.Entries.FullName)
            Assert-Test ('data/taxonomy.json' -in $entryNames) 'Release artifact omitted data/taxonomy.json'
            Assert-Test ('data/sources.json' -in $entryNames) 'Release artifact omitted data/sources.json'
            Assert-Test ('data/shared-table-sources.json' -in $entryNames) 'Release artifact omitted data/shared-table-sources.json'
            Assert-Test ('baselines/minimum.json' -in $entryNames) 'Release artifact omitted baselines/minimum.json'
            Assert-Test ('baselines/recommended.json' -in $entryNames) 'Release artifact omitted baselines/recommended.json'
            Assert-Test ('baselines/plus.json' -in $entryNames) 'Release artifact omitted baselines/plus.json'
            Assert-Test ('schemas/sources.schema.json' -in $entryNames) 'Release artifact omitted schemas/sources.schema.json'
        }
        finally {
            $archiveEntries.Dispose()
        }
    }
    else {
        try {
            & (Join-Path $root 'scripts' 'New-ReleaseArtifact.ps1') -OutputPath $artifactRootA -SourceRevision ('1' * 40) | Out-Null
            Assert-Test $false 'Release artifact was created without a committed HEAD'
        }
        catch {
            Assert-Test ($_.Exception.Message -match 'committed HEAD') 'Unborn repository failed with an unexpected release error'
        }
    }
}
finally {
    foreach ($path in $temporaryPaths) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    Write-Error ("Baseline tests failed with {0} error(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
    exit 1
}

Write-Host "Baseline tests passed: $checks checks."