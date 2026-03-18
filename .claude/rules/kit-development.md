# Kit Development Rules

## User-facing vs kit-internal commands

**User-facing commands** — installed to developer projects, referenced in skills and docs:
  /feature, /feature-quick, /feature-domains, /feature-plan, /feature-test,
  /feature-implement, /feature-refactor, /feature-pr, /feature-retro,
  /feature-complete, /feature-cleanup, /feature-resume, /feature-coordinate,
  /feature-init, /kb, /research, /architect, /decisions, /project-context,
  /vallorcine-help, /setup-vallorcine, /upgrade-vallorcine, /uninstall-vallorcine

**Kit-internal commands** — only exist in this repo, NOT installed to user projects:
  /ideate, /save-work, /release

When designing features, discussing workflows, or writing documentation, ONLY
reference user-facing commands. Kit-internal commands do not exist for end users
and must never appear in skills/, README, agents/, or user-facing output.

## File distinction

Files in `rules/`, `skills/`, `agents/`, `scripts/` — these get INSTALLED to
user projects. Changes here affect every vallorcine user.

Files in `.claude/rules/`, `.claude/commands/`, `.claude/skills/` — these are
LOCAL to vallorcine kit development only. Never deployed to users.
