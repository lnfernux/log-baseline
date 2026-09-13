# Changelog

All notable baseline releases will be documented here.

The project uses semantic versioning for the data contract:

- Patch releases correct or refresh data without adding fields.
- Minor releases add backward-compatible fields, tables, sources, or taxonomy entries.
- Major releases change or remove existing contract fields.

## 0.1.0 - 2026-09-13

The manifest reserves data version `0.1.0` for the first release. Release artifacts replace the working `unreleased` revision with the full source commit SHA.

- Migrated the Log Horizon baseline data without semantic changes.
- Added schemas, provenance, checksums, validation tests, deterministic release packaging, contribution guidance, and CI.
