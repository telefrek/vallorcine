---
description: "Archive feature working files after a PR has merged"
argument-hint: "<feature-slug> [--force]"
---

# /feature-complete "<feature-slug>" [--force]

Archives the feature's working files after a PR has merged.
Moves .feature/<slug>/ to .feature/_archive/<slug>/ (which is gitignored).
The source code, tests, ADRs, and KB entries all remain — only the working
state files (brief, work plan, domains, cycle log, status) are archived.

Knowledge files, index updates, and the archive manifest are committed by
`/feature-pr` before the PR is created — this command is just the post-merge
directory move.

Use --force to archive even if status.md does not show refactor complete
(e.g. the feature was simple enough that full TDD wasn't used).

---

## Step 1 — Verify readiness

Read `.feature/<slug>/status.md`.

**Without --force:**
If Refactor stage is not `complete`:
```
Feature '<slug>' is not yet marked as refactor-complete in status.md.

Current stage: <stage>

If the feature is genuinely done (e.g. PR merged, all tests green), run:
  /feature-complete "<slug>" --force

If work is still in progress, continue with:
  <next command from status.md>
```
Stop.

**With --force:**
Show a warning:
```
⚠ Archiving '<slug>' before full pipeline completion.
Status shows: <stage> / <substage>

This is fine if:
  - The PR has already merged
  - You intentionally skipped stages (e.g. no refactor needed for small changes)

Use AskUserQuestion with options:
  - "Proceed"
  - "Stop"

---

Display opening header:
```
───────────────────────────────────────────────
📦 FEATURE COMPLETE · <slug>
───────────────────────────────────────────────
```

## Step 1b — Ensure narrative exists

Check if `.feature/<slug>/narrative.md` exists. If not, attempt to generate it:
```bash
bash .claude/scripts/narrative-wrapper.sh "<slug>" ".feature/<slug>"
```

If generation succeeds:
```
  📖 Narrative generated before archival: .feature/<slug>/narrative.md
```

If generation fails:
```
  ⚠️ Narrative generation failed. The feature will be archived without it.
  To generate after archival: bash .claude/scripts/narrative-wrapper.sh "<slug>" ".feature/_archive/<slug>"
```

Do not block archival on narrative failure — but always attempt it and always
report the outcome.

---

## Step 2 — Archive the working directory

Move `.feature/<slug>/` to `.feature/_archive/<slug>/`.
(If `units/` subdirectory exists inside the slug directory, it moves with it
automatically — no special handling needed.)

`.feature/_archive/` is gitignored — the archive stays on the local machine
as a short-term reference but does not go into the repository.

If `.feature/_archive/` does not exist, create it (it should have been created
by /setup-vallorcine, but create it if missing).

---

## Step 2b — Work group manifest update

**Skip this step if the feature slug does not have a `work_group` field in
status.md and does not match the `<group>--<wd>` double-dash convention.**

If this is a work-group-sourced feature:

1. Determine the work group slug (from status.md `work_group` field or slug prefix).
2. Verify the WD frontmatter has `status: COMPLETE` (should already be set
   by feature-refactor Step 6b). If not COMPLETE, set it now as a fallback.
3. Refresh `.work/CLAUDE.md` Active Work Groups counts via the index
   helper — recomputes `WDs / Ready / Complete` and bumps Last Updated:

   ```bash
   bash .claude/scripts/work-index.sh update "<group-slug>"
   ```

   Do not edit `.work/CLAUDE.md` by hand. The script reads each WD's
   frontmatter `status:` and re-derives the row counts; hand-edits drift
   from filesystem state and miss the date stamp.

---

## Step 3 — Report

If `.feature/<slug>/spec-coverage.md` exists and is non-vacuous (or has
been moved to `.feature/_archive/<slug>/spec-coverage.md` by Step 2),
include the coverage line in the report so the user sees the final
annotation state for the feature:

```bash
COVERAGE_LINE=""
if [[ -f .feature/_archive/<slug>/spec-coverage.md ]]; then
  COVERAGE_LINE=$(bash .claude/scripts/spec-coverage.sh report .feature/_archive/<slug>/spec-coverage.md 2>/dev/null || true)
fi
```

```
───────────────────────────────────────────────
📦 FEATURE COMPLETE · <slug>
───────────────────────────────────────────────
Feature '<slug>' archived.

Working files moved to: .feature/_archive/<slug>/
  (gitignored — local reference only)

<If $COVERAGE_LINE non-empty:>
$COVERAGE_LINE

Permanent records (not moved):
  ADRs:       .decisions/ (all decisions remain)
  KB entries: .kb/ (all research remains)
  Source:     in git history
  Tests:      in git history

To recover working files if needed:
  cp -r .feature/_archive/<slug>/ .feature/<slug>/
```

If work-group-sourced, append:
```
Work group: <group> — <complete>/<total> work definitions complete
Next ready WD: /work-start "<group>" next
```
