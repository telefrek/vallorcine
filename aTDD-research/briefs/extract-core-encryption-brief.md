---
feature: "Extract shared encryption primitives to jlsm-core and add pre-encrypted document support"
slug: "extract-core-encryption"
created: "2026-03-19"
status: "scoped"
---

# Feature Brief — extract-core-encryption

## Summary
Extract shared encryption primitives (EncryptionSpec, EncryptionKeyHolder, and all four encryptors) from jlsm-table into jlsm-core so that upstream clients can encrypt JlsmDocuments before submission using the same keys and algorithms. Add a per-document "pre-encrypted" flag so the table layer skips encryption on write but validates ciphertext structural integrity. Export FieldEncryptionDispatch from jlsm-table for client use. This also positions encryption primitives for future use by other core components (WAL, SSTable) without cross-module dependencies.

## Actors
- Upstream clients encrypting documents before submission
- jlsm-table serializer processing pre-encrypted documents
- jlsm-table serializer encrypting documents that arrive unencrypted
- Future jlsm-core consumers (WAL, SSTable) that may need encryption primitives

## Inputs
- JlsmDocument with a pre-encrypted flag (boolean, per-document)
- Schema with per-field EncryptionSpec (unchanged from encrypt-memory-data)
- Caller-provided EncryptionKeyHolder (unchanged)

## Outputs / Side Effects
- Pre-encrypted documents pass through serializer without re-encryption
- Unencrypted documents are encrypted as before (existing behaviour preserved)
- Structurally invalid ciphertext is rejected at write time with a descriptive exception
- EncryptionSpec, EncryptionKeyHolder, and 4 encryptors available from jlsm-core
- FieldEncryptionDispatch exported from jlsm-table (promoted from internal)

## Business Rules
- Pre-encrypted is all-or-nothing: if the flag is set, ALL encrypted fields must already be encrypted; the serializer does not selectively encrypt
- Unencrypted documents (flag not set) behave exactly as today — no change
- The pre-encrypted flag is a trust signal: the serializer validates structural correctness but does not decrypt to verify content
- Decryption path is unchanged — the reader always decrypts regardless of how the document was encrypted

## Error Cases
- Pre-encrypted document with ciphertext length invalid for the field's EncryptionSpec → reject with IllegalArgumentException
- Pre-encrypted document with null/empty bytes on a field that requires encryption → reject
- Pre-encrypted flag set but schema has no encrypted fields → no-op (vacuously true, not an error)

## Explicit Out of Scope
- Key exchange protocol between client and server
- Client-side encryption SDK or helper library (clients use core directly)
- Changes to decryption or read path
- Changes to SSE, PositionalPostingCodec, or index structures (stay in table)
- WAL or block cache encryption (future work, now unblocked by this move)

## Acceptance Criteria
1. EncryptionSpec, EncryptionKeyHolder, and all 4 encryptors compile and test in jlsm-core with no jlsm-table dependency
2. jlsm-table depends on jlsm-core for encryption primitives (no duplication)
3. FieldEncryptionDispatch is exported from jlsm-table (accessible to consumers)
4. A pre-encrypted JlsmDocument round-trips through serialize/deserialize correctly without double-encryption
5. Structurally invalid ciphertext on a pre-encrypted document is rejected at write time with a descriptive error
6. All existing jlsm-table tests pass without modification (backward compat)
7. A jlsm-core-only consumer can encrypt field values using the same algorithm and key as jlsm-table would

## Open Assumptions
- Moving classes between modules can be done without breaking the JPMS module-info.java exports cleanly (jlsm-core exports new packages, jlsm-table's module-info requires jlsm-core's new packages)
- Existing jlsm-table tests that reference internal encryptor packages will need --add-exports adjustments to point at jlsm-core instead

## Research Commissions
None — no research signals identified during scoping. The encryption primitives and their APIs are already well-understood from the prior feature.

## Performance Expectations
- Zero overhead on the unencrypted path (no behavioral change)
- Pre-encrypted path should be faster than encrypt-on-write (validation only, no crypto operations)
- Module boundary change should have no runtime performance impact

## Project Context
- Language: Java 25 (Amazon Corretto)
- Framework: none — pure library
- Test framework: JUnit Jupiter (JUnit 5)
