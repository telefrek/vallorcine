---
feature: "table-partitioning"
created: "2026-03-16"
language: "Java 25"
---

# Work Plan — table-partitioning

## References
- Brief: [brief.md](brief.md)
- Domains: [domains.md](domains.md)
- Governing ADR: [.decisions/table-partitioning/adr.md](../../.decisions/table-partitioning/adr.md)
- KB: [partitioning-strategies.md](../../.kb/distributed-systems/data-partitioning/partitioning-strategies.md), [vector-search-partitioning.md](../../.kb/distributed-systems/data-partitioning/vector-search-partitioning.md)

## Existing Constructs

| Construct | File | Usage |
|-----------|------|-------|
| JlsmTable.StringKeyed | modules/jlsm-table/.../JlsmTable.java | use — each partition wraps one |
| JlsmSchema | modules/jlsm-table/.../JlsmSchema.java | use — shared schema across partitions |
| JlsmDocument | modules/jlsm-table/.../JlsmDocument.java | use — document model unchanged |
| TableQuery / Predicate | modules/jlsm-table/.../TableQuery.java, Predicate.java | use — predicate AST dispatched to partitions |
| TableEntry | modules/jlsm-table/.../TableEntry.java | use — range iteration result |
| StandardJlsmTable | modules/jlsm-table/.../StandardJlsmTable.java | use — factory for per-partition tables |

## New Constructs

| Construct | File | Contract summary |
|-----------|------|-----------------|
| PartitionDescriptor | modules/jlsm-table/.../jlsm/table/PartitionDescriptor.java | Record: range bounds + node ID + epoch |
| PartitionConfig | modules/jlsm-table/.../jlsm/table/PartitionConfig.java | Validated partition layout (contiguous, non-overlapping) |
| ScoredEntry | modules/jlsm-table/.../jlsm/table/ScoredEntry.java | Record: document + relevance score for ranked queries |
| PartitionClient | modules/jlsm-table/.../jlsm/table/PartitionClient.java | SPI: dispatch operations to a partition (remote-capable) |
| RangeMap | modules/jlsm-table/.../jlsm/table/internal/RangeMap.java | O(log P) key routing + range overlap queries |
| InProcessPartitionClient | modules/jlsm-table/.../jlsm/table/internal/InProcessPartitionClient.java | Wraps JlsmTable.StringKeyed for in-process dispatch |
| ResultMerger | modules/jlsm-table/.../jlsm/table/internal/ResultMerger.java | Top-k merge + ordered merge for multi-partition results |
| PartitionedTable | modules/jlsm-table/.../jlsm/table/PartitionedTable.java | Coordinator: routing + scatter-gather + merge |

## Stub Files Written

| File | Status |
|------|--------|
| modules/jlsm-table/src/main/java/jlsm/table/PartitionDescriptor.java | stubbed (record — implemented) |
| modules/jlsm-table/src/main/java/jlsm/table/PartitionConfig.java | stubbed |
| modules/jlsm-table/src/main/java/jlsm/table/ScoredEntry.java | stubbed (record — implemented) |
| modules/jlsm-table/src/main/java/jlsm/table/PartitionClient.java | stubbed (interface) |
| modules/jlsm-table/src/main/java/jlsm/table/internal/RangeMap.java | stubbed |
| modules/jlsm-table/src/main/java/jlsm/table/internal/InProcessPartitionClient.java | stubbed |
| modules/jlsm-table/src/main/java/jlsm/table/internal/ResultMerger.java | stubbed |
| modules/jlsm-table/src/main/java/jlsm/table/PartitionedTable.java | stubbed |

## Contract Definitions

### PartitionDescriptor
**File:** `modules/jlsm-table/src/main/java/jlsm/table/PartitionDescriptor.java`
**Governed by:** [ADR-001](../../.decisions/table-partitioning/adr.md)
**Signature:** `record PartitionDescriptor(long id, MemorySegment lowKey, MemorySegment highKey, String nodeId, long epoch)`
**Contract:**
- Receives: partition ID, half-open key range [lowKey, highKey), node location, epoch
- Returns: immutable descriptor
- Side effects: none
- Error conditions: NPE on null fields, IAE on negative epoch

### PartitionConfig
**File:** `modules/jlsm-table/src/main/java/jlsm/table/PartitionConfig.java`
**Governed by:** [ADR-001](../../.decisions/table-partitioning/adr.md)
**Signature:** `PartitionConfig.of(List<PartitionDescriptor>)`
**Contract:**
- Receives: ordered list of partition descriptors
- Returns: validated config
- Side effects: none
- Error conditions: IAE if descriptors overlap, have gaps, or are empty

