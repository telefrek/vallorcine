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

**TodoWrite progress tracking and upgrade safety.** Added two-tier TodoWrite
progress checklists across all TDD pipeline commands, plus crash recovery for
`/ideate` and a safety guard for the upgrade stale file removal.

**What shipped this session:**
- TodoWrite progress tracking in 7 pipeline commands (plan, domains, coordinate,
  test, implement, refactor, resume) — pipeline-level + stage-level granularity
  with `activeForm` for real-time detail
- Parallel mode: coordinator owns TodoWrite exclusively, polls per-unit status.md
  to update activeForm on each work unit. Subagents skip TodoWrite.
- `/ideate` Step 1.5: writes WIP.md immediately so crash recovery works
- `upgrade.sh` safety guard: prefix allowlist prevents corrupted manifest from
  deleting user files or project source code
- `install.sh` fix: adr-validate.sh was in MANIFEST but not installed
- Regression test (test 9): 5 assertions covering user file preservation

**Where things stand:**
All work committed on main (2 commits, not yet pushed). v0.3.3 is current
release. WIP.md cleared.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

- **TodoWrite two-tier progress tracking** (2026-03-17) — pipeline-level checklist
  (scoping → PR) in every command, plus stage-level granularity (per-test,
  per-construct, per-domain, per-refactor-check). Uses `activeForm` for real-time
  detail. Coordinator owns TodoWrite in parallel mode; subagents skip it.

- **/ideate writes WIP.md immediately** (2026-03-17) — Step 1.5 added: after
  determining session goal, write WIP.md before reading context. Prevents losing
  session state on crash. Appends if WIP.md already has in-flight work.

- **Upgrade safety guard: prefix allowlist** (2026-03-17) — stale file removal
  only operates on known kit-managed prefixes (.claude/commands/, agents/, rules/,
  scripts/, upgrade.sh). Non-kit paths in a corrupted manifest are skipped with a
  warning. Regression test added.

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*

### Do soon (medium effort, clear designs)

- **Work unit split thresholds** — 15K crossover and 3.5K per-construct are
  reasoned estimates, not measured. Token tracking is collecting actuals — needs
  data review once enough features have run with tracking enabled.

- ~~feature-resume PR auto-invoke~~ — **done** (2026-03-17). Fixed routing
  table (refactor/complete → PR, not complete), added yes/stop prompts for
  PR drafting and retrospective. Also added retro prompt to /feature-pr itself.

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
