package jlsm.core.compression;

import java.util.Arrays;
import java.util.Objects;

/**
 * Passthrough codec that performs no compression or decompression.
 *
 * <p>Compress returns a copy of the input slice; decompress returns a copy of the
 * input slice. The codec ID is {@code 0x00}.
 *
 * <p>This codec is used as the default when no compression is configured, and is
 * also used in the compression map when a block's compressed output would be
 * equal to or larger than the original data.
 *
 * <p>Package-private — accessed via {@link CompressionCodec#none()}.
 *
 * @see CompressionCodec
 * @see <a href="../../.decisions/compression-codec-api-design/adr.md">ADR: Compression Codec API Design</a>
 */
final class NoneCodec implements CompressionCodec {

    /** Singleton instance. */
    static final NoneCodec INSTANCE = new NoneCodec();

    private NoneCodec() {
    }

    @Override
    public byte codecId() {
        return 0x00;
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
