---
feature: "encrypt-memory-data"
created: "2026-03-18"
status: "complete"
---

# Work Plan — encrypt-memory-data

## References

- **Brief:** [brief.md](brief.md)
- **Domains:** [domains.md](domains.md)
- **ADR — Field Encryption API Design:** [.decisions/field-encryption-api-design/adr.md](../../.decisions/field-encryption-api-design/adr.md)
- **ADR — Encrypted Index Strategy:** [.decisions/encrypted-index-strategy/adr.md](../../.decisions/encrypted-index-strategy/adr.md)
- **KB — Searchable Encryption Schemes:** [.kb/algorithms/encryption/searchable-encryption-schemes.md](../../.kb/algorithms/encryption/searchable-encryption-schemes.md)
- **KB — Vector Encryption Approaches:** [.kb/algorithms/encryption/vector-encryption-approaches.md](../../.kb/algorithms/encryption/vector-encryption-approaches.md)
- **KB — JVM Key Handling Patterns:** [.kb/systems/security/jvm-key-handling-patterns.md](../../.kb/systems/security/jvm-key-handling-patterns.md)

## Module

All work targets `jlsm-table` (`modules/jlsm-table/src/main/java/jlsm/table/`).
Internal constructs live in `jlsm.table.internal`.

---

## Existing Constructs (extensions)

| # | Construct | Location | Change |
|---|-----------|----------|--------|
| E1 | `FieldDefinition` | `jlsm/table/FieldDefinition.java` | Extend record from `(name, type)` to `(name, type, encryptionSpec)` with backward-compatible constructor defaulting to `EncryptionSpec.NONE` |
| E2 | `JlsmSchema.Builder` | `jlsm/table/JlsmSchema.java` | Add `.field(name, type, encryptionSpec)` overload |
| E3 | `DocumentSerializer.SchemaSerializer` | `jlsm/table/internal/DocumentSerializer.java` | Add per-field encrypt/decrypt in dispatch table via `FieldEncryptionDispatch` |
| E4 | `IndexRegistry` | `jlsm/table/internal/IndexRegistry.java` | Add capability matrix validation at construction — reject incompatible encryption × index combinations |

## New Constructs

| # | Construct | Type | Package | Stub file |
|---|-----------|------|---------|-----------|
| N1 | `EncryptionSpec` | sealed interface | `jlsm.table` | `EncryptionSpec.java` |
| N2 | `EncryptionKeyHolder` | final class | `jlsm.table.internal` | `EncryptionKeyHolder.java` |
| N3 | `AesSivEncryptor` | final class | `jlsm.table.internal` | `AesSivEncryptor.java` |
| N4 | `BoldyrevaOpeEncryptor` | final class | `jlsm.table.internal` | `BoldyrevaOpeEncryptor.java` |
| N5 | `DcpeSapEncryptor` | final class | `jlsm.table.internal` | `DcpeSapEncryptor.java` |
| N6 | `AesGcmEncryptor` | final class | `jlsm.table.internal` | `AesGcmEncryptor.java` |
| N7 | `FieldEncryptionDispatch` | final class | `jlsm.table.internal` | `FieldEncryptionDispatch.java` |
| N8 | `SseEncryptedIndex` | final class | `jlsm.table.internal` | `SseEncryptedIndex.java` |
| N9 | `PositionalPostingCodec` | final class | `jlsm.table.internal` | `PositionalPostingCodec.java` |

---

## Contract Definitions

### N1 — EncryptionSpec

```
sealed interface EncryptionSpec
  permits None, Deterministic, OrderPreserving, DistancePreserving, Opaque
```

- **Capability methods:** `supportsEquality()`, `supportsRange()`, `supportsKeywordSearch()`, `supportsPhraseSearch()`, `supportsSseSearch()`, `supportsANN()` — all default `false`
- **None:** all capabilities `true` (plaintext)
- **Deterministic:** equality + keyword search
- **OrderPreserving:** equality + range
- **DistancePreserving:** ANN only
- **Opaque:** all `false`
- **Static factories:** `none()`, `deterministic()`, `orderPreserving()`, `distancePreserving()`, `opaque()`
- **Errors:** none (value type)
- **Governed by:** .decisions/field-encryption-api-design/adr.md

### N2 — EncryptionKeyHolder

```
static EncryptionKeyHolder of(byte[] keyMaterial)
MemorySegment keySegment()
int keyLength()
void close()
```

