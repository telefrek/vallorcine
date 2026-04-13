# Changelog

All notable changes to vallorcine are documented here.
Format: `## [version] — YYYY-MM-DD` with sections Added / Changed / Fixed / Removed.

---

## [0.13.4] — 2026-04-13

### Added
- **PreCompact crash recovery hook** — checkpoints active feature status
  before context compaction so `/feature-resume` can recover after overflow.

### Changed
- **Effort tuning** — `effort: high` on 4 adversarial skills (audit,
  feature-harden, spec-author, spec-verify) for deeper reasoning where
  it directly improves bug-finding quality.
- **KB article line limit relaxed** — soft target 200 lines, hard limit
  300 (was hard 200). Prevents unnecessary article splits on dense research.

---

## [0.13.3] — 2026-04-13

### Added
- `/work-plan` command — specification-only pipeline for work definitions.
  Runs domain analysis and spec authoring without implementation stages.
- `/decisions roadmap` "Create work group" option (Step 9) — translates
  roadmap clusters into `.work/` work definitions with artifact dependencies
  for parallel execution across terminal sessions.

### Changed
- `/work-start` simplified to implementation-only pipeline. Mode
  auto-detection removed; always hands off to `/feature-plan`. BLOCKED WDs
  now offer "Run /work-plan first" option.
- Cross-references updated across 8 skill files for `/work-plan` awareness.

---

## [0.13.2] — 2026-04-12

### Added

- **Standards compliance probe** — spec falsification checks every RFC/standard compliance claim against all other requirements for contradictions. Deviations must be explicit numbered requirements, not hidden behind "stricter than X." Root cause: F15 claimed RFC 8259 compliance but also rejected blank keys, which RFC 8259 allows.

---

## [0.13.1] — 2026-04-12

### Added

- **Spec falsification lenses** — 6 mandatory probe checklists in Pass 2a, derived from 51 real audit findings across 7 jlsm features:
  - **Degenerate values** — NaN, infinity, negative zero, boundary overflow, empty/null for every typed requirement
  - **Boundary validation** — unconditional validation, entry point enumeration, mutable input after validation
  - **Resource lifecycle** — derived objects after close, partial construction failure, close failure, double-close
  - **Cross-construct atomicity** — partial failure between multi-construct operations, rollback, observer visibility
  - **Error propagation** — post-error state, mid-stream output, shared resource state after exceptions
  - **Identity/equality** — equality semantics for types in comparison, lookup, dedup, caching
  - **Trust boundaries** — predicate sub-states, implicit trust between constructs
- **Mandatory concurrency contracts** — every construct in a spec must declare its thread-safety model. "Not thread-safe" is a requirement, not an omission. Pass 1 Step 1e drafts contracts, Pass 2a verifies completeness.
- **KB adversarial findings in spec falsification** — Pass 2 loads `type: adversarial-finding` KB entries for the feature's domains, providing proven attack vectors from prior audits
- **Concurrency contracts flow through full pipeline** — spec declarations inform feature-test (Lens B), feature-harden (concurrency lens), audit cards (thread_sharing), and aTDD breaker (concurrent attack generation). "Not thread-safe" prevents false positive concurrency findings everywhere.

### Fixed

- **Assembly subagent** — reads input files once instead of repeatedly (was reading analysis-cards.yaml 4 times, ~150K wasted tokens per run)

### Changed

- `/release` Step 7b now deletes old GitHub releases instead of converting to draft. Git tags are always preserved.

---

## [0.13.0] — 2026-04-12

### Added

- **Work layer (`.work/`)** — fourth knowledge layer for composable multi-feature work. Decompose large goals into work definitions with artifact-based dependencies and computed readiness. Same pull-model pattern as KB, decisions, and specs.
- **`/work "<goal>"`** — create a work group with scoping interview
- **`/work-decompose "<slug>"`** — break a work group into work definitions with dependency graph and shared interface contracts
- **`/work-status "<slug>"` / `--all`** — readiness report: what is READY, BLOCKED, IN_PROGRESS, or COMPLETE
- **`/work-start "<slug>" [WD-nn | next]`** — start implementing a ready work definition, bridging into the feature pipeline
- **Interface contracts** — specs with `kind: interface-contract` for shared surfaces between work definitions. Reuses all existing spec tooling.
- **Pipeline modes** — `specification` (produce artifacts only), `implementation` (consume existing specs, skip scoping/domains), `full` (default, backwards compatible). Mode-aware routing in feature-resume.
- **Work-aware context injection** — architect (forward compatibility, ordering gates), spec-author (downstream consumers), feature-domains (cross-WD domain reuse), feature-plan (interface stability constraints), feature-resume (work group grouping)
- **Curate analyses 15-17** — cross-WD spec displacement, stalled work groups, artifact dependency drift
- **Post-fix tendency check** — Step 2.8 in feature-implement queries KB for adversarial-finding entries after each construct passes tests, scanning for known anti-patterns before moving on

### Fixed

- **Prose prompts → AskUserQuestion** — replaced all 50 instances of prose-based interactive prompts ("Type 1 or 2", "Want me to X?", "yes / skip") with AskUserQuestion across architect, curate, decisions, feature-quick, feature-refactor, feature-pr, feature-domains. Prose prompts do not force Claude to stop — only AskUserQuestion does.
- **Architect evaluation guard** — candidate scoring (Step 4b) and falsification (Step 6) now display "analysis in progress — decision is at Step 7" to prevent users from choosing before falsification can revise candidates
- **Narrative generation required** — narrative-wrapper.sh reports failures instead of silently exiting. Retry after 2s for JSONL mid-flush. generate.py/generate.js exit 1 on failure (was always 0). feature-retro Step 6 reports failures with retry command. feature-complete Step 1b attempts generation before archival.
- **MANIFEST sync** — 9 stale audit prompt paths removed, 16 actual files added. install.sh now copies all .md files from skill dirs, all file types from prompts/audit/, installs audit-budget.sh
- **`__pycache__/`** added to target project .gitignore (narrative scripts generate Python bytecache)
- **Status line truncation** — feature slugs capped at 24 chars, construct names at 20 chars to keep stage/tokens/context visible on narrow terminals
- **Session-end prevention** — rule in tdd-protocol.md prevents Claude from suggesting "productive session" stops mid-pipeline. Only AskUserQuestion handoff points offer stopping.
- **curate-scan.sh** — 3 `grep -c` pipefail bugs producing "0\n0" instead of clean integers

