---
description: "Backfill @spec annotations on existing code for an APPROVED spec"
argument-hint: "<spec-id>"
---

# /spec-backfill

Walk every requirement of an APPROVED spec that has zero `@spec` annotations
in code, present likely enforcement sites for each, and apply annotations
the user chooses. The catch-up tool for mature corpora authored before
`@spec` annotation enforcement (`v0.16.5` / PR #67) was added.

**When to use:** APPROVED spec whose requirements pre-date annotation
enforcement and which has many uncovered R-ids. `/curate` annotation-drift
analysis routes here when a spec falls below 50% coverage.

**Not for:** active features mid-pipeline. The `/feature-test` and
`/feature-implement` substages already gate on annotation coverage; the
forward-enforcement gate is the right tool there. `/spec-backfill` is for
existing pre-enforcement code that no live feature touches.

---

## Pre-flight

1. Verify `jq` is installed:
   ```bash
   command -v jq >/dev/null 2>&1
   ```
   If missing, tell the user and stop.

2. Verify `.spec/registry/manifest.json` exists. If not, tell the user to
   run `/spec-init` and stop.

3. Resolve the spec ID from `$ARGUMENTS`. If empty, ask the user which spec
   to backfill via AskUserQuestion. Build the option list from
   `spec_manifest_ids` (limit to 4 + Other; if more candidates exist, hint
   that `/spec-backfill --all` covers the corpus).

4. Read `rules/spec-annotation-protocol.md` (already in your context as a
   project rule) — you must follow its comment-syntax-per-language and
   placement guidance when applying annotations below.

---

## Phase 1 — Discover uncovered requirements

Run the trace primitive in `--uncovered` mode:

```bash
bash .claude/scripts/spec-trace.sh --uncovered <spec-id>
```

Output is a parseable list, one R-id per line on stdout (e.g.
`auth.token-validation.R3`); a count summary is on stderr.

If output is empty: tell the user "spec is fully annotated — nothing to
backfill" and stop.

If non-empty: capture the list and the count. Read `.spec/backfill-log.md`
(initialize with `bash .claude/scripts/spec-backfill-log.sh init
.spec/backfill-log.md` if it does not exist) and filter the list down to
R-ids that do NOT yet have a terminal decision (`annotated` or `waived`).
`skipped` rows from prior runs are NOT terminal — those resurface by
design.

Tell the user the plan in one or two sentences:

```
spec <id> has <N> uncovered requirement(s). <K> were skipped on prior
runs and will resurface; <M> are already annotated or waived in the log
and will be skipped. Walking <N - already-decided> now.
```

---

## Phase 2 — Walk uncovered requirements

For each R-id remaining (in spec order):

### 2a. Surface the requirement text

Read the spec file (path resolved via `spec_file_for_id`). Locate the
matching `^R<n>[a-z]*(-…)?\.` line under `## Requirements` and extract the
requirement text (may span multiple lines until the next R-id).

### 2b. Find candidate sites

Run the candidate finder:

```bash
bash .claude/scripts/spec-backfill-candidates.sh <spec-id> <r-id>
```

Output is one row per candidate, ranked by token-overlap score:

```
<score>\t<rel-path>:<line>\t<truncated-context>
```

Stderr surfaces the requirement text and the extracted subject tokens for
display. Read both. The candidate finder may return zero rows for very
short or token-poor requirements — that is expected.

### 2c. Present and decide

Present the requirement text and top candidates to the user.

Build the AskUserQuestion options dynamically from the candidate rows.
Show up to 4 candidates as labeled options; always include "Other (specify
file:line)" and "Skip this R-id". Add "Waive (intentionally uncovered)"
when the user signals at top of session that they want this option, or
when a candidate set is empty.

```
R3 — The system must enforce token expiry by rejecting tokens whose
exp claim is in the past at validation time.

Subject tokens: TokenValidator, expiry, validate

Likely sites:
  (a) src/auth/TokenValidator.java:78  (overlap: 3)
        if (claims.getExpiry().isBefore(now)) {
  (b) src/auth/TokenValidator.java:45  (overlap: 2)
        public boolean validateExpiry(Claims claims) {
  (c) test/auth/TokenValidatorTest.java:120  (overlap: 2)
        @Test void expiredTokensRejected() {
```

Use AskUserQuestion with the constructed options. Do NOT prompt with prose
("Type a / b / c") — that does not stop generation; AskUserQuestion does.

### 2d. Apply the user's decision

Based on the choice:

- **Candidate selected** — read the file, locate the chosen line, and
  insert a `@spec <spec-id>.<R-id>` annotation in a comment ABOVE the line
  (not on the same line) using the comment syntax for that language. Per
  `rules/spec-annotation-protocol.md`: `// @spec <ref>` for C-family,
  `# @spec <ref>` for Python/Ruby/Bash, `-- @spec <ref>` for Lua/SQL,
  `<!-- @spec <ref> -->` for HTML/XML. If a sibling annotation already
  exists at that location, append the new ref to the existing comment
  rather than adding a separate line. Use Edit to apply.

  Then append to the log:
  ```bash
  bash .claude/scripts/spec-backfill-log.sh append \
    .spec/backfill-log.md "$(date +%F)" <spec-id> <r-id> annotated \
    "<rel-path>:<line>"
  ```

- **Other** — ask the user via AskUserQuestion follow-up for the file:line.
  Validate the path exists. Apply annotation as above. Log as `annotated`
  with the user-supplied location.

- **Skip** — append `skipped` to the log with no location. Move on. The
  R-id will resurface on the next run.

- **Waive** — ask follow-up via AskUserQuestion for a one-line reason.
  Append `waived` with the reason in the notes column. Waived R-ids do
  NOT resurface; the user has declared the requirement intentionally
  uncovered (e.g., aspirational, deprecated, enforced externally).

### 2e. Re-trace after each annotation (cheap correctness check)

After applying an `annotated` decision, the next loop iteration starts
with a stale picture of what is already covered. That is acceptable for
performance — the candidate finder still scores correctly because tokens
do not change. The end-of-session re-trace below catches any drift.

---

## Phase 3 — Confirm coverage moved

After all R-ids are processed (decided or skipped), re-run:

```bash
bash .claude/scripts/spec-trace.sh --uncovered <spec-id>
```

Compute and report:
- How many R-ids were uncovered at start.
- How many are uncovered now.
- Of the difference: how many were `annotated`, how many `skipped` (will
  resurface), how many `waived`.

Surface the report inline. Do NOT write a separate report file — the
`.spec/backfill-log.md` is the authoritative record.

If `skipped` count > 0, tell the user how to resume:

```
<K> requirement(s) were skipped and will resurface on rerun. Run
/spec-backfill <spec-id> again when you're ready to revisit them.
```

---

## Failure modes and recovery

- **Manifest does not resolve the spec ID.** Tell the user the spec ID is
  unknown; suggest `/spec` to list available specs. Stop.
- **Candidate finder returns zero rows for every R-id.** Likely indicates
  the requirement text is too prose-y for token extraction. Fall through
  to "Other" / "Skip" — do not silently advance.
- **Edit collides with an existing annotation that already covers this
  R-id.** That should not happen if Phase 1 filtered correctly, but if
  it does: log as `annotated` (idempotent on the log) and continue.
- **User aborts mid-walk.** The log preserves every decision applied so
  far; rerunning resumes from where the user left off. Do not revert
  applied annotations.
