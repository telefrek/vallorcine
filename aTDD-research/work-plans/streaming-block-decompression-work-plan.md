---
feature: "streaming-block-decompression"
created: "2026-03-18"
status: "complete"
---

# Work Plan — streaming-block-decompression

## Overview

Replace the upfront `decompressAllBlocks()` allocation in `TrieSSTableReader.scan()`
with a lazy `CompressedBlockIterator` that decompresses one block at a time. Add
block caching to `IndexRangeIterator` so consecutive entries in the same block
reuse a single decompressed buffer. Both iterators bypass the shared `BlockCache`
to prevent scan pollution of point-get cache entries.

## Target File

`modules/jlsm-core/src/main/java/jlsm/sstable/TrieSSTableReader.java`

All changes are modifications to this single file. No new files are created.

## Governing ADRs

- `.decisions/sstable-block-compression-format/adr.md` — Compression Offset Map format
- `.decisions/compression-codec-api-design/adr.md` — Open interface + explicit codec list

## KB References

- `.kb/algorithms/compression/block-compression-algorithms.md` — codec characteristics
- `.kb/systems/lsm-index-patterns/index-scan-patterns.md` — validates iterator-local buffer approach

## Constructs

### 1. New private method: `readAndDecompressBlockNoCache(int blockIndex)`

**Location:** `TrieSSTableReader.java`, after `readAndDecompressBlock(int)` (~line 360)

**Contract:**
```java
/**
 * Reads and decompresses a single block by index, bypassing the BlockCache.
 * Used by scan iterators to avoid polluting the shared cache with sequential reads.
 */
private byte[] readAndDecompressBlockNoCache(int blockIndex) throws IOException
```

**Logic:** Same as `readAndDecompressBlock` but without the `blockCache.get()` /
`blockCache.put()` calls. Reads compressed bytes from `eagerData` or `lazyChannel`,
looks up codec from `codecMap`, decompresses, and returns the raw byte array.

**Depends on:** `compressionMap`, `codecMap`, `eagerData`, `lazyChannel`

---

### 2. New inner class: `CompressedBlockIterator`

**Location:** `TrieSSTableReader.java`, after `DataRegionIterator` (~line 669)

**Contract:**
```java
/**
 * Iterates entries from a v2 compressed SSTable by decompressing one block at
 * a time. Only one decompressed block is held in memory at any point —
 * O(single block uncompressed size).
 *
 * <p>Does not interact with the shared BlockCache.
 */
private final class CompressedBlockIterator implements Iterator<Entry> {

    CompressedBlockIterator() { /* decompresses block 0 and parses entries */ }

    @Override public boolean hasNext() { ... }
    @Override public Entry next() { ... }
}
```

**Fields:**
- `int currentBlockIndex` — index of the currently decompressed block
- `List<Entry> blockEntries` — parsed entries from the current decompressed block
- `int entryIdx` — position within `blockEntries`
- `Entry next` — prefetched next entry (null when exhausted)

**Behavior:**
- Constructor: decompresses block 0 via `readAndDecompressBlockNoCache(0)`, parses
  all entries in the block using `EntryCodec.decode()` in a loop (same block-parsing
  logic as `DataRegionIterator`: read 4-byte count, then decode `count` entries).
  Prefetches the first entry.
- `advance()`: if `entryIdx < blockEntries.size()`, take the next entry. Otherwise
  increment `currentBlockIndex`; if `>= compressionMap.blockCount()`, set `next = null`
  and return. Otherwise decompress the next block, parse entries, reset `entryIdx`,
  and take the first entry.
- `hasNext()`: returns `next != null`
- `next()`: returns prefetched entry, calls `advance()`; throws `NoSuchElementException`
  if exhausted.

**Error handling:** `readAndDecompressBlockNoCache` throws `IOException`; wrapped
in `UncheckedIOException` at the iterator boundary.

---

### 3. Modify `scan()` — v2 path

**Location:** `TrieSSTableReader.java`, line 294-297

**Change:** Replace:
```java
byte[] allData = decompressAllBlocks();
return new DataRegionIterator(allData, allData.length);
```
With:
```java
return new CompressedBlockIterator();
```

The v1 path (lines 299-301) remains unchanged.

---

### 4. Modify `IndexRangeIterator` — add block cache fields

**Location:** `TrieSSTableReader.java`, `IndexRangeIterator` class (~line 675)

**New fields:**
```java
private int cachedBlockIndex = -1;
private byte[] cachedBlock = null;
```

**Change in `advance()`:** In the v2 branch (line 690-696), replace:
```java
byte[] block = readAndDecompressBlock(blockIndex);
```
With:
```java
byte[] block;
if (blockIndex == cachedBlockIndex) {
    block = cachedBlock;
} else {
    block = readAndDecompressBlockNoCache(blockIndex);
    cachedBlockIndex = blockIndex;
    cachedBlock = block;
}
```

This reuses the decompressed block for consecutive entries in the same block and
bypasses the shared BlockCache.

---

### 5. (Optional cleanup) `decompressAllBlocks()` becomes dead code

After the `scan()` change, `decompressAllBlocks()` is no longer called. It should
be removed during the refactor cycle to keep the codebase clean.

## Execution Strategy

Single work unit — all constructs are tightly coupled within one file and one
test class. Sequential TDD: write tests first, implement, refactor.

## Test Strategy

Tests go in the existing SSTable test class (or a new focused test class if the
existing one is too large). Key test cases:

1. **Full scan streaming:** Write a v2 SSTable with multiple blocks, `scan()`,
   verify all entries returned in order — same as existing test but confirms the
   new iterator path works.
2. **Range scan block caching:** Write a v2 SSTable, `scan(from, to)` where
   `from` and `to` span entries within the same block — verify entries returned
   correctly (exercises the `cachedBlock` reuse path).
3. **Range scan cross-block:** `scan(from, to)` spanning multiple blocks —
   verify block transition works and entries are correct.
4. **Single-block SSTable:** Edge case — only one block total.
5. **Empty range:** `scan(from, to)` with no matching entries.
6. **v1 unaffected:** Confirm v1 scan paths still work identically (regression guard).
7. **Memory behavior (assertion-level):** Verify that `decompressAllBlocks()` is
   not called — this can be confirmed by removing the method and ensuring
   compilation succeeds after the change.

## Risk Assessment

- **Low risk:** All changes are internal to `TrieSSTableReader`; no public API changes.
- **Low risk:** v1 code paths are untouched.
- **Medium risk:** Block parsing logic in `CompressedBlockIterator` must exactly
  match `DataRegionIterator`'s block format parsing (4-byte count header + entries).
  Mitigated by testing with multi-block SSTables.

## Estimated Effort

- Testing: ~8K tokens
- Implementation: ~6K tokens
- Refactor: ~3K tokens
- Total: ~17K tokens
