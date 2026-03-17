# vallorcine — Session Context

Handoff document for continuing work across fresh conversations.
Read DESIGN.md first for system architecture. This file covers the *active*
state of the project — what's happening now and what's next.

**Related files (pull-model — read only when needed):**
- `SETTLED.md` — stable design history, graduated decisions
- `COMPETITIVE.md` — market positioning and ecosystem gaps
- `DEFERRED.md` — good-but-not-now ideas; promote to Open questions when ready

**Section update cadences:**
- `Current focus` — replaced every session
- `Recent decisions` — rolling window, ~last 3 sessions; oldest graduate to SETTLED.md
- `Open questions` — live list; items resolve into SETTLED.md or get dropped
- `Deferred ideas` — pointer only; content lives in DEFERRED.md
- `Working preferences` — stable, shapes how we work together

---

## Current focus

*Last updated: 2026-03-17*

**Repo cleanup, uninstall command, and migration fix.**

**What shipped this session:**
- Deleted `commands/` directory — 23 stale pre-migration files removed from repo
- `/uninstall-vallorcine` command + `scripts/uninstall.sh` — clean removal preserving
  user data (`.kb/`, `.decisions/`, `.feature/`, user commands, `PROJECT-CONTEXT.md`)
- Migration cleanup in `install.sh` — auto-removes `.claude/commands/<name>.md` when
  matching skill exists, fixing duplicate slash commands for pre-0.4.0 upgraders
- Fixed `/dashboard` duplicate entry (heading suffix parsed as second description)
- 36 install tests + 23 dashboard tests passing
- Tested end-to-end: install → uninstall → fresh install on jlsm project

**Where things stand:**
PR #13 open on main. Uninstall tested on real project (jlsm). Dashboard panes work
but have two UX issues to address: panes consume too much main terminal space, and
watchers flicker during refresh. Next: dashboard layout improvements.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

- **Uninstall command** (2026-03-17) — `scripts/uninstall.sh` + `/uninstall-vallorcine`
  skill. Manifest-based removal with safety guard, `--dry-run` preview, settings/git
  cleanup, self-delete. Preserves `.kb/`, `.decisions/`, `.feature/`, user commands.

- **commands/ → skills/ migration cleanup** (2026-03-17) — `install.sh` now
  auto-removes stale `.claude/commands/<name>.md` files when a matching skill exists.
  Fixes duplicate slash command entries for users upgrading from pre-0.4.0.

- **commands/ directory deleted from repo** (2026-03-17) — 23 files removed, all
  duplicated in `skills/*/SKILL.md`. `.gitignore` updated to drop `!.claude/commands/`.
  Stale prefix in upgrade.sh kept for one more release cycle.

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*

### Do next (high priority, clear direction)

- **Dashboard: intent over mechanics** — the main terminal shows raw tool calls
  (Read, Edit, Bash) but users care about *what Claude is doing and why*, not
  which tools it called. Three complementary approaches identified:
  1. **Status line context** — update Claude Code's status line with a short
     intent string ("reading KB entry on HNSW", "evaluating candidate 2/3")
  2. **Turn summaries in stage detail pane** — rolling "last 3 actions" feed
     showing semantic descriptions, not tool names
  3. **Intent-first stage.json writes** — agents write intent to `stage.json`
     before each logical block of work, not just task completion status

  The common thread: surface **intent**, not **mechanics**. Works across all
  commands (feature pipeline, research, architect) since the problem is universal.
  Dashboard is a feature pipeline tool for progress tracking, but intent surfacing
  benefits every command.

- **Version display** — need a way to confirm installed version. Could be in
  `/vallorcine-help` header or a dedicated `/vallorcine:version` skill.

- **Plugin install path documentation** — document `vallorcine:`-prefixed
  commands from plugin install vs unprefixed from shell install. Both work,
  need to explain the difference in README.

### Do soon (medium effort, clear designs)

- **Work unit split thresholds** — 15K crossover and 3.5K per-construct are
  reasoned estimates, not measured. Token tracking is collecting actuals — needs
  data review once enough features have run with tracking enabled.

### Do when needed (useful but workarounds exist)

- **/feature-split** — split in-progress feature when scope expands. Workaround:
  finish current feature, start a new one.

- **HANDOFF.md convention** — `/save-work` mostly covers this. May just need
  documentation rather than new code.

- **KB coding agent** — third KB role that reads entries and implements against
  them. Current workflow (read KB manually) works.

### Do when scale demands it (team/scale features)

- **KB `depends-on` field** — frontmatter field for structural staleness. P2/P3
  tension with fan-out reads on dependency chains. Date-based staleness sufficient
  for current scale.

- **Team KB commands** — `/kb sync`, `/kb consolidate`, `/kb status`. Useful for
  teams but vallorcine is primarily single-developer today.

- **LSP integration** — README documentation of companion plugins. Nice-to-have.

- **Pipeline observability** — velocity metrics, KB utilization tracking.
  Premature until more projects use vallorcine.

- **KB cross-referencing** — reverse mapping (decisions → KB). One-way exists.
  Low urgency until KB is large enough to need it.

---

## Deferred ideas

*Kept in `DEFERRED.md` — pull-model, not loaded every session.*
*Read it when looking for future work to promote to Open questions.*

---

## Working preferences

*Stable — shapes how we work together*

**Conversational, not form-like.** Agents feel like a systematic colleague.
Prompts, questions, output read naturally.

**Explain the why, not just the what.** One sentence of context with every
question or decision.

**Agents are routers and specialists, not autonomy machines.** User stays in
the loop at every meaningful boundary. No silent chaining. No surprises.

**Token awareness is a first-class concern.** Quantitative where possible.
Not vibes-based.

**No ceremony without value.** Resist adding steps that always run regardless
of need. 0-signal complexity check is silent. 0-question scoping is valid.

**Prefer one clean interface over two adequate ones.** When choices came down
to two approaches, we consistently chose simpler to use even if harder to
implement: enter-to-proceed, sequential questions, pull model.
