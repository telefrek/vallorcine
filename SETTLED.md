# vallorcine — Settled Design History

Stable design decisions that have graduated from active development.
Pull-model: read only when you need the rationale behind a past decision.

*Entries move here from CONTEXT.md Recent decisions once they are no longer
actively being revised.*

---

## Origin and purpose

Built for jlsm (Java 25 LSM-Tree library) as a Claude Code workflow system.
Goal: KB for algorithm research persisting across sessions without polluting
context. Evolved into full two-subsystem kit: TDD pipeline + KB/Decisions.
Reusable package. Install with `bash install.sh`.

## Pull model (not push)

Auto-loading KB via CLAUDE.md @imports rejected: token cost grows every session.
Pull model keeps session start fixed at ~2K forever.
Root CLAUDE.md is pointer-only, never content.

## File-based state over in-memory

In-conversation memory rejected: sessions end, context overflows, restarts happen.
status.md as mutable checkpoint — interruptible and restartable at any point.

## status.md + cycle-log.md separation

status.md: mutable current state. cycle-log.md: append-only history.
Mirrors write-ahead log / event sourcing. Gives idempotency for free.

## Prompted continuation

Rejected fully automatic (loses checkpoints, compounds errors).
Rejected fully manual (user must remember commands).
Prompted continuation: ↵ to continue, spawns sub-agent.

Always pause (high review value): brief→domains, domains→plan, plan→test.
Enter-default: test→implement, implement→refactor, refactor→PR.

## Visual headers and token estimates

`─── EMOJI  AGENT · slug · Cycle N ───` opening, `── Section ────` markers.
Closing footer with token estimate. Purpose: session readability.
Estimates are approximations — Claude Code doesn't expose real counts.

## Consolidated single package

Started as two zips. Consolidated: shared install, Domain Scout depends on KB.

## Idempotency pattern

Read status.md → if complete stop → if in-progress resume → if not-started proceed.

## Write authority partitioning

Each agent writes only to designated files. Escalation paths for cross-domain
problems. Enforced by explicit rules in command files and agent definitions.

## Tests are the specification

Tests written before implementation. Code Writer never modifies tests.
Contract conflicts escalate to Test Writer.

## Context budget as first-class concern

Always-loaded files capped and pointer-only. Index files have 80-line hard caps
with archival. Subject files capped at 200 lines. 15K work-unit crossover is
a direct expression of this principle.

## Human confirmation before irreversible writes

Architect: deliberation loop before adr.md. Scoping: brief confirmation before
brief.md. Cheapest place to catch mistakes.

## Curation as correlation engine (2026-03-18)

Dropped the "concern graph" abstraction in favor of correlating git history
against existing artifacts. Four value buckets: ADR drift, KB+hindsight,
implicit dependencies, orphaned areas. Business objectives can't be inferred
from git history — focus on structural quality signals.

## Curation namespace and state (2026-03-18)

`.curate/` directory (gitignored, per-developer state). `curation-state.md`
for scan state + review log. Numbered pick list for findings — user picks by
number, loop re-presents remaining items, "done" exits. Backfill consolidated
into `/curate` as single entry point.

## Seed files and index self-healing (2026-03-18)

`install.sh` never overwrites user-populated KB/decisions indexes, even with
FORCE_UPDATE. `index-verify.sh` checks directory contents against index rows,
repairs missing entries from crash-interrupted bottom-up updates. Called by
`/curate` before scanning.

## Pre-PR verification and upgrade auto-commit (2026-03-18)

`/feature-pr` Step 0.5 scans for untracked `.kb/` and `.decisions/` files.
`/upgrade-vallorcine` commits kit changes as standalone `chore:` commit with
stash/restore. Explicit per-script permissions in `settings.json`.

## Agents are routers, not autonomy machines

/vallorcine-help is the clearest example: reads context, asks one question, hands a
pre-filled command. Never does pipeline work itself.

## KB topic management via /kb topic

/kb topic command; .kb/CLAUDE.md Topic Map is authoritative live list.
research.md reads it first, offers to run /kb topic as sub-agent if missing.

## Agents own the files (principle 10)

All kit-managed files carry managed-by notices. Manual edits bypass safety checks.

## /feature-quick complexity check

4 signal categories. 0-1: silent. 2-3: soft warning. 4+: hard redirect.

## Work units

Split when single-unit load > 15K AND clean dependency boundary exists.
1-3 never split. Each unit runs own test→implement→refactor cycle.

## Project this was built for

