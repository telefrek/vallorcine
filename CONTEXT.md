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

**Work layer — composable multi-feature work definitions (all 6 phases complete).**

**What happened (2026-04-11/12):**

- **Work layer (`.work/`)** — fourth knowledge layer. Same pull-model pattern as
  KB, decisions, specs. Work groups decompose large goals into work definitions
  with artifact-based dependencies and computed readiness.

- **Data model (Phase 1)** — `work-lib.sh` (YAML parsing, dep checking),
  `work-resolve.sh` (readiness computation with dependency graph and scope signal),
  `work-validate.sh` (structural validation with circular dep detection).
  Interface contracts as spec subtype (`kind: interface-contract`).

- **Creation flow (Phase 2)** — `/work`, `/work-decompose`, `/work-status` skills.
  Scoping interview, dependency graph presentation, readiness query.

- **Context injection (Phase 3)** — `work-context.sh` provides work group context
  to architect (forward compatibility, ordering gates), spec-author (downstream
  consumers), feature-domains (cross-WD domain reuse), feature-plan (interface
  stability constraints), and feature-resume (work group grouping).

- **Pipeline bridge (Phase 4)** — `/work-start` bridges work definitions into the
  feature pipeline. Feature-retro updates WD status and triggers readiness cascade.
  Feature-complete updates manifests.

- **Curation (Phase 5)** — curate-scan analyses 15-17: cross-WD spec displacement
  detection, stalled work groups, artifact dependency drift.

- **Pipeline decomposition (Phase 6)** — `pipeline_mode` field: specification-only
  (scoping → domains → spec authoring → complete), implementation-only (planning →
  testing → hardening → implementation → refactor), and full (default, backwards
  compatible). Mode-aware routing in feature-resume.

- **Bug fix** — 3 `grep -c` pipefail instances in curate-scan.sh producing "0\n0"
  instead of clean integers.

- **Tests** — 7 new test suites (68 new tests), 137 total across all suites. Zero
  regressions. 32 files changed, ~5K lines.

**Where things stand:**
All implementation on `feat/work-layer-foundation` branch (9 commits, 46 files,
~5K lines). Docs updated (DESIGN, README, CONTEXT). Tech debt cleaned (35
AskUserQuestion migrations, stale .bak removed). Changelog staged. Ready for
PR and merge. Next: real-world validation on a multi-feature workflow, then
remaining Open Questions (Phase 0 validation, concurrency lens, audit budget
controls).

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

- **Artifact-based dependencies, not stage-based** (2026-04-11) — work definitions
  depend on specific artifacts (specs at APPROVED, ADRs at accepted, KB entries
  existing), not on other WDs completing stages. Enables partial unblocking and
  provides a scoping signal (>5 deps = consider decomposition).

- **Interface contracts as spec subtype** (2026-04-11) — `kind: interface-contract`
  field on specs, not a fifth knowledge layer. Reuses all existing spec tooling
  (resolve, validate, author, displace). Displacement detection works on them
  automatically.

- **Computed readiness, not declared** (2026-04-11) — `work-resolve.sh` walks
  artifact deps each invocation. No cached state to go stale. Completing a WD
  that produces artifacts automatically unblocks dependent WDs.

- **Pipeline mode decomposition** (2026-04-11) — specification-only stops after
  spec authoring, implementation-only starts from planning. `pipeline_mode` field
  in status.md (default: full, backwards compatible). Work-start auto-detects
  mode from WD produces list.

- **Work context as pull-model injection** (2026-04-11) — `work-context.sh`
  provides bounded context snippets to architect, spec-author, domain analysis,
  work planner, and feature-resume. Zero cost when no work groups exist.

*9 decisions graduated to SETTLED.md (2026-04-12): effort asymmetry removal,
concurrency lens filtering, spec conflict detection, DRAFT specs blocked,
spec extraction from implementation, [ABSENT] lifecycle, fix-spec resolution,
architect adversarial hardening, Phase 0 already-fixed check.*

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*

### Do next (high priority, clear direction)

- **Real-world work layer validation** — exercise the full `/work` → `/work-decompose`
  → `/work-start` flow on an actual multi-feature task. Validate: readiness
  computation, context injection, pipeline mode selection, retro lifecycle
  updates. First candidate: a jlsm feature set or a vallorcine internal refactor.

- **Validate Phase 0 on F08-streaming-block-decompression** — first real test
  of the already-fixed check. Same domain as block-compression (28 prior fixes).
  Measure: how many findings short-circuit at Phase 0, turn savings vs baseline.

- **Concurrency lens false positive rate tracking** — need multi-codebase data
  to confirm thread_sharing field eliminates false positives. Block-compression
  data shows 54% preventable impossibles.

### Do soon (medium effort, clear designs)

- **Audit budget controls** — dollar cap on the prove-fix loop. Design:
  a cost-tracking script that sums JSONL token usage after each subagent.
  The prove-fix orchestrator calls it after each finding, stops dispatching
  when the running total hits the budget. Remaining findings marked DEFERRED
  in the report. Budget does NOT affect assembly, suspect, test cleanup,
  reporting, or feedback loop — those always run. CLI: `/audit --budget 200`.
  Needed before running the 7 remaining jlsm audits (~$3-5K total).

- **Test architect hardening on a real ADR** — the 6 hardening changes are
  in the prompt but untested on a real decision session. Next `/architect`
  invocation will exercise scope verification, constraint falsification, and
  inline score falsification.

### Do when needed (useful but workarounds exist)

- ~~**/feature-split**~~ — **subsumed by work layer** (2026-04-11). `/work-decompose`
  handles scope decomposition at the work group level. Individual features remain
  atomic; scope expansion is handled by creating new work definitions.

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
