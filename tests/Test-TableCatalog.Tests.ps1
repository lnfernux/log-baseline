[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'scripts' 'Compare-TableCatalog.ps1'
$fixtureMetadata = Join-Path $PSScriptRoot 'fixtures' 'table-metadata.json'
$fixtureSnapshot = Join-Path $PSScriptRoot 'fixtures' 'table-catalog-snapshot.json'
$temporaryPath = Join-Path ([System.IO.Path]::GetTempPath()) "log-baseline-table-catalog-$([guid]::NewGuid().ToString('N'))"
$failures = [System.Collections.Generic.List[string]]::new()
$checks = 0

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    $script:checks++
    if (-not $Condition) { $script:failures.Add($Message) }
}

try {
    New-Item -ItemType Directory -Path $temporaryPath | Out-Null
    $snapshotPath = Join-Path $temporaryPath 'snapshot.json'
    $reportPath = Join-Path $temporaryPath 'report.md'
    $resultPath = Join-Path $temporaryPath 'result.json'
    Copy-Item -LiteralPath $fixtureSnapshot -Destination $snapshotPath

    & $scriptPath `
        -MetadataPath $fixtureMetadata `
        -SnapshotPath $snapshotPath `
        -ReportPath $reportPath `
        -ResultPath $resultPath `
        -ObservedOn ([datetime]'2026-09-22') `
        -MinimumTableCount 1 `
        -UpdateSnapshot

    Assert-Test (Test-Path -LiteralPath $reportPath) 'Catalog review report was not created'
    Assert-Test (Test-Path -LiteralPath $resultPath) 'Catalog result JSON was not created'

    if (Test-Path -LiteralPath $resultPath) {
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        Assert-Test ($result.changed -eq $true) 'Fixture drift should be reported as changed'
        Assert-Test ($result.addedCount -eq 1) 'Expected one added table'
        Assert-Test ($result.removedCount -eq 1) 'Expected one removed table'
        Assert-Test (@($result.added) -contains 'NewTable') 'NewTable should be listed as added'
        Assert-Test (@($result.removed) -contains 'RemovedTable') 'RemovedTable should be listed as removed'
    }

    if (Test-Path -LiteralPath $reportPath) {
        $report = Get-Content -LiteralPath $reportPath -Raw
        Assert-Test ($report -match 'NewTable') 'Report should include added table details'
        Assert-Test ($report -match 'RemovedTable') 'Report should include removed table details'
        Assert-Test ($report -match 'does not prove') 'Report should warn that catalog removal is not proof of service removal'
    }

    $snapshot = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
    Assert-Test ($snapshot.observedOn -eq '2026-09-22') 'Updated snapshot should record its observation date'
    Assert-Test (@($snapshot.tables.name) -contains 'NewTable') 'Updated snapshot should contain the new table'
    Assert-Test (@($snapshot.tables.name) -notcontains 'RemovedTable') 'Updated snapshot should omit the removed table'

    $initialSnapshotPath = Join-Path $temporaryPath 'initial-snapshot.json'
    $initialResultPath = Join-Path $temporaryPath 'initial-result.json'
    & $scriptPath `
        -MetadataPath $fixtureMetadata `
        -SnapshotPath $initialSnapshotPath `
        -ReportPath (Join-Path $temporaryPath 'initial-report.md') `
        -ResultPath $initialResultPath `
        -ObservedOn ([datetime]'2026-09-22') `
        -MinimumTableCount 1 `
        -InitializeSnapshot `
        -UpdateSnapshot | Out-Null

    $initialResult = Get-Content -LiteralPath $initialResultPath -Raw | ConvertFrom-Json
    Assert-Test ($initialResult.initialized -eq $true) 'First run should be marked as snapshot initialization'
    Assert-Test ($initialResult.changed -eq $false) 'Snapshot initialization should not report every table as added'
    Assert-Test ((Get-Content -LiteralPath $initialSnapshotPath -Raw | ConvertFrom-Json).tables.Count -eq 2) 'Initial snapshot should contain all catalog tables'
}
finally {
    Remove-Item -LiteralPath $temporaryPath -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Error ("Table-catalog tests failed with {0} error(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
    exit 1
}

Write-Host "Table-catalog tests passed: $checks checks."