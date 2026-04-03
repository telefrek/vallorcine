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

*Last updated: 2026-04-03 (evening)*

**Open question resolution + prove-fix cost optimization + jlsm release prep.**

Three sessions (2026-04-02, 2026-04-03 day, 2026-04-03 evening) validated the
prove-fix pipeline on 3 features, resolved the high-priority open questions,
and identified + fixed a major cost inefficiency in the prove-fix subagent.

**What happened (2026-04-02 and 2026-04-03 day):**

See previous session entries in SETTLED.md for: combined prove-fix model,
release blockers, adversarial fixes, script audit, block-compression audit,
impossible category analysis, concurrency lens, spec ecosystem, batch specs.

**What happened (2026-04-03 evening):**

- **Open questions resolved:**
  - Spec-driven work planning → already implemented in `/spec` (discovery +
    change impact modes). Graduated.
  - Architect/decision hardening → 6 changes applied: scope verification
    (Step 0.5), constraint falsification (Step 1b), inline score falsification
    (scores >= 4 need "Would be a 2 if:"), prior ADR scores not evidence,
    falsification subagent REQUIRED annotations, quality checklist converted
    to write-and-justify narrative.
  - Curate cross-reference repair → implemented: Analysis 11 in curate-scan.sh
    (KB tag overlap, applies_to overlap, ADR eval→KB source gaps), Step 2i
    in curate SKILL, pick list items 14-15, action handlers.

- **Table-indices-and-queries audit data** — 68 findings: 38 fixed, 29
  impossible, 1 fix_impossible. Real turn counts from JSONL: IMPOSSIBLE
  findings averaged 35 turns each (1,155 total) vs CONFIRMED averaging
  39.7 turns (1,748 total). 40% of total audit effort was waste.

- **Phase 0 already-fixed check** — new mandatory pre-flight in prove-fix
  subagent (max 3 turns). Reads current source before writing any test.
  If the described vulnerability was already fixed by a prior finding in the
  same run, short-circuits to IMPOSSIBLE without test writing. Expected
  savings: ~900 turns (~30% of total audit cost) per feature.

**Where things stand:**
All high-priority open questions resolved. Architect pipeline hardened with
research-backed adversarial patterns. Curate has cross-reference repair.
Phase 0 installed in jlsm — next test: F08-streaming-block-decompression
(same domain as block-compression, ideal cascade test). Table-indices audit
completing test cleanup phase.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

- **Combined prove-fix per-finding model** (2026-04-02) — merged Prove + Fix into
  single subagent. Each finding gets fresh context. Test result determines path
  (not agent's choice). Validated: same cost as prove-only with fixes included.
  Fix cascade reduces total work via serial execution.

- **Sequential execution for prove-fix** (2026-04-02) — one finding at a time,
  no parallelism. Prevents fix conflicts on shared source files. Fix cascade
  deduplication is a bonus. Wall-clock tradeoff acceptable.

- **Effort asymmetry removal in prove-fix** (2026-04-02) — agent always writes
  test regardless of outcome (confirmed or impossible). Test result chooses the
  path. Prevents task-avoidance bias from sandbagging research.

- **Concurrency lens per-construct filtering** (2026-04-02) — thread_sharing
  field in cards (none/possible/explicit). Concurrency lens excludes
  thread_sharing:none constructs. Prevents false positives on single-threaded
  components.

- **Spec conflict detection at resolution time** (2026-04-02) — spec-resolve.sh
  checks for contradictions between included specs before emitting bundle.
  Feature-plan blocks, feature-test marks UNTESTABLE, feature-implement
  diagnoses spec conflicts instead of misdiagnosing as test/contract bugs.

- **DRAFT specs with conflicts blocked from bundles** (2026-04-02) — specs with
  [UNRESOLVED]/[CONFLICT] markers or open_obligations excluded from resolved
  context. Only APPROVED specs trusted as authoritative.

- **Spec extraction from implementation** (2026-04-03) — bottom-up spec
  authoring for foundational types (JlsmSchema, JlsmDocument). Auto-discovery
  of source, consuming specs, tests. [ABSENT] tag for behaviors code doesn't
  have but specs may assume.

- **[ABSENT] requirement lifecycle** (2026-04-03) — promote (becomes
  implementation work with [UNIMPLEMENTED] obligation), preserve (becomes
  negative requirement), defer (curate resurfaces). No requirement falls
  through the cracks.

- **Fix-spec conflict resolution** (2026-04-03) — three options: keep fix +
  update spec, revert fix + mark FIX_IMPOSSIBLE, split (keep fix + add new
  requirement that invalidates old). Fourth option: defer with [UNRESOLVED].

- **Architect adversarial hardening** (2026-04-03) — 6 changes from aTDD
  research: scope verification, constraint falsification, inline score
  falsification, prior-scores-not-evidence, REQUIRED annotations, write-and-
  justify checklist. Each change maps to a specific research finding.

- **Phase 0 already-fixed check** (2026-04-03) — mandatory pre-flight in
  prove-fix subagent. Reads current source before test writing. Short-circuits
  cascade impossibles in 3 turns instead of 35. Evidence: 33 IMPOSSIBLE
  findings in table-indices audit averaged 35 turns each.

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*

### Do next (high priority, clear direction)

- **Validate Phase 0 on F08-streaming-block-decompression** — first real test
  of the already-fixed check. Same domain as block-compression (28 prior fixes).
  Measure: how many findings short-circuit at Phase 0, turn savings vs baseline.

- **Concurrency lens false positive rate tracking** — need multi-codebase data
  to confirm thread_sharing field eliminates false positives. Block-compression
  data shows 54% preventable impossibles.

### Do soon (medium effort, clear designs)

- **Test architect hardening on a real ADR** — the 6 hardening changes are
  in the prompt but untested on a real decision session. Next `/architect`
  invocation will exercise scope verification, constraint falsification, and
  inline score falsification.

### Do when needed (useful but workarounds exist)

- **/feature-split** — split in-progress feature when scope expands.

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