### Removed

- Stale `skills/audit/SKILL.md.bak` backup file

---

## [0.12.0] — 2026-04-09

### Added
- **Facet-based research** — `/research "<subject>"` replaces the old
  `/research <topic> <category> "<subject>"` signature. The agent now
  researches first, identifies independent facets for cross-cutting subjects,
  suggests topic/category placement, and the user confirms before anything is
  written. Eliminates placement bias from commissioning context.
- **BM25 KB search** — new `kb-search.sh` script (Python + Node.js + bash
  fallback) provides ranked search over `.kb/` entries. Two-phase ranking:
  coarse over category indexes, enriched with subject frontmatter field weights
  (title/aliases 3x, tags 2x, summary 1.5x). Used by `/research` pre-scan,
  `/kb` query Step 1b, and available to `/curate` for relationship discovery.
- **Cross-linking at write time** — research sessions automatically cross-link
  new articles to each other and update existing entries' `related:` fields.
- **Context hints for callers** — all pipeline callers (`/feature-domains`,
  `/architect`, `/feature-retro`, `/audit`, etc.) pass optional `context:`
  hints describing their commissioning situation without dictating placement.
- **New test suite** — `scenario-kb-search.sh` (13 tests) covering BM25
  ranking, field weighting, Python/Node parity, and edge cases.

### Changed
- All 13 caller skills updated to new `/research` signature.
- `/kb` query Step 1b now uses `kb-search.sh` for mechanical ranking instead
  of LLM-driven keyword scanning (with fallback if script unavailable).
- Research agent identity (`agents/research-agent.md`) and rules
  (`rules/kb-research-agent.md`) updated for facet-first model.

---

## [0.11.0] — 2026-04-09

### Added
- **Spec displacement detection** — `/spec-resolve` detects when new specs
  contradict existing APPROVED specs via mechanical subject-token + antonym +
  keyword matching. Interactive resolution with four choices: accept
  invalidation, narrow new spec, narrow old spec, or defer.
- **Displacement pipeline integration** — accepted displacements flow as
  removal work units through `/feature-plan`, negative displacement tests in
  `/feature-test`, removal awareness in `/feature-implement`, and artifact
  finalization (INVALIDATED marking with cross-references) in `/feature-retro`.
- **Spec revival support** — `/spec-author` detects INVALIDATED specs in
  matching domains and offers them as reference input for fresh authoring.
  New cross-reference fields: `revives` / `revived_by`.
- **New spec frontmatter fields** — `displaced_by`, `revives`, `revived_by`,
  `displacement_reason` with validation in `spec-validate.sh`.
- **Orphaned spec detection** — `/curate` Analysis 14 finds APPROVED specs
  whose subject tokens no longer appear in any source file.
- **New test suites** — `scenario-spec-validate.sh` (8 tests),
  `scenario-spec-resolve.sh` (11 tests), orphaned spec tests in
  `scenario-curate-scan.sh` (4 new, 47 total).

### Fixed
- **subagent-hook.py/.js** — JSON parse failure now cleans up stale
  `.subagent-state` instead of leaving a permanent ghost indicator.
- **token-stop-hook.py** — `stdin.read()` replaced with chunked drain so
  the fast bail check is reachable without buffering all input.
- **statusline.py/.js/.sh** — context percentage normalized to integer
  display across all three languages.
- **token-stop-hook.py** — PID-scoped temp file prevents concurrent stop
  hook collisions.
- **statusline.js** — removed 3 redundant `existsSync` calls, baseline
  write wrapped in try/catch.
- **statusline.js, token-stop-hook.js, subagent-hook.js** — top-level
  try/catch added to guarantee exit 0.
- **token-stop-hook.js** — cold start line counting uses raw Buffer byte
  scan instead of `readFileSync` + `split`.
- **curate-scan.sh** — `grep -c` pipefail bug producing arithmetic errors
  when specs had zero UNRESOLVED markers.

---

## [0.10.0] — 2026-04-08

### Added
- `/feature-harden` — adversarial test hardening phase between test writing
  and implementation. Applies domain lenses (lifecycle, concurrency, boundaries,
  transformation, shared state, routing) to contracts pre-implementation.
  Surfaces spec gaps via [ABSENT] mechanism. Auto-selects skip/lite/full.
- Pre-prove quality gates for `/audit`: `dedup-findings.py` reorders
  dispatch queue for Phase 0 cascade; `check-test-coverage.py` matches
  findings against existing adversarial tests.
- `aggregate-results.py` pre-aggregates prove-fix outputs for report
  subagent (87% cost reduction: 98→20 turns, $44→$5.65).

### Changed
- `/feature-test` chains through `/feature-harden` before `/feature-implement`.
- `/feature-implement` reads `test-plan.md` for intent instead of individual
  test files; writes `implement-summary.md` as handoff for refactor;
  pre-checks `status.md` on resume to skip completed constructs.
- `/feature-refactor` reads `implement-summary.md` for delta awareness.
- `/feature-resume` recognizes hardening stage.
- Exploration prior-round integration hardened: unchanged CLEARED/FIXED
  constructs go to Ignore tier; DEFERRED/Frontier get highest priority.
- Audit report prompt consumes pre-aggregated summaries.

---

## [0.9.0] — 2026-04-07

### Added
- **Capability topology** — hierarchical domain → capability model replacing
  flat entries. Three capability types (core, emergent, refinement) and
  many-to-many feature mapping with roles (core, extends, quality, enables).
  Emergent capabilities capture cross-cutting behaviors from feature composition.
- **`/capabilities` command** — query, list, add, update, and backfill project
  capabilities organized by domain. Domain-aware navigation and search.
