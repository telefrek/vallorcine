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
