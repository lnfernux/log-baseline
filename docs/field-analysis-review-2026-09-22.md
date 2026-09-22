# Field analysis and baseline review evidence

This review used Azure-Sentinel revision `2e3336d0520681d277d1fa7b2fbc7730242f1d88` and the anonymous Azure Monitor metadata catalog observed on 2026-09-22.

## Results

- The corpus contained 5,158 query blocks.
- The earlier `_CL`-fallback allowlist discovered 303 trusted tables.
- Adding the 931-table catalog increased discovery to 311 tables and produced 202 threshold-qualified table entries.
- The catalog-backed run produced 42 new high-value-field candidates.
- Known parser artifacts `aadFunc`, `baseQuery`, `against`, `array_concat`, `bin`, `CorrelationId`, `Description`, `isfuzzy`, and `the` did not appear as table keys.
- The focused fixture now proves that an unclassified standard table is retained while a KQL alias is rejected. The suite passes 19 checks.
- Human review approved 29 of 30 classification candidates. Twenty-two were accepted unchanged, seven were edited, and one remains deferred.

## Findings

### Discovery needs independent evidence

An `_CL` suffix is useful evidence for custom tables but cannot identify new standard tables. Existing classifications and generated outputs also cannot discover names they have never seen. A pinned platform catalog closes that gap while local-symbol, function-call, and keyword filters continue to reject parser contamination.

### Frequency is not field ownership

A field referenced in a query can originate from a join, parser output, calculated alias, or enrichment table. Frequency establishes public usage only. High-value-field promotion still requires source-query and schema review.

### Recommendations and platform facts are different

Microsoft documents that DCR-based custom tables support the Auxiliary / Lake plan. Selecting that plan remains a recommendation based on access patterns. Auxiliary tables do not support alerts, so tier review must record that tradeoff for primary tables such as network-session telemetry.

### Human decisions need structured state

Markdown is useful for review, but prose is a weak import interface. Approved decisions are now represented as structured JSON and applied by `Import-ClassificationReview.ps1`, which validates edits, provenance, versioning, checksums, and the merged baseline.

### Provenance must identify the analyzed revision

Repository-level URLs and inherited source labels were insufficient to reproduce the analysis. Promoted records now point to the exact Azure-Sentinel commit and observation date.

## Controls added

1. Require `TableCatalogPath` for field analysis.
2. Test discovery of an unclassified standard table.
3. Test rejection of known KQL aliases during catalog-backed discovery.
4. Import classifications only from explicit `accept` or `edit` decisions.
5. Reject duplicate tables, unknown edit fields, and data-version regressions.
6. Regenerate manifest checksums and run baseline validation during import.

## Remaining work

- Resolve billing and selected-plan evidence for the one deferred candidate before promotion.
- Add deeper field-attribution tests for joins, parser functions, and calculated columns.
- Keep the table-catalog snapshot current through the scheduled drift workflow.
- Add isolated negative tests for malformed classification decision files.