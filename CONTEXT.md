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

**Tmux dashboard and skills migration.** Built a two-pane tmux dashboard for
real-time pipeline visibility, then migrated all commands to Claude Code skills.

**What shipped this session:**
- Two-pane tmux dashboard: pipeline progress (top-right) + stage detail (bottom-right)
- `vallorcine_theme.sh`, `vallorcine_pipeline.sh`, `vallorcine_stage-detail.sh` watchers
- `dashboard-state.sh` helper library (12 functions for agents to write state)
- `dashboard-stop-hook.sh` Stop hook for live token counter mid-stage
- `/dashboard` command (launch/off/on) with once-per-session hint at pipeline start
- Dashboard calls integrated into all 7 pipeline commands
- Skills migration: 23 commands → `.claude/skills/<name>/SKILL.md` with YAML frontmatter
- All slash command names unchanged (`/feature`, `/research`, etc.)
- 43 tests passing (20 install + 23 dashboard)

**Where things stand:**
PR #11 open on `feat/tmux-dashboard-and-skills-migration` (2 commits). v0.3.4
is current release.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

- **Tmux dashboard: two panes, project-scoped state** (2026-03-17) — pipeline
  progress + stage detail panes. State in `.claude/dashboard/` (gitignored).
  Agents write state directly; Stop hook updates live token counter. Explicit
  `/dashboard` launch, prompted once per session at first pipeline command.

- **Dashboard toggle via `/dashboard off`** (2026-03-17) — `.nodashboard`
  sentinel in `.claude/dashboard/` (developer-local, gitignored). `/dashboard on`
  removes it.

- **Token display: hybrid actuals + live counter** (2026-03-17) — stage-boundary
  writes for per-stage actuals. Stop hook writes running total for active stage.
  Estimates only shown when Work Planner provides real data — never guessed.

- **Artifacts in stage detail, not just TDD** (2026-03-17) — `stage.json` has
  `tasks` (agent actions) and `artifacts` (construct lifecycle). Artifacts track
  status across all stages, not just testing.

- **Skills migration** (2026-03-17) — all 23 commands moved from
  `.claude/commands/*.md` to `.claude/skills/<name>/SKILL.md`. YAML frontmatter
  (description, argument-hint). Slash command names unchanged. Positions kit for
  Claude Code next-gen skill features.

- **Watcher files prefixed `vallorcine_`** (2026-03-17) — prevents namespace
  collisions if users have their own dashboard watchers for other tools.

- **Never guess estimates** (2026-03-17) — if we don't have real data, show
  "unknown" rather than made-up numbers. Applies to token budgets, progress bars,
  and all forward-looking displays.

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*

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