- **Params:** `keyMaterial` — raw key bytes; copied to off-heap `Arena.ofShared()` segment; caller's array zeroed
- **Returns:** read-only `MemorySegment` view of key
- **Errors:** `NullPointerException` (null key), `IllegalArgumentException` (empty key), `IllegalStateException` (accessed after close)
- **Close:** `fill(0)` + `arena.close()`, idempotent via `volatile boolean`
- **Governed by:** .kb/systems/security/jvm-key-handling-patterns.md

### N3 — AesSivEncryptor

```
AesSivEncryptor(EncryptionKeyHolder keyHolder)
byte[] encrypt(byte[] plaintext, byte[] associatedData)
byte[] decrypt(byte[] ciphertext, byte[] associatedData)
```

- **Params:** 512-bit key (split K1 CMAC + K2 CTR); plaintext + optional associated data
- **Returns:** `[16-byte IV || ciphertext]` (+16 bytes expansion)
- **Errors:** `IllegalArgumentException` (key not 64 bytes, ciphertext too short), `SecurityException` (IV mismatch on decrypt — wrong key)
- **Governed by:** .kb/algorithms/encryption/searchable-encryption-schemes.md

### N4 — BoldyrevaOpeEncryptor

```
BoldyrevaOpeEncryptor(EncryptionKeyHolder keyHolder, long domainSize, long rangeSize)
long encrypt(long plaintext)
long decrypt(long ciphertext)
```

- **Params:** key holder, domain [1..M], range [1..N] where N >> M
- **Returns:** order-preserving ciphertext (encrypt), plaintext (decrypt via binary search)
- **Errors:** `IllegalArgumentException` (rangeSize <= domainSize, value out of bounds)
- **Governed by:** .kb/algorithms/encryption/searchable-encryption-schemes.md

### N5 — DcpeSapEncryptor

```
DcpeSapEncryptor(EncryptionKeyHolder keyHolder, int dimensions)
EncryptedVector encrypt(float[] vector)
float[] decrypt(float[] encrypted, long seed)
```

- **Params:** key holder, dimensions; vector must match dimensions
- **Returns:** `EncryptedVector(float[] values, long seed)` — same dimensionality
- **Errors:** `IllegalArgumentException` (wrong dimensions, non-positive dimensions)
- **Governed by:** .kb/algorithms/encryption/vector-encryption-approaches.md

### N6 — AesGcmEncryptor

```
AesGcmEncryptor(EncryptionKeyHolder keyHolder)
byte[] encrypt(byte[] plaintext)
byte[] decrypt(byte[] ciphertext)
```

- **Params:** 256-bit key; plaintext bytes
- **Returns:** `[12-byte IV || ciphertext || 16-byte tag]` (+28 bytes expansion)
- **Errors:** `IllegalArgumentException` (key not 32 bytes, ciphertext too short), `SecurityException` (auth tag verification failure)
- **Governed by:** .kb/algorithms/encryption/searchable-encryption-schemes.md

### N7 — FieldEncryptionDispatch

```
static FieldEncryptionDispatch create(JlsmSchema schema, EncryptionKeyHolder keyHolder)
byte[] encrypt(int fieldIndex, byte[] plaintext)
byte[] decrypt(int fieldIndex, byte[] ciphertext)
```

- **Params:** schema with per-field encryption specs, key holder (null if no fields encrypted)
- **Returns:** encrypted/decrypted bytes per field; identity for `EncryptionSpec.NONE`
- **Errors:** `IllegalArgumentException` (encrypted field with null key holder)
- **Mapping:** None→identity, Deterministic→AesSivEncryptor, OrderPreserving→BoldyrevaOpeEncryptor, DistancePreserving→DcpeSapEncryptor, Opaque→AesGcmEncryptor
- **Governed by:** .decisions/field-encryption-api-design/adr.md

### N8 — SseEncryptedIndex

```
SseEncryptedIndex(EncryptionKeyHolder keyHolder)
byte[] deriveToken(String term)
void add(String term, byte[] docId)
void delete(String term, byte[] docId)
List<byte[]> search(byte[] token)
```

- **Params:** key holder for PRF and posting encryption
- **Token derivation:** `Tw = PRF(K, term)`, stored keyed by `hash(Tw)`
- **Dynamic updates:** add/delete with forward privacy via state counter per term
- **Backing store:** `ConcurrentHashMap<ByteArrayKey, EncryptedPostingList>`
- **Governed by:** .decisions/encrypted-index-strategy/adr.md

### N9 — PositionalPostingCodec

```
PositionalPostingCodec(AesSivEncryptor detEncryptor, BoldyrevaOpeEncryptor opeEncryptor)
byte[] encode(byte[] docId, long[] positions)
DecodedPosting decode(byte[] posting)
```

