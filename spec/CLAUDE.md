# Specifications — Root Index

> **Managed by vallorcine agents. Use slash commands to modify this file.**
> To bootstrap: `/spec-init`
> To resolve context: `/spec-resolve "<feature description>"`
> To author a spec: `/spec-write "<id>" "<title>"`
> To verify a spec: `/spec-verify "<id>"`

> Pull model. Agents resolve specs via `spec-resolve.sh`, not by scanning.
> Do not read `.spec/` recursively. Use the resolver for context bundles.
> Structure: .spec/domains/<domain>/<spec>.md

## Domain Taxonomy

| Domain | Path | Description | Specs |
|--------|------|-------------|-------|

## Recently Added (last 10)

| Date | ID | Domain | Title |
|------|-----|--------|-------|

## Spec File Format Reference

Spec files use JSON front matter (between `---` delimiters), a machine-readable
requirements section, and a human narrative section separated by a bare `---` line.

```
---
{ "id": "F01", "version": 1, "status": "ACTIVE", "state": "DRAFT",
  "domains": [...], "requires": [...], "invalidates": [...],
  "decision_refs": [...], "kb_refs": [...], ... }
---

# F01 — Title

## Requirements
R1. Single falsifiable claim with explicit subject.
R2. ...

---

## Design Narrative
...
```

**Front matter fields:**
- `id` — feature identifier (F01, F02, ...)
- `version` — integer, incremented on revision
- `status` — lifecycle: ACTIVE | STABLE | DEPRECATED
- `state` — verification: DRAFT | APPROVED | INVALIDATED
- `domains` — array of domain slugs this spec belongs to
- `amends` / `amended_by` — cross-feature amendment links
- `requires` — feature IDs this spec depends on at runtime
- `invalidates` — specific FXX.RN references this spec supersedes
- `decision_refs` — ADR slugs from .decisions/ (cross-reference, not duplication)
- `kb_refs` — KB paths from .kb/ (topic/category/subject)
- `open_obligations` — work items that must be addressed

**Requirement writing rules:**
- One falsifiable claim per requirement
- Explicit subject: "The vector index must..." not "Must..."
- Measurable condition where applicable
- No compound requirements (no "and" joining two obligations)
- Present tense, active voice
- Unverified claims annotated: `[UNVERIFIED: assumes X]`
- **Behavioral, not structural:** requirements describe observable behavior,
  never specific class/method/file names. Verifiable by testing inputs and
  outputs, not by reading source code.

**Registry:** `.spec/registry/manifest.json` — machine-readable index.
**Obligations:** `.spec/registry/_obligations.json` — cross-feature work items.

## Code Traceability — @spec Annotations

Implementation and test code links back to specs via `@spec` annotations in
comments. These annotations are the primary mechanism for finding where a
requirement is enforced (implementation) and where it is validated (tests).

### Format

```
@spec FXX.RN              — single requirement
@spec FXX.RN,RN,RN        — multiple reqs from same spec
@spec FXX.RN FYY.RN       — multiple specs (space-separated)
@spec FXX.RN — description — optional human-readable note after dash
```

**Identifier rules:**
- Feature ID is always `FXX` — zero-padded, minimum 2 digits (`F01` not `F1`)
- Requirement number is `RN` — no zero-padding (`R1`, `R27`, `R156`)
- The `FXX.` prefix is mandatory on every reference — bare `R1` is invalid
- Canonical grep pattern: `@spec\s+F\d{2,}\.R\d+`

### Placement

- Use the host language's comment syntax (`//`, `#`, `/* */`, `--`, etc.)
- Place above the enforcing method or code block (like `@Override` in Java)
- One annotation per enforcement region — if a whole method implements R1,
  annotate the method once, not each line
- Same format in both implementation files and test files

### Examples

```java
// @spec F13.R1 — rejects null keys at index boundary
public void add(Key key, Value value) {
    if (key == null) throw new NullKeyException();
    ...
}

// @spec F13.R1,R3
@Test void testNullKeyRejection() { ... }
```

```python
# @spec F08.R12 F05.R4 — shared serialization constraint
def serialize(self, record):
    ...
```

### Relationship model

- **Many-to-many:** one requirement can have many enforcement points across
  files; one code location can enforce multiple requirements
- **No primary/secondary distinction:** all annotations are equal
- **Implementation vs test:** distinguished by file path, not annotation syntax
- **Drift detection:** `/curate` checks annotation consistency — annotations
  are written at implementation time and verified periodically, not maintained
  in real-time

### Tooling

- `spec-trace.sh <FXX>` — finds all `@spec` annotations for a feature,
  grouped by file, distinguishing implementation vs test locations
- `spec-verify` uses annotations as discovery hints when verifying requirements
- Coverage scripts use scoped `FXX.RN` matching (not bare R-numbers)
