# Microsoft Sentinel Log Baseline

[![Validate baseline](https://github.com/lnfernux/log-baseline/actions/workflows/validate.yml/badge.svg)](https://github.com/lnfernux/log-baseline/actions/workflows/validate.yml)
[![Data version](https://img.shields.io/badge/data-0.1.0-00cc00)](CHANGELOG.md)
[![Schema version](https://img.shields.io/badge/schema-1.0.0-475569)](data/manifest.json)
[![License](https://img.shields.io/badge/license-CC%20BY%204.0%20%2B%20MIT-475569)](LICENSE.md)

> [!IMPORTANT]
> **Context always takes precedence over this baseline.** A table marked as secondary can still be essential because of deployed detections, regulatory requirements, incident history, or business processes. Treat these recommendations as review inputs, not as a one-size-fits-all security standard.

Generic, versioned recommendations for Microsoft Sentinel log sources. The dataset classifies tables by security value and recommends ingestion tiers and retention periods for [Log Horizon](https://github.com/lnfernux/log-horizon) and the [Log Baseline explorer](https://baseline.infernux.no).

> [!NOTE]
> This repository is the canonical data source. Log Horizon vendors approved release snapshots so installed PowerShell modules remain self-contained and work without network access.

## Data

The canonical files are stored in [`data/`](data/):

| File | Description |
| --- | --- |
| `log-classifications.json` | Sentinel table classifications and recommendations. |
| `basic-plan-tables.json` | Built-in tables supporting the Basic plan. |
| `auxiliary-plan-tables.json` | Built-in tables supporting the Auxiliary plan. |
| `implicit-consumers.json` | Non-KQL Sentinel consumers and platform tables. |
| `high-value-fields.json` | Field recommendations and split hints. |
| `field-frequency-stats.json` | Derived field usage from public Sentinel rules. |
| `custom-classifications-example.json` | Log Horizon-compatible override examples. |
| `taxonomy.json` | The generic Domain > Log type mapping used by the explorer. |
| `sources.json` | Versioned provenance records referenced by classifications and generated datasets. |

The initial data was migrated without semantic changes from [Log Horizon](https://github.com/lnfernux/log-horizon).

### Data accuracy

> [!WARNING]
> The dataset uses AI-assisted research and classification with human review. AI output, public documentation, upstream detection content, and tenant observations can all be incomplete or outdated. Validate recommendations against your environment before using them.

**The repository was created and is maintained with AI assistance:**

1. Mapped out all current log sources from the data sources below (data connectors reference, the Azure-Sentinel repo and a live tenant).
2. Author (that's me, hi) mapped out a set of around 50 connectors in the JSON-schema manually and provided context as to why I chose that. In two cases I classified wrongly on purpose, this will make sense later.
3. AI (an specialized agent) with access to Microsoft Learn MCP and Defender MCP along with web-search was provided with the task of:
   * Using the classification sources to validate my current set of manual classifications and find any that didn't make sense.
   * After validating and generating a set of rules based on my input, classification sources and the run over the pre-classified data, it ran on the rest of the data.
4. Author (hi, that's me again) validated some of the baseline against live tenants and made some corrections.

> [!WARNING]
> This means a lot of thing CAN possibly go wrong here.

1. AI can be wrong, will be wrong. So a human needs to be in the loop.
2. This is a generic approach - the only context is that the data is security relevant and costs money for volume. So it can never be as good as a baseline created with context in mind.
3. The Microsoft Learn docs can a) either document tables in preview which are not yet available or b) is being deprecated/has been deprecated and no longer works.
4. Same goes for the Azure-Sentinel repo, the detections used for table mappings could be new, outdated, this also goes for the fields used in the frequency stats.
5. Live tenants could have custom solutions/tables.

> [!NOTE]
> So as you can see, what this is data that has been classified by a non-deterministic process with some oversight by a complete moron. **Use at your own peril.**
> From joke to reality, the web counterpart for this repo, [baseline.infernux.no](https://baseline.infernux.no), will at one point have an option to sign in with your Github account and vote on tables.

### Data sources

#### Table sources

The baseline is created using the following sources:

- [Microsoft Sentinel data connectors reference](https://learn.microsoft.com/azure/sentinel/data-connectors-reference)
- [Microsoft Sentinel tables and connectors reference](https://learn.microsoft.com/azure/sentinel/sentinel-tables-connectors-reference)
- [Azure Monitor table feature matrix](https://learn.microsoft.com/azure/azure-monitor/reference/tables-features)
- [Microsoft Sentinel billing](https://learn.microsoft.com/azure/sentinel/billing)
- [Microsoft Sentinel data tier management](https://learn.microsoft.com/azure/sentinel/manage-data-overview)
- [Azure/Azure-Sentinel](https://github.com/Azure/Azure-Sentinel)

#### Classification sources

For the classification, the following sources served as inspiration:

- [ACSC best practices for event logging and threat detection](https://www.cyber.gov.au/sites/default/files/2024-08/best-practices-for-event-logging-and-threat-detection.pdf)
- [ACSC priority logs for SIEM ingestion](https://www.cyber.gov.au/business-government/detecting-responding-to-threats/event-logging/implementing-siem-soar-platforms/priority-logs-for-siem-ingestion-practitioner-guidance)
- [CISA guidance for implementing M-21-31](https://www.cisa.gov/sites/default/files/2023-02/TLP%20CLEAR%20-%20Guidance%20for%20Implementing%20M-21-31_Improving%20the%20Federal%20Governments%20Investigative%20and%20Remediation%20Capabilities_.pdf)
- [CISA Microsoft Expanded Cloud Logs Implementation Playbook](https://www.cisa.gov/sites/default/files/2025-01/microsoft-expanded-cloud-logs-implementation-playbook-508c.pdf)
- [MITRE ATT&CK data sources](https://attack.mitre.org/datasources/)
- [NIST SP 800-92](https://csrc.nist.gov/pubs/sp/800/92/final)
- [Google Cloud Audit Logs](https://docs.cloud.google.com/logging/docs/audit)

See the [Log Horizon baseline methodology](https://github.com/lnfernux/log-horizon#how-the-classifications-were-built) for the full original description while the expanded methodology is migrated here. Each classification points to the exact Log Horizon source revision through `sourceIds`. These references establish provenance for the inherited recommendation. They do not claim that every recommendation is independently proven by every methodology source above.

The plan-support files cover the complete Microsoft table feature matrix, including tables that do not yet have a classification entry. Field-frequency statistics likewise retain tables found in the public rule corpus even when the baseline does not classify them.

### Human review workflow

The [`baseline-human-review` skill](.github/skills/baseline-human-review/SKILL.md) runs the complete review process: prerequisite checks, source-backed proposal generation, an overview with confidence and uncertainty, one-table-at-a-time decisions, a resumable review ledger, approved-change promotion, and validation. A reviewer can accept, edit, reject, defer, or challenge each proposal. Uncertain tables are highlighted and default to deferred.

All changes reach `main` through pull requests.

## Updating generated data

Update commands use local, reviewable inputs. They do not download mutable sources during validation.

Import a checked-out Log Horizon snapshot:

```powershell
pwsh ./scripts/Import-LogHorizonSnapshot.ps1 `
	-SourcePath ../log-horizon `
	-Revision 49188a945b7587c0d613e45381d19d54f77a04af
```

Save the [Microsoft Learn table feature matrix](https://learn.microsoft.com/azure/azure-monitor/reference/tables-features) as Markdown, then regenerate both plan lists:

```powershell
pwsh ./scripts/Update-PlanTables.ps1 `
	-InputPath ./tmp/tables-features.md `
	-ObservedOn 2026-09-13
```

Import field-analysis output generated from a specific Azure-Sentinel checkout:

```powershell
pwsh ./scripts/New-FieldAnalysis.ps1 `
	-AzureSentinelPath ../Azure-Sentinel `
	-SourceRevision <40-character-commit-sha> `
	-FieldFrequencyOutputPath ./tmp/field-frequency-stats.json `
	-HighValueFieldsOutputPath ./tmp/high-value-fields.json `
	-SummaryOutputPath ./tmp/field-analysis-summary.md

pwsh ./scripts/Import-FieldAnalysis.ps1 `
	-FieldFrequencyPath ./tmp/field-frequency-stats.json `
	-HighValueFieldsPath ./tmp/high-value-fields.json `
	-AzureSentinelRevision <40-character-commit-sha> `
	-ObservedOn 2026-09-13
```

Generation preserves curated high-value entries and adds threshold-qualified candidates without inventing split hints. Review the summary and candidate diff before running the import adapter. The workspace skill at [`.github/skills/high-value-field-generation/SKILL.md`](.github/skills/high-value-field-generation/SKILL.md) contains the full review checklist and examples.

The initial field-analysis snapshot predates revision capture. Its provenance record states that limitation explicitly. Future imports require the exact Azure-Sentinel commit.

### Table catalog review

The weekly `table-catalog-review.yml` workflow compares the anonymous Azure Monitor metadata API with a versioned source snapshot. It opens or updates a draft pull request containing only the refreshed snapshot and a review report. It never edits classifications. Source failures create or update a separate issue and cannot be interpreted as table removals.

The first successful run proposes the initial snapshot. Later runs report additions and catalog disappearances for the two [Baseline Curator](.github/agents/baseline-curator.agent.md) flows: automatic proposal generation or one-table-at-a-time human review.

## Validation

> [!TIP]
> Run both commands before proposing a change. CI executes the same checks on Windows and Linux.

Run from the repository root:

```powershell
pwsh ./scripts/Test-Baseline.ps1
pwsh ./tests/Test-Baseline.Tests.ps1
pwsh ./tests/Test-FieldAnalysis.Tests.ps1
pwsh ./tests/Test-TableCatalog.Tests.ps1
```

Validation covers JSON parsing and schemas, required values, unique table names, lifecycle references, plan lists, cross-file relationships, and manifest checksums.

## Release artifacts

The working manifest uses `unreleased` until a release commit exists. Build an artifact from that commit by passing its full SHA:

```powershell
pwsh ./scripts/New-ReleaseArtifact.ps1 -SourceRevision <40-character-commit-sha>
```

The command requires a committed Git `HEAD`, verifies the supplied revision, refuses uncommitted release inputs, validates the staged payload, embeds immutable revision URLs, and creates a deterministic ZIP plus SHA256 sidecar under the ignored `artifacts/` directory. Release files are generated locally and are not committed.

## Licensing

The files under `data/` and the project documentation are licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Scripts and JSON Schemas are licensed under the MIT License. See [LICENSE.md](LICENSE.md).
