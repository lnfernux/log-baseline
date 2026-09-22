---
name: baseline-human-review
description: "Use when validating, creating, or revising Microsoft Sentinel baseline classifications with a human reviewer. Verifies prerequisites, builds an evidence-backed review queue, presents one table at a time, records counterarguments and uncertainty, promotes only approved changes, validates the baseline, and prepares a pull request handoff."
argument-hint: "Review scope: all tables, changed tables, catalog additions, or named tables"
---

# Baseline human review

Run the complete human-in-the-loop classification process. A generated proposal is review input, never approval. Context always takes precedence over this generic baseline.

Load these bundled resources before starting:

- [Classification rules](references/classification-rules.md)
- [Table review example](references/table-review-example.md)
- [Review ledger template](templates/review-ledger.md)

Use the `Baseline Curator` agent for table research and proposal preparation when it is available.

## 1. Verify prerequisites

Before generating proposals, confirm:

1. PowerShell 7 is available and the current directory is the repository root.
2. The active branch is not `main`. Stop and ask the maintainer to create a feature branch if it is.
3. Existing unrelated changes are identified and will not be overwritten.
4. `pwsh ./scripts/Test-Baseline.ps1` passes before review starts.
5. The review scope is explicit: all tables, changed tables, catalog additions, or named tables.
6. Required source snapshots and their exact revisions or observation dates are recorded.
7. Microsoft Learn and public GitHub research are available. Never use tenant data, credentials, or private telemetry.
8. Generated-data changes have candidate files produced by their source adapters. Do not edit generated data manually.
9. `main` is protected using the settings in `.github/BRANCH_PROTECTION.md`. If protection cannot be verified, flag it in the final handoff.

Summarize the prerequisites and ask the human to resolve any failed item before continuing. Do not silently weaken a prerequisite.

## 2. Build the review queue

Create an ignored working folder under `artifacts/baseline-review/<date>-<scope>/` containing:

- `overview.md`: source revisions, scope, counts, risks, and confidence distribution.
- `review-ledger.md`: a copy of the bundled ledger template.
- `candidates.json`: proposed records only. Never treat this as canonical data.

For each table:

1. Read the current classification, schema, taxonomy, provenance, and relevant generated evidence.
2. Research Microsoft Learn first, then public Azure/Azure-Sentinel content, then the classification sources in `README.md`.
3. Apply `references/classification-rules.md` consistently.
4. Separate documented facts from recommendation judgment.
5. Record evidence URLs and exact source revisions where available.
6. Assign confidence: `high`, `medium`, or `low`.
7. Mark the table `uncertain` when evidence conflicts, table identity is ambiguous, behavior is preview-only, the recommendation is highly context-dependent, or generated evidence contains parser contamination.

Present the overview before starting table decisions. Include total tables, new/changed/unchanged counts, high/medium/low confidence counts, uncertain tables, and validation status.

## 3. Review one table at a time

Never request batch approval. Present exactly one table using this structure:

```markdown
## <TableName> (<position>/<total>)

Status: new | changed | unchanged
Confidence: high | medium | low
Uncertain: yes | no - <reason when yes>

### Current
<current record or "Not classified">

### Proposed
<complete proposed record>

### Documented facts
- <fact with evidence URL>

### Classification judgment
- <rule applied and rationale>

### Context
- <situations that could change the recommendation>

### Open questions
- <unknowns, conflicts, or "None">
```

Ask for one decision:

- `accept`: approve the proposal as shown.
- `edit`: approve with explicit field changes supplied by the reviewer.
- `reject`: leave the current baseline unchanged.
- `defer`: leave unchanged and record what evidence is missing.
- A free-form counterargument: reassess the evidence and rules, show the revised proposal or defend the original with sources, then ask again.

Record every decision immediately in `review-ledger.md`. Never convert silence, ambiguity, or uncertainty into acceptance. Low-confidence proposals should default to `defer`.

## 4. Complete the review

After all tables have a decision:

1. Show counts for accepted, edited, rejected, and deferred tables.
2. List every uncertain or deferred table and the missing evidence.
3. Ask for final confirmation to apply the accepted and edited records.
4. Apply only confirmed records. Preserve rejected and deferred records exactly.
5. Update source provenance and the data version according to `CHANGELOG.md`.
6. Regenerate manifest checksums with `pwsh ./scripts/Update-Manifest.ps1`.
7. Run all relevant validation:

```powershell
pwsh ./scripts/Test-Baseline.ps1
pwsh ./tests/Test-Baseline.Tests.ps1
pwsh ./tests/Test-FieldAnalysis.Tests.ps1
pwsh ./tests/Test-TableCatalog.Tests.ps1
```

## 5. Prepare the pull request handoff

All baseline and code changes must reach `main` through a pull request. Do not commit, push, open a pull request, release, or merge from this skill.

Return a PR-ready handoff containing:

- Review scope and source revisions.
- Accepted and edited tables.
- Rejected and deferred tables.
- Uncertainty and unresolved questions.
- Evidence links.
- Data/schema version impact.
- Compatibility impact.
- Validation output.
- Confirmation that generated files used source adapters.
- Confirmation that no tenant data or secrets are present.

Keep the ledger in the review artifacts until the maintainer has reviewed the final diff. The canonical data diff and the ledger must agree.