package jlsm.core.compression;

/**
 * Compression codec backed by {@link java.util.zip.Deflater} and
 * {@link java.util.zip.Inflater}.
 *
 * <p>The codec ID is {@code 0x02}. The constructor accepts a compression level
 * (0–9) matching the levels defined by {@link java.util.zip.Deflater}.
 *
 * <p>Each call to {@link #compress} and {@link #decompress} creates a fresh
 * {@code Deflater}/{@code Inflater} and calls {@code end()} in a {@code finally}
 * block to release native memory immediately. This avoids retaining native
 * resources across calls and is safe for concurrent use.
 *
 * <p>Package-private — accessed via {@link CompressionCodec#deflate()} and
 * {@link CompressionCodec#deflate(int)}.
 *
 * @see CompressionCodec
 * @see <a href="../../.decisions/compression-codec-api-design/adr.md">ADR: Compression Codec API Design</a>
 * @see <a href="../../.kb/algorithms/compression/block-compression-algorithms.md">KB: Block Compression Algorithms</a>
 */
final class DeflateCodec implements CompressionCodec {

    private final int level;

    /**
     * Creates a Deflate codec with the specified compression level.
     *
     * @param level compression level (0–9)
     * @throws IllegalArgumentException if level is outside the range 0–9
     */
    DeflateCodec(int level) {
        if (level < 0 || level > 9) {
            throw new IllegalArgumentException("Deflate level must be 0–9, got: " + level);
        }
        this.level = level;
    }

    @Override
    public byte codecId() {
        return 0x02;
    }

    @Override
    public byte[] compress(byte[] input, int offset, int length) {
        throw new UnsupportedOperationException("Not implemented");
    }

    @Override
    public byte[] decompress(byte[] input, int offset, int length, int uncompressedLength) {
        throw new UnsupportedOperationException("Not implemented");
    }
}
