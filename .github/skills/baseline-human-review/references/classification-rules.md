# Classification rules

These rules operationalize the public sources listed in `README.md`. They produce generic review recommendations, not tenant-specific conclusions.

## Evidence order

1. Microsoft Learn for table purpose, availability, billing, tier support, retention behavior, lifecycle, and platform ownership.
2. Public Azure/Azure-Sentinel content for connector declarations, query usage, detections, hunting coverage, and field references.
3. ACSC, CISA, MITRE ATT&CK, NIST SP 800-92, and the other classification sources in `README.md` for general logging and investigation principles.
4. Existing baseline records as consistency examples, never as proof that a new record is correct.

Record source URLs and observation dates. A missing statement is not evidence for the opposite claim.

## Guidance

The value rules apply two public documents. Both rank logs for collection. Neither prescribes a storage tier.

- **ACSC**: [Australian Cyber Security Centre (ACSC) priority logs for SIEM ingestion](https://www.cyber.gov.au/business-government/detecting-responding-to-threats/event-logging/implementing-siem-soar-platforms/priority-logs-for-siem-ingestion-practitioner-guidance), sections 1 to 14.
- **CISA**: [CISA guidance for implementing M-21-31](https://www.cisa.gov/sites/default/files/2023-02/TLP%20CLEAR%20-%20Guidance%20for%20Implementing%20M-21-31_Improving%20the%20Federal%20Governments%20Investigative%20and%20Remediation%20Capabilities_.pdf), prioritized event types 1 to 8.

Every record stores the rule that placed it: `valueRule` (C1 to C9) and `tierRule` (T1 to T5). Cite both IDs and the matching ACSC section or CISA item in every proposal.

## Classification

Decide security value first. Pick exactly one value rule. When several fit, pick the rule that describes the record type a detection would match on.

| Rule | Classification | The table records | ACSC | CISA |
| --- | --- | --- | --- | --- |
| C1 | primary | Detections, alerts, incidents, security findings (vulnerability and posture findings), and detection pipeline health | 1 EDR detections, 2 IDS/IPS alerts, risk considerations (check the health of priority sources) | - |
| C2 | primary | Authentication and credential use: interactive, non-interactive, service principal, managed identity, federated, VPN, NAC, and password vault access | 2 VPN/NAC, 3-4 domain controllers, 8 Entra sign-in logs | 1b |
| C3 | primary | Identity, privilege, and configuration changes: directory audit, cloud control plane, RBAC, Kubernetes API, security tool administration, virtualisation and MDM management | 2 configuration changes, 6, 8, 9, 11 | 1a, 4a, 5a, 6a-6b, 8a |
| C4 | primary | Endpoint and operating system activity: process, script, logon, service, scheduled task, registry, file | 1, 5, 6, 13, 14 | 2a-2j |
| C5 | primary | Network activity: firewall, DNS, DHCP, web proxy, flow, load balancer, mail gateway and message flow, web access to internet-facing services | 2, 8, 12 | 3a-3c |
| C6 | primary | Collaboration, SaaS, and business application activity | 8 Office 365 and Google Workspace | 7a |
| C7 | primary | Data access: storage, database audit and queries, API data access, directory queries, and audit log access | 8 storage and cloud API logs, 10 databases, 6/9/10/14 audit log access | - |
| C8 | primary | Behavior analytics, threat intelligence, and identity inventory used by detections | - | 1a identity attributes |
| C9 | secondary | Health, performance, metrics, diagnostics, inventory, posture snapshots, reference data, and aggregates derived from another collected table | - | - |

C8 and the detection pipeline health part of C1 are baseline judgment. Neither document names UEBA or Sentinel health tables. ACSC mentions threat intelligence only as something to correlate high-volume firewall logs against, and its risk considerations say the health of higher priority data sources should be checked regularly.

Do not infer `primary` from high query frequency alone. Do not infer `secondary` from low public rule coverage alone. Never use volume or cost to choose `secondary`. Volume belongs in the tier and volume fields.

## Category

Choose exactly one category allowed by `schemas/log-classifications.schema.json`. Select the category that describes the event semantics, not merely the vendor or connector name. If two categories are equally plausible, mark the proposal uncertain and explain the tradeoff.

## Tier

Decide the tier second, in this order. The first matching rule wins.

| Order | Rule | Tier | When |
| ---: | --- | --- | --- |
| 1 | T5 | analytics | The table would otherwise get T3 or T4, but it is a built-in table that `data/auxiliary-plan-tables.json` does not list. The data lake cannot hold it. |
| 2 | T1 | analytics | Generic detections need near-real-time matching on single events. |
| 3 | T2 | analytics | Low-volume enrichment or join target for analytics-tier detections or Sentinel features (identity inventory, threat intelligence, watchlists, reference data). |
| 4 | T3 | datalake | Primary, `volumeClass` high or very-high, and the generic detection use is aggregation, threat-intelligence matching, baselining, or investigation that KQL jobs and summary rules support. |
| 5 | T4 | datalake | Low-touch context queried during investigations rather than for alerting. |

Tier support is a documented platform fact. Security value is a judgment. Keep them separate. Never recommend an unsupported plan. DCR-based custom tables (`_CL`) support all plans. Classic custom tables from the HTTP Data Collector API are not DCR-based, so state in the proposal context that they need migrating to DCR-based tables before a move to the lake. Support for the HTTP Data Collector API ended on September 14, 2026.

For T5 tables, the proposal context states that long-term retention uses the mirrored lake copy and that volume is reduced with ingest-time filtering or collection scope. For T3 tables with some single-event detections, note the split pattern: a split transformation keeps the matching rows in analytics, mirrored to the lake, and sends the rest to a separate `_SPLT` table in the lake.

Data lake constraints for T3: ingestion latency up to 15 minutes, scheduled KQL jobs start at least 30 minutes after creation, 5 concurrent jobs and 100 enabled jobs per tenant, 1-hour query timeout ([KQL jobs](https://learn.microsoft.com/azure/sentinel/datalake/kql-jobs)).

## Classification and tier matrix

Every table lands in one of four cells. `scripts/Test-Baseline.ps1` enforces the rule-to-cell pairing.

| | Analytics | Data lake |
| --- | --- | --- |
| **Primary** | **C1-C8 with T1, T2, or T5.** High-value events that need near-real-time detection, low-volume join targets, or high-value tables the lake cannot hold. Examples: `SigninLogs` (C2 T1), `SecurityAlert` (C1 T1), `IdentityInfo` (C8 T2), `Event` (C4 T5). | **C1-C8 with T3 or T4.** High-value events at high volume detected through aggregation, threat-intelligence matching, or jobs, or high-value context used mainly in investigations. Examples: `AADNonInteractiveUserSignInLogs` (C2 T3), `AZFWNetworkRule` (C5 T3), `StorageBlobLogs` (C7 T3), `ASimDhcpEventLogs` (C5 T4). |
| **Secondary** | **C9 with T2 or T5.** Context that analytics-tier detections or Sentinel features join against, or context tables the lake cannot hold. Examples: `Watchlist` (C9 T2), `ExposureGraphNodes` (C9 T2), `Perf` (C9 T5), `Heartbeat` (C9 T5). | **C9 with T4.** Operational and reference context. Examples: `DeviceInfo` (C9 T4), `DeviceTvmSoftwareInventory` (C9 T4), `AZFWFatFlow` (C9 T4). |

Invalid pairings: C9 with T1 or T3, any value rule with a tier rule that contradicts `recommendedTier`, and T5 on a `_CL` table or a table listed in `data/auxiliary-plan-tables.json`.

## Volume

Set `volumeDriver` to what one row represents and `volumeClass` to the default class for that driver in `README.md`. Override the class only with a stated reason. Both fields are judgment. Never present them as measured volume.

## Retention

Use only `90`, `180`, or `365` days:

- `365`: primary evidence with recurring investigation, identity, control-plane, alert, incident, or regulatory value.
- `180`: primary or strong contextual evidence where medium-term investigation is generally useful.
- `90`: short-lived operational, health, verbose, or replaceable context.

Retention is a generic default. Explicitly state that incident history, regulation, threat model, and business processes can require a different value.

## Other fields

- `isFree`: set only from current Microsoft documentation. Do not infer from similar tables.
- `platform`: set only when the table is platform-owned rather than ordinary connector ingestion.
- `xdrStreamable`: set only with documented Defender XDR streaming support.
- `status` and `replacedBy`: require public lifecycle evidence and must appear together.
- `mitreSources`: include only applicable MITRE ATT&CK data-source identifiers supported by the event semantics.
- `keywords`: use concrete searchable concepts from the table purpose. Avoid generic filler.
- `valueRule` and `tierRule`: required on every canonical record. Set them from the tables above, never from the category name alone. They must agree with `classification` and `recommendedTier`.
- `sourceIds`: every changed recommendation must reference a matching record in `data/sources.json`.

## Generated evidence

Field frequency proves that public queries reference a parsed identifier. It does not prove that the identifier is native to the table or security-relevant. Reject aliases, calculated columns, join suffixes, fields from joined tables, literals, functions, and parser keywords.

High-value fields and split hints require human review. Never invent split hints. Validate manually authored KQL before promotion.

## Confidence and uncertainty

Use `high` when table identity, behavior, and the recommendation are supported by direct current documentation plus consistent public usage.

Use `medium` when the table is identified and documented but part of the recommendation depends on general methodology or incomplete usage evidence.

Use `low` and mark `uncertain` when any of these apply:

- Conflicting sources or unclear lifecycle state.
- Preview behavior that may change.
- Ambiguous table, connector, or field identity.
- Sparse, stale, or parser-contaminated rule evidence.
- Tier, billing, retention, or XDR support is undocumented.
- The generic recommendation changes substantially with tenant context.

Uncertain records default to `defer`. State exactly what evidence would resolve the uncertainty.