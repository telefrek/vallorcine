# vallorcine — Deferred Ideas

Good thoughts not being worked on now. Captured here to avoid losing them,
but not blocking current work. Not settled — these may be revisited, dropped,
or promoted to open questions at any time.

**Updated by:** `/save-work` — appends new deferrals, never auto-removes them.
**Read by:** `/ideate` on request only — pull-model, not loaded every session.
**Review cadence:** Check periodically; promote items to Open questions in
CONTEXT.md when you're ready to act on them, or drop them if no longer relevant.

---

## Active deferrals

- **LSP integration** — document in README which LSP plugins pair well with
  vallorcine's Code Writer stage as a recommended companion. No bundled dependency.

- **/feature-split** — split in-progress feature into two when scope expands.

- **KB coding agent** — third KB role that reads entries and implements against
  them. Would close the loop between research and implementation.

- **KB staleness: `depends-on` field** — frontmatter `depends-on` field in
  subject files for cross-entry dependency tracking. Staleness detection by
  date is now built into `/kb` query (checks `last_researched` and `Last Updated`
  against configurable threshold in project-config). The `depends-on` field
  would add structural staleness: "entry X changed, so entry Y needs review."

- **Team KB commands** — `/kb sync` (post-merge integrity check), `/kb
  consolidate` (merge overlapping entries), `/kb status` (human-readable
  summary), `/decisions review` (review contested ADRs). The git merge driver
  for concurrent index writes is already built — these commands would extend
  the team support further.

- **HANDOFF.md for cross-developer session handoff** — `/save-work` writes a
  structured summary of decisions made, approaches tried, and open questions.
  Useful for team handoffs and solo resume after long gaps. Documentation/convention
  for now — can't be enforced by tooling.

- **ADR contradiction check** — scan `.decisions/CLAUDE.md` for duplicate
  question slugs with `accepted` status. Originally spec'd as CI/GitHub Actions.
  Redesigned (2026-03-16): bash script (`scripts/adr-validate.sh`) to stay within
  principle 1. Can run as pre-flight check alongside version-check.sh.

- **Pipeline observability** — velocity metrics (time/tokens per stage across
  features), KB utilization (which entries get read), pipeline trends. Token
  tracking exists but is narrow. Premature until more projects use vallorcine.

- **KB cross-referencing** — reverse mapping from decisions to KB entries. One-way
  (KB → decisions) exists in `/kb query`. Low urgency until KB is large enough.

- ~~`/decisions backfill`~~ — **subsumed by `/curate`** (2026-03-18). Curation's
  analysis 8 (backfill candidates) + analysis 3b-3d (ADR pressure/gravity/hubs)
  cover all five signal sources. Archived feature domains (source 1) are scanned
  directly. Module boundaries, interface hierarchies, encoding choices, and
  dependency edges (sources 2-5) are detected via ADR gravity — files that
  co-change with ADR-constrained files but aren't in the ADR's scope. High
  gravity signals isolation problems that route to `/architect`.

---

## Dropped

- ~~Hooks for non-TDD tooling~~ — **dropped** (2026-03-16). Requires Claude Code
  hooks infrastructure — violates principle 1 (bash and markdown only).
- ~~Context7 / live docs in Domain Scout~~ — **dropped** (2026-03-16). Requires
  MCP server — violates principle 1 (bash and markdown only).
- ~~Coverage gating in refactor~~ — **dropped** (2026-03-16). Requires
  language-specific coverage tools — violates principle 1. Step 2e (missing test
  detection) is the language-agnostic proxy.

## Done

- ~~/decisions list~~ — **done** (v0.2.4)
- ~~Project-level CONTEXT.md~~ — **done** (v0.2.4)
- ~~Diff-based install~~ — **done** (v0.2.4)
- ~~Auto-capture of accidental decisions~~ — **done** (v0.2.4)
- ~~Feature retrospectives~~ — **done** (v0.2.4)
- ~~Dependency-aware work splitting~~ — **done** (v0.2.4)
- ~~/decisions explain~~ — **done** (v0.2.4)
- ~~/feature-cleanup~~ — **done** (v0.2.4)
