---
feature: "In-process database engine with multi-table management"
slug: "in-process-database-engine"
created: "2026-03-19"
status: "scoped"
---

# Feature Brief — in-process-database-engine

## Summary
A new `jlsm-engine` module providing an in-process database engine that manages multiple tables from a self-organized root directory. Supports table creation, table metadata introspection, data insertion, and querying via pass-through to the existing `jlsm-table` fluent query API. Thread-safe for concurrent callers. Architecturally open to future network protocols, engine-level query syntax (DDL), and clustered distribution.

## Actors
- Application threads (one or many, concurrent) interacting with the engine via its Java API

## Inputs
- Root directory path (engine initialization)
- Table schema definitions (table creation)
- Documents / rows (data insertion)
- Fluent query API calls (data retrieval)
- Engine-level commands: create table, drop table, list tables, table metadata

## Outputs / Side Effects
- Table catalog maintained in the root directory
- Per-table subdirectories with self-managed SSTable/WAL/MemTable lifecycle
- Query results returned via existing `jlsm-table` result types
- Table metadata (schema, name, stats) returned on introspection

## Business Rules
- Table names must be unique within an engine instance
- Creating a table that already exists is an error
- Dropping a table that doesn't exist is an error
- All engine operations are thread-safe — concurrent create/drop/query/insert must be safe
- Engine manages storage layout: callers provide only a root path
- Engine startup should recover existing tables from the root directory (WAL replay, SSTable discovery)

## Error Cases
- Duplicate table name on create → descriptive exception
- Unknown table name on drop/query/insert → descriptive exception
- Corrupt or unreadable root directory → IOException at engine open
- Table-level errors (WAL corruption, SSTable read failure) → surfaced per existing jlsm-table/core error handling

## Explicit Out of Scope
- Network protocols / binary serialization (future work)
- Cluster distribution / node joining (future work)
- Engine-level query language (DDL/DML parsing) — future; the fluent API is the interface for now
- Cross-table joins or transactions

## Acceptance Criteria
1. Can create a new engine instance pointing at a root directory
2. Can create a table with a schema and have it persisted
3. Can list all tables and retrieve metadata for a specific table
4. Can drop a table (removes from catalog and cleans up storage)
5. Can insert documents into a named table
6. Can query a named table using the existing fluent query API
7. Engine restart from the same root directory recovers all previously created tables
8. All operations are safe under concurrent access from multiple threads
9. Lives in a new `jlsm-engine` module with clean JPMS boundaries

## Open Assumptions
- The engine will depend on `jlsm-table` and transitively on `jlsm-core`
- Table catalog metadata (name, schema, creation time) will be persisted to the root directory so tables survive engine restart
- The engine API will be a class with methods (not static utilities) — instantiated with a builder or factory

## Research Commissions
None — no research signals identified during scoping.

## Performance Expectations
- Engine-level overhead (catalog lookup, routing to table) should be negligible compared to underlying table I/O
- No additional copies of data at the engine layer — pass-through to table operations

## Project Context
- Language: Java 25 (Amazon Corretto)
- Framework: none — pure library
- Test framework: JUnit Jupiter (JUnit 5)
