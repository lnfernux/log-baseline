# Microsoft Sentinel Log Baseline

This repository contains a generic starting baseline for Microsoft Sentinel log sources. It classifies tables by security value and recommends an ingestion tier and retention period.

Context takes precedence over this baseline. A table marked as secondary can still be essential in a specific environment because of deployed detections, regulatory requirements, incident history, or business processes. Treat these recommendations as review inputs, not tenant-specific decisions.

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

The initial data was migrated without semantic changes from [Log Horizon](https://github.com/lnfernux/log-horizon). Log Horizon will consume approved releases as vendored module data, keeping PowerShell Gallery installations self-contained and usable without a network connection.

## Sources

The baseline methodology draws on:

- [ACSC best practices for event logging and threat detection](https://www.cyber.gov.au/sites/default/files/2024-08/best-practices-for-event-logging-and-threat-detection.pdf)
- [ACSC priority logs for SIEM ingestion](https://www.cyber.gov.au/business-government/detecting-responding-to-threats/event-logging/implementing-siem-soar-platforms/priority-logs-for-siem-ingestion-practitioner-guidance)
- [CISA guidance for implementing M-21-31](https://www.cisa.gov/sites/default/files/2023-02/TLP%20CLEAR%20-%20Guidance%20for%20Implementing%20M-21-31_Improving%20the%20Federal%20Governments%20Investigative%20and%20Remediation%20Capabilities_.pdf)
- [CISA Microsoft Expanded Cloud Logs Implementation Playbook](https://www.cisa.gov/sites/default/files/2025-01/microsoft-expanded-cloud-logs-implementation-playbook-508c.pdf)
- [Microsoft Sentinel data connectors reference](https://learn.microsoft.com/azure/sentinel/data-connectors-reference)
- [Microsoft Sentinel tables and connectors reference](https://learn.microsoft.com/azure/sentinel/sentinel-tables-connectors-reference)
- [Azure Monitor table feature matrix](https://learn.microsoft.com/azure/azure-monitor/reference/tables-features)
- [Microsoft Sentinel billing](https://learn.microsoft.com/azure/sentinel/billing)
- [Microsoft Sentinel data tier management](https://learn.microsoft.com/azure/sentinel/manage-data-overview)
- [Azure/Azure-Sentinel](https://github.com/Azure/Azure-Sentinel)
- [MITRE ATT&CK data sources](https://attack.mitre.org/datasources/)
- [NIST SP 800-92](https://csrc.nist.gov/pubs/sp/800/92/final)
- [Google Cloud Audit Logs](https://docs.cloud.google.com/logging/docs/audit)

See the [Log Horizon baseline methodology](https://github.com/lnfernux/log-horizon#how-the-classifications-were-built) for the full original description while the expanded methodology is migrated here.

## Validation

Run from the repository root:

```powershell
pwsh ./scripts/Test-Baseline.ps1
```

Validation covers JSON parsing and schemas, required values, unique table names, lifecycle references, plan lists, cross-file relationships, and manifest checksums.

## Licensing

The files under `data/` and the project documentation are licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Scripts and JSON Schemas are licensed under the MIT License. See [LICENSE.md](LICENSE.md).
