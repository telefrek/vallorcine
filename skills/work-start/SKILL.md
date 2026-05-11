---
description: "Start implementing a specified work definition — implementation pipeline only"
argument-hint: "<group-slug> [WD-nn | next | all | --parallel [N]]"
---

# /work-start "<group-slug>" [WD-nn | next | all | --parallel [N]]

Bridges a work definition from a work group into the implementation pipeline.
Creates a `.feature/` directory and hands off to planning, testing, and
implementation. For specification-only work (producing specs, ADRs, or
interface contracts), use `/work-plan` instead.

**Arguments:**
- `<group-slug>` — the work group to draw from
- `WD-nn` — start a specific work definition (e.g., WD-01)
- `next` — auto-select the highest-value READY work definition
- `all` — sequentially run every SPECIFIED WD (one subagent per WD,
  waits for each to finish before starting the next). See "Sequential
  all mode" below. **Use this for context-economy on multi-WD groups —
  the parent stays small while each subagent gets a fresh context.**
- `--parallel [N]` — start every SPECIFIED WD concurrently (optionally
  cap at N concurrent sub-agents). See "Parallel mode" section below.

If no WD argument is provided, defaults to `next`.

**Choosing between `all` and `--parallel`:**

Both delegate to the same single-WD `/work-start` flow, so quality at
arbitration boundaries is identical — both modes set
`automation_mode: autonomous` for the dispatched sub-agents (escalations
surface, routine choices auto-default).

| | `all` (sequential) | `--parallel` |
|---|---|---|
| Subagents in flight | 1 at a time | N concurrent |
| Wall clock | N × per-WD time | ~1 × per-WD time |
| Token cost | Sum of per-WD costs | Sum (same total) |
| Resource contention (DB, ports, manifest) | None | Possible |
| Best for | Context economy, isolation | Wall-clock velocity |

---

## Step 1 — Validate work group

Check `.work/<group-slug>/` exists. If not:
```
Work group '<group-slug>' not found.

Available groups:
```
List directories in `.work/` (excluding `_archive`, `_refs`).
Stop.

---

## Step 2 — Run readiness resolver

```bash
bash .claude/scripts/work-resolve.sh "<group-slug>"
```

Parse the output to determine the readiness state of all WDs.

Display opening header:
```
───────────────────────────────────────────────
🚀 WORK START · <group-slug>
───────────────────────────────────────────────
```

---

## Step 3 — Select work definition

### If `all` is the argument:

Skip the single-WD selection logic and go to the **Sequential all
mode** section below. The rest of Step 3's single-WD paths (WD-nn /
next) do not apply.

### If `--parallel` flag is present:

Skip the single-WD selection logic and go to the **Parallel mode**
section below. The rest of Step 3's single-WD paths (WD-nn / next) do
not apply.

### If specific WD (e.g., WD-01):

Check the WD's status in the resolver output.

If SPECIFIED: proceed to Step 4.

If BLOCKED: check the blocker detail from the resolver output.
- If blocked by `wd:` deps (predecessor WDs not complete): report which WDs
  must complete first. Do not offer to start — the ordering exists for a reason.
  ```
  WD-<nn> (<title>) is BLOCKED by predecessor work definitions:
    <list blockers from resolver>

  Complete these first, or use /work-start "<group-slug>" next to auto-select
  a WD that is ready.
  ```
  Stop.
- If blocked by unmet artifact deps (spec/adr/kb): this WD needs specification.
  ```
  WD-<nn> (<title>) needs specification before implementation.
  Run /work-plan "<group-slug>" WD-<nn> first.
  ```
  Use AskUserQuestion with options:
    - "Run /work-plan first"
    - "Start anyway (skip specification)"
    - "Stop"

If READY or SPECIFYING: the WD has not been through `/work-plan` yet.
```
WD-<nn> (<title>) needs specification before implementation.
Run /work-plan "<group-slug>" WD-<nn> first.
```
Use AskUserQuestion with options:
  - "Run /work-plan first" (description: "Specify this WD to produce its required artifacts")
  - "Start anyway (skip specification)" (description: "Proceed without specs — not recommended")
  - "Stop"

If "Run /work-plan first": invoke `/work-plan "<group-slug>" WD-<nn>`.
If "Start anyway": proceed to Step 4 with a warning logged.

