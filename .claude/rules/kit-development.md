# Kit Development Rules

This repo has two layers of files that serve different audiences. Getting the
wrong one causes changes to either not take effect or ship to every user
unexpectedly. When in doubt about where a change belongs, ask.

## Where changes go

### Deployed to users (via install.sh / plugin install)

These files are installed to every project that uses vallorcine. Changes here
affect all users on their next install or upgrade.

| Path | What it is | Audience |
|------|-----------|----------|
| `skills/*/*.md` | Slash commands + supporting files (user-facing) | Developers using vallorcine |
| `agents/*.md` | Agent identity definitions | Claude (loaded by skills) |
| `rules/*.md` | Always-loaded rules (tdd-protocol, kb-protocol, etc.) | Claude (every session) |
| `scripts/*.sh` | Shell scripts (token tracking, merge driver, etc.) | Installed to .claude/scripts/ |
| `prompts/audit/*` | Audit pipeline prompts and scripts (.md, .py, .sh, .js) | Installed to .claude/prompts/audit/ |
| `install.sh` | Installer | Users running setup |
| `upgrade.sh` | Upgrader | Installed to .claude/upgrade.sh |
| `MANIFEST` | File list for upgrade stale removal | Installed to .claude/.vallorcine-manifest |
| `kb/`, `decisions/` | Seed files for KB and decisions structure | Installed to .kb/, .decisions/ |
| `.claude-plugin/` | Plugin manifests | Claude Code plugin system |
| `README.md` | User-facing documentation | GitHub / npm / plugin marketplace |

**Rule: every change to these files is a user-facing change.** Treat it like
shipping code — consider backwards compatibility, test with install.sh, and
include in the changelog.

### Local to vallorcine development only

These files exist only in this repo. They are NOT installed to user projects
and are NOT in the MANIFEST.

| Path | What it is | Audience |
|------|-----------|----------|
| `.claude/rules/*.md` | Dev-only rules (this file, bug-fix-regression) | Claude working on this repo |
| `.claude/skills/*/SKILL.md` | Dev-only commands (/ideate, /save-work, /release) | Vallorcine maintainers |
| `.claude/commands/*.md` | Legacy dev commands (if any remain) | Vallorcine maintainers |
| `.claude/settings.json` | Local Claude Code settings for this repo | This repo only |
| `tests/*.sh` | Test scripts | CI / local testing |
| `CONTEXT.md` | Active session state | Vallorcine maintainers |
| `SETTLED.md` | Design history | Vallorcine maintainers |
| `DESIGN.md` | Architecture reference | Both (but not installed) |
| `COMPETITIVE.md` | Market positioning | Vallorcine maintainers |
| `DEFERRED.md` | Parked ideas | Vallorcine maintainers |
| `WIP.md` | Session checkpoint (gitignored) | Current session |
| `.changelog-staging.md` | Pre-release notes (gitignored) | /release command |

**Rule: changes here never reach users.** Safe to iterate freely.

## User-facing vs kit-internal commands

**User-facing commands** — installed to developer projects:
  /feature, /feature-quick, /feature-domains, /feature-plan, /feature-test,
  /feature-implement, /feature-refactor, /audit, /feature-pr,
  /feature-retro, /feature-complete, /feature-cleanup, /feature-resume,
  /feature-coordinate,
  /spec, /spec-author, /spec-write, /spec-verify, /spec-init, /spec-resolve,
  /kb, /research, /architect, /decisions, /curate,
  /project-context, /vallorcine-help, /setup-vallorcine, /upgrade-vallorcine,
  /uninstall-vallorcine

**Kit-internal commands** — only exist in this repo:
  /ideate, /save-work, /release, /script-dev

When designing features, discussing workflows, or writing documentation, ONLY
reference user-facing commands. Kit-internal commands must never appear in
`skills/`, `README.md`, `agents/`, or any user-facing output.

## Decision checklist for new changes

When making a change, ask:

1. **Does this affect what users see or experience?**
   → Change goes in `skills/`, `rules/`, `agents/`, `scripts/`, `prompts/`, or `install.sh`
   → Update MANIFEST if adding, removing, or renaming a file
   → Update install.sh if the file needs a new install path or glob
   → Add to changelog staging

2. **Does this affect how we develop vallorcine?**
   → Change goes in `.claude/rules/`, `.claude/skills/`, or context files
   → No MANIFEST or changelog update needed

3. **Not sure?**
   → Ask. The cost of shipping an internal change to users (confusion, bloated
   rules files, leaked dev workflow) is higher than the cost of pausing to check.

## Pre-PR validation (mandatory, no exceptions)

Before every PR, run the MANIFEST and install validation. This catches stale
paths, missing files, renamed prompts, and install gaps that silently break
user projects.

**Step 1 — MANIFEST → source file check:**
Every path in MANIFEST must resolve to an actual file in the repo. For each
`.claude/X` entry, verify that `X` exists (e.g., `.claude/prompts/audit/foo.md`
→ `prompts/audit/foo.md`).

**Step 2 — Source → MANIFEST reverse check:**
Every installable file (skills, agents, rules, scripts, prompts) must have a
MANIFEST entry. Check for files that exist but are not listed.

**Step 3 — Fresh install test:**
Run `bash install.sh` to a temp directory, then verify every MANIFEST entry
was actually installed.

**Step 4 — Run `bash tests/test-install.sh`:**
Full regression suite. Zero failures required.

If any step fails, fix it before cutting the PR. MANIFEST drift is how users
end up with broken installs or stale files that upgrade can't clean.

## Interactive prompt standard

All user-facing interactive prompts in skills and agents MUST use
AskUserQuestion with labeled options. Never use "Type yes", "press Enter",
numbered text menus, or other patterns that require the user to type a
specific keyword.

- Binary choices: AskUserQuestion with 2 options (e.g., "Proceed" / "Stop")
- Multi-choice: AskUserQuestion with 2-4 options + Other for custom input
- Dynamic lists (variable item count): build AskUserQuestion from available
  items. If >4 items, use summary options (e.g., "All", "Done") with Other
  for specific selection.

This ensures a consistent UX across all skills and avoids users having to
guess the expected input format.
