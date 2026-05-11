---
description: "Show where a work group is and what to run next — entry point after /clear or interruption"
argument-hint: "[group-slug] [--list]"
---

# /work-resume "[group-slug]" [--list]

Tells you where a work group is and what to run next.
Use this after `/clear`, a crash, a context switch, or when picking up a
group on a different machine.

This skill is the work-layer counterpart to `/feature-resume`. It is
designed to be cheap — it reads structured state files and a cached
readiness summary instead of running the full resolver every time, so
you can call it after `/clear` without re-loading the entire group's
context into the conversation.

**Modes:**
- (no arg, or `--list`) — list every active work group with a one-line summary
- `<group-slug>` — show that group's current state and the next command

`/work-resume` differs from `/work-status`:
- `/work-status` runs the full resolver and prints the complete readiness
  table (heavy output suited to "what's the state of everything?")
- `/work-resume` reads the cached `_readiness.json` and the
  `_decompose-progress.md` checkpoint to give a thin "where am I and what
  do I run next" answer (cheap output suited to "I just cleared context")

If the cache is missing or stale, `/work-resume` runs the resolver once
to refresh it. Subsequent calls in the same session re-read the cache.

---

## Step 0 — List mode (no arg or `--list`)

If no group slug was given, or `--list` was passed:

1. Enumerate directories under `.work/` (excluding `_archive`, `_refs`).
2. For each group, read `.work/<group>/work.md` for the goal and
   `.work/<group>/_readiness.json` for the cached summary. Apply the
   same mtime freshness check as Step 3 — if the cache is missing or
   any WD-*.md / work.md is newer than the cache, run
   `bash .claude/scripts/work-resolve.sh <group> >/dev/null` to refresh.
3. **Track the refresh count.** Before the per-group loop, set
   `refreshed=0`. Increment it whenever you run the resolver for a
   group. After the loop, if `refreshed > 0` print this single
   diagnostic line BELOW the active-groups table (printing it before
   the table would require buffering output without knowing the count
   yet — printing it after lets the LLM emit the table first):
   ```
   (refreshed N stale readiness cache(s); first /work-resume after
    state mutations always pays this cost)
   ```
   This makes the cost visible — list-mode is "cheap" only when caches
   are already fresh; otherwise it pays for N resolver runs and the
   user deserves to know.
4. Display:

```
───────────────────────────────────────────────
📋 ACTIVE WORK GROUPS
───────────────────────────────────────────────
  <group-slug>      <ready>R / <blocked>B / <specifying>S / <implementing>I / <complete>C of <total>     <goal one-liner>
  <group-slug>      <ready>R / <blocked>B / <specifying>S / <implementing>I / <complete>C of <total>     <goal one-liner>
───────────────────────────────────────────────
Pick one: /work-resume "<group-slug>"
```

If no work groups exist:
```
No active work groups. Create one with:
  /work "<goal>"
```

Stop. Do not continue to other steps.

---

## Step 1 — Validate group

Check `.work/<group-slug>/` exists. If not:
```
Work group '<group-slug>' not found.

Available groups:
```
List directories under `.work/` (one per line). Stop.

Read `.work/<group-slug>/work.md` for the goal description.

Display opening header:
```
───────────────────────────────────────────────
🔄 WORK RESUME · <group-slug>
───────────────────────────────────────────────
Goal: <goal from work.md>
```

---

## Step 2 — Detect in-flight decompose checkpoint

Check `.work/<group-slug>/_decompose-progress.md`. If it exists, read
its frontmatter `phase:` field and `phase_a_complete_at:` timestamp.

### Step 2a — Detect orphan checkpoints

A "checkpoint exists" signal isn't always meaningful. Three cases need
distinct handling:

1. **Genuinely in-flight** — the decomposition needs resuming.

