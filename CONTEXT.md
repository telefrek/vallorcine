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

*Last updated: 2026-04-20*

**Spec domain migration complete end-to-end. Two PRs open awaiting review.**

**What happened (2026-04-20):**

Single session executed the full spec-to-domains migration in jlsm + kit-side
support in vallorcine. Both branches pushed, both PRs open.

### PR telefrek/vallorcine#43 — `feat/spec-traceability` (10 commits)

Three bundled layers:

**Layer 1 — spec-verify verify-and-repair loop** (previously on the branch):
`@spec FXX.RN` annotation standard, `spec-trace.sh`, 6-phase verify-and-repair
in `/spec-verify` with discovery-time annotation and test-gap filling.

**Layer 2 — Obligation lifecycle kit** (new this session):
- `type: wd` WD-to-WD dependencies in `artifact_deps`
- Obligation scanning in `/curate` (analysis 10e)
- `/work-decompose --from-obligations` mode
- `work-finalize.sh` auto-resolves WDs + obligations on feature complete
- `/work-start` distinguishes hard wd-type blocks from soft artifact blocks
- `test-install.sh` SIGPIPE fix — tests 8-14 hadn't been running (13 PASS →
  56 PASS)

**Layer 3 — Kit-side domain.slug support** (new this session):
Scripts (spec-trace, spec-validate, spec-resolve, spec-lib) and skills
(spec-write, spec-verify, spec/CLAUDE.md, work-decompose) accept both legacy
`FXX.RN` and new `domain.slug.RN` formats. `spec_file_for_id` supports both
manifest schema versions. Backwards-compatible — existing user projects work.

### PR nathannorthcutt/jlsm#40 — `spec-refactor` (13 commits)

Full migration execution:
- `.spec/MIGRATION.md` — 500-line plan with all 11 design decisions resolved
- 48 → 75 spec files across 12 canonical domains (schema, serialization,
  compression, sstable, wal, vector, query, encryption, engine, partitioning,
  transport, membership)
- 2838 source→destination RN mappings
- 8 dropped reqs (F02.R2-R10 invalidated by F17, F14.R48-R49 YAML never built)
  → historical comment markers
- 188+34 source files had `@spec` annotations rewritten
- F03 follow-up split: 22 application reqs extracted from
  `encryption/primitives-*` to `query/` + `serialization/`
- Two quality fixes landed in the branch: self-reference in
  compression.codec-contract, missing narrative separator on 29 migration-
  generated specs (Design Narrative stubs now point to the archive)

**Verified:**
- `./gradlew test` — BUILD SUCCESSFUL in 3m 47s on jlsm
- Round-trip validation passes (every source.rn resolves in the new layout)
- Kit's `spec-validate.sh` passes on all 75 jlsm specs end-to-end

**Where things stand:**
Both PRs awaiting review. Backup of pre-migration specs lives at
`.spec/_archive/migration-2026-04-20/` in jlsm. MIGRATION.md + the
`_migration_f03_followup/` scripts are preserved in the branch for reference.

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

- **Primitives vs applications — encryption pattern** (2026-04-20) — encryption
  spec content splits cleanly by abstraction level. Primitives (keys, rotation,
  algorithms, variants) live in `encryption/`. Applications (how WAL/query/
  indices use encryption) live in their functional domain with a multi-domain
  tag for discovery from encryption. Codified as MIGRATION.md P6 and applied
  to F42/F46/F47/F03 during jlsm migration. Same principle generalizes to any
  cross-cutting primitive (compression, serialization would follow same pattern).

- **Manifest schema v2** (2026-04-20) — post-migration manifest uses
  `{schema_version: 2, specs: [{id, path, ...}]}` (array of specs with id
  field) instead of legacy `{features: {FXX: {...}}}` (object keyed by ID).
  Kit's `spec_file_for_id` detects both and adapts. Schema v2 handles
  `domain.slug` spec IDs naturally; v1 is retained for backwards compat
  with legacy projects.

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*
*Status tags: `[implemented]` = code exists, needs validation. `[designed]` = spec
exists, not yet coded. No tag = needs both design and implementation.*

### Do next

*vallorcine#43 and jlsm#40 merged 2026-04-21.*

- **Post-migration cleanup in jlsm** (small follow-up PR):
  - Remove `.spec/MIGRATION.md` (plan doc, no longer needed)
  - Remove `.spec/_migration_f03_followup/` (kept through merge for reference)
  - Keep `.spec/_archive/migration-2026-04-20/` through one release cycle,
    then remove

- **Unblock jlsm work-start** — restructure decisions-backlog WDs, then validate
  `/work-start` flow against the new domain.slug specs.

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