If IMPLEMENTING: check if a feature directory already exists for this WD:
```
WD-<nn> is already being implemented.
Feature directory: .feature/<group>--<wd-slug>/

Resume with: /feature-resume "<group>--<wd-slug>"
```
Stop.

If COMPLETE:
```
WD-<nn> is already COMPLETE. Nothing to do.
```
Stop.

### If "next" (or no WD specified):

From the SPECIFIED WDs, select the one with the most downstream dependents
(i.e., the WD whose completion would unblock the most other WDs). This
maximizes unblocking value.

If multiple WDs tie on unblocking value, prefer the one with fewer
artifact dependencies (simpler work first).

If no WDs are SPECIFIED:
```
No work definitions are SPECIFIED in '<group-slug>'.

Status:
  <ready>  ready (needs /work-plan first)
  <specifying> specifying
  <implementing> implementing
  <complete> complete

Run /work-plan "<group-slug>" to specify a ready WD first.
```
Stop.

Display the selected WD:
```
Selected: WD-<nn> — <title>
  Domains: <domains>
  Deps: <dep count> (all satisfied)
  Unblocks: <list of WDs this will unblock, or "none">
```

Use AskUserQuestion with options:
  - "Start WD-<nn>"
  - "Pick a different WD"
  - "Stop"

---

## Step 4 — Create feature directory

Generate a feature slug from the work group and WD:
```
<group-slug>--<wd-id-lowercase>
```
Example: `auth-migration--wd-01`

Create `.feature/<slug>/` directory.

### 4a — Generate brief.md

Read the WD file (`.work/<group-slug>/WD-<nn>.md`). Build `brief.md` from:

```markdown
# Feature Brief: <WD title>

**Source:** Work group '<group-slug>', WD-<nn>
**Generated:** <YYYY-MM-DD>

## Description
<WD Summary section content>

## Acceptance Criteria
<WD Acceptance Criteria section content>

## Constraints
<WD Implementation Notes section content>

## Artifact Dependencies (from work group)
<List each artifact_dep with its current state>

## Produced Artifacts (expected outputs)
<List each produces entry>

## Work Group Context
<Run work-context.sh --group "<group-slug>" and include relevant excerpt>
```

### 4b — Verify implementation readiness

If the WD's `artifact_deps` include unresolved items (the WD was started
with "Start anyway" in Step 3), display a warning:
```
  Warning: This WD has unresolved artifact dependencies.
  Consider running /work-plan "<group-slug>" WD-<nn> first to produce
  the required specifications.
```
Proceed regardless — the user explicitly chose to start.

### 4c — Write status.md

Write `.feature/<slug>/status.md` with the standard format plus work group
metadata:

```yaml
work_group: <group-slug>
work_definition: WD-<nn>
pipeline_mode: implementation
```

Set stage = `planning`, substage = `loading-context`.

Stage Completion table — implementation stages only:

| Stage | Status |
|-------|--------|
| Planning | pending |
| Testing | pending |
| Hardening | pending |
| Implementation | pending |
| Refactor | pending |

### 4d — Claim the WD (SPECIFIED → IMPLEMENTING)

Use `work-claim.sh` for the status transition. It does an atomic
compare-and-swap under flock so two parallel sessions racing to start
implementation on the same WD cannot both succeed — the second one
gets a CONFLICT and bails out.

```bash
if ! bash .claude/scripts/work-claim.sh "<group-slug>" "WD-<nn>" SPECIFIED IMPLEMENTING; then
  echo ""
  echo "Another session has already started this WD. Run:"
  echo "  /work-resume \"<group-slug>\""
  echo "to see what to do next (likely: /feature-resume \"<group>--<wd-slug>\")."
  exit 1
fi

# Refresh the manifest table and readiness JSON cache so other skills
# and parallel sessions see the new state without waiting for the next
# /work-status call.
bash .claude/scripts/work-resolve.sh "<group-slug>" >/dev/null
```

The manifest table is automatically synced by `work-resolve.sh` — do not
update it manually.

---

## Step 5 — Hand off to pipeline

```
Feature directory created: .feature/<slug>/
Pipeline mode: implementation (specifications already exist)

Proceeding directly to work planning — specs and ADRs will be loaded
from the resolved context.
```
Invoke `/feature-plan "<slug>"`.

