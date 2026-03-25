---
feature: "engine clustering"
slug: "engine-clustering"
created: "2026-03-20"
status: "scoped"
---

# Feature Brief — engine-clustering

## Summary
Add cluster membership and table ownership capabilities to jlsm-engine.
Multiple engine instances discover each other via a pluggable SPI, form a
cluster with split-brain detection, and automatically balance table and
partition ownership across members. Queries against partitioned tables are
scattered to owning nodes and gathered into a unified result. When a node
becomes unavailable, the cluster serves partial results from surviving
nodes and rebalances ownership after a configurable grace period.

## Actors
- Engine instances (peers — no leaders)
- Application code (starts engines, configures discovery, issues queries)
- Discovery SPI implementations (resolve cluster members)
- Transport abstraction (delivers messages between nodes)

## Inputs
- Cluster configuration: discovery provider, grace period, transport
- Engine lifecycle events: join, leave, failure detection
- Table/partition metadata: which tables exist, partition schemes

## Outputs / Side Effects
- Consistent cluster membership view across all live nodes
- Table/partition ownership map (which node owns what)
- Scatter-gather query execution across partition owners with merged results
- Query routing: direct table operations to the owning node
- Rebalancing on membership changes (after grace period for departures)
- Partial results when some owners are unavailable

## Business Rules
- No leaders — all nodes are peers
- Split-brain detection: nodes must agree on membership; partitioned
  minorities must detect they are split and act accordingly
- Grace period on node departure: configurable delay before rebalancing
  to tolerate rolling restarts
- After grace period expires, departed node is treated as new if it returns
- Unavailable partitions reduce result completeness but do not block queries
- Table rebalancing is automatic — no manual placement
- Queries on partitioned tables scatter to all partition owners and gather
  results into a single unified response

## Error Cases
- Split-brain detected: minority partition must stop serving affected
  tables or mark results as potentially inconsistent
- Discovery failure: engine should be able to operate standalone until
  discovery succeeds
- Transport failure between specific nodes: treat as node unavailability
  for routing purposes
- Partial scatter-gather: if some partition owners are unavailable, return
  results from reachable owners with indication of incompleteness

## Explicit Out of Scope
- Leader election and automatic failover/replication
- Data replication between nodes
- Built-in network transport (NIO layer is future work)

## Acceptance Criteria
- Multiple engines in the same JVM can discover each other, form a
  cluster, and agree on membership
- Split-brain scenario is detected and handled safely
- Tables are automatically distributed across cluster members
- Partitioned tables have per-partition ownership tracked and routable
- Queries on partitioned tables scatter-gather across owners and return
  merged results
- Node departure triggers rebalancing after grace period
- Node returning after grace period is treated as a new member
- Partial results are served when some nodes are unavailable, with
  indication of which partitions were missing
- Discovery and transport are SPI-based abstractions

## Open Assumptions
- The in-process database engine feature (currently at planning stage)
  will land first and provide the engine API this builds on
- Consistent hashing or similar is acceptable for partition assignment
  (specific algorithm TBD during planning)

## Research Commissions
None — no research signals identified during scoping.

## Performance Expectations
- Membership protocol should converge quickly (sub-second in-JVM,
  bounded time over network in future)
- Rebalancing should not block ongoing queries on unaffected tables
- Ownership lookups must be fast (routing is on the query hot path)
- Scatter-gather should execute partition queries concurrently

## Project Context
- Language: Java 25 (Amazon Corretto toolchain)
- Framework: none — pure library
- Test framework: JUnit Jupiter (JUnit 5)
