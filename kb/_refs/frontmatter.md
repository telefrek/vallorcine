---
type: reference-fragment
title: KB Frontmatter Schema (Canonical)
---

# KB Frontmatter Schema (Canonical)

Every KB entry begins with a YAML frontmatter block. This file defines the
authoritative schema. Every other template (`adversarial-finding-template.md`,
`feature-footprint-template.md`) MUST align with it. Writer skills (`/research`,
the audit pipeline, `/feature-retro`) MUST validate against it before writing.

If you are reading this because a `/curate` scan flagged a schema drift, the
patch is to bring the entry into alignment with this file — not to extend the
schema to match the entry.

## Why a single schema matters

Inconsistent frontmatter breaks every cross-cutting query the KB depends on:

- `kb-search.sh` ranks by tags and applies_to. Missing tags = missing matches.
- `/curate` cross-reference repair finds tag-overlap pairs. Missing tags =
  missing repair candidates.
- The Research Agent walks `related:` for depth-1 traversal. Missing related =
  isolated entries that never surface.
- Tag-based filtering (test-writer, audit) loads findings by `domain`. Missing
  domain = invisible to the loader.

Schema drift looks cosmetic but degrades search and discoverability silently.

## Entry types

Every entry has exactly one `type`. The type determines which type-specific
fields are required.

| `type:` value          | Purpose                                         | Template                              |
|------------------------|-------------------------------------------------|---------------------------------------|
| `research`             | Algorithm / pattern / system survey + tradeoffs | (this file — see "Research entry")    |
| `adversarial-finding`  | Bug pattern from audit / aTDD / defensive TDD   | `adversarial-finding-template.md`     |
| `feature-footprint`    | What a feature built + where it lives           | `feature-footprint-template.md`       |
| `reference-fragment`   | Schema/convention docs in `_refs/` only         | (this file is one)                    |
| `detail-companion`     | The `-detail.md` half of a split entry          | `detail-companion.md`                 |

**Default type when unset:** `research`. A writer that creates an entry without
a `type:` field is producing a research-style entry. (Writers SHOULD set it
explicitly. Readers MUST treat omission as `research`.)

## Required core fields (every type)

```yaml
---
title: "<Human-readable title>"           # MUST be present, in quotes
type: "<entry type>"                      # MUST be one of the values above
applies_to:                               # MUST be a list (may be empty for cross-cutting research)
  - "<file/module path or pattern>"
last_researched: "YYYY-MM-DD"             # MUST be ISO date, in quotes
research_status: "<status>"               # MUST be one of: active, stable, archived
---
```

### Field semantics

- `title` — exact, human-readable. Will be used as the subject row's display
  name in category indexes. Avoid filename-style kebab-case here.
- `type` — see entry-types table above. One value, never a list.
- `applies_to` — file/module patterns this entry is *about*. For research
  entries that survey a general algorithm, an empty list is acceptable. For
  adversarial findings and feature footprints, this MUST be non-empty.
- `last_researched` — date the entry's content was last verified against
  reality. Updated on every meaningful edit, not just creation. ISO format,
  always in quotes (`"2026-05-09"`, not bare `2026-05-09`).
- `research_status` — one of:
  - `active` — under ongoing investigation; expect changes within ~30 days.
  - `mature` — verified by production use or extensive audits; ~6-month review.
  - `stable` — verified, low expected churn; ~12-month review. Default for
    completed research.
  - `deprecated` — superseded by a newer entry; the body SHOULD point at the
    successor. Readers should prefer the successor.

## Optional core fields (every type)

