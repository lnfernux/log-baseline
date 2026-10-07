---
name: high-value-field-generation
description: "Use when generating or reviewing field-frequency statistics and high-value-field candidates from an offline Azure-Sentinel checkout. Runs deterministic local analysis, preserves curated entries, and requires human review before canonical import."
argument-hint: "Path to the Azure-Sentinel checkout and optional output directory"
---

# High-value field generation

Generate review candidates from a fixed local Azure-Sentinel revision. Frequency is evidence that public detections reference a field. It does not by itself prove that the field has high security value.

## Prerequisites

1. Use PowerShell 7 from the repository root.
2. Confirm the checkout contains `Detections`, `Hunting Queries`, or `Solutions`.
3. Record the exact 40-character Azure-Sentinel commit SHA.
4. Use a reviewed table-catalog snapshot from `Compare-TableCatalog.ps1`.
5. Save the Log Analytics metadata API response (`https://api.loganalytics.io/v1/metadata`) to `./tmp/table-metadata.json` and record the observation date. It supplies table columns.
6. Write candidates outside `data/`. Do not edit generated canonical files directly.

## Generate candidates

```powershell
$revision = git -C ../Azure-Sentinel rev-parse HEAD

pwsh ./scripts/New-FieldAnalysis.ps1 `
    -AzureSentinelPath ../Azure-Sentinel `
    -SourceRevision $revision `
    -TableCatalogPath ./.github/table-catalog/snapshot.json `
    -TableSchemaPath ./tmp/table-metadata.json `
    -FieldFrequencyOutputPath ./tmp/field-frequency-stats.json `
    -HighValueFieldsOutputPath ./tmp/high-value-fields.json `
    -SummaryOutputPath ./tmp/field-analysis-summary.md
```

For a reproducibility check, pass a fixed `-GeneratedAt` value and run the command twice to separate timestamp changes from analysis changes.

## Review

1. Read `field-analysis-summary.md` and inspect candidate diffs against `data/`.
2. Confirm parsed rule and table counts are plausible for the selected revision.
3. Compare discovered tables with the catalog, classifications, and `_CL` custom tables. Investigate names admitted by only one source. Classified names reported as parsers are parser aliases, not tables. Review them as naming corrections.
4. Review `unverifiedTables` separately. Their fields are not checked against a schema and can include aliases, calculated fields, and joined columns.
5. Review the `parsers` section: source tables, source columns, and parsed fields. A parser with no source tables usually reads through `table()` or another parser. Do not copy parsed field names onto source tables.
6. Check newly proposed fields against several source queries. Reject parser artifacts, aliases, operators, literals, and low-context fields.
7. Preserve curated descriptions unless public evidence supports a correction.
8. Treat empty `splitHints` on new candidates as intentional. Write split hints manually only when the KQL expression is valid and the split produces useful review context.
9. Record uncertainty. Do not turn frequency thresholds into claims about detection quality.
10. Treat `-SharedSourceCandidatesOutputPath` output as leads, not filters. The extractor takes the first `DeviceVendor`, `DeviceProduct`, `ProcessName`, or `Facility` predicate anywhere in the query. It ignores `or` between values of the same field and can pick up predicates from joined subqueries on other tables. Rebuild every accepted filter from the parser or vendor documentation.
11. XDR-only tables such as `EntraIdSignInEvents` are not in the Log Analytics metadata. Add their columns from the Defender XDR schema reference to a copy of the schema input, or they stay in `unverifiedTables`.

## Promote reviewed output

Only promote files after a human has approved the candidate diff:

```powershell
pwsh ./scripts/Import-FieldAnalysis.ps1 `
    -FieldFrequencyPath ./tmp/field-frequency-stats.json `
    -HighValueFieldsPath ./tmp/high-value-fields.json `
    -AzureSentinelRevision $revision `
    -ObservedOn 2026-09-22
```

Then run:

```powershell
pwsh ./scripts/Test-Baseline.ps1
pwsh ./tests/Test-Baseline.Tests.ps1
pwsh ./tests/Test-FieldAnalysis.Tests.ps1
```

Report the source revision, thresholds, generated files, accepted and rejected candidates, manually authored split hints, and validation results.