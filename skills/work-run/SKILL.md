---
description: "Drive a work group autonomously through implementation, dispatching WDs as ready and pausing only for user-required escalations"
argument-hint: "<group-slug> [--cap N] [--resume]"
---

# /work-run "<group-slug>" [--cap N] [--resume]

Drives a fully-decomposed, fully-specified work group through the
feature-pipeline autonomously. Unlike `/work-start --parallel` (which
fires one wave of SPECIFIED WDs, waits for all, then exits),
`/work-run` continuously re-dispatches WDs as their dependencies clear
— so a 10-WD group with cross-WD `required_state: SPECIFIED` deps can
complete in roughly the wall-clock time of the longest single WD.

**The contract.** Sub-agents follow the user-required escalation
protocol established by `/work-start` (see its "User-required
escalation contract" section). When a sub-agent halts on an
escalation, `/work-run` freezes new dispatches, surfaces the question
via `AskUserQuestion`, waits for resolution, then resumes. Currently
in-flight sub-agents continue to run — only the dispatch loop is
paused — so the user only blocks the dispatcher, not the work that
was already underway.

**Arguments:**
- `<group-slug>` — the work group to run
- `--cap N` — maximum concurrent sub-agents (default: 3). Higher uses
  more tokens-per-minute; lower yields wall-clock for cost.
- `--resume` — explicit resume of an existing orchestrator state. If
  the directory exists and `--resume` is NOT passed, the user is asked
  via `AskUserQuestion` whether to resume or clear-and-restart.

**Prerequisites:**
- The group is fully decomposed (`/work-decompose` has run).
- Every WD that should be in scope has been planned (`/work-plan`).
  Only WDs with `status: SPECIFIED` and satisfied deps enter the
  dispatch queue. WDs in `READY` or `BLOCKED` are not auto-planned —
  the user owns the specification phase.
- The user has already verified the WGs' specs/decisions are coherent.
  `/work-run` will surface design questions but it does NOT do upfront
  spec authoring.

---

## Step 0 — Concurrency guard

Before doing anything else, check whether another `/work-run` instance
might already be driving this group. Use **`mkdir`-based atomic acquisition**
(not echo-into-file, which has a TOCTOU race between liveness check and
write — adversarial review HIGH #3, 2026-05-11):

```bash
ORCH_DIR=".work/<group-slug>/.orchestrator"
mkdir -p "$ORCH_DIR" 2>/dev/null || true
LOCK_DIR="$ORCH_DIR/driver.lock"

# Atomic test-and-set. mkdir fails if the directory exists — no race.
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    held_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
    if [[ -n "$held_pid" ]] && kill -0 "$held_pid" 2>/dev/null; then
        echo "ERROR: /work-run is already running (driver pid $held_pid)"
        echo "       If that process is dead, remove $LOCK_DIR and retry."
        exit 1
    fi
    # Stale lock — held pid is dead. Clean up and retry once.
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" || { echo "ERROR: could not acquire lock"; exit 1; }
fi
echo $$ > "$LOCK_DIR/pid"
trap "rm -rf '$LOCK_DIR'" EXIT
```

**Cap validation** (MEDIUM #1, 2026-05-11): reject `--cap` values below 1.
A `--cap 0` would silently terminate the run without dispatching anything.

```bash
if [[ "$cap" -lt 1 ]]; then
    echo "ERROR: --cap must be >= 1 (got $cap)"
    exit 2
fi
```

The lock directory is the single-driver enforcement the orchestrator's
state machine relies on. The orchestrator script itself doesn't check
this — `/work-run` does, because it knows it's the only sanctioned
driver.

---

## Step 1 — Validate work group

Check `.work/<group-slug>/` exists. If not, list available groups and
stop. (Same as `/work-start` Step 1.)

Display the opening header:

```
───────────────────────────────────────────────
🏃 WORK RUN · <group-slug>
───────────────────────────────────────────────
```

---

## Step 2 — Initialize or resume orchestrator

Two branches based on whether `.work/<group-slug>/.orchestrator/`
already exists.

**Guard (HIGH #5, 2026-05-11):** if `--resume` was passed but the
orchestrator directory does NOT exist, error out before doing anything
else — the user's explicit intent (resume an existing run) cannot be
satisfied:

```bash
if [[ "$resume_flag" == "1" && ! -d "$ORCH_DIR" ]]; then
    echo "ERROR: --resume requested but no orchestrator state exists for <group-slug>."
    echo "       Run /work-run <group-slug> without --resume to start fresh."
    exit 1
fi
```

### 2a. Orchestrator state exists

Display its current state:

```bash
bash .claude/scripts/work-orchestrator.sh status "<group-slug>"
```

**Cold-resume reconciliation (HIGH #7, 2026-05-11).** Before re-entering
the loop, scan `in-flight/` for stale records — a previous /work-run
session may have died with sub-agents in flight whose notifications
were lost. For each in-flight record:

1. Read `feature_slug` from the record + `dispatched_at`.
2. Check `.feature/<feat>/status.md` mtime. If it does not exist OR
   has not been touched since `dispatched_at` + a small allowance
   (say 60s), the sub-agent likely never started or its parent died
   before its first stage transition.
3. For each such stale record, use `AskUserQuestion`:
   - Title: "`<wd-id>` was in-flight when the prior session ended,
     but status.md shows no activity. Mark as STOPPED, retry dispatch,
     or keep waiting?"
   - Options: **Mark STOPPED** / **Retry dispatch** / **Keep waiting**
4. Apply the user's choice via the orchestrator
   (`complete <wd> STOPPED_AT_unknown "stale on resume"` /
    move record back to queue + new dispatch in Step 3e / leave it).

If `--resume` was passed on the command line, skip the resume-vs-clear
prompt below (the user already declared intent) and proceed to the
reconciliation pass + Step 3.

Otherwise, use `AskUserQuestion`:

- Title: "Existing orchestrator state found for `<group-slug>`. Resume from
  where it left off, or clear and start fresh?"
- Options:
  - **Resume** — run cold-resume reconciliation above, then enter loop
  - **Clear and restart** — run `work-orchestrator.sh clear` + `init` (DESTRUCTIVE — completed-set is preserved nowhere else). Warns user that any currently-running sub-agents become orphans; their completion notifications will arrive into a fresh-state /work-run that has no in-flight record matching them, and Step 3a will ignore them.
  - **Stop** — exit `/work-run` without changes

### 2b. No orchestrator state

Initialize:

```bash
bash .claude/scripts/work-orchestrator.sh init "<group-slug>" --cap <N>
```

If `init` errors (typo'd group, work-resolve failure), the
orchestrator script will print a diagnostic — surface it to the user
and stop. Do not proceed with a half-built state.

The initial queue contains every WD with `status: SPECIFIED` AND all
artifact_deps satisfied. If the queue is empty:

```
No SPECIFIED WDs in <group-slug> ready to dispatch.

This usually means /work-plan has not been run on this group yet, or
all WDs are blocked on cross-WD dependencies whose upstream isn't
COMPLETE.

  Run /work-status <group-slug> to see the readiness breakdown.
  Run /work-plan <group-slug> to take READY WDs to SPECIFIED.
```

Clear the orchestrator state (`work-orchestrator.sh clear`) so the
next run starts fresh, and exit.

---

## Step 3 — Driver loop

This is the main loop. Each iteration is a single LLM turn — the skill
body runs top-to-bottom once per turn, then returns. Background-agent
completion notifications cause the next turn, which re-enters the loop
through this step.

### 3a. Reconcile any pending in-flight completions

**Source of truth.** When a background sub-agent completes, the runtime
delivers its final assistant message in the new turn's input — this is
the canonical signal of completion, NOT the dispatch marker (the
marker only records `begin`; `/work-run` never writes `ack` or `fail`,
so its `result` field is always null while in-flight).

**Matching notification → WD.** The agent's final message will start
with the `<feature-slug>:` prefix per PR A's escalation contract. To
recover the WD-id, look up the in-flight record by feature_slug:

```bash
WD_ID=$(grep -l "\"feature_slug\":[[:space:]]*\"<slug>\"" \
        "$ORCH_DIR/in-flight/"*.json 2>/dev/null \
        | head -1 | xargs -I{} basename {} .json)
```

If multiple completion notifications batched in this turn (the user
spent time answering AskUserQuestion in 3c, several siblings finished
during that wait), process each by repeating the lookup-and-classify
sequence. The orchestrator's per-WD mutations are atomic, so order
within a turn doesn't matter.

For each completion:

1. Extract the return line from the new turn's input (the agent's
   final assistant message — one line of the form
   `<feature-slug>: <STATUS> — <detail>`).

2. Classify (5-way, per `/work-start`'s escalation contract — match
   `ESCALATION_AT_` BEFORE `STOPPED_AT_` since both share the
   `<STATUS>_AT_<stage>` shape):
   - `ESCALATION_AT_<stage> — <category>: <question>` → **escalation**
   - `COMPLETE — <detail>` → **clean**
   - `STOPPED_AT_<stage> — <detail>` → **stopped mid-pipeline**
   - `ERROR — <detail>` → **errored**
   - `SKIPPED — <detail>` → **claim conflict** (rare under orchestrator)
   - Unparseable → **parse-failed**
   - Agent return literally equals `[Tool result missing due to internal error]` → **payload-lost**
   - Agent return contains `The user doesn't want to proceed with this tool use.` → **user-stopped**

3. Route to the orchestrator. **Always single-quote the reason
   argument** (MEDIUM #6, 2026-05-11) — return lines can carry
   `$()`, backticks, or semicolons. Pass via single quotes and
   escape any embedded `'` via the `'\''` pattern. Example:
   `'this is a 'safer' message'` → `'this is a '\''safer'\'' message'`.

   | Classification | Orchestrator call |
   |----------------|-------------------|
   | escalation | `block <group> <wd-id> 'escalation:<category>' '.feature/<slug>/escalation.json'` |
   | clean | `complete <group> <wd-id> COMPLETE '<line>'` |
   | stopped | `complete <group> <wd-id> 'STOPPED_AT_<stage>' '<line>'` |
   | errored | `complete <group> <wd-id> ERROR '<detail>'` |
   | skipped | `complete <group> <wd-id> SKIPPED '<detail>'` |
   | parse-failed | `complete <group> <wd-id> ERROR 'parse-failed: <first 80 chars>'` |
   | payload-lost | `complete <group> <wd-id> ERROR 'payload-lost'` |
   | user-stopped | `complete <group> <wd-id> ERROR 'user-stopped'` |

4. **Orphan notifications** (clear-and-restart edge case). If the
   `feature_slug` lookup at step 1 returns no matching in-flight
   record, this notification is from a sub-agent that was orphaned
   by a prior `clear`. Log it to stderr and skip — do NOT call the
   orchestrator with an unknown WD-id (would error).

### 3b. Check for hung in-flight WDs

```bash
HUNG=$(bash .claude/scripts/work-orchestrator.sh hung "<group-slug>" --threshold-seconds 1800)
```

If non-empty, for each line `<wd-id> <delta-seconds> <feature-slug>`:

Use `AskUserQuestion`:
- Title: "WD-<nn> has not transitioned in <delta-min> min. Continue waiting, mark as stopped, or investigate?"
- Options:
  - **Keep waiting** — pipeline durations vary; some legitimately take 30+ min
  - **Mark STOPPED** — accept that the sub-agent is wedged; `complete <wd> STOPPED_AT_unknown "hung past threshold"` and continue
  - **Investigate** — exit `/work-run` so the user can inspect `.feature/<slug>/` manually

### 3c. Surface escalations if paused

```bash
PAUSED=$(grep -oE '"paused":[[:space:]]*(true|false)' "$ORCH_DIR/state.json" | head -1 | grep -o 'true\|false')
```

If paused == true, enumerate `$ORCH_DIR/blocked/*.json`. For each
blocked WD:

1. Read `blocked/<wd>.json` to get `feature_slug` and `escalation_path`.
2. Read `<escalation_path>` (`.feature/<slug>/escalation.json`) for
   the structured question. **Validate the file exists and parses as
   JSON with a `question` field** (MEDIUM #2, 2026-05-11):

   ```bash
   if [[ ! -f "$escalation_path" ]] || ! python3 -c "import json; d=json.load(open('$escalation_path')); assert 'question' in d" 2>/dev/null; then
       missing_escalation=1
   fi
   ```

   If missing or malformed, construct a fallback AskUserQuestion below.

Use `AskUserQuestion` with the appropriate construction. **Cap the
total option count at 4** (per kit's interactive-prompt standard;
MEDIUM #7, 2026-05-11) — if escalation.json's `options` array exceeds
2 entries, present the first 2 and instruct the user to consult the
JSON file for the rest.

**Construction A — escalation.json valid with `options`:**

- Title: WD-id + the `question` field
- Options (up to 4):
  - First option from escalation.json `options[0]` (label + description)
  - Second option from `options[1]` if present (and not "Other"-shaped)
  - **Skip this WD** — mark as ERROR
  - **Abort run** — exit cleanly
- If `options` has more than 2 entries, suffix the title with
  "(see `<escalation_path>` for all <N> candidate answers)"

**Construction B — escalation.json valid without `options`:**

- Title: WD-id + the `question` field
- Options:
  - **I've resolved it externally — re-dispatch**
  - **Skip this WD**
  - **Abort run**
  - **Other** (with text input) — record the answer

**Construction C — escalation.json missing or malformed (fallback):**

- Title: "WD-`<wd-id>`: sub-agent escalated but `escalation.json` is missing/malformed. Final return line: `<line>`. How to proceed?"
- Options:
  - **Re-dispatch as-is** (assume the user has already resolved out of band)
  - **Skip this WD**
  - **Abort run**
  - **Inspect** (exit so user can investigate)

Per the user's chosen action:

- **Resolved** (Constructions A/B) → write `.feature/<slug>/escalation-resolved.md`
  recording the user's choice + verbatim answer text + timestamp,
  then `unblock <group> <wd-id>` (re-queue). The re-dispatched sub-agent
  prompt below (Step 3e) tells the next agent to read this file.
- **Sub-agent option chosen** (Construction A) → record the chosen
  option's label + description in `.feature/<slug>/escalation-resolved.md`,
  then `unblock <wd-id>`.
- **Skip** → `skip <group> <wd-id> '<user-supplied reason>'` (atomic
  blocked → completed:ERROR, per PR C's orchestrator `skip` subcommand;
  CRITICAL #1, 2026-05-11). Do NOT use `unblock + complete` — the
  intermediate queue state breaks because `complete` requires in-flight.
- **Abort** → drop the lock, exit cleanly with: "to resume:
  /work-run `<group-slug>` --resume. Currently in-flight sub-agents
  will continue to completion; their notifications arrive into the
  next session." Document explicitly that blocked/ and in-flight/
  remain on disk for next-session reconciliation.

Repeat per blocked WD until `blocked/` is empty.

Then:

```bash
bash .claude/scripts/work-orchestrator.sh resume "<group-slug>"
bash .claude/scripts/work-orchestrator.sh resolve "<group-slug>"
```

The orchestrator's `resume` refuses while `blocked/` is non-empty
(safety guard from PR B), so this only succeeds after every escalation
is resolved. Run `resolve` afterwards: the user's escalation
resolutions may have edited specs/ADRs in ways that unblock WDs which
were previously BLOCKED in work-resolve's view but never queued.

**Notification timing (HIGH #4, 2026-05-11).** AskUserQuestion is
synchronous within the turn — while the user is answering, in-flight
sub-agents may complete and queue notifications. Those notifications
are NOT delivered mid-turn; they queue. After 3c's AskUserQuestion
loop, when the turn yields, the next turn fires with the queued
notifications visible. Step 3a's "extract feature_slug + lookup
in-flight" pattern handles multiple completions in one batch.

### 3d. Termination check

If all of the following are true, the run is complete:

- `ready` (from `work-orchestrator.sh ready`) is empty
- `in-flight/` is empty
- `blocked/` is empty

Go to Step 4 — completion summary.

### 3e. Dispatch new sub-agents

Compute the ready set:

```bash
READY=$(bash .claude/scripts/work-orchestrator.sh ready "<group-slug>")
```

For each WD in `READY` (one per line):

1. Compute the feature slug: `<group-slug>--<wd-id>`.

2. **Feature-directory preparation — single deterministic approach**
   (HIGH #6, 2026-05-11 — one prescribed strategy, no alternatives).
   The dispatched sub-agent's pipeline expects `.feature/<feature-slug>/`
   to exist with a seeded `status.md`, `brief.md`, and `cycle-log.md`.
   `/work-start` Step 4 does this work. Rather than duplicate it, the
   /work-run dispatch protocol is: **the sub-agent's prompt invokes
   `/work-start "<group-slug>" <wd-id>` as the first step**, which
   creates the feature directory AND immediately falls into the
   single-WD pipeline (`/feature-plan` → ... → `/feature-refactor`).
   `/work-start`'s claim-via-work-claim.sh sees the WD is already
   IMPLEMENTING (orchestrator's `dispatch` set this state), takes
   the IMPLEMENTING path, and proceeds. **The sub-agent does NOT
   re-dispatch — /work-start in autonomous mode runs the pipeline
   inline.** This is the contract.

3. Call `work-orchestrator.sh dispatch <group> <wd-id> <feature-slug>`
   (this moves the WD from queue to in-flight). The dispatch MUST
   happen before the Agent call so that if the Agent call errors
   synchronously (next step), the orchestrator's in-flight record
   accurately reflects the attempt.

4. Write a dispatch marker:
   ```bash
   bash .claude/scripts/work-dispatch.sh begin "<group-slug>" "<wd-id>"
   ```

5. **Check for a prior escalation-resolved.md** (MEDIUM #3, 2026-05-11).
   If `.feature/<feature-slug>/escalation-resolved.md` exists from a
   previous escalation cycle, its contents are appended to the
   sub-agent prompt so the agent doesn't re-encounter the same
   ambiguity. Without this, a re-dispatched sub-agent would re-write
   the same escalation.json → infinite loop.

6. Dispatch the Agent with `run_in_background: true`:

   **Prompt for each sub-agent:**
   ```
   You are the dynamic pipeline runner for <feature-slug>.

   Invoke /work-start "<group-slug>" <wd-id> --nested — the --nested
   flag tells /work-start to write nested_in_dispatch: true +
   execution_strategy: cost into status.md (because nested sub-agent
   contexts cannot dispatch /feature-coordinate's parallel batches).
   /work-start will then claim the WD via work-claim.sh, create
   the feature directory at .feature/<feature-slug>/ if not present,
   and run the single-WD pipeline (/feature-plan → /feature-test →
   /feature-implement → /feature-refactor → /feature-pr) in
   automation_mode autonomous with execution_strategy cost (sequential
   work-unit execution — the orchestrator provides parallelism at
   the WD level).

   <If escalation-resolved.md exists, insert here verbatim:>
   ── Prior escalation resolution ──
   The user previously resolved a USER-REQUIRED escalation on this WD.
   Read .feature/<feature-slug>/escalation-resolved.md for their answer
   before proceeding. Apply the resolution and continue the pipeline.

   Follow the user-required escalation contract from /work-start: on a
   NEW USER-REQUIRED escalation, write
   .feature/<feature-slug>/escalation.json (schema in /work-start's
   "User-required escalation contract" section), append a
   `user-escalation — <category>: <question>` entry to cycle-log.md,
   set status.md substage to `awaiting-user-input`, and halt.

   Return EXACTLY one line of one of these forms:
     "<feature-slug>: COMPLETE — <detail>"
     "<feature-slug>: ESCALATION_AT_<stage> — <category>: <question>"
     "<feature-slug>: STOPPED_AT_<stage> — <detail>"
     "<feature-slug>: ERROR — <detail>"
   ```

7. **Check the Agent tool's immediate return for synchronous errors**
   (HIGH #2, 2026-05-11). `run_in_background: true` returns immediately,
   but the runtime may reject the dispatch synchronously (max-agents,
   user-rejected, malformed prompt). If the return indicates a
   synchronous error rather than "dispatched":
   - The agent never started; no notification will arrive.
   - Call `complete <group> <wd-id> ERROR '<sync error detail>'` in
     the same turn to release the in-flight slot.
   - Continue dispatching the rest of the ready set.

   Do NOT yield without reconciling synchronous-error dispatches — the
   in-flight record would otherwise wedge the cap-vs-inflight math
   until the 30-min hung detector caught it.

After all dispatches (or failed dispatches), the loop body completes
its turn. For successfully-dispatched agents, the runtime will deliver
a system notification when each finishes; that notification triggers a
new LLM turn which re-enters Step 3 from the top.

### 3f. Yield

End the current turn. The skill body has done what it can with the
current orchestrator state. Display a compact summary to the user
before yielding:

```
── /work-run tick · <group> ───────────────
  ready dispatched this turn: <N>
  in-flight: <M>
  completed: <P> / <total>
  blocked: <Q>
  paused: <yes|no>
  next: waiting for background sub-agent completion
```

---

## Step 4 — Completion summary

The orchestrator's queue, in-flight, and blocked sets are all empty.
Print the final summary:

```bash
bash .claude/scripts/work-orchestrator.sh status "<group-slug>"
```

Plus a roll-up:

```
🏁 /work-run complete · <group-slug>
───────────────────────────────────────
Total WDs:    <N>
COMPLETE:     <n>
STOPPED:      <list with WD-id + stage>
ERROR:        <list with WD-id + reason>
Wall clock:   <last_tick - started_at>
───────────────────────────────────────

Recommended next steps:
  - For STOPPED WDs: /feature-resume <feature-slug> to pick up
  - For ERROR WDs: inspect .feature/<slug>/ and decide
  - Clear orchestrator state when done: work-orchestrator.sh clear <group>
```

Use `AskUserQuestion`:

- Title: "Run complete. Clear the orchestrator state?"
- Options:
  - **Clear now** — `work-orchestrator.sh clear <group>` + remove driver.pid
  - **Keep state for inspection** — leave `.orchestrator/` for later review

Then drop the driver lock and exit.

---

## Failure modes and recovery

- **User pressed ESC during dispatch** — the Agent tool returns "user
  rejected"; classify as user-stopped; orchestrator marks fail with
  reason `user-stopped`; user re-invokes `/work-run --resume` to
  continue. The dispatch marker stays as a record.
- **Background agent crashes (payload-lost)** — same recovery as
  user-stopped; `complete <wd> ERROR "payload lost"`.
- **`/work-run` process killed mid-turn** — driver.pid remains, lock
  blocks re-invocation. User confirms the PID is dead (`ps`), removes
  the lock, re-invokes. The orchestrator's persistent state is intact.
- **Sub-agent dispatch marker says begin but no return notification
  ever arrived** — the agent is wedged. `hung` will eventually catch
  it via the status.md mtime threshold; user is prompted to mark
  STOPPED or investigate.

---

## Why this skill exists

- `/work-start --parallel` fires one wave of ready WDs and waits for
  ALL to complete before exiting. A 10-WD group with one slow outlier
  pays for the outlier's full duration without using the freed slots.
  `/work-run` dispatches newly-ready WDs the moment a sibling
  completes.
- The escalation contract from `/work-start` (PR A) lets sub-agents
  signal "I need user input" in a structured way; without
  `/work-run`'s loop, users would have to manually re-invoke
  `/work-start` after each escalation. `/work-run` automates the
  loop: pauses on escalation, surfaces via `AskUserQuestion`, resumes
  cleanly.
- The orchestrator state machine (PR B) persists across crashes;
  `/work-run --resume` picks up where a killed session left off.

This skill is the "press play" wrapper on top of the contract + state
machine.