- **Params:** DET encryptor for terms, OPE encryptor for positions
- **Returns:** encoded posting bytes (encode); `DecodedPosting(docId, encryptedPositions)` (decode)
- **Phrase query:** consecutive OPE positions
- **Proximity query:** OPE position difference within threshold
- **Governed by:** .decisions/encrypted-index-strategy/adr.md

### E1 — FieldDefinition extension

- Extend record to `(String name, FieldType type, EncryptionSpec encryptionSpec)`
- Add compact constructor defaulting `encryptionSpec` to `EncryptionSpec.NONE` when the 2-arg canonical form is used
- Backward-compatible: existing `new FieldDefinition(name, type)` still works

### E2 — JlsmSchema.Builder extension

- Add `Builder field(String name, FieldType type, EncryptionSpec encryptionSpec)` overload
- Existing `field(name, type)` delegates to the 3-arg form with `EncryptionSpec.NONE`

### E3 — DocumentSerializer extension

- At `SchemaSerializer` construction, create `FieldEncryptionDispatch` from schema + key holder
- In encode path: encrypt field bytes after serialization, before writing to output
- In decode path: decrypt field bytes after reading from input, before deserialization

### E4 — IndexRegistry extension

- At construction, validate each indexed field's `EncryptionSpec` against the index type's requirements
- E.g., range index on a field with `Opaque` encryption → `IllegalArgumentException`
- Capability matrix: use `EncryptionSpec.supportsEquality()`, `.supportsRange()`, etc.

---

## Work Units

### WU-1 — Foundation types

**Constructs:** N1 (EncryptionSpec), N2 (EncryptionKeyHolder), E1 (FieldDefinition ext), E2 (JlsmSchema.Builder ext)
**Depends on:** none
**Estimated load:** ~3K tokens test, ~3K tokens implement, ~1K tokens refactor

**Implementation order (within unit):**
1. `EncryptionSpec` — sealed interface with 5 permits, capability methods, static factories
2. `EncryptionKeyHolder` — Arena-backed off-heap key storage
3. `FieldDefinition` extension — add `encryptionSpec` component with backward compatibility
4. `JlsmSchema.Builder` extension — add 3-arg `field()` overload

### WU-2 — Encryption engines

**Constructs:** N3 (AesSivEncryptor), N4 (BoldyrevaOpeEncryptor), N5 (DcpeSapEncryptor), N6 (AesGcmEncryptor)
**Depends on:** WU-1 (EncryptionKeyHolder)
**Estimated load:** ~6K tokens test, ~8K tokens implement, ~2K tokens refactor

**Implementation order (within unit):**
1. `AesGcmEncryptor` — simplest, uses JCE directly
2. `AesSivEncryptor` — CMAC + CTR, more complex but well-specified
3. `BoldyrevaOpeEncryptor` — hypergeometric sampling, algorithmic complexity
4. `DcpeSapEncryptor` — vector math + PRNG seeding

### WU-3 — Serializer + index integration

**Constructs:** N7 (FieldEncryptionDispatch), E3 (DocumentSerializer ext), E4 (IndexRegistry ext)
**Depends on:** WU-1 (EncryptionSpec, FieldDefinition), WU-2 (all encryptors)
**Estimated load:** ~4K tokens test, ~5K tokens implement, ~2K tokens refactor

**Implementation order (within unit):**
1. `FieldEncryptionDispatch` — spec-to-encryptor mapping
2. `DocumentSerializer` extension — integrate dispatch into encode/decode
3. `IndexRegistry` extension — capability matrix validation

### WU-4 — Full-text search tiers

**Constructs:** N9 (PositionalPostingCodec), N8 (SseEncryptedIndex)
**Depends on:** WU-2 (AesSivEncryptor, BoldyrevaOpeEncryptor), WU-3 (FieldEncryptionDispatch)
**Estimated load:** ~5K tokens test, ~8K tokens implement, ~2K tokens refactor

**Implementation order (within unit):**
1. `PositionalPostingCodec` — T2 position-aware postings (DET + OPE)
2. `SseEncryptedIndex` — T3 SSE encrypted inverted index (Curtmola SSE-2)

---

## Execution Order (across work units)

Balanced execution strategy — WU-1 and WU-2 can partially overlap (WU-2 starts after EncryptionKeyHolder is complete):

```
WU-1 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
         WU-2 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                      WU-3 ━━━━━━━━━━━━━━━━━━━━━━
                                                              WU-4 ━━━━━━━━━━━━━━━━━━━━━━
```

Total estimated: ~49K tokens across 4 work units.