- **`/decisions roadmap`** — cluster, classify, and prioritize deferred
  decisions into an actionable roadmap with dependency analysis.
- **Budget-aware audit pipeline** — dollar cap on prove-fix loop with
  proportional allocation across findings. Remaining findings marked DEFERRED.
  Resume filters already-processed findings.
- **Phase 0 already-fixed check** — mandatory pre-flight in prove-fix subagent
  reads current source before test writing. Short-circuits cascade impossibles
  in ~2 turns instead of ~35. Validated: 31 ALREADY_FIXED in engine-clustering.
- **Orchestrator context optimization** — extract-findings.sh + reconciliation
  return format reduces context growth by ~19K tokens per audit.
- **HTML narrative renderer** — audit visualization pipeline with dashboard-style
  static views, session replay, cost/bug metrics, and severity breakdowns.
- **Curate audit feedback** — /curate picks up deferred spec updates and KB
  patterns from audit feedback loop.

### Changed
- **AskUserQuestion standardization** — all 28 interactive prompts across 11
  files converted from text menus to AskUserQuestion tool calls.
- **Architect adversarial hardening** — 6 changes from aTDD research: scope
  verification, constraint falsification, inline score falsification,
  prior-scores-not-evidence, REQUIRED annotations, write-and-justify checklist.
- **Curate cross-reference repair** — Analysis 11 in curate-scan.sh detects
  KB tag overlap, applies_to overlap, and ADR eval→KB source gaps.

### Fixed
- Feedback loop uses AskUserQuestion for forced pause instead of text "STOP"
- Resume skips already-processed findings instead of re-running all
- Resume prompt shows remaining findings count, not total
- Budget prompt uses AskUserQuestion instead of "press Enter"
- Feedback loop menus display sequentially, not simultaneously
- Phase breakdown rows link to stage sections for navigation
- Aggregate phase breakdown by stage type, not per-phase rows
- Cost/bug and total cost visible in audit hero + impact summary

---

## [0.8.0] — 2026-04-03

### Added
- **Combined prove-fix pipeline** — merged Prove + Fix stages into single
  per-finding subagent. Serial dispatch with fix cascade deduplication,
  budget control, and resume support. Validated on 3 jlsm features: $7-11/bug
  for detection + regression test + source fix.
- **`/spec` command** — unified spec query, gap discovery, and change impact
  analysis. Natural language input, discovers matching requirements across all
  specs, traces downstream impact of proposed changes.
- **`/audit` command** — renamed from `/feature-audit`. Adversarial audit
  pipeline with prove-fix model, test cleanup phase, spec conflict detection.
- **Spec extraction mode** — bottom-up spec authoring from existing
  implementation. Auto-discovers source files, consuming specs, and tests.
  Cross-references for CONTRADICTED, UNGUARANTEED, MISSING findings.
- **Spec conflict detection pipeline** — spec-resolve checks contradictions
  between included specs. feature-plan blocks on conflicts, feature-test
  marks UNTESTABLE, feature-implement diagnoses spec conflicts in test failures.
- **[ABSENT] requirement lifecycle** — extraction mode surfaces behaviors code
  doesn't have. Promote (becomes implementation work), preserve (becomes
  negative requirement), or defer (/curate resurfaces later).
- **Fix-spec conflict resolution** — audit report detects when fixes contradict
  spec requirements. Three options: keep fix + update spec, revert fix, defer.
- **Ambiguous spec detection** — spec-author Pass 2c catches "either/or"
  requirements. Job 3b detects contradictory test interpretations of same
  requirement.
- **Test cleanup phase (Job 3b)** — updates stale pre-existing tests after
  audit fixes, classifies failures as STALE, SPEC AMBIGUITY, or REGRESSION.
- **Curate spec awareness** — 4 new signal types: unspecified shared types,
  open obligations, spec-code drift, undecided [ABSENT] requirements.
- **Multi-language parity** — bash + Node.js implementations of reconcile-cards
  and extract-views pipeline scripts, plus wrapper scripts for runtime detection.
- **Architect falsification pass** — mandatory subagent between scoring and
  deliberation that challenges scores, tests rejections, exposes assumptions.
- **KB confidence field** — high/medium/low on research entries, surfaced
  during architect scoring.
- **Audit feedback loop** — reconcile-findings generates spec-updates.md and
  kb-suggestions.md from audit results.

### Changed
- **Spec integration into /feature flow** — routes through spec-author →
  spec-write after domain analysis when .spec/ exists. Backwards compatible.
- **/feature-test** — Lens A operationalizes .spec/ requirements in spec mode,
  falls back to inline analysis. Lens B spec-aware with SPEC-BOUNDARY,
  BLIND-SPOT, IMPL-RISK finding tags.
- **/feature-plan** — loads specs as primary context. Blocks on spec conflicts.
- **/feature-implement** — detects spec conflicts in test failures, escalates
  to spec-author instead of misdiagnosing as test/contract bugs.
- **/feature-refactor** — delegates to /audit instead of removed pass-based
  pipeline prompts.
- **Spec-author Pass 2** — prove/disprove framing requires concrete attacks,
  not bare assertions. Burden of proof on disproof.
- **Concurrency lens** — card construction captures thread_sharing evidence
  (none/possible/explicit). Suspect has mandatory concurrency clearings.
  Domain pruning excludes single-threaded constructs. Validated: 0 false
  positives across 2 audits.
- **DRAFT specs with unresolved conflicts** blocked from resolved context bundles.
- **/vallorcine-help** — all new commands documented, pipeline description
  updated to 9 steps.

### Fixed
- **Prove-fix edit persistence** — mandatory re-read before edits, verification
  after compile, diff in output. Fixes data loss where serial agents overwrote
  earlier agents' changes.
- **Test timeout isolation** — individual method runs to isolate hanging tests.
  Applied to prove-fix, feature-implement, feature-test.
- **API error retry** — prove-fix orchestrator retries once on 500/timeout,
  then marks DEFERRED and continues.
- **Script hardening** — ~55 fixes across 27 scripts (bash/Python/Node):
  atomic writes, exit 0 guarantees, pipefail safety, empty array guards,
  'use strict', sorted→max optimization.
