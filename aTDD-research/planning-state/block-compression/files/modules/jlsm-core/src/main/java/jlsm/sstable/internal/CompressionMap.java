package jlsm.sstable.internal;

import java.util.List;

/**
 * Compression offset map for SSTable v2 format.
 *
 * <p>Maps each data block to its on-disk position, compressed size, uncompressed
 * size, and the codec ID used for compression. This metadata is stored as a
 * contiguous section in the SSTable file between the data blocks and the key
 * index, and is loaded eagerly at reader open time.
 *
 * <h3>Binary format</h3>
 * <pre>
 *   [blockCount — 4 bytes, big-endian int]
 *   [entries × blockCount]:
 *     blockOffset      — 8 bytes, big-endian long
 *     compressedSize   — 4 bytes, big-endian int
 *     uncompressedSize — 4 bytes, big-endian int
 *     codecId          — 1 byte
 *   Total per entry: 17 bytes
 * </pre>
 *
 * @see <a href="../../.decisions/sstable-block-compression-format/adr.md">ADR: SSTable Block Compression Format</a>
 */
public final class CompressionMap {

    /** Size in bytes of a single compression map entry. */
    public static final int ENTRY_SIZE = 17;

    /**
     * A single entry in the compression map describing one data block.
     *
     * @param blockOffset      absolute file offset of the compressed block data
     * @param compressedSize   size of the block as stored on disk (compressed)
     * @param uncompressedSize original size of the block before compression
     * @param codecId          identifier of the codec used (0x00 = none, 0x02 = deflate)
     */
    public record Entry(long blockOffset, int compressedSize, int uncompressedSize, byte codecId) {
    }

    private final List<Entry> entries;

    /**
     * Creates a compression map from the given entries.
     *
     * @param entries list of per-block compression entries; must not be null
     * @throws NullPointerException if entries is null
     */
    public CompressionMap(List<Entry> entries) {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Returns the list of per-block entries.
     *
     * @return unmodifiable list of entries
     */
    public List<Entry> entries() {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Returns the entry at the given block index.
     *
     * @param blockIndex zero-based block index
     * @return the entry for that block
     * @throws IndexOutOfBoundsException if blockIndex is out of range
     */
    public Entry entry(int blockIndex) {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Returns the number of blocks in this map.
     *
     * @return block count
     */
    public int blockCount() {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Serializes this compression map to its binary representation.
     *
     * @return byte array in the format described in the class javadoc
     */
    public byte[] serialize() {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Deserializes a compression map from its binary representation.
     *
     * @param data byte array in the format described in the class javadoc
     * @return the deserialized compression map
     * @throws IllegalArgumentException if the data is malformed
     * @throws NullPointerException     if data is null
     */
    public static CompressionMap deserialize(byte[] data) {
        throw new UnsupportedOperationException("Not implemented");
    }
}
