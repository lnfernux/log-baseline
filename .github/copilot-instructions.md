# Log Baseline repository instructions

This repository is the canonical, versioned baseline data source for Microsoft Sentinel log tables. Log Horizon and the static explorer consume approved release snapshots.

## Core rules

- Context takes precedence over the generic baseline. Do not present recommendations as tenant-specific conclusions.
- Preserve the flat fields consumed by Log Horizon. Additive schema changes require a minor data version. Removing or renaming fields requires a major version.
- Use public evidence. Never add tenant identifiers, customer data, credentials, or private telemetry.
- Do not infer undocumented security behavior.
- Do not publish releases, create commits, push branches, or open pull requests. Leave validated changes for the maintainer.
- Do not edit generated data manually. Plan support and field-frequency statistics must come from their source adapters.

## Validation

Run from the repository root:

```powershell
pwsh ./scripts/Test-Baseline.ps1
```

When preparing an artifact locally:

```powershell
pwsh ./scripts/New-ReleaseArtifact.ps1
```

## Research order

1. Microsoft Learn MCP for official Sentinel, Azure Monitor, table, billing, tier, and retention documentation.
2. GitHub MCP for the public Azure/Azure-Sentinel repository and public connector content.
3. Standards and vendor documentation listed in the repository README.

Separate documented facts from judgment-based recommendations. Every classification change needs a concise rationale and public evidence.
