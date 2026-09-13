# Contributing

Contributions are welcome for incorrect classifications, missing Microsoft Sentinel tables, source updates, taxonomy improvements, and validation tooling.

## Before submitting

- Search existing issues and pull requests.
- Use public documentation or public repositories as evidence.
- Do not include tenant IDs, subscription IDs, workspace IDs, customer names, queries containing customer data, credentials, or screenshots from private environments.
- Explain environment-specific recommendations as context rather than universal defaults.

## Data changes

Keep changes focused and preserve the existing flat classification used by Log Horizon.

For a classification change, include:

- The Sentinel table name.
- The current and proposed values.
- A concise rationale.
- Public source links.
- Whether the change affects security value, tier, retention, lifecycle, or taxonomy.

Plan support and field-frequency statistics are regenerated from their upstream sources.

## Validation

Run from the repository root:

```powershell
pwsh ./scripts/Test-Baseline.ps1
```

The command should ideally pass before opening a pull request, but there might be cases where it does not.

## Pull requests

1. Fork the repository and branch from `main`.
2. Make one focused change.
3. Run validation.
4. Complete the pull request template and link the relevant issue.

Every data change requires human review and no pull requests are merged automatically.