```yaml
aliases: ["<other name>", "<another name>"]   # synonyms for grep / search
tags: ["<tag-1>", "<tag-2>"]                  # vocabulary below
topic: "<topic>"                               # informational; path is canonical
category: "<category>"                         # informational; path is canonical
related:                                       # other KB entries
  - "<topic>/<category>/<subject>.md"
decision_refs: []                              # ADR slugs (no .md extension)
spec_refs: []                                  # spec IDs from .spec/
sources:                                       # citations (see Source format)
  - url: "https://example.com/page"
    title: "<source title>"
    accessed: "YYYY-MM-DD"
    type: "<docs|paper|blog|repo|standard>"
confidence: "<low|medium|high>"                # earned, not asserted
```

`topic` and `category` are optional and informational. The file's path is
canonical — if the path says `data-structures/caching/`, the topic is
`data-structures` and category is `caching`. When these fields are present,
they MUST match the path. `/curate` flags mismatches as drift.

### Tag vocabulary

Tags are the primary cross-cutting query dimension. Use these conventions:

- **Domain tags**: `concurrency`, `validation`, `resource-management`,
  `serialization`, `caching`, `networking`, `consensus`, `replication`,
  `security`, `compression`, `encryption`, `partitioning`.
- **Concern tags**: `correctness`, `performance`, `memory-safety`,
  `data-integrity`, `availability`.
- **Discovery tags** (adversarial-finding only): `adversarial-finding`,
  `defensive-test-vector`, `audit-confirmed`.
- **Construct tags**: `builder`, `record`, `interface`, `closeable`,
  `iterator`, `cache`, `lock`.

Tags MUST be lowercase kebab-case. Do not invent new tag spellings for
existing concepts (e.g. don't introduce `concurrent` when `concurrency`
exists). When unsure, grep `kb/` for the existing spelling.

### Confidence

`confidence` is earned, not asserted by the author:

- `high` — verified across **2 or more independent sources** (research) OR
  **observed in 2 or more separate audits/features** (adversarial-finding).
- `medium` — single strong source / one audit confirmation.
- `low` — speculative; not yet validated against multiple data points.

Writers MUST NOT default to `high`. The audit pipeline and `/research` writer
SHOULD start at `medium` and require explicit corroboration evidence to upgrade
to `high`. `/curate` flags `confidence: high` entries with single-source or
single-audit provenance for downgrade.

### Source format

Cite each external source as a structured object. Bare URLs without `accessed:`
dates are rejected at write time — wiki-style sources rot, and an undated
citation cannot be re-verified.

```yaml
sources:
  - url: "https://github.com/owner/repo/wiki/Page"
    title: "Page Title"
    accessed: "2026-05-09"
    type: "docs"
  - url: "https://arxiv.org/abs/2404.12345"
    title: "Paper Title (Author et al., 2024)"
    accessed: "2026-05-09"
    type: "paper"
```

`type:` values: `docs`, `paper`, `blog`, `repo`, `standard`, `talk`.

## Type-specific required fields

### Research entry (`type: research`)

No additional required fields beyond core. Optional fields commonly used:

```yaml
complexity:
  time_build: "<big-O>"
  time_query: "<big-O>"
  space:      "<big-O>"
```

### Adversarial finding (`type: adversarial-finding`)

```yaml
domain: "<security|memory-safety|performance|concurrency|data-integrity|validation>"
severity: "<tendency|confirmed|critical>"
```

- `domain` is one value, used by the test-writer to load relevant findings.
- `severity`:
  - `tendency` — recurring anti-pattern, not always a bug.
  - `confirmed` — verified bug class, reproduced in code.
  - `critical` — security or data-integrity bug requiring immediate attention.

### Feature footprint (`type: feature-footprint`)

```yaml
domains: ["<domain-1>", "<domain-2>"]
constructs: ["<TypeName>", "<InterfaceName>"]
```

- `domains` (plural) — the domains this feature touched. Distinct from
  adversarial-finding's singular `domain`.
- `constructs` — key public types added or modified.

Feature footprints SHOULD live under `architecture/feature-footprints/` and
SHOULD use `research_status: stable` (footprints are historical records, not
research that goes stale on a fixed cadence).

### Detail companion (`type: detail-companion`)

