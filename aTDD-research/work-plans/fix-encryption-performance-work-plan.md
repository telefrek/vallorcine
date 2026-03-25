---
feature: "fix-encryption-performance"
created: "2026-03-19"
status: "approved"
---

# Work Plan — fix-encryption-performance

## References
- **Brief:** [brief.md](brief.md)
- **Domains:** [domains.md](domains.md)
- **KB:** [`.kb/algorithms/encryption/deterministic-encryption-performance.md`](../../.kb/algorithms/encryption/deterministic-encryption-performance.md)
- **Findings:** `perf-output/findings.md` (commit 89338a9)

## Modules Affected
- **jlsm-core** — all 3 encryptor classes modified in `jlsm.encryption` package

---

## Existing Constructs

| # | Construct | Location | Action |
|---|-----------|----------|--------|
| 1 | BoldyrevaOpeEncryptor | `jlsm.encryption.BoldyrevaOpeEncryptor` | optimize — cache Cipher/KeySpec, reuse PRF buffer |
| 2 | AesSivEncryptor | `jlsm.encryption.AesSivEncryptor` | optimize — cache CMAC + CTR Cipher instances, convert static methods to instance |
| 3 | AesGcmEncryptor | `jlsm.encryption.AesGcmEncryptor` | optimize — cache Cipher + SecretKeySpec as fields |

## New Constructs

None.

---

## Contract Definitions

### BoldyrevaOpeEncryptor optimization (item 1)

**File:** `modules/jlsm-core/src/main/java/jlsm/encryption/BoldyrevaOpeEncryptor.java`
**Governed by:** perf-output/findings.md (BoldyrevaOpeEncryptor Cipher.getInstance finding)

**Changes:**
- Add fields: `private final Cipher prfCipher;` `private final SecretKeySpec prfKeySpec;` `private final byte[] prfBuffer = new byte[16];`
- Constructor: initialize `prfCipher = Cipher.getInstance("AES/ECB/NoPadding")`, `prfKeySpec = new SecretKeySpec(keyBytes, 0, min(len, 32), "AES")`, `prfCipher.init(ENCRYPT_MODE, prfKeySpec)`
- `prfSeed()`: remove `Cipher.getInstance()` / `Cipher.init()` / `ByteBuffer.allocate(16)`; write directly to `prfBuffer`; call `prfCipher.doFinal(prfBuffer, 0, 16, outputBuf, 0)`
- `prfNext()`: same pattern — reuse `prfCipher` and `prfBuffer`
- Also cache Cipher+KeySpec for `cmac()` and `aesCtr()` helper methods (called from `s2v()` and `encrypt()`)
- Error handling: if `doFinal` throws, the Cipher may be in a bad state; wrap in try-catch and re-init if needed
- Correctness: same key, same input produces same output; caching does not change AES-ECB behavior

**Expected impact:** from 0.028 ops/s to >1K ops/s (orders-of-magnitude improvement)

---

### AesSivEncryptor optimization (item 2)

**File:** `modules/jlsm-core/src/main/java/jlsm/encryption/AesSivEncryptor.java`
**Governed by:** `.kb/algorithms/encryption/deterministic-encryption-performance.md`

**Changes:**
- Add fields: `private final Cipher cmacCipher;` `private final Cipher ctrCipher;`
- Constructor: initialize both Cipher instances with their respective keys
- Convert `cmac()` from static to instance method — use cached `cmacCipher`, call only `doFinal()` (skip `getInstance`/`init`). The Cipher is already initialized with the CMAC key. Called 3 times per encrypt (zero block, AD, final).
- Convert `aesCtr()` from static to instance method — use cached `ctrCipher`. For ECB mode used in manual CTR, `doFinal` is sufficient since ECB is stateless between calls.
- Use buffer-accepting `doFinal(input, inOff, inLen, output, outOff)` overloads where possible to reduce `byte[]` allocation
- Correctness: all existing `AesSivEncryptorTest` tests must pass unchanged

**Expected impact:** from 66K ops/s to 100-130K ops/s (~2x improvement)

---

### AesGcmEncryptor optimization (item 3)

**File:** `modules/jlsm-core/src/main/java/jlsm/encryption/AesGcmEncryptor.java`
**Governed by:** perf-output/findings.md

**Changes:**
- Add fields: `private final Cipher cipher;` `private final SecretKeySpec keySpec;`
- Constructor: `cipher = Cipher.getInstance("AES/GCM/NoPadding")`, `keySpec = new SecretKeySpec(keyBytes, "AES")`
- `encrypt()`: remove `Cipher.getInstance()` + `new SecretKeySpec()`; use cached fields; still call `cipher.init()` per call (GCM requires new IV each time)
- `decrypt()`: same — remove `getInstance` + `new SecretKeySpec()`; use cached fields
- Correctness: GCM requires `init()` per call for IV, but `Cipher` and `SecretKeySpec` objects are safe to reuse

**Expected impact:** from 252K ops/s to ~300K+ ops/s (minor gain)

---

## Implementation Order

Single unit, cost strategy. Implementation order by impact:

```
1. BoldyrevaOpeEncryptor — highest impact (from 0.028 ops/s), most JCE calls per encrypt
   ├── Tests: existing BoldyrevaOpeEncryptorTest covers correctness (same inputs → same outputs)
   ├── Impl: cache Cipher/KeySpec/buffer in constructor, eliminate per-call allocation
   └── Verify: ./gradlew :modules:jlsm-core:test --tests "*BoldyrevaOpeEncryptorTest*"

2. AesSivEncryptor — second highest impact (from 66K ops/s), multiple cmac + aesCtr calls
   ├── Tests: existing AesSivEncryptorTest covers correctness
   ├── Impl: cache CMAC + CTR Cipher instances, convert static → instance, buffer-accepting doFinal
   └── Verify: ./gradlew :modules:jlsm-core:test --tests "*AesSivEncryptorTest*"

3. AesGcmEncryptor — lowest impact (already 252K ops/s), minor gain from caching
   ├── Tests: existing AesGcmEncryptorTest covers correctness
   ├── Impl: cache Cipher + SecretKeySpec as fields
   └── Verify: ./gradlew :modules:jlsm-core:test --tests "*AesGcmEncryptorTest*"

Final: ./gradlew check (full build verification)
```

## Key Constraints

- Cipher instances are NOT thread-safe — cache as instance fields, not static
- AES/ECB/NoPadding and AES/CTR/NoPadding are stateless between `doFinal()` calls — safe to reuse without re-init
- AES/GCM/NoPadding requires `Cipher.init()` per call (new IV each time) — only cache the Cipher object and KeySpec
- The threading model (single-threaded per serializer instance via FieldEncryptionDispatch) means `ThreadLocal` is unnecessary
- All optimizations must preserve encryption correctness — existing tests serve as the correctness oracle
- DcpeSapEncryptor uses `SecureRandom`, not `Cipher.getInstance()` — no JCE caching issue, excluded from scope
