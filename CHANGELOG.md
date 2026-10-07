# Changelog

All notable baseline releases will be documented here.

The project uses semantic versioning for the data contract:

- Patch releases correct or refresh data without adding fields.
- Minor releases add backward-compatible fields, tables, sources, or taxonomy entries.
- Major releases change or remove existing contract fields.

## 0.4.0 - 2026-10-06

- Added optional `defenderNative` (schema 1.3.0) and set it on 67 tables queryable in Defender advanced hunting without ingestion. The README documents how consumers apply Defender and ISOC included retention as deployment context.
- Added 40 tables: Defender XDR tables including Teams message security, cloud infrastructure, behaviors, and the `EntraId*SignInEvents` tables, plus Entra Domain Services, Application Gateway for Containers, Cloud HSM, Arc-enabled Kubernetes audit, App Service file and antivirus audit, and partner alert tables. `CloudKeyVaultEvents` is classified from the Defender portal schema only and is not publicly documented.
- Corrected table names that were parser aliases or missing `_CL`: `BitwardenEventLogs_CL`, `IllumioInsightsGraph_CL`, `TheHiveData_CL`, `TrellixEvents_CL`, and `ImpervaWAFCloudV2_CL` (previously `ImpervaWAFCloud`). Removed `CrowdStrikeReplicatorV2`, which is a parser over Falcon Data Replicator tables.
- Added 19 CrowdStrike tables: the built-in API tables `CrowdStrikeCases`, `CrowdStrikeDetections`, `CrowdStrikeIncidents`, `CrowdStrikeHosts`, and `CrowdStrikeVulnerabilities`, the Falcon Data Replicator S3 connector custom tables (`CrowdStrike_*_Events_CL`, `CrowdStrike_Secondary_Data_CL`), and the legacy FDR v2 custom ASIM tables (`ASim*_CL`).
- Reclassified `prancer_CL` as primary (C1). Its analytic rules alert directly on posture findings.
- Corrected `CloudAuditEvents` to Defender for Cloud control-plane audit (C3) and the `IdentityLogonEvents` description.
- Set `isFree` to false for `SecurityIncident`, `Watchlist`, and `ConfidentialWatchlist`. No Microsoft documentation lists them as free.
- Reclassified `AzureDiagnostics` and `OracleWebLogicServer_CL` as primary (C5). Moved `DeviceInfo` and `Tailscale_Devices_CL` to analytics (T2) because analytic rules join against them.
- Reduced retention from 365 to 180 days for 24 secondary (C9) tables.
- Refreshed plan support from Learn (observed 2026-10-06). `Update-PlanTables.ps1` now sorts ordinally.
- `New-FieldAnalysis.ps1` takes `-TableSchemaPath` and keeps only real columns for tables with a known schema. It no longer treats names from the existing field files as tables, and it maps rules that call parsers to a new `parsers` section with source tables and source columns. `field-frequency-stats.json` gains optional `unverifiedTables` and `parsers` fields.
- Replaced the field statistics migrated from Log Horizon (April 2026, 3,858 rules) with a schema-filtered analysis of Azure-Sentinel `2e3336d` (5,158 queries, 145 tables, 115 parsers). `AzureDiagnostics` stays unverified because its columns vary by resource.
- Cleaned curated high-value fields: removed 56 entries keyed by parser aliases and dropped fields that are not columns of the table (2,520 to 1,134 curated fields). Added 42 mined entries. Fixed the `WindowsFirewall` split hint, which referenced a non-existent `Direction` column.
- Renamed classified parser aliases to their tables: `ElasticAgentEvent` to `ElasticAgentLogs_CL`, `OktaSSO` to `OktaV2_CL`, and `Corelight` to `Corelight_CL`. Moved `ForescoutEvent` and `RadiflowEvent` to `shared-table-sources.json`, because they are sources inside `Syslog` and `CommonSecurityLog`.
- Added `shared-table-sources.json` and its schema for sources inside shared tables, with a row filter, optional parser, and the same classification fields as tables. Validation checks the shared table, rule pairings, and plan support. `New-FieldAnalysis.ps1` can write source candidates from parser and rule filters.
- Added 55 human-reviewed shared-table sources, 39 in `CommonSecurityLog` and 16 in `Syslog`, including a Linux authentication source for the `auth` and `authpriv` facilities. Filters use case-insensitive `=~` and there is one entry per product. Traffic and proxy sources use C5 on the data lake (T3, 180 days), and alert sources use C1 in analytics (T1, 365 days).
- Added optional `splitHints` to shared-table sources, with hints for PAN-OS, Cisco ASA and FTD, Zscaler, Infoblox, and vArmour. Validation rejects split hints on Analytics sources and filters or hints with operators that transformations do not support, such as `in~` and `has_any`. The README shows how to combine all sources on a shared table into its single split condition, and that retention is set per table, not per source. The `CommonSecurityLog` and `Syslog` records now classify only rows that match no source.
- Rewrote 9 table split hints in `high-value-fields.json` (`AuditLogs`, `AzureActivity`, `AzureDiagnostics`, `CommonSecurityLog`, `DeviceFileEvents`, `DeviceNetworkEvents`, `DeviceProcessEvents`, `OfficeActivity`, `W3CIISLog`) to replace `has_any` and `in~` with `or`. Validation applies the same operator check to table split hints.
- Added 238 Corelight v3 tables (`Corelight_v3_*_CL`) from the Corelight Connector Exporter. Traffic, aggregate, and authentication protocol logs use C5 on the data lake (T3, 180 days). OT protocol logs use C5 IoT/OT Security (T3, 180 days), and other protocol logs use T4 with 90 days. Detection logs such as `notice`, `intel`, and `suricata_corelight` use C1 in analytics (T1, 365 days), except `suricata_eve` (T3). Inventory, `corelight_ad_*` anomaly detection baseline, and sensor health logs are secondary (C9, T4, 90 days). `Corelight_CL` is now legacy, replaced by the v3 traffic and `notice` tables. Added the 121 Corelight v2 tables (`Corelight_v2_*_CL`) as legacy, each replaced by its v3 table.
- Added the five CrowdStrike API `*V2_CL` tables that the CCF connector writes since solution 3.4.0. They copy the V1 classifications. `CrowdStrikeVulnerabilitiesV2_CL` and `CrowdStrikeVulnerabilities` are C3. The V1 tables `CrowdStrikeAlerts`, `CrowdStrikeCases`, `CrowdStrikeDetections`, `CrowdStrikeHosts`, and `CrowdStrikeVulnerabilities` are now legacy.
- Renamed records change `tableName` for consumers that pinned the old names. No contract field changed.
- Split hints guard negated action predicates with `isnotempty()`, so rows without an action no longer stay in Analytics. Filters and hints with a top-level `or` are stored in parentheses, and validation rejects them otherwise. The `linux-auth` source is high volume because cron PAM sessions log to `authpriv`.
- `New-FieldAnalysis.ps1` no longer drops rule fields whose casing differs from the schema, and it uses the schema spelling for known columns and the most frequent spelling for category and universal defaults. Output no longer depends on hash order.
- Defined `xdrStreamable` in the README as listed for the Microsoft Defender XDR connector in Microsoft Sentinel. All 21 flagged tables match the connector page, including `DeviceFileCertificateInfo`.
- Verified `EntraIdSignInEvents` fields against the Defender XDR schema reference. Removed 9 high-value fields that are not columns of the table, such as `ActionType` and `RawEventData`, and moved the table out of `unverifiedTables`.

