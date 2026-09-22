# Pre-made baselines

These cumulative Log Horizon-compatible layers were migrated from log-baseline-web:

- `minimum.json`: core Microsoft identity, Sentinel, Azure control-plane, and Microsoft 365 audit coverage.
- `recommended.json`: Minimum plus Microsoft Graph, common Azure resource logs, and behavior analytics.
- `plus.json`: Recommended plus broader Microsoft Entra and Sentinel behavior data.

The JSON files are generated from `data/log-classifications.json` by `scripts/Update-PreMadeBaselines.ps1`. Do not edit them manually. Their checksums are stored in `data/manifest.json`, validated by `scripts/Test-Baseline.ps1`, and included in release artifacts.