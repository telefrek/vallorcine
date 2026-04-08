package jlsm.table.internal;

/**
 * Contract: Tier 2 position-aware posting format for encrypted full-text search. Extends
 * inverted index postings with OPE-encrypted term positions. Encodes a document ID and its
 * term positions into a byte sequence where terms are DET-encrypted and positions are
 * OPE-encrypted, enabling phrase queries (consecutive OPE positions) and proximity queries
 * (position difference within threshold).
 *
 * <p>Governed by: .decisions/encrypted-index-strategy/adr.md
 */
public final class PositionalPostingCodec {

    // TODO: Not implemented
    // - Constructor: accept AesSivEncryptor (DET for terms) + BoldyrevaOpeEncryptor (OPE for positions)
    // - encode(byte[] docId, long[] positions) → byte[] posting entry
    // - decode(byte[] posting) → DecodedPosting(docId, encryptedPositions)
    // - Phrase query support: check consecutive OPE-encrypted positions
    // - Proximity query support: check OPE position difference within threshold

    /**
     * Creates a positional posting codec with the given encryptors.
     *
     * @param detEncryptor the deterministic encryptor for term values
     * @param opeEncryptor the order-preserving encryptor for term positions
     */
    public PositionalPostingCodec(AesSivEncryptor detEncryptor, BoldyrevaOpeEncryptor opeEncryptor) {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Encodes a document ID and its term positions into an encrypted posting entry.
     *
     * @param docId the document identifier
     * @param positions the plaintext term positions within the document
     * @return the encoded posting bytes
     */
    public byte[] encode(byte[] docId, long[] positions) {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Decodes an encrypted posting entry.
     *
     * @param posting the encoded posting bytes
     * @return the decoded posting with document ID and encrypted positions
     */
    public DecodedPosting decode(byte[] posting) {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * A decoded posting entry containing the document ID and OPE-encrypted positions.
     *
     * @param docId the document identifier
     * @param encryptedPositions the OPE-encrypted term positions (order-preserved)
     */
    public record DecodedPosting(byte[] docId, long[] encryptedPositions) {}
}
