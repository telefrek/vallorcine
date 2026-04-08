---
feature: "in-process-database-engine"
created: "2026-03-19"
status: "complete"
---

# Work Plan — in-process-database-engine

## References

- [brief.md](brief.md) — feature brief
- [domains.md](domains.md) — domain analysis
- [.decisions/table-catalog-persistence/adr.md](../../.decisions/table-catalog-persistence/adr.md) — Per-Table Metadata Directories
- [.decisions/engine-api-surface-design/adr.md](../../.decisions/engine-api-surface-design/adr.md) — Interface-Based Handle Pattern with Tracked Lifecycle and Lease Eviction

## Existing Constructs

| Construct | Location | Usage |
|-----------|----------|-------|
| JlsmTable (sealed: StringKeyed, LongKeyed) | modules/jlsm-table | Underlying table interface; LocalTable delegates to StringKeyed |
| JlsmSchema | modules/jlsm-table | Schema definition passed to createTable |
| JlsmDocument | modules/jlsm-table | Document model for CRUD operations |
| StandardJlsmTable | modules/jlsm-table | Factory for building JlsmTable instances in LocalEngine |
| TableQuery\<K\> | modules/jlsm-table | Fluent query builder; Table.query() passes through |
| TypedStandardLsmTree | modules/jlsm-core | Wires WAL+MemTable+SSTable; used by LocalEngine to build per-table trees |
| LocalWriteAheadLog | modules/jlsm-core | Per-table WAL created by LocalEngine |
| ConcurrentSkipListMemTable | modules/jlsm-core | Per-table MemTable factory |
| TrieSSTableWriter / TrieSSTableReader | modules/jlsm-core | Per-table SSTable I/O |
| DocumentSerializer | modules/jlsm-table | Schema-driven binary serialization |
| BlockedBloomFilter | modules/jlsm-core | Bloom filter for SSTable reads |
| TableEntry\<K\> | modules/jlsm-table | Range/query iteration result record |
| Predicate (sealed) | modules/jlsm-table | Query predicate AST |
| UpdateMode (enum) | modules/jlsm-table | REPLACE / PATCH mode for updates |
| DuplicateKeyException | modules/jlsm-table | Thrown on duplicate key create |
| KeyNotFoundException | modules/jlsm-table | Thrown on missing key update |

## New Constructs

| # | Construct | Package | WU | File |
|---|-----------|---------|-----|------|
| 1 | Engine (interface) | jlsm.engine | WU-1 | Engine.java |
| 2 | Table (interface) | jlsm.engine | WU-1 | Table.java |
| 3 | TableMetadata (record) | jlsm.engine | WU-1 | TableMetadata.java |
| 4 | EngineMetrics (record) | jlsm.engine | WU-1 | EngineMetrics.java |
| 5 | AllocationTracking (enum) | jlsm.engine | WU-1 | AllocationTracking.java |
| 6 | HandleEvictedException | jlsm.engine | WU-1 | HandleEvictedException.java |
| 7 | HandleTracker | jlsm.engine.internal | WU-2 | HandleTracker.java |
| 8 | HandleRegistration | jlsm.engine.internal | WU-2 | HandleRegistration.java |
| 9 | TableCatalog | jlsm.engine.internal | WU-2 | TableCatalog.java |
| 10 | LocalEngine | jlsm.engine.internal | WU-3 | LocalEngine.java |
| 11 | LocalTable | jlsm.engine.internal | WU-3 | LocalTable.java |

## Stub Files Written