A detail companion is the bottom half of a split entry. See
`detail-companion.md` for the full convention. Required core fields apply,
plus:

```yaml
companion_to: "<topic>/<category>/<subject>.md"   # MUST point at the parent
```

The companion's `title` SHOULD be the parent's title plus " — Detail".

## Filename rules

- Lowercase kebab-case: `byte-budget-cache-variable-size-entries.md`.
- ASCII only, no spaces, no underscores.
- A filename MUST be unique across the entire KB tree, not just within its
  category. If `partial-init-no-rollback.md` exists in `patterns/validation/`,
  do not also create `patterns/resource-management/partial-init-no-rollback.md`
  — disambiguate (e.g. `builder-pre-validation-mutation.md`,
  `multi-step-init-no-rollback.md`). Cross-folder collisions break grep and
  hide pattern-recurrence evidence under separate filenames.

`/curate` flags cross-folder filename collisions as drift candidates.

## What lives in `_refs/` only

`type: reference-fragment` is reserved for schema and convention docs that
ship with vallorcine and are referenced from elsewhere. Do not invent new
`reference-fragment` entries inside a project's KB; that namespace is for the
kit, not the project.

## Required body sections by type

These are listed for completeness; full templates are in the per-type files.

| Type                  | Required H2 sections (in order)                               |
|-----------------------|---------------------------------------------------------------|
| `research`            | `summary`, `how-it-works`, `tradeoffs`, `practical-usage`, `sources` |
| `adversarial-finding` | `What happens`, `Why implementations default to this`, `Test guidance`, `Found in` |
| `feature-footprint`   | `What it built`, `Key constructs`, `Adversarial findings`, `Cross-references` |
| `detail-companion`    | (free-form; this file does not gate body content)             |

Section names are case-sensitive and used by the audit and curate scanners.
Re-naming `## Sources` to `## References` will cause sources to drop out of
link-rot scans.

## Validating an entry

A writer skill validating an entry SHOULD:

1. Parse the YAML frontmatter. Reject if missing or malformed.
2. Confirm `type` is one of the known values; default to `research` if absent.
3. Confirm all core required fields are present and non-empty (except
   `applies_to` which may be empty for general research).
4. Confirm type-specific required fields are present.
5. Confirm `last_researched` matches `^\d{4}-\d{2}-\d{2}$`.
6. Confirm `research_status` is one of the three allowed values.
7. Confirm tags (if present) are all lowercase kebab-case.
8. Confirm sources (if present) all have `url`, `title`, and `accessed`.
9. Confirm filename does not collide with another KB entry under any topic.
10. Confirm `type: reference-fragment` only appears in `_refs/`.

`/curate` runs these same checks against existing entries and flags
deviations.

## Migration rules for legacy entries

Some KB instances have entries authored before this schema was canonical.
When a `/curate` schema-drift pass encounters legacy frontmatter:

- A bare-URL source becomes `{ url, title: "<derived from URL>", accessed: "<git-blame-date>", type: "<inferred>" }`.
- Missing `type:` on an entry under `architecture/feature-footprints/` becomes `type: feature-footprint`.
- Missing `type:` on an entry containing the section `## What happens` AND a `## Found in` becomes `type: adversarial-finding`.
- Missing `type:` otherwise becomes `type: research`.
- Missing `last_researched:` becomes the file's last git-commit date.
- Missing `research_status:` becomes `stable` for footprints, `active` for everything else.
- `research_status: archived` is renamed to `deprecated` (the canonical schema
  uses `deprecated` for "superseded by a newer entry").
- `confidence: high` without ≥2 corroborating sources/audits is downgraded to `medium` and flagged for human review.
- Frontmatter `topic:` / `category:` that disagree with the file's path are
  rewritten to match the path (path is canonical; the fields are
  informational mirrors).

Migration is opt-in per entry — `/curate` proposes patches and the user
accepts or declines each one. Bulk silent rewrites are not allowed.