## 0.3.0 - 2026-10-02

- Separated security value from storage tier. `classification` follows value rules C1-C9 mapped to the Australian Cyber Security Centre (ACSC) priority logs for SIEM ingestion and CISA's M-21-31 guidance. `recommendedTier` follows tier rules T1-T5. Volume no longer sets the classification.
- Reclassified 89 tables. 88 moved to primary, including all Entra ID sign-in log types, firewall, DNS, proxy, flow, storage access, database audit, security tool admin audit, and collaboration audit tables. `DnsInventory` moved to secondary.
- Moved DNS and network session tables (`DnsEvents`, `ASimDnsActivityLogs`, `ASimNetworkSessionLogs`, `ASimWebSessionLogs`, and others) from Analytics to Data lake.
- Recommended Analytics for 40 tables that previously recommended Data lake but do not support the Auxiliary/Lake plan. Validation now rejects that combination.
- Added optional `volumeClass` and `volumeDriver` fields (schema 1.2.0) and populated them for every classification.
- Added optional `valueRule` (C1-C9) and `tierRule` (T1-T5) fields (schema 1.2.0) and populated them for every classification. Validation enforces that each pair matches `classification`, `recommendedTier`, and plan support.
- Added 16 tables: Defender for Endpoint custom data collection, Intune, and Azure VMware Solution.
- Added provenance records for ACSC, CISA, Microsoft Sentinel data lake documentation, the Azure Monitor table reference, and the volume model.
- The review importer now replaces changed records, adds reviewed source records, and regenerates the pre-made baselines.
- The data contract is backward compatible: the new fields are optional and no existing field changed. The 89 reclassifications and 78 tier changes do change Log Horizon's per-table recommendations once it vendors 0.3.0.

## 0.2.0 - 2026-09-22

- Added 29 human-reviewed classifications from Azure-Sentinel revision `2e3336d0520681d277d1fa7b2fbc7730242f1d88`.
- Recommended the Data Lake tier for Tailscale device and network data and UniFi Site Manager inventory, metrics, and configuration data.
- Added exact Azure-Sentinel provenance for the reviewed classifications.
- Added catalog-backed field analysis so unclassified standard tables remain discoverable without admitting arbitrary KQL identifiers.
- Added a structured adapter for importing approved classification-review decisions.
- Added checksum-pinned Minimum, Recommended, and Plus pre-made baseline layers migrated from log-baseline-web.

## 0.1.0 - 2026-09-13

The manifest reserves data version `0.1.0` for the first release. Release artifacts replace the working `unreleased` revision with the full source commit SHA.

- Migrated the Log Horizon baseline data without semantic changes.
- Added schemas, provenance, checksums, validation tests, deterministic release packaging, contribution guidance, and CI.
