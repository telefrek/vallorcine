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

*Last updated: 2026-04-12*

**Work layer shipped. Distributed collaboration designed. Next: validation.**

**What happened (2026-04-11/12):**

- **Work layer (`.work/`)** — fourth knowledge layer. All 6 phases implemented:
  data model, creation flow, context injection, pipeline bridge, curation, pipeline
  decomposition. 12 commits, 50 files, ~5.6K lines. PR #36 open for merge.

- **Distributed collaboration design** — explored multi-party work plan merging
  (multiple people running `/work-decompose` on different branches). Key design:
  slug-based WD IDs (no sequential collisions), regenerable indexes (manifest.md
  derived from WD files), additive decomposition, overlap detection at authoring
  time, post-merge validation for the parallel-branch case. Captured in DEFERRED.md
  for implementation when team workflows are needed.

- **Bug fixes** — 3 `grep -c` pipefail bugs in curate-scan.sh, 35 AskUserQuestion
  prompt migrations, stale .bak removal.

- **Tests** — 7 new test suites (68 tests), 137 total across all suites. Zero
  regressions.

**Where things stand:**
PR #36 open on `feat/work-layer-foundation`. Next: merge PR, then real-world
validation on a multi-feature workflow. Remaining Open Questions: Phase 0
validation, concurrency lens, audit budget controls.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

*5 work layer decisions graduated to SETTLED.md (2026-04-12): artifact-based
dependencies, interface contracts as spec subtype, computed readiness, pipeline
mode decomposition, work context as pull-model injection.*

*9 decisions graduated to SETTLED.md (2026-04-12): effort asymmetry removal,
concurrency lens filtering, spec conflict detection, DRAFT specs blocked,
spec extraction from implementation, [ABSENT] lifecycle, fix-spec resolution,
architect adversarial hardening, Phase 0 already-fixed check.*

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*
*Status tags: `[implemented]` = code exists, needs validation. `[designed]` = spec
exists, not yet coded. No tag = needs both design and implementation.*

### Do next — validate existing implementations

- **Real-world work layer validation** `[implemented]` — exercise the full
  `/work` → `/work-decompose` → `/work-start` flow on an actual multi-feature
  task. Validate: readiness computation, context injection, pipeline mode
  selection, retro lifecycle updates. First candidate: a jlsm feature set or
  a vallorcine internal refactor.

- **Validate audit budget controls** `[implemented]` — budget controls are fully
  specified in audit/SKILL.md (4 checkpoints) with audit-budget.sh script. Need
  a real audit run with budget to confirm: AskUserQuestion flow, scope gate,
  discovery/suspect cost checkpoints, prove-fix soft cap, deferred finding marking.

- **Validate Phase 0 on F08-streaming-block-decompression** `[implemented]` —
  first real test of the already-fixed check. Same domain as block-compression
  (28 prior fixes). Measure: how many findings short-circuit at Phase 0, turn
  savings vs baseline.

- **Concurrency lens false positive rate tracking** `[implemented]` — need
  multi-codebase data to confirm thread_sharing field eliminates false positives.
  Block-compression data shows 54% preventable impossibles.

### Do soon (medium effort, clear designs)

- **Test architect hardening on a real ADR** `[implemented]` — the 6 hardening
  changes are in the prompt but untested on a real decision session. Next
  `/architect` invocation will exercise scope verification, constraint
  falsification, and inline score falsification.

### Do when needed (useful but workarounds exist)

- **Large repo curation testing** — `/curate` needs testing on a repo with
  1000+ commits, 30+ contributors.

### Do when scale demands it (team/scale features)

- **Team KB commands** — `/kb sync`, `/kb consolidate`, `/kb status`.

- **Pipeline observability** — velocity metrics, KB utilization tracking.

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
Not vibes-based. Always measure by API token pricing, never assume subscription.

**No ceremony without value.** Resist adding steps that always run regardless
of need. 0-signal complexity check is silent. 0-question scoping is valid.

**Prefer one clean interface over two adequate ones.** When choices came down
to two approaches, we consistently chose simpler to use even if harder to
implement: enter-to-proceed, sequential questions, pull model.
