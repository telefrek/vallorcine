---
type: reference-fragment
title: Adversarial Finding Entry Template
---

# Adversarial Finding Entry Template

KB entries with `type: adversarial-finding` capture bug patterns and tendencies
discovered through adversarial testing (aTDD rounds, audit passes, or enhanced
TDD defensive vectors). They persist across features and inform future test
writing and implementation.

> **Authoritative schema:** `_refs/frontmatter.md`. This template instantiates
> the schema for adversarial findings; it does not extend or override it. If
> the two diverge, frontmatter.md wins.

## Frontmatter

```yaml
---
title: "<Pattern name>"
type: adversarial-finding
domain: "<security|memory-safety|performance|concurrency|data-integrity|validation>"
severity: "<tendency|confirmed|critical>"
applies_to:
  - "<file path pattern or module name>"
last_researched: "YYYY-MM-DD"
research_status: "active"

# Optional but strongly recommended for searchability:
aliases: []
tags: ["adversarial-finding", "<domain>", "<concern>"]
related: []
decision_refs: []
sources: []
confidence: "<low|medium|high>"
---
```

### Field-specific guidance for adversarial findings

- `tags` SHOULD always include `adversarial-finding` plus the `domain` value
  plus any concern tags that apply (e.g. `correctness`, `data-integrity`).
  This makes the finding discoverable via `kb-search.sh` and tag-overlap
  cross-reference repair.
- `severity`:
  - `tendency` — recurring anti-pattern, not always a bug.
  - `confirmed` — verified bug class, reproduced in code.
  - `critical` — security or data-integrity bug requiring immediate attention.
- `confidence`:
  - `medium` — single audit confirmation. **This is the writer's default.**
  - `high` — observed in 2+ separate audits/features. Earned, not asserted.
- `applies_to` MUST be non-empty. An adversarial finding with no scope is not
  actionable for the test writer that consumes it.
- `decision_refs` — ADR slugs from `.decisions/` that this finding is
  relevant to (no `.md` extension, no full path).

For full field semantics see `frontmatter.md`.

## Required sections

```markdown
# <Pattern name>

## What happens
<!-- 2-3 sentences: the bug pattern and when it manifests -->

## Why implementations default to this
<!-- Root cause: spec gap, performance shortcut, language default -->

## Test guidance
<!-- Specific test vectors the test-writer should add when working in this domain.
     Include the exact assertion shape (exception type, message contents). -->

## Found in
<!-- Features where this was discovered, with round/date.
     Each entry counts as evidence for confidence upgrade. -->
- <feature-slug> (round N, YYYY-MM-DD): <one-line description>
```

Section names are case-sensitive — the audit and curate scanners look for
exact matches.

## How it's used

- **Test writer** reads findings matching the current feature's `domain` and
  `applies_to` patterns during defensive vector generation.
- **Spec analyst** reads findings during aTDD round analysis to avoid
  re-discovering known patterns.
- **Domain scout** surfaces findings during `/feature-domains` when a domain
  has adversarial coverage.
- **`/curate`** flags entries with `confidence: high` but only one entry in
  `## Found in` for confidence downgrade.

## Where adversarial findings should live

Adversarial findings SHOULD be filed under `patterns/<domain>/`, not under a
research-style topic such as `algorithms/<area>/`. The category split is
**by lens** (validation, concurrency, resource-management) so the test-writer
loading findings for a given concern finds them in one place.

A finding discovered while researching SQL parsing belongs at
`patterns/validation/<finding-name>.md`, with a `related:` link from the
`algorithms/sql-extensions/<feature>.md` research entry. Putting it in
`algorithms/sql-extensions/` puts it where readers don't search for it.
