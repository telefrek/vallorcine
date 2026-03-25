---
feature: "float16-vector-support"
created: "2026-03-13"
language: "Java 25"
---

# Work Plan — float16-vector-support

## References
- Brief: [brief.md](brief.md)
- Domains: [domains.md](domains.md)
- Governing ADRs: none (all domains resolved without ADR)

## Existing Constructs

| Construct | File | Usage |
|-----------|------|-------|
| VectorIndex | modules/jlsm-core/.../jlsm/core/indexing/VectorIndex.java | extend — add `precision()` method |
| LsmVectorIndex | modules/jlsm-vector/.../jlsm/vector/LsmVectorIndex.java | extend — add float16 encode/decode helpers + precision-dispatch methods |
| AbstractBuilder | modules/jlsm-vector/.../jlsm/vector/LsmVectorIndex.java:242 | extend — add `.precision()` builder method |
| IvfFlat | modules/jlsm-vector/.../jlsm/vector/LsmVectorIndex.java:306 | extend — float16 storage for posting vectors, centroids stay float32 |
| Hnsw | modules/jlsm-vector/.../jlsm/vector/LsmVectorIndex.java:638 | extend — float16 storage for node vector portion |

## New Constructs

| Construct | File | Contract summary |
|-----------|------|-----------------|
| VectorPrecision | modules/jlsm-core/.../jlsm/core/indexing/VectorPrecision.java | Enum: FLOAT32(4), FLOAT16(2) with `bytesPerComponent()` |

## Stub Files Written

| File | Status |
|------|--------|
| modules/jlsm-core/.../jlsm/core/indexing/VectorPrecision.java | complete (enum, fully implemented) |
| modules/jlsm-core/.../jlsm/core/indexing/VectorIndex.java | stubbed (`precision()` method added) |
| modules/jlsm-vector/.../jlsm/vector/LsmVectorIndex.java | stubbed (encode/decode stubs + builder/constructor wiring) |

## Contract Definitions

### VectorPrecision (NEW)
**File:** `modules/jlsm-core/src/main/java/jlsm/core/indexing/VectorPrecision.java`
**Governed by:** domains.md — Float16 encoding/conversion
**Signature:** `public enum VectorPrecision { FLOAT32(4), FLOAT16(2) }`
**Contract:**
- Enum with two values: FLOAT32 and FLOAT16
- `bytesPerComponent()` returns 4 or 2 respectively
- Used as builder parameter and VectorIndex property

### VectorIndex.precision() (EXTEND)
**File:** `modules/jlsm-core/src/main/java/jlsm/core/indexing/VectorIndex.java`
**Governed by:** brief — "A property on VectorIndex exposes the configured precision"
**Signature:** `VectorPrecision precision()`
**Contract:**
- Returns the precision configured at build time
- Never null
- Both IvfFlat and Hnsw implementations must implement this

### encodeFloat16s (EXTEND LsmVectorIndex)
**File:** `modules/jlsm-vector/src/main/java/jlsm/vector/LsmVectorIndex.java`
**Governed by:** domains.md — Float16 encoding/conversion
**Signature:** `static byte[] encodeFloat16s(float[] floats)`
**Contract:**
- Receives: float[] (must not be null)
- Returns: byte[] of length `floats.length * 2`
- Each float converted via `Float.floatToFloat16(float)` → short, stored big-endian
- Side effects: none
- Error conditions: assert on null input

### decodeFloat16s (EXTEND LsmVectorIndex)
**File:** `modules/jlsm-vector/src/main/java/jlsm/vector/LsmVectorIndex.java`
**Governed by:** domains.md — Float16 encoding/conversion
**Signature:** `static float[] decodeFloat16s(byte[] bytes, int dimensions)`
**Contract:**
- Receives: byte[] (must not be null, length must equal dimensions * 2), int dimensions
- Returns: float[] of length `dimensions`
- Each 2-byte pair read as big-endian short, converted via `Float.float16ToFloat(short)`
- Side effects: none
- Error conditions: assert on null input, assert on byte count mismatch

### encodeVector (EXTEND LsmVectorIndex)
**File:** `modules/jlsm-vector/src/main/java/jlsm/vector/LsmVectorIndex.java`
**Governed by:** domains.md — Float16 SIMD distance computation
**Signature:** `static byte[] encodeVector(float[] floats, VectorPrecision precision)`
**Contract:**
- Receives: float[] (must not be null), VectorPrecision (must not be null)
- Returns: byte[] — dispatches to encodeFloats (FLOAT32) or encodeFloat16s (FLOAT16)
- Side effects: none

### decodeVector (EXTEND LsmVectorIndex)
**File:** `modules/jlsm-vector/src/main/java/jlsm/vector/LsmVectorIndex.java`
**Governed by:** domains.md — Float16 SIMD distance computation
**Signature:** `static float[] decodeVector(byte[] bytes, int dimensions, VectorPrecision precision)`
**Contract:**
- Receives: byte[] (must not be null), int dimensions, VectorPrecision (must not be null)
- Returns: float[] of length `dimensions` — always float32 for SIMD computation
- Dispatches to decodeFloats (FLOAT32) or decodeFloat16s (FLOAT16)
- Side effects: none

### IvfFlat float16 storage (EXTEND)
**File:** `modules/jlsm-vector/src/main/java/jlsm/vector/LsmVectorIndex.java`
**Governed by:** brief — "IvfFlat centroids remain float32"
**Contract:**
- `index()`: posting-list vector encoded via `encodeVector(vector, precision)` instead of `encodeFloats(vector)`
- `index()`: centroids always encoded via `encodeFloats(vector)` regardless of precision
- `search()`: posting-list vectors decoded via `decodeVector(bytes, dims, precision)` — result is float32 for SIMD
- `search()`: centroids always decoded via `decodeFloats(bytes, dims)` regardless of precision
- `precision()`: returns the configured VectorPrecision
- Error conditions: unchanged from float32 path

### Hnsw float16 storage (EXTEND)
**File:** `modules/jlsm-vector/src/main/java/jlsm/vector/LsmVectorIndex.java`
**Governed by:** brief — "HNSW neighbor links unchanged"
**Contract:**
- `encodeNode()`: vector portion uses `encodeVector(vector, precision)` — size changes from `dim*4` to `dim*precision.bytesPerComponent()`
- `decodeNode()`: vector portion decoded via `decodeVector(bytes, dims, precision)` — vecBytes computed as `bytes.length - off`, dims as `vecBytes / precision.bytesPerComponent()`
- `index()`, `search()`: all `scoreNode()` calls use decoded float32 vectors — SIMD path unchanged
- Neighbor links: unchanged (doc-ID bytes, not vector data)
- `precision()`: returns the configured VectorPrecision
- Error conditions: unchanged from float32 path

## Implementation Order
1. `encodeFloat16s` / `decodeFloat16s` — no dependencies beyond `Float.floatToFloat16/float16ToFloat`
2. `encodeVector` / `decodeVector` — depends on (1)
3. `IvfFlat` float16 threading — depends on (2); replace `encodeFloats`/`decodeFloats` calls with precision-dispatch
4. `Hnsw` float16 threading — depends on (2); update `encodeNode`/`decodeNode` + sizing
