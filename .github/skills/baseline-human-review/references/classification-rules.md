# Classification rules

These rules operationalize the public sources listed in `README.md`. They produce generic review recommendations, not tenant-specific conclusions.

## Evidence order

1. Microsoft Learn for table purpose, availability, billing, tier support, retention behavior, lifecycle, and platform ownership.
2. Public Azure/Azure-Sentinel content for connector declarations, query usage, detections, hunting coverage, and field references.
3. ACSC, CISA, MITRE ATT&CK, NIST SP 800-92, and the other classification sources in `README.md` for general logging and investigation principles.
4. Existing baseline records as consistency examples, never as proof that a new record is correct.

Record source URLs and observation dates. A missing statement is not evidence for the opposite claim.

## Classification

Use `primary` when the table directly records security detections, authentication or authorization decisions, control-plane changes, endpoint or network security activity, incidents, or evidence routinely required to investigate a security event.

Use `secondary` when the table mainly provides enrichment, inventory, performance, health, posture, reference, or operational context and is not usually the direct event record for detection or investigation.

Do not infer `primary` from high query frequency alone. Do not infer `secondary` from low public rule coverage alone.

## Category

Choose exactly one category allowed by `schemas/log-classifications.schema.json`. Select the category that describes the event semantics, not merely the vendor or connector name. If two categories are equally plausible, mark the proposal uncertain and explain the tradeoff.

## Tier

Recommend `analytics` when the generic use requires frequent interactive queries, near-real-time detections, alerting, hunting, or short-latency investigation.

Recommend `datalake` when the generic use is predominantly long-term, high-volume, infrequently queried context and the documented table capabilities support that recommendation.

Tier support is a documented platform fact. Security value is a judgment. Keep them separate. Never recommend an unsupported plan.

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