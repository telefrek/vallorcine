---
feature: "table-indices-and-queries"
created: "2026-03-16"
language: "Java 25"
---

# Work Plan — table-indices-and-queries

## References
- Brief: [brief.md](brief.md)
- Domains: [domains.md](domains.md)
- Governing ADRs: none

## Existing Constructs

| Construct | File | Usage |
|-----------|------|-------|
| JlsmTable | modules/jlsm-table/src/main/java/jlsm/table/JlsmTable.java | extend — add query() to StringKeyed/LongKeyed |
| StandardJlsmTable | modules/jlsm-table/src/main/java/jlsm/table/StandardJlsmTable.java | extend — add index() to builders |
| StringKeyedTable | modules/jlsm-table/src/main/java/jlsm/table/internal/StringKeyedTable.java | extend — add index maintenance on writes + query() |
| LongKeyedTable | modules/jlsm-table/src/main/java/jlsm/table/internal/LongKeyedTable.java | extend — add index maintenance on writes + query() |
| DuplicateKeyException | modules/jlsm-table/src/main/java/jlsm/table/DuplicateKeyException.java | use — thrown on unique constraint violation |
| JlsmDocument | modules/jlsm-table/src/main/java/jlsm/table/JlsmDocument.java | use — field value extraction for index maintenance |
| JlsmSchema / FieldDefinition / FieldType | modules/jlsm-table/src/main/java/jlsm/table/ | use — index validation, field type resolution |
| LsmFullTextIndex | modules/jlsm-indexing/src/main/java/jlsm/indexing/LsmFullTextIndex.java | use — backing store for full-text indices |
| LsmVectorIndex | modules/jlsm-vector/src/main/java/jlsm/vector/LsmVectorIndex.java | use — backing store for vector indices |
| TypedLsmTree | modules/jlsm-core (jlsm.core.tree) | use — backing store for equality/range/unique indices |
| DocumentAccess | modules/jlsm-table/src/main/java/jlsm/table/internal/DocumentAccess.java | use — access document field values from internal package |

## New Constructs

| Construct | File | Contract summary |
|-----------|------|-----------------|
| IndexType | modules/jlsm-table/src/main/java/jlsm/table/IndexType.java | Enum: EQUALITY, RANGE, UNIQUE, FULL_TEXT, VECTOR |
| IndexDefinition | modules/jlsm-table/src/main/java/jlsm/table/IndexDefinition.java | Record: field name + index type + optional vector config |
| Predicate | modules/jlsm-table/src/main/java/jlsm/table/Predicate.java | Sealed interface: AST for query predicates (11 node types) |
| TableQuery | modules/jlsm-table/src/main/java/jlsm/table/TableQuery.java | Fluent query builder producing Predicate tree |
| FieldValueCodec | modules/jlsm-table/src/main/java/jlsm/table/internal/FieldValueCodec.java | Sort-preserving binary encoding for index keys |
| SecondaryIndex | modules/jlsm-table/src/main/java/jlsm/table/internal/SecondaryIndex.java | Sealed interface: abstraction over index implementations |
| FieldIndex | modules/jlsm-table/src/main/java/jlsm/table/internal/FieldIndex.java | Equality/range/unique index backed by LSM tree |
| FullTextFieldIndex | modules/jlsm-table/src/main/java/jlsm/table/internal/FullTextFieldIndex.java | Full-text index wrapping LsmFullTextIndex |
| VectorFieldIndex | modules/jlsm-table/src/main/java/jlsm/table/internal/VectorFieldIndex.java | Vector index wrapping LsmVectorIndex |
| IndexRegistry | modules/jlsm-table/src/main/java/jlsm/table/internal/IndexRegistry.java | Manages all indices, routes writes, provides lookup |
| QueryExecutor | modules/jlsm-table/src/main/java/jlsm/table/internal/QueryExecutor.java | Plans and executes queries using IndexRegistry |

## Stub Files Written

| File | Status |
|------|--------|
| modules/jlsm-table/src/main/java/jlsm/table/IndexType.java | stubbed |
| modules/jlsm-table/src/main/java/jlsm/table/IndexDefinition.java | stubbed |
| modules/jlsm-table/src/main/java/jlsm/table/Predicate.java | stubbed |
| modules/jlsm-table/src/main/java/jlsm/table/TableQuery.java | stubbed |
| modules/jlsm-table/src/main/java/jlsm/table/internal/FieldValueCodec.java | stubbed |
| modules/jlsm-table/src/main/java/jlsm/table/internal/SecondaryIndex.java | stubbed |
| modules/jlsm-table/src/main/java/jlsm/table/internal/FieldIndex.java | stubbed |
| modules/jlsm-table/src/main/java/jlsm/table/internal/FullTextFieldIndex.java | stubbed |
| modules/jlsm-table/src/main/java/jlsm/table/internal/VectorFieldIndex.java | stubbed |
| modules/jlsm-table/src/main/java/jlsm/table/internal/IndexRegistry.java | stubbed |
| modules/jlsm-table/src/main/java/jlsm/table/internal/QueryExecutor.java | stubbed |

