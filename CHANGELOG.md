# Changelog

All notable changes to vallorcine are documented here.
Format: `## [version] — YYYY-MM-DD` with sections Added / Changed / Fixed / Removed.

---

## [unreleased]

### Added
- Est. Tokens and Actual Tokens columns in Stage Completion table in status.md
- `/feature-resume` displays estimated vs actual token comparison with delta %
- `/decisions list` — browse and filter all decisions by status and keyword
- `/decisions explain "<slug>"` — plain-language summary of a decision with KB context
- `/feature-cleanup` — interactive walkthrough of stale feature directories (keep/archive/delete)
- `install.sh --diff` — show what would change between installed and package version without writing
- `/feature-retro` — post-feature retrospective: scope divergence, assumption validation,
  domain gap review, token accuracy, TDD efficiency. Auto-invokes `/architect`,
  `/decisions review`, and `/research` for actionable findings.
- Dependency topology view in `/feature-resume` — work units displayed in
  dependency layers with `└─ depends on:` annotations, batch info for parallel mode,
  and progress counter

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
- `/vallorcine-help` — guided entry point, routes to /quick or /feature
- `/feature` — scoping agent with sequential one-question-at-a-time interview
- `/feature-init` — project profile setup with inference from existing project files
- `/feature-domains` — domain scout, commissions research and architect runs
- `/feature-plan` — work planner with token-based work unit split analysis
- `/feature-test` — test writer agent, TDD cycle management
- `/feature-implement` — code writer agent
- `/feature-refactor` — refactor agent with 6-category checklist
- `/feature-pr` — PR draft generator
- `/feature-complete` — archive and cleanup
- `/feature-resume` — crash recovery from status.md checkpoint
- `/feature-resume --status` — pipeline status display with --share mode
- `/quick` — lightweight single-construct path with complexity assessment
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