2. **Orphan (deletion at end of Phase C didn't run)** — kit bug, manual
   ctrl-C between manifest write and checkpoint clear, or external
   interruption. The decomposition is complete on disk but the
   checkpoint was never cleared.

3. **Stale-by-age** — a checkpoint that's been sitting for over a week.
   Even if the group hasn't moved past DRAFT, the user has clearly
   abandoned this attempt; offer recovery.

**Detection rule**: classify the checkpoint as an orphan if EITHER:

- (a) **At least one WD has progressed past DRAFT.** Use `find ... -exec`
  rather than piping to `xargs` — `xargs` without `-r` hangs on macOS
  when the input is empty:
  ```bash
  find ".work/<group-slug>" -maxdepth 1 -name 'WD-*.md' \
       -exec grep -lE '^status: (SPECIFYING|SPECIFIED|IMPLEMENTING|COMPLETE)$' {} + \
       2>/dev/null | head -1
  ```
  If the command prints any path, treat as orphan. Phase C must have run
  (it's what writes WD-NN.md files) for any WD to exist past DRAFT; the
  checkpoint is therefore an orphan that survived a missed cleanup.
- (b) `phase_a_complete_at` from the checkpoint frontmatter is more than
  7 days old — stale-by-age.

WD-count matching (the original heuristic) was fragile because users can
add or remove WDs by hand, and Phase A's "tentative" list isn't a
reliable count baseline. "Any WD past DRAFT" is a much stronger signal
because no manual workflow takes a WD past DRAFT without `/work-plan` or
`/work-start` having run, both of which presuppose that decomposition
is complete.

For an **orphan**:
```
⚠ /work-decompose checkpoint found, but the group looks fully decomposed
  (<N> WDs in manifest, checkpoint last updated <date>).

  This is most likely an orphan from a prior session that ended
  between writing the WDs and clearing the checkpoint.
```
Use AskUserQuestion with options:
  - "Delete the orphan and continue" (Recommended)
  - "Treat as in-flight and resume /work-decompose"
  - "Stop"

If "Delete and continue": `rm .work/<group-slug>/_decompose-progress.md`
and continue to Step 3 readiness routing.
If "Treat as in-flight": fall through to the in-flight surface below.
If "Stop": exit.

For a genuinely **in-flight** checkpoint:

```
⚠ /work-decompose was interrupted in Phase <A|B>.
  Checkpoint:    .work/<group-slug>/_decompose-progress.md
  Last updated:  <timestamp from frontmatter>

To resume:
  /work-decompose "<group-slug>"
  → the skill will detect the checkpoint, summarize Phase A's seam
    analysis, and continue from where it left off.
```

Stop. Do not continue to readiness routing — finishing decomposition is
the prerequisite, and showing READY/BLOCKED tables before WDs are
finalized is misleading.

---

## Step 2c — Detect orchestrator state

If `.work/<group-slug>/.orchestrator/` exists, the `/work-run` orchestrator
(when present) was running a dynamic-DAG dispatch over this group and
either finished, was paused for escalation, or crashed.

The orchestrator's persistent state is independent of any
`/work-decompose` checkpoint and lives in its own directory tree —
state.json + queue.txt + in-flight/ + completed/ + blocked/.

Display its current state before routing the user to readiness:

```bash
bash .claude/scripts/work-orchestrator.sh status "<group-slug>"
```

Interpret the output:

- **Paused: YES** — the orchestrator halted on a user-required escalation.
  Read each `blocked/<wd>.json` to find the escalation_path and show the
  user the underlying question. The user should resolve the design
  point (edit specs/ADRs/context as needed), then either:
  - Run `work-orchestrator.sh unblock <group> <wd-id>` + `resume <group>`
    to re-queue the blocked WD, OR
  - Re-invoke `/work-run` (when it lands in PR C) — the skill detects
    the orchestrator state and resumes from where it stopped.

- **In-flight > 0** — a previous orchestrator session crashed or its
  parent exited mid-run. Run
  `work-orchestrator.sh hung "<group-slug>" --threshold-seconds 1800`
  to find WDs whose `.feature/<slug>/status.md` hasn't been touched
  for 30+ minutes; those are recoverable via `/feature-resume <slug>`
  or by clearing the in-flight record and re-queueing.

- **All sets empty / completed = total** — the orchestrator finished;
  the state directory can be cleared at the user's discretion with
  `work-orchestrator.sh clear <group-slug>`.

This is detection + diagnosis only. The actionable routing UX
(AskUserQuestion-driven escalation handling, automatic re-dispatch)
lives in `/work-run` itself; here we just inform the user that the
orchestrator state exists so they're not surprised by a stale queue
or unresolved escalation.

---

## Step 3 — Refresh readiness cache (if needed)

Decide whether the cache is fresh with this single check (mtime-based,
no JSON parsing needed):

```bash
CACHE=".work/<group-slug>/_readiness.json"
if [[ ! -f "$CACHE" ]] || \
   find ".work/<group-slug>" -maxdepth 1 \
        \( -name 'WD-*.md' -o -name 'work.md' \) \
        -newer "$CACHE" -print -quit | grep -q .; then
  bash .claude/scripts/work-resolve.sh "<group-slug>" >/dev/null
fi
```

The `find ... -newer` test prints any WD or work.md whose mtime exceeds
the cache's mtime; piping to `grep -q .` short-circuits on the first
hit. When the cache is fresh, `find` finds nothing and we skip the
resolver entirely — that's the cheap-path that makes `/work-resume`
worth invoking after a `/clear`.

After the conditional refresh, read `.work/<group-slug>/_readiness.json`
to render the rest of this skill's output.

**If JSON parse fails AFTER a fresh resolver run**, this is a real
defect — either `work-resolve.sh` is broken or the cache file was
clobbered. Do NOT silently fall back to parsing the markdown report.
Surface the error explicitly:

```
ERROR: Could not parse .work/<group-slug>/_readiness.json after a
       fresh resolver run. The cache may be corrupt.

       Diagnostics:
         <one-line python json.load error>

       Recovery:
         rm .work/<group-slug>/_readiness.json
         bash .claude/scripts/work-resolve.sh "<group-slug>"
       (and file an issue if it recurs.)
```

Stop after surfacing. A silent fallback would mask the underlying bug
and let downstream skills consume stale or wrong state.

---

## Step 4 — Display compact status

From the parsed JSON `summary` and `wds` array, render:

```
SUMMARY
  <total> WDs · <ready> ready · <blocked> blocked · <specifying> specifying · <specified> specified · <implementing> implementing · <complete> complete

ACTIVE
  <only show WDs whose status is SPECIFYING, IMPLEMENTING, or BLOCKED>
  WD-<nn>  <title>                  <STATUS>   <one-line context — for BLOCKED, the first blocker; for SPECIFYING/IMPLEMENTING, " feature: <slug>">
  ...

NEXT UP (if any READY or SPECIFIED WDs)
  <first 3 READY or SPECIFIED WDs by deps_count ascending, unblocks descending>
  WD-<nn>  <title>                  <READY|SPECIFIED>
```

Skip any section with no rows. If every WD is COMPLETE, replace ACTIVE
and NEXT UP with:
```
✓ All work definitions complete.
```

Do NOT print the full status table — that's `/work-status`'s job. The
goal here is to keep this skill's output under ~30 lines so it can be
re-invoked cheaply after `/clear`.

---

## Step 5 — Determine the next command

Apply this routing in order — first match wins:

0. **Any unacknowledged dispatch marker exists** → a previous
   `/work-start` (sequential `all` or `--parallel`) dispatched a
   sub-agent whose result was never confirmed by the coordinator.
   Two known causes:
   - The Agent tool returned `[Tool result missing due to internal error]`
     (payload-lost), or
   - The user pressed ESC and the dispatch returned `The user doesn't
     want to proceed with this tool use. The tool use was rejected.`
     (user-stopped).

   In either case the WD's manifest status and `.feature/` dir do not
   tell the full story — the coordinator's task list says
   `in_progress` but no result was ever recorded. The dispatch marker
   is the durable record.

   Run:
   ```bash
   bash .claude/scripts/work-dispatch.sh stuck "<group-slug>"
   ```
   One line per unacknowledged marker:
   `<wd-id>|<dispatched_at>|<has_result>|<failure_reason>`. If the
   list is empty, fall through to rule 1.

   For each stuck marker, gather filesystem evidence:
   - Does `.feature/<group-slug>--<wd-slug>/` exist?
   - Is the WD's frontmatter status `IMPLEMENTING` (work-claim ran)
     or still `SPECIFIED` (sub-agent never claimed)?
   - Does `.feature/<...>/cycle-log.md` exist with content (sub-agent
     ran TDD cycles)?

   Display:
   ```
   ⚠ STUCK DISPATCHES detected in <group-slug>:

     WD-<nn> — dispatched <dispatched_at>
       Reason   : <failure_reason or "no result received">
       WD status: <SPECIFIED | IMPLEMENTING>
       .feature/: <present | absent>
       Cycle log: <empty | <N> cycles recorded>

       Recommendation:
         <see action selection below>
   ```

   Action selection per stuck marker:
   - **`failure_reason: user-stopped` AND WD status is SPECIFIED AND
     `.feature/` is absent** → the dispatch was cancelled before any
     work happened. Recommend re-dispatch:
     ```
     /work-start "<group-slug>" <wd-id>
     ```
   - **`failure_reason: payload-lost` (or any reason) AND WD status is
     IMPLEMENTING AND `.feature/` is present** → the sub-agent at
     least claimed the WD and started; the result was lost. Recommend
     `/feature-resume "<group-slug>--<wd-slug>"` to inspect actual
     state and continue from where the sub-agent left off.
   - **Any other shape** → surface the evidence and let the user
     decide; do not auto-route.

   After the user acts (re-dispatch, /feature-resume, or accepts the
   loss), they should clear the marker:
   ```bash
   bash .claude/scripts/work-dispatch.sh clear "<group-slug>" "<wd-id>"
   ```
   `/work-resume` SHOULD remind the user of this at the end of the
   stuck-marker block.

   Do NOT silently proceed to the rest of the routing list while
   markers are unacknowledged — recovery is the user's call, not the
   skill's.

1. **Any `_decompose-progress.md` exists** → already handled in Step 2.

2. **Group has zero WDs** (total == 0) → decomposition has not run yet.
   Suggest:
   ```
   NEXT STEP
     /work-decompose "<group-slug>"
     This group has no work definitions yet — decompose it first.
   ```

3. **Any WD is SPECIFYING with a `.feature/<group>--<wd-slug>/` dir
   present** → user has an in-flight specification feature. Suggest:
   ```
   NEXT STEP
     /feature-resume "<group>--<wd-slug>"
     <one sentence: "WD-<nn> is mid-spec — resume the specification feature">
   ```
   When more than one WD is SPECIFYING, pick the one whose
   `.feature/<group>--<wd-slug>/status.md` was modified most recently
   (active work tends to leave the freshest status mtime). Fall back to
   the WD-NN.md mtime only when no matching `.feature/` directory
   exists locally — in that case priority 5 already handled it.

4. **Any WD is IMPLEMENTING with a `.feature/<group>--<wd-slug>/` dir
   present** → user has an in-flight implementation feature. Suggest:
   ```
   NEXT STEP
     /feature-resume "<group>--<wd-slug>"
     <one sentence: "WD-<nn> is mid-implementation — resume it">
   ```

5. **Any WD is SPECIFYING/IMPLEMENTING but the matching `.feature/`
   directory does NOT exist on this machine** → the in-flight feature
   was authored on another machine or in a clobbered workspace. Surface:
   ```
   NOTE: WD-<nn> is <STATUS> but .feature/<slug>/ is not present here.
         The feature was likely authored on another machine. Check git
         to see if a feature PR exists; otherwise, treat the WD as
         needing fresh planning.
   ```
   Do not auto-route — let the user decide.

6. **Any WD is SPECIFIED** → planning is done, ready to implement.
   Suggest:
   ```
   NEXT STEP
     /work-start "<group-slug>" next
     <one sentence: "<n> WD(s) planned and ready to implement">
   ```

7. **Any WD is READY** → planning is the next step. Suggest:
   ```
   NEXT STEP
     /work-plan "<group-slug>" next
     <one sentence: "<n> WD(s) ready to plan">
   ```

8. **All remaining WDs are BLOCKED** → list the unique unblock actions
   (from `wds[*].blockers`). Group by blocker type:
   ```
   NEXT STEP — unblock to proceed
     /spec-author "<id>" "<title>"   — for <list of WDs blocked on it>
     /architect "<problem>"          — for <list of WDs blocked on it>
     /research "<subject>"           — for <list of WDs blocked on it>
   ```

9. **All WDs are COMPLETE** → display:
   ```
   NEXT STEP
     This group is finished. Run /feature-retro on individual features
     if you haven't already, or /work "<goal>" to start a new group.
   ```

Stop after displaying the NEXT STEP block. Do not auto-invoke — the
caller may want to switch groups or take a different path.

---

## Implementation notes

- **No subagent dispatch.** This skill is intentionally lightweight. It
  reads files and renders text. Heavy lifting is delegated to
  `/work-status`, `/work-plan`, `/work-start`, and `/feature-resume`.
- **JSON-first.** Always prefer `_readiness.json` over re-running the
  resolver. The cache is regenerated whenever any WD frontmatter
  changes, so staleness is bounded by file mtime.
- **Idempotent.** Running `/work-resume` twice in a row reads the cache
  twice with no side effects.
- **Survives `/clear`.** All state lives in files. The skill needs no
  conversation context to operate.
