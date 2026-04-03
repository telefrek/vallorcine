package jlsm.table.internal;

import jlsm.table.FieldDefinition;

/**
 * Contract: Validates ciphertext structural integrity for pre-encrypted documents.
 * Each encryption scheme has known expansion sizes; ciphertext that doesn't match
 * is rejected as corrupt.
 *
 * Governed by: .decisions/pre-encrypted-document-signaling/adr.md
 */
public final class CiphertextValidator {

    private CiphertextValidator() {
        // Utility class
    }

    /**
     * Validates that the given ciphertext is structurally valid for the field's encryption spec.
     *
     * @param field the field definition (carries EncryptionSpec and FieldType)
     * @param ciphertext the raw ciphertext bytes to validate
     * @throws IllegalArgumentException if the ciphertext is structurally invalid
     * @throws NullPointerException if field or ciphertext is null
     */
    public static void validate(FieldDefinition field, byte[] ciphertext) {
        throw new UnsupportedOperationException("Not implemented");
    }
}
