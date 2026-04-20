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

*Last updated: 2026-04-19*

**Spec verification and repair in progress. Kit tooling shipped. Domain reorg designed.**

**What happened (2026-04-16/17/19):**

Built the spec traceability and verification system, then used it to verify all
jlsm specs with existing implementation code.

**Kit changes (vallorcine, feat/spec-traceability branch, 5 commits):**
- `@spec FXX.RN` annotation standard for code↔spec traceability
- `spec-trace.sh` — finds annotations across codebases (13 scenario tests)
- spec-verify redesigned as 6-phase verify-and-repair loop (verify → classify →
  decide → amend specs → fix code via TDD → finalize)
- spec-verify annotates implementation AND test files during discovery
- spec-verify fills test gaps (writes structural/reflection tests for uncovered
  requirements)

**jlsm verification results (in progress):**
- **7 specs APPROVED:** F02 (v2), F06, F08 (v3), F13 (v1), F14 (v2), F15 (v3),
  F17 (v1) — real bugs found and fixed, stale spec text amended, regression tests
  added, `@spec` annotations throughout
- **Remaining:** F01, F03, F04, F05, F07, F09, F10 (in progress), F11, F12, F16, F18
- **6 pipeline failure patterns identified** — each has root cause and fix task

**Comprehensive gap analysis completed:** 11 spec-layer gaps found across skills,
scripts, and agents. 4 critical (feature-implement, feature-refactor, spec-write
invalidation, work-decompose state validation), 4 important (cross-spec conflict,
audit feedback, displacement, test traceability), 3 lower priority.

**Spec reorganization designed:** Feature-centric (`F13-jlsm-schema.md`) →
behavioral-domain (`schema/construction.md`). 12 top-level domains, ~60 spec files.
Annotation format changes from `@spec F13.R1` to `@spec schema.construction.R1`.
Execute after verification pass completes.

**Where things stand:**
Verification pass ~50% complete (7/18 implementation specs APPROVED). F10 (139
reqs, largest) in progress. After verification: domain reorg, then fix the 11
spec-layer gaps, then unblock work-start with restructured WDs.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

*4 decisions graduated to SETTLED.md (2026-04-19): WD validity, spec promotion,
health model, work-decompose spec state. See SETTLED.md.*

- **Spec violations are contracts, not backlog** (2026-04-16) — spec-verify
  repairs violations inline (fix code or amend spec). Obligations created only
  on explicit user deferral, never as default path.

- **@spec annotations as primary traceability** (2026-04-16) — `@spec FXX.RN`
  comments in code link requirements to enforcement points. spec-verify
  annotates during discovery. spec-trace.sh provides the reverse index.

- **Correctness over context cost** (2026-04-17) — never drop correctness-relevant
  context to save tokens. Solve context problems via phase splitting and condensed
  handoffs instead of skipping information agents need.

- **Spec reorganization: behavioral domains** (2026-04-17) — specs will migrate
  from feature-centric (F13-jlsm-schema.md) to behavioral-domain
  (schema/construction.md). 12 domains, ~60 files. Annotation format changes
  to `@spec domain.slug.RN`. Execute after verification pass.

- **Partial implementation state needed** (2026-04-19) — current model is binary
  (APPROVED or DRAFT). Need a clean representation for "90% implemented, 10%
  explicitly deferred." Domain reorg may solve naturally (implemented parts in
  one spec, stubs in another).

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*
*Status tags: `[implemented]` = code exists, needs validation. `[designed]` = spec
exists, not yet coded. No tag = needs both design and implementation.*

### Do next

- **Complete jlsm spec verification** — 11 specs remaining with implementation
  code (F01, F03, F04, F05, F07, F09, F10, F11, F12, F16, F18). F10 in progress.
  Each goes through verify-and-repair loop: annotate, verify, classify, fix.

- **Spec domain reorganization** — migrate from feature-centric to behavioral-domain
  organization. 12 domains, ~60 files. Mechanical: rename script + manifest rebuild
  + `@spec` annotation find/replace. Execute after verification pass. `[designed]`

- **Unblock jlsm work-start** — restructure decisions-backlog WDs, then validate
  `/work-start` flow. Depends on spec verification + reorg completing first.

### Do soon (medium effort, clear designs)

- **Fix spec-layer gaps (11 identified)** — 4 critical: feature-implement spec
  awareness, feature-refactor spec awareness, spec-write two-file invalidation,
  work-decompose spec state validation. Full gap analysis in session memory.

- **Fix 6 pipeline failure patterns** — one-sided invalidation, audit outpacing
  specs, assert-only guards, dead code wiring, spec asymmetry, feature-centric
  organization. Each has root cause and fix task documented.

- **Partial implementation state model** — binary APPROVED/DRAFT insufficient for
  specs that are 90% implemented. Need either per-requirement states, split specs,
  or APPROVED-with-obligations. Data from verification pass will inform design.

### Do when needed (useful but workarounds exist)

- **Large repo curation testing** — `/curate` needs testing on a repo with
  1000+ commits, 30+ contributors.

- **spec-trace.sh sub-lettered IDs** — R39a-h pattern not matched by numeric-only
  regex. Annotations exist in code but uncounted. Fix when reorg drops FXX IDs.

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
