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

*Last updated: 2026-03-14*

**Session goal:** Continue after session failure — commit accumulated bug fixes and improvements.

**Just completed:**
- Fixed 6 bugs: feature-resume auto-start, autonomous mode opt-in timing, crash recovery
  auto-resume, broken "hit enter" prompts, PR creation automation, feature branch in init
- 3 improvements: handoff points offer to auto-continue, DEFERRED.md for local dev,
  MANIFEST + stale-file removal in install/upgrade
- Fail-forward upgrade policy documented (went straight to SETTLED.md)
- Switched to branch-based PR workflow now that v0.1.2 is a live release
- Opened PR #1: wip/session-bugs-and-improvements → main

**Where things stand:**
PR #1 is open. All session work is on the branch. Next: review and merge PR #1,
then continue feature work via branches. /decisions command is the highest-priority
open item.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

### 2026-03-13 — CONTEXT.md three-file split

Problem: CONTEXT.md grows unbounded — settled design history and competitive
landscape notes cost tokens every session despite being rarely needed.
Decision: split into three files with distinct domains and cadences:
- **CONTEXT.md** — active working state (~150-200 lines, read every session)
- **SETTLED.md** — graduated design decisions (pull-model, grows freely)
- **COMPETITIVE.md** — market positioning (pull-model, updated during research)
`/save-work` graduates aged Recent decisions to SETTLED.md. CONTEXT.md carries
one-line pointers to both reference files.
Rejected: two-file split with competitive in settled (different domain and
update cadence); per-session files (too many files, harder to load).

### 2026-03-13 — Escalation flags and re-entry logic

Full Code Writer → Test Writer → Work Planner escalation chain. Code Writer
detects contract conflict, logs `code-escalation`, directs to `/feature-test
--escalation`. Test Writer diagnoses: fixes the test (cases 1-2) or escalates
to Work Planner via `test-to-planner-escalation` (case 3). Work Planner reads
escalation, revises contract + stub in Contract Revision section, logs
`contract-revised`.

Both handoff points have 3-strike limits — after 3 escalations on the same
contract/test, hard stop with manual resolution guidance. Prevents infinite loops.

Re-entry: feature-implement.md checks `escalation-resolved` substage to resume
after Test Writer fixes. feature-test.md checks `contract-revised` substage to
re-verify tests after Work Planner revises.

### 2026-03-13 — WIP.md crash-recovery checkpoint

Problem: vallorcine uses status.md + cycle-log.md for projects that use it, but
vallorcine's own development had no crash-recovery mechanism.
Decision: WIP.md in repo root (gitignored) — mutable checkpoint with current
task, files being modified, done/remaining. /ideate reads it on session start,
/save-work deletes it on close. Lightweight: updated at milestones, not every edit.
Rejected: memory system (tied to working tree state, not cross-project knowledge);
full status.md model (overkill for meta-development).

### 2026-03-13 — cycle-log.md tail-read rule

Problem: cycle-log.md is append-only with no cap; long-running features pay full
token cost on every agent read.
Decision: tail-read rule in tdd-protocol.md (always loaded) — agents read only
last 30 lines by default. Full reads reserved for PR draft and feature-complete.
Rejected: file splitting with archival threshold (adds maintenance machinery);
per-cycle sections with lazy loading (requires reformatting).

### 2026-03-13 — Autonomous TDD loop mode

Added opt-in automation that chains implement → refactor → next unit tests
without stopping. User chooses mode once at first `/feature-implement` run;
choice persists in status.md for the feature lifetime.

Two deliberate non-automations: (1) missing tests escalation (2e) always pauses
both modes — it's a quality gate, not friction. (2) structural issues in 2c/2d
also always pause — interface changes affect other units and need human judgement.

### 2026-03-13 — Plugin system support

Decision: add plugin manifest alongside shell installer, not replace it.
Two reasons: (1) plugin path is lower friction for new users; (2) shell path
enables /upgrade-vallorcine with version stamps and user-file preservation.
Neither path is strictly better — they complement each other.

### 2026-03-13 — GitHub repo structure and versioning

Standard repo layout with README, CHANGELOG, .gitignore, VERSION (semver).
install.sh reads VERSION, writes stamp to target project, warns on mismatch.
--dev flag for local testing. Branch convention: wip/<topic>.

### 2026-03-14 — Branch-based PR workflow

Now that v0.1.2 is a live release, all development happens on wip/<topic> branches
and merges via PR. Direct commits to main are reserved for session context files
(CONTEXT.md, WIP.md) and emergency patches only.

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed*

- **/decisions command** — list/filter existing ADRs. Suggested early, never
  built. Useful once a project accumulates many decisions. Confirmed gap vs
  competitors. **Ranked: high priority.**

- **KB coding agent** — third KB role that reads entries and implements against
  them. Would close the loop between research and implementation.

- **Work unit split thresholds** — 15K crossover and 3.5K per-construct are
  reasoned estimates, not measured. Real-world use will reveal if adjustment needed.

- **CONTEXT.md maintenance discipline** — `/save-work` now handles graduation
  and doc sync, but still depends on remembering to run it.
  Could /feature-complete prompt for `/save-work` automatically?

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
