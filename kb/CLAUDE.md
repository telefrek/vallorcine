# Knowledge Base — Root Index

> **Managed by vallorcine agents. Use slash commands to modify this file.**
> To add a topic: `/kb topic "<name>" "<description>"`
> To add research: `/research "<subject>"`

> Pull model. Navigate: topic → category → subject file.
> Do not scan this directory recursively.
> Structure: `.kb/<topic>/<category>/<subject>.md`

## Topic Map

| Topic | Path | Categories | Files | Last Updated |
|-------|------|------------|-------|--------------|

## Recently Added (last 10)
| Date | Topic | Category | Subject |
|------|-------|----------|---------|

## Where does X go?

The KB has two cross-cutting categorization axes. Use these rules to decide:

- **Domain topics** describe a subject area: how something works, how it's
  built, what tradeoffs it exposes. Examples: `algorithms/`, `data-structures/`,
  `distributed-systems/`, `systems/`. Most `type: research` entries live here.

- **`patterns/`** describes lens-shaped findings: bug patterns, anti-patterns,
  fix patterns. Categories under `patterns/` are named for the **concern**
  (`validation/`, `concurrency/`, `resource-management/`), not for the domain
  the bug was discovered in. All `type: adversarial-finding` entries live
  under `patterns/`.

Decision rule: **What is the entry primarily teaching the reader?**
- "How algorithm X works" → domain topic.
- "Anti-pattern Y to avoid in code that does Z" → `patterns/<concern>/`.

A finding discovered while researching SQL parsing belongs at
`patterns/validation/<finding>.md`, not at `algorithms/sql-extensions/<finding>.md`.
The research entry that surveys SQL parsing can `related:` link to the finding.

## Filename uniqueness

Filenames MUST be unique across the entire `.kb/` tree, not just within their
category. Two entries in different folders with the same filename break grep
and hide cross-cutting evidence. If you need two related entries, disambiguate
by name (`builder-pre-validation-mutation.md` vs `multi-step-init-no-rollback.md`).

## Shared References

`_refs/frontmatter.md` — **canonical schema** for all entries; writers MUST validate against it
`_refs/adversarial-finding-template.md` — schema instance for `type: adversarial-finding` entries
`_refs/feature-footprint-template.md` — schema instance for `type: feature-footprint` entries
`_refs/detail-companion.md` — `<subject>-detail.md` split convention
`_refs/complexity-notation.md` — notation key used in algorithm files
`_refs/benchmarking-methodology.md` — how benchmark figures are cited

Older entries: [_archive.md](_archive.md)
