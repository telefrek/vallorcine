package jlsm.table.internal;

import jlsm.table.EncryptionSpec;
import jlsm.table.JlsmSchema;

/**
 * Contract: Builds per-field encrypt and decrypt function arrays from a schema and key holder.
 * Maps each field's {@link EncryptionSpec} to the appropriate encryptor instance.
 * {@link EncryptionSpec#NONE} maps to identity (no-op). Used by {@code DocumentSerializer}
 * at construction time to build encrypt/decrypt lambdas alongside the existing
 * {@code FieldDecoder} dispatch table.
 *
 * <p>Governed by: .decisions/field-encryption-api-design/adr.md
 */
public final class FieldEncryptionDispatch {

    // TODO: Not implemented
    // - Constructor / factory: accept JlsmSchema + EncryptionKeyHolder
    // - Build per-field encrypt function: (fieldIndex, byte[]) → byte[]
    // - Build per-field decrypt function: (fieldIndex, byte[]) → byte[]
    // - EncryptionSpec.NONE → identity lambda
    // - Deterministic → AesSivEncryptor (field name as associated data)
    // - OrderPreserving → BoldyrevaOpeEncryptor
    // - DistancePreserving → DcpeSapEncryptor
    // - Opaque → AesGcmEncryptor

    /**
     * Creates a dispatch table for the given schema and key holder.
     *
     * @param schema the table schema with per-field encryption specs
     * @param keyHolder the key holder; may be null if no fields are encrypted
     * @return a new dispatch instance
     * @throws IllegalArgumentException if any encrypted field lacks a key holder
     */
    public static FieldEncryptionDispatch create(JlsmSchema schema, EncryptionKeyHolder keyHolder) {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Encrypts the raw bytes for the field at the given index.
     *
     * @param fieldIndex the zero-based field index
     * @param plaintext the plaintext bytes
     * @return the encrypted bytes, or the same bytes if the field is not encrypted
     */
    public byte[] encrypt(int fieldIndex, byte[] plaintext) {
        throw new UnsupportedOperationException("Not implemented");
    }

    /**
     * Decrypts the raw bytes for the field at the given index.
     *
     * @param fieldIndex the zero-based field index
     * @param ciphertext the encrypted bytes
     * @return the plaintext bytes, or the same bytes if the field is not encrypted
     */
    public byte[] decrypt(int fieldIndex, byte[] ciphertext) {
        throw new UnsupportedOperationException("Not implemented");
    }

    private FieldEncryptionDispatch() {
        throw new UnsupportedOperationException("Not implemented");
    }
}
