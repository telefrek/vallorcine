---
feature: "Fix encryption performance issues from perf-review"
slug: "fix-encryption-performance"
created: "2026-03-19"
status: "scoped"
---

# Feature Brief — fix-encryption-performance

## Summary
Fix critical and significant performance issues in the encryption primitives identified by perf-review. BoldyrevaOpeEncryptor is unusable (0.028 ops/s) due to Cipher.getInstance() in its hot inner loop. AesSivEncryptor is 4x slower than AesGcmEncryptor — partially due to the same JCE allocation pattern, partially algorithmic. Cache Cipher instances and SecretKeySpec objects in all encryptors, then research and apply any viable AES-SIV algorithmic optimizations or evaluate alternative deterministic encryption schemes.

## Actors
- All encryption consumers (DocumentSerializer, FieldEncryptionDispatch, SseEncryptedIndex, client-side encryption via jlsm-core)

## Inputs
- Existing encryptor implementations in jlsm.encryption package (jlsm-core)
- Perf-review findings (perf-output/findings.md, commit 89338a9)

## Outputs / Side Effects
- BoldyrevaOpeEncryptor: orders-of-magnitude throughput improvement
- AesSivEncryptor: measurable throughput improvement from JCE caching, potentially more from algorithmic optimization or scheme replacement
- AesGcmEncryptor: minor improvement from Cipher caching (already fast)
- DcpeSapEncryptor: audit for same pattern (may not apply)
- All existing tests continue to pass — no behavioral changes

## Business Rules
- Cipher instances are NOT thread-safe (javax.crypto.Cipher is stateful). Caching must use per-instance fields with documented thread-safety constraints matching the existing encryptor usage model.
- Encryption correctness must not change — same inputs produce same outputs for existing schemes.
- If a replacement deterministic scheme is adopted, it must preserve the EncryptionSpec.Deterministic contract: same plaintext + same key → same ciphertext, enabling equality queries and keyword search.
- The encryptors in jlsm-core are used by FieldEncryptionDispatch which is constructed once per serializer (single-threaded within a serializer instance).

## Error Cases
- Cached Cipher in invalid state after exception → must reset or recreate
- Thread-safety violation if Cipher is shared across threads without synchronization

## Explicit Out of Scope
- Changing the EncryptionSpec sealed hierarchy or capability methods
- Performance of DocumentSerializer non-encryption paths
- Pre-encrypted validation path (already 500M ops/s — nothing to fix)
- New encryption capabilities or index strategy changes
- Changes to BoldyrevaOpeEncryptor's algorithm (hypergeometric sampling is the scheme — only the JCE usage pattern is fixed)

## Acceptance Criteria
1. BoldyrevaOpeEncryptor throughput improves by at least 100x (from 0.028 ops/s)
2. AesSivEncryptor throughput improves measurably from JCE caching
3. If AES-SIV algorithmic optimization or an alternative deterministic scheme is viable, the gap vs AES-GCM narrows (target: <2x, currently ~4x)
4. If neither is viable, the gap is documented as accepted algorithmic cost with a clear rationale
5. All existing encryption tests pass without modification
6. Perf-review scratch benchmark confirms improvements

## Open Assumptions
- Cipher instances for AES/ECB/NoPadding and AES/CTR/NoPadding are safe to reuse across doFinal calls (stateless between calls for these modes)
- The threading model of FieldEncryptionDispatch (single-threaded per serializer) means ThreadLocal is unnecessary — field-level caching is sufficient

## Research Commissions
1. **Deterministic encryption performance optimization**
   Key questions: Can the AES-SIV CMAC + CTR two-pass be optimized (e.g., single AES key schedule shared between CMAC and CTR, pre-expanded round keys, hardware AES-NI exploitation via JCE provider selection)? Are there alternative deterministic AEAD constructions that are faster while preserving the same security properties (deterministic, same plaintext → same ciphertext)? Candidates to evaluate: AES-ECB-then-CMAC (simplified SIV), HBS (hash-based SIV), AEAD constructions based on AES-GCM-SIV (RFC 8452), or other misuse-resistant deterministic schemes. What are the security tradeoffs of each alternative vs standard AES-SIV?
   Purpose: Determines whether the 4x gap vs AES-GCM can be narrowed through optimization or scheme replacement, or must be accepted as inherent cost of deterministic encryption.

## Performance Expectations
- BoldyrevaOPE: from 0.028 ops/s to >1K ops/s (Cipher caching alone)
- AES-SIV: from 66K ops/s to >100K ops/s (JCE caching), potentially higher with algorithmic optimization or scheme replacement
- AES-GCM: from 252K ops/s to ~300K+ ops/s (minor Cipher caching gain)
- Validated via perf-review scratch benchmark re-run

## Project Context
- Language: Java 25 (Amazon Corretto)
- Framework: none — pure library
- Test framework: JUnit Jupiter (JUnit 5)
