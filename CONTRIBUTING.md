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

Use the repository adapters rather than editing generated files directly:

```powershell
pwsh ./scripts/Update-PlanTables.ps1 -InputPath <saved-learn-markdown> -ObservedOn <date>
pwsh ./scripts/New-FieldAnalysis.ps1 -AzureSentinelPath <checkout> -SourceRevision <sha> -FieldFrequencyOutputPath <candidate> -HighValueFieldsOutputPath <candidate> -SummaryOutputPath <summary>
pwsh ./scripts/Import-FieldAnalysis.ps1 -FieldFrequencyPath <file> -HighValueFieldsPath <file> -AzureSentinelRevision <sha> -ObservedOn <date>
pwsh ./scripts/Import-LogHorizonSnapshot.ps1 -SourcePath <checkout> -Revision <sha>
```

Generate field-analysis candidates outside `data/`, review the summary and candidate diff, then use the import adapter for approved output. Frequency is supporting evidence, not proof that a field has high security value. Split hints require manual KQL review.

Review the resulting data, provenance changes, and manifest checksums together. The scheduled table-catalog workflow creates a source-drift review queue and does not modify classifications automatically.

## Validation

Run from the repository root:

```powershell
pwsh ./scripts/Test-Baseline.ps1
pwsh ./tests/Test-Baseline.Tests.ps1
pwsh ./tests/Test-FieldAnalysis.Tests.ps1
pwsh ./tests/Test-TableCatalog.Tests.ps1
```

Both commands must pass before opening a pull request. If a proposed contract change requires a failing fixture, update the validator and tests in the same pull request.

## Pull requests

1. Fork the repository and branch from `main`.
2. Make one focused change.
3. Run validation.
4. Complete the pull request template and link the relevant issue.

Every data change requires human review and no pull requests are merged automatically.

## Contribution licensing

By submitting a contribution, you confirm that you have the right to provide it and agree that it is licensed under the repository license applicable to the changed file. Data and documentation contributions use CC BY 4.0. Script and schema contributions use the MIT License.
