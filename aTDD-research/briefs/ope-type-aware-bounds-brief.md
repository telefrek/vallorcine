---
feature: "OPE domain/range optimization with type-aware bounds, BoundedString, and encryption docs"
slug: "ope-type-aware-bounds"
created: "2026-03-19"
status: "scoped"
---

# Feature Brief — ope-type-aware-bounds

## Summary
Replace the hardcoded Long.MAX_VALUE/2 OPE domain in FieldEncryptionDispatch with type-aware bounds derived from the field type. Add parameterized string length via FieldType.string(maxLength) with a reasonable default cap. Restrict OrderPreserving encryption to numeric primitives and BoundedString (reject on unbounded STRING — range scans on arbitrary strings are almost always a modeling mistake). Write encryption package README.md documenting capabilities, performance tradeoffs, and usage guidance.

## Actors
- Table consumers configuring OrderPreserving encryption on fields
- FieldEncryptionDispatch (derives OPE domain/range from field type)
- IndexRegistry (validates OrderPreserving compatibility with field type)
- Library users reading the encryption README for guidance

## Inputs
- FieldType of the encrypted field (Primitive type, BoundedString with maxLength, VectorType)
- Existing FieldEncryptionDispatch OPE construction (line 97-98)
- Existing IndexRegistry encryption compatibility validation

## Outputs / Side Effects
- OPE domain/range derived from field type at dispatch construction time:
  - INT8: domain 256, range ~2,560 (10x ratio)
  - INT16: domain 65,536, range ~655,360
  - INT32: domain 2^32, range ~2^32 * 10
  - INT64: domain capped to avoid extreme recursion (e.g., 2^48, range 2^48 * 10)
  - TIMESTAMP: same as INT64
  - STRING(maxLen): domain based on maxLen bytes (256^min(maxLen,6)), range 10x
  - Unbounded STRING: OrderPreserving rejected at IndexRegistry validation
  - BOOLEAN, FLOAT*, VECTOR, ARRAY, OBJECT: OrderPreserving rejected
- FieldType.string(maxLength) factory method; FieldType.Primitive.STRING gets a default cap
- Dramatically faster OPE encryption for typical field types
- IndexRegistry rejects OrderPreserving on field types where OPE is impractical
- README.md in jlsm-core's encryption package

## Business Rules
- OPE range must be > domain (Boldyreva scheme requirement)
- Range/domain ratio of 10x as default (balances security vs recursion depth)
- Default STRING max length: 255 bytes (VARCHAR(255) convention)
- FieldType.string(maxLength) must be backward compatible — existing STRING usage unaffected
- OrderPreserving + unbounded STRING → IllegalArgumentException at IndexRegistry validation
- OrderPreserving + BOOLEAN/FLOAT/VECTOR/ARRAY/OBJECT → IllegalArgumentException (existing behavior, just documenting)
- OPE on values exceeding the derived domain → fail eagerly with descriptive error
- INT64/TIMESTAMP OPE domain is capped to prevent >50 recursion levels — document the practical range limitation

## Error Cases
- OrderPreserving on unbounded STRING → IllegalArgumentException at schema/index validation
- OPE encrypt with value exceeding derived domain → IllegalArgumentException
- FieldType.string(0) or negative maxLength → IllegalArgumentException
- FieldType.string(maxLength > 6) with OrderPreserving → warn that OPE only uses first 6 bytes for ordering (values longer than 6 bytes that share a 6-byte prefix will have identical ciphertext order)

## Explicit Out of Scope
- BINARY field type (separate feature)
- Changes to AES-SIV, AES-GCM, or DCPE encryptors
- Changes to the Boldyreva algorithm itself
- OPE on FLOAT types (floating-point domain semantics are different)
- Changing the existing EncryptionSpec sealed hierarchy

## Acceptance Criteria
1. FieldEncryptionDispatch derives OPE domain/range from field type instead of hardcoded Long.MAX_VALUE/2
2. OPE encrypt for INT32 fields completes in <10ms (vs seconds before)
3. OPE encrypt for STRING(6) fields completes in <100ms
4. FieldType.string(maxLength) works as a parameterized string type
5. Existing FieldType.Primitive.STRING has a default max length cap (255)
6. OrderPreserving on unbounded STRING is rejected at validation
7. README.md exists in the encryption package with scheme comparison, capability matrix, and performance guidance
8. All existing tests pass without modification

## Open Assumptions
- FieldType.string(maxLength) can be implemented as a new record in the FieldType sealed hierarchy (e.g., FieldType.BoundedString(int maxLength)) without breaking existing switch expressions
- A 10x range/domain ratio provides adequate security for typical use cases
- Capping INT64/TIMESTAMP OPE domain to 2^48 (with 10x range) is acceptable — values outside this range would need Deterministic encryption instead of OrderPreserving
- The existing 6-byte limit in bytesToPositiveLong() is acceptable for string OPE (strings longer than 6 bytes are ordered by their first 6 bytes only)

## Research Commissions
None — the OPE domain/recursion relationship is well-understood from perf-review findings, and the KB covers the security properties of each scheme.

## Performance Expectations
- INT8 OPE: >100K ops/s (domain 256, ~8 recursion levels)
- INT16 OPE: >10K ops/s (domain 65K, ~16 levels)
- INT32 OPE: >100 ops/s (domain 4B, ~32 levels)
- STRING(2) OPE: >10K ops/s (domain 65K)
- STRING(5) OPE: >10 ops/s (domain ~1T)
- Validated via perf-review scratch benchmark

## Project Context
- Language: Java 25 (Amazon Corretto)
- Framework: none — pure library
- Test framework: JUnit Jupiter (JUnit 5)