jlsm — pure Java 25 modular LSM-Tree library.
Modules: jlsm-core, jlsm-indexing, jlsm-vector.
Build: Gradle (Groovy DSL). Test: JUnit 5.
Vector indexing work (float16, HNSW, IVF-Flat) drove KB and work-unit design.

## CONTEXT.md rolling structure (2026-03-13)

Problem: flat CONTEXT.md grows unbounded; after many sessions a fresh Claude
spends significant tokens reading stale settled history alongside current state.
Decision: four-section structure with explicit cadences. Current focus and
Recent decisions stay short. Settled design grows but is reference-only.
Rejected: separate files per session (too many files, harder to load cleanly);
timestamp-based pruning (mechanical, loses the why behind decisions).

## Enter to proceed everywhere (2026-03-13)

Original: "type yes/no" for all confirmation prompts.
Problem: unnecessary friction; requiring affirmation words feels form-like.
Decision: Enter always means proceed. Format: `  ↵  action  ·  or type: stop`
Numbered choices (1/2/3) reserved for genuine divergence with no safe default.
Also: prompt-conventions.md as always-loaded 62-line rules file rather than
copying format into every command file (drift risk) or shared on-demand file
(extra read per invocation).

## Sequential scoping interview (2026-03-13)

Original: agent presents all question categories at once (wall of questions).
Problem: shallow answers, worse briefs.
Decision: agent privately ranks unknowns by impact, asks one per turn.
`── Question i of n ──` header. N shifts down if answers resolve multiple
unknowns. 0 questions valid if description is fully specified.

## CONTEXT.md three-file split (2026-03-13)

CONTEXT.md split into three files: CONTEXT.md (active state, bounded),
SETTLED.md (graduated history), COMPETITIVE.md (market positioning).
Different update cadences, different token costs. `/save-work` graduates
aged entries.

## 5-pass analysis pipeline (2026-03-27)

Inventory → triage → clustering → per-cluster deep analysis → reconciliation.
Each pass writes to disk; next pass reads the file, not the conversation history.
416K tokens vs ~1M for equivalent coverage. Validated against 26 known bugs (92%).

## Construct-level clustering (2026-03-27)

Clusters follow data flow and shared state, not file boundaries. `shares_state`
edges are unsplittable within a type. Cross-type bridges defer to reconciliation.
No hard size limits — graph structure determines boundaries.

## Attack-generation framing (2026-03-27)

"What input breaks this?" not "does this look correct?" Per-cell independence
prevents satisficing. Validated: doubled bug detection vs comprehension framing.

## Write-and-return test writers (2026-03-27)

Phase 4 breakers write tests and exit. No compile loops in test writing.
Separate compile-check phase. Eliminates 50% post-write overhead.

## Escalation flags and re-entry logic (2026-03-13)

Full Code Writer → Test Writer → Work Planner escalation chain with
3-strike limits. Re-entry via substage markers (`escalation-resolved`,
`contract-revised`).

## WIP.md crash-recovery checkpoint (2026-03-13)

WIP.md in repo root (gitignored) for vallorcine's own development.
Mutable checkpoint read by /ideate, deleted by /save-work.

## cycle-log.md tail-read rule (2026-03-13)

Agents read only last 30 lines by default. Full reads reserved for
PR draft and feature-complete.

## Autonomous TDD loop mode (2026-03-13)

Opt-in automation chaining implement → refactor → next unit tests.
Missing tests escalation (2e) and structural issues (2c/2d) always pause.

## Plugin system support (2026-03-13)

Plugin manifest alongside shell installer, not replacing it. Plugin path
is lower friction; shell path enables /upgrade-vallorcine.

## GitHub repo structure and versioning (2026-03-13)

Standard layout with README, CHANGELOG, .gitignore, VERSION (semver).
Branch convention: wip/<topic>.

## /release skips bump when VERSION already ahead (2026-03-14)

/release checks latest GitHub release tag. If VERSION > latest, skip bump.
"bump" escape hatch for manual override.

## Branch-based PR workflow (2026-03-14)

All development on wip/<topic> branches, merge via PR. Direct commits to
main reserved for context files and emergency patches.

## VERSION only bumped by /release (2026-03-15)

/save-work stages changelog notes in .changelog-staging.md instead of
touching VERSION. /release is single owner of version bumps.

## install.sh self-install safety guard (2026-03-15)

--dev installs to mktemp -d. Safety guard blocks install to repo root.

## Per-phase token tracking (2026-03-15)

scripts/token-usage.sh reads session JSONL for actual token consumption.
Shell-only, zero token cost. Integrated into all pipeline commands.