- Report.md suspect file glob pattern (parallel-era assumption cleanup).

---

## [0.7.0] — 2026-03-25

### Added
- **Spec analysis pre-pass** — `/feature-test` Step 1c analyzes work-plan contracts
  across two lenses (contract gaps + implementation risk patterns) before writing tests.
  Generates defensive test vectors that prevent bugs from being written rather than
  finding them after implementation. Reads adversarial KB entries from prior features.
- **Adversarial audit loop** — `/feature-refactor` Step 4b runs a post-implementation
  audit pass: re-analyzes implementation code, writes targeted adversarial tests, and
  fixes confirmed bugs with fix-forward scanning. First loop runs automatically;
  additional rounds require user approval for cross-construct bugs.
- **Spec Analyst agent** (`spec-analyst-agent.md`) — both-lens analysis identity for
  the audit pre-pass and post-implementation audit.
- **Breaker agent** (`breaker-agent.md`) — adversarial test writing identity.
- **KB adversarial-finding template** — persists bug patterns across features so each
  audit makes the next one smarter.
- **KB feature-footprint template** — condensed feature records for cross-reference
  during domain analysis.
- **aTDD research data** — full methodology, experiment harness, and validation results
  in `aTDD-research/`. Documents why each pipeline change was made.

### Changed
- **Unified pipeline model** — one pipeline with configurable audit depth replaces the
  tier model. `/feature-quick` = 0 audit loops, `/feature` = 1 loop (default), complex
  features = user-approved additional rounds.
- **Code Writer agent** — fix-forward rule: after fixing a bug, scans all other constructs
  for the same anti-pattern.
- **Refactor agent** — assert-only validation check, silent exception swallowing check,
  known_issues.md awareness for structural invariants.
- **Test Writer agent** — reads adversarial KB entries during defensive vector generation.
- **Domain Scout** — surfaces feature footprints during `/feature-domains`, silently
  passes adversarial findings through to test phase.
- **Feature retro** — graduates adversarial findings and feature footprints to `.kb/`.
- **TDD protocol** — 5-minute Bash timeout on all test execution.
- **Pipeline timeouts** — aligned across `/feature-coordinate`, `/feature-implement`,
  `/feature-test`.
- **README** — updated pipeline diagram showing audit pass and KB feedback loop.
- **`/vallorcine-help`** — updated pipeline descriptions with spec analysis and audit.

### Validation
Validated on 3 jlsm features. Combined pipeline is 3.7x cheaper than original TDD on
the largest feature (encrypt-memory-data: 47 files, 17.7M vs 64.9M tokens) with zero
post-implementation audit bugs. Spec analysis prevents bugs rather than finding them.

---

## [0.6.0] — 2026-03-20

### Design evolution
- **Principle 1 evolved: bash-first, zero required dependencies** — previously "bash
  and markdown only" as a hard constraint. Relaxed to allow enhanced Python and
  JavaScript implementations under strict rules: every feature must have a bash
  fallback, both runtimes must be supported if either is, and detection/degradation
  must be automatic. The core kit remains bash and markdown — enhanced implementations
  are permitted only when bash cannot fully serve the need (platform constraint or
  practical constraint). This change enables shipping the narrative pipeline and
  multi-language hooks as part of the kit rather than requiring external tools.

### Added
- **Narrative pipeline in `/feature-retro`** — 3-stage pipeline (tokenizer → parser
  → renderer) generates polished `narrative.md` with shields.io badges, Mermaid gantt,
  progressive disclosure, and phase-by-phase breakdowns. Full Python + JavaScript
  parity with graceful degradation. 16 scenario tests.
- **ADR out-of-scope extraction** — `curate-scan.sh` Analysis 9 extracts "What This
  Decision Does NOT Solve" items from confirmed ADRs. `/curate` presents findings and
  offers to create deferred stubs. `/architect` Step 6c auto-creates deferred stubs
  going forward. 8 new tests (41/41 passing).
- **Architect iterative research** — Step 4c commissions targeted follow-up research
  when initial candidates don't adequately cover constraint dimensions. Up to 3
  research iterations total.
- **Architect composite candidates** — Step 4b2 identifies when combining two
  candidates would satisfy constraints better than either alone.
- **`/decisions revisit`** — replaces `/decisions review`. Accepts topic/description
  search, conversational "why" step, revision condition checking against current
  codebase, and `/feature` kickoff after revision.
- **Enhanced status line + token tracking** — Python and Node.js implementations
  alongside bash. Runtime detection wrappers. Subagent visibility via SDK hooks.
- **Mandatory documentation review in `/release`** — Step 1.5 checks README, EXAMPLES,
  DESIGN, and CONTEXT against changes before drafting release notes.

### Changed
- **`/setup-vallorcine`** absorbs `/feature-init` — single bootstrap command
  initializes KB, decisions, feature pipeline, project profile, and .gitignore.
- **Architect neutral presentation** — non-negotiable rule: never express a preference
  or declare a winner before Step 6a deliberation.
- **Disabled auto code review workflow** — `claude-code-review.yml` switched to
  manual trigger only.

### Fixed
- Crash-safe history archive — write before remove in decisions archival
- Trailing phases from other features bleeding through after retro/complete
- Crashed subagent idle time double-counting prior user wait gap
- Subagent idle tracking collisions (now keyed by tool_use_id)
- Mermaid gantt overflow for features >24h
- Corrupt `.meta.json` files crashing session tokenization
- Shields.io badges breaking on hyphenated model names
- 33 parser/tokenizer bugs documented and fixed

### Removed
- `/feature-init` — consolidated into `/setup-vallorcine`
- `/decisions review` — consolidated into `/decisions revisit`
- `tools/showcase/` — retired old pipeline; replaced by `scripts/narrative/`

---

## [0.5.3] — 2026-03-18

### Fixed

- **Token tracking** — stop hook now logs the final stage's tokens before
  cleaning up on terminal states (pr/created). Previously, refactor and
  sometimes implementation showed "—" in the token summary.