## Contract Definitions

### IndexType
**File:** `modules/jlsm-table/src/main/java/jlsm/table/IndexType.java`
**Signature:** `public enum IndexType { EQUALITY, RANGE, UNIQUE, FULL_TEXT, VECTOR }`
**Contract:**
- Pure enum, no logic
- EQUALITY: eq/ne on any primitive
- RANGE: eq/ne/gt/gte/lt/lte/between on ordered types (numeric, string, timestamp)
- UNIQUE: like RANGE + uniqueness constraint
- FULL_TEXT: full-text search on STRING fields
- VECTOR: kNN on float array fields

### IndexDefinition
**File:** `modules/jlsm-table/src/main/java/jlsm/table/IndexDefinition.java`
**Signature:** `public record IndexDefinition(String fieldName, IndexType indexType, int vectorDimensions, SimilarityFunction similarityFunction)`
**Contract:**
- Receives: field name, index type, optional vector config
- Validates: fieldName non-null/non-blank, VECTOR requires positive dimensions + non-null similarity fn
- Convenience constructor: `IndexDefinition(String, IndexType)` for non-vector types
- Pure value holder — validated at construction

### Predicate
**File:** `modules/jlsm-table/src/main/java/jlsm/table/Predicate.java`
**Signature:** `public sealed interface Predicate permits Eq, Ne, Gt, Gte, Lt, Lte, Between, FullTextMatch, VectorNearest, And, Or`
**Contract:**
- All leaf nodes carry field name + typed value(s), validated non-null at construction
- Composite nodes (And, Or) require at least 2 children, defensively copied
- VectorNearest requires positive topK
- Inspectable — all fields accessible via record accessors
- Error conditions: NPE on null field/value, IAE on invalid child count or topK

### TableQuery
**File:** `modules/jlsm-table/src/main/java/jlsm/table/TableQuery.java`
**Signature:** `public final class TableQuery<K>`
**Contract:**
- Receives: field names and values via fluent chaining (where/and/or → FieldClause → operator)
- Returns: `Iterator<TableEntry<K>>` on `execute()`
- `predicate()` returns the built Predicate tree for inspection
- `where(field)` starts a new predicate, `and(field)` / `or(field)` chain combinators
- FieldClause provides: eq, ne, gt, gte, lt, lte, between, fullTextMatch, vectorNearest
- Side effects: none until execute()
- Error conditions: IAE on invalid field names or type mismatches

### FieldValueCodec
**File:** `modules/jlsm-table/src/main/java/jlsm/table/internal/FieldValueCodec.java`
**Signature:** `public final class FieldValueCodec` (utility class)
**Contract:**
- `encode(Object value, FieldType fieldType) → MemorySegment`: sort-preserving binary
- `decode(MemorySegment encoded, FieldType fieldType) → Object`: reverse of encode
- Encoding: INT8/16/32/64 → sign-bit-flipped big-endian; FLOAT32/64 → IEEE 754 sort-preserving;
  FLOAT16 → sign-bit-flipped 2-byte; STRING → UTF-8; BOOLEAN → 0x00/0x01; TIMESTAMP → same as INT64
- Error conditions: IAE if value type is incompatible with fieldType

### SecondaryIndex
**File:** `modules/jlsm-table/src/main/java/jlsm/table/internal/SecondaryIndex.java`
**Signature:** `public sealed interface SecondaryIndex extends Closeable permits FieldIndex, FullTextFieldIndex, VectorFieldIndex`
**Contract:**
- `definition()` — returns the IndexDefinition this index was created from
- `onInsert(primaryKey, fieldValue)` — called on document insert; null values are not indexed
- `onUpdate(primaryKey, oldFieldValue, newFieldValue)` — removes old, inserts new
- `onDelete(primaryKey, fieldValue)` — removes from index
- `lookup(predicate)` — returns Iterator<MemorySegment> of matching primary keys
- `supports(predicate)` — returns true if this index can evaluate the predicate
- Closeable — releases backing store

### FieldIndex
**File:** `modules/jlsm-table/src/main/java/jlsm/table/internal/FieldIndex.java`
**Signature:** `public final class FieldIndex implements SecondaryIndex`
**Contract:**
- Backed by a TypedLsmTree; key = concat(encodedFieldValue, primaryKey), value = empty marker
- EQUALITY: supports Eq, Ne
- RANGE: supports Eq, Ne, Gt, Gte, Lt, Lte, Between
- UNIQUE: same as RANGE + check-before-write on insert/update (throws DuplicateKeyException)
- Lookup: prefix scan on encoded field value → collect primary keys
- For Ne: full index scan excluding the given value

