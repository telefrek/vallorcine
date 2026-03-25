---
feature: "Add block-level compression to SSTable storage"
slug: "block-compression"
created: "2026-03-17"
status: "scoped"
---

# Feature Brief — block-compression

## Summary
Add block-level compression to SSTable data blocks in `jlsm-core`. Compression is configurable per-tree via the builder API, allowing different trees (indices vs. table data) to use different codecs or parameters. The SSTable format encodes compression metadata per-block so compressed and uncompressed SSTables are fully interoperable.

## Actors
- Library consumers configuring compression via the tree/writer builder API
- `TrieSSTableWriter` (compresses blocks on flush)
- `TrieSSTableReader` (decompresses blocks on read)
- `BlockCache` (caches decompressed blocks)

## Inputs
- Compression codec selection + configuration (algorithm, level) at tree build time
- Raw key/value entry data flowing through the write path

## Outputs / Side Effects
- Compressed data blocks in SSTable files on disk
- Updated SSTable footer/metadata encoding compression type per block
- Reduced on-disk size and network I/O for remote-backed stores

## Business Rules
- Compression is per data block, not per file — each block independently decompressed
- Codec is configurable per tree instance via builder; default is no compression (backward compatible)
- SSTable format must self-describe compression: readers determine codec from block/footer metadata, not from tree config
- No external runtime dependencies; use `java.util.zip.Deflater`/`Inflater` for the initial codec; additional codecs (e.g. a hand-rolled LZ4-style fast codec) may be added after KB research
- Block cache stores decompressed blocks — compression/decompression happens below the cache layer

## Error Cases
- Corrupted compressed block → `IOException` with descriptive message; do not crash
- Unknown compression codec in metadata → `IOException` identifying the unknown codec ID
- Decompression produces unexpected size → assertion failure + `IOException`

## Explicit Out of Scope
- WAL compression (separate concern, different write pattern)
- Key index / bloom filter compression (these are small metadata structures)
- Implementing a custom fast codec in this feature (may follow from research as a future feature)
- Compaction-time re-compression with a different codec

## Acceptance Criteria
1. `TrieSSTableWriter` accepts a `CompressionCodec` and writes compressed data blocks
2. `TrieSSTableReader` reads both compressed and uncompressed SSTables transparently
3. Round-trip tests: write with compression, read back, verify identical entries
4. Interop tests: write without compression, read with compression configured (and vice versa)
5. `./gradlew check` passes cleanly

## Open Assumptions
- Deflate via `java.util.zip` provides acceptable compression ratios for the initial implementation; research may reveal better no-dependency alternatives
- Compression metadata fits in the existing SSTable footer structure or a small per-block header addition
- Block cache already operates on deserialized block content, so no cache format changes are needed

## Performance Expectations
- Compression adds CPU overhead to write path; decompression adds CPU overhead to read path — both should be bounded and measurable via existing JMH infrastructure
- Net I/O reduction should outweigh CPU cost for remote backends
- No performance regression for uncompressed mode (no-op codec path)

## Project Context
- Language: Java 25 (Amazon Corretto toolchain)
- Framework: none — pure library
- Test framework: JUnit Jupiter (JUnit 5)
