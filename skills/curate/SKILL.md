---
description: "Review codebase quality — find stale decisions, knowledge gaps, and implicit dependencies"
argument-hint: "[--init] [--deeper] [--verify [--analysis link-rot|falsification-stale|all]]"
---

# /curate [--init] [--deeper] [--verify]

Correlation engine that combines vallorcine's structured history with git data
to find things that individual features, decisions, and research sessions
couldn't see because they each had a narrower scope.

**What it finds:**
1. ADR pressure — decisions under concentrated change (scope being actively modified)
2. ADR gravity — files implicitly related to decisions but not in their scope
3. Hub files — shared dependencies across 3+ decisions (fragility/test concerns)
4. ADR drift — code diverging from architectural decisions
5. Stale KB — research that may have better approaches now given what's been built
6. Implicit dependencies — gaps between independently-designed features
7. Orphaned areas — high-churn files with no structured knowledge behind them
8. Unspecified shared types — foundational types referenced by 3+ specs with no spec
9. Spec obligations — DRAFT specs with unresolved conflicts blocking approval
10. Spec-code drift — specs whose domain code changed after the spec was written
11. Cross-reference gaps — KB entries and ADRs with missing related/source links
12. Missing `@spec` annotations — APPROVED specs with reqs that lack impl-side or test-side annotations
13. Aging open obligations — obligations on specs that haven't been committed in 30+ days
14. Link rot — KB-cited URLs that no longer resolve (4xx or connection failures)
15. Falsification-lens staleness — APPROVED specs authored before a falsification lens shipped that match the lens's keywords (candidates for re-falsification under the newer lens)
16. KB filename collisions — entries sharing a filename across folders (silently fragments search and pattern-recurrence evidence)
17. KB schema drift — frontmatter that does not match `.kb/_refs/frontmatter.md` (missing/bad-enum fields, confidence overclaim, path/frontmatter mismatch)
18. KB type/location mismatch — adversarial findings outside `patterns/<concern>/` or feature-footprints outside `architecture/feature-footprints/`
19. KB citation drift in source — `// KB:` / `# KB:` citations in changed source files that point at missing entries or whose entry's `applies_to` doesn't include the source file (closes the loop with the `check-kb-ref.sh` PostToolUse hook)
20. Spec graduation candidates — specs marked `status: DEPRECATED` that are still `state: APPROVED` (still entering `/spec-resolve` bundles despite the author's intent to retire them — finalize displacement or retract the status)
21. Spec corpus xref drift — corpus rollup of unresolvable `decision_refs` / `kb_refs` across all specs (per-spec `spec-validate.sh` warnings are easy to miss at scale)
22. Spec annotation coverage rollup — corpus-level summary across the four buckets (fully covered / drift / bare-only / unannotated). Frames `/spec-backfill --all` vs row-by-row routing decision.
23. ADRs without spec coverage — accepted/proposed ADRs that no spec references via `decision_refs`. Architectural intent without an operational contract.

**Flags:**
- `--init` — first-time scan (ignores last-scanned SHA, good for new installs)
- `--deeper` — scan 6 months instead of default 3
- `--obligation-age-days <n>` — override aging threshold for open obligations (default: 30)
- `--max-specs-traced <n>` — cap @spec annotation traces per run (default: 50)
- `--verify` — focused pass over verification-shaped candidates only
  (link-rot, falsification-staleness). Skips the broader correlation
  flow. Dismissals persist to `.curate/verify-dismissed.txt` so future
  scans don't re-prompt the same items.
- `--analysis <name>` — when used with `--verify`, restrict to a single
  analysis: `link-rot`, `falsification-stale`, or `all` (default: `all`).

This command feels like a colleague who noticed something and is offering to help,
not a task manager assigning work.

## Verify mode

When invoked with `--verify`, this skill runs the same scan but presents
ONLY the verification-shaped candidates from Analyses 21 (link rot) and
22 (falsification staleness). The broader correlation flow (ADR
pressure, hub files, spec-code drift, cross-ref repair, etc.) is
skipped — those signals belong to the regular `/curate` cadence.

Verify mode is a separate cadence: run it before major work (release
prep, audit kickoff) or monthly, when the heavier verification pass
is justified. Regular `/curate` stays drift-shaped; verify mode is
verification-shaped.

**Per-candidate flow:**
- Each link-rot row → AskUserQuestion with options: refresh via
  `/research`, mark accepted, dismiss, skip.
- Each falsification-stale row → AskUserQuestion with options: run
  depth pass via `/spec-author <id> --depth-pass-only --lens <name>`,
  decline (lens does not apply), dismiss, skip.

**Dismissal persistence.** When the user picks "dismiss" in verify
mode, append a row to `.curate/verify-dismissed.txt`:

```
<analysis>|<candidate-key>|<dismiss-date>|<reason>
```

Where `<candidate-key>` is the URL for link-rot or `<spec-id>:<lens>`
for falsification-staleness. Future verify-mode runs read this file
and skip any candidate whose key is dismissed (the underlying
`scan-summary.md` still surfaces them for non-verify `/curate` runs;
the dismissal only applies to the verify-mode prompt loop).

When the user picks "skip" instead of "dismiss", nothing is recorded
— the candidate resurfaces next verify-mode run.

---

## Step 0 — Pre-flight

Check that `.curate/` directory exists. If not, create it.

Read `.curate/curation-state.md` if it exists — extract the last-scanned SHA
from the Scan State section. (Older installs may still carry a Review Log
section in this file. Migrate it to the append-only review log on first run:)

```bash
if [[ -f .curate/curation-state.md ]]; then
  bash .claude/scripts/curate-review-log.sh migrate \
    .curate/curation-state.md .curate/review-log.md
fi
```

Migration is idempotent — re-running on a migrated state file is a no-op.
After this point, the review log lives at `.curate/review-log.md` and is
append-only. Never edit it by hand.

Read the unresolved items the user previously deferred or noted-for-later.
These will be re-surfaced in Step 2.5 alongside any new findings:

```bash
PRIOR_UNRESOLVED=$(bash .claude/scripts/curate-review-log.sh unresolved \
  .curate/review-log.md 2>/dev/null || true)
```

`PRIOR_UNRESOLVED` is a list of `<key>|<status>|<description>|<date>`
records. Empty when this is the first run or every prior finding was
resolved/dismissed.

**Stuck-marker recovery.** Scan `.curate/_dispatches/` for any
unacknowledged finding-resolution markers from a previous `/curate`
run that crashed mid-dispatch:

```bash
STUCK_MARKERS=$(bash .claude/scripts/dispatch-marker.sh stuck \
  .curate/_dispatches 2>/dev/null || true)
```

Each row is `<finding-key>|<dispatched-at>|<has-result>|<failure-reason>`.

If non-empty, surface BEFORE Step 1 (the scan run): for each stuck
marker, use AskUserQuestion with three options —
**"Re-dispatch"** (clear marker, include in this run),
**"Skip for now"** (leave marker; next run will resurface it),
**"Investigate manually"** (print marker JSON via
`dispatch-marker.sh status .curate/_dispatches <finding-key>` and
stop the `/curate` run).

This mirrors `/work-resume rule 0` (PR #79) and `/spec-backfill` C0 —
any unacknowledged marker pre-empts the normal flow because it
represents a previous dispatch whose result was never reconciled.

Display opening header:
```
───────────────────────────────────────────────
🔍 CURATION · scanning for quality signals
───────────────────────────────────────────────
```

---

## Step 0.5 — Index verification (self-healing)

Before scanning, run the index verification script to catch and repair any
index inconsistencies from previous crashes:

```bash
bash .claude/scripts/index-verify.sh --both 2>&1
```

If repairs are made, the script outputs what was fixed. Note these for the
findings presentation — they're bookkeeping fixes the user should know about
but don't need to act on.

If the script doesn't exist (older install), skip silently.

---

## Step 1 — Run the scan script

Build the scan command:

```bash
bash .claude/scripts/curate-scan.sh [--init] [--window <months>] \
  [--obligation-age-days <n>] [--max-specs-traced <n>]
```

- Default: `--window 3` (3 months, capped at 500 commits)
- If `--init` flag: pass `--init`
- If `--deeper` flag: pass `--window 6`
- If the user passes `--obligation-age-days` or `--max-specs-traced`, forward them
- The `--verify` flag does NOT change the scan invocation — the script still
  runs every analysis. Verify mode only narrows which candidates the
  pick-list presents in Step 3.

Run the script. If it exits with "No new commits since last scan," report that
and ask if the user wants to force a rescan with `--init`.

### Step 1.1 — Verify scan completeness via sentinel (REQUIRED)

After the scan script exits, before reading the summary in Step 2,
check that `.curate/scan-summary.md` ends with the scan-complete
sentinel. The sentinel is the last line and looks like:

```
✓ Scan complete: <iso-date> · max_specs_traced=<N> · specs_traced=<M> · scan_mode=<full|incremental> · window_months=<W>
```

A missing sentinel means the script exited before its final block —
the summary was partially written and **must NOT be read as
authoritative**. Common causes: Claude Code's default Bash timeout
(jlsm-sized repos can run 10–15 min if Analysis 18 traces all
APPROVED specs), manual Ctrl-C, context compaction mid-run.

**Check:**

```bash
tail -1 .curate/scan-summary.md | grep -q "^✓ Scan complete:"
```

If absent → the scan was interrupted. Surface to the user via
AskUserQuestion:

- **"Re-run with `--init --max-specs-traced 0`"** — recommended for
  large repos. Skips the per-spec annotation trace (Analysis 18),
  which is the only analysis that typically pushes runtime past 60s.
  Annotation-coverage rollup data will be absent; if needed, run a
  follow-up trace pass with `--max-specs-traced 50` (or higher) once
  the fast scan confirms the rest of the corpus is clean.
- **"Re-run with `--init`"** — fresh full scan; same timeout risk.
- **"Read partial summary anyway"** — only safe when the missing
  analyses are known to not apply (small repos, first-time setup).
  The user takes responsibility.

If the sentinel IS present, surface its contents to the user in one
line so they see the scope of what ran:

```
Scan complete: <date> · traced <M>/<approved-count> specs · window <W>m
```

**No-op scan detection** (CRIT 5, 2026-05-11 adversarial). When the
scan script exits "No new commits since last scan" or "No commits
found in scan range," it overwrites scan-summary.md with a `no-op`
marker — the sentinel includes the literal substring `· no-op ·`.
Detect this:

```bash
if tail -1 .curate/scan-summary.md | grep -q "· no-op ·"; then
    # No-op scan — prior findings already addressed or no qualifying
    # activity in window. Do NOT proceed into Step 2 with the prior
    # summary as if it were fresh.
fi
```

If detected, surface to the user via AskUserQuestion:

- **"Force a fresh scan (`--init`)"** — re-runs against the full window
  regardless of `LAST_SHA`.
- **"Expand the window (`--window-months N`)"** — useful when commit
  activity falls outside the default window.
- **"Stop — nothing to curate right now"** — exit cleanly.

Without this check, prior findings (potentially days/weeks old) get
re-presented as if they were just discovered — confusing the user and
re-surfacing already-resolved drift.

If `specs_traced=0` in the sentinel AND APPROVED specs exist in the
manifest, note that the annotation-coverage rollup (Analysis 18b) and
the per-spec annotation gap analyses (Analysis 18) did not run for
this scan. Offer to schedule a follow-up trace pass before closing.

---

## Step 1.5 — Verify-mode branch

If the user invoked `/curate --verify`:

1. **Filter Step 2 to subsections 2p (link rot) and 2q (falsification
   staleness) only.** Skip 2a-2o and 2r entirely. The other signals
   belong to the regular `/curate` cadence.
2. **Apply the analysis filter.** If the user passed
   `--analysis link-rot`, only run 2p. If `--analysis falsification-stale`,
   only run 2q. Default (or `--analysis all`) runs both.
3. **Read the dismissed-state file** at `.curate/verify-dismissed.txt`
   (touch it if missing). The format is one row per dismissal:
   `<analysis>|<candidate-key>|<date>|<reason>`. Build a transient set
   of dismissed keys.
4. **Filter candidates by dismissed-state.** When walking the candidate
   list from the scan summary, skip any candidate whose key matches a
   dismissed entry. The user already declined to act on it; don't
   re-prompt until the dismissed entry is manually removed.
5. **Step 3 pick list shows ONLY verify-mode items.** No other findings
   surface. The cold-start framing is also skipped — verify mode
   assumes structured artifacts already exist.
6. **Step 4 routing in verify mode.** When the user picks "dismiss" on
   a candidate, append a new row to `.curate/verify-dismissed.txt`:
   - For link-rot: `link-rot|<url>|<YYYY-MM-DD>|<one-line reason>`
   - For falsification-stale: `falsification-stale|<spec-id>:<lens>|<YYYY-MM-DD>|<one-line reason>`
   When the user picks "skip", do NOT write to the dismissed file —
   "skip" defers; "dismiss" persists.

If the user did NOT pass `--verify`, skip this entire section and run
Step 2 normally with all subsections.

---

## Step 2 — Read and correlate

Read `.curate/scan-summary.md` (the script's output).

Also read (if they exist):
- `.decisions/CLAUDE.md` — active decisions index
- `.kb/CLAUDE.md` — KB root index
- `.feature/CLAUDE.md` — active and archived features

### 2a — ADR drift detection

**ADR Pressure** (from "ADR Pressure" in scan summary):
1. ADRs with 2+ constrained files changed in the scan window
2. Higher pressure % = more of the decision's scope is actively changing
3. Read the ADR and assess: is the code evolving within the decision, or away from it?
4. High pressure (>60%) → strong signal for re-evaluation

**ADR Gravity** (from "ADR Gravity" in scan summary):
1. Files that co-change with ADR-constrained files but aren't in the ADR's scope
2. These are implicit relationships — the decision's influence is wider than documented
3. Assess: should these files be added to the ADR's `files:` field, or is the
   co-change coincidental?
4. High gravity (5+ unconstrained files for one ADR) → potential **isolation problem**.
   The decision may have drawn the boundary in the wrong place. Flag for `/architect`
   review with framing: "This decision's actual dependency footprint is larger than
   its documented scope — worth re-evaluating the boundary."

**Hub Files** (from "Hub Files" in scan summary):
1. Files co-changing with 3+ ADRs' constrained areas
2. These are fragility points — changes here ripple across multiple decisions
3. Flag as test coverage concerns: "This file is a shared dependency across
   <N> architectural decisions. Worth ensuring test coverage is solid."

**Flat artifact correlations** (from "Artifact Correlations" where Type is ADR):
1. Individual ADR file references not captured by pressure (single-file changes)
2. Read the referenced ADR, compare stated approach against changed files
3. Check if "Conditions for Revision" have been met by recent changes

### 2b — KB + hindsight review

For each entry in "Stale KB Entries":
1. Note the KB file and how long since last research
2. Cross-reference with "Churn Hotspots" — is the area the KB covers actively changing?
3. Check if any ADRs were made since the KB entry was written that might change
   which options are viable

For each entry in "Artifact Correlations" where Type is KB:
1. Note that implementation has changed since research was done
2. Flag if the changes suggest the research conclusions may need updating

### 2c — Implicit dependency detection

Using "Co-change Clusters" and "Artifact Correlations" where Type is FEATURE:
1. Identify file pairs that co-change but were designed in separate features
2. Check if cross-feature test coverage exists for the shared files
3. Flag gaps where independently-designed features share files without
   cross-coverage

### 2d — Orphaned areas

From "Orphaned Areas" in the scan summary:
1. Identify high-churn files with no KB, ADR, or feature coverage
2. These are backfill candidates — areas the codebase is actively changing
   but that have no structured knowledge behind them

### 2e — Test-source drift

From "Test-Source Drift" in the scan summary:
1. Source files that changed but their corresponding tests didn't
2. Cross-reference with feature archives — were these files part of features
   that should have had test updates?
3. Flag files where the drift is significant (3+ source commits with no test change)
4. This catches within-feature drift where implementation evolved but tests
   didn't keep pace

### 2f — Backfill candidates (implicit decisions)

From "Backfill Candidates" in the scan summary:
1. Archived feature domains that made implicit decisions (no governing ADR)
2. For each candidate, assess whether the decision is significant enough to
   warrant formal documentation
3. Present as items the user can decide, draft as ADR, defer, or dismiss
4. This subsumes the standalone `/decisions backfill` command — curate is the
   single entry point for finding undocumented decisions

### 2g — Out-of-scope items (deferred work in accepted ADRs)

From "Out-of-Scope Items" in the scan summary:
1. Items from "What This Decision Does NOT Solve" sections of confirmed ADRs
   that have no corresponding deferred decision stub
2. These are architectural concerns the team explicitly scoped out when making
   a decision — they are effectively deferred work invisible to `/decisions triage`
3. Group items by parent ADR for presentation
4. For each item, the user can: create a deferred stub, skip, or create all
   stubs from that parent ADR at once

### 2h — Spec coverage analysis

**Guard:** Only run this step if `.spec/` exists. If no spec directory, skip
entirely — don't mention specs or suggest setting up specs.

From "Spec Coverage Gaps" in the scan summary (if present):

**Unspecified shared types:**
1. Types referenced by 3+ specs that have no spec of their own
2. These are foundational types with implicit contracts — multiple specs
   depend on their behavior but nobody has defined what that behavior is
3. Rank by reference count — higher count = more dependent specs = bigger risk

**Specs with open obligations:**
1. Specs with `[UNRESOLVED]` or `[CONFLICT]` markers or `open_obligations`
   in frontmatter
2. These are blocking downstream work — DRAFT specs can't be relied on until
   obligations are resolved
3. Higher obligation count = more blocking

**Obligation registry (from _obligations.json):**
1. Open obligations from the centralized registry — spec requirements where the
   code does not match the spec. These are the gap between what was specified
   and what was built.
2. Group by spec for display. Show affected requirement count and blocked_by.
3. Route to `/work-decompose "<group>" --from-obligations` to convert
   obligations into a work group with proper WD ordering. This is the primary
   action — obligations without a work group have no implementation path.
4. Higher affected-requirement count = larger implementation gap.

**Spec-code drift:**
1. Specs whose domain files have been committed since the spec was created
2. Higher commit count = more likely the spec no longer matches reality
3. Cross-reference with ADR pressure — if the same area has both ADR pressure
   and spec drift, it's a stronger signal

**Undecided absent behaviors:**
1. Specs with `[ABSENT]` requirements — behaviors that downstream specs assume
   but the implementation doesn't provide
2. These are unresolved design decisions: each `[ABSENT]` requirement needs an
   explicit promote/preserve/defer choice
3. Higher count = more implicit assumptions without backing decisions

**Orphaned specs (no matching source code):**
1. APPROVED specs whose subject tokens were not found in any source file
2. These may describe behavior that was removed without updating the spec
3. For each orphaned spec, use AskUserQuestion with options:
   - **"Verify with /spec-verify"** — run spec-verify to check if the
     behavior still exists (subject token search may have missed it)
   - **"Mark as INVALIDATED"** — the behavior was removed; mark the spec
     as INVALIDATED with `displacement_reason: "behavior removed — detected
     by curate scan"`
   - **"Skip for now"** — defer to a later curation pass

### 2i — Cross-reference repair candidates

**Guard:** Only run this step if "Cross-Reference Candidates" section exists in
the scan summary. If absent, skip entirely.

From "Cross-Reference Candidates" in the scan summary:

**KB entries with missing related links (tag overlap):**
1. Entry pairs that share 2+ tags but have no `related` link between them
2. Higher tag overlap = stronger signal that these entries should reference each other
3. Entries in different categories are more valuable links — same-category entries
   are already navigable via category indexes
4. Assess whether the overlap is meaningful: shared tags like "performance" +
   "caching" between a caching strategy and a benchmarking entry → likely related.
   Shared tags like "java" + "testing" between unrelated entries → coincidental.

**KB entries with overlapping applies_to:**
1. Entries that target the same source files/patterns but don't reference each other
2. These likely describe different aspects of the same code — a `related` link
   helps the Research Agent find all relevant context when loading one entry
3. Stronger signal than tag overlap because file paths are specific

**ADR evaluation references not in KB Sources:**
1. KB entries cited in evaluation.md scoring that don't appear in the ADR's
   KB Sources Used table
2. These are missing traceability links — the ADR used this research during
   evaluation but doesn't formally reference it
3. Fix is straightforward: add the missing row to the KB Sources table

### 2j — Deferred audit feedback

**Guard:** Only run this step if "Deferred Audit Feedback" section exists
in the scan summary. If absent, skip entirely.

From "Deferred Audit Feedback" in the scan summary:

1. Each row is a `spec-updates.md` or `kb-suggestions.md` file from a
   completed audit where the user skipped or deferred the feedback loop
2. These contain ready-made spec requirements and KB pattern suggestions
   that a prior audit produced — they don't need re-analysis, just review
   and application
3. Present as high-priority pick list items — the work is already done,
   applying it is cheap

When the user picks one of these items:
- Read the file at the path shown in the scan summary
- Present the contents using the same apply/review/skip (for specs) or
  create/select/skip (for KB) menus from the audit feedback loop
  (see audit SKILL.md Job 5a/5b for the exact flow)
- After applying: rename the file from `<name>.md` to `<name>.applied.md`
  so it won't be picked up by future curate scans or audit feedback loops

### 2k — Decisions roadmap needed

**Guard:** Only run this step if "Decisions Roadmap Needed" section exists
in the scan summary. If absent, skip entirely.

From "Decisions Roadmap Needed" in the scan summary:

1. There are 10+ deferred decisions with no current roadmap
2. Present as a high-priority pick list item: "N deferred decisions need
   planning — run `/decisions roadmap` to cluster and prioritize"
3. When the user picks this item: suggest running `/decisions roadmap` in
   a separate session (roadmap is a planning skill, not a curate action)

### 2l — Work group health

**Guard:** Only run this step if any "Work Group:" section exists in the scan
summary. If absent, skip entirely.

**Displaced dependencies:**
1. Work definitions that depend on specs now INVALIDATED
2. These WDs are effectively BLOCKED by a spec that no longer exists
3. For each, use AskUserQuestion with options:
   - **"Author replacement spec"** → suggest `/spec-author` for the missing spec
   - **"Update WD to remove dependency"** → the WD no longer needs this artifact
   - **"Skip for now"** — defer

**Stalled work groups:**
1. Work groups with no WD activity in 14+ days
2. Present the group name, total WDs, completed WDs, and days since last activity
3. For each, use AskUserQuestion with options:
   - **"Check status"** → run `/work-status "<group>"`
   - **"Skip"** — acknowledged, no action needed

**Artifact drift:**
1. WDs whose artifact dependencies were modified after the WD was written
2. The artifact still exists but its content changed — the WD's assumptions
   may be stale
3. For each, use AskUserQuestion with options:
   - **"Review WD"** → read the WD and the changed artifact, assess impact
   - **"Skip"** — the change was minor and doesn't affect the WD

### 2m — Spec annotation coverage gaps

**Guard:** Only run this step if "Spec Annotation Coverage Gaps" section exists
in the scan summary. If absent, skip entirely.

From "Spec Annotation Coverage Gaps" in the scan summary:

**Requirements missing impl- or test-side annotations:**
1. Rows with gap "test-only → missing impl annotation" mean a test is tagged
   with `@spec <sid>.Rn` but no implementation file carries the same tag. The
   requirement may be unimplemented, or the impl exists but was never annotated.
2. Rows with gap "impl-only → missing test annotation" mean implementation is
   tagged but no test is. The requirement may be untested, or a test exists
   but was never annotated.
3. Higher req count per spec = bigger coverage hole.

**APPROVED specs with no annotations at all:**
1. The spec is APPROVED but `spec-trace` found zero `@spec` references in
   source or test. Either the code was never annotated, or the spec no longer
   describes any implemented behavior (overlap with orphaned-spec detection).
2. These are higher-priority than single-requirement gaps because the whole
   spec's traceability is missing.

For each finding, use AskUserQuestion with options:
- **"Backfill via /spec-backfill"** → routes to `/spec-backfill <spec-id>`
  to walk uncovered requirements and apply annotations to existing code.
  This is the right tool for the "no annotations at all" case and for
  single-requirement gaps where the implementation already exists.
- **"Verify via /spec-verify"** → use when the gap may indicate spec→code
  drift (the spec describes behavior that may no longer be in the code, or
  vice versa). `/spec-verify` classifies and repairs spec violations; it is
  heavier than `/spec-backfill` and not the default for pure annotation
  backfill.
- **"Accept gap with justification"** → the gap is intentional (e.g. the
  requirement is pure documentation; no runtime behavior to annotate). Record
  in the curation state review log with a short justification.
- **"Skip for now"** — defer to next /curate pass

### 2m-drift — Annotation drift (partial coverage below 50%)

**Guard:** Only run this step if the "Annotation drift — APPROVED specs
below 50% coverage" subsection exists under "Spec Annotation Coverage Gaps"
in the scan summary. If absent, skip entirely.

This subsection lists APPROVED specs whose annotation coverage has slipped
below 50% — they have *some* annotations (so they are not in the
unannotated bucket above) but are drifting. Rows are ordered by uncovered-
percentage descending, then by spec-file age descending.

If there are 4+ drifted specs, ask the user once whether to handle them
individually or run a corpus walk. Use AskUserQuestion with options:
- **"Run /spec-backfill --all"** → the corpus walk catches drift across
  every spec in one pass; progress persists in `.spec/backfill-log.md`
  so the user can break out and resume.
- **"Walk specs one at a time"** → fall through to per-spec routing below.

For each drifted spec (or each one when walking individually), use
AskUserQuestion with options:
- **"Backfill via /spec-backfill <spec-id>"** → routes to per-spec walk.
- **"Skip for now"** — defer to next /curate pass.
- **"Dismiss as intentional"** — record in the review log so this spec
  no longer appears in drift findings (e.g. an aspirational spec where
  partial coverage is by design).

### 2n — Aging open obligations

**Guard:** Only run this step if "Aging Open Obligations" section exists in
the scan summary. If absent, skip entirely.

From "Aging Open Obligations" in the scan summary:

1. Each row shows a spec ID, age in days since the spec file was last committed,
   and the obligation text.
2. The age is a proxy — the obligation has survived that long without the spec
   being touched, suggesting it's drifted out of active attention.
3. Higher age = more drift. 60+ days is a strong signal; 30-60 is a reminder.

For each aging obligation, use AskUserQuestion with options:
- **"Resolve via /spec-author"** → run `/spec-author` on the spec to either
  author the missing behavior as new requirements or close the obligation as
  intentional
- **"Resolve via /spec-resolve"** → use `/spec-resolve` to work through
  `[UNRESOLVED]` / `[CONFLICT]` markers if the obligation is a conflict
- **"Close as stale"** → the obligation is no longer relevant; remove it from
  the spec's `open_obligations` frontmatter with a short note in the spec's
  design narrative explaining the closure
- **"Skip for now"** — defer to next /curate pass

### 2p — Link rot in KB entries

**Guard:** Only run this step if "Link Rot in KB Entries" section exists in
the scan summary. If absent, skip entirely.

From "Link Rot in KB Entries" in the scan summary:

1. Each row shows a status code, the KB entry path, the URL, and when it
   was last checked. Status `000` indicates a connection failure (DNS,
   timeout, refused). Status `4xx` indicates the server responded but the
   resource is gone.
2. Dead URLs in KB entries silently rot the knowledge: the stored fact
   looks authoritative but the source it claims to ground no longer
   exists. Higher-impact when the KB entry is heavily cross-referenced.
3. The script caches per-URL results (7-day TTL) so the same dead URLs
   don't trigger fresh `curl` requests on every scan.

For each candidate, use AskUserQuestion with options:
- **"Refresh via /research"** (description: "Run /research <subject> to
  re-investigate the topic and replace the dead citation with a current
  source")
- **"Verify via /curate --verify"** (description: "Confirm via WebFetch
  that the URL is genuinely gone before refreshing — useful when transient
  connection failures may have produced false positives")
- **"Mark as accepted"** (description: "The URL is gone but the cited
  fact is still valid in the KB; record acceptance in the curation
  review log so the same URL doesn't resurface")
- **"Skip"** — defer to next /curate pass

If "Refresh": invoke `/research "<subject inferred from KB entry>" context: "curate: dead citation at <kb-path>, URL <url> returned <status>"`.
If "Mark as accepted": append the URL to a `link-rot-accepted` block in
`.curate/curation-state.md`. The cache continues to track it; future scans
surface it but the review log shows the user's prior acceptance.

### 2q — Falsification-lens staleness

**Guard:** Only run this step if "Falsification Lens Staleness" section
exists in the scan summary. If absent, skip entirely.

From "Falsification Lens Staleness" in the scan summary:

1. Each row shows an APPROVED spec, its git first-commit-touched date,
   the lens whose introduction date post-dates the spec, and the keyword
   from the spec body that matched the lens's pattern.
2. The signal: the spec's original Pass 2 falsification predates this
   lens shipping, so attack categories the lens covers (e.g., adversary-
   model patterns from the security lens shipped in v0.14.2) may not
   have been considered.
3. The match is heuristic. A spec mentioning "auth" doesn't necessarily
   need a security depth pass; the user judges whether the lens applies.

For each candidate, use AskUserQuestion with options:
- **"Run depth pass via /spec-author"** (description: "Run
  `/spec-author <spec-id> --depth-pass-only --lens <lens>` to re-falsify
  the spec under the named lens; findings flow through the standard
  arbitration UI")
- **"Decline — lens does not apply"** (description: "The keyword match
  is incidental; the spec's scope does not actually need the lens's
  attack categories. Records a decline so future scans don't resurface
  this lens for this spec")
- **"Skip"** — defer to next /curate pass

If "Run depth pass": invoke
`/spec-author <spec-id> --depth-pass-only --lens <lens>` directly.
If "Decline": append a `falsification-decline` row to
`.curate/curation-state.md` keyed by `<spec-id>:<lens>`. The script
continues to surface this candidate, but the review log shows the
user's prior decline.

### 2o — Subdivision candidates (mature specs that may want to subdivide)

**Guard:** Only run this step if "Subdivision Candidates" section exists in
the scan summary. If absent, skip entirely.

From "Subdivision Candidates" in the scan summary:

1. Each row shows a spec that has grown past one file's worth of behavior
   (≥50 reqs OR ≥15K tokens) AND shows multiple distinct concerns
   (≥2 section headers, no single section dominating).
2. Subdivision is a **natural progression** for these specs — the parent
   stays a full spec retaining cross-cutting requirements, while concern-
   specific reqs move to child specs. The detection is heuristic; a spec
   that looks subdividable on paper may turn out to be a single tightly-
   coupled concern that just happens to have multiple section headers.
3. The script already filters out specs where one section holds ≥90% of
   the requirements (those are mature-but-singular and not real candidates).

For each candidate, use AskUserQuestion with options:
- **"Subdivide via /spec-split"** → run `/spec-split <spec-id>`. The skill
  will propose concern boundaries from the spec's existing section
  structure, confirm with you (with edit option), and execute the split
  with @spec annotation rewrites + automatic rollback on validation
  failure.
- **"Decline — concerns are interlocked"** → mark this spec as a recent
  decline so a future /curate pass doesn't surface it again immediately.
  Add a one-line note to the spec's design narrative explaining why it
  shouldn't subdivide (e.g. "single algorithm, requirement clusters
  reflect implementation phases, not separable concerns").
- **"Defer"** → the spec is a candidate but you're not ready to subdivide
  this session. It will resurface at the next /curate run.

The "Decline — concerns are interlocked" option is important. Subdivision
fragments a coherent contract when forced; it should never be automatic.
Honest declines are a feature, not a failure.

### 2r — KB structural drift

**Guard:** Only run this step if any of the following sections exist in the
scan summary: "KB Filename Collisions", "KB Schema Drift", "KB Type/Location
Mismatch". If none exist, skip entirely.

These three analyses share a goal — keep the KB's structure aligned with
`.kb/_refs/frontmatter.md` so search, cross-reference repair, and type-aware
loaders work. They are presented together because the user's typical action
is the same: review one entry's drift and apply the patch.

**KB filename collisions** (from "KB Filename Collisions" in scan summary):

1. Each row shows a filename that exists at 2+ paths under different
   folders. Cross-folder collisions silently fragment grep, pattern-
   recurrence evidence, and `kb-search.sh` ranking. A reader running
   `grep partial-init-no-rollback.md .kb` gets N hits and cannot tell
   which is canonical.
2. Resolve by renaming the lesser-used variant(s) to disambiguate (e.g.,
   `builder-pre-validation-mutation.md` and `multi-step-init-no-rollback.md`).
3. Alternatively, if the collision is intentional and benign, dismiss with a
   one-line reason — but the default assumption is that a collision is drift.

For each collision, use AskUserQuestion with options:
- **"Rename one variant"** (description: "Choose which path keeps the name; the
  other gets a more specific filename. /curate updates references that point
  at the renamed file.")
- **"Merge into one entry"** (description: "If the entries cover the same
  pattern, merge into the canonical location and delete the duplicate.
  Append the deleted entry's `## Audit Findings` history to the kept entry.")
- **"Dismiss as intentional"** (description: "Record in review log; won't
  resurface")
- **"Skip"** (description: "Defer to next /curate pass")

**KB schema drift** (from "KB Schema Drift" in scan summary):

1. Each row is one issue per entry. Issue codes:
   - `missing-frontmatter` — no YAML block at top.
   - `missing-<field>` — required core or type-specific field absent.
   - `bad-<field>` — value outside the allowed enum (e.g.
     `research_status: foo`).
   - `legacy-<field>` — deprecated value in use (e.g.
     `research_status: archived` should be `deprecated`).
   - `confidence-overclaim` — `confidence: high` without ≥2 corroborating
     sources or `## Found in` entries.
   - `topic-mismatch` / `category-mismatch` — frontmatter field disagrees
     with the file's path (path is canonical).
2. An entry with multiple issues appears multiple times. Resolve them
   together when picking that entry.
3. Drift breaks tag-based search, cross-reference repair, and the
   type-aware loaders in `/research`, audit, and feature-retro.

For each entry (group rows by path), use AskUserQuestion with options:
- **"Apply patches"** (description: "/curate proposes the minimal edits — add
  missing fields with derived values, fix enum values, downgrade
  unsupported confidence, sync topic/category to path. Review each patch
  before write.")
- **"Walk one issue at a time"** (description: "Present each issue individually
  with its own apply/skip choice. Use when patches need per-issue judgment.")
- **"Dismiss the entry"** (description: "The drift is intentional or the
  entry is being retired. Record in review log.")
- **"Skip"** (description: "Defer to next /curate pass")

When applying patches, derive values from the entry's existing content where
possible — e.g., infer missing `last_researched` from git-blame's most-recent
commit, infer missing `type:` from section headings (`## What happens` +
`## Found in` ⇒ `adversarial-finding`).

**KB type/location mismatch** (from "KB Type/Location Mismatch" in scan summary):

1. Each row shows an entry whose declared `type:` does not match its path
   prefix:
   - `type: adversarial-finding` MUST live under `patterns/<concern>/`.
   - `type: feature-footprint` MUST live under
     `architecture/feature-footprints/`.
2. Adversarial findings in `algorithms/` or `systems/` are invisible to the
   test-writer that loads findings from `patterns/<concern>/` — they don't
   show up in defensive-vector generation or audit lens loads. The bug they
   describe gets re-discovered.

For each mismatch, use AskUserQuestion with options:
- **"Relocate the entry"** (description: "Move to the canonical path under
  `patterns/<concern>/` (for findings) or `architecture/feature-footprints/`
  (for footprints). Update all incoming `related:` links. /curate proposes
  a destination; the user can override.")
- **"Re-classify the type"** (description: "The entry isn't actually a finding
  / footprint — it's research that mentions a finding. Change `type:` to
  `research`, leave the location, and split the actual finding into a new
  entry under `patterns/`.")
- **"Dismiss as intentional"** (description: "Rare; the location is
  deliberately non-canonical. Record in review log.")
- **"Skip"** (description: "Defer to next /curate pass")

When relocating, propose the destination as `patterns/<concern>/<basename>` —
the writer must still pick the appropriate concern (`validation`,
`concurrency`, `resource-management`, `testing`, `transactions`).
`/curate` infers the concern from the entry's `domain:` field (for
adversarial-findings) or asks the user.

### 2s — KB citation drift in source

**Guard:** Only run this step if the "KB Citation Drift in Source" section
exists in the scan summary. If absent, skip entirely.

This analysis closes the loop with the `check-kb-ref.sh` PostToolUse hook:
the hook fires at write-time, this analysis catches the cases the hook
missed (kit installed mid-stream, file edited before the hook landed,
citation predates an entry rename). Every row is a `// KB:` / `# KB:` /
`<!-- KB: -->` citation in a source file that doesn't reconcile with the
KB.

Two reason codes:

- `missing-entry` — the cited path doesn't resolve. The KB entry was
  renamed, deleted, or never existed. The citation is rotted.
- `applies_to-mismatch` — the cited entry exists, but its `applies_to`
  doesn't include the source file. Either the citation is wrong (likely
  copy-paste from another file) or the entry's `applies_to` is too
  narrow.

For each row, use AskUserQuestion with options:

- **"Update the citation"** (description: "The citation is wrong. Edit
  the source file to point at the correct KB entry, or remove the
  citation if no KB applies. /curate proposes the right entry from
  `applies_to` matches when possible.")
- **"Extend the entry's applies_to"** (description: "The citation is
  correct but the cited entry's `applies_to` is too narrow. Add the
  source file (or a glob covering it) to the entry's `applies_to:`
  frontmatter list. Stage the change with `git add`; user commits.")
- **"Dismiss as intentional"** (description: "Rare; e.g., the citation
  is to a parent-domain entry that the writer wanted to reference even
  though `applies_to` is more specific. Record in review log.")
- **"Skip"** (description: "Defer to next /curate pass")

For `missing-entry`: only "Update the citation" / "Dismiss" / "Skip" make
sense (you can't extend an entry that doesn't exist).

For `applies_to-mismatch`: when the user picks "Extend", `/curate`
proposes a glob — usually the broadest folder under which the source
file lives (e.g. `modules/auth/**` rather than the exact file path).
Confirm with the user before staging.

---

## Step 2.5 — Merge in unresolved prior items

The pre-flight (Step 0) read `PRIOR_UNRESOLVED` from the append-only review
log. These are items the user previously chose to defer or noted-for-later
without acting on. They are NOT new findings — they are the kit's promise
to the user that "skipped items will resurface next /curate run" (see the
closing report's wording).

For each line in `PRIOR_UNRESOLVED` (`<key>|<status>|<description>|<date>`):

1. Check whether the same `<key>` is already represented in the current
   scan's findings (e.g., `adr-pressure:auth-session-storage` is in both
   the scan's pressure list and the prior unresolved set). If so, leave
   it as a current-scan finding — no duplicate; the act of seeing it
   again is what the user needs.
2. If the key is not represented in the current scan (the underlying
   signal aged out, OR thresholds shifted), surface it anyway as a
   "previously-deferred" item, with its description and the date the
   user deferred it. The user explicitly didn't resolve it; they should
   see it again.

Build a deprioritized "Previously deferred" group for the pick list. It
appears AFTER all current-scan groups in Step 3, so new findings get
attention first but old commitments aren't lost.

Format for the group:

```
Previously deferred (from prior /curate runs):
  N. <description> — deferred <date>, key: <key>
     → I'll re-present the same options as last time
```

Routing for prior-deferred picks: re-read the key prefix to determine
which Step-2 sub-section's resolution flow applies (e.g.,
`adr-pressure:` → 2a path, `spec-drift:` → 2h path,
`kb-stale:` → 2b path, `link-rot:` → 2p path, etc.). If a key prefix
doesn't match any current sub-section (rare — usually means the kit
was upgraded and a category was renamed), present the description and
let the user describe what to do next via "Other".

---

## Step 3 — Present findings as a numbered pick list

Present findings as a numbered list, grouped by priority (highest first).
Each item gets: the problem, why it matters, and what you'll do if they pick it.
Lead with the most actionable items. Tone: offering help, not assigning tasks.

### Cold start (no existing KB/ADRs/features)

When there are no artifact correlations (everything is orphaned), present as
a prioritized bootstrapping guide:

```
I scanned the last <N> months of changes (<N> commits) and found <N> areas
worth exploring:

  1. <Area> (<files>) — <N> commits, <observation>.
     → I'll research how this is structured and write a KB entry

  2. <Area> (<files>) — <observation>.
     → I'll run an architecture review to document the current approach

  3. <Area> (<files>) — <observation>.
     → I'll explore this area and surface anything worth documenting

Items you don't address are saved automatically — run /curate anytime to pick them up.
```

Use AskUserQuestion to let the user choose. Build options dynamically:
- If 4 or fewer items: one option per item (labeled with its number and
  short description), plus `All` (description: "Work through each item in
  order") and `Done` (description: "Note remaining items for next /curate run").
- If more than 4 items: use `All`, `Done`, and `Other` (description: "Type
  a number to start with"). If the user selects "Other", wait for them to
  provide the item number as free text.

### Warm repo (has existing artifacts)

Present correlations first (numbered), then orphaned areas:

```
I scanned <N> commits since last review and found <N> items:

  1. <Index/integrity issue> — <what's broken and impact>
     → I'll fix this now (no confirmation needed, it's bookkeeping)

  2. <ADR slug> — <N>% pressure (<M> of <T> constrained files changed)
     → I'll compare the current code against this decision

  3. <ADR slug> — <N> unconstrained files co-changing with its scope
     → This decision's boundary may not match the actual dependencies.
       I'll review the isolation.

  4. <Hub file> — shared across <N> decisions (<slugs>)
     → I'll check test coverage for this shared dependency

  5. <ADR slug> — <what changed and why the decision may not fit>
     → I'll re-evaluate this decision against the current codebase

  6. <KB entry> — last researched <date>, <what's changed since>
     → I'll refresh this research with current implementation context

  7. <Shared files> — touched by <feature A> and <feature B>, no cross-coverage
     → I'll explore the interaction and flag anything missed

  8. <parent-adr-slug> — <N> out-of-scope items with no deferred stubs
     → I'll show them and you can choose which to track as deferred decisions

  9. <TypeName> — referenced by <N> specs but has no spec of its own
     → I'll run spec extraction to define its contract and find cross-spec conflicts

 10. Spec <ID> (<name>) — <N> unresolved conflicts blocking APPROVED status
     → I'll show the conflicts so you can resolve them via /spec-author

 11. Spec <ID> (<name>) — <N> commits to related files since spec was written
     → I'll check if the spec still matches the implementation via /spec-verify

 12. Spec <ID> (<name>) — <N> undecided [ABSENT] requirements need explicit decisions
     → I'll show each one so you can promote, preserve, or defer

 13. <Orphaned files> — <N> commits, no KB or decision coverage
     → I'll research this area so future work has context

 14. <N> KB entries may need `related` links — <N> tag-overlap pairs, <N> applies_to overlaps
     → I'll show the most likely candidates so you can add or dismiss each link

 15. <adr-slug> — evaluation references <N> KB entries not in its Sources table
     → I'll add the missing references to the ADR

 16. Spec <ID> — <N> requirements missing impl- or test-side @spec annotations
     → I'll run /spec-verify so we can add annotations, write missing tests, or accept gaps

 17. Spec <ID> — open obligation aging <N> days (spec file not committed in that time)
     → I'll route to /spec-author or /spec-resolve to close or resolve it

 18. <KB entry> — <N> dead citation URLs (status <code>)
     → I'll show each one so you can refresh via /research or accept the rot

 19. Spec <ID> — authored <date>, predates <lens> lens (matched keyword "<word>")
     → I'll show the lens scope so you can run a depth pass or decline

 20. <N> KB filename collisions — `<basename>` exists at <N> paths
     → I'll show each so you can rename, merge, or dismiss

 21. <N> KB schema-drift issues across <M> entries
     → I'll group by entry and propose patches against `.kb/_refs/frontmatter.md`

 22. <N> KB type/location mismatches — adversarial-findings outside `patterns/` or footprints outside `architecture/feature-footprints/`
     → I'll propose a relocation or type reclassification per entry

 23. <N> KB citation drift rows in changed source files — `// KB:` lines pointing at missing entries or whose entry's `applies_to` doesn't include the source file
     → I'll propose either a citation update or an `applies_to` extension per row

Items you don't address are saved automatically — run /curate anytime to pick them up.
```

Use AskUserQuestion to let the user choose. Build options dynamically:
- If 4 or fewer items: one option per item (labeled with its number and
  short description), plus `All` (description: "Work through each item in
  order") and `Done` (description: "Note remaining items for next /curate run").
- If more than 4 items: use `All`, `Done`, and `Other` (description: "Type
  a number to start with"). If the user selects "Other", wait for them to
  provide the item number as free text.

### After completing an item

After resolving an item, re-present the remaining list (renumbered) so the
user can pick the next one without having to remember what was left:

```
Done. <N> items remaining:

  1. <next item> — <description>
     → <action>

  2. ...

```

Use AskUserQuestion to let the user choose. Build options dynamically:
- If 4 or fewer remaining items: one option per item (labeled with its number
  and short description), plus `Done` (description: "Note remaining items for
  next /curate run").
- If more than 4 remaining items: use `Done` and `Other` (description: "Type
  a number to continue with"). If the user selects "Other", wait for them to
  provide the item number as free text.

### Nothing found

```
I scanned <N> commits since last review — nothing flagged.

Your KB entries are current, ADRs align with the code, and there are no
obvious coverage gaps. Nice.

Next scan will pick up from here automatically.
```

---

## Step 4 — Handle user response (LOOP — always return to pick list)

**CRITICAL: After completing ANY item, ALWAYS return to the pick list with
remaining items. NEVER go to the closing report until the user explicitly
says "done" or all items are resolved. The user controls when curation ends,
not the agent.**

The flow is a loop:
```
Present numbered list → user picks → execute action → mark resolved →
re-present remaining items → user picks again → ... → user says "done" → close
```

### Step 4 dispatch protocol (context-economy on long sessions)

When a `/curate` run surfaces 20+ findings, resolving each finding
inline accumulates file-read context in the coordinator linearly with
the finding count. For a 30-finding session that resolves a mix of
ADR/KB/spec findings, the coordinator can carry 200–300 KB of read
state by the end. The dispatch protocol below isolates that
read-cost in per-finding sub-agents and keeps the coordinator's
context bounded.

**Pattern: two-phase dispatch per finding.** Dispatched sub-agents
follow the codebase convention (`/work-start all`, `/feature-coordinate`)
of running autonomously — they do NOT call AskUserQuestion mid-flow.
User interaction happens in the coordinator between the two phases.

**When to use dispatch:** findings whose resolution involves reading
artifact files (ADR, KB entries, spec frontmatter, source files).
The list is recorded in the **Dispatchable types** table below. When
the user picks a finding NOT in that table (index rebuild, log
appends, trivial bookkeeping), handle inline as today.

**Dispatchable types** (heavy file reads in resolution):

| Type | Why it qualifies |
|------|------------------|
| ADR pressure / gravity / drift | Reads full ADR file + constrained file list |
| KB stale | Reads KB entry full text + related entries |
| Spec coverage / spec-code drift | Reads spec frontmatter + manifest + source matches |
| Spec annotation drift (Analysis 18b drift bucket) | Reads spec file + spec-trace output |
| Spec graduation candidate (Analysis 27) | Reads spec frontmatter + invalidates-references |
| Spec corpus xref drift (Analysis 28) | Reads spec frontmatter + ADR/KB resolution |
| ADRs without spec (Analysis 29) | Reads full ADR file to scope the spec to author |
| KB schema drift / type-location mismatch | Reads KB entry frontmatter + body |
| Subdivision candidate | Reads full spec body to assess split |

**Pre-flight: stuck-marker recovery.** Before re-entering the pick
list after a prior `/curate` run, check
`.curate/_dispatches/` for unacknowledged markers:

```bash
bash .claude/scripts/dispatch-marker.sh stuck .curate/_dispatches
```

If non-empty, surface each one via AskUserQuestion:
- **"Re-dispatch <finding-key>"** — clear the marker, include the
  finding in this run.
- **"Skip <finding-key>"** — leave marker in place; it will resurface
  next run.
- **"Investigate manually"** — print the marker JSON via
  `dispatch-marker.sh status` and stop.

This mirrors `/work-resume rule 0` and `/spec-backfill` C0.

**Phase A — diagnose + propose** (autonomous sub-agent):

```bash
bash .claude/scripts/dispatch-marker.sh begin .curate/_dispatches <finding-key>--propose
```

Agent prompt verbatim (substitute `<finding-key>`, `<finding-type>`,
`<scan-summary-excerpt>` — copy the 1–3 rows from
`.curate/scan-summary.md` that describe this finding):

```
You are the diagnose + propose stage for /curate finding
<finding-key> of type <finding-type>.

Scan summary excerpt:
<scan-summary-excerpt>

Read whatever artifacts the resolution playbook for this finding type
requires (see `.claude/skills/curate/SKILL.md` Step 4 subsections —
look up the row whose label matches `<finding-type>` and follow its
"Read the X file" / "compare against Y" instructions for the read
portion ONLY). Build a structured proposal.

Return EXACTLY ONE LINE — a JSON object — matching this shape:

{"finding_key":"<finding-key>","finding_type":"<type>",
 "diagnosis":"<2–3 sentence summary of what you found>",
 "options":[
   {"label":"<≤4 words>","description":"<≤80 chars>",
    "side_effect":"<one of: invoke-architect | invoke-research |
                   invoke-spec-author | edit-file | log-only | other>",
    "side_effect_args":{...}}
 ],
 "auto_applicable":<bool>,
 "auto_apply_instructions":<string|null>}

Cap at 4 options. Always include a "Skip" option as the LAST option.

`auto_applicable: true` is allowed ONLY for these types: index rebuild
(not in dispatchable list — would not reach this prompt), `kb-citation`
with a single obvious successor target (rename-and-update mechanical).
For all other types, set `auto_applicable: false`. The coordinator
treats out-of-whitelist auto_applicable claims as `false` regardless.

DO NOT call AskUserQuestion. DO NOT edit any files. DO NOT log
anything. Read-only stage. Any other return shape is a parse failure.
```

**Parse the proposal + ack marker.** Validate JSON via `jq -e
'.finding_key and .options'`. On parse failure, mark
`parse-failed: <first-80-chars>` and surface AskUserQuestion to the
user with recovery options (re-dispatch, skip, handle-inline).

```bash
bash .claude/scripts/dispatch-marker.sh ack .curate/_dispatches <finding-key>--propose "<diagnosis>"
```

**Coordinator: AskUserQuestion.** Present `diagnosis` as the
preamble; build options from the `options[]` list. The user's choice
becomes the input to Phase B.

If `auto_applicable: true` AND the type is in the whitelist
(`kb-citation` only), skip the AskUserQuestion and proceed directly
to Phase B with the `auto_apply_instructions`.

**Phase B — apply** (autonomous sub-agent, idempotent):

```bash
bash .claude/scripts/dispatch-marker.sh begin .curate/_dispatches <finding-key>--apply
```

Agent prompt verbatim:

```
You are the apply stage for /curate finding <finding-key>.

Chosen option:
  label: <user's chosen label>
  side_effect: <one of: invoke-architect | invoke-research |
                invoke-spec-author | edit-file | log-only | other>
  side_effect_args: <JSON from proposal>

Execute the side effect:

- invoke-architect → Use the Agent tool to invoke /architect with the
  arguments in side_effect_args.problem_statement. Wait for return.
- invoke-research → Use the Agent tool to invoke /research with
  side_effect_args.subject.
- invoke-spec-author → Use the Agent tool to invoke /spec-author with
  side_effect_args.feature_id + side_effect_args.title.
- edit-file → Use Edit tool to apply side_effect_args.old_string →
  side_effect_args.new_string in side_effect_args.file_path.
- log-only → no side effect; just log to review-log.
- other → side_effect_args.notes describes the action; record it in
  review-log with status `manual-resolution-required`.

After executing, append to .curate/review-log.md via:
  bash .claude/scripts/curate-review-log.sh append \
    .curate/review-log.md "$(date +%F)" "<finding-key>" \
    "<status: resolved | deferred | skipped | manual-resolution-required>" \
    "<one-line notes>"

Return EXACTLY ONE LINE:

  RESOLVED|<finding-key>|<one-line-summary>
  DEFERRED|<finding-key>|<reason>
  SKIPPED|<finding-key>
  MANUAL|<finding-key>|<reason>

DO NOT call AskUserQuestion. The decision is final. Any other return
is a parse failure.
```

**Parse Phase B + ack the apply marker.** Same payload-lost /
user-stopped / parse-failed handling as `/spec-backfill` C2e. On
success, ack the marker:

```bash
bash .claude/scripts/dispatch-marker.sh ack .curate/_dispatches <finding-key>--apply "<return-line>"
```

Return to the pick list with the finding marked resolved.

**Why this works across the dispatch boundary:**

- Each sub-agent has a fresh context window — its file reads cost ~0
  to the coordinator.
- The coordinator holds only: the pick list (text), the in-flight
  finding's proposal JSON (~1–2 KB briefly), the user's choice
  (<100 bytes), the final summary (<200 bytes kept across iterations).
- After 30 findings: ~6 KB of accumulated summaries vs ~200 KB
  inline today.

The protocol's first cut applies to the **Dispatchable types** above.
Light findings (index rebuild, log appends, no-artifact-read
bookkeeping) continue to use the inline patterns below.

### User picks a number — inline patterns (light findings + fallback)

For findings NOT in the **Dispatchable types** table above, OR if the
dispatch fails and the user opts to "handle inline" during recovery,
execute the action directly per the playbooks below. These are also
the playbooks the dispatched sub-agent reads to know what to do —
the only difference is who holds the file-read context.

**Index/integrity fixes:** Fix directly — rebuild indexes, clean up stale
entries. These are bookkeeping and don't need architectural judgment.

**ADR pressure:** Read the ADR file, then compare the decision's stated approach
against the changed constrained files. Present a summary: "This decision
constrains <N> files and <M> have changed. Here's what shifted: <brief
description>."

Use AskUserQuestion:
  - "Re-evaluate via /architect"
  - "Skip"

**ADR gravity (low, <5 files):** Read the ADR and the unconstrained files.
Assess whether the relationship is meaningful or coincidental. If meaningful:
"These files appear to be implicitly part of this decision's scope."

Use AskUserQuestion:
  - "Add files to ADR scope"
  - "Skip (coincidental)"

**ADR gravity (high, 5+ files) — isolation concern:** This is a boundary
problem, not just missing file tags. Invoke `/architect "<ADR-slug> boundary
review"`. Provide context: "This decision's actual dependency footprint is
significantly wider than documented — <N> unconstrained files co-change with
its scope. The boundary may need redrawing."

**Hub files:** Read the hub file and the ADRs it's connected to. Assess test
coverage: does the file have tests that cover its interaction with each
decision's constrained area? Flag gaps. This is not an `/architect` issue —
it's a test coverage concern. Present: "This file is shared across <N>
decisions. Current test coverage: <assessment>."

**ADR drift:** Present: "This was originally decided on <date> because <reason>.
The codebase has shifted."

Use AskUserQuestion:
  - "Re-evaluate via /architect"
  - "Skip"

If accepted, invoke `/architect "<problem>"` as a review session.

**Stale KB:** Invoke `/research "<subject>" context: "curate: stale KB entry at <topic>/<category>, originally researched <date>. Since then, <what changed>."`.
Provide context about what changed since the original research.

**Implicit dependencies:** Investigate directly within the curation session.
Read the shared files, review the feature briefs that touched them, and assess
whether there's a real gap. Present findings and suggest next steps (which
might be "this is fine" or "worth adding tests for X interaction").

**Orphaned areas:** Offer `/research "<subject>" context: "curate: orphaned area needing coverage"` to build understanding, or `/architect`
if the area seems to need a decision.

**Test-source drift:** Investigate the specific files — read the source changes
and the existing tests. Assess whether the tests are genuinely stale (need
updating) or whether the source changes were internal refactoring that doesn't
affect the test contracts. Present findings: "tests need updating because X
changed" or "tests are still valid — the changes were internal."

**Backfill candidates (implicit decisions):** Present the candidate with context
from the archived feature. Offer the same actions as the old `/decisions backfill`:
- **decide** → invoke `/architect` with the problem statement
- **draft** → write a draft ADR (status: draft, source: backfill)
- **defer** → write a deferred stub
- **dismiss** → append to `.decisions/.backfill-dismissed`, won't resurface

**Out-of-scope items (deferred work in accepted ADRs):** Present items grouped
by parent ADR:

```
── Out-of-scope items from <parent-slug> ──────
This ADR (accepted <date>) scoped out these items:

  [1] <item text> — <reason>
  [2] <item text> — <reason>
  ...

For each: create-stub · skip
Or: create-all · skip-all
```

- **create-stub** → Write a deferred decision stub using the Step 0D template
  from `/architect`:
  - Slugify the concern (first ~5 words, kebab-case)
  - Problem: the concern text
  - Why Deferred: "Scoped out during `<parent-slug>` decision. `<reason>`."
  - Resume When: "When `<parent-slug>` implementation is stable and this
    concern becomes blocking."
  - What Is Known So Far: "See `.decisions/<parent-slug>/adr.md` for the
    architectural context that excluded this concern."
  - Next Step: "Run `/architect "<concern>"` when ready to evaluate."
  - Add a row to the Deferred section of `.decisions/CLAUDE.md`
  - Append an `out-of-scope-promoted` event to the parent ADR's `log.md`
- **create-all** → Apply create-stub to all items from that parent ADR
- **skip** → Items resurface on next `/curate` run (no dismiss needed — once
  a stub exists, the scan deduplicates automatically)

**Unspecified shared types:** Read the spec files that reference this type to
understand the implicit contract. Then invoke `/spec-author extraction-mode`
with the type name — this extracts the type's behavioral contract from the
referencing specs and the source code, producing a standalone spec. Present
summary: "This type is referenced by <N> specs. Here's what each spec assumes
about it: <brief list>."

Use AskUserQuestion:
  - "Extract spec"
  - "Skip"

If accepted, invoke `/spec-author extraction-mode` with the type name.

**Specs with open obligations:** Read the spec file and display the specific
`[UNRESOLVED]` and `[CONFLICT]` markers with their surrounding context (2-3
lines each direction). Present: "This spec has <N> unresolved items. Here they
are: <list>."

Use AskUserQuestion:
  - "Resolve via /spec-resolve"
  - "Skip"

**Obligation registry:** Present the obligations grouped by spec: "Spec <ID>
has <N> open obligations affecting <M> requirements. Blocked by: <blockers>."

Use AskUserQuestion:
  - "Create work group from obligations" (description: "Run /work-decompose
    with --from-obligations to convert these into actionable work definitions")
  - "View obligation details" (description: "Read the full obligation
    descriptions from _obligations.json")
  - "Skip"

When "Create work group": guide the user to create a work group with `/work`
for the affected spec(s), then run `/work-decompose "<group>" --from-obligations`.
When "View details": read and display the full obligation entries from
_obligations.json for the selected spec.

**Spec-code drift:** Present the commit count and affected domains: "This spec
was written on <date> and <N> commits have touched its domain files since."

Use AskUserQuestion:
  - "Verify via /spec-verify"
  - "Skip"

When the user accepts, invoke `/spec-verify` with the spec file path.

**Undecided absent behaviors:** Read the spec file. Find all requirements
tagged with `[ABSENT]`. For each one, display the requirement ID, the full
requirement text, and any consuming specs that assume this behavior. Then
offer the three choices:

- **promote** — Rewrite as a positive requirement describing what the code
  SHOULD do. Remove `[ABSENT]`, add `[UNIMPLEMENTED]`. This creates an open
  obligation (implementation work needed).
- **preserve** — Rewrite as a negative requirement documenting the intentional
  absence ("X MUST NOT Y" instead of "X does not Y [ABSENT]"). Remove
  `[ABSENT]`. This locks in the design choice.
- **defer** — Leave `[ABSENT]` in place. It will resurface on the next
  `/curate` run.

Apply decisions directly to the spec file. After all `[ABSENT]` requirements
in the spec are decided, summarize what changed: how many promoted (new work),
how many preserved (documented decisions), how many deferred.

**Cross-reference repair (KB related links):** Present candidates one at a time,
highest overlap first. For each pair, show both entries' tags and the shared tags:

```
── Cross-reference candidate ───────────────────
  Entry A: .kb/<path-a>
    Tags: [tag1, tag2, tag3]
  Entry B: .kb/<path-b>
    Tags: [tag1, tag2, tag4]
  Shared: [tag1, tag2]

  add    — add related links in both entries
  skip   — not related, won't resurface
  defer  — resurface next /curate run
```

- **add**: Read both entries. Add entry B's relative path to entry A's `related`
  array and vice versa. Both entries get the bidirectional link. Use the standard
  frontmatter array format (`related: ["topic/category/subject.md"]`).
- **skip**: Record as dismissed in curation state (`xref-dismissed`). Won't
  resurface on future scans.
- **defer**: Leave for next `/curate` run.

For applies_to overlap candidates, present the same way but show the shared
file paths instead of tags. Same action options.

**Cross-reference repair (ADR KB Sources):** Present the ADR and its missing
references together:

```
── Missing KB references in ADR ────────────────
  ADR: .decisions/<slug>/adr.md
  Missing from KB Sources table:
    · .kb/<path> — referenced in evaluation.md scoring
    · .kb/<path> — referenced in evaluation.md scoring

  add-all — add all missing references to the ADR's KB Sources table
  select  — choose which to add
  skip    — these references aren't significant
```

- **add-all**: Read adr.md, add rows to the "KB Sources Used in This Decision"
  table for each missing entry. Role column: "Referenced in evaluation."
- **select**: Present each missing reference individually for add/skip.
- **skip**: Record and move on. Won't resurface (the evaluation hasn't changed).

**Spec annotation coverage gap:** Read the spec file and the gap row. Present
the gap type and affected requirements: "Spec `<ID>` has `<N>` requirements
with `<gap-type>`: `<R1, R3, R7>`." If the spec is entirely unannotated, say:
"Spec `<ID>` is APPROVED but has zero `@spec` annotations in source or test
— the traceability is missing."

Use AskUserQuestion:
  - "Verify via /spec-verify" (description: "Run /spec-verify to classify each
    gap as code bug, stale spec, missing test, or needs decision, and repair
    inline")
  - "Accept gap with justification" (description: "The gap is intentional;
    record justification in the curation review log")
  - "Skip" (description: "Defer to next /curate pass")

If "Verify": invoke `/spec-verify` with the spec file path.
If "Accept": prompt the user for the justification text (free-form), record it
in `.curate/curation-state.md` as: `| <date> | annotation-gap:<sid> | accepted |
<justification> |`. The scan will resurface it on future runs, but the review
log shows the accepted rationale.

**Aging open obligation:** Read the spec file and find the obligation in the
`open_obligations` frontmatter array. Present age and full text: "Spec `<ID>`
has an obligation aging `<N>` days: `<obligation-text>`. Last commit touching
this spec: `<date>`."

Use AskUserQuestion:
  - "Resolve via /spec-author" (description: "Author new requirements or close
    the obligation as intentional via /spec-author")
  - "Resolve via /spec-resolve" (description: "Work through [UNRESOLVED] /
    [CONFLICT] markers if the obligation is a conflict")
  - "Close as stale" (description: "Remove from open_obligations with a short
    closure note in the spec's design narrative")
  - "Skip" (description: "Defer to next /curate pass")

If "Close as stale": edit the spec file — remove the obligation entry from the
`open_obligations` frontmatter array, append a one-line note to the spec's
design narrative (e.g., "Closed aging obligation on `<date>`: `<text>` — no
longer relevant because …"), and stage the change. Do not commit unless the
user explicitly requests it.

**Link rot in KB entry:** Read the KB entry and locate the dead URL in
context (one or two surrounding lines so the user sees what the URL was
backing). Present: "KB entry `<path>` cites `<url>` — last check returned
`<status>` on `<date>`."

Use AskUserQuestion. The options depend on whether `--verify` is active:

In normal `/curate` mode:
  - "Refresh via /research" (description: "Re-investigate the topic and
    replace the dead citation with a current source")
  - "Verify via /curate --verify" (description: "Re-check via verify
    mode for confirmation before action")
  - "Mark as accepted" (description: "The URL is gone but the cited fact
    is still valid; record acceptance so it doesn't resurface")
  - "Skip" (description: "Defer to next /curate pass")

In `--verify` mode:
  - "Refresh via /research" (description: same as above)
  - "Mark as accepted" (description: same as above)
  - "Dismiss" (description: "Persistent skip — record in
    .curate/verify-dismissed.txt so future verify runs don't re-prompt")
  - "Skip" (description: "Defer to next verify pass")

If "Refresh": invoke
`/research "<subject>" context: "curate: dead citation at <kb-path>, URL <url> returned <status>"`.
Infer the subject from the KB entry's title or topic context.
If "Mark as accepted": append the URL to a `link-rot-accepted` block in
`.curate/curation-state.md` with a one-line justification. The cache
continues tracking it; future scans surface but the review log shows
prior acceptance.
If "Dismiss" (verify mode only): append
`link-rot|<url>|<YYYY-MM-DD>|<reason>` to `.curate/verify-dismissed.txt`.
Prompt the user for a one-line reason; default to "user dismissed".

**Falsification-lens staleness candidate:** Read the spec file and the
named lens reference (e.g., `prompts/audit/lens-security.md` for the
security lens). Present: "Spec `<id>` was authored `<date>`, before the
`<lens>` lens shipped on `<lens-date>`. The spec mentions `<keyword>`,
which suggests the lens may apply. Running a depth pass under this lens
will look for attack categories the original Pass 2 may have missed."

Use AskUserQuestion. The options depend on whether `--verify` is active:

In normal `/curate` mode:
  - "Run depth pass via /spec-author" (description: "Re-falsify the spec
    under the named lens; findings flow through standard arbitration")
  - "Decline — lens does not apply" (description: "Keyword match is
    incidental; spec scope does not actually need the lens's coverage")
  - "Skip" (description: "Defer to next /curate pass")

In `--verify` mode:
  - "Run depth pass via /spec-author" (description: same as above)
  - "Decline — lens does not apply" (description: same as above)
  - "Dismiss" (description: "Persistent skip — record in
    .curate/verify-dismissed.txt so future verify runs don't re-prompt")
  - "Skip" (description: "Defer to next verify pass")

If "Run depth pass": invoke
`/spec-author <spec-id> --depth-pass-only --lens <lens-name>`.
If "Decline": append a `falsification-decline` row to
`.curate/curation-state.md` keyed by `<spec-id>:<lens>`. The scan
continues to surface; the review log shows the prior decline.
If "Dismiss" (verify mode only): append
`falsification-stale|<spec-id>:<lens>|<YYYY-MM-DD>|<reason>` to
`.curate/verify-dismissed.txt`. Prompt for a one-line reason; default
to "user dismissed".

**KB filename collision:** Read both/all colliding entries and present a
side-by-side: title, type, last_researched, audit-finding count, and the
first sentence of `## summary` or `## What happens`. Help the user judge
which is canonical. Present:

```
── Filename collision: <basename> ─────────────
  [A] <path-A>
      type: <type>, last: <date>, citations: <N>
      "<first-sentence>"

  [B] <path-B>
      type: <type>, last: <date>, citations: <N>
      "<first-sentence>"
```

Use AskUserQuestion:
  - "Rename A" — A becomes a more specific filename; user proposes the new name
  - "Rename B" — B becomes a more specific filename; user proposes the new name
  - "Merge into A" — fold B's audit-findings into A, delete B, update incoming `related:` links
  - "Merge into B" — fold A's audit-findings into B, delete A, update incoming `related:` links
  - "Dismiss as intentional" — record in review log; won't resurface
  - "Skip" — defer

When renaming, do NOT just `git mv` the file — also update every `related:`
entry in the rest of `.kb/` that points at the old path, and check
`@./` includes from any parent file (detail-companion convention) for
broken references. Stage the rename + reference updates with `git add`;
do not commit unless the user explicitly requests it.

**KB schema drift:** Read the entry and present the issues grouped together:

```
── Schema drift: <path> ──────────────────────
  Issues (<N>):
    · missing-type — required field 'type' is unset
    · missing-last-researched — field absent
    · confidence-overclaim — confidence: high but only 1 corroborating finding

  Frontmatter (current):
    title: "<title>"
    research_status: "active"
    confidence: "high"
    ...

  Proposed patches (per .kb/_refs/frontmatter.md):
    + type: adversarial-finding   (inferred from sections '## What happens' + '## Found in')
    + last_researched: "2026-04-12"   (from git-blame)
    ~ confidence: medium   (downgrade from high; only 1 finding)
```

Use AskUserQuestion:
  - "Apply patches" — write all proposed patches at once
  - "Walk one at a time" — present each issue individually with its own apply/skip
  - "Dismiss the entry" — drift is intentional; record in review log
  - "Skip" — defer

When applying, derive values where possible:
- `last_researched` → most-recent git commit touching the file
- `type` → infer from sections (`## What happens` + `## Found in` ⇒ `adversarial-finding`; entry under `architecture/feature-footprints/` ⇒ `feature-footprint`; otherwise `research`)
- `research_status: archived` → rewrite to `deprecated`
- `topic:` / `category:` mismatches → rewrite to match the path
- `confidence: high` overclaim → downgrade to `medium`

Always stage the patches; do not commit unless explicitly requested.

**KB type/location mismatch:** Read the entry. Determine the expected location:
- `type: adversarial-finding` → `patterns/<concern>/<basename>`. Infer
  `<concern>` from the entry's `domain:` field (`validation`, `concurrency`,
  `resource-management`, `data-integrity`, etc.). If the domain doesn't map
  cleanly, ask the user with AskUserQuestion listing the existing
  `patterns/` subfolders.
- `type: feature-footprint` → `architecture/feature-footprints/<basename>`.

Present:

```
── Type/location mismatch: <path> ────────────
  Type: <type>
  Current location: <topic>/<category>/
  Canonical location: <expected-prefix>
  Reason: <reason>
```

Use AskUserQuestion:
  - "Relocate" — move to the canonical location, update incoming `related:` links and any `@./` includes
  - "Re-classify type" — entry is research that mentions a finding; change `type:` to `research`, leave at current path. Then ask if the user wants to also create a new finding entry under `patterns/<concern>/`
  - "Dismiss as intentional" — rare; record in review log
  - "Skip" — defer

When relocating, the same care as for filename collisions applies — update
every incoming `related:` link, check `@./` includes, stage with `git add`,
let the user commit.

After completing the action, mark it `resolved` in the review log. Then
**ALWAYS re-present the remaining items** (renumbered) so the user can
continue. Only proceed to Step 5 when the user says "done" or all items
are resolved.

### User says "all"

Work through items in order, starting with #1. After each item completes,
proceed to the next. After ALL items are resolved, show the closing report.

### User says "done"

Note all remaining unaddressed items as `suggested` in the review log.
Display:
```
Noted <N> remaining items. They'll resurface next time you run /curate,
deprioritized below any new findings.

Run /curate anytime — incremental scans are fast.
```
Proceed to Step 5.

### Automatic persistence

Every finding gets a row in the append-only review log via:

```bash
bash .claude/scripts/curate-review-log.sh append \
  .curate/review-log.md \
  <YYYY-MM-DD> \
  <key> \
  "<description>" \
  <status> \
  ["<notes>"]
```

Where `<status>` is one of:
- `resolved` — user acted on it (ran /architect, /research, etc.)
- `deferred` — user explicitly chose Skip / Defer; resurface next run
- `suggested` — user said "done" without addressing this item
- `dismissed` — verify-mode only; persistent skip
- `explored` — user investigated, no action needed

`<key>` is a structured identifier so the same finding maps consistently
across runs. Use these conventions:

| Finding type | Key format |
|--------------|-----------|
| ADR pressure | `adr-pressure:<slug>` |
| ADR gravity | `adr-gravity:<slug>` (or `adr-gravity:<slug>:<file>` for per-file) |
| ADR drift / revisit | `adr-drift:<slug>` |
| Hub file | `hub-file:<file>` |
| Stale KB | `kb-stale:<topic>/<category>/<subject>` |
| Spec-code drift | `spec-drift:<spec-id>` |
| Test-source drift | `test-drift:<file>` |
| Backfill candidate | `backfill:<source>:<problem-slug>` |
| Out-of-scope item | `out-of-scope:<parent-slug>:<idx>` |
| Spec annotation gap | `annotation-gap:<spec-id>` |
| Aging obligation | `obligation-aging:<obligation-id>` |
| Link rot | `link-rot:<url>` |
| Falsification stale | `falsification-stale:<spec-id>:<lens>` |
| Cross-ref repair | `crossref:<artifact-id>` |
| Subdivision candidate | `subdivision:<spec-id>` |
| Bookkeeping repair | `scan-bookkeeping:<repair-name>` |
| KB filename collision | `kb-collision:<basename>` |
| KB schema drift | `kb-schema:<path>:<issue-code>` |
| KB type/location mismatch | `kb-location:<path>` |
| KB citation drift | `kb-citation:<source-file>:<cited-entry>` |
| Spec graduation candidate | `spec-graduation:<spec-id>` |
| Spec xref drift | `spec-xref:<spec-id>:<ref-type>:<broken-ref>` |
| ADR without spec coverage | `adr-no-spec:<adr-slug>` |

The append helper is duplicate-safe — re-appending an identical row is a
no-op, so resuming a previous /curate session does not duplicate entries.

Nothing gets lost. The next `/curate` run resurfaces `suggested` and `deferred`
items via Step 2.5 deprioritized below new findings.

---

## Step 5 — Update curation state

After the user is done (explored items, deferred, or noted for later):

Update `.curate/curation-state.md` with **only the Scan State section**.
The Review Log lives in `.curate/review-log.md` (append-only) and is
managed exclusively via `curate-review-log.sh`. Writing the Review Log
inline in curation-state.md would silently destroy prior rows on every
run — that is the bug this design replaces.

```markdown
# Curation State

## Scan State
Last scanned: <current HEAD SHA>
Last scanned date: <YYYY-MM-DD>
Window: <months used>
Commits scanned: <N>
```

(The original Step 5 template emitted both Scan State and Review Log into
this file, which is what destroyed the persistence guarantee. Do not
re-introduce the Review Log section here.)

After updating curation-state.md, do not write to review-log.md directly
— Step 4 already appended every finding via `curate-review-log.sh append`.

---

## Step 6 — Closing report

Read the current review-log totals so the closing line reflects the
append-only log, not just this session's actions:

```bash
LOG_REPORT=$(bash .claude/scripts/curate-review-log.sh report \
  .curate/review-log.md 2>/dev/null || echo "")
```

```
───────────────────────────────────────────────
🔍 CURATION complete
───────────────────────────────────────────────
Scanned: <N> commits (<scan mode>)
Found: <N> items across <N> categories
This session: <N> resolved · <N> deferred · <N> noted
$LOG_REPORT
Next scan will pick up from <current SHA short>.
Run /curate anytime — scans run on the full <N>-month window.
───────────────────────────────────────────────
```

---

## Quality checklist (self-verify before ending session)

- [ ] Scan script ran successfully and produced scan-summary.md
- [ ] Findings presented conversationally, not as a raw dump
- [ ] Each finding includes why it matters and an offer to help
- [ ] Every finding got an append row via `curate-review-log.sh append`
- [ ] curation-state.md updated with Scan State only (no Review Log section)
- [ ] No commands assigned — only offers made
- [ ] Cold start findings are prioritized bootstrapping suggestions, not a wall of "everything is orphaned"
