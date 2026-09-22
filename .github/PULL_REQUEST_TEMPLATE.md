## Summary

<!-- Describe the change and why it is needed. -->

## Evidence

<!-- Link public documentation or repositories supporting data changes. -->

## Type of change

- [ ] Classification or recommendation correction
- [ ] New or removed table
- [ ] Source or plan metadata update
- [ ] Taxonomy update
- [ ] Schema or tooling change
- [ ] Documentation update
- [ ] Breaking contract change

## Validation

- [ ] `pwsh ./scripts/Test-Baseline.ps1` passes.
- [ ] `pwsh ./tests/Test-Baseline.Tests.ps1` passes.
- [ ] Existing flat Log Horizon fields remain compatible.
- [ ] Generated files were updated through their source adapter.
- [ ] New or changed recommendations reference an entry in `data/sources.json`.
- [ ] Baseline recommendations have explicit human decisions; uncertain tables are documented or deferred.
- [ ] No secrets, tenant identifiers, customer data, or private telemetry are included.
- [ ] Environment-specific context is not presented as a universal recommendation.