---

## Sequential all mode

When invoked with `all`, `/work-start` runs every SPECIFIED work
definition in the group **one at a time**, dispatching a separate
sub-agent that executes the existing single-WD `/work-start` flow for
each. The coordinator (this skill, in the user's conversation) carries
only the dispatch state and one-line summaries of completed runs — the
heavy 200K-per-WD planning + testing + implementation context lives
inside each sub-agent and is gone when it returns.

This is the structural automation of the
`/clear` + `/work-resume` + `/work-start WD-N` rhythm: same per-WD
context economy, same dependency-respecting selection, no `/clear` or
`/work-resume` typed by the user during the run.

### When to use `all` vs `--parallel`

Both run every SPECIFIED WD in the group. The trade-off is wall-clock
vs. resource isolation, NOT quality of arbitration — both modes
delegate to the same single-WD `/work-start` flow which uses the same
mode-gating in pipeline skills.

`all` (sequential):
- **Context economy is the priority** — multi-WD groups that would
  otherwise accumulate context across skill switches.
- **No spec/test resource contention** by construction — one
  sub-agent at a time.
- **One arbitration session per WD** — the user only sees prompts for
  the WD currently in flight.

`--parallel`:
- Wall-clock speed is the priority AND the WDs are runtime-isolated.
- N× token cost is acceptable.
- Concurrent sub-agents may serialize on shared writes (manifest, KB)
  — see Parallel mode caveats.

Both modes use `automation_mode: autonomous` and
`execution_strategy: balanced` for the dispatched sub-agents (set by
the single-WD flow at Step 4c). Routine choices auto-default;
escalations surface to the user.

### Sequential-all flow

Replace Steps 3–5 with this block when `all` is the argument.

1. **Initial enumeration.** Read `_readiness.json` (refreshed by the
   resolver call in Step 2) and collect every WD whose status is
   `SPECIFIED`. If zero, report and stop:
   ```
   No SPECIFIED work definitions in '<group-slug>' — run /work-plan
   "<group-slug>" all to specify READY WDs first, or check
   /work-status for blockers.
   ```

2. **Show the plan.** Compute the initial run order — sort by
   unblocking value (most downstream dependents first), tie-breaking
   by fewer artifact dependencies. Display:
   ```
   ── Sequential start plan ──────────────────────
   Group: <group-slug>
   SPECIFIED WDs: <N>
   Initial order (by unblocking value):
     1. WD-<nn> — <title>  (unblocks: <list>)
     2. WD-<nn> — ...
   Note: a WD's completion may unblock a sibling that's currently
   BLOCKED on a wd: dep — the loop re-enumerates between iterations,
   so the run may include WDs not in this initial list.
   ───────────────────────────────────────────────
   ```
   Use AskUserQuestion to confirm:
     - "Run sequentially" (Recommended)
     - "Cap at 3" (or another cap)
     - "Stop"

3. **Iterate until no eligible WD remains.** Loop:

   a. **Re-enumerate.** Run `bash .claude/scripts/work-resolve.sh
      "<group-slug>" >/dev/null` then re-read `_readiness.json`. Re-
      enumerating is mandatory — completing a WD in iteration N may
      satisfy a `wd:` or spec dep that promotes a sibling from
      BLOCKED to SPECIFIED in iteration N+1.

   b. **Pick the next.** From the current SPECIFIED list, pick the
      WD with the highest unblocking value (same heuristic as Step 2).
      Skip WDs the run has already dispatched (track in a dispatched
      set keyed by WD id). If no SPECIFIED WD remains that hasn't been
      dispatched, exit the loop.

   c. **Honor the cap.** If the user chose a cap in Step 2 and the
      dispatched count has reached it, exit the loop.

   d. **Dispatch ONE sub-agent that recursively invokes the
      single-WD `/work-start`.** This is critical — do NOT hand-roll
      the feature creation + claim + pipeline dispatch logic in this
      coordinator. The single-WD flow already does it correctly.

      **Before the Agent call**, write a dispatch marker so a
      lost-payload or rejected-dispatch failure does not leave the
      coordinator's task list silently out of sync with reality:
      ```bash
      bash .claude/scripts/work-dispatch.sh begin "<group-slug>" "<wd-id>"
      ```
      This creates `.work/<group-slug>/_dispatch-<wd-id>.json` with
      `ack: false`. Step 3f flips it to `ack: true` once the result is
      parsed (or marks `failure_reason` when parsing fails). The marker
      is what `/work-resume` uses to detect stuck dispatches and
      surface them as recovery candidates.

      **Then invoke the sub-agent** with this prompt verbatim:
      ```
      You are the sequential pipeline runner for <group-slug> /
      <wd-id>.

      Invoke /work-start "<group-slug>" <wd-id>. The single-WD flow
      will create the feature directory, claim the WD via
      work-claim.sh (SPECIFIED → IMPLEMENTING), and hand off to
      /feature-plan → /feature-test → /feature-implement →
      /feature-refactor → /feature-pr.

      Treat automation_mode as autonomous. Do not pause between
      pipeline stages. If a stage hits a TECHNICAL escalation (test
      conflict, missing tests, refactor escalation), record it in the
      feature's cycle-log.md and continue with remaining stages where
      possible — this is auto-handled and reported in your summary.

      If a stage hits a USER-REQUIRED escalation (design ambiguity,
      missing context the kit can't supply, irreconcilable spec
      conflict, an impossible requirement), follow the user-required
      escalation contract from /work-start: write
      .feature/<feature-slug>/escalation.json with the schema in the
      "User-required escalation contract" section, append a
      `user-escalation — <category>: <question>` entry to cycle-log.md,
      set status.md substage to `awaiting-user-input`, then halt the
      WD and return ESCALATION_AT_<stage> as below.

      Distinguish these return modes in your final return:

      - If the /work-start invocation reports a `[claim] CONFLICT:`
        message from work-claim.sh (another terminal advanced the WD
        between the coordinator's enumeration and this dispatch),
        return:
          "<group-slug>--<wd-id>: SKIPPED — claim conflict"

      - If you wrote escalation.json per the contract, return:
          "<group-slug>--<wd-id>: ESCALATION_AT_<stage> — <category>: <question>"

      - Any other failure (feature directory creation, status.md
        write error, pipeline escalation, unexpected exception) is an
        ERROR — return:
          "<group-slug>--<wd-id>: ERROR — <one-line detail>"

      Successful runs return:
        "<group-slug>--<wd-id>: <COMPLETE | STOPPED_AT_<stage>> — <detail>"

      Return exactly ONE line and nothing else after. The coordinator
      parses this string.
      ```

   e. **Wait for the sub-agent to return.** The Agent tool blocks
      until the child emits its final assistant message.

   f. **Classify the return and update the marker.** The Agent tool
      returns one of five shapes. Treat each distinctly — silent
      assumptions corrupt the task list. **Match `ESCALATION_AT_`
      before `STOPPED_AT_`** since both share the `<STATUS>_AT_<stage>`
      shape.

      - **Escalation return** matching `<group-slug>--<wd-id>: ESCALATION_AT_<stage> — <category>: <question>`.
        The sub-agent halted awaiting user input and has written
        `.feature/<group>--<wd>/escalation.json` with the structured
        question (see "User-required escalation contract"). Mark with
        the category as the reason so the future orchestrator can
        route:
        ```bash
        bash .claude/scripts/work-dispatch.sh fail "<group-slug>" "<wd-id>" "escalation:<category>"
        ```
        Use `fail` (not `ack`) because the WD is not complete — it is
        paused awaiting user input. Append to a dedicated escalations
        list separate from the clean-return aggregate.

      - **Clean return** matching `<group-slug>--<wd-id>: <STATUS> — <detail>`
        (where STATUS is one of `COMPLETE`, `STOPPED_AT_<stage>`,
        `ERROR`, `SKIPPED`). Acknowledge:
        ```bash
        bash .claude/scripts/work-dispatch.sh ack "<group-slug>" "<wd-id>" "<exact return line>"
        ```
        Append to the aggregate results list.

      - **Payload lost** — the Agent return literally equals
        `[Tool result missing due to internal error]` or otherwise
        contains no parseable result. The sub-agent may have run,
        partially run, or never started; the result is gone. Mark:
        ```bash
        bash .claude/scripts/work-dispatch.sh fail "<group-slug>" "<wd-id>" "payload-lost"
        ```
        Surface to the user via AskUserQuestion: "Pause for
        `/work-resume <group-slug>` recovery" / "Continue with the
        next WD (recovery later)" / "Stop the run". Do NOT advance
        the coordinator's TaskTool entry to `completed` — leave it
        `in_progress` so the user sees that it needs attention. The
        marker is the durable record; recovery is `/work-resume`.

      - **User stopped** — the Agent return contains
        `The user doesn't want to proceed with this tool use. The tool
        use was rejected.` The sub-agent never started. Mark:
        ```bash
        bash .claude/scripts/work-dispatch.sh fail "<group-slug>" "<wd-id>" "user-stopped"
        ```
        Surface to the user via AskUserQuestion: "Re-dispatch this WD"
        / "Continue with the next WD" / "Stop the run". Re-dispatching
        is safe because the sub-agent never claimed; `/work-start`
        will see the WD still SPECIFIED (or IMPLEMENTING if a previous
        attempt got further) and the marker will be overwritten on
        the next `begin`.

      - **Parse failed** — the return is a string but does not match
        the expected shape. Mark:
        ```bash
        bash .claude/scripts/work-dispatch.sh fail "<group-slug>" "<wd-id>" "parse-failed: <first 80 chars of return>"
        ```
        Surface the same recovery prompt as payload-lost. The marker
        records the unparseable tail so `/work-resume` can show it.

      Append to the aggregate. Display incrementally:
      ```
      [<n>/<eligible>] <group-slug>--<wd-id>: <STATUS> — <detail>
      ```
      For payload-lost / user-stopped / parse-failed lines, show:
      ```
      [<n>/<eligible>] <group-slug>--<wd-id>: DISPATCH FAILURE (<reason>) — recoverable via /work-resume
      ```

   g. **Stop conditions.** Continue unless:
      - The sub-agent returned `ERROR` or `STOPPED_AT_<stage>` AND
        the user opts to halt (AskUserQuestion: "Continue with
        remaining" / "Stop and inspect").
      - The dispatch hit `payload-lost` / `user-stopped` /
        `parse-failed` AND the user picked "Pause" / "Stop" in 3f.
      - SKIPPED returns are silent — log and continue (the coordinator
        intentionally tolerates conflicts as parallel-session signals).

4. **Final aggregate.** When the loop exits:
   ```
   ── Sequential run complete · <group-slug> ─────
   Dispatched: <N>
   Complete: <n>
   Stopped mid-pipeline: <list with stage>
   Errored: <list with detail>
   Skipped (claim conflict / no longer eligible): <list>
   ───────────────────────────────────────────────

   Next steps:
     <if any stopped/errored:> /feature-resume "<group>--<wd-id>" — inspect each
     <if any new SPECIFIED post-run:> /work-start "<group-slug>" all — run the next batch
     <if all complete:> the group is fully implemented; consider /feature-retro on each feature
   ```

### Concurrency caveats

Sequential `all` avoids parallel-mode hazards by construction — one
WD's pipeline finishes before the next starts. Two failure modes
remain, both handled gracefully:

- **Another terminal racing the same WD.** `work-claim.sh` (called
  inside the dispatched single-WD flow at Step 4d) rejects the claim
  with CONFLICT and exits 1. The sub-agent returns
  `SKIPPED — claim conflict` and the coordinator continues to the next
  WD. No corruption, no stuck loop.
- **Status drift mid-run.** A WD that was SPECIFIED at Step 3a may be
  IMPLEMENTING by Step 3b (another terminal got there). The
  re-enumeration at the top of every iteration catches this — the
  ineligible WD is filtered out before dispatch.

---

## Parallel mode

When invoked with `--parallel [N]`, `/work-start` dispatches every
SPECIFIED work definition in the group as a concurrent sub-agent. Each
sub-agent runs the full feature pipeline
(`/feature-plan` → `/feature-test` → `/feature-implement` →
`/feature-refactor`) in an isolated context.

### When to use parallel mode

Parallel mode is a velocity multiplier when the group has multiple
WDs that are READY to implement and have no runtime cross-dependencies
(e.g., they land in separate modules or produce non-overlapping
artifacts). A wave of five SPECIFIED WDs in a group can complete in
roughly the time of one WD instead of five sequential runs.

### When NOT to use parallel mode

- **WDs share runtime state** (test DB, ports, cache). Parallel test
  execution will fight for resources. Sequential is safer.
- **WDs produce overlapping specs or KB entries.** Concurrent writes
  to the same spec file or KB entry corrupt the registry.
- **The user wants to review each step.** Parallel mode is
  fire-and-wait; individual WD progress is visible in each sub-agent's
  `.feature/<slug>/status.md` but there is no global pause point
  between stages.

### Parallel-mode flow

Replace Steps 3–5 with this block when `--parallel` is set.

1. **Enumerate startable WDs.** Parse the `work-resolve.sh` output
   table and collect every WD whose Status is `SPECIFIED`. If zero,
   report and stop:
   ```
   No SPECIFIED work definitions in '<group-slug>' — run /work-plan
   first to specify READY WDs, or check work-status for blockers.
   ```

2. **Cap concurrency.** If the user supplied `--parallel N`, take the
   first N SPECIFIED WDs (prefer those with more downstream dependents
   — same "unblocking value" heuristic as `next` mode). If `N` is
   omitted, dispatch all of them.

3. **Show the plan.** Display:
   ```
   ── Parallel start plan ─────────────────────────
   Group: <group-slug>
   SPECIFIED WDs: <N>
   Will dispatch concurrently: <dispatched count>

     WD-<nn> — <title>  (domains: <domains>, unblocks: <list>)
     WD-<nn> — ...
   ───────────────────────────────────────────────
   ```
   Use AskUserQuestion to confirm — parallel mode spawns multiple
   long-running pipelines at once and the user should be explicit:
   - "Dispatch all <N> in parallel"
   - "Cap at 2" (or a lower number)
   - "Stop — I'll start them manually"

4. **Create feature directories (all WDs, sequential).** For each
   dispatched WD, run Step 4 from the single-WD path in full: generate
   `brief.md`, verify readiness, write `status.md`, update the WD's
   status to `IMPLEMENTING`. Do this sequentially — these operations
   touch the `.work/` tree and are fast. Fanning out here adds no
   measurable benefit and risks racing on `manifest.md` regeneration.

5. **Dispatch sub-agents concurrently.** First, write a dispatch
   marker for every WD that's about to be dispatched (so a payload-
   loss or user-stop on any single sub-agent can be recovered). Run
   sequentially before the Agent calls:
   ```bash
   for wd_id in <list of WD ids being dispatched>; do
     bash .claude/scripts/work-dispatch.sh begin "<group-slug>" "$wd_id"
   done
   ```
   Then spawn one sub-agent per WD in a **single message with multiple Agent tool calls**.
   Each sub-agent receives this prompt:
   ```
   You are the parallel pipeline runner for <feature-slug>.
   The feature directory exists at .feature/<feature-slug>/.
   Status.md is initialized at planning/loading-context and the WD is
   marked IMPLEMENTING.

   Invoke /feature-plan "<feature-slug>" and run the full pipeline
   through to /feature-refactor. Do not pause for user confirmation;
   treat automation_mode as autonomous.

   TECHNICAL escalations (spec conflict, missing tests, test writer
   escalation) are auto-handled: record in cycle-log.md and continue
   with remaining stages where possible; mention in your summary.

   USER-REQUIRED escalations (design ambiguity, missing context the
   kit can't supply, irreconcilable spec conflict, impossible
   requirement) halt the WD. Follow the user-required escalation
   contract from /work-start:
     1. write .feature/<feature-slug>/escalation.json with the schema
        in /work-start's "User-required escalation contract" section
     2. append a `user-escalation — <category>: <question>` entry to
        cycle-log.md
     3. set status.md substage to `awaiting-user-input`
     4. return ESCALATION_AT_<stage> per below

   Return a single summary line of one of these forms:
     "<feature-slug>: COMPLETE — <detail>"
     "<feature-slug>: ESCALATION_AT_<stage> — <category>: <question>"
     "<feature-slug>: STOPPED_AT_<stage> — <detail>"
     "<feature-slug>: ERROR — <detail>"
   ```

6. **Aggregate results — classify each return.** Use the same
   five-way classification as Sequential mode Step 3f (escalation /
   clean / payload-lost / user-stopped / parse-failed). **Match
   `ESCALATION_AT_` before `STOPPED_AT_`** since both share the
   `<STATUS>_AT_<stage>` shape. For each sub-agent's return:
   - Escalation (`ESCALATION_AT_<stage> — <category>: <question>`):
     `bash .claude/scripts/work-dispatch.sh fail "<group>" "<wd-id>" "escalation:<category>"`
     (use `fail` not `ack` — WD is paused awaiting user input)
   - Clean: `bash .claude/scripts/work-dispatch.sh ack "<group>" "<wd-id>" "<line>"`
   - Payload lost: `bash .claude/scripts/work-dispatch.sh fail "<group>" "<wd-id>" "payload-lost"`
   - User stopped: `bash .claude/scripts/work-dispatch.sh fail "<group>" "<wd-id>" "user-stopped"`
   - Parse failed: `bash .claude/scripts/work-dispatch.sh fail "<group>" "<wd-id>" "parse-failed: <first 80 chars>"`

   Then summarize:
   ```
   ── Parallel run complete · <group-slug> ───────
   Dispatched: <N>
   Complete: <n>/<N>
   Escalations awaiting user input: <n>
     WD-<nn> (<category>) — "<question>"
          .feature/<group>--WD-<nn>/escalation.json
   Stopped mid-pipeline: <list with stage>
   Errored: <list with detail>
   Dispatch failures (payload-lost / user-stopped / parse-failed):
     <list with WD-id and reason>
   ───────────────────────────────────────────────
   ```
   For escalations, the user's next action is to open the listed
   escalation.json file(s), resolve the design point (edit the spec,
   add an ADR, supply context), then re-dispatch via
   `/work-resume "<group-slug>"`. For stopped or errored WDs, the
   user's next action is usually `/feature-resume "<feature-slug>"`.
   For dispatch failures, the next action is
   `/work-resume "<group-slug>"` — it scans the dispatch markers and
   surfaces each stuck WD with the right recovery path (re-dispatch,
   inspect, or accept the partial result).

### Concurrency caveats (documented, user-accepted)

- **Shared KB / ADR writes.** If two WDs' `/feature-retro` phases both
  want to write a new `adversarial-finding` KB entry about the same
  pattern, both writes succeed but one silently clobbers. Mitigation:
  run `/curate` after a parallel batch; it detects duplicate KB
  entries in the cross-reference analysis.
- **Shared spec writes.** If two WDs produce specs in overlapping
  domains, both `/spec-write` calls may serialize through the same
  manifest file. The manifest update uses atomic `jq` + tmp + mv, so
  the *last writer wins* on the manifest — but individual spec files
  are per-WD and don't conflict.
- **Test runner contention.** Parallel test suites can race on shared
  resources (test DB, network ports, temp files). This is a
  project-level concern. If the project's tests are isolated per WD,
  parallel is safe; if not, either cap at 1 or don't use parallel.
- **Token / cost budget.** N parallel pipelines burn roughly N× the
  tokens and dollars of a single run. Budget accordingly.

---

## User-required escalation contract

Two kinds of escalation happen during autonomous pipeline runs. They
need to be distinguished — only one of them halts the WD.

**Stage escalation** (existing, auto-continued): a pipeline stage hits
a technical conflict it can handle within the pipeline — test writer
can't write a failing test, refactor stage finds a spec conflict, etc.
The kit's existing rules say: record in `cycle-log.md` and continue
with remaining stages. The WD finishes (possibly with `STOPPED_AT_`)
and the user sees the escalation in the post-run summary.

**User-required escalation** (this contract): the sub-agent cannot
proceed without user input. Common categories:

| Category | When |
|----------|------|
| `design-choice` | Spec/ADR is ambiguous; multiple valid implementations. The sub-agent can identify them but cannot pick. |
| `missing-context` | A referenced concept (symbol, decision, KB entry) doesn't resolve. The sub-agent searched and found nothing. |
| `spec-conflict` | Two specs contradict each other on a point the current stage needs to honor. Cannot be reconciled in-pipeline. |
| `impossible` | A requirement physically can't be satisfied (e.g., contradicts an external fact). Needs scope/spec revision. |
| `other` | Escape hatch — use the `question` field to explain. |

The sub-agent halts the WD and surfaces the question via a structured
artifact. The parent (this skill, today; the orchestrator in a future
PR) routes the question to the user.

### Sub-agent obligations on user-required escalation

When a sub-agent in `automation_mode: autonomous` encounters a
user-required situation:

1. **Write `.feature/<slug>/escalation.json`** with this schema (JSON,
   atomic write via tmp + rename):

   ```json
   {
     "schema_version": 1,
     "feature_slug": "<group>--<wd>",
     "wd_id": "WD-nn",
     "group_slug": "<group-slug>",
     "raised_at": "<ISO-8601 UTC>",
     "blocking_stage": "feature-plan|feature-test|feature-implement|feature-refactor",
     "category": "design-choice|missing-context|spec-conflict|impossible|other",
     "question": "<one-line summary, suitable for AskUserQuestion prompt>",
     "context": "<longer explanation; may include rationale + what was tried>",
     "context_refs": ["<file:line>", "<spec-id.RN>", "<.decisions/slug>"],
     "options": [
       { "label": "<short>", "description": "<what choosing this means>" }
     ]
   }
   ```

   `context_refs` and `options` are optional. If the sub-agent has no
   candidate answers, omit `options` — the user will provide one.

2. **Record a `user-escalation` entry in `cycle-log.md`**:
   ```
   - <ISO-8601 UTC> user-escalation — <category>: <question>
   ```
   This complements escalation.json (which is the structured form) and
   keeps cycle-log as the single audit timeline.

3. **Update `status.md` substage** to `awaiting-user-input` so
   `/work-resume` and `/feature-resume` recognize the halted state.

4. **Return one line** of the form:
   ```
   <feature-slug>: ESCALATION_AT_<stage> — <category>: <question>
   ```
   The leading sentinel `ESCALATION_AT_` is what the parent classifier
   matches. The `<category>: <question>` tail is for the human-readable
   summary.

### Parent classifier (5-way + dispatch-failure modes)

Extend the sequential and parallel mode classifiers from 4 to 5
recognized clean-return shapes. Order matters — match
`ESCALATION_AT_` before `STOPPED_AT_` since both share the
`<feature>: <STATUS>_AT_<stage>` shape.

| Status pattern | Classification | Marker call |
|----------------|----------------|-------------|
| `: COMPLETE — ` | clean | `ack <line>` |
| `: ESCALATION_AT_<stage> — ` | **escalation (new)** | `fail "escalation:<category>"` |
| `: STOPPED_AT_<stage> — ` | stopped mid-pipeline | `ack <line>` |
| `: SKIPPED — ` | skipped (claim conflict) | `ack <line>` |
| `: ERROR — ` | errored | `ack <line>` |

The dispatch-failure modes (`payload-lost`, `user-stopped`,
`parse-failed`) remain unchanged. Use `fail` with reason
`escalation:<category>` rather than `ack` for escalations because the
WD did NOT complete — it is paused awaiting input. A future orchestrator
will re-dispatch the WD after the user resolves the question.

### Parent summary — escalations are surfaced distinctly

Both sequential `all` and `--parallel` modes extend the post-run
summary with an "Escalations awaiting user input" block:

```
── Parallel run complete · <group-slug> ───────
Dispatched: 5
Complete: 2/5
Escalations awaiting user input: 1
  WD-04 (design-choice) — "Use sealed permit or interface for codec?"
       .feature/<group>--WD-04/escalation.json
Stopped mid-pipeline: WD-07 (testing)
Errored: 1 (WD-02)
Dispatch failures: 0
───────────────────────────────────────────────
Next: open the escalation.json file(s) to read context, then re-dispatch
the resolved WD with /work-resume "<group-slug>".
```

Until the future orchestrator (PR B/C) lands, the user opens
escalation.json manually, resolves the design point (edits the spec,
adds an ADR, updates context), then re-dispatches via `/work-resume`.

---

## Notes

- The double-dash convention (`<group>--<wd>`) in the feature slug allows
  feature-resume, feature-retro, and feature-complete to auto-detect work
  group association without needing to read status.md.
- The brief.md includes work group context so domain analysis and planning
  have visibility into the broader initiative.
- Status.md starts at planning/loading-context because specifications
  should already exist from a prior `/work-plan` run or manual authoring.
- Parallel mode (`--parallel`) is an advanced flow — see the "Parallel
  mode" section above for when it applies and the concurrency caveats.
