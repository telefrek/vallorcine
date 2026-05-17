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

Output is a parseable list, one **fully-qualified R-id** per line on
stdout (e.g. `auth.token-validation.R3`); a count summary is on stderr.

**Important — strip the `<spec-id>.` prefix before passing to downstream
scripts.** `spec-backfill-candidates.sh` and `spec-backfill-log.sh`
both expect **bare R-ids** (e.g. `R3`), not fully-qualified ones. Pass
the FQ form and the candidate finder errors with "Requirement '...' not
found"; the log helpers' `has-decision` key never matches an annotated
row. The 2026-05-11 adversarial finding (CRIT 4) confirmed this caused
Phase 1's terminal-decision filter to silently no-op, re-walking
already-annotated requirements.

For each FQ R-id captured (e.g. `auth.token-validation.R3`), compute
the bare form via shell expansion: `r_id="${fq_rid##*.}"` (yields
`R3`). Use `r_id` for ALL subsequent `spec-backfill-candidates.sh` /
`spec-backfill-log.sh` invocations.

If output is empty: tell the user "spec is fully annotated — nothing to
backfill" and stop.

If non-empty: capture the list and the count. Read `.spec/backfill-log.md`
(initialize with `bash .claude/scripts/spec-backfill-log.sh init
.spec/backfill-log.md` if it does not exist) and filter the list down to
R-ids (bare form) that do NOT yet have a terminal decision (`annotated`
or `waived`). `skipped` rows from prior runs are NOT terminal — those
resurface by design.

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

**Subagent contract — MANDATORY for every dispatch.** Every per-spec
sub-agent this skill dispatches MUST be given this preamble at the top
of its prompt:

> **Subagent contract:** Honor `rules/completeness-contract.md`
> (load-bearing — no silent deferrals; trigger phrases = escalation
> signals, not completion modes). If you cannot complete assigned
> scope, escalate via AskUserQuestion with user-validatable proof. A
> return claiming COMPLETE alongside deferred items is a contract
> violation.

When per-spec sub-agents return, the coordinator MUST run the validation
script BEFORE accepting:

```bash
mkdir -p /tmp/vallorcine
return_file=/tmp/vallorcine/spec-backfill-return-"<spec-id>".txt
printf '%s\n' "$FULL_RETURN_TEXT" > "$return_file"
bash .claude/scripts/validate-subagent-return.sh "$return_file" 2>/tmp/vallorcine/validator-stderr.txt
rc=$?
```

- `rc=0` → accept and continue to the next spec.
- `rc=1` → trigger phrase detected. Surface to user via AskUserQuestion
  with validator stderr. Do not advance to the next spec until resolved.
- `rc=2` → tooling error. Log and treat as `rc=0`.

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

