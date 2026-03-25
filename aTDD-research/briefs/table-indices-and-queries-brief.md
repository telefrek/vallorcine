---
feature: "Table indices and queries"
slug: "table-indices-and-queries"
created: "2026-03-16"
status: "scoped"
---

# Feature Brief — table-indices-and-queries

## Summary
Add secondary index support and a fluent query API to jlsm-table.
Indices are owned by the table (not the schema) and support single-field
equality, range, unique-constraint, full-text (via jlsm-indexing), and
vector (via jlsm-vector) types. The query API uses a fluent builder
designed to be translatable to SQL in the future.

## Actors
- Library consumers building applications on top of jlsm-table
- The table itself, which maintains indices synchronously on writes

## Inputs
- Index definitions at table construction time (field name + index type)
- Query expressions built via fluent API (predicates, boolean combinators)
- For full-text: text query strings
- For vector: query vectors + k parameter

## Outputs / Side Effects
- Query results as Iterator<TableEntry<K>> (consistent with existing
  getAllInRange pattern)
- Index state maintained on disk alongside the table's LSM tree
- DuplicateKeyException on unique-constraint violation during
  create/update

## Business Rules
- Indices are defined on the table builder, validated against the schema
  (field must exist, type must be compatible with index type)
- Index maintenance is synchronous with writes — after a successful
  create/update/delete, all indices reflect the change
- Unique indices enforce the constraint at write time, not query time
- Full-text indices delegate to LsmInvertedIndex from jlsm-indexing
- Vector indices delegate to LsmVectorIndex from jlsm-vector
- Range indices support the ordered comparisons (gt, gte, lt, lte)
  for naturally ordered types (numeric, string, timestamp)
- Equality indices support eq/ne for any primitive field type
- Query planner selects the best available index for each predicate;
  predicates without a matching index fall back to a scan-and-filter

## Error Cases
- Index on nonexistent field: IllegalArgumentException at build time
- Index type incompatible with field type (e.g., range on boolean):
  IllegalArgumentException at build time
- Unique constraint violation: DuplicateKeyException at write time
- Query on a field type incompatible with the predicate operator
  (e.g., gt on boolean): IllegalArgumentException at query build time

## Explicit Out of Scope
- Composite (multi-field) indices — future work
- Full SQL parser/compliance — the fluent API is designed to be
  translatable but no SQL string parsing is included
- Index-only queries (covering indices that skip document fetch)
- Async/background index building for existing data
- Aggregations (COUNT, SUM, AVG, etc.)

## Acceptance Criteria
- Can define equality, range, unique, full-text, and vector indices
  on a table via the builder
- Indices are maintained on create, update (both REPLACE and PATCH),
  and delete operations
- Fluent query API supports: eq, ne, gt, gte, lt, lte, between,
  fullTextMatch, vectorNearest, and boolean combinators (and, or)
- Queries that match an index use it; queries without an index
  fall back to scan-and-filter
- Unique index rejects duplicate values at write time
- All index types round-trip through table close/reopen

## Open Assumptions
- Full-text index reuses the existing tokenization/stemming pipeline
  from jlsm-indexing (LsmInvertedIndex)
- Vector index reuses IvfFlat or Hnsw from jlsm-vector
  (LsmVectorIndex); the specific algorithm is caller's choice
- Index storage uses separate LSM trees colocated with the main
  table's data directory
- The fluent API returns a Query object that is inspectable/
  serializable for future SQL translation

## Performance Expectations
- Index lookups should be O(log N) via the backing LSM tree, not
  O(N) table scans
- Write amplification is proportional to the number of indices
  (one additional LSM write per index per mutation)
- Scan-and-filter fallback is acceptable for unindexed predicates
  but should be clearly documented as O(N)

## Project Context
- Language: Java 25 (Amazon Corretto)
- Framework: none — pure library
- Test framework: JUnit Jupiter (JUnit 5)
