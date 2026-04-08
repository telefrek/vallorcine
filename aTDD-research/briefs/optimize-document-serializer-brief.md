---
feature: "Optimize DocumentSerializer deserialization — eliminate toArray copy, precompute schema constants, dispatch table"
slug: "optimize-document-serializer"
created: "2026-03-18"
status: "scoped"
---

# Feature Brief — optimize-document-serializer

## Summary
Optimize `DocumentSerializer.SchemaSerializer.deserialize()` to reduce the 34% scan CPU cost identified by profiling. Three changes: (1) avoid the per-document `segment.toArray()` copy by using `heapBase()` for heap-backed segments with a fallback path for off-heap/mmap'd/remote segments, (2) precompute schema-derived constants (boolCount, mask byte sizes, field-is-boolean flags, field list as array) in the `SchemaSerializer` constructor instead of recomputing per document, (3) replace the per-field `switch` pattern matching in `decodeField` with a precomputed field decoder dispatch table. Target: ~10-12% scan CPU reduction.

## Actors
- `DocumentSerializer.SchemaSerializer` — the inner class implementing `MemorySerializer<JlsmDocument>`
- `DocumentSerializer` — static utility methods for field encoding/decoding

## Inputs
- `MemorySegment` containing serialized document bytes (heap-backed, off-heap, or remote-backed)
- `JlsmSchema` defining field types and order (fixed per serializer instance)

## Outputs / Side Effects
- `JlsmDocument` with deserialized field values — identical output to current implementation
- No change to serialization (encode) path
- No change to the binary format

## Business Rules
- Heap-backed segments (`heapBase().isPresent()`) use the backing array directly with offset — zero-copy
- Off-heap segments (mmap'd, remote) fall back to `toArray()` copy — correct but not zero-copy
- Schema constants computed once in `SchemaSerializer` constructor, not per `deserialize()` call
- Field decoder dispatch table built once per schema, indexed by field position
- Deserialization must produce byte-identical results to the current implementation for all field types
- Schema evolution (write-time field count < current field count) must still work correctly

## Error Cases
- Corrupt data: same behavior as current — `ArrayIndexOutOfBoundsException` or malformed VarInt propagates as-is
- Off-heap segment with insufficient length: same as current — bounds check by MemorySegment API

## Explicit Out of Scope
- Serialization (encode) path optimization
- Lazy field deserialization (deferring String construction until `getString()` is called)
- Primitive boxing elimination (requires `JlsmDocument` model redesign)
- Binary format changes
- SIMD acceleration of scalar field decoding (already used for array types)

## Acceptance Criteria
1. All existing `DocumentSerializer` and `JlsmTable` tests pass — byte-for-byte identical deserialization
2. `heapBase()` fast path avoids `toArray()` allocation for heap-backed segments
3. Off-heap/mmap'd segments fall back correctly to `toArray()` copy
4. `countBoolFieldsUpTo()` is not called during deserialization — constants precomputed
5. Field decoding uses dispatch table instead of `switch` pattern matching
6. Perf-review scratch benchmark shows measurable scan throughput improvement

## Open Assumptions
- The JIT compiler does not already optimize away the `toArray()` copy for heap-backed segments (profiler evidence suggests it does not — 103 samples in copy frames)
- Field decoder dispatch table via `@FunctionalInterface` lambdas will inline well under JIT — needs benchmark validation
- Off-heap segment fallback path performance is acceptable (same as current behavior)

## Performance Expectations
- Baseline: DocumentSerializer deserialization = 34% of scan CPU (432 profiler samples)
- Target: ~10-12% reduction in deserialization CPU
  - `toArray()` elimination: ~8% (103 samples)
  - Schema constant precomputation: ~1.5% (19 samples)
  - Dispatch table: ~1-2% estimated
- Validation: perf-review scratch benchmark comparing scan throughput before/after

## Project Context
- Language: Java 25 (Amazon Corretto)
- Framework: none — pure library
- Test framework: JUnit Jupiter (JUnit 5)