### FullTextFieldIndex
**File:** `modules/jlsm-table/src/main/java/jlsm/table/internal/FullTextFieldIndex.java`
**Signature:** `public final class FullTextFieldIndex implements SecondaryIndex`
**Contract:**
- Wraps LsmFullTextIndex from jlsm-indexing
- Supports: FullTextMatch predicate only
- On insert: index(primaryKey, Map.of(fieldName, fieldValue))
- On update: remove old terms, index new terms
- On delete: remove all terms for the document
- Lookup: delegates to LsmFullTextIndex.search()

### VectorFieldIndex
**File:** `modules/jlsm-table/src/main/java/jlsm/table/internal/VectorFieldIndex.java`
**Signature:** `public final class VectorFieldIndex implements SecondaryIndex`
**Contract:**
- Wraps LsmVectorIndex (IvfFlat or Hnsw) from jlsm-vector
- Supports: VectorNearest predicate only
- Field must be ArrayType with FLOAT32 or FLOAT16 element type
- On insert: extract float array, insert into vector index
- On update: remove old vector, insert new vector
- On delete: remove vector from index
- Lookup: delegates to LsmVectorIndex.search(query, topK), returns primary keys

### IndexRegistry
**File:** `modules/jlsm-table/src/main/java/jlsm/table/internal/IndexRegistry.java`
**Signature:** `public final class IndexRegistry implements Closeable`
**Contract:**
- Receives: schema + list of IndexDefinitions at construction
- Validates: each definition against the schema (field exists, type compatible with index type)
- Creates SecondaryIndex instances for each definition
- `onInsert(primaryKey, document)` — extracts field values, routes to each index; unique checks first
- `onUpdate(primaryKey, oldDoc, newDoc)` — routes to each index with old/new field values
- `onDelete(primaryKey, document)` — routes to each index
- `findIndex(predicate)` — returns the best matching SecondaryIndex or null
- `isEmpty()` — true if no indices defined
- Closeable — closes all indices (deferred exception pattern)

### QueryExecutor
**File:** `modules/jlsm-table/src/main/java/jlsm/table/internal/QueryExecutor.java`
**Signature:** `public final class QueryExecutor<K>`
**Contract:**
- Receives: schema, IndexRegistry at construction
- `execute(predicate)` — plans and executes the query
- For leaf predicates: check IndexRegistry.findIndex(); if found, use index lookup; else scan-and-filter
- For And: execute children, intersect primary key sets
- For Or: execute children, union primary key sets
- Returns: Iterator<TableEntry<K>> over matching documents
- Error conditions: IOException on I/O errors

---

## Work Units

### WU-1: Index infrastructure
**Constructs:** IndexType, IndexDefinition, FieldValueCodec, SecondaryIndex, FieldIndex, FullTextFieldIndex, VectorFieldIndex, IndexRegistry
**Extensions:** StandardJlsmTable builders (add index()), StringKeyedTable/LongKeyedTable (write-path integration)
**Depends on:** none
**Est. session load:** ~24K

### WU-2: Query API + execution
**Constructs:** Predicate, TableQuery, QueryExecutor
**Extensions:** JlsmTable.StringKeyed/LongKeyed (add query())
**Depends on:** WU-1 (IndexRegistry, SecondaryIndex)
**Est. session load:** ~14K

## Implementation Order
1. WU-1 — Index infrastructure (no dependencies)
   1. IndexType (enum, no deps)
   2. IndexDefinition (depends on IndexType)
   3. FieldValueCodec (depends on FieldType)
   4. SecondaryIndex (interface, depends on IndexDefinition, Predicate)
   5. FieldIndex (depends on SecondaryIndex, FieldValueCodec)
   6. FullTextFieldIndex (depends on SecondaryIndex, LsmFullTextIndex)
   7. VectorFieldIndex (depends on SecondaryIndex, LsmVectorIndex)
   8. IndexRegistry (depends on SecondaryIndex, all index impls)
   9. StandardJlsmTable builder extensions (depends on IndexDefinition, IndexRegistry)
   10. StringKeyedTable/LongKeyedTable write-path (depends on IndexRegistry)
2. WU-2 — Query API + execution (depends on WU-1)
   1. Predicate (sealed interface, no deps)
   2. TableQuery (depends on Predicate)
   3. QueryExecutor (depends on Predicate, IndexRegistry, SecondaryIndex)
   4. JlsmTable.StringKeyed/LongKeyed query() extensions (depends on TableQuery)
