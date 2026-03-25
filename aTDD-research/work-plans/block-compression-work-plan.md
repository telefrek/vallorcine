---
feature: "block-compression"
created: "2026-03-17"
status: "complete"
---

# Work Plan — block-compression

## References

- **Brief:** [brief.md](brief.md)
- **Domains:** [domains.md](domains.md)
- **ADR — Codec API:** [.decisions/compression-codec-api-design/adr.md](../../.decisions/compression-codec-api-design/adr.md)
- **ADR — SSTable Format:** [.decisions/sstable-block-compression-format/adr.md](../../.decisions/sstable-block-compression-format/adr.md)
- **KB — Algorithms:** [.kb/algorithms/compression/block-compression-algorithms.md](../../.kb/algorithms/compression/block-compression-algorithms.md)

---

## Existing Constructs (to extend)

### 1. SSTableFormat
- **Location:** `modules/jlsm-core/src/main/java/jlsm/sstable/internal/SSTableFormat.java`
- **Changes:** Add `MAGIC_V2` (0x4A4C534D53535402L), `FOOTER_SIZE_V2` (64), `COMPRESSION_MAP_ENTRY_SIZE` (17) constants
- **Governing ADR:** .decisions/sstable-block-compression-format/adr.md

### 2. TrieSSTableWriter
- **Location:** `modules/jlsm-core/src/main/java/jlsm/sstable/TrieSSTableWriter.java`
- **Changes:** Accept `CompressionCodec` parameter; compress each data block before writing; build `CompressionMap` entries; write compression map section; write v2 footer with map offset/length; key index entries use (blockIndex, intraBlockOffset) format; if compressed >= uncompressed, store as NoneCodec in map
- **Governing ADR:** .decisions/sstable-block-compression-format/adr.md, .decisions/compression-codec-api-design/adr.md

### 3. TrieSSTableReader
- **Location:** `modules/jlsm-core/src/main/java/jlsm/sstable/TrieSSTableReader.java`
- **Changes:** Accept `CompressionCodec...` varargs; detect v1/v2 by magic byte; for v2: read compression map, build `Map<Byte, CompressionCodec>` from varargs, decompress blocks on read using map entries; for v1: fall back to current logic; throw IOException on unknown codec ID
- **Governing ADR:** .decisions/sstable-block-compression-format/adr.md, .decisions/compression-codec-api-design/adr.md

### 4. StandardLsmTree.Builder
- **Location:** `modules/jlsm-core/src/main/java/jlsm/tree/StandardLsmTree.java`
- **Changes:** Add `.compression(CompressionCodec)` method defaulting to `CompressionCodec.none()`; pass codec to writer factory and reader factory lambdas
- **Governing ADR:** .decisions/compression-codec-api-design/adr.md

### 5. module-info.java
- **Location:** `modules/jlsm-core/src/main/java/module-info.java`
- **Changes:** Add `exports jlsm.core.compression;`

---

## New Constructs (stubs written)

### 1. CompressionCodec (interface)
- **Location:** `modules/jlsm-core/src/main/java/jlsm/core/compression/CompressionCodec.java`
- **Package:** `jlsm.core.compression` (exported)
- **Visibility:** public interface (open, non-sealed)
- **Governing ADR:** .decisions/compression-codec-api-design/adr.md

#### Contract

**`byte codecId()`**
- Returns the unique byte identifier for this codec
- Stored per-block in the compression map
- Known IDs: 0x00 (none), 0x02 (deflate)

**`byte[] compress(byte[] input, int offset, int length)`**
- Compresses `length` bytes starting at `offset` from `input`
- Returns a new byte array containing the compressed data
- Params: `input` (non-null), `offset` (>= 0), `length` (>= 0, offset+length <= input.length)
- Throws: `IllegalArgumentException` if offset/length out of bounds
- Throws: `UncheckedIOException` if compression fails
- Side effects: none (stateless)

