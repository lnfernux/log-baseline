[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($RootPath)
$classificationsPath = Join-Path $root 'data' 'log-classifications.json'
$outputPath = Join-Path $root 'baselines'
$schemaPath = Join-Path $root 'schemas' 'log-classifications.schema.json'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

$classifications = @(Get-Content -LiteralPath $classificationsPath -Raw | ConvertFrom-Json -Depth 100)
$byName = @{}
foreach ($entry in $classifications) { $byName[[string]$entry.tableName] = $entry }

$minimum = @(
    'SigninLogs', 'AuditLogs', 'AADRiskyUsers', 'AADUserRiskEvents',
    'SecurityAlert', 'SecurityIncident', 'AzureActivity', 'OfficeActivity'
)
$recommendedAdditions = @(
    'MicrosoftGraphActivityLogs', 'AzureDiagnostics', 'AZKVAuditLogs', 'AZFWThreatIntel',
    'AGWFirewallLogs', 'StorageBlobLogs', 'SQLSecurityAuditEvents', 'BehaviorAnalytics'
)
$plusAdditions = @(
    'AADNonInteractiveUserSignInLogs', 'AADServicePrincipalSignInLogs',
    'AADManagedIdentitySignInLogs', 'AADProvisioningLogs', 'AADRiskyServicePrincipals',
    'AADServicePrincipalRiskEvents', 'ADFSSignInLogs', 'MicrosoftServicePrincipalSignInLogs',
    'AADGraphActivityLogs', 'GraphNotificationsActivityLogs', 'AADRiskyAgents',
    'AADAgentRiskEvents', 'AADCustomSecurityAttributeAuditLogs', 'SentinelBehaviorInfo',
    'SentinelBehaviorEntities'
)
$definitions = [ordered]@{
    'minimum.json' = $minimum
    'recommended.json' = @($minimum + $recommendedAdditions)
    'plus.json' = @($minimum + $recommendedAdditions + $plusAdditions)
}

New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
foreach ($definition in $definitions.GetEnumerator()) {
    $missing = @($definition.Value | Where-Object { -not $byName.ContainsKey($_) })
    if ($missing.Count -gt 0) { throw "$($definition.Key) references missing classifications: $($missing -join ', ')" }

    $records = @($definition.Value | ForEach-Object { $byName[$_] })
    $targetPath = Join-Path $outputPath $definition.Key
    $json = (($records | ConvertTo-Json -Depth 30) + "`n").Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText($targetPath, $json, $utf8NoBom)
    if (-not (Test-Json -Path $targetPath -SchemaFile $schemaPath)) { throw "$($definition.Key) does not match the classification schema." }
}

& (Join-Path $root 'scripts' 'Update-Manifest.ps1') -RootPath $root
Write-Host "Updated $($definitions.Count) pre-made baseline layers."
