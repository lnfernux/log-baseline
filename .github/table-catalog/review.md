# Microsoft Sentinel table catalog review

Observed: 2026-10-12
Source: https://api.loganalytics.io/v1/metadata
Previous tables: 931
Current tables: 941
Added: 10
Removed from catalog: 0

A table disappearing from this catalog does not prove that the service or table was removed. Confirm every change against public documentation before editing the baseline.

## Added tables

### AgentFabricFlowLogs

- Type: Microsoft
- API state: Any
- Description: Per-connection flow records emitted by Agent Fabric policy enforcement, including source/destination identity, the allow/deny/inspect verdict, protocol, and L7 request shape. Used to build the flow map and live-inspect experiences and to audit policy decisions.

### ASimEmailEventLogs

- Type: Microsoft
- API state: Any
- Description: Microsoft Sentinel normalized email event logs table.

### CallActivityEvents

- Type: Microsoft
- API state: Any
- Description: This table shows information about activities performed during Microsoft Teams calls by Microsoft Defender for Office 365.

### HorizonDBAutovacuumStats

- Type: Microsoft
- API state: Any
- Description: Information related to autovacuum and schema level statistics of an Azure HorizonDB replica.

### HorizonDBPgStatActivitySessions

- Type: Microsoft
- API state: Any
- Description: Session's data collected from PostgreSQL pg_stat_activity system view of an Azure HorizonDB replica. Contains one row per connection referred here as a backend and the data is collected at an interval of 5-minutes.

### HorizonDBQueryStoreQueryText

- Type: Microsoft
- API state: Any
- Description: Query text captured by query store in Azure HorizonDB replica.

### HorizonDBQueryStoreRuntimeStats

- Type: Microsoft
- API state: Any
- Description: Query store runtime statistics related to query execution information of an Azure HorizonDB replica.

### HorizonDBQueryStoreWaitsStats

- Type: Microsoft
- API state: Any
- Description: Query store wait statistics sampled of an Azure HorizonDB replica. Wait event types combine different wait events into buckets by category or type.

### HorizonDBServerLogs

- Type: Microsoft
- API state: Any
- Description: PostgreSQL server logs of an Azure HorizonDB replica.

### HorizonDBTransactionsStats

- Type: Microsoft
- API state: Any
- Description: Remaining transactions and multixact idenfiers for each database of an Azure HorizonDB replica.

## Removed from catalog

None.

## Classification review

- Verify each table against Microsoft Learn and its connector or solution source.
- Separate documented facts from classification judgment.
- Use the baseline curator automatic proposal or human review flow before changing canonical data.
