---
feature: "extract-core-encryption"
created: "2026-03-19"
status: "approved"
---

# Work Plan — extract-core-encryption

## References
- **Brief:** [brief.md](brief.md)
- **Domains:** [domains.md](domains.md)
- **ADRs:**
  - [`.decisions/pre-encrypted-document-signaling/adr.md`](../../.decisions/pre-encrypted-document-signaling/adr.md) — Factory method with boolean field
  - [`.decisions/field-encryption-api-design/adr.md`](../../.decisions/field-encryption-api-design/adr.md) — Schema annotation (EncryptionSpec, FieldEncryptionDispatch)

## Modules Affected
- **jlsm-core** — receives 6 moved classes into new exported package `jlsm.encryption`
- **jlsm-table** — loses 6 classes from `jlsm.table` / `jlsm.table.internal`, gains extensions to existing classes + 1 new internal class

---

## Existing Constructs

| # | Construct | Location | Action | Target Location |
|---|-----------|----------|--------|-----------------|
| 1 | EncryptionSpec | `jlsm.table.EncryptionSpec` | move | `jlsm.encryption.EncryptionSpec` (jlsm-core, exported) |
| 2 | EncryptionKeyHolder | `jlsm.table.internal.EncryptionKeyHolder` | move | `jlsm.encryption.EncryptionKeyHolder` (jlsm-core, exported) |
| 3 | AesSivEncryptor | `jlsm.table.internal.AesSivEncryptor` | move | `jlsm.encryption.AesSivEncryptor` (jlsm-core, exported) |
| 4 | AesGcmEncryptor | `jlsm.table.internal.AesGcmEncryptor` | move | `jlsm.encryption.AesGcmEncryptor` (jlsm-core, exported) |
| 5 | BoldyrevaOpeEncryptor | `jlsm.table.internal.BoldyrevaOpeEncryptor` | move | `jlsm.encryption.BoldyrevaOpeEncryptor` (jlsm-core, exported) |
| 6 | DcpeSapEncryptor | `jlsm.table.internal.DcpeSapEncryptor` | move | `jlsm.encryption.DcpeSapEncryptor` (jlsm-core, exported) |
| 7 | FieldEncryptionDispatch | `jlsm.table.internal.FieldEncryptionDispatch` | extend | promote to `jlsm.table`, add `validateCiphertextLength()` |
| 8 | JlsmDocument | `jlsm.table.JlsmDocument` | extend | add `preEncrypted` field, factory, getter |
| 9 | DocumentAccess | `jlsm.table.internal.DocumentAccess` | extend | add `isPreEncrypted()` to Accessor interface + impl |
| 10 | DocumentSerializer | `jlsm.table.DocumentSerializer` | extend | add pre-encrypted branch in serialize path |
| 11 | module-info.java (jlsm-core) | `modules/jlsm-core/src/main/java/module-info.java` | update | add `exports jlsm.encryption;` |
| 12 | module-info.java (jlsm-table) | `modules/jlsm-table/src/main/java/module-info.java` | update | no change needed (`requires transitive jlsm.core` already present) |
| 13 | build.gradle (jlsm-core) | `modules/jlsm-core/build.gradle` | update | no new `--add-exports` needed (package is exported) |
| 14 | build.gradle (jlsm-table) | `modules/jlsm-table/build.gradle` | update | no change needed (no existing `--add-exports` for moved packages) |

## New Constructs

| # | Construct | Location | Purpose |
|---|-----------|----------|---------|
| 15 | CiphertextValidator | `jlsm.table.internal.CiphertextValidator` | Validates ciphertext structural integrity per EncryptionSpec for pre-encrypted documents |

**Stub written:** `modules/jlsm-table/src/main/java/jlsm/table/internal/CiphertextValidator.java`

---

## Contract Definitions

### WU-1 Contracts: Module Extraction

#### File moves (items 1-6)

Each class is moved from its current location to `modules/jlsm-core/src/main/java/jlsm/encryption/`:

