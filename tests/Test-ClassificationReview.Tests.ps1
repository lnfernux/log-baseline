[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) "log-baseline-review-import-$([guid]::NewGuid().ToString('N'))"
$failures = [System.Collections.Generic.List[string]]::new()
$checks = 0
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    $script:checks++
    if (-not $Condition) { $script:failures.Add($Message) }
}

function Write-JsonFixture {
    param([string]$Path, [object]$Value)
    $json = (($Value | ConvertTo-Json -Depth 30) + "`n").Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

try {
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    foreach ($directory in 'baselines', 'data', 'schemas', 'scripts') {
        Copy-Item -LiteralPath (Join-Path $root $directory) -Destination $fixtureRoot -Recurse
    }
    $dataVersion = (Get-Content -LiteralPath (Join-Path $fixtureRoot 'data' 'manifest.json') -Raw | ConvertFrom-Json).dataVersion

    $candidatePath = Join-Path $fixtureRoot 'candidates.json'
    $decisionPath = Join-Path $fixtureRoot 'decisions.json'
    $candidate = @([ordered]@{
        tableName = 'FixtureReviewed_CL'
        proposed = [ordered]@{
            tableName = 'FixtureReviewed_CL'
            connector = 'Fixture connector'
            classification = 'secondary'
            valueRule = 'C9'
            category = 'Infrastructure Diagnostics'
            description = 'Fixture record for classification review import testing'
            keywords = @('fixture', 'review')
            mitreSources = @()
            recommendedTier = 'analytics'
            tierRule = 'T2'
            volumeClass = 'low'
            volumeDriver = 'application-trace'
            isFree = $false
            recommendedRetentionDays = 180
            domainId = 'infrastructure-platform'
            logTypeId = 'diagnostic'
            sourceIds = @('azure-sentinel-rule-corpus')
        }
    })
    $decisions = [ordered]@{
        decisions = @([ordered]@{
            tableName = 'FixtureReviewed_CL'
            decision = 'edit'
            changes = [ordered]@{ recommendedTier = 'datalake'; tierRule = 'T4' }
        })
    }
    Write-JsonFixture -Path $candidatePath -Value $candidate
    Write-JsonFixture -Path $decisionPath -Value $decisions

    & (Join-Path $root 'scripts' 'Import-ClassificationReview.ps1') `
        -CandidatesPath $candidatePath `
        -DecisionsPath $decisionPath `
        -AzureSentinelRevision ('a' * 40) `
        -ObservedOn ([datetime]'2026-09-22') `
        -DataVersion $dataVersion `
        -RootPath $fixtureRoot | Out-Null

    $classifications = @(Get-Content -LiteralPath (Join-Path $fixtureRoot 'data' 'log-classifications.json') -Raw | ConvertFrom-Json)
    $imported = @($classifications | Where-Object tableName -eq 'FixtureReviewed_CL')
    Assert-Test ($imported.Count -eq 1) 'Approved classification was not imported exactly once'
    Assert-Test ($imported[0].recommendedTier -eq 'datalake') 'Structured edit was not applied'

    $manifest = Get-Content -LiteralPath (Join-Path $fixtureRoot 'data' 'manifest.json') -Raw | ConvertFrom-Json
    Assert-Test ($manifest.dataVersion -eq $dataVersion) 'Data version was not updated'
    Assert-Test ($manifest.files.'log-classifications.json' -eq (Get-FileHash -LiteralPath (Join-Path $fixtureRoot 'data' 'log-classifications.json') -Algorithm SHA256).Hash) 'Classification checksum was not updated'

    $sources = Get-Content -LiteralPath (Join-Path $fixtureRoot 'data' 'sources.json') -Raw | ConvertFrom-Json
    $source = @($sources.sources | Where-Object id -eq 'azure-sentinel-rule-corpus')
    Assert-Test ($source[0].revision -eq ('a' * 40)) 'Source revision was not updated'
    Assert-Test (@($source[0].appliesTo) -contains 'log-classifications.json') 'Classification provenance was not linked'

    $before = @(Get-Content -LiteralPath (Join-Path $fixtureRoot 'data' 'log-classifications.json') -Raw | ConvertFrom-Json)
    $changed = ($before | Where-Object tableName -eq 'SigninLogs' | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
    $changed | Add-Member -NotePropertyName volumeClass -NotePropertyValue 'very-high' -Force
    $changed | Add-Member -NotePropertyName volumeDriver -NotePropertyValue 'sign-in' -Force
    $changed.sourceIds = @($changed.sourceIds + 'fixture-guidance')
    $sourcesFixturePath = Join-Path $fixtureRoot 'sources-additions.json'
    Write-JsonFixture -Path $candidatePath -Value @([ordered]@{ tableName = 'SigninLogs'; status = 'changed'; proposed = $changed })
    Write-JsonFixture -Path $decisionPath -Value ([ordered]@{ decisions = @([ordered]@{ tableName = 'SigninLogs'; decision = 'accept' }) })
    Write-JsonFixture -Path $sourcesFixturePath -Value @([ordered]@{
        id = 'fixture-guidance'
        title = 'Fixture guidance'
        url = 'https://example.com/guidance'
        revision = 'fixture'
        observedOn = '2026-10-02'
        appliesTo = @('log-classifications.json')
        scope = 'Fixture source for changed-record import testing.'
    })

    & (Join-Path $root 'scripts' 'Import-ClassificationReview.ps1') `
        -CandidatesPath $candidatePath `
        -DecisionsPath $decisionPath `
        -ReviewedSourcesPath $sourcesFixturePath `
        -ObservedOn ([datetime]'2026-10-02') `
        -DataVersion $dataVersion `
        -RootPath $fixtureRoot | Out-Null

    $after = @(Get-Content -LiteralPath (Join-Path $fixtureRoot 'data' 'log-classifications.json') -Raw | ConvertFrom-Json)
    $replaced = @($after | Where-Object tableName -eq 'SigninLogs')
    Assert-Test ($after.Count -eq $before.Count) 'Changed record import altered the classification count'
    Assert-Test ($replaced.Count -eq 1 -and $replaced[0].volumeClass -eq 'very-high') 'Changed record was not replaced in place'
    $sources = Get-Content -LiteralPath (Join-Path $fixtureRoot 'data' 'sources.json') -Raw | ConvertFrom-Json
    Assert-Test (@($sources.sources | Where-Object id -eq 'fixture-guidance').Count -eq 1) 'Reviewed source record was not added'
    Assert-Test (@($sources.sources | Where-Object id -eq 'azure-sentinel-rule-corpus')[0].revision -eq ('a' * 40)) 'Azure-Sentinel provenance changed without a revision'
    $minimum = @(Get-Content -LiteralPath (Join-Path $fixtureRoot 'baselines' 'minimum.json') -Raw | ConvertFrom-Json)
    Assert-Test (@($minimum | Where-Object tableName -eq 'SigninLogs')[0].volumeClass -eq 'very-high') 'Pre-made baselines were not regenerated'

    Write-JsonFixture -Path $candidatePath -Value @([ordered]@{ tableName = 'MissingTable_CL'; status = 'changed'; proposed = [ordered]@{ tableName = 'MissingTable_CL' } })
    Write-JsonFixture -Path $decisionPath -Value ([ordered]@{ decisions = @([ordered]@{ tableName = 'MissingTable_CL'; decision = 'accept' }) })
    $rejected = $false
    try {
        & (Join-Path $root 'scripts' 'Import-ClassificationReview.ps1') -CandidatesPath $candidatePath -DecisionsPath $decisionPath -ObservedOn ([datetime]'2026-10-02') -DataVersion $dataVersion -RootPath $fixtureRoot | Out-Null
    }
    catch { $rejected = $_.Exception.Message -match 'no existing classification' }
    Assert-Test $rejected 'Changed candidate without an existing record was accepted'
}
finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Error ("Classification-review tests failed with {0} error(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
    exit 1
}

Write-Host "Classification-review tests passed: $checks checks."
