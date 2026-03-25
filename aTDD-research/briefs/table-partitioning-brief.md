---
feature: "table partitioning"
slug: "table-partitioning"
created: "2026-03-16"
status: "scoped"
---

# Feature Brief — table-partitioning

## Summary
Add range-based table partitioning to jlsm-table via a new `PartitionedTable`
that coordinates reads and writes across multiple partitions. Each partition
is a self-contained `JlsmTable` with co-located secondary indices, vector
index, and inverted index. The coordinator holds a range map of partition
descriptors (not direct JlsmTable references) and routes operations based
on key ranges. Vector and full-text queries scatter to all partitions and
merge results. Initial scope: static partition assignment, in-process
execution, with interfaces designed for future remote/networked partitions.

## Actors
- **Library consumer:** configures partition count, key ranges, and schema;
  performs CRUD, property queries, vector search, full-text search, and
  combined queries through the PartitionedTable API
- **PartitionedTable (coordinator):** routes operations to the correct
  partition(s), executes scatter-gather for multi-partition queries,
  merges results (top-k for vector, RRF for hybrid)
- **Partition (node-local JlsmTable):** executes operations on its key range
  with all indices co-located

## Inputs
- Schema (JlsmSchema) + partition configuration (number of partitions,
  key range boundaries)
- CRUD operations: put/get/delete by document key
- Query operations: property predicates, vector similarity, full-text,
  and any combination — same query API as JlsmTable

## Outputs / Side Effects
- Query results: documents matching predicates, ranked by relevance
  (property), similarity (vector), term relevance (text), or fusion (hybrid)
- Partition-local storage: each partition writes to its own LSM-tree,
  WAL, SSTables, and indices under a partition-specific path

## Business Rules
- Key-based operations (put/get/delete) route to exactly one partition
  based on the range map — O(log P) routing where P = partition count
- Property-only queries with a key range predicate route to the minimal
  set of overlapping partitions
- Vector-only, full-text-only, and combined queries scatter to all
  partitions; coordinator merges top-k results
- Each partition is a complete, self-contained JlsmTable — all index
  types (secondary, vector, inverted) co-located with documents
- Partition descriptors include range boundaries and location metadata
  (node ID, epoch) to support future remote partitions

## Error Cases
- Key outside all partition ranges → IllegalArgumentException
- Partition unavailable (future: node down) → IOException with partition ID
- Query timeout on scatter-gather → configurable timeout, partial results
  with indication of which partitions responded

## Explicit Out of Scope
- Dynamic partition split/merge (separate future feature)
- Remote/networked partition communication (separate future feature —
  interface designed but only in-process implementation)
- Replication and consensus (separate decision per ADR-001)
- Cross-partition transactions
- Partition rebalancing / data migration

## Acceptance Criteria
- PartitionedTable supports all JlsmTable query types: property, vector,
  full-text, and combinations
- Key-based CRUD routes to correct partition and returns correct results
- Scatter-gather vector search returns correct top-k across partitions
- Hybrid (vector + property filter) queries execute per-partition and
  merge correctly
- Each partition is independently closeable and uses its own storage path
- Partition routing interface is designed to accept remote implementations
  without changing the coordinator

## Open Assumptions
- Partition count is specified at creation and does not change (static)
- All partitions run in the same JVM for the initial implementation
- Key ranges are contiguous and non-overlapping, covering the full keyspace
- Vector index type per partition matches the table-level configuration

## Performance Expectations
- Key routing: O(log P) via binary search on range map
- Property range query: fan-out proportional to overlapping partitions
- Vector/text/combined query: O(P) scatter-gather, acceptable for P ≤ 100
- No measurable overhead vs single JlsmTable for single-partition tables

## Architecture Decision
- ADR-001: Range Partitioning with Per-Partition Co-located Indices
  (.decisions/table-partitioning/adr.md)

## Project Context
- Language: Java 25 (Amazon Corretto)
- Framework: none — pure library
- Test framework: JUnit Jupiter (JUnit 5)