| Class | From package | To package |
|-------|-------------|------------|
| EncryptionSpec | `jlsm.table` | `jlsm.encryption` |
| EncryptionKeyHolder | `jlsm.table.internal` | `jlsm.encryption` |
| AesSivEncryptor | `jlsm.table.internal` | `jlsm.encryption` |
| AesGcmEncryptor | `jlsm.table.internal` | `jlsm.encryption` |
| BoldyrevaOpeEncryptor | `jlsm.table.internal` | `jlsm.encryption` |
| DcpeSapEncryptor | `jlsm.table.internal` | `jlsm.encryption` |

For each moved class:
- Update `package` declaration to `jlsm.encryption`
- Remove any intra-package imports that are no longer needed
- Add cross-package imports where the class references other moved classes (they all land in the same package, so most intra-references become package-local)
- EncryptionSpec's Javadoc references `jlsm.table.internal.IndexRegistry` — update to reflect that IndexRegistry remains in jlsm-table

#### module-info.java changes (items 11-12)

**jlsm-core** (`modules/jlsm-core/src/main/java/module-info.java`):
- Add `exports jlsm.encryption;` after the existing exports block

**jlsm-table** (`modules/jlsm-table/src/main/java/module-info.java`):
- No change needed. `requires transitive jlsm.core` already provides access to all exported jlsm-core packages including the new `jlsm.encryption`.

#### build.gradle changes (items 13-14)

**jlsm-core** (`modules/jlsm-core/build.gradle`):
- No new `--add-exports` needed because `jlsm.encryption` is an exported package.
- Tests for encryption classes that move to jlsm-core will import from the exported package directly.

**jlsm-table** (`modules/jlsm-table/build.gradle`):
- No change needed. There are no existing `--add-exports` entries for the moved packages.

#### Import update strategy

Source files in jlsm-table that must have imports updated:

| File | Old import(s) | New import(s) |
|------|---------------|---------------|
| `FieldDefinition.java` | `jlsm.table.EncryptionSpec` | `jlsm.encryption.EncryptionSpec` |
| `JlsmSchema.java` | `jlsm.table.EncryptionSpec` (if any direct reference) | `jlsm.encryption.EncryptionSpec` |
| `DocumentSerializer.java` | `jlsm.table.internal.EncryptionKeyHolder` | `jlsm.encryption.EncryptionKeyHolder` |
| `FieldEncryptionDispatch.java` | `jlsm.table.EncryptionSpec`, `jlsm.table.internal.{AesSivEncryptor, AesGcmEncryptor, BoldyrevaOpeEncryptor}` | `jlsm.encryption.*` |
| `IndexRegistry.java` | `jlsm.table.EncryptionSpec` | `jlsm.encryption.EncryptionSpec` |
| `SseEncryptedIndex.java` | any encryption imports | `jlsm.encryption.*` |
| `PositionalPostingCodec.java` | any encryption imports | `jlsm.encryption.*` |

Note: `EncryptionSpec` is currently in the `jlsm.table` package (same package as `FieldDefinition`), so some files may use it without an explicit import. After the move to `jlsm.encryption`, all usages in `jlsm.table` and `jlsm.table.internal` will need an explicit import.

#### Test file moves

Tests for pure encryption classes move from jlsm-table to jlsm-core:

| Test file | From | To |
|-----------|------|----|
| `EncryptionSpecTest.java` | `modules/jlsm-table/src/test/java/jlsm/table/` | `modules/jlsm-core/src/test/java/jlsm/encryption/` |
| `EncryptionKeyHolderTest.java` | `modules/jlsm-table/src/test/java/jlsm/table/` | `modules/jlsm-core/src/test/java/jlsm/encryption/` |
| `AesSivEncryptorTest.java` | `modules/jlsm-table/src/test/java/jlsm/table/` | `modules/jlsm-core/src/test/java/jlsm/encryption/` |
| `AesGcmEncryptorTest.java` | `modules/jlsm-table/src/test/java/jlsm/table/` | `modules/jlsm-core/src/test/java/jlsm/encryption/` |
| `BoldyrevaOpeEncryptorTest.java` | `modules/jlsm-table/src/test/java/jlsm/table/` | `modules/jlsm-core/src/test/java/jlsm/encryption/` |
| `DcpeSapEncryptorTest.java` | `modules/jlsm-table/src/test/java/jlsm/table/` | `modules/jlsm-core/src/test/java/jlsm/encryption/` |

