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
5. Write candidates outside `data/`. Do not edit generated canonical files directly.

## Generate candidates

```powershell
$revision = git -C ../Azure-Sentinel rev-parse HEAD

pwsh ./scripts/New-FieldAnalysis.ps1 `
    -AzureSentinelPath ../Azure-Sentinel `
    -SourceRevision $revision `
    -TableCatalogPath ./.github/table-catalog/snapshot.json `
    -FieldFrequencyOutputPath ./tmp/field-frequency-stats.json `
    -HighValueFieldsOutputPath ./tmp/high-value-fields.json `
    -SummaryOutputPath ./tmp/field-analysis-summary.md
```

For a reproducibility check, pass a fixed `-GeneratedAt` value and run the command twice to separate timestamp changes from analysis changes.

## Review

1. Read `field-analysis-summary.md` and inspect candidate diffs against `data/`.
2. Confirm parsed rule and table counts are plausible for the selected revision.
3. Compare discovered tables with the catalog, classifications, and `_CL` custom tables. Investigate names admitted by only one source.
4. Check newly proposed fields against several source queries. Reject parser artifacts, aliases, operators, literals, and low-context fields.
5. Preserve curated descriptions unless public evidence supports a correction.
6. Treat empty `splitHints` on new candidates as intentional. Write split hints manually only when the KQL expression is valid and the split produces useful review context.
7. Record uncertainty. Do not turn frequency thresholds into claims about detection quality.

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