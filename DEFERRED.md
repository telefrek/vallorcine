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
