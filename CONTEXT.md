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

*Last updated: 2026-04-03*

**Audit pipeline validation + spec ecosystem hardening + jlsm release prep.**

Two sessions (2026-04-02 and 2026-04-03) validated the combined prove-fix
pipeline on float16-vector-support and block-compression, hardened the full
aTDD pipeline with adversarial fixes, built the spec conflict detection
and extraction system, and started the jlsm release prep (2-week push).

**What happened (2026-04-02):**

- **Combined prove-fix model validated** — merged separate Prove + Fix stages
  into single per-finding subagent. Tested on float16: 40 findings, 20 fixed,
  10 impossible, $207 total (with fixes included). Serial execution prevents
  fix conflicts and enables fix cascade deduplication (7 of 10 impossibles
  were prior fixes resolving later findings).

- **All 5 release blockers cleared** — spec phase in /feature flow, /feature-test
  consuming .spec/, /feature-audit using prove-fix, multi-language parity for
  pipeline scripts (bash + Node), /feature-audit renamed to /audit.

- **Pipeline hardened with 5 adversarial fixes** — spec-author prove/disprove
  framing, architect falsification pass, KB confidence field, audit feedback
  loop (reconcile-findings), feature-refactor delegation to /audit.

- **Script audit** — ~55 fixes across 27 scripts (bash/Python/Node): atomic
  writes, exit 0 guarantees, pipefail safety, empty array guards.

**What happened (2026-04-03):**

- **Block-compression audit complete** — 77 findings, 28 fixed, 49 impossible,
  $550. 6 lenses, 11 clusters. Found real bugs: footer overflow guards,
  int truncation, codec validation, state machine hardening, resource safety.

- **Impossible category analysis** — 48 impossibles broken down: 19 fix cascade
  (40%), 4 single-threaded false positive (8%), 3 idempotent false positive (6%),
  22 genuine (46%). True bug rate: 52.2% (excluding preventable impossibles).

- **Concurrency lens false positive prevention** — card construction captures
  thread_sharing evidence, Suspect has mandatory concurrency clearings,
  domain pruning excludes single-threaded constructs from concurrency clusters.

- **Test deduplication** — prove-fix checks existing test coverage before writing
  new tests. Suspect can clear findings as "already tested."

- **Spec conflict resolution flow** — audit report detects fix-spec conflicts,
  orchestrator presents 3 options (keep fix + update spec, revert fix, defer).
  Standalone resolve-spec-conflict prompt for manual resolution.

- **Spec extraction mode** — bottom-up spec authoring from existing implementation.
  Auto-discovers source files, consuming specs, and tests. Cross-references
  consuming specs for CONTRADICTED, UNGUARANTEED, MISSING findings.

- **[ABSENT] requirement promotion** — extraction mode surfaces behaviors the
  code does NOT do. Users promote (becomes implementation work), preserve
  (becomes negative requirement), or defer (curate resurfaces later).

- **Curate spec awareness** — 4 new signal types: unspecified shared types,
  open obligations, spec-code drift, undecided [ABSENT] requirements. Each
  routes to the appropriate spec command.

- **Batch spec authoring** — 10 jlsm features got hardened specs via automated
  two-pass process. ~$3.40/spec.

**Where things stand:**
Audit pipeline is validated on 2 features with real cost data. Spec ecosystem
is comprehensive: authoring, extraction, conflict detection, resolution,
curate integration. jlsm has 11 specs covering all features. Block-compression
has a spec conflict (eager snapshot vs F08 streaming) being resolved. Next
audit will validate the concurrency lens fix and test dedup improvements.

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

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*

### Do next (high priority, clear direction)

- **Spec-driven work planning** — two capabilities: (1) free-text search across
  all specs to find applicable requirements for a problem description,
  (2) spec-change-driven planning where the planner traces downstream impact
  of requirement changes (tests, implementations, dependent specs). Entry
  point: `/spec-plan` or extension of `/spec-author`.

- **Validate concurrency lens fix** — run an audit on a concurrency-heavy
  feature (striped-block-cache) with updated prompts. Verify single-threaded
  false positives are eliminated and test dedup reduces cascade impossibles.

- **JlsmSchema spec extraction** — running now. Will test the extraction mode
  on the highest-fanout type (6 consuming specs). Results inform whether
  extraction mode scales.

### Do soon (medium effort, clear designs)

- **Architect/decision hardening** — apply adversarial authoring to the decision
  deliberation layer. Falsification pass added (Step 6) but not yet tested
  on real ADRs.

- **/curate cross-reference repair** — signal type that discovers missing
  `related`/`decision_refs` in existing KB entries via tag overlap.

- **Concurrency lens false positive rate tracking** — need multi-codebase data
  to confirm thread_sharing field eliminates false positives. Block-compression
  data shows 54% preventable impossibles.

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
