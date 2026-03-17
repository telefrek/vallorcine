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

**Dashboard redesign — retired tmux, added status line + hook-based token tracking.**

**What shipped this session:**
- **Tmux dashboard retired** — deleted skill, 2 scripts, 3 watchers, 14 tests.
  Removed all dashboard bash blocks from 9 skill files. Documented as "tried and
  retired" in SETTLED.md with clear rationale.
- **Hook-based token tracking** — `scripts/token-stop-hook.sh` auto-detects stage
  transitions by comparing `.token-state` against `status.md`. Logs to `token-log.md`
  automatically. Removed 16 `token_checkpoint`/`token_summary` bash blocks from skills.
- **Status line** — `scripts/statusline.sh` shows feature slug, pipeline stage,
  total tokens, and context window % with color-coded warnings. Registered via
  `settings.json` statusLine config. Works without tmux.
- **Domain scout KB empty check** — when KB has zero topics, offers research/continue/
  skip-research before per-domain analysis. `skip_all_research` flag carries forward.
- **Version display** — `/vallorcine-help` headers now show installed version.
- **33 install tests passing** (removed 3 dashboard-specific tests, all others green).
- Tested end-to-end: fresh install on jlsm with status line + token hook working.

**Where things stand:**
PR #13 still open (previous session's work). This session's changes are on
`feat/cleanup-uninstall` branch. Status line confirmed working on jlsm — shows
`slug · stage · tokens · ctx %`. Next: plugin install path docs, then release.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

- **Tmux dashboard retired** (2026-03-17) — tmux panes fought the medium: bash
  side-effect calls were unreliable (sub-agents skip them), panes consumed screen
  space, and the whole approach required tmux. Replaced with native Claude Code
  primitives (status line + hooks) that work everywhere.

- **Hook-based token tracking** (2026-03-17) — Stop hook detects stage transitions
  by comparing cached stage vs `status.md`. No skill-level bash calls needed.
  Three paths: no-op (~1ms), active same stage (~5ms), transition (~200ms).

- **Status line for pipeline visibility** (2026-03-17) — shows slug · stage ·
  tokens · context %. Reads `.token-state` + session JSON. Fires after each
  response automatically. No cost display (subscription model makes it misleading).

- **Domain scout KB empty check** (2026-03-17) — offers research/continue/skip
  when KB has zero topics. `skip_all_research` flag prevents repeated per-domain
  prompts when user wants to rely on local domain knowledge.

- **Version in /vallorcine-help headers** (2026-03-17) — reads
  `.claude/.vallorcine-version`. Shows `🚀 HELP · vallorcine v0.4.0`.

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*

### Do next (high priority, clear direction)

- (none — current items resolved, promote from lower tiers or DEFERRED.md)

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