Each moved test file:
- Update `package` declaration to `jlsm.encryption`
- Update imports: `jlsm.table.internal.{ClassName}` → `jlsm.encryption.{ClassName}`
- Update imports: `jlsm.table.EncryptionSpec` → `jlsm.encryption.EncryptionSpec`

Tests that STAY in jlsm-table (they test table-layer integration, not encryption primitives):
- `FieldDefinitionEncryptionTest.java` — tests FieldDefinition with EncryptionSpec; update imports only
- `JlsmSchemaEncryptionTest.java` — tests schema construction with encryption; update imports only
- `FieldEncryptionDispatchTest.java` — tests dispatch table; update imports to `jlsm.encryption.*`
- `IndexRegistryEncryptionTest.java` — tests index compatibility; update imports only
- `DocumentSerializerEncryptionTest.java` — tests serializer round-trip; update imports only
- `PositionalPostingCodecTest.java` — references AesSivEncryptor, BoldyrevaOpeEncryptor, EncryptionKeyHolder; update imports only
- `SseEncryptedIndexTest.java` — references EncryptionKeyHolder; update imports only

---

### WU-2 Contracts: Pre-Encrypted Document Support

#### CiphertextValidator (item 15)

**Location:** `modules/jlsm-table/src/main/java/jlsm/table/internal/CiphertextValidator.java`
**Stub:** written

**Contract:**
```java
public final class CiphertextValidator {
    private CiphertextValidator() {} // utility class

    /**
     * Validates ciphertext structural integrity for the given field's encryption spec.
     * @throws IllegalArgumentException if ciphertext is structurally invalid
     * @throws NullPointerException if field or ciphertext is null
     */
    public static void validate(FieldDefinition field, byte[] ciphertext);
}
```

**Validation rules per scheme:**
- `EncryptionSpec.None` — should not be called; throw IllegalArgumentException if invoked
- `EncryptionSpec.Deterministic` (AES-SIV) — min length 16 bytes (synthetic IV)
- `EncryptionSpec.Opaque` (AES-GCM) — min length 28 bytes (12 IV + 16 tag)
- `EncryptionSpec.OrderPreserving` (Boldyreva OPE) — exactly 8 bytes
- `EncryptionSpec.DistancePreserving` (DCPE/SAP) — length must equal `dimensions * 4`; dimensions derived from `field.type()` (must be VectorType)
- Null or empty ciphertext on any encrypted field — reject

Error messages must include: field name, encryption scheme, expected constraint, actual length.

#### FieldEncryptionDispatch extension (item 7)

**Current location:** `jlsm.table.internal.FieldEncryptionDispatch`
**New location:** `jlsm.table.FieldEncryptionDispatch` (promoted to exported package)

Changes:
- Move file from `internal/` to parent package
- Update `package` declaration to `jlsm.table`
- Update imports to reference `jlsm.encryption.*` (from WU-1)
- Add method:
```java
/**
 * Validates that the ciphertext length is structurally valid for the field
 * at the given index.
 *
 * @param fieldIndex the zero-based field index
 * @param actualLength the actual ciphertext byte length
 * @throws IllegalArgumentException if the length is invalid for the field's encryption spec
 */
public void validateCiphertextLength(int fieldIndex, int actualLength);
```

#### JlsmDocument extension (item 8)

