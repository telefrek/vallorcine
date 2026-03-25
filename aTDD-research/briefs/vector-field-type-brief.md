---
feature: "Add VectorType to FieldType hierarchy with fixed dimensions and float precision"
slug: "vector-field-type"
created: "2026-03-17"
status: "scoped"
---

# Feature Brief — vector-field-type

## Summary
Add a `VectorType(Primitive elementType, int dimensions)` record to the sealed `FieldType` hierarchy, constrained to FLOAT16/FLOAT32 element types and a fixed positive dimension count. Update `IndexRegistry` validation to require `VectorType` (not `ArrayType`) for VECTOR indices, and derive `vectorDimensions` from the schema field type rather than `IndexDefinition`. Remove the legacy `ArrayType(FLOAT32/FLOAT16)` vector index path.

## Actors
Library consumers defining schemas and creating vector indices.

## Inputs
- Element precision (FLOAT16 or FLOAT32) and dimension count when defining a vector field
- Schema field name when creating a VECTOR index

## Outputs / Side Effects
- New `FieldType.VectorType` record in the sealed hierarchy
- `FieldType.vector(Primitive, int)` static factory method
- `IndexDefinition.vectorDimensions` removed; dimensions derived from schema's `VectorType`
- `IndexRegistry` validation updated: VECTOR index requires `VectorType` field
- `DocumentSerializer` updated to serialize/deserialize `VectorType` fields (fixed-length float arrays)

## Business Rules
- `VectorType` element type must be FLOAT16 or FLOAT32 — reject others at construction
- Dimensions must be positive — reject ≤ 0 at construction
- All records for a vector field must have exactly `dimensions` elements — validate at insert time
- A VECTOR index can only be created on a `VectorType` field — `ArrayType` no longer qualifies

## Error Cases
- `IllegalArgumentException` if `VectorType` constructed with non-float element type or dimensions ≤ 0
- `IllegalArgumentException` if `IndexRegistry` encounters a VECTOR index on a non-`VectorType` field
- Validation error at document insert if vector length ≠ field's declared dimensions

## Explicit Out of Scope
- Implementing `VectorFieldIndex` (currently a stub — remains a stub)
- Changes to `jlsm-vector` module internals
- Supporting element types beyond FLOAT16/FLOAT32

## Acceptance Criteria
1. `FieldType.VectorType` exists as a permitted implementation of the sealed interface
2. `FieldType.vector(FLOAT32, 128)` returns a `VectorType` with correct element type and dimensions
3. `IndexDefinition` no longer carries `vectorDimensions` — it is derived from the schema
4. `IndexRegistry` rejects VECTOR index on `ArrayType` fields
5. `IndexRegistry` accepts VECTOR index on `VectorType` fields
6. `DocumentSerializer` correctly round-trips documents with vector fields
7. All existing tests updated; no regressions in `./gradlew check`

## Open Assumptions
- `VectorType` serialization in `DocumentSerializer` uses the same encoding as the current `ArrayType(FLOAT32/FLOAT16)` path (fixed-length, no length prefix needed since dimensions are known from schema)
- `SimilarityFunction` remains on `IndexDefinition` (it's an index concern, not a type concern)

## Performance Expectations
- No measurable performance change — this is a type-system / validation change

## Project Context
- Language: Java 25
- Framework: none — pure library
- Test framework: JUnit Jupiter (JUnit 5)
