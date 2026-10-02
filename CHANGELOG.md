# Changelog

All notable baseline releases will be documented here.

The project uses semantic versioning for the data contract:

- Patch releases correct or refresh data without adding fields.
- Minor releases add backward-compatible fields, tables, sources, or taxonomy entries.
- Major releases change or remove existing contract fields.

## 0.3.0 - Unreleased

- Separated security value from storage tier. `classification` follows value rules C1-C9 mapped to ASD's priority logs for SIEM ingestion and CISA's M-21-31 guidance. `recommendedTier` follows tier rules T1-T5. Volume no longer sets the classification.
- Reclassified 89 tables. 88 moved to primary, including all Entra ID sign-in log types, firewall, DNS, proxy, flow, storage access, database audit, security tool admin audit, and collaboration audit tables. `DnsInventory` moved to secondary.
- Moved DNS and network session tables (`DnsEvents`, `ASimDnsActivityLogs`, `ASimNetworkSessionLogs`, `ASimWebSessionLogs`, and others) from Analytics to Data lake.
- Recommended Analytics for 40 tables that previously recommended Data lake but do not support the Auxiliary/Lake plan. Validation now rejects that combination.
- Added optional `volumeClass` and `volumeDriver` fields (schema 1.2.0) and populated them for every classification.
- Added optional `valueRule` (C1-C9) and `tierRule` (T1-T5) fields (schema 1.2.0) and populated them for every classification. Validation enforces that each pair matches `classification`, `recommendedTier`, and plan support.
- Added 16 tables: Defender for Endpoint custom data collection, Intune, and Azure VMware Solution.
- Added provenance records for ASD, CISA, Microsoft Sentinel data lake documentation, the Azure Monitor table reference, and the volume model.
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
