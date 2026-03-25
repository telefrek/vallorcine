---
feature: "add float16 support to vector indexing"
slug: "float16-vector-support"
created: "2026-03-12"
status: "scoped"
---

# Feature Brief — float16-vector-support

## Summary
Add float16 (half-precision) vector storage and distance computation to both IvfFlat and Hnsw
implementations in jlsm-vector. Vectors are accepted as float[] at the API boundary and quantized
to float16 internally. A discoverable property on VectorIndex indicates the precision of the index.
Targets ~50% storage reduction per vector. Float16 indices are separate from float32 indices — no
mixed-precision, no migration path.

## Actors
Library consumers building vector search applications who want to trade precision for storage
savings on large collections.

## Inputs
- float[] vectors (same API as today)
- Builder configuration: explicit precision selection (float32 or float16)

## Outputs / Side Effects
- Vectors stored as dim×2 bytes (float16) instead of dim×4 bytes (float32)
- Distance computation performed in half-precision
- IvfFlat centroids remain float32 for assignment quality
- HNSW neighbor links unchanged (doc-ID bytes, not vector data)

## Business Rules
- Precision is an explicit builder choice — never auto-selected
- float[] accepted at API boundary; downcast to float16 internally on write
- Queries accepted as float[], downcast before scoring
- A property on VectorIndex exposes the configured precision
- Float16 and float32 indices are fully independent types

## Error Cases
- NaN / Infinity in float[] that can't be represented in float16: document behavior (IEEE 754
  half-precision rules apply)
- Subnormal / overflow values that lose precision on downcast

## Explicit Out of Scope
- Automatic precision selection (deferred — explicit choice only)
- Migration between float32 and float16 indices
- Quantization-aware retraining or centroid recomputation
- Mixed-precision within a single index
- Changes to the float32 code path

## Acceptance Criteria
- Both IvfFlat and Hnsw support float16 via builder configuration
- Storage uses dim×2 bytes per vector (posting lists / node values)
- Distance computation uses float16 arithmetic
- IvfFlat centroids remain float32
- VectorIndex exposes a precision property
- Recall delta vs float32 is measured and documented
- Existing float32 indices are unaffected

## Performance Expectations
- ~50% storage reduction per vector vs float32
- Recall regression measured and documented (no hard threshold)

## Open Assumptions
- Java's Float.float16ToFloat / Float.floatToFloat16 (Java 20+) will be used for conversion
- Distance computation: vectors are stored as float16 (short[]) but decoded to float32 for SIMD
  computation via FloatVector. Precision loss comes from storage quantization (values rounded to
  float16 on write). True float16 SIMD arithmetic is not available in Java 25's Vector API —
  Float16Vector is in active development (JDK-8370691) and expected in JDK 27+. When it ships,
  the inner distance loop can be swapped to native float16 SIMD without changing storage format.

## Project Context
- Language: Java 25 (Amazon Corretto toolchain)
- Framework: none — pure library
- Test framework: JUnit Jupiter (JUnit 5)