**`byte[] decompress(byte[] input, int offset, int length, int uncompressedLength)`**
- Decompresses `length` bytes starting at `offset` from `input`
- Returns a new byte array of exactly `uncompressedLength` bytes
- Params: `input` (non-null), `offset` (>= 0), `length` (>= 0), `uncompressedLength` (> 0)
- Throws: `IllegalArgumentException` if offset/length out of bounds
- Throws: `UncheckedIOException` if decompression fails or output size mismatch
- Side effects: none (stateless)

**`static CompressionCodec none()`**
- Returns `NoneCodec.INSTANCE` (singleton)

**`static CompressionCodec deflate()`**
- Returns `new DeflateCodec(6)`

**`static CompressionCodec deflate(int level)`**
- Params: `level` (0–9)
- Returns `new DeflateCodec(level)`
- Throws: `IllegalArgumentException` if level outside 0–9

---

### 2. NoneCodec (package-private final class)
- **Location:** `modules/jlsm-core/src/main/java/jlsm/core/compression/NoneCodec.java`
- **Package:** `jlsm.core.compression`
- **Visibility:** package-private
- **Governing ADR:** .decisions/compression-codec-api-design/adr.md

#### Contract

- `codecId()` returns `0x00`
- `compress(input, offset, length)` returns `Arrays.copyOfRange(input, offset, offset + length)`
- `decompress(input, offset, length, uncompressedLength)` returns `Arrays.copyOfRange(input, offset, offset + length)`
  - Asserts `length == uncompressedLength`; throws `UncheckedIOException` if mismatch
- Singleton via `static final NoneCodec INSTANCE`
- Thread-safe (stateless)

---

### 3. DeflateCodec (package-private final class)
- **Location:** `modules/jlsm-core/src/main/java/jlsm/core/compression/DeflateCodec.java`
- **Package:** `jlsm.core.compression`
- **Visibility:** package-private
- **Governing ADR:** .decisions/compression-codec-api-design/adr.md, .kb/algorithms/compression/block-compression-algorithms.md

#### Contract

- Constructor: `DeflateCodec(int level)` — validates level 0–9, stores as final field
- `codecId()` returns `0x02`
- `compress(input, offset, length)`:
  - Creates `Deflater(level)` in try-finally; calls `end()` in finally
  - `setInput(input, offset, length)` → `finish()` → `deflate()` loop into output buffer
  - Returns trimmed byte array of compressed data
  - Throws `UncheckedIOException` wrapping any failure
- `decompress(input, offset, length, uncompressedLength)`:
  - Creates `Inflater()` in try-finally; calls `end()` in finally
  - `setInput(input, offset, length)` → `inflate()` into `new byte[uncompressedLength]`
  - Asserts actual inflated count == `uncompressedLength`; throws `UncheckedIOException` if mismatch
  - Returns the output array
- Thread-safe (no shared mutable state; Deflater/Inflater per-call)

---

### 4. CompressionMap (public final class)
- **Location:** `modules/jlsm-core/src/main/java/jlsm/sstable/internal/CompressionMap.java`
- **Package:** `jlsm.sstable.internal` (not exported)
- **Visibility:** public (within module, not exported)
- **Governing ADR:** .decisions/sstable-block-compression-format/adr.md

#### Contract

**`record Entry(long blockOffset, int compressedSize, int uncompressedSize, byte codecId)`**
- Value type for a single block's compression metadata

**`CompressionMap(List<Entry> entries)`**
- Stores a defensive copy as `List.copyOf(entries)`
- Throws: `NullPointerException` if entries is null

**`List<Entry> entries()`**
- Returns the unmodifiable list of entries

**`Entry entry(int blockIndex)`**
- Returns `entries.get(blockIndex)`
- Throws: `IndexOutOfBoundsException` if out of range

**`int blockCount()`**
- Returns `entries.size()`

**`byte[] serialize()`**
- Writes `[blockCount(4)][entries: blockOffset(8) + compressedSz(4) + uncompressSz(4) + codecId(1)]`
- All multi-byte values big-endian
- Returns byte array of size `4 + blockCount * 17`