| File | Path | WU |
|------|------|----|
| module-info.java | modules/jlsm-engine/src/main/java/module-info.java | WU-1 |
| build.gradle | modules/jlsm-engine/build.gradle | WU-1 |
| Engine.java | modules/jlsm-engine/src/main/java/jlsm/engine/Engine.java | WU-1 |
| Table.java | modules/jlsm-engine/src/main/java/jlsm/engine/Table.java | WU-1 |
| TableMetadata.java | modules/jlsm-engine/src/main/java/jlsm/engine/TableMetadata.java | WU-1 |
| EngineMetrics.java | modules/jlsm-engine/src/main/java/jlsm/engine/EngineMetrics.java | WU-1 |
| AllocationTracking.java | modules/jlsm-engine/src/main/java/jlsm/engine/AllocationTracking.java | WU-1 |
| HandleEvictedException.java | modules/jlsm-engine/src/main/java/jlsm/engine/HandleEvictedException.java | WU-1 |
| HandleTracker.java | modules/jlsm-engine/src/main/java/jlsm/engine/internal/HandleTracker.java | WU-2 |
| HandleRegistration.java | modules/jlsm-engine/src/main/java/jlsm/engine/internal/HandleRegistration.java | WU-2 |
| TableCatalog.java | modules/jlsm-engine/src/main/java/jlsm/engine/internal/TableCatalog.java | WU-2 |
| LocalEngine.java | modules/jlsm-engine/src/main/java/jlsm/engine/internal/LocalEngine.java | WU-3 |
| LocalTable.java | modules/jlsm-engine/src/main/java/jlsm/engine/internal/LocalTable.java | WU-3 |
| settings.gradle (modified) | settings.gradle | WU-1 |

## Contract Definitions

### 1. Engine (interface)

**Package:** `jlsm.engine` (exported)
**Governed by:** `.decisions/engine-api-surface-design/adr.md`

```java
public interface Engine extends Closeable {
    Table createTable(String name, JlsmSchema schema) throws IOException;
    Table getTable(String name) throws IOException;
    void dropTable(String name) throws IOException;
    Collection<TableMetadata> listTables();
    TableMetadata tableMetadata(String name);
    EngineMetrics metrics();
    @Override void close() throws IOException;
}
```

- **Receives:** table names (non-null, non-empty Strings), JlsmSchema instances
- **Returns:** Table handles (tracked), TableMetadata, EngineMetrics snapshots
- **Side effects:** creates/drops table subdirectories; registers/invalidates handles
- **Error conditions:** IOException on I/O failure; IllegalArgumentException on null/empty name; IOException if table already exists (create) or not found (get/drop)

### 2. Table (interface)

**Package:** `jlsm.engine` (exported)
**Governed by:** `.decisions/engine-api-surface-design/adr.md`

```java
public interface Table extends AutoCloseable {
    void create(String key, JlsmDocument doc) throws DuplicateKeyException, IOException;
    Optional<JlsmDocument> get(String key) throws IOException;
    void update(String key, JlsmDocument doc, UpdateMode mode) throws KeyNotFoundException, IOException;
    void delete(String key) throws IOException;
    void insert(JlsmDocument doc) throws IOException;
    TableQuery<String> query();
    Iterator<TableEntry<String>> scan(String fromKey, String toKey) throws IOException;
    TableMetadata metadata();
    @Override void close();
}
```

- **Receives:** string keys, JlsmDocument instances, UpdateMode
- **Returns:** Optional\<JlsmDocument\>, TableQuery\<String\>, Iterator\<TableEntry\<String\>\>, TableMetadata
- **Side effects:** delegates CRUD to underlying JlsmTable.StringKeyed; close() releases handle registration
- **Error conditions:** HandleEvictedException if handle is invalid; DuplicateKeyException/KeyNotFoundException from table; IOException on I/O failure

### 3. TableMetadata (record)

**Package:** `jlsm.engine` (exported)
**Governed by:** `.decisions/table-catalog-persistence/adr.md`

```java
public record TableMetadata(String name, JlsmSchema schema, Instant createdAt, TableState state) {
    public enum TableState { LOADING, READY, DROPPED, ERROR }
}
```

- **Receives:** name (non-null, non-empty), schema (non-null), createdAt (non-null), state (non-null)
- **Returns:** immutable metadata snapshot
- **Side effects:** none
- **Error conditions:** NullPointerException on null fields; assertion on empty name