Each line is `<dispatch-id>|<dispatched_at>|...`. Dispatch IDs for
this skill are **suffixed**: `<spec-id>--propose` (Phase A markers)
or `<spec-id>--apply` (Phase B markers). The stuck output may show
both, the same spec, or just one. **Group stuck markers by spec-id
before surfacing** (2026-05-11 adversarial HIGH #2) — otherwise the
user sees "Re-dispatch <spec>--propose" + "Re-dispatch <spec>--apply"
as two separate prompts for the same spec, with no clear meaning
because the user doesn't necessarily know what "--propose" vs
"--apply" implies.

For each unique `<spec-id>` (stripping the `--propose`/`--apply`
suffix via `${id%--*}`), pick the appropriate routing based on
which markers exist:

| Markers present | Meaning | Recommended action |
|-----------------|---------|---------------------|
| `--propose` only | Phase A ran but Phase B never dispatched. Decisions in memory were lost. | Re-dispatch Phase A (the user's prior decisions are gone; walk the spec again). |
| `--apply` only | Phase B dispatched but never ack'd. Some annotations may already exist; the log records them. | **Investigate** first — list completed rows via `spec-backfill-log.sh list-decisions <log> <spec>`. Re-dispatching Phase A is safe (the log's terminal-decision filter skips them), but a partial Phase B's `skipped` rows from the lost run will surface again. |
| Both | Phase A and Phase B both fired; result lost mid-Phase-B. | Same as `--apply` only — investigate the log first. |

Use `AskUserQuestion` per unique spec-id, with options drawn from
the table above:

- **"Re-dispatch Phase A (walk spec again)"** — clears any
  `<spec>--propose` marker, runs Phase A fresh.
- **"Investigate via `spec-backfill-log.sh list-decisions`"** — print
  the per-R-id state and stop the run for this spec.
- **"Skip <spec> for now"** — leave markers; spec resurfaces next run.

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

### C2. Per-spec two-phase dispatch loop

For each spec with uncovered R-ids, in manifest order, run this loop
until the dispatched count reaches the cap (if set) or the eligible
set is empty.

**The two-phase pattern is mandatory.** The single-spec flow's Phase 2
uses AskUserQuestion per R-id. Dispatched sub-agents (Agent tool) run
to a single final-message return; the codebase convention is that
sub-agents do NOT call AskUserQuestion mid-flow (the only documented
sub-agent contract — see `/work-start all`, `/feature-coordinate` — is
"run autonomously and return one message"). Two-phase dispatch
respects that contract by splitting the work: sub-agent A runs the
read-heavy discover + propose stage with no user prompting, the
coordinator surfaces the per-R-id decisions via AskUserQuestion, then
sub-agent B applies the decisions mechanically.

**C2a. Phase A — discover + propose (sub-agent, autonomous).**

Write the marker, then dispatch:

```bash
bash .claude/scripts/dispatch-marker.sh begin .spec/_backfill-dispatches <spec-id>--propose
```

Agent prompt verbatim (substitute `<spec-id>`):

```
You are the discover + propose stage for /spec-backfill <spec-id>.

Run, in order:
  1. bash .claude/scripts/spec-trace.sh --uncovered <spec-id>
     This emits FULLY-QUALIFIED R-ids (e.g., `auth.foo.R3`).
  2. For each uncovered R-id (cap at 12 — surface "more remain" in
     output if there are more):
     - Strip the spec-id prefix to get the bare R-id:
       r_id="${fq_rid##*.}" (e.g., `auth.foo.R3` → `R3`).
       spec-backfill-candidates.sh and spec-backfill-log.sh both
       require BARE R-ids; passing the FQ form errors. (CRIT 4,
       2026-05-11 adversarial.)
     - Extract the requirement text from the spec file under
       ## Requirements (match `^<r_id>[a-z]*(-…)?\.`).
     - Run `bash .claude/scripts/spec-backfill-candidates.sh <spec-id>
       <r_id>` (bare) and capture the top 5 candidates.
  3. Read .spec/backfill-log.md if it exists; for each bare R-id, run
     `bash .claude/scripts/spec-backfill-log.sh has-decision
     .spec/backfill-log.md <spec-id> <r_id>`; mark R-ids whose
     has-decision returns `annotated|waived` as "already_decided" so
     the coordinator can skip them.

Return EXACTLY ONE LINE — a JSON object — matching this shape:

{"spec_id":"<spec-id>","total_uncovered":<int>,"more_remain":<bool>,
 "items":[
   {"r_id":"R3","requirement_text":"<≤200 chars>",
    "candidates":[{"file":"<path>","line":<int>,"context":"<≤80 chars>","score":<float>}],
    "already_decided":null},
   ...
 ]}

If `total_uncovered` is 0, return:
  {"spec_id":"<spec-id>","total_uncovered":0,"items":[]}

DO NOT call AskUserQuestion. DO NOT edit any files. DO NOT log anything.
Read-only stage. Coordinator handles all user interaction + log writes.

Any other return shape is treated as a parse failure.
```

**C2b. Parse the proposal + ack marker.**

Receive the JSON. Validate via `jq -e '.spec_id and .items'`. On
parse failure, mark the propose-stage marker as failed and continue
to next spec (the surfacing logic is in C2e — mark the propose marker
as failed via `bash .claude/scripts/dispatch-marker.sh fail
.spec/_backfill-dispatches <spec-id>--propose "parse-failed: <first
80 chars>"`, surface to user, continue).

```bash
bash .claude/scripts/dispatch-marker.sh ack .spec/_backfill-dispatches <spec-id>--propose "<one-line-summary>"
```

**C2c. Coordinator AskUserQuestion loop (per R-id).**

For each `item` in `items` where `already_decided` is null:

Build AskUserQuestion options dynamically from the top candidates plus
the standard tail (Skip, Waive, Other). Present:

```
R3 — <requirement_text>

Suggested annotation sites:
  (a) <file>:<line>  (score: <s>)  <context>
  (b) ...

Pick one, or Skip / Waive / specify Other.
```

Collect the user's decision into a decision-set:

```json
{"spec_id":"<spec-id>","decisions":[
  {"r_id":"R3","action":"annotate","file":"...","line":123},
  {"r_id":"R5","action":"skip"},
  {"r_id":"R7","action":"waive","reason":"<≤100 chars>"}
]}
```

If the user picks "Other", validate the file path exists in coordinator
before adding to the decision-set (same validation as today's inline
flow).

The decision-set lives in coordinator context briefly (~500 bytes per
spec at most) — released as soon as Phase B returns.

**Skip Phase B dispatch when the decision-set is no-op** (2026-05-11
adversarial HIGH #4). Before invoking C2d:

- If `decisions` is empty AND every item was `already_decided` (this is
  a no-op re-run of an already-completed spec), skip C2d entirely.
  Print `<spec-id> — all uncovered R-ids already terminal (no-op)` and
  ack the propose marker with that summary. Continue to next spec.
- If `decisions` is non-empty but contains ONLY `skip` actions (user
  declined every R-id this round), there are still log rows to write
  for audit trail — dispatch C2d normally so the `skipped` rows are
  recorded (they're non-terminal and will resurface on the next run
  with a forward-progress signal).
- Otherwise dispatch C2d normally.

This guard avoids paying full sub-agent overhead to log zero rows
when re-running `/spec-backfill --all` after a clean completion (every
Phase A returns items with `already_decided` set; previously the
coordinator dispatched Phase B per spec just to confirm "no work to
do").

**C2d. Phase B — apply (sub-agent, autonomous, idempotent).**

```bash
bash .claude/scripts/dispatch-marker.sh begin .spec/_backfill-dispatches <spec-id>--apply
```

Agent prompt verbatim (substitute the JSON):

```
You are the apply stage for /spec-backfill <spec-id>.

Decisions (JSON):
<paste the decision-set JSON here>

For each decision, in order:

- action="annotate" → read the file at <file>, locate <line>, insert
  a `@spec <spec-id>.<R-id>` annotation in a comment ABOVE the line
  (per rules/spec-annotation-protocol.md comment syntax). If a sibling
  @spec annotation already exists at that location, append to the
  existing comment rather than adding a new line. Use the Edit tool.
  Append to the log:
    bash .claude/scripts/spec-backfill-log.sh append \
      .spec/backfill-log.md "$(date +%F)" <spec-id> <R-id> annotated \
      "<file>:<line>"

- action="skip" → append `skipped` row to the log (no location).

- action="waive" → append `waived` row with the reason in notes.

Before each apply, query `bash .claude/scripts/spec-backfill-log.sh
has-decision .spec/backfill-log.md <spec-id> <R-id>`. If a terminal
decision (annotated | waived) already exists, skip this decision
silently — the apply stage MUST be idempotent so a re-dispatch after a
crash does not double-annotate.

After all decisions, run:
  bash .claude/scripts/spec-trace.sh --uncovered <spec-id>
and count the remaining uncovered R-ids.

Return EXACTLY ONE LINE:

  COMPLETE <spec-id> annotated=<N> skipped=<K> waived=<W> uncovered_after=<U>

DO NOT call AskUserQuestion. The decision set is final; do not
re-prompt. Any other return is treated as a parse failure.
```

**C2e. Parse Phase B return + ack the apply-stage marker.**

Classify into one of:

- **COMPLETE …** — ack the marker:
  ```bash
  bash .claude/scripts/dispatch-marker.sh ack .spec/_backfill-dispatches <spec-id>--apply "<return-line>"
  ```
  Print `<spec-id> — <return-line>` to the user. Continue to next spec.

- **Payload lost** — Agent return literally equals
  `[Tool result missing due to internal error]`. Mark the apply
  marker `payload-lost`. The propose marker is still acked, and the
  log captured partial progress if Phase B did any work. Surface via
  AskUserQuestion: "Re-dispatch <spec-id> apply" /
  "Skip and continue" / "Investigate manually".

- **User stopped** — Agent return contains
  `The user doesn't want to proceed with this tool use`. Mark
  `user-stopped`. Same recovery options.

- **Parse failed** — return present but does not match. Mark
  `parse-failed: <first-80-chars>`. Print raw return; same recovery
  options.

**C2f. Forward-progress re-loop for >12 uncovered specs** (2026-05-11
adversarial HIGH #3). Phase A's prompt caps at 12 uncovered R-ids per
dispatch and sets `more_remain=true` in the JSON when there are more.
Without a re-loop, a spec with 30 uncovered R-ids only ever surfaces
R-ids 1-12 across any number of `/spec-backfill --all` runs — R-ids
13-30 are invisible because `skipped` rows from the first batch keep
the same 12 surfacing first.

After C2e ack, check the Phase A return's `more_remain` flag:

- If `more_remain == false` → continue to next spec (current behavior).
- If `more_remain == true`:
  - Count this round's **forward progress** = number of decisions
    whose action was `annotate` or `waive` (terminal in the log).
  - If forward progress is **zero** (user skipped every R-id this
    round), stop iterating this spec — the next batch would just
    re-surface the same 12. Continue to next spec. The skipped R-ids
    will resurface on the next `/spec-backfill --all` run.
  - If forward progress is **>= 1**, re-dispatch Phase A for the same
    spec (new propose marker, fresh AskUserQuestion loop). The
    already-annotated/waived R-ids will be filtered by Phase A's
    `already_decided` check; the user sees the next batch of 12
    uncovered R-ids. Cap the inner loop at 3 iterations per spec to
    prevent pathological cases.

This makes the corpus walk eventually-complete for specs with >12
uncovered R-ids, as long as the user makes forward progress at least
once per round.

**C2g. Honor the cap.** If a cap was set in C1 and the dispatched
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
- **User aborts mid-walk (single-spec mode).** The log preserves every
  decision applied so far; rerunning resumes from where the user left
  off. Do not revert applied annotations.
- **User aborts mid-AskUserQuestion loop (corpus mode C2c)** — 2026-05-11
  adversarial MED #2. In corpus mode, decisions are collected in
  coordinator memory across multiple `AskUserQuestion` prompts (one per
  R-id) BEFORE Phase B dispatches and writes log rows. A user abort
  (ESC) after, say, 5 of 12 R-ids leaves 5 answered decisions in
  memory with 7 unanswered. Without explicit handling, the run exits
  and ALL 5 decisions are discarded — the user has to redo them on the
  next run.

  When a corpus-mode C2c AskUserQuestion returns a user-abort signal:
  1. **Dispatch Phase B with the PARTIAL decision-set** the user has
     already answered. Phase B is idempotent (log dedupe + has-decision
     filter) so this is safe.
  2. After Phase B completes, surface to the user that the run is
     stopping with progress preserved:
     ```
     Aborted mid-walk on <spec-id> at R-id <N>/<total>.
     <K> decisions applied to log; <total - K> R-ids will resurface on
     the next /spec-backfill --all run.
     ```
  3. Exit the corpus loop (do NOT continue to the next spec).

  The full corpus run is interruptible at any boundary; this fix makes
  the in-spec walk interruptible too without losing answered decisions.