- **Statusline log pollution** — statusline no longer writes 4-column
  context-token rows to token-log.md. Token logging is now exclusively
  handled by the stop hook (transcript-based, more accurate).
- **Terminal double-logging guard** — hook firing twice after reaching
  terminal state no longer creates duplicate entries.

### Added

- **Claude Code GitHub Actions** — `@claude` mention support in issues
  and PR comments, plus automated code review on every PR.
- **GitHub issue templates** — structured bug report and feature request
  forms mapped to vallorcine's five concerns.
- **14 token tracking regression tests** — stage transitions, terminal
  handling, statusline isolation, cold start, and log format consistency.

### Changed

- **COMPETITIVE.md** — full rewrite with three-tier framing, 15+
  competitors profiled, head-to-head comparison table, and confirmed
  gaps analysis.
- **Plugin metadata** — author updated to Telefrek, added repository
  and homepage fields.
- **README** — added self-hosted marketplace install option.

---

## [0.5.2] — 2026-03-18

### Fixed
- **Token actuals in status.md** — stop hook now updates the Actual Tokens column
  in the Stage Completion table on stage transitions. Previously always showed "—".
- **Feature finalization moved to `/feature-pr`** — archive manifest, `.feature/CLAUDE.md`
  update, and knowledge/decisions file commits now happen before PR creation (Step 5),
  not post-merge in `/feature-complete`. Prevents uncommitted feature artifacts from
  being lost or leaking into the next feature's PR.
- **PR Step 0.5 separates feature vs upgrade changes** — `.decisions/` files
  (CLAUDE.md, history.md) correctly identified as feature-produced. `.claude/` files
  flagged as upgrade artifacts with recommendation to commit separately.

### Changed
- `/feature-complete` stripped to post-merge directory move only. No more data
  operations that could be skipped or forgotten.

---

## [0.5.1] — 2026-03-18

### Added
- **Research signal recognition in scoping** — uncertainty patterns ("I don't know",
  "not sure") captured as Research Commissions in the feature brief. Domain scout
  auto-commissions `/research` for each.
- **ADR Pressure** — `/curate` detects decisions with 2+ constrained files actively
  changing, reports pressure percentage for re-evaluation.
- **ADR Gravity** — `/curate` detects unconstrained files co-changing with
  ADR-constrained files, revealing implicit relationships. High gravity (5+ files)
  flags isolation problems for `/architect` boundary review.
- **Hub Files** — `/curate` flags files co-changing with 3+ ADRs' constrained areas
  as fragility/test-coverage concerns. Test files excluded from gravity signals.
- **Research fetch discipline** — research agent moves on after ~30s on hung fetches,
  3 sources sufficient, no retries in same session.

### Fixed
- `grep -cxF` under `set -e` produced dual output breaking gravity detection in
  curate-scan.sh.

### Changed
- `/decisions backfill` subsumed by `/curate` — analyses 3b-3d + analysis 8 cover
  all backfill signal sources.

---

## [0.5.0] — 2026-03-18

### Added
- `/curate` command — codebase quality review with correlation engine
  - 8 scan analyses: churn, co-change, artifact correlation, orphaned areas,
    KB staleness, ADR revisit, test-source drift, backfill candidates
  - Numbered pick list for conversational triage
  - Loop behavior: always returns to remaining items after each action
  - Incremental scanning (delta from last-scanned SHA)
  - Scale safety: 500-commit cap, 3-month default window
- `index-verify.sh` — self-healing index verification for crash recovery
- Pre-PR commit verification — `/feature-pr` scans for untracked KB/ADR files
- `/upgrade-vallorcine` auto-commit — kit changes committed as standalone `chore:`
  commit, stashes in-flight staged changes
- Runtime file gitignore — installer adds runtime files to user's `.gitignore`
- Script permissions — installer pre-approves vallorcine scripts in `settings.json`
- `files:` and `applies_to:` frontmatter fields on ADR and KB templates
- Construct analysis derives structural tests from stub interfaces
- Coverage checklist added to test writer to reduce refactor escalations
- 36 new tests (24 curate scan + 12 index verify)

### Changed
- Architecture model expanded from four concerns to five (added Curation)
- `/decisions backfill` consolidated into `/curate` as a scan analysis
- Documentation updated: DESIGN.md, README.md, plugin/marketplace descriptions

### Fixed
- Seed files no longer overwritten by FORCE_UPDATE or version mismatch auto-force
- `/feature-complete` now checks for untracked `.kb/` and `.decisions/` files

---

## [0.4.4] — 2026-03-17

### Changed
- Speed mode coordinator uses completion-driven loop instead of batch-wait.
  Units launch as soon as their dependencies resolve — no waiting for unrelated
  units in the same batch to finish. Minimizes wall-clock time on the critical path.
- Balanced mode retains batch-wait behaviour for predictable checkpoints.
- Dependency graph display now shows critical path and max parallelism.
- Architect prompts user on KB coverage gaps before evaluating decisions.

---

## [0.4.3] — 2026-03-17

### Fixed
- Status line now detects stage transitions during chained sub-agent execution
  by reading actual stage from `status.md` instead of relying on Stop hook
- Per-stage token usage logged to `token-log.md` automatically on stage
  transitions, even when stages chain without returning to the user

---

## [0.4.2] — 2026-03-17

### Fixed
- Status line per-stage token tracking now uses context window delta
  (`used_percentage * context_window_size`) instead of `total_input_tokens`
  which barely changed between status line fires
- Added substage display for all pipeline stages (scoping, planning, testing,
  implementation, refactor, PR) — not just refactor

---

## [0.4.1] — 2026-03-17

### Added
- Status line (`scripts/statusline.sh`) — shows feature slug, pipeline stage,
  total tokens, and context window % with color-coded warnings (green/yellow/red)
- Token tracking Stop hook (`scripts/token-stop-hook.sh`) — auto-detects stage
  transitions and logs to `token-log.md` without any skill-level bash calls
- `/uninstall-vallorcine` command + `scripts/uninstall.sh` — manifest-based
  removal with safety guard, `--dry-run` preview, settings/git cleanup, self-delete
