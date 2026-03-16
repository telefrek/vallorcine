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

- **`/decisions backfill` — retroactive decision extraction.** Scans source
  structure to surface implicit architectural decisions that were never documented
  as ADRs. Designed 2026-03-16, revised 2026-03-16. Full spec below.

  **Command:** `/decisions backfill [<path>] [--limit N]`
  - With path: scan specified module/package, top 5 by signal strength
  - No path: allowed only if project is under `backfill_file_threshold` (default
    50 source files, configurable in project-config.md). Over threshold: require
    explicit path — display available top-level modules with file counts.
  - `--limit N`: adjust batch size (default 5)
  - Re-runnable: dismissed items recorded in `.decisions/.backfill-dismissed`,
    don't resurface.

  **Step 0 — Size check (zero token cost):**
  Read `project-config.md` for source directory and language. Run bash `find`
  to count source files by extension. Compare against `backfill_file_threshold`.

  If over threshold and no path provided:
  ```
  This project has ~320 source files. To keep scan costs predictable,
  specify a path to scope the backfill:

    /decisions backfill src/core
    /decisions backfill src/api

  Available top-level modules:
    src/core/      (42 files)
    src/api/       (38 files)
    src/auth/      (15 files)
    ...
  ```

  **Signal sources (ranked):**
  1. Archived feature domains marked `resolved` with no ADR (highest signal)
  2. Module/package boundaries — why does this exist as a separate unit?
  3. Interface hierarchies — sealed types, strategy patterns, extension points
  4. Encoding/serialization/storage choices — high cost to change
  5. Dependency graph edges — why A depends on B but not C

  **Filtered out (not surfaced):**
  - Framework/library choices (tooling, not architecture)
  - Naming, test structure, formatting (linter territory)
  - Anything with an existing ADR in `.decisions/`

  **Per-candidate actions:**
  - **decide** → invoke `/architect` inline for full deliberation
  - **draft** → user provides rationale in a few sentences, written as partial
    ADR marked `status: draft`. Domain Scout warns on draft ADRs but does not
    block — user's choice to proceed without formalizing.
  - **defer** → prompt for who should answer + optional context. Written as stub
    ADR marked `status: deferred`. Stays in `.decisions/`, local only (no
    external system integration yet).
  - **dismiss** → recorded in `.decisions/.backfill-dismissed` so it doesn't
    resurface on re-scan.

  **Key design decisions:**
  - Conventions are out of scope — linters own that. Only ADR-weight items.
  - Draft ADRs visible to Domain Scout as warnings, not blockers.
  - Deferred ADRs are local `.decisions/` stubs, not GitHub issues.
  - Path-scoped, not incremental — user controls scope per invocation.
  - File count threshold in project-config.md (default 50) gates full-project scan.

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
