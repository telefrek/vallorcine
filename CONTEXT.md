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

*Last updated: 2026-04-21*

**v0.14.0 released. jlsm on v0.14.0 kit with 15-WD planning snapshot landed.
`/curate` drift detection shipped.**

**What happened (2026-04-21):**

Single day, three lanes cleanly closed.

### vallorcine — v0.14.0 released

`/release` cut v0.14.0 from main at commit `d09bc33`. Release notes bundle
the spec-verify verify-and-repair loop, the `.work/` layer and its 5
commands, `@spec` annotation standard + `spec-trace.sh`, interface contracts,
pipeline modes, obligation lifecycle, and manifest schema v2. GitHub Release
created with zip attached; retention policy left all 4 releases intact.

### vallorcine#46 — `/curate` drift detection (merged)

Two new analyses in `curate-scan.sh`:
- **Analysis 18** — enumerate APPROVED specs via manifest (dual-schema v1/v2
  aware), call `spec-trace.sh` for each, flag reqs missing impl / test / both
  annotations. Routes to `/spec-verify`.
- **Analysis 19** — enumerate specs with non-empty `open_obligations`,
  compute age from last commit touching the spec, flag obligations older
  than `--obligation-age-days` (default 30). Routes to `/spec-author` or
  `/spec-resolve`.

New CLI flags: `--obligation-age-days`, `--max-specs-traced` (caps
`spec-trace` fan-out for large repos). `.changelog-staging.md` seeded for
next release.

### jlsm — PR #41 + #42 both merged

**#41** — 6 query specs promoted DRAFT → APPROVED with direct-coverage
annotations on 86/86 reqs (closed a claimed-but-false "100% coverage" hedge
by adding 8 new tests for R1, R2, R6, R8, R26 that previously relied on
sibling-subtype transitive coverage).

**#42** — three-commit landing:
1. Kit upgrade v0.13.8 → v0.14.0 in jlsm (`.claude/upgrade.sh`, 131/131
   MANIFEST parity). Cosmetic `upgrade.sh` bug filed as
   telefrek/vallorcine#45.
2. Planning snapshot: 5 work groups / 15 WDs in `.work/` for the 13 still-
   DRAFT specs: `close-coverage-gaps` (2 WDs, both READY),
   `implement-transport` (3 WDs, 1/2), `implement-membership` (2 WDs, 1/1,
   cross-group blocks on transport), `implement-sstable-enhancements`
   (3 WDs, all READY), `implement-encryption-lifecycle` (5 WDs, 1/4, F41
   decomposed by section). All WDs at `status: DRAFT` because specs are
   DRAFT — WDs will promote them through `/work-plan` → `/work-start` when
   scheduled. Validated with `work-validate.sh` (15/15 ok) and
   `work-resolve.sh` (readiness matches graph).
3. `.spec/MIGRATION.md` + `_migration_f03_followup/` moved into
   `_archive/migration-2026-04-20/`; 25 spec Design Narratives had their
   cross-reference updated.

**Where things stand:**
jlsm main now has everything needed to start picking up the planning
snapshot WDs. Nine are READY, six are BLOCKED on within-group predecessors.
vallorcine main has the `/curate` drift entries staged for the next
release (likely v0.14.1 — additive, backwards-compatible).

### Later in the session — competitive refresh + GSD audit

PRs #48 and #49 landed a two-step competitive analysis pass: the refresh
brought COMPETITIVE.md to current data (Superpowers 42K→163K, feature-dev
89K→176K, Qodo 2.1 Rules System, Cursor 3, Google Antigravity, claude-mem
as a category signal, academic commoditization via GitHub Code Security
instead of standalone AutoFL/LLMAO), and the GSD audit (55,791 stars)
corrected the pre-audit framing of GSD as a shallow lookalike.

**Strategic finding from the GSD audit:** GSD is a real direct-lane
competitor with substantial feature depth — falsifiable specs (Socratic
ambiguity scoring), audit pipeline, project knowledge graph, security
verification, retrospectives, wave-based multi-feature parallelism, 83
commands across 14 runtime platforms. Our defensible moat is narrower
than the pre-audit framing implied and is now architectural, not
feature-label: **spec lifecycle (DRAFT/APPROVED/INVALIDATED) +
displacement detection + specs driving audit passes + declared
artifact-dependency readiness + multi-pass knowledge-compounding audit**.
Positioning should shift from the "spec-driven" label (GSD owns that
mindshare at 55K+ stars) to depth-of-spec-rigor.

