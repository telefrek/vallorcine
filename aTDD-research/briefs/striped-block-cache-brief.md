---
feature: "Striped/sharded LruBlockCache for multi-threaded performance"
slug: "striped-block-cache"
created: "2026-03-17"
status: "scoped"
---

# Feature Brief — striped-block-cache

## Summary
Add a new `StripedBlockCache` class that implements `BlockCache` by partitioning the key space across N independent `LruBlockCache` stripes, each with its own lock. This eliminates the single-lock contention bottleneck identified in perf findings (75% throughput drop at 2 threads). The existing `LruBlockCache` remains available. Static factory methods on `LruBlockCache` — `getMultiThreaded()` and `getSingleThreaded()` — provide the recommended entry points, making the choice explicit to consumers.

## Actors
- SSTable readers (concurrent `get`/`put` callers)
- Compaction engine (`evict` after SSTable removal)
- Consumer code wiring the cache via `BlockCache` interface and `LruBlockCache` factory methods

## Inputs
- `stripeCount` (number of independent LRU shards, configurable via builder)
- `capacity` (total capacity, divided across stripes)
- Standard `BlockCache` parameters: `sstableId`, `blockOffset`, `MemorySegment block`

## Outputs / Side Effects
- Same `BlockCache` contract — transparent to callers
- Near-linear throughput scaling under concurrent access

## Business Rules
- Factory methods on `LruBlockCache`: `getMultiThreaded()` returns a `StripedBlockCache.Builder`, `getSingleThreaded()` returns a `LruBlockCache.Builder`
- Stripe selection: hash `(sstableId, blockOffset)` to determine stripe index
- Capacity is divided evenly across stripes (total capacity / stripeCount per stripe)
- Each stripe is an independent `LruBlockCache` with its own lock and eviction
- `evict(sstableId)` must visit all stripes (entries for one SSTable may span stripes)
- `size()` returns sum across all stripes; `capacity()` returns total capacity
- Default stripe count: sensible default (e.g., number of available processors, capped)

## Error Cases
- `stripeCount <= 0` → `IllegalArgumentException`
- `capacity < stripeCount` → `IllegalArgumentException` (each stripe needs at least 1)
- Same validation as `LruBlockCache` for `blockOffset < 0`, null blocks

## Explicit Out of Scope
- Changing the `BlockCache` interface
- Caffeine-style concurrent LRU or other eviction policies
- Weighted/byte-based capacity (stays entry-count based)

## Acceptance Criteria
- `StripedBlockCache` implements `BlockCache` and passes all existing `LruBlockCacheTest` scenarios adapted for the new class
- `LruBlockCache.getMultiThreaded()` and `LruBlockCache.getSingleThreaded()` factory methods return the correct builder types
- Existing `LruBlockCacheBenchmark` contention benchmarks show improved multi-thread throughput when run against `StripedBlockCache`
- Javadoc on the factory methods documents which to choose and why

## Open Assumptions
- Stripe selection uses a simple hash (e.g., mix of `sstableId` and `blockOffset`) — no need for consistent hashing since stripes are fixed at construction
- `close()` closes all stripes, accumulating exceptions per the deferred close pattern
- The existing `LruBlockCache.builder()` method remains for backward compatibility

## Performance Expectations
- Near-linear throughput scaling from 1 to 8 threads (vs 75% drop with single-lock)
- Single-thread overhead minimal (one hash + array index per operation)

## Project Context
- Language: Java 25 (Amazon Corretto toolchain)
- Framework: none — pure library
- Test framework: JUnit Jupiter (JUnit 5)
