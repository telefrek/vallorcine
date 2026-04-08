---
feature: "Add opt-in field-level encryption for in-memory data in jlsm-table"
slug: "encrypt-memory-data"
created: "2026-03-18"
status: "scoped"
---

# Feature Brief — encrypt-memory-data

## Summary
Add opt-in field-level encryption for in-memory data in jlsm-table, protecting sensitive field values against memory inspection (heap dumps, cold boot attacks). Different field types use type-appropriate encryption mechanisms — text fields may support searchable encryption (e.g., order-preserving or deterministic encryption for index compatibility), vector fields need dimension-preserving schemes, and scalar fields need efficient symmetric encryption. Encryption is configured per-table at the schema level with caller-provided keys. The goal is to preserve as much query and index functionality as possible while encrypted, not just key-value retrieval.

## Actors
- Table consumers configuring encryption on sensitive schemas
- External KMS systems providing key material
- JlsmTable / DocumentSerializer / index structures processing encrypted field values

## Inputs
- Caller-provided encryption keys (per-table or per-field)
- Schema-level encryption configuration (which fields, which mechanism)
- JlsmDocument field values (plaintext at write time)

## Outputs / Side Effects
- Field values encrypted in memory (MemTable entries, document objects)
- Encrypted values persisted through SSTable flush (encrypted at rest as a side effect, but the primary goal is in-memory protection)
- Decrypted values returned on read to authorized callers
- Index structures operate on encrypted or derived representations where the encryption scheme permits

## Business Rules
- Encryption is opt-in at the table/schema level — no encryption by default
- Field-level granularity: different fields can use different mechanisms or remain unencrypted
- Type-aware encryption: text, vector, and scalar fields may use different schemes to preserve type-specific query capabilities
- Caller-provided keys — library does not generate, store, or manage keys
- Key material must not leak into logs, error messages, toString(), or any observable state beyond the encryption boundary
- Key handoff design must be compatible with external KMS security models (keys held in memory only for the minimum necessary duration)

## Error Cases
- Null or invalid key material: fail eagerly at table construction
- Decryption with wrong key: detect and throw rather than return garbage
- Schema evolution: adding encrypted fields to existing unencrypted data (new fields are null, not corrupt — existing behavior)

## Explicit Out of Scope
- Key generation, rotation, or storage (caller's responsibility)
- Transport-layer encryption (TLS — orthogonal concern)
- Encryption of WAL entries (separate concern, can layer on later)
- Encryption of non-table components (bloom filters, block cache keys)

## Acceptance Criteria
1. A table can be configured with per-field encryption at schema level
2. Encrypted field values are not readable in plaintext from memory inspection of MemTable entries or heap dumps
3. Authorized reads return correct plaintext values
4. At least one field type supports indexed search while encrypted
5. Wrong-key decryption is detected, not silent corruption
6. Key material does not appear in logs, exceptions, or debug output
7. Performance impact is documented via benchmark comparison

## Open Assumptions
- Java's built-in crypto providers (javax.crypto) are sufficient for the symmetric encryption primitives — no external dependency needed
- MemorySegment-backed storage can hold encrypted bytes without format changes (encrypted fields are just opaque byte sequences)

## Research Commissions
1. **Searchable encryption schemes for text fields**
   Key questions: What are the viable approaches (deterministic encryption, order-preserving encryption, searchable symmetric encryption)? What query operations does each preserve? What are the security/functionality tradeoffs? What is implementable in pure Java without external libraries?
   Purpose: Determines whether encrypted text fields can support secondary index lookups, range queries, or prefix matching.

2. **Encryption approaches for vector fields**
   Key questions: Can encrypted vectors preserve distance computation (approximate nearest neighbor)? Are there dimension-preserving encryption schemes? What is the security model for approximate results? Is there a practical pure-Java approach?
   Purpose: Determines whether encrypted vector fields can support similarity search or must be decrypt-then-search.

3. **In-memory key handling security patterns**
   Key questions: What are best practices for holding caller-provided keys in JVM memory (char[] vs byte[], zeroing after use, scope of access)? How do Java KMS client libraries typically hand off key material? What is the threat model for JVM heap inspection?
   Purpose: Informs the key handoff API design so it integrates cleanly with KMS systems and doesn't create new attack surfaces.

## Performance Expectations
- Encryption/decryption adds per-field overhead on every read and write
- Searchable encryption schemes (if viable) will be slower than plaintext index operations — quantify via benchmark
- Non-encrypted fields on the same table should have zero overhead
- Target: encrypted field read/write should not exceed 10x the cost of unencrypted equivalent for simple symmetric encryption

## Project Context
- Language: Java 25 (Amazon Corretto)
- Framework: none — pure library
- Test framework: JUnit Jupiter (JUnit 5)