**`static CompressionMap deserialize(byte[] data)`**
- Reads the binary format produced by `serialize()`
- Throws: `IllegalArgumentException` if data is malformed (wrong length, etc.)
- Throws: `NullPointerException` if data is null

---

## Stub Files Written

| Stub | Path |
|------|------|
| CompressionCodec | `modules/jlsm-core/src/main/java/jlsm/core/compression/CompressionCodec.java` |
| NoneCodec | `modules/jlsm-core/src/main/java/jlsm/core/compression/NoneCodec.java` |
| DeflateCodec | `modules/jlsm-core/src/main/java/jlsm/core/compression/DeflateCodec.java` |
| CompressionMap | `modules/jlsm-core/src/main/java/jlsm/sstable/internal/CompressionMap.java` |

---

## Work Units

### WU-1: Compression Codec Types
**Constructs:** CompressionCodec, NoneCodec, DeflateCodec, module-info.java export
**Dependencies:** none
**Scope:**
- Implement `NoneCodec.compress()` and `decompress()` (passthrough copy)
- Implement `DeflateCodec.compress()` and `decompress()` (Deflater/Inflater with per-call lifecycle)
- Input validation and defensive assertions in all methods
- Add `exports jlsm.core.compression;` to module-info.java
- Add `--add-exports jlsm.core/jlsm.core.compression=ALL-UNNAMED` to test jvmArgs if needed (public package — not needed)

**Test focus:**
- NoneCodec round-trip: compress then decompress returns identical data
- NoneCodec identity: codecId == 0x00
- DeflateCodec round-trip: compress then decompress returns identical data for various inputs
- DeflateCodec levels: all levels 0–9 produce valid output
- DeflateCodec with empty input
- DeflateCodec with large input (> 64 KiB)
- Invalid arguments: null input, negative offset, out-of-bounds length
- Static factory methods return correct types
- DeflateCodec level validation (negative, > 9)

---

### WU-2: SSTable v2 Format with Compression
**Constructs:** CompressionMap, SSTableFormat (extend), TrieSSTableWriter (extend), TrieSSTableReader (extend), StandardLsmTree.Builder (extend)
**Dependencies:** WU-1
**Scope:**
- Implement `CompressionMap` serialization/deserialization
- Add v2 constants to `SSTableFormat`
- Modify `TrieSSTableWriter` to accept `CompressionCodec`, compress blocks, write compression map, write v2 footer
- Modify `TrieSSTableReader` to accept `CompressionCodec...`, detect v1/v2 by magic, read compression map, decompress on read
- Modify key index to use (blockIndex, intraBlockOffset) in v2
- Modify `StandardLsmTree.Builder` to accept `.compression(CompressionCodec)` and thread it through
- Backward compatibility: v2 reader reads v1 files, v1 reader cannot read v2 files (fails with unknown magic)

**Test focus:**
- CompressionMap round-trip serialization
- CompressionMap edge cases: empty map, single entry, many entries
- SSTableFormat v2 constants are correct values
- TrieSSTableWriter with NoneCodec produces readable v2 file
- TrieSSTableWriter with DeflateCodec compresses blocks and file is smaller
- TrieSSTableReader reads v2 files with NoneCodec
- TrieSSTableReader reads v2 files with DeflateCodec
- TrieSSTableReader reads v1 files (backward compatibility)
- Round-trip: write with deflate, read back, verify all entries identical
- Interop: write v1, read with v2 reader; write v2 with none, read correctly
- Unknown codec ID in v2 file → IOException
- StandardLsmTree.Builder with compression: full tree write/read round-trip
- Block that doesn't compress well → stored as NoneCodec in map

---

## Implementation Order

1. **WU-1** (no dependencies) — codec types and module export
2. **WU-2** (depends on WU-1) — SSTable format changes and tree builder integration

Execution strategy: **balanced** — WU-1 can start immediately; WU-2 starts after WU-1 completes.
