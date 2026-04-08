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
