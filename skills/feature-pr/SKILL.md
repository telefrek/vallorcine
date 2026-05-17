---
description: "Draft a pull request title, description, and review checklist"
argument-hint: "<feature-slug>"
---

# /feature-pr "<feature-slug>"

Drafts a pull request title, description, and review checklist by reading the
feature's working files. Works for both /feature and /feature-quick slugs.

Run this after /feature-refactor completes and before opening the PR.

---

## Pre-flight guard

Check that `.feature/<slug>/` exists. If not:
"No feature found for '<slug>'. Check the slug or run /feature-resume to see active features."

Check that cycle-log.md has at least one `refactor-complete` or `implemented` entry.
If not: "Feature '<slug>' has not been implemented yet. Complete the pipeline first."

---

## Idempotency pre-flight

Check status.md for a `pr-draft` substage entry.
If a previous PR draft exists in `.feature/<slug>/pr-draft.md`:
```
📋 PR DRAFT · <slug>
───────────────────────────────────────────────
A PR draft already exists for '<slug>'.
Draft: .feature/<slug>/pr-draft.md

```
Use AskUserQuestion with options:
  - "Proceed to PR"
  - "Regenerate"

If "Regenerate": proceed to regenerate the draft.
If "Proceed to PR": skip to Step 6 — PR creation (attempt to create the PR from the existing draft).

---

Display opening header:
```
───────────────────────────────────────────────
📋 PR DRAFT · <slug>
───────────────────────────────────────────────
```

---

## Step 0.5 — Pre-PR commit verification

Before drafting, check for uncommitted files that should be part of this PR.
These are files created by the pipeline (research, architect, test writer,
code writer) that may not have been staged — especially after crashes or
session interruptions.

### Scan for uncommitted files

Run `git status --short` and check for untracked or modified files in:

1. **`.kb/`** — KB entries created during `/feature-domains` or `/feature-retro`
2. **`.decisions/`** — ADRs, index updates, and history.md from `/feature-domains`
   or `/feature-retro`. This includes `CLAUDE.md` (active decisions index) and
   `history.md` (archived rows) — both are updated by the architect agent during
   domain analysis. These are feature-produced, not upgrade artifacts.
3. **Source files** listed in `work-plan.md` (if it exists)
4. **Test files** listed in `work-plan.md` or referenced in `cycle-log.md`

### Separating feature changes from upgrade changes

If `.claude/` files are also modified (skills, scripts, settings, manifest),
those are likely from a vallorcine upgrade, not the feature pipeline. Present
them separately:

```
── Pre-PR check ────────────────────────────────
I found uncommitted changes in two categories:

Feature-produced (should be in this PR):
  ? .decisions/compression-codec-api-design/adr.md
  M .decisions/CLAUDE.md
  M .decisions/history.md
  ? .kb/systems/lsm-index-patterns/index-scan-patterns.md
  M src/storage/block.go

Vallorcine upgrade (separate commit recommended):
  M .claude/skills/research/SKILL.md
  M .claude/settings.json
  M .claude/.vallorcine-manifest
```

Recommend committing upgrade changes first (`chore: upgrade vallorcine to vX.X.X`)
before staging feature changes. This keeps the feature PR clean.

Filter out:
- `.feature/` — gitignored working files, not committed
- `.curate/` — gitignored runtime files
- Files already staged

### If uncommitted files found

```
── Pre-PR check ────────────────────────────────
I found files created during this feature's pipeline that haven't been
committed yet:

Knowledge & decisions:
  ? .decisions/session-storage/adr.md
  ? .decisions/session-storage/constraints.md
  ? .decisions/session-storage/evaluation.md
  ? .decisions/session-storage/log.md
  ? .kb/systems/payments/stripe-integration.md

Source & tests:
  M src/auth/session.ts
  ? tests/auth/test-session.ts

These should be included in your PR.

Use AskUserQuestion with options:
  - "Stage all"
  - "Let me pick"
  - "Skip (I'll handle it manually)"
```