### Active plan on pause

WIP.md carries a 9-item priority stack for `/ideate continue` to resume.
Next action: item 2 — v0.14.1 release (`.changelog-staging.md` already has
the `/curate` drift entry seeded). After that: security-aware analysis
lens + four critical spec-layer gaps exposed by jlsm dogfood.

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

- **Fix now, not defer — positive justification required** (2026-04-21) —
  generalises the existing kit-failures and spec-violations rules: when a
  problem surfaces mid-session, default to fixing it in the current PR.
  Phrases like "not X's problem", "separate concern", "covered transitively
  by Y" are red flags that need positive justification before they're
  acceptable. No transitive / side-effect coverage for claimed behaviour —
  test what is claimed, directly. Memory: `feedback_fix_now_not_defer.md`.

- **Planning-snapshot work groups: DRAFT status** (2026-04-21) — WDs that
  point at specs still in DRAFT should use `status: DRAFT`, not SPECIFIED.
  SPECIFIED implies the spec is APPROVED and ready for implementation;
  DRAFT matches the actual state where the WD will promote the spec via
  `/work-plan` before implementation can proceed. Applied to the 5 jlsm
  work groups shipped in #42.

- **GSD is a real direct-lane competitor, not a shallow lookalike**
  (2026-04-21). Hands-on audit (55,791 GitHub stars, 83 commands, 14
  runtime platforms) found falsifiable specs via Socratic ambiguity
  scoring, autonomous audit-to-fix, a project knowledge graph,
  retrospectives, security verification, and wave-based multi-feature
  parallelism. Confirmed still uniquely vallorcine: spec lifecycle states,
  displacement detection, specs driving audit, declared artifact-dep
  readiness + pipeline modes, multi-pass knowledge-compounding audit.
  Positioning must emphasize the depth-of-spec-rigor axis, not the
  "spec-driven" label (GSD owns that mindshare at 55K+ stars). See
  PR #49 for full head-to-head.

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*
*Status tags: `[implemented]` = code exists, needs validation. `[designed]` = spec
exists, not yet coded. No tag = needs both design and implementation.*

### Do next

*vallorcine#43, #44, #46, #47, #48, #49 merged 2026-04-21. v0.14.0
released.*
*jlsm#40, #41, #42 merged 2026-04-21. Kit at v0.14.0; 15-WD planning
snapshot on main. Nathan working through WDs on the jlsm side.*

**Active plan on pause — see WIP.md for full 9-item stack.**
The session ended after item 1 (GSD audit) with PR #49 merged. `/ideate
continue` resumes from item 2. Summary of the stack in priority order:

1. ~~GSD feature audit~~ — **done 2026-04-21** (PR #49)
2. **v0.14.1 release** — next action. `.changelog-staging.md` already has
   the `/curate` drift entry seeded. Trivial `/release` invocation.
3. Marketplace submission currency check — user-driven; Nathan to confirm
   whether the pending submission is pinned to v0.13.x.
4. **Security-aware analysis lens** — targeted `/audit` lens for
   adversary-model bug classes (timing channels, IV reuse, ciphertext
   integrity) that generic lenses miss. Triggered by the jlsm encryption
   audit empirical data.
5. **Fix 4 critical spec-layer gaps** — feature-implement spec awareness,
   feature-refactor spec awareness, spec-write two-file invalidation,
   work-decompose spec state validation.
6. Partial implementation state model (depends on data from jlsm WDs in
   progress; revisit once 2-3 have run).
7. Fix 6 pipeline failure patterns.
8. Distributed work layer (deferred — team-mode feature).
9. #45 cosmetic `upgrade.sh` output bug (low priority).

**Positioning shift to encode across user-facing docs** (README,
EXAMPLES.md, landing content) when time permits: emphasize the
depth-of-spec-rigor axis (lifecycle, displacement, audit integration,
computed readiness) over the "spec-driven" label. GSD owns the
spec-driven label at 55K+ stars.

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