- Domain scout KB empty check — offers research/continue/skip-research when KB
  has zero topics, with `skip_all_research` flag to suppress per-domain prompts
- Version display in `/vallorcine-help` headers (reads `.vallorcine-version`)
- Plugin vs shell install path documentation in README with comparison table

### Changed
- Install registers Stop hook + status line in `settings.json` automatically
- Uninstall cleans up token hook and status line from `settings.json`
- Install auto-removes stale `.claude/commands/<name>.md` when matching skill exists

### Removed
- Tmux dashboard (`/dashboard` skill, `dashboard-state.sh`, `dashboard-stop-hook.sh`,
  3 watcher scripts, `watchers/` directory) — retired in favor of status line + hooks
- All dashboard bash blocks from 9 pipeline skill files
- All `token_checkpoint` and `token_summary` bash blocks from 8 skill files
- `commands/` directory — 23 stale pre-migration files deleted from repo
- Dashboard test file (`test-dashboard.sh`, 14 tests)

### Fixed
- Unsafe `source` of state files — values now properly escaped with `printf '%q'`
- Redundant `jq` forks in stop hook (5→1) and statusline (2→1)
- Non-numeric guards on context percentage and token formatting
- Migration cleanup for pre-0.4.0 upgraders (duplicate slash commands)

---

## [0.4.0] — 2026-03-17

### Added
- Tmux dashboard with two panes: pipeline progress and stage detail
- `vallorcine_theme.sh` — shared icon/color palette for dashboard
- `vallorcine_pipeline.sh` — pipeline pane watcher (7 stages, token spend, alerts, progress bar)
- `vallorcine_stage-detail.sh` — stage detail pane watcher (tasks, artifacts, timestamp, interrupt hint)
- `dashboard-state.sh` — 12-function helper library for agents to write dashboard state
- `dashboard-stop-hook.sh` — Stop hook for live token counter during active stages
- `/dashboard` command (launch/off/on) with once-per-session tmux hint
- Dashboard state calls in all 7 pipeline commands (stage start + complete)
- `.claude/dashboard/` gitignore entry in `/feature-init`
- `test-dashboard.sh` — 23 tests for watchers, state helpers, install, and pipeline integration

### Changed
- Migrated all 23 slash commands from `.claude/commands/*.md` to `.claude/skills/<name>/SKILL.md`
- Added YAML frontmatter (description, argument-hint) to all skills
- `install.sh` installs skills instead of commands
- MANIFEST updated to `.claude/skills/` paths
- Upgrade safety guard includes `.claude/skills/*` and `.claude/watchers/*` prefixes
- Old `.claude/commands/*` files cleaned up on upgrade via stale removal
- Watcher files prefixed with `vallorcine_` to avoid namespace collisions
- Reframed project descriptions: "A reliable engineering partner for Claude Code"
- Updated README, DESIGN.md, marketplace.json, plugin.json with new positioning
- Added `/dashboard` to System commands table in README

---

## [0.3.4] — 2026-03-17

### Added
- TodoWrite two-tier progress checklists across all TDD pipeline commands
  (feature-plan, feature-domains, feature-coordinate, feature-test,
  feature-implement, feature-refactor, feature-resume)
- Pipeline-level progress (scoping → PR) visible in every command
- Stage-level granularity: per-test, per-construct, per-domain, per-refactor-check
- `activeForm` for real-time detail on in-progress items
- Parallel mode: coordinator owns TodoWrite, polls per-unit status.md
- `/ideate` Step 1.5: writes WIP.md immediately for crash recovery
- Upgrade safety guard: prefix allowlist for stale file removal
- Regression test for upgrade safety (test 9, 5 assertions)
- Delegate stub creation and work-plan assembly to subagent for context isolation
- Architect auto-resumes paused feature after decision is confirmed

### Changed
- `/feature-pr` now prompts for `/feature-retro` after PR creation (yes/skip)
- `/feature-resume` offers "Type **yes**" prompt for PR drafting and retrospective

### Fixed
- `install.sh` missing `adr-validate.sh` (was in MANIFEST but not installed)
- `/feature-resume` mapped `refactor/complete` to `/feature-complete` instead
  of `/feature-pr` — now correctly routes through PR drafting first

---

## [0.3.3] — 2026-03-16

### Added
- ADR-informed candidate ranking in `/architect` Step 4. When a KB category has
  >8 entries, reads scoring data from related ADRs to prioritize which subject
  files to load. High scorers and new/unranked entries load first. Low scorers
  deprioritized but available on request. Saves 25-40K tokens on large categories.
- ADR staleness signal: when new KB entries exist that a related ADR never
  evaluated, the Architect flags it for potential `/decisions review`. Closes
  the loop between new research and existing decisions.

---

## [0.3.2] — 2026-03-16

### Added
- Cross-topic keyword scan in `/architect`, `/kb query`, and `/feature-domains`.
  KB discovery now searches across all category indexes for tangentially related
  entries, not just top-down navigation. Catches research in unexpected
  topics/categories. ~1-2K token cost.

### Fixed
- `upgrade.sh` — removed python3 dependency for JSON parsing. Uses plain text
  `gh` output and sed/grep for API responses. Principle 1 compliance.
- `research.md` — hardcoded year range (2024/2025) replaced with relative
  `<current_year - 1> OR <current_year>`.

---

## [0.3.1] — 2026-03-16

### Added
- **Principle 1: bash-first, zero required dependencies** — new top-priority
  design principle. No feature may require anything beyond bash and markdown.
  Enhanced Python/JS implementations permitted under strict rules (see DESIGN.md).
- **Refactor step 2h: security review** — holistic security audit after all
  other refactoring. Checks auth, data handling, trust boundaries, dependencies,
  and threat surface delta. HIGH/MEDIUM/LOW severity. Always pauses on findings.
- **ADR contradiction check** (`scripts/adr-validate.sh`) — pre-flight script
  warns when duplicate accepted slugs exist. Added to pipeline pre-flight checks.
- **Backfill file threshold** — `/decisions backfill` requires explicit path on
  projects over `backfill_file_threshold` (default 50, configurable in
  project-config.md).