### ScoredEntry
**File:** `modules/jlsm-table/src/main/java/jlsm/table/ScoredEntry.java`
**Governed by:** [vector-search-partitioning.md](../../.kb/distributed-systems/data-partitioning/vector-search-partitioning.md)
**Signature:** `record ScoredEntry<K>(K key, JlsmDocument document, double score)`
**Contract:**
- Receives: key, document, relevance score
- Returns: immutable scored result
- Side effects: none

### PartitionClient
**File:** `modules/jlsm-table/src/main/java/jlsm/table/PartitionClient.java`
**Governed by:** [ADR-001](../../.decisions/table-partitioning/adr.md)
**Signature:** `interface PartitionClient extends Closeable`
**Contract:**
- CRUD methods mirror JlsmTable.StringKeyed
- `query(Predicate, int)` returns `List<ScoredEntry<String>>` for ranked results
- Designed for remote: no JlsmTable in the signature, only serializable types
- Error conditions: IOException on partition failure

### RangeMap
**File:** `modules/jlsm-table/src/main/java/jlsm/table/internal/RangeMap.java`
**Governed by:** [partitioning-strategies.md#routing](../../.kb/distributed-systems/data-partitioning/partitioning-strategies.md)
**Signature:** `RangeMap(PartitionConfig)`, `routeKey(MemorySegment)`, `overlapping(MemorySegment, MemorySegment)`
**Contract:**
- `routeKey`: O(log P) lookup, returns owning descriptor, IAE if key outside all ranges
- `overlapping`: returns descriptors whose ranges overlap [from, to)
- `all`: returns all descriptors in key order

### InProcessPartitionClient
**File:** `modules/jlsm-table/src/main/java/jlsm/table/internal/InProcessPartitionClient.java`
**Governed by:** [ADR-001](../../.decisions/table-partitioning/adr.md)
**Signature:** `InProcessPartitionClient(PartitionDescriptor, JlsmTable.StringKeyed)`
**Contract:**
- Delegates all operations directly to the wrapped JlsmTable
- `query` executes predicate via the table's query executor
- `close` closes the underlying table

### ResultMerger
**File:** `modules/jlsm-table/src/main/java/jlsm/table/internal/ResultMerger.java`
**Governed by:** [vector-search-partitioning.md#result-fusion](../../.kb/distributed-systems/data-partitioning/vector-search-partitioning.md)
**Signature:** `mergeTopK(List<List<ScoredEntry<K>>>, int)`, `mergeOrdered(List<Iterator<TableEntry<String>>>)`
**Contract:**
- `mergeTopK`: priority queue merge by score descending, returns global top-k
- `mergeOrdered`: N-way merge of sorted iterators by key order

### PartitionedTable
**File:** `modules/jlsm-table/src/main/java/jlsm/table/PartitionedTable.java`
**Governed by:** [ADR-001](../../.decisions/table-partitioning/adr.md)
**Signature:** `PartitionedTable.builder()` → `Builder` with `partitionConfig`, `schema`, `partitionClientFactory`, `build()`
**Contract:**
- CRUD: route key → partition via RangeMap, delegate to PartitionClient
- `getRange`: route to overlapping partitions, merge ordered
- `query`: scatter to all partitions (vector/text) or overlapping (property range), merge top-k
- `close`: close all partition clients, accumulate exceptions

---

## Work Units

### WU-1: Data model + routing
**Constructs:** PartitionDescriptor, ScoredEntry, PartitionConfig, PartitionClient (interface), RangeMap
**Depends on:** none
**Est. session load:** ~14K

### WU-2: Partition execution
**Constructs:** InProcessPartitionClient, ResultMerger
**Depends on:** WU-1 public interface (PartitionClient, PartitionDescriptor, ScoredEntry)
**Est. session load:** ~8K

### WU-3: Coordinator
**Constructs:** PartitionedTable
**Depends on:** WU-1 (RangeMap, PartitionConfig, PartitionClient), WU-2 (ResultMerger, InProcessPartitionClient)
**Est. session load:** ~9K

## Implementation Order
1. WU-1: Data model + routing — no dependencies
2. WU-2: Partition execution — depends on WU-1
3. WU-3: Coordinator — depends on WU-1 + WU-2
