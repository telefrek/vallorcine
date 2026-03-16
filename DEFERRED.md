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

- **Hooks for non-TDD tooling** — linting on write, security scanning, formatting.
  Future: `hooks/` directory with opt-in configs via project-config.md.

- **LSP integration** — document in README which LSP plugins pair well with
  vallorcine's Code Writer stage as a recommended companion.

- **Context7 / live docs in Domain Scout** — pull current framework docs via
  Context7 MCP. Opt-in via project-config.md flag.

- ~~/decisions list~~ — **done** (v0.2.4). Browse and filter by status/keyword.

- ~~Project-level CONTEXT.md~~ — **done** (v0.2.4). `PROJECT-CONTEXT.md` with `/project-context` command.
  90-day expiry, scoped entries, size cap, agent integration at scoping/domains/planning.

- ~~Diff-based install~~ — **done** (v0.2.4). `install.sh --diff` shows changes without writing.

- **Coverage gating in refactor** — flag coverage drops below configured minimum.

- **/feature-split** — split in-progress feature into two when scope expands.

- **KB coding agent** — third KB role that reads entries and implements against
  them. Would close the loop between research and implementation.

- ~~Auto-capture of accidental decisions~~ — **done** (v0.2.4). PostSessionEnd hook +
  `/decisions candidates` review command. Surfaces at `/feature-domains` and `/feature-resume`.

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

- ~~Feature retrospectives~~ — **done** (v0.2.4). `/feature-retro` reviews scope, assumptions, domains, tokens, TDD efficiency.

- ~~Dependency-aware work splitting~~ — **done** (v0.2.4). Topology view with dependency layers in `/feature-resume`.

- ~~/decisions explain~~ — **done** (v0.2.4). Plain-language ADR summary with KB context.

- ~~/feature-cleanup~~ — **done** (v0.2.4). Interactive walkthrough of stale feature dirs.

- **HANDOFF.md for cross-developer session handoff** — `/save-work` writes a
  structured summary of decisions made, approaches tried, and open questions.
  Useful for team handoffs and solo resume after long gaps. Documentation/convention
  for now — can't be enforced by tooling.

- **ADR contradiction CI check** — scan `.decisions/CLAUDE.md` for duplicate
  question slugs with `accepted` status. Requires CI integration (GitHub Actions
  or pre-push hook). See "Known team issues" in DESIGN.md for details.

- **`/decisions backfill` — retroactive decision extraction.** Scans archived
  features and source structure to surface implicit architectural decisions that
  were never documented as ADRs. Designed 2026-03-16. Full spec below.

  **Command:** `/decisions backfill [<path>] [--limit N]`
  - No args: scan archived features + source structure, top 5 by signal strength
  - With path: scope to module/package, top 5
  - `--limit N`: adjust batch size (default 5)
  - Re-runnable: dismissed items recorded, don't resurface. Shows deferred items
    after new candidates (deferred may now be answerable).

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
  - Incremental by design — 5 at a time, not an exhaustive dump.