## Index merge driver for team concurrency (2026-03-16)

Custom git merge driver for .kb/CLAUDE.md and .decisions/CLAUDE.md.
Auto-resolves concurrent table row additions. Scoped via .gitattributes
to only vallorcine-managed index files. Auto-configured on first pipeline
command via ensure-merge-driver.sh.

## Pre-flight checks at pipeline start (2026-03-16)

Three advisory scripts run before every pipeline command: version-check.sh,
ensure-merge-driver.sh, kb-freshness-check.sh. All silent on success,
never block.

## KB staleness detection in /kb query (2026-03-16)

/kb checks entry age against configurable threshold (default 90 days).
Offers inline /research for gaps or stale entries.

## Domain Scout must not self-resolve (2026-03-16)

`resolved` requires an actual ADR in `.decisions/`. The scout identifies domains
and checks for existing coverage — it does not make architectural decisions.
Design choices without an ADR → `pending-decision`. The scout's own reasoning
that something is "well-understood" does not count as resolution.

## Auto-invoke architect/research from domains (2026-03-16)

Domain Scout launches `/architect` and `/research` as sub-agents inline when
gaps are found. Default is action, skip requires explicit opt-out. Previously
the scout just told the user to run the commands separately.

## install.sh auto-force on version mismatch (2026-03-16)

Detects installed version differs from package version and sets FORCE=1
automatically. Fixes bootstrapping problem where buggy upgrade.sh could
never be patched by either install or upgrade.

## Fail-forward upgrade policy (2026-03-14)

Problem: upgrade.sh now removes stale files; a natural follow-on is rollback support.
Decision: no rollback. vallorcine follows a fail-forward policy — if an upgrade
introduces a problem, the fix is to upgrade again to a patched release.
Rationale: commands are markdown prompt files, not compiled code or user data.
A bad upgrade is annoying but not catastrophic. Rollback requires storing the
old manifest + old file contents, and removing new files while restoring old ones
risks leaving the system in a worse mixed state — especially for user-preserved
files. Escape hatch: `bash .claude/upgrade.sh --version vX.Y.Z` pins to any
released version. Noted in upgrade.sh summary output.
Rejected: snapshot before upgrade (storage overhead, point-in-time problem);
git-based restore (not all projects version .claude/).

## Four-concern architecture model (2026-03-16)

vallorcine organised around Knowledge (/kb, /research), Decisions (/architect,
/decisions), Features (/feature-*), and System (/vallorcine-*, /project-context).
README and DESIGN.md restructured to match. Commands named by concern.

## /quick → /feature-quick rename (2026-03-16)

Aligns with feature-* naming convention. All 12 files with references updated.

## Refactor steps 2g (documentation) and 2h (security review) (2026-03-16)

2g: refactor agent verifies project docs stay current after feature changes.
2h: holistic security audit — auth, data handling, trust boundaries, dependencies,
threat surface delta. HIGH/MEDIUM/LOW severity. Always pauses on findings.

## Principle 1 evolved: bash-first, zero required dependencies (2026-03-19)

Originally "bash and markdown only" as a hard constraint (2026-03-16). Relaxed
to allow enhanced implementations in Python and JavaScript under strict rules:
no feature may exist only in Python/JS, both runtimes must be supported if
either is, detection and degradation must be automatic. Bash remains the
reference implementation for every feature.

Two justifications clear the bar: (1) platform constraints — bash cannot access
the data (e.g., Claude Code SDK hooks expose subagent activity that shell hooks
cannot see), (2) practical constraints — bash implementation would be too
degraded to serve its purpose (e.g., processing hundreds of MB of JSONL through
tokenization and AST construction). The third-party tool test is the tiebreaker:
if the alternative is "download this external tool," ship it in the kit with
graceful degradation instead.

Previous entry preserved the spirit — zero adoption friction — but blocked
useful tooling that could ship as part of the kit rather than requiring external
dependencies.

## Draft ADRs warn but don't block (2026-03-16)

Domain Scout classifies draft ADRs as pending-decision with a warning.
User can proceed or formalize via /decisions review.

## Decision candidates from transcript scanning (2026-03-16)

PostSessionEnd hook stages candidates in .decisions/.decision-candidates.
Notices surface at /feature-domains and /feature-resume.

## PROJECT-CONTEXT.md for team knowledge (2026-03-16)

