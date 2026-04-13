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

*Last updated: 2026-04-13*

**Spec hardening validated. Audit → pipeline feedback loop proven.**

**What happened (2026-04-12/13):**

- **v0.13.0** — work layer shipped (PR #36 merged). 7 concerns, 40+ commands,
  137 tests. Documentation overhauled (README, DESIGN, COMPETITIVE). MANIFEST
  integrity fixes. Narrative generation made reliable. 50 prose prompts migrated
  to AskUserQuestion. Session-end prevention rule. Status line truncation.

- **v0.13.1** — spec falsification hardened with 7 mandatory probe lenses derived
  from 51 real audit findings: degenerate values, boundary validation, resource
  lifecycle, cross-construct atomicity, error propagation, identity/equality, trust
  boundaries. Mandatory concurrency contracts in every spec. KB adversarial findings
  loaded into falsification. Concurrency contracts flow through full pipeline
  (feature-test, feature-harden, audit cards, aTDD breaker).

- **v0.13.2** — standards compliance probe. RFC compliance claims checked against
  all other requirements for contradictions.

- **json-only-simd-jsonl audit** — 16 confirmed bugs fixed (vs 33 avg for earlier
  features without specs). 13 of 16 map to spec lenses shipped in v0.13.1/v0.13.2.
  2 are SIMD algorithm bugs (spec was correct, impl was wrong). Cost: $233 total,
  $14.58/bug. 4 KB patterns created, 13 spec requirements added (R47-R59).

- **ROI validated**: spec analysis costs ~$30 extra, saves ~$216 in audit costs.
  With v0.13.1 spec improvements, projected reduction from 16 to ~3 audit bugs
  (81% reduction). Feature pipeline is the quality gate; audit is the diagnostic.

- **Roadmap → work group bridge** — `/decisions roadmap` now offers "Create work
  group" (Step 9) that translates clusters into `.work/` WDs. New `/work-plan`
  command for specification-only pipeline. `/work-start` simplified to
  implementation-only (mode auto-detection removed).

**Where things stand:**
Released v0.13.2. Roadmap → work group bridge implemented (pending release).
Next jlsm feature will be the first authored with the hardened spec
falsification — the real test of whether the 7 lenses prevent the bugs
upstream. Remaining: lightweight post-TDD audit design (deferred, waiting for
next feature's audit data).

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

### Do next

- **First feature with hardened spec falsification** — author a jlsm feature
  using v0.13.2 (7 falsification lenses, mandatory concurrency contracts, KB
  adversarial findings, standards compliance probe). Then audit it. Compare
  audit findings to json-only-simd-jsonl baseline (16 bugs). Target: <5 bugs.

- **Real-world work layer validation** `[implemented]` — exercise the full
  `/work` → `/work-decompose` → `/work-start` flow on an actual multi-feature
  task. First candidate: a jlsm feature set.

### Do soon (medium effort, clear designs)

- **Validate audit budget controls** `[implemented]` — run an audit with a
  dollar budget to confirm the AskUserQuestion flow and soft cap work.

- **Test architect hardening on a real ADR** `[implemented]` — the 6 hardening
  changes are in the prompt but untested on a real decision session.

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