- `tests/scenario-adr-contradiction.sh` — 10-case regression test for ADR
  contradiction detection.

### Changed
- Design principles renumbered 1-10 by priority with violation consequences
  documented. Structural constraints (1-3) > correctness (4-7) > workflow (8-10).
- Refactor checklist updated from 7 items (2a-2g) to 8 items (2a-2h).
- DEFERRED.md reorganized into active/dropped/done sections.
- COMPETITIVE.md gaps updated — hooks, coverage gating, Context7 dropped
  as principle 1 violations.
- Open questions prioritized into four tiers (do next / do soon / when needed /
  when scale demands).

### Resolved
- Command name collision audit — zero collisions across 22 commands vs 45
  Claude Code built-ins.
- setup-vallorcine / feature-init merge — settled as separate (four-concern
  model boundary).
- install.sh --run-tests — dropped (tests are for plugin development only).
- KB depends-on field — deferred (P2/P3 tension, premature at current scale).

---

## [0.3.0] — 2026-03-16

### Added
- Parallel work unit execution with `/feature-coordinate` batch coordinator
- Execution strategy prompt (cost/balanced/speed) in `/feature-plan`
- Per-unit file isolation (`units/WU-N/`) for parallel subagent safety
- `/decisions backfill` — retroactive decision extraction from archived features and source structure
- `/decisions list` — browse and filter all decisions by status and keyword
- `/decisions explain "<slug>"` — plain-language ADR summary with KB context
- `/decisions candidates` — review decisions discovered from session transcripts
- `/feature-retro` — post-feature retrospective (scope, assumptions, domains, tokens, TDD efficiency)
- `/feature-cleanup` — interactive stale feature directory management
- `/project-context` — team-shared codebase knowledge with 90-day expiry
- `/vallorcine-help` answers plain-text questions about commands
- `install.sh --diff` — preview changes without writing
- Token estimate vs actual tracking in status.md Stage Completion table
- Dependency topology view in `/feature-resume` with batch info
- Refactor agent step 2g — documentation check

### Changed
- Domain Scout auto-invokes `/architect` and `/research` as sub-agents inline
- Domain Scout classification tightened: `resolved` requires actual ADR
- Draft ADRs display as warnings in domain analysis, don't block
- `/feature-resume` auto-invokes `/feature-domains` when scoping complete
- Renamed `/quick` to `/feature-quick` for naming consistency
- README restructured around four-concern model (knowledge, decisions, features, system)
- DESIGN.md updated with four-concern architecture description

### Fixed
- `install.sh` auto-forces update on version mismatch (bootstrapping fix)
- Standardized all prompts to "Type **yes**" pattern
- `/release` push and changelog prompts use consistent format

---

## [0.2.3] — 2026-03-16

### Added
- `/decisions backfill` — retroactive decision extraction from archived features
  and source structure. Surfaces implicit decisions for decide/draft/defer/dismiss.
  Scoped by path, incremental (default 5 per session), dismissed items don't
  resurface.
- `/vallorcine-help` answers plain-text questions about commands and workflows
  ("how do I resume a feature?") in addition to interactive routing

### Changed
- `/feature-domains` now auto-invokes `/architect` and `/research` as sub-agents
  when gaps are found, instead of deferring to manual user action
- Domain Scout classification tightened: `resolved` requires an actual ADR in
  `.decisions/`, not the scout's own reasoning. Design choices without an existing
  ADR are classified as `pending-decision` and routed to the Architect Agent.
- Draft ADRs (`status: draft`) display as warnings in domain analysis but do not
  block
- `/feature-resume` auto-invokes `/feature-domains` when scoping is complete

### Fixed
- `install.sh` auto-forces update on version mismatch, fixing the bootstrapping
  problem where a broken `upgrade.sh` could never be patched
- `/release` push and GitHub Release prompts use "Type **yes**" pattern
- Standardized remaining "confirm to proceed" prompts in feature-domains

---

## [0.2.2] — 2026-03-16

### Added
- Parallel work unit execution with batch coordinator (`/feature-coordinate`)
- Execution strategy prompt (cost/balanced/speed) in `/feature-plan`
- Per-unit file isolation (`units/WU-N/`) for parallel subagent safety
- Parallel-aware display in `/feature-resume` with batch grouping
- Per-unit change grouping in `/feature-pr` descriptions

### Fixed
- Standardized prompt language to "Type **yes**" across all commands
  (feature-domains, feature-init, kb, quick, research, upgrade-vallorcine)

---

## [0.2.1] — 2026-03-16

### Fixed
- `upgrade.sh`: `gh release` commands failed when `.vallorcine-source` contained
  an SSH URL (`git@github.com:owner/repo.git`). Added normalization to convert
  both SSH and HTTPS URLs to `OWNER/REPO` format before passing to `gh`. Also
  updated `.vallorcine-source` to write HTTPS URLs by default.

---

## [0.2.0] — 2026-03-16

### Added
- **Pre-flight checks** — three advisory scripts run at every pipeline command
  start: version skew warning, index merge driver auto-setup, KB/decisions
  freshness check against main branch
- **Index merge driver** — custom git merge driver for `.kb/CLAUDE.md` and
  `.decisions/CLAUDE.md` that auto-resolves concurrent table row additions by
  keeping all rows from both sides. Scoped via `.gitattributes` to only
  vallorcine-managed index files — never affects user code
- **KB staleness detection** — `/kb "<question>"` checks entry age against
  configurable threshold (default 90 days in project-config.md), warns on stale
  entries, and offers to invoke `/research` as sub-agent inline for gaps or
  outdated data
- **Per-phase token tracking** — `scripts/token-usage.sh` reads Claude Code
  session JSONL to track actual token consumption per pipeline phase. Integrated
  into all 8 pipeline commands and `/feature-resume`
- **Scenario test suite** — 6 scenario tests (53 assertions) covering
  project-config conflicts, version skew detection/resolution/warning, merge
  driver with/without, auto-setup, and stale KB detection. All tests use
  `/tmp/vallorcine/*` paths for permission pre-granting
