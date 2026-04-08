---
feature: "optimize-document-serializer"
created: "2026-03-18"
status: "confirmed"
---

# Work Plan — optimize-document-serializer

## References

| Document | Path |
|----------|------|
| Brief | .feature/optimize-document-serializer/brief.md |
| Domains | .feature/optimize-document-serializer/domains.md |
| Target file | modules/jlsm-table/src/main/java/jlsm/table/DocumentSerializer.java |

## Existing Constructs to Extend

### SchemaSerializer constructor
**File:** `modules/jlsm-table/src/main/java/jlsm/table/DocumentSerializer.java` (line ~96)
**Change:** Add precomputed schema constants (`fieldArray`, `isBoolField`, `prefixBoolCount`, `fieldCount`, `boolCount`, `nullMaskBytes`, `boolMaskBytes`) and build the `FieldDecoder[]` dispatch table. All computed from the `JlsmSchema` passed at construction time.

### SchemaSerializer#deserialize()
**File:** `modules/jlsm-table/src/main/java/jlsm/table/DocumentSerializer.java` (line ~144)
**Change:** Replace `segment.toArray()` with `extractBytes()` heap fast path. Replace per-call `countBoolFieldsUpTo()` with `prefixBoolCount[]` lookup. Replace per-field `switch` pattern matching in `decodeField` with `decoders[i].decode(buf, cursor)` dispatch.

## New Constructs to Create

### ByteArrayView record + extractBytes method
**File:** `DocumentSerializer.java` (private, inside class)
**Purpose:** Zero-copy heap fast path. `heapBase().isPresent()` returns the backing `byte[]` + offset directly; off-heap fallback copies via `toArray()`.

```java
private record ByteArrayView(byte[] data, int offset) {}

private static ByteArrayView extractBytes(MemorySegment segment) {
    Optional<Object> heapBase = segment.heapBase();
    if (heapBase.isPresent()) {
        byte[] data = (byte[]) heapBase.get();
        int offset = (int) segment.heapOffset();
        return new ByteArrayView(data, offset);
    } else {
        byte[] data = segment.toArray(ValueLayout.JAVA_BYTE);
        return new ByteArrayView(data, 0);
    }
}
```

### int[] prefixBoolCount
**File:** `DocumentSerializer.java` — field in `SchemaSerializer`
**Purpose:** Precomputed array where `prefixBoolCount[i]` = number of boolean fields in positions `0..i-1`. Length `fieldCount + 1` so `prefixBoolCount[writeFieldCount]` works for any `writeFieldCount <= fieldCount`. Replaces `countBoolFieldsUpTo()` during deserialization — O(1) lookup vs O(n) iteration. Handles schema evolution correctly.

### FieldDecoder @FunctionalInterface + FieldDecoder[] decoders
**File:** `DocumentSerializer.java` — private interface + field in `SchemaSerializer`
**Purpose:** Dispatch table indexed by field position. Each entry is a lambda that decodes the field from `byte[] buf` + `Cursor`. Replaces per-field `switch` pattern matching in `decodeField`. Boolean fields use a special decoder that reads from the bool bitmask. Built once per schema in the constructor.

```java
@FunctionalInterface
private interface FieldDecoder {
    Object decode(byte[] buf, Cursor cursor);
}
```

## Contract Definitions

No new public API. All constructs are `private` inside `DocumentSerializer`. The external contract is unchanged:
- `SchemaSerializer` implements `MemorySerializer<JlsmDocument>`
- `serialize(JlsmDocument)` — unchanged
- `deserialize(MemorySegment)` — same signature, same output, internal implementation optimized
- Binary format — unchanged, all existing round-trip tests must pass identically

## Implementation Order

| Step | Construct | Depends On | Description |
|------|-----------|------------|-------------|
| 1 | `ByteArrayView` + `extractBytes` | — | Private record and static method, no dependencies |
| 2 | Precomputed schema constants | — | `fieldArray`, `isBoolField`, `prefixBoolCount`, mask sizes in `SchemaSerializer` constructor |
| 3 | `FieldDecoder` interface + dispatch table | Step 2 | Build `FieldDecoder[]` in constructor using precomputed field metadata |
| 4 | Modified `deserialize()` | Steps 1, 2, 3 | Rewrite deserialize to use `extractBytes`, `prefixBoolCount[]`, and `decoders[]` |

All steps modify a single file: `modules/jlsm-table/src/main/java/jlsm/table/DocumentSerializer.java`.

## Precomputed SchemaSerializer Fields (Reference)

```java
private final JlsmSchema schema;
private final FieldDefinition[] fieldArray;
private final boolean[] isBoolField;
private final int[] prefixBoolCount;    // length fieldCount + 1
private final int fieldCount;
private final int boolCount;
private final int nullMaskBytes;
private final int boolMaskBytes;
private final FieldDecoder[] decoders;
```

## Modified deserialize() (Reference)

```java
public JlsmDocument deserialize(MemorySegment segment) {
    ByteArrayView view = extractBytes(segment);
    byte[] buf = view.data();
    Cursor cursor = new Cursor(buf, view.offset());

    int _ = readShortBE(buf, cursor.advance(2)) & 0xFFFF;
    int writeFieldCount = readShortBE(buf, cursor.advance(2)) & 0xFFFF;

    int readCount = Math.min(writeFieldCount, fieldCount);
    int writeBoolCount = prefixBoolCount[Math.min(writeFieldCount, fieldCount)];
    int writeNullMaskBytes = (writeFieldCount + 7) / 8;
    int writeBoolMaskBytes = writeBoolCount > 0 ? (writeBoolCount + 7) / 8 : 0;

    int nullMaskOffset = cursor.advance(writeNullMaskBytes);
    int boolMaskOffset = writeBoolCount > 0 ? cursor.advance(writeBoolMaskBytes) : -1;

    Object[] values = new Object[fieldCount];
    int boolIdx = 0;
    for (int i = 0; i < readCount; i++) {
        boolean isNull = isNullBit(buf, nullMaskOffset, i);
        if (isNull) {
            if (isBoolField[i]) boolIdx++;
            continue;
        }
        if (isBoolField[i]) {
            values[i] = isBoolBit(buf, boolMaskOffset, boolIdx);
            boolIdx++;
        } else {
            values[i] = decoders[i].decode(buf, cursor);
        }
    }

    return new JlsmDocument(schema, values);
}
```

## Testing Strategy

All changes are internal optimizations. Existing tests validate correctness:
- Round-trip serialize/deserialize tests confirm byte-identical output
- Schema evolution tests confirm writeFieldCount < currentFieldCount handling
- Off-heap segment tests confirm fallback path

New tests to add:
- `extractBytes` returns zero-copy view for heap-backed segments (verify `data` is same array reference)
- `extractBytes` returns copied array for off-heap segments (verify offset is 0)
- `prefixBoolCount` correctness for schemas with mixed field types
- Dispatch table produces identical results to current `decodeField` for all `FieldType` variants

## Risk Notes

- JIT inlining of `FieldDecoder` lambdas needs benchmark validation (noted in brief as open assumption)
- `heapBase()` returns `Optional<Object>` — the cast to `byte[]` is safe only for `MemorySegment.ofArray(byte[])` segments; other heap-backed segment types (if any future JDK adds them) would need review
