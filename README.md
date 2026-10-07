# Microsoft Sentinel Log Baseline

[![Validate baseline](https://github.com/lnfernux/log-baseline/actions/workflows/validate.yml/badge.svg)](https://github.com/lnfernux/log-baseline/actions/workflows/validate.yml)
[![Data version](https://img.shields.io/badge/data-0.4.0-00cc00)](CHANGELOG.md)
[![Schema version](https://img.shields.io/badge/schema-1.3.0-475569)](data/manifest.json)
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
| `shared-table-sources.json` | Classifications for sources inside shared tables such as `CommonSecurityLog` and `Syslog`. |
| `basic-plan-tables.json` | Built-in tables supporting the Basic plan. |
| `auxiliary-plan-tables.json` | Built-in tables supporting the Auxiliary plan. |
| `implicit-consumers.json` | Non-KQL Sentinel consumers and platform tables. |
| `high-value-fields.json` | Field recommendations and split hints. |
| `field-frequency-stats.json` | Derived field usage from public Sentinel rules. |
| `custom-classifications-example.json` | Log Horizon-compatible override examples. |
| `taxonomy.json` | The generic Domain > Log type mapping used by the explorer. |
| `sources.json` | Versioned provenance records referenced by classifications and generated datasets. |

The [`baselines/`](baselines/) folder contains the cumulative Minimum, Recommended, and Plus layers originally defined by log-baseline-web. Run `pwsh ./scripts/Update-PreMadeBaselines.ps1` after classification changes. The generated layers are schema-validated, checksum-pinned in the manifest, and included in release artifacts.

The initial data was migrated without semantic changes from [Log Horizon](https://github.com/lnfernux/log-horizon).

### Data accuracy

> [!WARNING]
> The dataset uses AI-assisted research and classification with human review. AI output, public documentation, upstream detection content, and tenant observations can all be incomplete or outdated. Validate recommendations against your environment before using them.

**The repository was created and is maintained with AI assistance:**

1. Mapped out all current log sources from the data sources below (data connectors reference, the Azure-Sentinel repo and a live tenant).
2. Author (that's me, hi) mapped out a set of around 50 connectors in the JSON-schema manually and provided context as to why I chose that.
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

## Classification rules

Each table gets two independent recommendations. `classification` records security value. `recommendedTier` records where the data should live, based on volume and how detections use it. Volume never changes the classification. Every record stores the rule behind each recommendation in `valueRule` (C1-C9) and `tierRule` (T1-T5), and `scripts/Test-Baseline.ps1` rejects pairings that contradict the matrix below.

The value rules apply two select public guidance documents for simplicity's sake:

- **ACSC**: [Australian Cyber Security Centre (ACSC) priority logs for SIEM ingestion](https://www.cyber.gov.au/business-government/detecting-responding-to-threats/event-logging/implementing-siem-soar-platforms/priority-logs-for-siem-ingestion-practitioner-guidance), sections 1 to 14.
- **CISA**: [CISA guidance for implementing M-21-31](https://www.cisa.gov/sites/default/files/2023-02/TLP%20CLEAR%20-%20Guidance%20for%20Implementing%20M-21-31_Improving%20the%20Federal%20Governments%20Investigative%20and%20Remediation%20Capabilities_.pdf), the prioritized event types 1 to 8.

Both documents rank logs for collection. Neither prescribes a storage tier. ACSC notes that firewall and DNS volume *"may overshadow the importance of the information received"* and discourages using a SIEM as the central store for all logs. The tier rules come from that point and from documented Microsoft Sentinel data lake behavior.

### Value rules

| Rule | Primary when the table records | ACSC | CISA |
| --- | --- | --- | --- |
| C1 | Detections, alerts, incidents, security findings (vulnerability and posture findings), and detection pipeline health | 1 EDR detections, 2 IDS/IPS alerts, risk considerations (check the health of priority sources) | - |
| C2 | Authentication and credential use, including non-interactive, service principal, managed identity, federated, VPN, NAC, and password vault access | 2 VPN/NAC, 3-4 domain controllers, 8 Entra sign-in logs | 1b |
| C3 | Identity, privilege, and configuration changes: directory audit, cloud control plane, RBAC, Kubernetes API, security tool administration, virtualisation and MDM management | 2 configuration changes, 6, 8, 9, 11 | 1a, 4a, 5a, 6a-6b, 8a |
| C4 | Endpoint and operating system activity: process, script, logon, service, scheduled task, registry, file | 1, 5, 6, 13, 14 | 2a-2j |
| C5 | Network activity: firewall, DNS, DHCP, web proxy, flow, load balancer, mail gateway and message flow, web access to internet-facing services | 2, 8, 12 | 3a-3c |
| C6 | Collaboration, SaaS, and business application activity | 8 Office 365 and Google Workspace | 7a |
| C7 | Data access: storage, database audit and queries, API data access, directory queries, and audit log access | 8 storage and cloud API logs, 10 databases, 6/9/10/14 audit log access | - |
| C8 | Behavior analytics, threat intelligence, and identity inventory used by detections | - | 1a identity attributes |
| C9 | Secondary: health, performance, metrics, diagnostics, inventory, posture snapshots, reference data, and aggregates derived from another collected table | - | - |

C8 and the detection pipeline health part of C1 are baseline judgment. Neither document names UEBA or Sentinel health tables. ACSC mentions threat intelligence only as something to correlate high-volume firewall logs against, and its risk considerations say the health of higher priority data sources should be checked regularly.

### Tier rules

The first matching rule wins.

| Rule | Tier | When |
| --- | --- | --- |
| T5 | Analytics | The table would otherwise get T3 or T4, but it has no Auxiliary/Lake support. See plan support below. |
| T1 | Analytics | Generic detections need near-real-time matching on single events. |
| T2 | Analytics | Low-volume enrichment or join target for analytics-tier detections or Sentinel features. |
| T3 | Data lake | Primary, high or very-high volume, and the generic detection use is aggregation, threat-intelligence matching, baselining, or investigation. |
| T4 | Data lake | Low-touch context queried during investigations rather than for alerting. |

T3 relies on [KQL jobs](https://learn.microsoft.com/azure/sentinel/datalake/kql-jobs) and summary rules. Data lake ingestion latency is up to 15 minutes, a scheduled job starts at least 30 minutes after it is created, and a tenant can run 5 jobs concurrently with 100 enabled. Tables where some rows need T1 and the rest fit T3 are split candidates. A [split transformation](https://learn.microsoft.com/azure/sentinel/transformation-filter-split#split-transformations) keeps the matching rows in Analytics, where they are also mirrored to the lake, and sends the rest to a separate `_SPLT` table in the lake.

Analytic rules do not force the analytics tier. A KQL job or summary rule can promote the subset a detection needs from the lake into an analytics table. Rule usage is evidence for the tier decision, not the decision itself: T1 needs single-event matching that cannot wait for lake latency, and T2 needs the table to be a join or lookup target for analytics-tier detections.

### Plan support

The data lake tier does not support every table. T3 and T4 apply only when the [Azure Monitor table feature matrix](https://learn.microsoft.com/azure/azure-monitor/reference/tables-features) lists Auxiliary/Lake support for the table (`data/auxiliary-plan-tables.json`), or when the table is a DCR-based custom table (`_CL`). Every other table that would land in the lake gets `analytics` with rule T5. For those tables, long-term retention uses the mirrored lake copy, and volume is reduced with ingest-time filtering or a narrower collection scope. `scripts/Test-Baseline.ps1` rejects a `datalake` recommendation for a built-in table without Auxiliary/Lake support.

Microsoft documents that [DCR-based custom tables support all plans](https://learn.microsoft.com/azure/azure-monitor/logs/logs-table-plans#set-the-table-plan). Classic custom tables created by the HTTP Data Collector API are not DCR-based, so [migrate them to DCR-based tables](https://learn.microsoft.com/azure/azure-monitor/logs/custom-logs-migrate) before planning a move to the lake. Support for the HTTP Data Collector API ended on September 14, 2026.

### Classification and tier matrix

| | Analytics | Data lake |
| --- | --- | --- |
| **Primary** | **C1-C8 with T1, T2, or T5.** High-value events that need near-real-time detection, low-volume join targets, or high-value tables the lake cannot hold. `SigninLogs` (C2 T1), `SecurityAlert` (C1 T1), `IdentityInfo` (C8 T2), `Event` (C4 T5). | **C1-C8 with T3 or T4.** High-value events at high volume detected through aggregation or jobs, or high-value context used mainly in investigations. `AADNonInteractiveUserSignInLogs` (C2 T3), `AZFWNetworkRule` (C5 T3), `StorageBlobLogs` (C7 T3), `ASimDhcpEventLogs` (C5 T4). |
| **Secondary** | **C9 with T2 or T5.** Context that analytics-tier detections or Sentinel features join against, or context tables the lake cannot hold. `Watchlist` (C9 T2), `ExposureGraphNodes` (C9 T2), `Perf` (C9 T5), `Heartbeat` (C9 T5). | **C9 with T4.** Operational and reference context. `DeviceInfo`, `DeviceTvmSoftwareInventory`, `AZFWFatFlow`, `StorageQueueLogs` (all C9 T4). |

Secondary tables never use T1 or T3.

### Sources inside shared tables

Network, security, and OT devices that send CEF or Syslog share `CommonSecurityLog` and `Syslog`, and most of them are queried through a parser. One record per table cannot describe them. `shared-table-sources.json` classifies each source with the same value, tier, volume, and retention fields as a table, plus:

- `table`: the shared table.
- `filter`: a KQL predicate that selects the source's rows, such as `DeviceVendor =~ "radiflow"`.
- `parser`: the parser alias, when rules use one.
- `splitHints`: optional, for data lake sources. Each hint is a KQL predicate for the rows of that source to keep in Analytics, such as threat logs and denied traffic.

The `CommonSecurityLog` and `Syslog` records in `log-classifications.json` describe the remainder: rows that match no source in `shared-table-sources.json`. Source records take precedence for their own rows. Table-level split hints in `high-value-fields.json` apply to the remainder only.

A per-source tier is applied with a [split transformation](https://learn.microsoft.com/azure/sentinel/transformation-filter-split#split-transformations) on the shared table. A table has one split rule. Rows that match its condition go to Analytics and are mirrored to the data lake. All other rows go to `<Table>_SPLT` in the data lake only. Build one condition per shared table from the sources deployed in the tenant:

```kql
// Analytics sources keep all their rows in Analytics.
(<analytics source filter>) or (<analytics source filter>)
// Data lake sources keep only the rows their split hints select.
or ((<data lake source filter>) and ((<hint>) or (<hint>)))
// Remainder, only when the table record recommends analytics.
or case((<any source filter>) or (<any source filter>), false, true)
```

An analytics source that is left out of the condition moves to the data lake. A data lake source without split hints adds nothing. Filters and hints with a top-level `or` are stored in parentheses, and validation rejects them otherwise. Split hints guard negated predicates with `isnotempty()`, because `!~` is true for empty values. Filters can overlap, such as `linux-auth` and process-based sources that log to the `auth` facility. Overlap does not change the split condition, but per-source volume counts the shared rows once for each source. Filters and split hints use only [operators that transformations support](https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-transformations-kql#supported-scalar-operators), so `in~` and `has_any` are written out with `or`.

Retention is set per table, not per source. All data lake rows land in one `<Table>_SPLT` table, so set its retention to the highest `recommendedRetentionDays` among the deployed data lake sources and the remainder when it is data lake. Set the shared table's retention to the highest value among the deployed analytics sources and the remainder when it is analytics. Per-source retention is advisory inside a shared table.

Plan support comes from the shared table. Per-source volume comes from summing `_BilledSize` over the filter, not from `Usage`. `New-FieldAnalysis.ps1 -SharedSourceCandidatesOutputPath` lists candidate sources from parser filters and from vendor filters in rules.

### Defender-native tables

`defenderNative: true` marks tables that are queryable in Defender advanced hunting without ingestion into a workspace ([schema reference](https://learn.microsoft.com/defender-xdr/advanced-hunting-schema-tables)). Some of them, such as `CloudKeyVaultEvents` and `EntraIdSignInEvents`, have no Log Analytics table at all.

`xdrStreamable: true` means the table is listed for the [Microsoft Defender XDR connector](https://learn.microsoft.com/azure/sentinel/connect-microsoft-365-defender) in Microsoft Sentinel. It does not describe the [streaming API](https://learn.microsoft.com/defender-xdr/supported-event-types).

The tier and retention fields describe the Microsoft Sentinel workspace model. In a Defender-native deployment, including [ISOC in Microsoft Defender](https://learn.microsoft.com/defender-xdr/isoc-overview), the native data is available for the included retention window without ingestion. The window is 90 days for Microsoft Defender data, Azure Activity, and Office 365 Activity ([announcement](https://techcommunity.microsoft.com/blog/microsoftthreatprotectionblog/integrated-security-operations-center-in-microsoft-defender/4559097)). Consumers apply that window as context: the tier recommendation covers retention beyond it, and a missing `Usage` row for a Defender-native table is expected, not a gap.

### Volume model

`volumeDriver` records what one row represents. `volumeClass` is the expected volume relative to other tables where the source is deployed. **Both are based on judgment and experience**, not broadly measured tenant volume. [Log Horizon](https://github.com/lnfernux/log-horizon) measures actual ingestion from the `Usage` table.

| Driver | Default class | Driver | Default class |
| --- | --- | --- | --- |
| `alert` | low | `connection` | very-high |
| `admin-action` | low | `dns-query` | very-high |
| `snapshot` | low | `web-request` | very-high |
| `sign-in` | medium | `token-sign-in` | high |
| `activity` | medium | `endpoint-event` | high |
| `message` | medium | `os-event` | high |
| `indicator` | medium | `api-request` | high |
| `data-access` | high | `metric` | high |
| `application-trace` | high | | |

Per-table overrides adjust the class where the default does not fit. For example, `AADNonInteractiveUserSignInLogs` is very-high, and WAF tables are high because they usually log matched requests. An override is a reviewer judgment, and records do not store a reason for it.

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
	-TableCatalogPath ./.github/table-catalog/snapshot.json `
	-TableSchemaPath ./tmp/table-metadata.json `
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

`-TableSchemaPath` takes a saved copy of the [Log Analytics metadata API](https://api.loganalytics.io/v1/metadata) response. Fields for tables with a known schema are limited to real columns, which removes aliases, calculated fields, and columns from joined tables. Tables without a known schema, mostly `_CL`, are listed in `unverifiedTables`. Only classified tables, catalog tables, and `_CL` tables count as tables.

Rules that call a parser (a `FunctionAlias` under a `Parsers` folder) are attributed to the parser, not to a table. The `parsers` section maps each parser to its source tables, the source columns it reads (when the source schema is known), and the parsed fields that rules use. Ingestion-time transformations work on source columns, so `perTable` and `high-value-fields.json` stay keyed by table.

The initial field-analysis snapshot predates revision capture. Its provenance record states that limitation explicitly. Future imports require the exact Azure-Sentinel commit.

Import explicitly approved classification decisions from a human review:

```powershell
pwsh ./scripts/Import-ClassificationReview.ps1 `
	-CandidatesPath ./artifacts/baseline-review/<review>/candidates.json `
	-DecisionsPath ./artifacts/baseline-review/<review>/approved-decisions.json `
	-AzureSentinelRevision <40-character-commit-sha> `
	-ObservedOn <date> `
	-DataVersion <next-version>
```

The importer accepts only `accept` and `edit` decisions, applies structured edits, rejects duplicate tables and unknown fields, updates provenance and version metadata, regenerates pre-made baselines and checksums, and validates the result. Candidates with `status: changed` replace the existing record in place. All other candidates must be new tables. `-AzureSentinelRevision` is optional and updates the Azure-Sentinel provenance record only when supplied. `-ReviewedSourcesPath` adds or replaces source records by `id`.

### Table catalog review

The weekly `table-catalog-review.yml` workflow compares the anonymous Azure Monitor metadata API with a versioned source snapshot. It opens or updates a draft pull request containing only the refreshed snapshot and a review report. It never edits classifications. Source failures create or update a separate issue and cannot be interpreted as table removals.

The first successful run proposes the initial snapshot. Later runs report additions and catalog disappearances for the two [Baseline Curator](.github/agents/baseline-curator.agent.md) flows: automatic proposal generation or one-table-at-a-time human review.

## Validation

> [!TIP]
> Run all commands before proposing a change. CI executes the same checks on Windows and Linux.

Run from the repository root:

```powershell
pwsh ./scripts/Test-Baseline.ps1
pwsh ./tests/Test-Baseline.Tests.ps1
pwsh ./tests/Test-FieldAnalysis.Tests.ps1
pwsh ./tests/Test-ClassificationReview.Tests.ps1
pwsh ./tests/Test-TableCatalog.Tests.ps1
```

Validation covers JSON parsing and schemas, required values, unique table names, lifecycle references, plan lists, pre-made baseline layers, cross-file relationships, and manifest checksums.

## Release artifacts

The working manifest uses `unreleased` until a release commit exists. Build an artifact from that commit by passing its full SHA:

```powershell
pwsh ./scripts/New-ReleaseArtifact.ps1 -SourceRevision <40-character-commit-sha>
```

The command requires a committed Git `HEAD`, verifies the supplied revision, refuses uncommitted release inputs, validates the staged payload, embeds immutable revision URLs, and creates a deterministic ZIP plus SHA256 sidecar under the ignored `artifacts/` directory. Release files are generated locally and are not committed.

## Licensing

The files under `data/` and the project documentation are licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Scripts and JSON Schemas are licensed under the MIT License. See [LICENSE.md](LICENSE.md).