Committed file at project root. 90-day expiry, scoped entries, 50-entry cap.
/project-context command (not /context — that's a Claude Code built-in).

## TodoWrite two-tier progress tracking (2026-03-17)

Pipeline-level checklist (scoping → PR) in every command, plus stage-level
granularity (per-test, per-construct, per-domain, per-refactor-check). Uses
`activeForm` for real-time detail. Coordinator owns TodoWrite in parallel
mode; subagents skip it.

## /ideate writes WIP.md immediately (2026-03-17)

Step 1.5: after determining session goal, write WIP.md before reading context.
Prevents losing session state on crash. Appends if WIP.md already has in-flight
work.

## Upgrade safety guard: prefix allowlist (2026-03-17)

Stale file removal only operates on known kit-managed prefixes. Non-kit paths
in a corrupted manifest are skipped with a warning. Regression test covers
5 assertions for user file preservation.

## Tmux dashboard: tried and retired (2026-03-17)

Built a tmux-based dashboard with pipeline progress + stage detail panes. State
in `.claude/dashboard/`, watchers polling `stage.json`, agents writing state via
`dashboard-state.sh` bash calls.

**Why it failed:**
- Every dashboard state update required a bash command that the user had to approve
  — added friction and token cost for a side effect, not the main work
- Dashboard instructions in skill files are markdown hints that sub-agents skip —
  unreliable by design
- Tmux panes compete with the main interaction for screen real estate; at narrow
  widths the pipeline pane crushed to 1 char wide
- Watchers flickered (1s poll fallback without inotifywait)
- If you're not in tmux, 100% of the dashboard cost is pure waste
- Fundamentally: building a UI layer on top of a CLI tool fights the medium

**What replaced it:** Claude Code's native task system for pipeline position,
status line for lightweight activity signals. Zero infrastructure, zero approval
cost, works everywhere.

**Lesson:** Principle 1 (bash-first, zero required dependencies) extends to UX
— don't build custom UI when the host tool already has the right primitives.

## Skills migration (2026-03-17)

All 23 commands moved from `.claude/commands/*.md` to `.claude/skills/<name>/SKILL.md`.
YAML frontmatter (description, argument-hint). Slash command names unchanged.
`commands/` directory deleted from repo. Install auto-removes stale command files
when matching skills exist.

## Watcher files prefixed `vallorcine_` (2026-03-17)

Prevents namespace collisions if users have their own dashboard watchers.

## Project positioning: "reliable engineering partner" (2026-03-17)

Reframed all descriptions away from mechanical feature lists. Lead with trust
and ease of use, not TDD pipeline internals. Tagline: "ship features that make
the next one faster."

## Dashboard is a feature pipeline tool (2026-03-17)

Research and architect sessions are conversational and interactive — no pipeline
progress panes needed. Dashboard shows idle/empty state gracefully. Intent
surfacing (separate concern) benefits all commands.

## Always work from branches, merge via PR (2026-03-17)

Never commit directly to main. Kebab-case branch names. Prompt for confirmation
if user asks to bypass.

## Never guess estimates (2026-03-17)

If we don't have real data, show "unknown" rather than made-up numbers. Applies
to token budgets, progress bars, and all forward-looking displays.

## setup-vallorcine and feature-init remain separate (2026-03-16)

Originally considered merging both into a single command (both are one-time setup).
Rejected after the four-concern architecture model made the boundary clear:
/setup-vallorcine creates Knowledge + Decisions infrastructure (.kb/, .decisions/).
/feature-init creates Features infrastructure (.feature/, project-config.md).
A project may use KB/Decisions without the feature pipeline, or vice versa.
Merging would force users of one concern to configure the other.

## Command naming review — no collisions, no renames (2026-03-17)

Reviewed all 23 commands against 60+ Claude Code built-ins. Zero hard collisions.
Soft risk: `/kb`, `/research`, `/architect`, `/decisions` are generic names that
another plugin could claim. Plugin install path already namespaces these as
`vallorcine:kb` etc. Shell install keeps short names for usability. Not worth
renaming — the plugin path solves the multi-plugin case, and short names are a
feature for single-plugin projects.

## Hook-based token tracking replaces skill-level bash calls (2026-03-17)

Stop hook (`token-stop-hook.sh`) auto-detects stage transitions by comparing
`.claude/.token-state` against `status.md`. Logs to `token-log.md` automatically.
All `token_checkpoint` and `token_summary` bash blocks removed from skills (16
total). Three performance paths: no-op ~1ms, active same-stage ~5ms, transition
~200ms.

## Status line for pipeline visibility (2026-03-17)

`scripts/statusline.sh` shows feature slug, pipeline stage, substage, per-stage
context tokens, and context window % with color-coded warnings. Replaces tmux
dashboard for pipeline position awareness.

**Key design insight: the status line is both display and tracker.** Claude Code
fires the status line script after each assistant message AND between tool calls
within a response. Each pipeline agent updates `status.md` as its first action
(idempotency pre-flight). This means `status.md` reflects the current stage
*before* the status line fires — even during chained sub-agent execution where
the Stop hook never gets a chance to run.

The status line exploits this by reading the actual `**Stage:**` field from
`status.md` on every fire, comparing it against a cached baseline in
`.claude/.statusline-baseline`. When the stage changes:
1. Log the completed stage's context token usage to `token-log.md`
2. Reset the baseline for the new stage
3. Display the new stage with tokens at 0

**Why this works during chained sub-agents:** When `/feature` invokes
`/feature-domains` as a sub-agent, which invokes `/feature-plan`, etc., the
Stop hook never fires (it requires Claude to fully stop). But the status line
fires between tool calls within the response. Each agent updates `status.md`
before doing its work. So the status line sees: scoping → domains → planning →
testing → implementation → refactor — all within one continuous response.

**Per-stage tokens** are derived from `context_window.used_percentage ×
context_window.context_window_size` (from Claude Code's session JSON). The
delta from the baseline gives "tokens consumed by this stage." This is context
tokens (what's in the window), not cumulative API tokens.

**Three state files:**
- `.claude/.token-state` — written by Stop hook on cold start, read by status
  line for `feature_dir`. Not updated during chained execution.
- `.claude/.statusline-baseline` — written by status line on stage transitions.
  Contains `baseline_stage`, `baseline_ctx_tokens`, `baseline_timestamp`.
- `.feature/<slug>/token-log.md` — append-only log of per-stage token usage.
  Written by status line on transitions, read by `/feature-resume --status`.

## Plugin vs shell install path documentation (2026-03-17)

README documents both paths with comparison table: plugin gets `vallorcine:`
prefix, shell gets unprefixed short names. Plugin path doesn't auto-configure
hooks/status line (manual settings.json addition documented). Shell path
auto-configures everything via install.sh.

## Domain scout KB empty check (2026-03-17)

Offers research/continue/skip when KB has zero topics. `skip_all_research`
flag prevents repeated per-domain prompts when user wants to rely on local
domain knowledge.

## Version display in /vallorcine-help (2026-03-17)

Reads `.claude/.vallorcine-version`. Shows version in opening headers.

## Five-concern architecture model (2026-03-18)

Expanded from four concerns to five: Knowledge, Decisions, Features, Curation,
System. Curation is a correlation engine (`/curate`) that combines vallorcine's
structured history with git data to find things individual features, decisions,
and research sessions couldn't see. Four value buckets: ADR drift, KB+hindsight
review, implicit dependencies, orphaned areas.

## Curation is a correlation engine, not a concern graph (2026-03-18)

Original design built a persistent "concern graph" tracking semantic areas.
Dropped because: business objectives can't be inferred from git history, the
concern abstraction was doing double duty (code + business), and without business
intent "concerns" are just "files that change together" which git tracks natively.
Reframed as correlating existing signals (vallorcine artifacts + git history) to
find cross-cutting issues.

## Seed files never force-overwritten (2026-03-18)

`install.sh` uses `_install_seed()` for `.kb/CLAUDE.md` and `.decisions/CLAUDE.md`.
Always skips if file exists, regardless of FORCE_UPDATE or version mismatch auto-force.
Found via dogfood: every force install was wiping JLSM's populated indexes with
empty seed templates. Regression test covers both paths.

## JS parity required for narrative pipeline (2026-03-20)

Principle 1 mandates both Python and JS if either is provided. Full port of 5
pipeline files verified with identical output.

## ADR out-of-scope items as deferred stubs (2026-03-20)

Accepted ADRs contain "What This Decision Does NOT Solve" sections invisible to
`/decisions triage`. Retroactive: `/curate` Analysis 9 finds them. Proactive:
`/architect` Step 6c auto-creates deferred stubs.

## Consolidate /feature-init into /setup-vallorcine (2026-03-20)

No project has used one concern without the other. Supersedes the earlier
separation decision.

## Architect iterative research (2026-03-20)

After scoring, if coverage is thin, commission targeted follow-up research.
Up to 3 iterations.

## Architect composite candidates (2026-03-20)

Evaluate combinations of approaches when no single candidate covers all
constraints. Boundary rule defines which component handles which sub-problem.

## /decisions revisit replaces /decisions review (2026-03-20)

Single command accepts slug or topic, conversational "why" pre-step, revision
condition checking, feature kickoff after revision.

## Architect neutral presentation (2026-03-20)

Non-negotiable rule: never express preference before Step 6a deliberation.

## Mandatory doc review in /release (2026-03-20)

Step 1.5 checks README, EXAMPLES, DESIGN, CONTEXT against changes before
release notes can be drafted.

## aTDD as parallel path, not replacement (2026-03-23)

Adversarial TDD is a second pipeline option alongside standard TDD. Three
tiers: Quick (easy), Enhanced TDD + Audit (moderate), Full aTDD
(complex/critical). Selection at scoping time.

## Spec Analyst generates dynamic Breaker prompts (2026-03-23)

Static adversarial prompts plateau at cycle 3-4. The Analyst reads
implementation + tests + prior findings to generate a targeted prompt each
round, avoiding redundant coverage.

## Validate with hard numbers before shipping (2026-03-23)

Run both pipelines against jlsm features from identical starting points.
Measure: additional bugs found, tokens per round, convergence curve. Replace
speculative cost estimates with real data.

## Research bundle for reproducibility (2026-03-23)

Sanitized JSONL logs, feature descriptions, git SHAs, automation scripts.
Others can independently verify results.

## Combined prove-fix per-finding model (2026-04-02)

Merged Prove + Fix into single subagent. Each finding gets fresh context.
Test result determines path (not agent's choice). Validated: same cost as
prove-only with fixes included. Fix cascade reduces total work via serial
execution. One finding at a time, no parallelism — prevents fix conflicts
on shared source files.

## Effort asymmetry removal in prove-fix (2026-04-02)

Agent always writes test regardless of outcome (confirmed or impossible).
Test result chooses the path. Prevents task-avoidance bias from sandbagging
research.

## Concurrency lens per-construct filtering (2026-04-02)

thread_sharing field in cards (none/possible/explicit). Concurrency lens
excludes thread_sharing:none constructs. Block-compression data shows 54%
preventable impossibles.

## Spec conflict detection at resolution time (2026-04-02)

spec-resolve.sh checks for contradictions between included specs before
emitting bundle. Feature-plan blocks, feature-test marks UNTESTABLE,
feature-implement diagnoses spec conflicts. DRAFT specs with [UNRESOLVED],
[CONFLICT] markers or open_obligations excluded from resolved context.

## Spec extraction from implementation (2026-04-03)

Bottom-up spec authoring for foundational types. Auto-discovery of source,
consuming specs, tests. [ABSENT] tag for behaviors code doesn't have but
specs may assume. Three lifecycle paths: promote → implementation work,
preserve → negative requirement, defer → curate resurfaces.

## Fix-spec conflict resolution (2026-04-03)

Three options: keep fix + update spec, revert fix + mark FIX_IMPOSSIBLE,
split (keep fix + add new requirement that invalidates old). Fourth:
defer with [UNRESOLVED].

## Architect adversarial hardening (2026-04-03)

6 changes from aTDD research: scope verification, constraint falsification,
inline score falsification, prior-scores-not-evidence, REQUIRED annotations,
write-and-justify checklist.

## Phase 0 already-fixed check (2026-04-03)

Mandatory pre-flight in prove-fix subagent. Reads current source before
test writing. Short-circuits cascade impossibles in 3 turns instead of 35.

## Seven-concern architecture model (2026-04-11)

Expanded from six concerns to seven: Knowledge, Decisions, Specifications,
Features, Work, Curation, System. Work (`.work/`) is a coordination layer
for multi-feature work — decomposes goals into work definitions with
artifact-based dependencies and computed readiness. Interface contracts are
a spec subtype (`kind: interface-contract`), not a separate layer.

## Artifact-based dependencies, not stage-based (2026-04-11)

Work definitions depend on specific artifacts (specs at APPROVED, ADRs at
accepted, KB entries existing), not on other WDs completing stages. Enables
partial unblocking — a WD becomes READY as soon as its specific deps exist,
regardless of what stage the producing WD is in. Also provides a scoping
signal: >5 artifact deps suggests the WD should be decomposed further.

## Interface contracts as spec subtype (2026-04-11)

`kind: interface-contract` field on specs, not a fifth knowledge layer. Reuses
all existing spec tooling (resolve, validate, author, displace). Displacement
detection works on interface contracts automatically. Shared surfaces between
work definitions are just specs that multiple WDs reference.

## Computed readiness, not declared (2026-04-11)

`work-resolve.sh` walks artifact deps each invocation. No cached state to go
stale. Completing a WD that produces artifacts automatically unblocks dependent
WDs. Status lifecycle: DRAFT → SPECIFIED → READY/BLOCKED (computed) →
IN_PROGRESS → COMPLETE.

## Pipeline mode decomposition (2026-04-11)

Three modes: specification-only (scoping → domains → spec authoring → complete),
implementation-only (planning → testing → hardening → implementation → refactor),
full (default, backwards compatible). `pipeline_mode` field in status.md.
`/work-start` auto-detects mode from WD produces list. Feature-resume routes
to mode-appropriate next stage.

## Work context as pull-model injection (2026-04-11)

`work-context.sh` provides bounded context snippets to architect (forward
compatibility, ordering gates), spec-author (downstream consumers),
feature-domains (cross-WD domain reuse), feature-plan (interface stability
constraints), and feature-resume (work group grouping). Zero cost when no
work groups exist — scripts exit immediately.

## Decisions-only WDs are invalid (2026-04-16)

Every WD that produces or modifies specs must include an implementation pass.
If a decision results in no spec changes and no code changes, it's a close or
re-defer, not a WD. Found when all 13 jlsm decisions-backlog WDs produced only
ADRs with no implementation scope.

## Spec promotion requires cross-check (2026-04-16)

Before DRAFT→APPROVED, a spec must be verified against all APPROVED specs in
its domain. Anchors go first (nothing to cross-check), subsequent specs have a
growing constraint set. Prevents contradictory APPROVED specs in the same domain.

## Three-tier spec health model (2026-04-16)

Tier A: code matches spec → promote to APPROVED. Tier B: spec correct but code
has bugs → fix code then promote. Tier C: spec describes target architecture,
code is a working simplification → keep DRAFT with annotations. Found during
jlsm anchor audit of 8 specs (5 Tier A, 1 Tier B, 2 Tier C).

## Work-decompose must check spec state (2026-04-16)

Decomposition without visibility into `.spec/` produces WDs disconnected from
reality. The algorithm must read spec registry as part of its analysis. Found
when work-decompose created 13 WDs that completely missed 26 existing DRAFT specs.

## @spec annotations as primary traceability (2026-04-16)

`@spec FXX.RN` (and after the 2026-04-20 migration, `@spec domain.slug.RN`)
comments in code link requirements to enforcement points. `spec-verify`
annotates during discovery; `spec-trace.sh` provides the reverse index.
Together they make spec→code traceability queryable in both directions
without a separate registry. `/curate` analysis 18 enumerates APPROVED
specs and calls `spec-trace.sh` for each to flag reqs missing impl/test
annotations.

## Correctness over context cost (2026-04-17)

Never drop correctness-relevant context from an agent prompt to save tokens.
When prompts grow past budget, the fix is phase splitting + condensed
handoff files (analysis-phase writes a structured finding doc, next-phase
reads that instead of inheriting the conversation), not cutting information
the agent needs to make decisions. Codified in
`.claude/rules/context-efficiency.md`.

## Spec reorganization to behavioral domains (2026-04-17, executed 2026-04-20)

Specs migrated from feature-centric layout (`F13-jlsm-schema.md`) to
behavioral-domain layout (`domains/schema/construction.md`). 12 domains,
~60-75 files depending on how cross-cutting concerns split. Annotation
format changed from `@spec FXX.RN` to `@spec domain.slug.RN`. Executed in
jlsm PR #40 + vallorcine PR #43 (2026-04-20) — 75 specs reshaped
domain-first. The kit stays backwards-compatible with feature-ID specs
via the dual-schema manifest detection (see next entry).

## Primitives vs applications spec pattern (2026-04-20)

When a concern is cross-cutting (encryption, compression, serialization),
split the spec content by abstraction level: primitives (keys, rotation,
algorithms, variants) live in their own domain directory; applications
(how WAL/query/indices *use* encryption) live in their functional domain
with a multi-domain tag for cross-discovery. Codified as MIGRATION.md P6
and applied to jlsm F42/F46/F47/F03 during migration. Same rule
generalizes to any cross-cutting primitive.

## Manifest schema v2 + dual-schema read path (2026-04-20, hardened 2026-04-23)

Post-migration manifests use `{schema_version: 2, specs: [{id, path, ...}]}`
(array of specs with domain-slug IDs) instead of legacy
`{features: {FXX: {...}}}`. Schema v2 handles `domain.slug` IDs natively;
v1 is retained for projects that haven't migrated. Every read-path
script uses `spec-lib.sh` helpers (`spec_file_for_id`,
`spec_manifest_ids`, `spec_manifest_state`, `spec_manifest_domains_for`)
that detect the schema at read time. Writes to v2 manifests use v2 shape;
v1 writes use v1 shape. No forced migration window — v1 stays working
indefinitely. The 2026-04-23 `fix/manifest-v2-schema-compat` branch
closed the remaining silent-failure paths in `spec-resolve.sh`,
`work-lib.sh`, `work-finalize.sh`, `curate-scan.sh`, and `spec-stats.sh`.

## Fix now, not defer — positive justification required (2026-04-21)

Generalises the existing kit-failures and spec-violations rules: when a
problem surfaces mid-session, default to fixing it in the current PR.
Phrases like "not X's problem", "separate concern", "covered
transitively by Y" are red flags that need positive justification before
they're acceptable. No transitive / side-effect coverage for claimed
behaviour — test what is claimed, directly. Memory:
`feedback_fix_now_not_defer.md`.

## Planning-snapshot work groups use DRAFT status (2026-04-21)

WDs that point at specs still in DRAFT use `status: DRAFT`, not
SPECIFIED. SPECIFIED implies the spec is APPROVED and ready for
implementation; DRAFT matches the actual state where the WD will promote
the spec via `/work-plan` before implementation can proceed. Applied to
the 5 jlsm work groups shipped in PR #42 (15 WDs, 13 still-DRAFT specs).

## Parallel-subagent hang prevention — mode-gated prompts + termination contract (2026-04-23)

When `/feature-coordinate` dispatches work units as concurrent
sub-agents, the coordinator's `Agent` tool calls block until each child
emits its final assistant message. Two failure modes had to be closed:

1. **Unconditional AskUserQuestion sites** in the three pipeline skills
   (`/feature-test`, `/feature-implement`, `/feature-refactor`) —
   including several explicitly marked "regardless of automation_mode"
   — would hang forever in a subagent with no human attached. Every site
   now has a `balanced | speed` bypass that records
   `escalated-<reason>` to `cycle-log.md` + substage and returns
   `ESCALATED`, letting the coordinator surface it via its existing
   escalation flow.

2. **Weak termination signal** at `/feature-refactor`'s parallel-mode
   exit — saying "STOP" as prose is not a forcing function at the LLM
   level. The skill now carries an explicit subagent termination
   contract: "your very next message MUST be the single-line summary —
   no more Read, Bash, Grep, Edit." `/feature-coordinate` gained a
   Step 1a documenting the dispatch contract every coordinator must
   embed in Agent prompts.

Root cause came from a 2026-04-23 jlsm WU-3 run: status.md flipped to
COMPLETE at 10:41:32, but the subagent kept running ~2 min before the
user had to Ctrl+C to unblock the coordinator. Regression:
`tests/scenario-parallel-subagent-hang-prevention.sh` (10 structural
invariants; grep-based so it's durable against future skill edits).

---

## Spec violations are contracts, not backlog (2026-04-16, graduated 2026-05-09)

`/spec-verify` repairs violations inline (fix code or amend spec).
Obligations are created only on explicit user deferral, never as the
default path. This was a deliberate inversion from an earlier model
where every detected violation became a new obligation row, which
encouraged "I'll fix it later" inertia and decoupled the spec from
the code that was supposed to enforce it. Inline repair forces the
choice (fix or amend) at detection time; deferral is an opt-in escape
hatch for genuine "we cannot resolve this now" cases.

## Partial implementation state still binary (2026-04-19, graduated 2026-05-09)

The spec model remains binary (APPROVED or DRAFT). A partial
implementation primitive — "90% implemented, 10% explicitly deferred"
— has been on the open-questions list since 2026-04-19. Decision after
two release cycles: the per-requirement annotation coverage table
introduced by PR #67 (v0.16.5) provides the per-requirement grain
(annotated / not-annotated / waived / pending). That likely IS the
partial-implementation primitive. No new schema needed; a `pending`
status row in `spec-coverage.md` is the explicit-deferral marker.
Revisit if jlsm post-v0.16.5 surfaces a real workflow that the
coverage-table grain can't express.

## GSD is a direct-lane competitor (2026-04-21, graduated 2026-05-09)

Positioning emphasis: depth-of-spec-rigor (lifecycle, displacement,
audit integration, computed readiness), NOT the "spec-driven" label
(GSD owns mindshare at 55K+ stars). See COMPETITIVE.md for the
head-to-head breakdown. This shapes ongoing user-facing docs work and
informs the user-facing pitch wherever vallorcine is described.
