package jlsm.table.internal;

/**
 * Contract: Deterministic encryption using AES-SIV (RFC 5297). A 512-bit key is split into
 * K1 (CMAC key) and K2 (CTR key). S2V derives a synthetic IV from the plaintext and optional
 * associated data; AES-CTR encrypts the plaintext under that IV. The same plaintext + associated
 * data always produces the same ciphertext, enabling equality queries on encrypted values.
 *
 * <p>Ciphertext format: {@code [16-byte IV || ciphertext]} — +16 bytes expansion.
 *
 * <p>Governed by: .kb/algorithms/encryption/searchable-encryption-schemes.md
 */
public final class AesSivEncryptor {

    // TODO: Not implemented
    // - Constructor: accept EncryptionKeyHolder, extract 512-bit key, split K1/K2
    // - encrypt(byte[] plaintext, byte[] associatedData) → byte[] (IV || ciphertext)
    // - decrypt(byte[] ciphertext, byte[] associatedData) → byte[] plaintext
    // - S2V: CMAC-based IV derivation per RFC 5297
    // - Decrypt verifies IV matches recomputed S2V — throws on mismatch (wrong key detection)

    /**
     * Creates an AES-SIV encryptor using the given key holder.
     *
     * @param keyHolder the key holder providing a 512-bit (64-byte) key
     * @throws IllegalArgumentException if key length is not 64 bytes
     */
    public AesSivEncryptor(EncryptionKeyHolder keyHolder) {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Encrypts the plaintext deterministically with optional associated data.
     *
     * @param plaintext the data to encrypt; must not be null
     * @param associatedData optional associated data for IV derivation; may be null
     * @return the ciphertext as {@code [16-byte IV || encrypted bytes]}
     */
    public byte[] encrypt(byte[] plaintext, byte[] associatedData) {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Decrypts AES-SIV ciphertext and verifies the synthetic IV.
     *
     * @param ciphertext the data to decrypt (IV || encrypted bytes); must not be null
     * @param associatedData the associated data used during encryption; may be null
     * @return the plaintext bytes
     * @throws IllegalArgumentException if ciphertext is too short
     * @throws SecurityException if IV verification fails (wrong key or tampered data)
     */
    public byte[] decrypt(byte[] ciphertext, byte[] associatedData) {
        throw new UnsupportedOperationException("Not implemented");
    }
}
