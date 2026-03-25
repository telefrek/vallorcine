---
feature: "striped-block-cache"
created: "2026-03-17"
status: "complete"
---

# Work Plan — striped-block-cache

## References

| Reference | Path |
|-----------|------|
| Feature brief | `.feature/striped-block-cache/brief.md` |
| Domain analysis | `.feature/striped-block-cache/domains.md` |
| ADR: stripe hash function | `.decisions/stripe-hash-function/adr.md` |
| ADR: cross-stripe eviction | `.decisions/cross-stripe-eviction/adr.md` |
| BlockCache interface | `modules/jlsm-core/src/main/java/jlsm/core/cache/BlockCache.java` |
| LruBlockCache implementation | `modules/jlsm-core/src/main/java/jlsm/cache/LruBlockCache.java` |

## Existing Constructs

| Construct | Path | Change |
|-----------|------|--------|
| `BlockCache` interface | `modules/jlsm-core/src/main/java/jlsm/core/cache/BlockCache.java` | No changes — implement as-is |
| `LruBlockCache` class | `modules/jlsm-core/src/main/java/jlsm/cache/LruBlockCache.java` | Add `getMultiThreaded()` and `getSingleThreaded()` static factory methods |

## New Constructs

| Construct | Path | Purpose |
|-----------|------|---------|
| `StripedBlockCache` | `modules/jlsm-core/src/main/java/jlsm/cache/StripedBlockCache.java` | Implements `BlockCache` by partitioning key space across N independent `LruBlockCache` stripes |

## Stub Files Written

| File | Status |
|------|--------|
| `modules/jlsm-core/src/main/java/jlsm/cache/StripedBlockCache.java` | Created — all methods throw `UnsupportedOperationException` |

## Contract Definitions

### StripedBlockCache

**Constructor (via Builder):**
- `stripeCount` (int, default `min(availableProcessors(), 16)`) — number of independent LRU shards
- `capacity` (long, required) — total capacity divided evenly across stripes

**Stripe index — `stripeIndex(long sstableId, long blockOffset, int stripeCount)`:**
- Splitmix64 finalizer (Stafford variant 13) per ADR `.decisions/stripe-hash-function/adr.md`
- Golden-ratio combining: `sstableId * 0x9E3779B97F4A7C15L + blockOffset`
- Three multiply-XOR-shift stages, non-negative mask, modulo stripeCount
- Package-private static method (testable but not public API)

**`get(long sstableId, long blockOffset)` → `Optional<MemorySegment>`:**
- Delegates to `stripes[stripeIndex(sstableId, blockOffset, stripeCount)].get(...)`
- Validates `blockOffset >= 0`

**`put(long sstableId, long blockOffset, MemorySegment block)` → void:**
- Delegates to `stripes[stripeIndex(sstableId, blockOffset, stripeCount)].put(...)`
- Validates `blockOffset >= 0`, `block != null`

**`evict(long sstableId)` → void:**
- Sequential loop over all stripes per ADR `.decisions/cross-stripe-eviction/adr.md`
- Each stripe acquires/releases its own lock independently

**`size()` → long:**
- Returns sum of `stripe.size()` across all stripes

**`capacity()` → long:**
- Returns total capacity (stored field, not recomputed)

**`close()` → void:**
- Deferred exception pattern: close all stripes, accumulate exceptions, throw first with others suppressed

### LruBlockCache Extensions

**`getMultiThreaded()` → `StripedBlockCache.Builder`:**
- Static factory method returning `StripedBlockCache.builder()`

**`getSingleThreaded()` → `LruBlockCache.Builder`:**
- Static factory method returning `LruBlockCache.builder()`

### Validation Rules

| Condition | Exception |
|-----------|-----------|
| `stripeCount <= 0` | `IllegalArgumentException` |
| `capacity < stripeCount` | `IllegalArgumentException` ("each stripe needs at least 1") |
| `blockOffset < 0` on get/put | `IllegalArgumentException` |
| `block == null` on put | `NullPointerException` |

## Implementation Order

This is a single work unit (no work-unit splitting needed).

1. **Test Writer** — Write `StripedBlockCacheTest` covering:
   - Construction with valid parameters
   - Construction validation (bad stripeCount, bad capacity)
   - `stripeIndex` distribution (package-private access from test)
   - `get`/`put` delegation (single stripe and multi-stripe)
   - `evict` across all stripes
   - `size` aggregation
   - `capacity` returns total
   - `close` with deferred exception pattern
   - Concurrent get/put correctness (multi-threaded stress)
   - `LruBlockCache.getMultiThreaded()` returns `StripedBlockCache.Builder`
   - `LruBlockCache.getSingleThreaded()` returns `LruBlockCache.Builder`

2. **Code Writer** — Implement:
   - `StripedBlockCache` — fill in all stub methods
   - `LruBlockCache` — add `getMultiThreaded()` and `getSingleThreaded()` static methods

3. **Refactor Agent** — Review for:
   - Coding guidelines compliance (defensive assertions, minimal scope, records)
   - Deferred close pattern correctness
   - Javadoc completeness
   - No unnecessary allocations in hot path
