# Table review example

This example demonstrates the review format. It is not a substitute for current source research.

## SecurityAlert (1/1)

Status: unchanged
Confidence: high
Uncertain: no

### Current

- Classification: `primary`
- Value rule: `C1`
- Category: `Security Alerts`
- Tier: `analytics`
- Tier rule: `T1`
- Volume: `alert` / `low`
- Retention: `365`

### Proposed

No change.

### Documented facts

- The current baseline describes `SecurityAlert` as aggregated security alerts from Microsoft and third-party providers.
- The table is free and platform-owned in the current baseline. Revalidate these properties against current Microsoft Learn documentation during a real review.

### Classification judgment

- Security alerts are direct detection and investigation records: value rule C1 (ACSC 1 EDR detections, ACSC 2 IDS/IPS alerts), so `primary`.
- Interactive triage and correlation need near-real-time access: tier rule T1, so `analytics`. The cell is primary/analytics.
- Recurring investigations support the generic `365`-day retention recommendation.

### Context

- A tenant may retain alerts elsewhere or have regulatory requirements that change retention.

### Open questions

- None after current documentation is verified.

Decision: `accept`, `edit`, `reject`, `defer`, or provide a counterargument.