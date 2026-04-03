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

*Last updated: 2026-03-30*

**Spec storage system + adversarial authoring + pipeline integration.**

Built the complete spec storage layer (`.spec/`), adversarial spec authoring
process (`/spec-author`), and integrated specs into the work planner and TDD
pipeline. Tested on float16-vector-support: 8 surface requirements expanded
to 29 hardened behavioral requirements across two adversarial passes (~110K
tokens total for both passes).

**What happened this session (2026-03-30):**

- **Spec storage system built and tested** — 5 bash scripts (spec-lib, validate,
  stats, resolve, obligations-gc), 6 skills (spec-init, spec-resolve, spec-write,
  spec-verify, spec-author), install/upgrade/manifest integration. Domain-sharded
  directories, manifest registry for O(1) lookups, transitive `requires` expansion,
  token-budgeted context bundles. Tested against sample 3-spec corpus.

- **Adversarial spec authoring validated** — two-pass process: structured draft
  (operational sequence tracing, failure mode expansion, decision collapsing) then
  adversarial falsification (enforcement path tracing, cross-requirement interaction,
  cross-module boundaries, observability). Float16 test: pass 2 found 6 new gaps,
  pass 3 found 4 (diminishing returns confirmed two passes optimal).

- **KB/decisions cross-references added** — `related`, `decision_refs`, `kb_refs`
  fields across all three knowledge layers. LLM relevance gate in `/kb` query.
  Tags on category indexes for keyword scan surface area. `adr-validate.sh`
  extended with cross-reference validation.

- **Work planner integrated with specs** — spec resolution as primary context,
  construct-graph clustering (shares_state, produces/consumes, depends_on),
  requirement traceability table, agent success shaping, spec as tiebreaker
  for escalations.

- **TDD framing agreed** — test writer operationalizes spec (Lens A becomes
  "can I write a test that verifies this requirement?"), breaker falsifies spec
  (finds behaviors the spec didn't anticipate). Audit mode: same split.

**Where things stand:**
Spec system is built and tested. Work planner is integrated. TDD test writer and
breaker agent changes are designed but not yet implemented. Next: implement
`/feature-test` changes, update breaker agent, then run end-to-end test on float16.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

- **Spec storage as sixth knowledge layer** (2026-03-30) — `.spec/` alongside `.kb/`
  and `.decisions/`. Domain-sharded directories, manifest registry, bash resolver for
  deterministic context bundles. Specs reference decisions and KB, don't duplicate them.

- **Two-pass adversarial spec authoring** (2026-03-30) — Pass 1: structured draft with
  operational sequence tracing and failure mode expansion. Pass 2: adversarial
  falsification with enforcement path tracing. User checkpoint between passes.
  Validated: 8→29 requirements on float16, two passes optimal (third pass yield drops).

- **Specs describe behavior, not code** (2026-03-30) — requirements must be verifiable
  by observing inputs/outputs, never reference class/method/file names. Work planner
  translates behavioral contracts into implementation constructs.

- **Prerequisite stubs verified and APPROVED immediately** (2026-03-30) — when a feature
  assumes something about an existing component, create a minimal spec stub, verify it
  holds in code, mark APPROVED. No DRAFT stubs for verified assumptions.

- **Conflict check mandatory in /spec-write** (2026-03-30) — new specs must run the
  resolver first and either `invalidates` conflicting requirements or adjust. Silent
  contradictions are spec defects.

- **Collapse user decisions, expand spec requirements** (2026-03-30) — present users
  one conceptual decision; expand into separate per-layer requirements that evolve
  independently. Users make fewer decisions; specs are fully descriptive.

- **Enforcement path tracing for new requirements** (2026-03-30) — any requirement
  adding validation must trace callers/consumers. A requirement that creates a
  cascading failure when enforced is a spec defect, not a finding.

- **Construct-graph clustering replaces token-based work unit splitting** (2026-03-30) —
  work units cluster by shares_state (unsplittable), produces/consumes, and depends_on.
  Later units include prior unit constructs as visible context. Token cost is secondary.

- **KB cross-references via `related` and `decision_refs`** (2026-03-30) — explicit
  frontmatter fields for cross-topic KB links and KB→ADR links. LLM relevance gate
  prunes before deep reads. Depth-1 limit on `related` traversal. Tags on category
  indexes for keyword scan surface area. Repair mechanism deferred to `/curate`.

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*

### Do next (high priority, clear direction)

- **Implement /feature-test spec integration** — update Lens A (operationalize
  spec requirements into tests) and Lens B (spec failure modes as test vectors).
  Update breaker agent prompt for spec-aware falsification.

- **End-to-end test** — run /spec-author → /spec-write → /feature-plan →
  /feature-test on float16-vector-support in jlsm. Validate the full pipeline
  from hardened spec to failing tests.

- **Integrate spec into shipped /audit skill** — audit mode reads `.spec/` as
  authoritative reference, diffs code against spec. Findings are either "code
  violates spec requirement" or "code has behavior no spec covers."

### Do soon (medium effort, clear designs)

- **Architect/decision hardening** — apply adversarial authoring to the decision
  deliberation layer. Same Author→Adversarial→Arbitration pattern. Use existing
  jlsm ADRs (pre/post-hardening) as test cases.

- **Phase 4 implementation for audit** — write-and-return test writer (4a),
  compile checker (4b), fix-up subagent (4c), per-cluster implementer (4d).
  Context pruning to eliminate compile/fix loop bloat.

- **/curate cross-reference repair** — new signal type that discovers missing
  `related`/`decision_refs` in existing KB entries via tag overlap and
  applies_to pattern matching.

### Do when needed (useful but workarounds exist)

- **/feature-split** — split in-progress feature when scope expands. Workaround:
  finish current feature, start a new one.

- **Large repo curation testing** — `/curate` needs testing on a repo with
  1000+ commits, 30+ contributors.

### Do when scale demands it (team/scale features)

- **Team KB commands** — `/kb sync`, `/kb consolidate`, `/kb status`.

- **Pipeline observability** — velocity metrics, KB utilization tracking.

- **LSP integration** — README documentation of companion plugins.

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