### 4. EngineMetrics (record)

**Package:** `jlsm.engine` (exported)
**Governed by:** `.decisions/engine-api-surface-design/adr.md`

```java
public record EngineMetrics(int tableCount, int totalOpenHandles,
        Map<String, Integer> handlesPerTable,
        Map<String, Map<String, Integer>> handlesPerSourcePerTable) {}
```

- **Receives:** non-negative counts, non-null maps
- **Returns:** immutable snapshot (maps defensively copied via Map.copyOf)
- **Side effects:** none
- **Error conditions:** NullPointerException on null maps; assertion on negative counts

### 5. AllocationTracking (enum)

**Package:** `jlsm.engine` (exported)
**Governed by:** `.decisions/engine-api-surface-design/adr.md`

```java
public enum AllocationTracking { OFF, CALLER_TAG, FULL_STACK }
```

- Three tracking levels controlling diagnostic capture at handle allocation
- OFF: no overhead; CALLER_TAG: records source ID; FULL_STACK: captures stack trace

### 6. HandleEvictedException

**Package:** `jlsm.engine` (exported)
**Governed by:** `.decisions/engine-api-surface-design/adr.md`

```java
public final class HandleEvictedException extends IllegalStateException {
    public enum Reason { EVICTION, ENGINE_SHUTDOWN, TABLE_DROPPED }
    // Carries: tableName, sourceId, handleCountAtEviction, allocationSite, reason
}
```

- **Receives:** tableName (non-null), sourceId (non-null), handleCountAtEviction (>= 0), allocationSite (nullable), reason (non-null)
- **Returns:** diagnostic exception with full eviction context
- **Side effects:** none
- **Error conditions:** NullPointerException on required null fields

### 7. HandleTracker

**Package:** `jlsm.engine.internal` (not exported)
**Governed by:** `.decisions/engine-api-surface-design/adr.md`

```java
final class HandleTracker implements Closeable {
    static Builder builder();
    HandleRegistration register(String tableName, String sourceId);
    void release(HandleRegistration registration);
    void evictIfNeeded(String tableName);
    void invalidateAll(HandleEvictedException.Reason reason);
    void invalidateTable(String tableName, HandleEvictedException.Reason reason);
    EngineMetrics snapshot();
}
```

- **Receives:** table names, source IDs, HandleRegistration tokens
- **Returns:** HandleRegistration on register; EngineMetrics snapshot
- **Side effects:** tracks handles in concurrent data structures; evicts oldest handles from greediest source under pressure; invalidates registrations
- **Error conditions:** NullPointerException on null args; eviction triggers HandleEvictedException on affected handles
- **Builder:** maxHandlesPerSourcePerTable (default 16), maxHandlesPerTable (default 64), maxTotalHandles (default 1024), allocationTracking (default OFF)

### 8. HandleRegistration

**Package:** `jlsm.engine.internal` (not exported)

- Mutable token with volatile `invalidated` flag
- Carries tableName, sourceId, allocationSite (nullable)
- Used internally by HandleTracker and LocalTable

### 9. TableCatalog

**Package:** `jlsm.engine.internal` (not exported)
**Governed by:** `.decisions/table-catalog-persistence/adr.md`

```java
final class TableCatalog implements Closeable {
    TableCatalog(Path rootDir);
    void open() throws IOException;
    TableMetadata register(String name, JlsmSchema schema) throws IOException;
    void unregister(String name) throws IOException;
    Optional<TableMetadata> get(String name);
    Collection<TableMetadata> list();
    Path tableDirectory(String name);
    boolean isLoading();
}
```

