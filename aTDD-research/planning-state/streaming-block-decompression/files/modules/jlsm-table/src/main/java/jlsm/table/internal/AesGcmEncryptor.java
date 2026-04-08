package jlsm.table.internal;

/**
 * Contract: Opaque encryption using AES-GCM with a random IV per encryption. Provides
 * authenticated encryption — tampering or wrong-key decryption is detected via tag
 * verification. No search capability on encrypted values.
 *
 * <p>Ciphertext format: {@code [12-byte IV || ciphertext || 16-byte auth tag]} — +28 bytes
 * expansion.
 *
 * <p>Governed by: .kb/algorithms/encryption/searchable-encryption-schemes.md
 */
public final class AesGcmEncryptor {

    // TODO: Not implemented
    // - Constructor: accept EncryptionKeyHolder, extract 256-bit key
    // - encrypt(byte[] plaintext) → byte[] (IV + ciphertext + tag)
    // - decrypt(byte[] ciphertext) → byte[] plaintext
    // - Random 12-byte IV per encryption (SecureRandom)
    // - Decrypt verifies auth tag — throws on failure (wrong key / tampered data)

    /**
     * Creates an AES-GCM encryptor using the given key holder.
     *
     * @param keyHolder the key holder providing a 256-bit (32-byte) key
     * @throws IllegalArgumentException if key length is not 32 bytes
     */
    public AesGcmEncryptor(EncryptionKeyHolder keyHolder) {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Encrypts the plaintext with AES-GCM using a random IV.
     *
     * @param plaintext the data to encrypt; must not be null
     * @return the ciphertext as {@code [12-byte IV || encrypted bytes || 16-byte tag]}
     */
    public byte[] encrypt(byte[] plaintext) {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Decrypts AES-GCM ciphertext and verifies the authentication tag.
     *
     * @param ciphertext the data to decrypt (IV || encrypted || tag); must not be null
     * @return the plaintext bytes
     * @throws IllegalArgumentException if ciphertext is too short
     * @throws SecurityException if authentication tag verification fails
     */
    public byte[] decrypt(byte[] ciphertext) {
        throw new UnsupportedOperationException("Not implemented");
    }
}
