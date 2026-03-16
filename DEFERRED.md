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

- **/decisions list** — browse and filter existing ADRs by status, date, or
  keyword. See open questions in CONTEXT.md for priority rationale.

- **Project-level CONTEXT.md** — rolling-context pattern for projects *using*
  the kit. Different from ADRs — "things we've learned about this codebase."

- **Diff-based install** — diff mode showing what changed between installed
  and package version.

- **Coverage gating in refactor** — flag coverage drops below configured minimum.

- **/feature-split** — split in-progress feature into two when scope expands.

- **KB coding agent** — third KB role that reads entries and implements against
  them. Would close the loop between research and implementation.

- **Auto-capture of accidental decisions** — PostSessionEnd hook scans transcript
  for decision-shaped language, prompts user to save as ADR. Preserves
  intentionality while expanding capture surface.

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

- **Feature retrospectives** — optional `/feature-retro` after `/feature-pr`.
  Reviews divergence from scope, invalidated ADRs, missed domain analysis gaps.
  Writes back to `.decisions/` and `.kb/`.

- **Dependency-aware work splitting** — `depends-on` field per work unit in
  `/feature-plan`. Enables topology-aware status view in `/feature-resume
  --status`.

- **/decisions explain** — `/decisions explain <slug>` generates plain-language
  summary of an ADR with its supporting KB entries. Useful for PR descriptions
  and onboarding.

- **/feature-cleanup** — interactive walkthrough of existing `.feature/<slug>/`
  directories. For each: show last activity date and stage, ask user to keep,
  archive (move to `_archive/`), or delete. Addresses abandoned feature directory
  clutter for long-running projects.

- **HANDOFF.md for cross-developer session handoff** — `/save-work` writes a
  structured summary of decisions made, approaches tried, and open questions.
  Useful for team handoffs and solo resume after long gaps. Documentation/convention
  for now — can't be enforced by tooling.

- **ADR contradiction CI check** — scan `.decisions/CLAUDE.md` for duplicate
  question slugs with `accepted` status. Requires CI integration (GitHub Actions
  or pre-push hook). See "Known team issues" in DESIGN.md for details.