- **Receives:** rootDir (non-null Path), table names (non-null, non-empty), JlsmSchema
- **Returns:** TableMetadata, Optional\<TableMetadata\>, Collection\<TableMetadata\>, Path
- **Side effects:** creates/removes per-table subdirectories; writes/deletes metadata files; scans root on open()
- **Error conditions:** IOException on directory creation failure, corrupt metadata, or missing table; IllegalArgumentException on empty name

### 10. LocalEngine

**Package:** `jlsm.engine.internal` (not exported)
**Governed by:** `.decisions/engine-api-surface-design/adr.md`, `.decisions/table-catalog-persistence/adr.md`

```java
final class LocalEngine implements Engine {
    static Builder builder();
    // Implements all Engine methods
}
```

- **Receives:** configuration via Builder (rootDirectory required; handle limits optional)
- **Returns:** Table handles, TableMetadata, EngineMetrics
- **Side effects:** opens TableCatalog on construction; creates per-table JlsmTable instances (lazy); delegates handle tracking to HandleTracker; force-invalidates all handles on close()
- **Error conditions:** IllegalStateException if rootDirectory not set in builder; IOException from catalog/table operations
- **Builder:** rootDirectory, maxHandlesPerSourcePerTable (16), maxHandlesPerTable (64), maxTotalHandles (1024), allocationTracking (OFF), memTableFlushThresholdBytes (64 MiB)

### 11. LocalTable

**Package:** `jlsm.engine.internal` (not exported)
**Governed by:** `.decisions/engine-api-surface-design/adr.md`

```java
final class LocalTable implements Table {
    // Wraps JlsmTable.StringKeyed + HandleRegistration
    // Every method checks handle validity before delegating
}
```

- **Receives:** JlsmTable.StringKeyed delegate, HandleRegistration, HandleTracker, TableMetadata
- **Returns:** delegates to JlsmTable.StringKeyed for all data operations
- **Side effects:** checkValid() before every operation; close() releases HandleRegistration
- **Error conditions:** HandleEvictedException if registration is invalidated; all JlsmTable exceptions pass through

## Work Units

### WU-1: API types + module setup

**Constructs:** Engine, Table, TableMetadata, EngineMetrics, AllocationTracking, HandleEvictedException, module-info.java, build.gradle, settings.gradle
**Depends on:** nothing
**Scope:** All exported types in `jlsm.engine` package + module infrastructure. Engine and Table are interfaces (no implementation needed). Records include validation. Enum and exception are complete types.
**Test focus:** TableMetadata validation (null rejection, empty name), EngineMetrics defensive copy, HandleEvictedException field access, AllocationTracking values

### WU-2: Infrastructure

**Constructs:** HandleTracker, HandleRegistration, TableCatalog
**Depends on:** WU-1 (uses TableMetadata, EngineMetrics, AllocationTracking, HandleEvictedException)
**Scope:** Internal infrastructure classes. HandleTracker manages concurrent handle bookkeeping with eviction. TableCatalog manages per-table directories and metadata persistence.
**Test focus:** HandleTracker register/release/eviction/invalidation/snapshot; TableCatalog open/register/unregister/get/list with filesystem I/O

### WU-3: Engine implementation

**Constructs:** LocalEngine, LocalTable
**Depends on:** WU-1, WU-2
**Scope:** Full engine implementation wiring catalog + handle tracker + JlsmTable. LocalEngine.Builder, table creation with directory setup, table retrieval with lazy init, table drop with cleanup, close with handle invalidation. LocalTable delegates all ops through validity check.
**Test focus:** Engine lifecycle (create/get/drop/list/close), LocalTable delegation + validity check, concurrent access, recovery from existing root directory

## Implementation Order

1. **WU-1** — API types + module setup (no dependencies; pure types)
2. **WU-2** — Infrastructure (depends on WU-1 types; testable in isolation)
3. **WU-3** — Engine implementation (depends on WU-1 + WU-2; integration-level tests)

WU-1 and WU-2 can be parallelized if WU-1 types are committed first (WU-2 only imports from the exported package). WU-3 must wait for both.
