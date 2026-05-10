---
type: reference-fragment
title: Feature Footprint Entry Template
---

# Feature Footprint Entry Template

KB entries with `type: feature-footprint` are condensed records of what a
feature built, what domains it touched, and what was learned. Generated during
`/feature-retro`, they provide cross-reference context for future features
working in the same areas.

> **Authoritative schema:** `_refs/frontmatter.md`. This template instantiates
> the schema for feature footprints; it does not extend or override it. If the
> two diverge, frontmatter.md wins.

## Frontmatter

```yaml
---
title: "<feature-slug>"
type: feature-footprint
domains: ["<domain-1>", "<domain-2>"]
constructs: ["<TypeName>", "<InterfaceName>"]
applies_to:
  - "<file path pattern>"
last_researched: "YYYY-MM-DD"
research_status: "stable"

# Optional but recommended:
related: []
decision_refs: []
spec_refs: []
tags: []
---
```

### Field-specific guidance for feature footprints

- `domains` (plural, list) — the domains this feature touched. Distinct from
  adversarial-finding's singular `domain`. Use the same vocabulary as the
  domain tags in `frontmatter.md`.
- `constructs` — key public types added or modified. These are the names a
  future reader is most likely to grep for. Class names, interface names,
  not method names.
- `applies_to` — file patterns this feature owns. MUST be non-empty.
- `decision_refs` — ADR slugs from `.decisions/` that governed this feature.
- `spec_refs` — spec IDs from `.spec/` that this feature implements.
- `research_status: stable` — footprints don't go stale in the same way as
  research; they're historical records. The default and expected value is
  `stable`. Only mark `archived` if the feature was wholly removed.

For full field semantics see `frontmatter.md`.

## Where feature footprints should live

Feature footprints live under `architecture/feature-footprints/` and follow
the naming pattern `<feature-slug>.md` (or `<feature-slug>--wd-<NN>.md` for
work-decomposed features). Avoid placing them anywhere else — they are
historical artifacts, not research, and `/curate` distinguishes them by path.

## Required sections

```markdown
# <feature-slug>

## What it built
<!-- 2-3 sentences: what capability was added -->

## Key constructs
<!-- List of new/modified types with one-line descriptions -->
- `ConstructName` — <what it does>

## Adversarial findings
<!-- Patterns discovered during aTDD or audit; cross-ref to adversarial-finding KB entries -->
- <finding-name>: <one-line summary> → [KB entry](<path>)

## Cross-references
<!-- Links to ADRs, other KB entries, related features -->
- ADR: .decisions/<slug>/adr.md
- Related features: <feature-slugs that depend on or extend this>
```

## How it's used

- **Domain scout** reads footprints during `/feature-domains` to understand
  what prior work exists in a domain.
- **`/curate`** cross-references footprints with git history to detect
  drift, stale dependencies, and orphaned code.
- **Test writer** uses the adversarial findings section to find relevant
  patterns when writing tests for constructs in the same domain.
- **`/work-decompose`** uses `constructs` and `applies_to` to find
  dependencies between work units.
