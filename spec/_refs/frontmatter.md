---
type: reference-fragment
title: Spec Frontmatter Schema (Canonical)
---

# Spec Frontmatter Schema (Canonical)

Every spec under `.spec/domains/` opens with a JSON frontmatter block
between `---` delimiters. This file is the single authoritative
schema. The validator (`scripts/spec-validate.sh`) enforces it; the
writer (`/spec-write`) emits files conforming to it; `/curate`
analyses (notably the spec corpus drift checks) reconcile against it.

If a `/curate` scan or a `spec-validate.sh` run flagged a schema
deviation, the patch is to bring the spec into alignment with this
file — not to extend the schema.

## Why JSON, not YAML

KB entries and ADRs use YAML frontmatter. Specs use JSON inside `---`
fences. The reason is mechanical: spec frontmatter has structured
arrays (`requires`, `invalidates`, `decision_refs`, `kb_refs`) and
nullable fields (`amends`, `parent_spec`, `displaced_by`) that are
read and written by `jq` from `spec-lib.sh`. JSON gives one parser,
deterministic round-trip, and no quoting ambiguity for arrays of
spec-id references that contain dots.

Tooling that reads spec frontmatter MUST use `jq` (or the
`fm` wrapper in `spec-lib.sh`), never grep-for-`^key:`. Patterns that
work on KB/ADR YAML will silently miss every spec field.

## Block format

```
---
{
  "id": "<spec-id>",
  "version": <integer>,
  "status": "<DRAFT|ACTIVE|STABLE|DEPRECATED>",
  "state":  "<DRAFT|APPROVED|INVALIDATED>",
  "domains": ["<domain1>", "<domain2>"],
  "requires": [],
  "invalidates": [],
  "amends": null,
  "amended_by": null,
  "decision_refs": [],
  "kb_refs": []
}
---
```

The closing `---` is followed by a third bare `---` line later in
the file, marking the human narrative section. Three `---` lines
total: open frontmatter, close frontmatter, open narrative.

## Required core fields

Every spec MUST have these. `spec-validate.sh` exits non-zero if any
are missing or malformed.

| Field | Type | Constraint |
|-------|------|------------|
| `id` | string | Either `FXX` (legacy) or lowercase `domain.slug[.subdomain...]` |
| `version` | integer | Increments on each spec rewrite (`/spec-write` v2, v3, …) |
| `status` | enum | `DRAFT` \| `ACTIVE` \| `STABLE` \| `DEPRECATED` |
| `state`  | enum | `DRAFT` \| `APPROVED` \| `INVALIDATED` |
| `domains` | array | Non-empty list of domain folder names |

### `state` vs `status` — they are NOT the same field

The two fields express different concepts. Both are required. Both
are independently validated.

- **`state`** — the spec's *lifecycle position* in the pipeline.
  - `DRAFT` — being authored or has unresolved conflict markers.
  - `APPROVED` — registered, passed validation, entered the
    resolved-bundle pool.
  - `INVALIDATED` — superseded by another spec via the displacement
    chain (`displaced_by`). Excluded from `/spec-resolve` bundles by
    default.
- **`status`** — the spec's *implementation/consumption posture*.
  - `DRAFT` — not yet pursued.
  - `ACTIVE` — currently the source of truth for ongoing
    implementation work.
  - `STABLE` — implementation has settled; spec is reference material.
  - `DEPRECATED` — author intent to retire, not yet displaced.
    **`status: DEPRECATED` without a corresponding
    `state: INVALIDATED` is a graduation candidate** —
    `/curate` Analysis 27 flags this.

**Common confusion:** marking a spec `DEPRECATED` does NOT remove it
from `/spec-resolve` bundles. To take a spec out of resolution, set
`state: INVALIDATED` (which requires a `displaced_by` reference). The
`status` field is documentation only.

## Optional fields

```json
{
  "kind": "interface-contract",
  "parent_spec": "<parent-id>",
  "displaced_by": ["<successor-id>"],
  "displacement_reason": "<free text>",
  "revives": ["<predecessor-id>"],
  "revived_by": ["<successor-id>"],
  "_split_from": "<parent-id>",
  "open_obligations": []
}
```

| Field | Purpose |
|-------|---------|
| `kind` | Currently only `interface-contract` (work-layer interface specs). Omit otherwise. |
| `parent_spec` | Single parent ID when this spec is a `/spec-split` child. ID prefix MUST match parent + one segment. Acyclic. |
| `displaced_by` | Specs that supersede this one. Setting non-empty REQUIRES `state: INVALIDATED`. Pipeline-managed, do NOT set by hand. |
| `displacement_reason` | Free text; required when `displaced_by` is non-empty. |
| `revives` | Specs whose intent this spec restores. Each target MUST be `state: INVALIDATED`. Pipeline-managed. |
| `revived_by` | Inverse of `revives`. Pipeline-managed. |
| `_split_from` | Set by `/spec-split` on the children. Informational. |
| `open_obligations` | Array of obligation IDs blocking APPROVED state when present. |

## Cross-references

Three reference families resolve against external stores:

- **`requires`** — spec IDs in `requires` MUST appear in
  `manifest.json`. `spec-validate.sh` Check 6 enforces this.
- **`decision_refs`** — ADR slugs. Resolution path:
  `.decisions/<slug>/adr.md`. Missing files surface as warnings;
  `/curate` Analysis 28 (corpus xref scan) flags broken refs at
  scale.
- **`kb_refs`** — KB entry paths (no `.md` extension). Resolution
  path: `.kb/<path>.md`. Missing files surface as warnings; `/curate`
  Analysis 28 flags broken refs at scale.

Reference IDs use the same grammar as `id`:

- Spec ID alone: `F01` OR `schema.field-access` OR
  `encryption.primitives-lifecycle.key-rotation`.
- Spec requirement ref (in `invalidates`): `F01.R3` OR
  `schema.field-access.R3`. Letter-suffixed Rs (`R51a`) and
  multi-dot IDs are supported.

## ID grammar

```
spec_id_re='^(F[0-9]+|[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+)$'
spec_ref_re='^(F[0-9]+|[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+)\.R[0-9]+[a-z]*(-[0-9]+[a-z]*)?$'
```

(Defined once in `spec-validate.sh`. Never re-implement these
patterns elsewhere; source them or call `spec-validate.sh`.)

## Validation

Every write path through `/spec-write` calls `spec-validate.sh
<file>`. The script exits non-zero on any error and prints all
errors before exiting (no silent partial validation). Warnings are
emitted to stderr and do not block the write — these include
unresolvable `decision_refs` / `kb_refs`. Hard errors include
malformed JSON, missing required fields, invalid enum values,
unresolvable `requires` / `displaced_by` / `revives`, and
`state: APPROVED` with `[UNRESOLVED]` or `[CONFLICT]` markers in the
machine section.

## What `/curate` adds on top

Per-spec validation is necessary but not sufficient. Two `/curate`
analyses look at the corpus:

- **Analysis 27 — DEPRECATED-without-INVALIDATED**: surfaces specs
  carrying `status: DEPRECATED` while still `state: APPROVED`,
  meaning they continue to enter `/spec-resolve` bundles despite the
  user's intent to retire them. Recommendation routes to displacement
  finalization or to amending the status.
- **Analysis 28 — corpus xref drift**: walks every spec's
  `decision_refs` and `kb_refs`, reports broken paths in one rollup.
  Catches the case where a single spec's `spec-validate.sh` warning
  is easy to miss at scale (jlsm 2026-05-10: 1 broken kb_ref hidden
  among 84 distinct refs).

Run `/curate --init` (or `/curate` after a normal scan) to surface
both.