- **"Known team issues" in DESIGN.md** — documents mitigated and unmitigated
  team concurrency risks
- **COMPETITIVE.md** — 7 new competitors added (claude-mem, memsearch,
  claude-cognitive, Claude Code auto-memory, claude-code-workflows, feature-dev,
  Jamie-BitFlight/claude_skills)
- **DEFERRED.md** — 6 new feature ideas from research brief

### Changed
- `/save-work` no longer bumps VERSION — stages changelog notes in
  `.changelog-staging.md` for `/release` to consume
- `/release` syncs README.md version line
- `install.sh --dev` uses temp dir instead of overwriting repo `.claude/`;
  safety guard blocks `install.sh .` from repo root
- `test-install.sh` updated to use `/tmp/vallorcine/` paths

### Fixed
- `install.sh` self-install safety guard prevents overwriting source files
  when run from the vallorcine repo root

---

## [0.1.5] — 2026-03-14

### Fixed
- `upgrade.sh`: when exec'd with `--apply` by the new script, pre-flight
  checks and the full fetch/download/extract block ran unnecessarily against
  the temp extract directory, causing an immediate exit before any files were
  applied; all args are now parsed upfront and both sections are gated behind
  `APPLY -eq 0`

---

## [0.1.4] — 2026-03-14

### Fixed
- `upgrade.sh`: `compare_versions` returns non-zero exit codes (1 and 2) which
  caused `set -e` to terminate the script before the return code could be
  captured — upgrade check always exited prematurely when a newer version was
  available
- `/release`: removed redundant `↵ confirm` step after version bump; all
  auto-proceed steps (push, GitHub release, CHANGELOG confirm) now proceed
  unless the user types `skip` or `edit`, eliminating Enter-to-confirm prompts
  that don't work in Claude Code's chat interface

---

## [0.1.3] — 2026-03-14

### Fixed
- `/feature-resume` now auto-invokes `/feature-plan` when that is the identified next step
- Autonomous mode opt-in moved to `/feature-plan` (before testing begins, not after)
- Crash recovery in autonomous mode auto-resumes without requiring a manual command
- "Hit enter to continue" prompts replaced with explicit "continue" keyword throughout
- `/feature-pr` now creates the PR via `gh pr create` directly, not just a draft file
- `/feature-init` prompts for a feature branch and applies project naming rules

### Added
- Handoff points offer to invoke the next command automatically as a sub-agent
- `DEFERRED.md` for vallorcine local development (pull-model, not loaded every session)
- `MANIFEST` file listing all kit-managed files
- `install.sh` and `upgrade.sh` remove stale files no longer in the kit MANIFEST
- Fail-forward upgrade policy documented in `upgrade.sh` summary output

---

## [0.1.2] — 2026-03-13

- Split CONTEXT.md into three bounded files with version sync
- Add tail-read rule for cycle-log.md to cap token cost
- Add escalation re-entry logic and WIP checkpoint system

---

## [0.1.1] — 2026-03-13

### Changed
- Split CONTEXT.md into three files: CONTEXT.md (active state, bounded),
  SETTLED.md (graduated design history), COMPETITIVE.md (market positioning)
- `/save-work` now graduates aged decisions to SETTLED.md and syncs DESIGN.md/README.md
- `/ideate` skips reference files unless the session goal requires them

---

## [0.1.0] — 2026-03-13

Initial release. Two subsystems: TDD Pipeline and KB/Decisions.

### Added

**TDD Pipeline**
- `/vallorcine-help` — guided entry point, routes to /feature-quick or /feature
- `/feature` — scoping agent with sequential one-question-at-a-time interview
- `/feature-init` — project profile setup with inference from existing project files
- `/feature-domains` — domain scout, commissions research and architect runs
- `/feature-plan` — work planner with token-based work unit split analysis
- `/feature-test` — test writer agent, TDD cycle management
- `/feature-implement` — code writer agent
- `/feature-refactor` — refactor agent with 8-category checklist (2a-2h)
- `/feature-pr` — PR draft generator
- `/feature-complete` — archive and cleanup
- `/feature-resume` — crash recovery from status.md checkpoint
- `/feature-resume --status` — pipeline status display with --share mode
- `/feature-quick` — lightweight single-construct path with complexity assessment
- Escalation chain: Code Writer → Test Writer → Work Planner with 3-strike limits and re-entry logic
- `cycle-log.md` tail-read rule — agents read last 30 lines by default, capping token cost

**KB/Decisions**
- `/research` — Research Agent, writes to `.kb/`
- `/kb topic` — creates new KB topics, maintains .kb/CLAUDE.md Topic Map
- `/kb lookup` — retrieves KB entries on demand
- `/setup-vallorcine` — initialises .kb/ and .decisions/ directories
- `/architect` — Architect Agent with 6-constraint deliberation loop
- `/decisions review` — revisits existing architecture decisions

**Infrastructure**
- Work unit splitting with token-based thresholds (15K crossover)
- `--unit WU-N` flag on inner-loop commands
- Enter-to-proceed prompts throughout (no yes/no required)
- `prompt-conventions.md` always-loaded rules file
- `DESIGN.md` — 9 design principles, structural patterns, token budget
- `CONTEXT.md` — active session context (bounded ~150-200 lines)
- `SETTLED.md` — graduated design history (pull-model reference)
- `COMPETITIVE.md` — market positioning and ecosystem gaps (pull-model reference)
- `RESUME.md` — session start/close instructions
- `install.sh` — idempotent installer, skip-existing, FORCE_UPDATE=1 to overwrite
- `VERSION` file with semver
- `.claude-plugin/plugin.json` — plugin manifest for `/plugin install` native path
- `.claude-plugin/marketplace.json` — single-plugin marketplace for `/plugin marketplace add`
- `/upgrade-vallorcine` — checks source repository for new release tags, shows release notes, downloads and applies with confirmation. Never touches user-generated files.
- `upgrade.sh` — shell script installed into `.claude/upgrade.sh` in target projects. Downloads release zip via gh CLI or curl fallback, applies kit files only, preserves user content.
