# Changelog

All notable baseline releases will be documented here.

The project uses semantic versioning for the data contract:

- Patch releases correct or refresh data without adding fields.
- Minor releases add backward-compatible fields, tables, sources, or taxonomy entries.
- Major releases change or remove existing contract fields.

## 0.2.0 - 2026-09-22

- Added eight human-reviewed classifications from Azure-Sentinel revision `2e3336d0520681d277d1fa7b2fbc7730242f1d88`.
- Recommended the Data Lake tier for Tailscale device and network data and UniFi Site Manager inventory, metrics, and configuration data.
- Added exact Azure-Sentinel provenance for the reviewed classifications.
- Added catalog-backed field analysis so unclassified standard tables remain discoverable without admitting arbitrary KQL identifiers.
- Added a structured adapter for importing approved classification-review decisions.
- Added checksum-pinned Minimum, Recommended, and Plus pre-made baseline layers migrated from log-baseline-web.

## 0.1.0 - 2026-09-13

The manifest reserves data version `0.1.0` for the first release. Release artifacts replace the working `unreleased` revision with the full source commit SHA.

- Migrated the Log Horizon baseline data without semantic changes.
- Added schemas, provenance, checksums, validation tests, deterministic release packaging, contribution guidance, and CI.
