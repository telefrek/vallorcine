---
feature: "ope-type-aware-bounds"
created: "2026-03-19"
---

# Work Plan — ope-type-aware-bounds

## Overview
Replace hardcoded Long.MAX_VALUE/2 OPE domain in FieldEncryptionDispatch with type-aware bounds derived from field type. Add BoundedString field type. Restrict OrderPreserving to compatible types. Write encryption README.

## Work Units

This is a single-unit feature — all changes are tightly coupled and must compile together.

### WU-1: BoundedString + OPE Domain Derivation + Validation + Documentation

**Constructs (new):**
1. `FieldType.BoundedString(int maxLength)` — new sealed permit record
2. `FieldType.string(int maxLength)` — static factory method
3. `FieldEncryptionDispatch.deriveOpeBounds(FieldType)` — domain/range derivation
4. `modules/jlsm-core/src/main/java/jlsm/encryption/README.md` — encryption package docs

**Constructs (modified):**
5. `FieldType` sealed interface — add BoundedString to permits clause
6. `FieldEncryptionDispatch` — replace hardcoded OPE domain with type-aware derivation
7. `IndexRegistry.validate()` — reject OrderPreserving on unbounded STRING, BOOLEAN, FLOAT*, VECTOR, ARRAY, OBJECT
8. `JlsmDocument.validateType()` — add `case BoundedString` delegating to STRING logic + length check
9. `DocumentSerializer` — add `case BoundedString _` in measureField, encodeField, decodeField (delegate to STRING)
10. `JsonParser` — add `case BoundedString _` delegating to STRING
11. `JsonWriter` — add `case BoundedString _` delegating to STRING
12. `YamlParser` — add `case BoundedString _` delegating to STRING
13. `YamlWriter` — add `case BoundedString _` delegating to STRING (2 switch sites)
14. `FieldValueCodec` — extend instanceof check to accept BoundedString as Primitive STRING-equivalent
15. `IndexRegistry.extractFieldValue()` — extend instanceof chain to handle BoundedString
16. `QueryExecutor.extractFieldValue()` — extend instanceof chain to handle BoundedString
17. `IndexRegistry.validate()` — accept BoundedString for RANGE/UNIQUE/EQUALITY/FULL_TEXT index types

**Switch sites inventory (all in jlsm-table/src/main/java):**
| File | Line(s) | Pattern | Action |
|------|---------|---------|--------|
| FieldType.java | 17-18 | permits clause | Add BoundedString |
| JlsmDocument.java | 349-385 | switch(type) validateType | Add case BoundedString |
| DocumentSerializer.java | 386-424 | measureField switch | Add case BoundedString |
| DocumentSerializer.java | 502-548 | encodeField switch | Add case BoundedString |
| DocumentSerializer.java | 716-766 | decodeField switch | Add case BoundedString |
| JsonParser.java | 151-155 | switch(type) | Add case BoundedString |
| JsonWriter.java | 89-93 | switch(type) | Add case BoundedString |
| YamlParser.java | 132-157 | switch(fd.type()) | Add case BoundedString |
| YamlWriter.java | 75-79 | switch(type) | Add case BoundedString |
| YamlWriter.java | 157-162 | switch(type) element | Add case BoundedString |
| FieldValueCodec.java | 42, 64 | instanceof Primitive check | Accept BoundedString |
| IndexRegistry.java | 200-234 | validate switch | Accept BoundedString for RANGE/UNIQUE/EQUALITY/FULL_TEXT |
| IndexRegistry.java | 302-320 | extractFieldValue instanceof | Add BoundedString branch |
| QueryExecutor.java | 179 | extractFieldValue instanceof | Add BoundedString branch |

**OPE domain derivation table:**
| FieldType | Domain | Range | Notes |
|-----------|--------|-------|-------|
| INT8 | 256 | 2,560 | Full 8-bit range |
| INT16 | 65,536 | 655,360 | Full 16-bit range |
| INT32 | 4,294,967,296 (2^32) | 42,949,672,960 (2^32*10) | Full 32-bit range |
| INT64 | 281,474,976,710,656 (2^48) | 2,814,749,767,106,560 (2^48*10) | Capped to prevent deep recursion |
| TIMESTAMP | same as INT64 | same as INT64 | Epoch millis |
| BoundedString(n) | 256^min(n,6) + 1 | domain * 10 | +1 ensures domain >= 1 after bytesToPositiveLong offset |

**Implementation order:**
1. Add BoundedString record + factory to FieldType (foundation)
2. Update all switch sites (compile fix — trivial STRING delegation)
3. Add deriveOpeBounds to FieldEncryptionDispatch, replace hardcoded domain
4. Tighten IndexRegistry validation for OrderPreserving
5. Add length validation in JlsmDocument for BoundedString
6. Write encryption README.md

**Test file:** `modules/jlsm-table/src/test/java/jlsm/table/BoundedStringOpeTest.java`

## Dependencies
- WU-1 and WU-2 from extract-core-encryption (encryption classes in jlsm.encryption) — complete
- fix-encryption-performance (Cipher caching) — complete

## Risk
- Low: all switch site changes are mechanical STRING delegation
- Medium: OPE domain derivation math must match bytesToPositiveLong encoding
