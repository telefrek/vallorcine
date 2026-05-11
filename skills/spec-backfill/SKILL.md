---
description: "Backfill @spec annotations on existing code for an APPROVED spec (or --all specs)"
argument-hint: "<spec-id> | --all"
---

# /spec-backfill

Walk every requirement of an APPROVED spec that has zero `@spec` annotations
in code, present likely enforcement sites for each, and apply annotations
the user chooses. The catch-up tool for mature corpora authored before
`@spec` annotation enforcement (`v0.16.5` / PR #67) was added.

**Two modes:**
- `/spec-backfill <spec-id>` — walk one spec.
- `/spec-backfill --all` — iterate every APPROVED spec in the manifest,
  running the per-spec walk against each. The catch-up tool for whole
  corpora (e.g. jlsm: 75 specs / 12 domains, mostly authored before
  enforcement existed).

**When to use:** APPROVED spec(s) whose requirements pre-date annotation
enforcement and which have uncovered R-ids. `/curate` annotation-drift
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

3. Determine mode from `$ARGUMENTS`:
   - `--all` (or `-a`) → corpus mode (jump to "Corpus mode" section below
     after pre-flight).
   - empty → ask the user which spec to backfill via AskUserQuestion.
     Build the option list from APPROVED specs in the manifest (limit to
     4 + Other; if more candidates exist, hint that `/spec-backfill --all`
     covers the corpus).
   - non-empty, not `--all` → treat as a literal spec-id and use it.

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

## Corpus mode (`--all`)

When invoked with `--all`, iterate every APPROVED spec in the manifest
and run the per-spec walk against each via the **subagent dispatch
pattern** — each spec is processed by a dedicated sub-agent that owns
all file reads, the candidate-finding subprocess, and edit application.
The coordinator (this skill, in the user's conversation) only holds
per-spec one-line summaries, keeping its context bounded as the corpus
grows. Pre-flight runs once; the backfill log is the same
`.spec/backfill-log.md` so progress and prior decisions persist across
the whole corpus.

### Why dispatch instead of inline iteration

Inline iteration accumulates context linearly: spec 1's candidates +
requirement text + edit application stay in the coordinator's window
while spec 2 begins, and so on. By spec 12 a coordinator running
inline holds 12 × (5–30 KB) of read state. Dispatching each spec as a
sub-agent gives that spec a fresh context window; the coordinator
absorbs only the return summary (~80 bytes per spec). 12 specs ≈ 1 KB
of accumulated summaries — bounded forever.

The dispatch boundary lines up with per-spec independence: backfill
decisions for spec A do not affect spec B's candidate scoring or
requirement text. Cross-spec resumption is already handled by the
append-only `backfill-log.md` — already-decided (spec, R-id) pairs
auto-skip on subsequent runs regardless of which run made the decision.

### C0. Pre-flight: surface stuck dispatches from prior runs

Before enumerating, check for unacknowledged dispatch markers under
`.spec/_backfill-dispatches/`:

```bash
bash .claude/scripts/dispatch-marker.sh stuck .spec/_backfill-dispatches
```

If output is non-empty, surface each stuck spec to the user via
AskUserQuestion BEFORE starting the corpus walk:

- **"Re-dispatch <spec-id>"** — clear the marker and include the spec
  in the run.
- **"Skip <spec-id> for now"** — leave the marker; spec will be
  surfaced again next run.
- **"Investigate manually"** — print the marker contents
  (`dispatch-marker.sh status …`) and stop the run.

This mirrors `/work-resume rule 0` (PR #79) — any unacknowledged marker
pre-empts the normal flow because it represents a previous run whose
result the coordinator never saw.

### C1. Discover the candidate set

Enumerate APPROVED specs by reading the manifest:

```bash
jq -r '
  if .specs then
    .specs[] | select(.state == "APPROVED") | .id
  else
    (.features // {}) | to_entries[] | select(.value.state == "APPROVED") | .key
  end
' .spec/registry/manifest.json
```

Both v1 (`features` object keyed by ID) and v2 (`specs` array of objects)
manifest schemas are handled by the `if .specs then` switch — the same
dual-schema pattern `spec-lib.sh` uses.

For each ID, run `bash .claude/scripts/spec-trace.sh --uncovered <id>`
and capture only the count of uncovered R-ids. Skip specs that return
zero uncovered (already fully annotated). The pre-flight scan is the
ONLY place the coordinator reads spec-trace output for the corpus —
per-spec depth lives inside each dispatched sub-agent.

Tell the user the corpus picture in one paragraph:

```
Corpus has <N> APPROVED specs. <K> already fully annotated — skipping.
<M> have at least one uncovered requirement, totalling <U> uncovered
R-ids across the corpus. Dispatching one sub-agent per spec to keep
this conversation's context bounded. Break out at any time and rerun
/spec-backfill --all to resume.
```

Use AskUserQuestion to confirm before starting if `<U>` exceeds 50:
- **"Run all"** (Recommended)
- **"Cap at 10 specs"** (or another cap)
- **"Cancel"**

### C2. Per-spec dispatch loop

For each spec with uncovered R-ids, in manifest order, run this loop
until the dispatched count reaches the cap (if set) or the eligible
set is empty:

**C2a. Write the dispatch marker.**

```bash
bash .claude/scripts/dispatch-marker.sh begin .spec/_backfill-dispatches <spec-id>
```

This creates `.spec/_backfill-dispatches/_dispatch-<spec-id>.json` with
`ack: false`. The marker is gitignored. Flipped to `ack: true` once the
sub-agent returns and the coordinator parses its result.

**C2b. Dispatch the sub-agent.** Invoke the Agent tool with this prompt
verbatim (substitute `<spec-id>`):

```
You are the per-spec backfill runner for <spec-id>.

Invoke /spec-backfill <spec-id>. The single-spec flow handles Phase 1
(discover uncovered R-ids), Phase 2 (per-R-id candidate walk with user
decisions), and Phase 3 (re-trace + summarize). AskUserQuestion in
Phase 2 surfaces to the actual user — you do not auto-answer it. The
user IS available across the dispatch boundary; do not assume
autonomy.

When the per-spec flow completes, return EXACTLY ONE LINE on stdout
matching this shape:

  COMPLETE <spec-id> annotated=<N> skipped=<K> waived=<W> uncovered_after=<U>

If the user breaks out mid-walk (any non-resume exit), return:

  STOPPED <spec-id> annotated=<N> skipped=<K> waived=<W> remaining=<R>

If the spec turns out to have zero uncovered R-ids after the log query
(prior runs covered everything), return:

  EMPTY <spec-id>

Any other return is treated as a parse failure.
```

**C2c. Wait for the return.** The Agent tool blocks until the sub-agent
emits its final assistant message.

**C2d. Classify and ack.** Parse the return into one of four shapes:

- **COMPLETE** / **STOPPED** / **EMPTY** — ack the marker with the
  exact return line:
  ```bash
  bash .claude/scripts/dispatch-marker.sh ack .spec/_backfill-dispatches <spec-id> "<return-line>"
  ```
  Print a one-line summary to the user: `<spec-id> — <return-line>`.
  Continue to next spec.

- **Payload lost** — Agent return literally equals
  `[Tool result missing due to internal error]`. Mark the marker as
  failed:
  ```bash
  bash .claude/scripts/dispatch-marker.sh fail .spec/_backfill-dispatches <spec-id> "payload-lost"
  ```
  Surface via AskUserQuestion: "Pause for investigation" /
  "Re-dispatch <spec-id>" / "Skip and continue".

- **User stopped** — Agent return contains
  `The user doesn't want to proceed with this tool use`. Mark as
  failed with reason `user-stopped`. Surface AskUserQuestion:
  "Re-dispatch <spec-id>" / "Continue with next spec" / "Stop the run".

- **Parse failed** — return present but does not match any expected
  shape. Mark as failed with reason `parse-failed: <first-80-chars>`.
  Print the raw return to the user and offer the same recovery options
  as user-stopped.

**C2e. Honor the cap.** If a cap was set in C1 and the dispatched
count has reached it, exit the loop after acking the current spec.

### C3. Corpus summary

After the loop exits, emit a final aggregate report:

- Total specs dispatched / completed / stopped / empty / failed
- Total annotations applied this session (sum from return lines)
- Total R-ids skipped (will resurface) / waived
- Any remaining stuck markers (re-run pre-flight count)
- Pointer to `.spec/backfill-log.md` for the canonical record

If any spec returned STOPPED or any marker is still failed, tell the
user how to resume:

```
<X> spec(s) left work undone this run. Rerun /spec-backfill --all
to resume — already-decided R-ids will be skipped automatically, and
the pre-flight will offer to re-dispatch any stuck markers.
```

### C4. Cost awareness

Even with dispatch, whole-corpus runs are still long because each
sub-agent does real work — the win is coordinator context economy,
not wall-clock. The C1 confirmation step surfaces the cost note when
the uncovered count exceeds 50, but a corpus with 50+ specs may still
benefit from a `Cap at 10` first pass to validate the dispatch is
behaving as expected.

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
