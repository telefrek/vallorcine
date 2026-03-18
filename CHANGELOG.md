# Changelog

All notable changes to vallorcine are documented here.
Format: `## [version] — YYYY-MM-DD` with sections Added / Changed / Fixed / Removed.

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
- **Principle 1: bash and markdown only** — new top-priority design principle.
  Hard constraint gating all new features. No external dependencies beyond
  bash and markdown.
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
