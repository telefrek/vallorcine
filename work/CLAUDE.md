# Work Definitions — Root Index

> **Managed by vallorcine agents. Use slash commands to modify this file.**
> To create a work group: `/work "<goal>"`
> To decompose: `/work-decompose "<slug>"`
> To check readiness: `/work-status "<slug>"`
> To start implementation: `/work-start "<slug>" [WD-nn | next]`

> Pull model. Load on demand only.
> Do not scan this directory recursively.
> Structure: .work/<group-slug>/WD-<nn>.md

## Active Work Groups

| Group | Path | Goal | WDs | Ready | Complete | Last Updated |
|-------|------|------|-----|-------|----------|--------------|

## Recently Added (last 10)

| Date | Group | WD | Title | Status |
|------|-------|----|-------|--------|

## Work Definition Format Reference

Work definitions use YAML front matter (between `---` delimiters) and
markdown narrative sections.

```yaml
---
id: WD-01
title: Short descriptive title
group: group-slug
status: DRAFT | SPECIFIED | READY | IN_PROGRESS | COMPLETE | BLOCKED
domains: [domain1, domain2]
artifact_deps:
  - { type: spec, path: "domain/spec-name", required_state: APPROVED }
  - { type: adr, slug: "decision-slug", required_status: accepted }
  - { type: spec, path: "domain/interface-name", kind: interface-contract, required_state: APPROVED }
produces:
  - { type: spec, path: "domain/spec-name" }
  - { type: spec, path: "domain/interface-name", kind: interface-contract }
---

## Summary
What this work definition accomplishes.

## Acceptance Criteria
Observable outcomes that confirm the work is complete.

## Implementation Notes
Constraints, dependencies, or considerations for implementation.
```

**Status lifecycle:** DRAFT → SPECIFIED → READY → IN_PROGRESS → COMPLETE
BLOCKED is set mechanically when artifact dependencies are unsatisfied.

**Artifact dependency types:**
- `spec` — a specification in `.spec/domains/`; checked via manifest.json
- `adr` — an architecture decision in `.decisions/`; checked via front matter
- `kb` — a knowledge base entry in `.kb/`; checked by file existence

**Interface contracts** are specs with `kind: interface-contract` — shared
surfaces between work definitions. Same tooling as regular specs.

**Scope signal:** Work definitions with >5 artifact dependencies may benefit
from further decomposition.

Older entries: [_archive.md](_archive.md)