**Location:** `modules/jlsm-table/src/main/java/jlsm/table/JlsmDocument.java`

Changes per ADR:
- Add field: `private final boolean preEncrypted`
- Extend existing constructor: `JlsmDocument(JlsmSchema schema, Object[] values, boolean preEncrypted)`
- Backward-compatible delegation: existing constructor calls `this(schema, values, false)`
- Add static factory: `public static JlsmDocument preEncrypted(JlsmSchema schema, Object... nameValuePairs)` — same validation as `of()` except type validation is SKIPPED for fields with `EncryptionSpec != NONE` (those values are expected to be `byte[]`)
- Add package-private getter: `boolean isPreEncrypted()`

#### DocumentAccess extension (item 9)

**Location:** `modules/jlsm-table/src/main/java/jlsm/table/internal/DocumentAccess.java`

Changes:
- Add to the `Accessor` interface: `boolean isPreEncrypted(JlsmDocument doc);`
- Add implementation in JlsmDocument's static initializer block: delegates to `doc.isPreEncrypted()`

#### DocumentSerializer extension (item 10)

**Location:** `modules/jlsm-table/src/main/java/jlsm/table/DocumentSerializer.java`

Changes in `SchemaSerializer.serialize()`:
- Read pre-encrypted flag via DocumentAccess: `final boolean preEnc = accessor.isPreEncrypted(doc);`
- Add pre-encrypted branch before existing encryption path:
  ```
  if (preEnc) {
      // Skip encryption; validate ciphertext via CiphertextValidator; write bytes directly
      encodeFieldsPreEncrypted(fields, values, cursor);
  } else {
      // Existing path unchanged
  }
  ```
- New private method `encodeFieldsPreEncrypted()`:
  - For each field with `EncryptionSpec != NONE`: cast value to `byte[]`, call `CiphertextValidator.validate()`, write ciphertext bytes
  - For each field with `EncryptionSpec.NONE`: encode normally (same as existing unencrypted path)
- Deserialization path: no changes (always decrypts)

---

## Work Units

### WU-1: Module Extraction

**Constructs:** 1-6 (moves), 11-14 (config updates), plus import updates in all affected source and test files
**Dependencies:** none
**Estimated load:** medium (mechanical moves + import updates across ~20 files)

**Deliverables:**
- 6 source files created in `modules/jlsm-core/src/main/java/jlsm/encryption/`
- 6 source files deleted from jlsm-table
- 6 test files created in `modules/jlsm-core/src/test/java/jlsm/encryption/`
- 6 test files deleted from jlsm-table
- module-info.java (jlsm-core) updated
- Imports updated in ~13 jlsm-table source+test files
- `./gradlew check` passes

### WU-2: Pre-Encrypted Document Support

**Constructs:** 7-10 (extensions), 15 (CiphertextValidator)
**Dependencies:** WU-1 (imports reference `jlsm.encryption.*`)
**Estimated load:** medium (5 files modified/created, new test class, integration with serializer)

**Deliverables:**
- CiphertextValidator implemented (stub already written)
- FieldEncryptionDispatch promoted + extended
- JlsmDocument extended with pre-encrypted support
- DocumentAccess extended
- DocumentSerializer extended with pre-encrypted branch
- Tests for all new behavior
- `./gradlew check` passes

---

## Implementation Order

```
WU-1: Module extraction
  ├── Tests: move 6 test files, update packages/imports, verify they fail (classes not yet in jlsm-core)
  ├── Impl: move 6 source files, update module-info, update all imports
  └── Verify: ./gradlew check

WU-2: Pre-encrypted document support (blocked on WU-1)
  ├── Tests: CiphertextValidator tests, JlsmDocument preEncrypted tests, DocumentSerializer pre-encrypted round-trip tests
  ├── Impl: CiphertextValidator, FieldEncryptionDispatch promotion + extension, JlsmDocument extension, DocumentAccess extension, DocumentSerializer extension
  └── Verify: ./gradlew check
```
