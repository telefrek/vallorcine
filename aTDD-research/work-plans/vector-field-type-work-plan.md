# Work Plan — vector-field-type

## References

- **Brief:** [brief.md](brief.md)
- **Domains:** [domains.md](domains.md)
- **ADR — Vector type serialization encoding:** `.decisions/vector-type-serialization-encoding/adr.md`
- **ADR — IndexDefinition API simplification:** `.decisions/index-definition-api-simplification/adr.md`

## Existing Constructs (extend)

| # | Construct | File | Change |
|---|-----------|------|--------|
| 1 | `FieldType` | `modules/jlsm-table/src/main/java/jlsm/table/FieldType.java` | Add `VectorType` inner record, `vector()` factory, update `permits` clause |
| 2 | `JlsmSchema.Builder` | `modules/jlsm-table/src/main/java/jlsm/table/JlsmSchema.java` | Add `vectorField()` convenience method |
| 3 | `IndexDefinition` | `modules/jlsm-table/src/main/java/jlsm/table/IndexDefinition.java` | Remove `vectorDimensions` field, simplify record signature |
| 4 | `IndexRegistry` | `modules/jlsm-table/src/main/java/jlsm/table/internal/IndexRegistry.java` | Update `validate()` to check `VectorType` instead of `ArrayType` |
| 5 | `DocumentSerializer` | `modules/jlsm-table/src/main/java/jlsm/table/DocumentSerializer.java` | Add `VectorType` handling in measure/encode/decode |

## New Constructs (create)

| # | Construct | File | Notes |
|---|-----------|------|-------|
| 1 | `FieldType.VectorType` | `modules/jlsm-table/src/main/java/jlsm/table/FieldType.java` | Inner record, not a standalone file |

## Contract Definitions

### FieldType.VectorType (NEW)

- **File:** `modules/jlsm-table/src/main/java/jlsm/table/FieldType.java`
- **Governed by:** `.decisions/vector-type-serialization-encoding/adr.md`
- **Signature:** `record VectorType(Primitive elementType, int dimensions) implements FieldType`
- **Contract:**
  - Receives: `elementType` (must be `FLOAT16` or `FLOAT32`), `dimensions` (must be > 0)
  - Returns: immutable value holding element precision and fixed dimension count
  - Side effects: none
  - Error: `IllegalArgumentException` if `elementType` is not `FLOAT16`/`FLOAT32` or `dimensions <= 0`

### FieldType.vector() factory (EXTEND)

- **File:** `modules/jlsm-table/src/main/java/jlsm/table/FieldType.java`
- **Signature:** `static FieldType vector(Primitive elementType, int dimensions)`
- **Contract:** Returns new `VectorType`; delegates validation to `VectorType` constructor

### FieldType sealed permits (EXTEND)

- **File:** `modules/jlsm-table/src/main/java/jlsm/table/FieldType.java`
- **Change:** Update `permits` clause from `Primitive, ArrayType, ObjectType` to `Primitive, ArrayType, ObjectType, VectorType`

### JlsmSchema.Builder.vectorField() (EXTEND)

- **File:** `modules/jlsm-table/src/main/java/jlsm/table/JlsmSchema.java`
- **Signature:** `public Builder vectorField(String name, FieldType.Primitive elementType, int dimensions)`
- **Contract:** Convenience method that calls `field(name, FieldType.vector(elementType, dimensions))`

### IndexDefinition record (EXTEND)

- **File:** `modules/jlsm-table/src/main/java/jlsm/table/IndexDefinition.java`
- **Governed by:** `.decisions/index-definition-api-simplification/adr.md`
- **New signature:** `record IndexDefinition(String fieldName, IndexType indexType, SimilarityFunction similarityFunction)`
- **New 2-arg constructor:** `IndexDefinition(String fieldName, IndexType indexType)` delegates to `this(fieldName, indexType, null)`
- **Compact constructor validation:**
  - `fieldName` not null/blank
  - `indexType` not null
  - If `indexType == VECTOR`: require `similarityFunction` not null
- **Removes:** `vectorDimensions` field entirely

### IndexRegistry.validate() (EXTEND)

- **File:** `modules/jlsm-table/src/main/java/jlsm/table/internal/IndexRegistry.java`
- **Contract change:** VECTOR index case checks `fieldType instanceof FieldType.VectorType` instead of `ArrayType(FLOAT32/FLOAT16)`
- **Dimension extraction:** Use `VectorType.dimensions()` to pass to `VectorFieldIndex`
- **Error:** `IllegalArgumentException` if VECTOR index declared on non-`VectorType` field

### DocumentSerializer (EXTEND)

- **File:** `modules/jlsm-table/src/main/java/jlsm/table/DocumentSerializer.java`
- **Governed by:** `.decisions/vector-type-serialization-encoding/adr.md`
- **measureField():** Add `case FieldType.VectorType vt -> vt.dimensions() * elementWidth(vt.elementType())`
  - FLOAT32 element width: 4 bytes
  - FLOAT16 element width: 2 bytes
- **encodeField():** Add `VectorType` case
  - Write `d` elements contiguously (no VarInt prefix — dimensions are known from schema)
  - FLOAT32: reuse existing SIMD byte-swap path (same logic as `encodeFloat32Array` but without VarInt length prefix)
  - FLOAT16: scalar 2-byte big-endian short writes
- **decodeField():** Add `VectorType` case
  - Read `d` elements contiguously
  - FLOAT32: return as `float[]`
  - FLOAT16: return as `short[]`
- **Null handling:** Vector as a whole may be null (controlled by document null bitmask). No null elements within a vector.

## Implementation Order

| Order | Construct | Rationale |
|-------|-----------|-----------|
| 1 | `FieldType.VectorType` + `vector()` factory + `permits` update | Foundation — no dependencies |
| 2 | `JlsmSchema.Builder.vectorField()` | Depends on `VectorType` existing |
| 3 | `IndexDefinition` simplification | Independent of `VectorType` but logically paired |
| 4 | `IndexRegistry.validate()` update | Depends on `VectorType` + new `IndexDefinition` |
| 5 | `DocumentSerializer` `VectorType` handling | Depends on `VectorType` |

## Work Units

Single unit — all constructs are tightly coupled and share the same TDD cycle.

## Stubs

No standalone stub files created. All changes are modifications to existing files or inner records within existing files.
