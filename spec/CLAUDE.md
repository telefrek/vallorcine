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
- `invalidates` — specific `<spec-id>.RN` references this spec supersedes
- `decision_refs` — ADR slugs from .decisions/ (cross-reference, not duplication)
- `kb_refs` — KB paths from .kb/ (topic/category/subject)
- `open_obligations` — work items that must be addressed
- `parent_spec` — (optional) immediate parent spec ID for nested specs.
  Set on children of a layered domain (see "Layered specs" below). Single
  string; null/omitted on top-level specs.

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
@spec <spec-id>.RN              — single requirement
@spec <spec-id>.RN,RN,RN        — multiple reqs from same spec
@spec <spec-id>.RN <other>.RN   — multiple specs (space-separated)
@spec <spec-id>.RN — description — optional human-readable note after dash
```

`<spec-id>` is the spec's identifier from its frontmatter `id` field. Two
formats are supported:

- **`FXX`** (legacy) — zero-padded numeric feature ID like `F01`, `F13`.
  Example: `@spec F13.R1`.
- **`domain.slug`** (recommended for new projects) — behavioral-domain
  identifier like `schema.field-access`, `query.full-text-index`.
  Example: `@spec schema.field-access.R1`.

Use whichever format your project's specs use — check `.spec/domains/`
to see the convention. Mixing both formats in the same project works but
is discouraged.

**Identifier rules:**
- Requirement number is `RN` (with optional letter suffix for amendments —
  `R1`, `R27`, `R51a`). No zero-padding.
- The `<spec-id>.` prefix is mandatory on every reference — bare `R1` is invalid
- Spec IDs may be nested (one or more dots) for layered specs — see
  "Layered specs" below. `@spec encryption.primitives-lifecycle.key-rotation.R45`
  is valid.
- Canonical grep pattern: `@spec\s+(F\d{2,}|[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+)\.R\d+[a-z]?`

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

- `spec-trace.sh <spec-id>` — finds all `@spec` annotations for a spec
  (accepts FXX or domain.slug, including nested IDs),
  grouped by file, distinguishing implementation vs test locations
- `spec-verify` uses annotations as discovery hints when verifying requirements
- Coverage scripts use scoped `<spec-id>.RN` matching (not bare R-numbers)

## Layered specs (parent + children)

A spec can subdivide into a parent + children when a domain matures past
one file's worth of behavior. The parent stays a full spec — it retains
R-numbered cross-cutting requirements that genuinely span all children
(e.g. "all DEKs MUST be wrappable under their tenant root"). Children
own concern-specific requirements.

This is a **natural progression**, not a remediation step. Specs start
unsplit; they subdivide when `/curate` or `/spec-author` recognize that
multiple distinct concerns have accumulated. The explicit
`/spec-split <spec-id>` skill executes the subdivision.

### File layout

The file system mirrors the ID hierarchy:

```
.spec/domains/encryption/
  primitives-lifecycle.md              ← parent (cross-cutting + glossary)
  primitives-lifecycle/                ← children directory
    key-rotation.md
    dek-management.md
    revocation.md
```

Recursive — a child can itself subdivide later
(`primitives-lifecycle/key-rotation/scheduled.md`). Same shape, same
tooling.

### ID grammar and ID↔path

Spec IDs use one or more dots:

- `encryption` — the top-level domain (no spec, just a directory)
- `encryption.primitives-lifecycle` — top-level spec in that domain
- `encryption.primitives-lifecycle.key-rotation` — child spec under
  `primitives-lifecycle`

The path is **deterministic** from the ID:
`a.b.c.d` → `.spec/domains/a/b/c/d.md`. First component is the
top-level domain dir; intermediate components become subdirectories;
last component is the filename. The manifest still indexes every spec
explicitly; the ID-computed path is a fallback used by
`spec_file_for_id()` when a spec is not yet registered.

### Children declare `parent_spec`

A child spec's frontmatter carries a single-string `parent_spec` field
naming its immediate parent:

```json
{
  "id": "encryption.primitives-lifecycle.key-rotation",
  "parent_spec": "encryption.primitives-lifecycle",
  ...
}
```

Parents do **not** declare children — `children_specs` is computed at
scan time from the manifest (mirrors the `.decisions/` parent
precedent; avoids bidirectional-sync bugs). Validation enforces:

- Parent must exist in the manifest.
- Child ID must be `parent_id` + `.` + exactly one segment (so
  `encryption.primitives-lifecycle.key-rotation` may declare
  `encryption.primitives-lifecycle` as parent, but not
  `encryption.foo`).
- Parent chain must be acyclic.

### Loading rules

`spec-resolve.sh` is hierarchy-aware:

- When a child lands in candidates, the **entire parent chain is
  auto-included**. Cross-cutting requirements at a parent are part of
  every descendant's contract; they cannot be dropped.
- `INCLUDE_SIBLINGS=true` (env var) opts into loading every sibling
  (other children of the same parent). Used by adversarial paths
  (`/spec-author` Pass 2/3) that need cross-sibling contradiction
  detection.

`@spec` annotations resolve through the same `spec_file_for_id()` —
no annotation rewriting is needed when subdivision happens at the
*parent* boundary (cross-cutting requirements that stay at parent
keep their existing annotations).

### When to subdivide

Subdivision is appropriate when:

- A spec's machine section is approaching the read cap
  (~25K tokens — well under the kit's pipe-buffer SIGPIPE cliff
  past 64KB)
- Multiple distinct behavioral categories have accumulated, each
  with its own dense requirement set
- The cross-category reference density is low (each category is
  largely self-contained)

Subdivision is **not** appropriate for specs that are large because
of one tightly-coupled concern (the size is real but the concern is
indivisible). `/curate`'s subdivision detector surfaces candidates;
the user approves or skips per spec.
