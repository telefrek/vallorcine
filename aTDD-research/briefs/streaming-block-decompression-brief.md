---
feature: "Streaming block decompression for compressed SSTable scans"
slug: "streaming-block-decompression"
created: "2026-03-18"
status: "scoped"
---

# Feature Brief — streaming-block-decompression

## Summary
Replace upfront `decompressAllBlocks()` in `TrieSSTableReader.scan()` with lazy per-block decompression during iteration. Apply the same optimization to `scan(fromKey, toKey)` by caching the current decompressed block within the range iterator to avoid redundant re-decompression of the same block for consecutive entries. Target: recover the ~37-39% scan throughput regression measured in the perf-review session (commit 1e70573). Commission research into index-type scan patterns (inverted index, vector index) to inform future BlockCache integration decisions.

## Actors
- `TrieSSTableReader` — the SSTable reader providing `scan()` and `scan(from, to)`
- `DataRegionIterator` — full-scan iterator (currently receives pre-decompressed byte[])
- `IndexRangeIterator` — range-scan iterator (currently calls `readAndDecompressBlock()` per entry)

## Inputs
- v2 compressed SSTable file with compression map
- Optional `BlockCache` (existing behavior for point gets — not involved in this change)

## Outputs / Side Effects
- `scan()` returns an `Iterator<Entry>` that decompresses blocks one at a time as iteration advances
- `scan(from, to)` returns an `Iterator<Entry>` that caches the current decompressed block and reuses it for entries in the same block
- No change to v1 (uncompressed) code paths
- No change to point-get (`get()`) behavior

## Business Rules
- Decompression must be lazy: only decompress a block when the iterator reaches an entry in that block
- Each iterator maintains its own block buffer scoped to its lifetime — no pollution of the shared BlockCache
- The current decompressed block must be reused for consecutive entries in the same block (both full scan and range scan)
- v1 code paths remain completely unchanged
- Iterator must still produce entries in the same order as the current implementation

## Error Cases
- Corrupt compressed block: `UncheckedIOException` propagated from `CompressionCodec.decompress()` — same as current behavior
- Reader closed during iteration: existing `checkNotClosed()` guard applies

## Explicit Out of Scope
- BlockCache integration for scan paths (deferred pending research into index scan patterns)
- Changes to eager-load `open()` / `openLazy()` factory methods
- Changes to the compression codec interface or format
- Streaming decompression within a single block (block-level granularity is sufficient)

## Acceptance Criteria
1. `scan()` on a v2 SSTable does not allocate the full decompressed data array upfront
2. `scan(from, to)` on a v2 SSTable does not re-decompress a block for consecutive entries in the same block
3. All existing SSTable tests pass (v1 and v2, eager and lazy readers)
4. Perf-review scratch benchmark shows measurable improvement in `scanAll` throughput for compressed SSTables vs current implementation

## Research Commission
- **Topic:** Index scan patterns over LSM storage — how do inverted indices (full-text), vector indices (IVF-Flat, HNSW), and secondary indices use the SSTable scan path?
- **Key questions:** Are scans sequential or random-access? Do indices re-scan the same blocks? Would scan-path block caching benefit specific index types? What are typical scan widths (full table vs narrow range)?
- **Purpose:** Inform whether the iterator-local buffer is sufficient long-term or if a scan-aware BlockCache tier is needed for index workloads
- **Timing:** Commission during domain analysis; findings feed into future work, not this implementation

## Open Assumptions
- Block-level lazy decompression granularity is sufficient — we do not need sub-block streaming
- The perf improvement will be most visible at larger entry counts where the upfront allocation cost dominates
- Iterator-local buffer is the correct default; research may recommend a scan-aware cache variant later

## Performance Expectations
- Baseline (current): scanAll with deflate ~37-39% slower than uncompressed
- Target: narrow the gap significantly — decompression CPU is inherent, but eliminating the upfront full-array allocation and copy should recover a portion of the throughput loss
- Memory: peak memory during scan reduced from O(total uncompressed size) to O(single block uncompressed size)

## Project Context
- Language: Java 25 (Amazon Corretto)
- Framework: none — pure library
- Test framework: JUnit Jupiter (JUnit 5)