**If "Stage all":** run `git add` for all listed files. Report what was staged.
**If "Let me pick":** present numbered list, user picks by number. Stage selected.
**If "Skip":** proceed to Step 1. Note in the PR description that uncommitted
files were detected (so the reviewer knows to check).

### If no uncommitted files found

Proceed silently to Step 1. No message needed.

---

## Step 1 — Load context

Read in order:
1. `.feature/<slug>/status.md` — current state, cycle count
2. `.feature/<slug>/brief.md` if it exists (full /feature pipeline)
   OR the Description field from status.md (quick task)
3. `.feature/<slug>/work-plan.md` if it exists
4. `.feature/<slug>/cycle-log.md` — full history
   (If `units/` directory exists, the coordinator has already merged per-unit
   logs into the feature-level cycle-log.md — read that merged log.)
5. `.feature/<slug>/domains.md` if it exists — for ADR links

Do NOT read implementation or test files — the PR description should describe
intent and behaviour, not implementation details.

---

## Step 1a — Spec coverage gate (mandatory before Step 2)

If `.feature/<slug>/spec-coverage.md` exists, refresh it against the current
codebase and run the gate. The gate is the structural enforcement that every
**primary** loaded spec requirement has at least one `@spec` annotation in
tests or implementation. Rows tagged `context` in the Notes column come from
specs that were transitively pulled into the bundle for planning visibility
(parent chain, `requires:`, sibling expansion) — those are NOT this feature's
annotation obligation and the gate skips them by default:

```bash
if [[ -f .feature/<slug>/spec-coverage.md ]]; then
  bash .claude/scripts/spec-coverage.sh update \
    .feature/<slug>/spec-coverage.md --all
  bash .claude/scripts/spec-coverage.sh gate \
    .feature/<slug>/spec-coverage.md
fi
```

**If the gate fails (exit nonzero):**

The script prints the list of uncovered requirements (primary scope only by
default). Display the output to the user and stop the PR draft. Do not
proceed to Step 2.

The user has three resolutions:

1. **Annotate the missing site.** Open the relevant test or implementation
   file and add `@spec <spec-id>.R<n>` per the format in
   `rules/spec-annotation-protocol.md`. Re-run `/feature-pr`.
2. **Waive the row** when an annotation genuinely doesn't fit (e.g., the
   requirement is satisfied by configuration, not code; or coverage lives
   in an integration suite outside this repo's scan paths):
   ```bash
   bash .claude/scripts/spec-coverage.sh waive \
     .feature/<slug>/spec-coverage.md \
     <spec-id>.R<n> "<reason — surfaced in the PR description>"
   ```
3. **Override the gate entirely** if the user accepts the coverage gap as a
   conscious decision. Use AskUserQuestion with two options:
   - "Annotate now" — stop, let the user annotate or waive specific rows.
   - "Override gate (record reason in PR)" — proceed with a `--accept-coverage-gap`
     style note included in the PR description's "Notes for reviewer" section.
     Record the user-supplied reason verbatim. Do NOT silently override.

The override path is intended for rare cases where the user has a valid
reason the kit cannot detect (e.g., legacy code being touched in a way that
predates spec authoring). It is recorded in the PR so reviewers can see
the gap was explicit.

**`--include-context` strict mode** is available for whole-bundle audits
(reviewing every requirement the bundle pulled in, not just primary scope):

```bash
bash .claude/scripts/spec-coverage.sh gate \
  .feature/<slug>/spec-coverage.md --include-context
```

`/feature-pr` does NOT pass `--include-context` by default. Reach for it only
when explicitly auditing the whole bundle's coverage — e.g., during a
spec-backfill or curation pass — not as a routine PR check.

---

## Step 1b — Quality-bar gate (mandatory before Step 2)

Per `rules/completeness-contract.md` §5 (Quality-bar contract), the
repository's check command MUST pass before a PR is drafted. "Preexisting
failures" is NOT an exemption.

Detect the check command from project conventions:

```bash
# Order: project-config.md override → conventional commands
check_cmd=""
if [[ -f .feature/project-config.md ]]; then
  check_cmd=$(grep -E '^check_command:' .feature/project-config.md | sed 's/check_command://;s/^ *//;s/ *$//')
fi

if [[ -z "$check_cmd" ]]; then
  if   [[ -f gradlew ]];        then check_cmd="./gradlew check"
  elif [[ -f pnpm-lock.yaml ]]; then check_cmd="pnpm test"
  elif [[ -f yarn.lock ]];      then check_cmd="yarn test"
  elif [[ -f package.json ]];   then check_cmd="npm test"
  elif [[ -f Cargo.toml ]];     then check_cmd="cargo test"
  elif [[ -f go.mod ]];         then check_cmd="go test ./..."
  elif [[ -f Makefile ]];       then check_cmd="make check"
  fi
fi
```

If `check_cmd` is empty, surface to user via AskUserQuestion: ask the user
to supply the check command or skip the gate with explicit justification.

If `check_cmd` is set, run it:

```bash
eval "$check_cmd"
check_rc=$?
```

**If `check_rc=0`:** proceed to Step 2.

**If `check_rc≠0`:** the gate fails. PR draft is blocked. Display the
failures and surface to user via AskUserQuestion with three options:

1. **Fix the failures** — stop, fix the failing tests/checks in this PR,
   re-run /feature-pr.
2. **Move failures to .flake-allowlist.md** — if a failure is genuinely
   preexisting and out of this WD's scope, add it to `.flake-allowlist.md`
   with the schema below, then re-run /feature-pr. The flake-allowlist is
   committed; reviewers see what's been deferred and why.
3. **Override the gate (rare)** — only if you can demonstrate the failure
   is unrelated to this change AND fixing it materially expands scope.
   Record user-supplied justification verbatim in the PR description.
   This is the contract's "escape hatch" — use sparingly.

`.flake-allowlist.md` schema (one entry per failing test):

```markdown
## <test-id or test-class.method>

- **Why flaky/broken:** <one-line reason>
- **Assignee:** <github-username or team>
- **Deadline:** <YYYY-MM-DD — when this allowlist entry expires>
- **Added:** <YYYY-MM-DD>
- **Originating PR:** #<pr-number>
```

No deadline = no exemption. The deadline forces a follow-up rather than
permanent silence.

---

## Step 2 — Draft the PR

Construct the PR draft in this order:

### Title
One line. Format: `<type>(<scope>): <what it does>`
Types: feat / fix / refactor / test / chore
Examples:
- `feat(auth): add rate limiting to login endpoint`
- `fix(user): handle null email in isActive check`
- `refactor(cache): extract TTL logic into shared utility`

### Description

```markdown
## What
<2–3 sentences describing what this PR does and why. Written for a reviewer
who has not seen the feature work. No implementation details.>

## Changes
<Bullet list of the meaningful changes — constructs added, behaviour changed,
files modified. One line each. Sourced from work-plan.md and cycle-log.md.>

<If units/ directory exists (parallel feature), group changes by work unit:>
### WU-1: <name>
- <changes from WU-1 cycle-log entries>

### WU-2: <name>
- <changes from WU-2 cycle-log entries>

## Tests
<How the change is tested. Number of tests written, what they cover at a high
level. Note any edge cases or security scenarios specifically tested.>

<If `.feature/<slug>/spec-coverage.md` exists and was non-vacuous, include:>
## Spec coverage
<Output of `bash .claude/scripts/spec-coverage.sh report .feature/<slug>/spec-coverage.md`,
e.g. "Spec coverage: 12 loaded · 11 annotated · 1 waived · 0 pending".>
<If any rows were waived in this feature, list each one with its waiver reason.>
<If the gate was overridden via "Override gate", state that explicitly with
the reason the user supplied.>

## Decisions
<Only if domains.md exists and ADRs were consulted. Brief note on any
architectural decisions that influenced this implementation, with links.
Omit this section entirely for quick tasks with no ADR involvement.>

## Notes for reviewer
<Anything the reviewer should pay particular attention to — a tricky edge case,
a known limitation, a follow-up task that was deferred, a dependency on another PR.
If nothing notable: omit this section.>
```

### Review checklist

Generated from the refactor cycle log and project-config.md:

```markdown
## Review checklist
- [ ] Tests pass locally (`<run tests command from project-config>`)
- [ ] Linter passes (`<lint command>`)
<If type check exists:>
- [ ] Type check passes (`<type check command>`)
<If security findings were noted in refactor cycle:>
- [ ] Security: <specific item to verify>
<If performance findings were noted:>
- [ ] Performance: <specific item to verify>
<If integration tests exist:>
- [ ] Integration tests pass (`<integration test command>`)
- [ ] No unintended side effects on <related areas from domains.md>
```

---

## Step 3 — Display and confirm

Display the full draft in chat:
```
─────────────────────────────────────────────────────────────
PR DRAFT — <slug>
─────────────────────────────────────────────────────────────
Title: <title>

<description>

<checklist>
─────────────────────────────────────────────────────────────
─────────────────────────────────────────────────────────────
```

Use AskUserQuestion with options:
  - "Finalize"
  - "Describe adjustments" (Other — accepts custom input)

Iterate on feedback. When the user chooses "Finalize", write to disk.

---

## Step 4 — Write pr-draft.md

Write `.feature/<slug>/pr-draft.md`:

```markdown
---
feature: "<slug>"
created: "<YYYY-MM-DD>"
status: "draft"
---

# PR Draft — <slug>

## Title
<title>

## Description
<full description>

## Review checklist
<checklist>

---
*Generated from brief.md, work-plan.md, and cycle-log.md on <date>.*
*Copy the Title and Description sections directly into your PR.*
```

Update status.md substage → `pr-draft-written`.
Append `pr-drafted` entry to cycle-log.md:
```markdown
## <YYYY-MM-DD> — pr-drafted
**Agent:** 📋 PR Draft
**Summary:** PR draft written and confirmed by user.
**Token estimate:** ~<N>K (loaded: brief ~2K, work-plan ~4K, cycle-log ~<N>K)
---
```

---

## Step 4.5 — Run retrospective (if not already run)

The retrospective writes feature footprints, adversarial findings, capability
index updates, and work-definition status changes back to `.kb/`,
`.capabilities/`, and `.work/`. These artifacts MUST land in this PR — if they
land after the PR is created, they end up outside the merge and force a
follow-up "fix retro artifacts" PR. The next step (Step 5) commits whatever
the retro produces, so retro must run *before* Step 5.

### Skip if already run

Check `cycle-log.md` for an existing `retro-complete` entry. If present, the
retrospective has already run for this feature — skip to Step 5 silently.

### If not run

Display:
```
── Retrospective ──────────────────────────────────
The retro captures what worked / what didn't while the feature is fresh, and
writes feature-footprint + adversarial-finding entries back to `.kb/` so the
next feature benefits. Its outputs (KB entries, capability index updates,
work-definition status) MUST be in this PR — running retro after the PR is
created strands the artifacts outside the merge.
```

Use AskUserQuestion with options:
  - "Run retro now (recommended)"
  - "Skip — accept follow-up retro PR"

**If "Run retro now":** invoke `/feature-retro "<slug>"` as a sub-agent. Wait
for it to complete. Step 5 will pick up its outputs.

**If "Skip":** proceed but note in the PR description that retro was skipped
and a follow-up artifacts PR will be needed:

```markdown
## Retrospective
Retro deferred. Run `/feature-retro "<slug>"` after merge — outputs will need
their own follow-up PR (kb/capabilities/work-tracking only).
```

This is the explicit-acknowledgement path. The default is to run retro inline.

---

## Step 5 — Finalize feature records

Before creating the PR, finalize the feature's knowledge and index records so
they are included in the PR. This work used to happen post-merge in
`/feature-complete`, but leaving it until after the PR risks losing information
— users may not run the cleanup step, or the uncommitted changes get ignored.

### 5a — Write archive manifest

Write `.feature/<slug>/ARCHIVE.md`:

```markdown
---
feature: "<slug>"
archived: "<YYYY-MM-DD>"
---

# Archive Manifest — <slug>

## Feature Summary
<Summary from brief.md>

## What Was Built
<Bullet list of constructs from work-plan.md>

## Files Created / Modified
<From work-plan.md and cycle-log.md>

## TDD Summary
- Cycles completed: <n>
- Tests written: <n>
- Missing tests found during refactor: <total across all cycles>

## Decisions Made
<Links to ADRs created or used — these remain in .decisions/, this is just a reference>

## KB Entries Used
<Links to KB entries — these remain in .kb/>
```

### 5b — Update .feature/CLAUDE.md

Move the feature row from Active Features to Completed / Archived:

```
| <feature> | <slug> | <YYYY-MM-DD> | .feature/_archive/<slug>/ |
```

### 5c — Commit feature records

Stage and commit all feature-produced files that aren't yet committed. This
deliberately covers four trees because the feature pipeline writes to all of
them: `.kb/` (knowledge), `.decisions/` (ADRs), `.capabilities/` (capability
index updates from retro), and `.work/` (work-definition status from retro
+ work-resolve.sh). Missing any of these is the bug that produced repeated
"fix retro artifacts" follow-up PRs.

```bash
git add .feature/CLAUDE.md

# Decisions tree (ADRs + indexes)
git add .decisions/CLAUDE.md .decisions/history.md 2>/dev/null
git add .decisions/*/adr.md .decisions/*/constraints.md .decisions/*/evaluation.md .decisions/*/log.md 2>/dev/null

# Knowledge base (entries + indexes at every level)
git add .kb/ 2>/dev/null

# Capability index (retro promotes feature into the capability map)
git add .capabilities/ 2>/dev/null

# Work tracking (retro flips WD status to COMPLETE; manifest re-syncs)
git add .work/ 2>/dev/null

git commit -m "chore: finalize <slug> — archive manifest, index updates, knowledge files"
```

If nothing to commit (all already staged), continue silently.

---

## Step 6 — Create the PR

Check if `gh` CLI is available: run `gh auth status` silently.

**If `gh` is not available or not authenticated:**
```
───────────────────────────────────────────────
📋 PR DRAFT complete · <slug>
  Tokens : <TOKEN_USAGE>
───────────────────────────────────────────────
PR draft written to .feature/<slug>/pr-draft.md

gh CLI not found or not authenticated. To create the PR manually:
  1. Copy the title from pr-draft.md
  2. Copy the description from pr-draft.md
  3. Open a PR in your repo's UI or with: gh pr create

When the PR merges, run:
  /feature-complete "<slug>"
───────────────────────────────────────────────
```

Stop. (Retro already ran in Step 4.5 — its outputs are in the commit prepared
by Step 5 and will be part of the PR you create.)

**If `gh` is available:**

Display:
```
───────────────────────────────────────────────
📋 PR DRAFT complete · <slug>
  Tokens : <TOKEN_USAGE>
Draft: .feature/<slug>/pr-draft.md

Use AskUserQuestion with options:
  - "Create PR now"
  - "Skip"
───────────────────────────────────────────────
```

If "Skip":
```
When you're ready:
  gh pr create --title "<title>" --body-file .feature/<slug>/pr-draft.md

When the PR merges, run:
  /feature-complete "<slug>"
```
Stop.

If "Create PR now":

Run:
```
gh pr create --title "<title from pr-draft.md>" --body-file ".feature/<slug>/pr-draft.md"
```

If the command succeeds, capture the PR URL from `gh` output. Update status.md
substage → `pr-created`. Append to cycle-log.md:
```markdown
## <YYYY-MM-DD> — pr-created
**Agent:** 📋 PR Draft
**PR:** <URL>
---
```

Display:
```
───────────────────────────────────────────────
✓ PR opened: <URL>
───────────────────────────────────────────────
When the PR merges:
  /feature-complete "<slug>"
───────────────────────────────────────────────
```

Stop. (Retro already ran in Step 4.5 — its outputs were committed in Step 5
and are part of this PR. Do NOT offer a post-PR retro here — that was the
bug that produced repeated "fix retro artifacts" follow-up PRs.)

If `gh pr create` fails (e.g. branch not pushed, no remote): display the error
and fall back to the manual instructions above. Do not retry automatically.
