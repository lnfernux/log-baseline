# Microsoft Sentinel Log Baseline

This repository contains a generic starting baseline for Microsoft Sentinel log sources used by [Log Horizon - Microsoft Sentinel SIEM Log Source Analyzer](https://github.com/lnfernux/log-horizon). 
It's a set of data with tables classified by security value and recommends an ingestion tier and retention period.

**Context always takes precedence over this baseline -**regardless of what this repository says. 

As an example, a table marked as secondary in this baseline can still be essential in a specific environment because of deployed detections, regulatory requirements, incident history, or business processes. Treat these recommendations as a starting point or review inputs, one-size-fits-all best practice (it's not). It's a baseline, not a complete security foundation to lean on alone.

## Data

The canonical files are stored in [`data/`](data/):

- `log-classifications.json` - Sentinel table classifications and recommendations.
- `basic-plan-tables.json` - built-in tables supporting the Basic plan.
- `auxiliary-plan-tables.json` - built-in tables supporting the Auxiliary plan.
- `implicit-consumers.json` - non-KQL Sentinel consumers and platform tables.
- `high-value-fields.json` - field recommendations and split hints.
- `field-frequency-stats.json` - derived field usage from public Sentinel rules.
- `custom-classifications-example.json` - Log Horizon-compatible override examples.
- `taxonomy.json` - the generic Domain > Log type mapping used by the explorer.
- `sources.json` - versioned provenance records referenced by classifications and generated datasets.

The initial data was migrated without semantic changes from [Log Horizon](https://github.com/lnfernux/log-horizon). Log Horizon will consume approved releases as vendored module data, keeping PowerShell Gallery installations self-contained and usable without a network connection.

## Sources

The baseline is created using the following sources:

- [Microsoft Sentinel data connectors reference](https://learn.microsoft.com/azure/sentinel/data-connectors-reference)
- [Microsoft Sentinel tables and connectors reference](https://learn.microsoft.com/azure/sentinel/sentinel-tables-connectors-reference)
- [Azure Monitor table feature matrix](https://learn.microsoft.com/azure/azure-monitor/reference/tables-features)
- [Microsoft Sentinel billing](https://learn.microsoft.com/azure/sentinel/billing)
- [Microsoft Sentinel data tier management](https://learn.microsoft.com/azure/sentinel/manage-data-overview)
- [Azure/Azure-Sentinel](https://github.com/Azure/Azure-Sentinel)

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
pwsh ./scripts/Import-FieldAnalysis.ps1 `
	-FieldFrequencyPath ./tmp/field-frequency-stats.json `
	-HighValueFieldsPath ./tmp/high-value-fields.json `
	-AzureSentinelRevision <40-character-commit-sha> `
	-ObservedOn 2026-09-13
```

The initial field-analysis snapshot predates revision capture. Its provenance record states that limitation explicitly. Future imports require the exact Azure-Sentinel commit.

## Validation

Run from the repository root:

```powershell
pwsh ./scripts/Test-Baseline.ps1
pwsh ./tests/Test-Baseline.Tests.ps1
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
