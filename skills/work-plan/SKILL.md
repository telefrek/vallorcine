---
description: "Specify a work definition — produce specs and ADRs without implementation"
argument-hint: "<group-slug> [WD-nn | next | all]"
---

# /work-plan "<group-slug>" [WD-nn | next | all]

Specification-only pipeline for a work definition. Creates a feature directory,
runs domain analysis and spec authoring, then stops. No implementation stages.

Use this when:
- A WD produces specification artifacts (ADRs, specs, interface contracts)
- You want to plan and specify before implementing
- You're running parallel specification across multiple terminal sessions

For implementation after specification is complete, use `/work-start`.

**Arguments:**
- `<group-slug>` — the work group to draw from
- `WD-nn` — specify a particular work definition (e.g., WD-01)
- `next` — auto-select the highest-value READY work definition
- `all` — sequentially specify every READY WD (one subagent per WD,
  waits for each to finish before starting the next). See "Sequential
  all mode" below. **Use this for context-economy on multi-WD groups —
  the parent stays small while each subagent gets a fresh context.**

If no WD argument is provided, defaults to `next`.

**A note on `all` and arbitration prompts.** `/spec-author` Pass 2
surfaces falsification findings that require user decisions
(arbitration). In `all` mode, those `AskUserQuestion` calls surface to
you normally — the coordinator pauses while you answer, then continues.
This is a feature, not a bug: spec quality depends on you weighing in
on design intent, and the coordinator handles the rest (state, dispatch,
ordering). If you want fire-and-forget at the cost of accepting auto-
defaults, that's NOT this mode — it would require a future
`--autonomous` flag and `/spec-author` learning the same
`execution_strategy` mode-gate that test/implement/refactor already use.

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
📝 WORK PLAN · <group-slug>
───────────────────────────────────────────────
```

---

## Step 3 — Select work definition

### If `all` is the argument:

Skip the single-WD selection logic and go to the **Sequential all
mode** section below. The rest of Step 3's single-WD paths (WD-nn /
next) do not apply.

### If specific WD (e.g., WD-01):

Check if the specified WD is READY in the resolver output.

If READY: proceed to Step 4.

If BLOCKED: display the blockers from the resolver output:
```
WD-<nn> (<title>) is BLOCKED:
  - <blocker 1>
  - <blocker 2>

Unblock by resolving these dependencies first.
```
Use AskUserQuestion with options:
  - "Pick a different WD"
  - "Start anyway (skip readiness check)"
  - "Stop"

If "Pick a different WD": show READY WDs and let user choose.
If "Start anyway": proceed to Step 4 with a warning logged.

If SPECIFYING: check if a feature directory already exists for this WD:
```
WD-<nn> is already being specified.
Feature directory: .feature/<group>--<wd-slug>/

Resume with: /feature-resume "<group>--<wd-slug>"
```
Stop.

If SPECIFIED:
```
WD-<nn> is already specified. Ready for implementation:
  /work-start "<group-slug>" WD-<nn>
```
Stop.

If IMPLEMENTING or COMPLETE:
```
WD-<nn> is already past the specification phase. Nothing to do.
```
Stop.

### If "next" (or no WD specified):

From the READY WDs, select the one with the most downstream dependents
(i.e., the WD whose completion would unblock the most other WDs). This
maximizes unblocking value.

If multiple WDs tie on unblocking value, prefer the one with fewer
artifact dependencies (simpler work first).

If no WDs are READY:
```
No work definitions are READY in '<group-slug>'.

Status:
  <blocked>  blocked
  <in_progress> in progress
  <complete> complete

Unblock by resolving the artifact dependencies shown in:
  /work-status "<group-slug>"
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
  - "Plan WD-<nn>"
  - "Pick a different WD"
  - "Stop"

---

## Step 4 — Create feature directory

Generate a feature slug from the work group and WD:
```
<group-slug>--<wd-id-lowercase>
```
Example: `decisions-backlog--wd-01`

Create `.feature/<slug>/` directory.

### 4a — Generate brief.md

Read the WD file (`.work/<group-slug>/WD-<nn>.md`). Build `brief.md` from:

```markdown
# Feature Brief: <WD title>

**Source:** Work group '<group-slug>', WD-<nn>
**Generated:** <YYYY-MM-DD>
**Pipeline mode:** specification

## Description
<WD Summary section content>

## Acceptance Criteria
<WD Acceptance Criteria section content>

## Constraints
<WD Implementation Notes section content>

## Group Envelope (AUTHORITATIVE — from work group Phase B)

Group-level artifacts settled during `/work-decompose` Phase B. **These are
authoritative for WD-local analysis** — domain analysis must defer to them
rather than re-deciding. If WD-local work would contradict an envelope item,
that's an escalation back to `/work-decompose`, not a local override.

For each artifact in the WD's `artifact_deps:`, write one entry:
- **spec `<domain>/<name>`** — state: APPROVED — <title from spec frontmatter>
  <one-sentence summary of what the spec settles>
- **adr `<slug>`** — status: accepted — <title from adr.md H1>
  <one-sentence summary of the decision>
- **kb `<path>`** — <title from entry frontmatter>

Also list explicit scope declarations from `work.md`:
- **out_of_scope:** <items from work.md's out_of_scope frontmatter, if any>
- **external_deps:** <entries from work.md's external_deps frontmatter, if any>

If the WD has no artifact_deps and no group-level scope declarations, write:
"No group envelope — this WD operates standalone within the work group."

## Produced Artifacts (expected outputs)
<List each produces entry>

## Work Group Context
<Run work-context.sh --group "<group-slug>" and include relevant excerpt>
```

### 4b — Write status.md

Write `.feature/<slug>/status.md` with the standard format plus work group
metadata:

```yaml
work_group: <group-slug>
work_definition: WD-<nn>
pipeline_mode: specification
```

Set stage = `scoping`, substage = `complete`.

Stage Completion table — specification mode only:

| Stage | Status |
|-------|--------|
| Scoping | complete |
| Domains | pending |
| Spec Authoring | pending |

### 4c — Claim the WD (DRAFT → SPECIFYING)

Use `work-claim.sh` for the status transition rather than a direct
`sed`. The script does an atomic compare-and-swap under flock, so two
parallel sessions racing to plan the same WD cannot both succeed —
the second one gets a CONFLICT and bails out.

```bash
if ! bash .claude/scripts/work-claim.sh "<group-slug>" "WD-<nn>" DRAFT SPECIFYING; then
  echo ""
  echo "Another session is already planning this WD. Run:"
  echo "  /work-resume \"<group-slug>\""
  echo "to see the current state."
  exit 1
fi
```

Why claim instead of raw `sed`: the resolver run at Step 2 is a snapshot
that's stale by the time we reach Step 4c. Without CAS, two terminals
that both saw DRAFT at Step 2 will both `sed`-flip to SPECIFYING and
both proceed to author specs, racing on writes. The claim script
re-reads status under the lock and refuses if it has changed.

The manifest table is automatically synced by `work-resolve.sh` — do not
update it manually.

---

## Step 5 — Domain analysis

```
Feature directory created: .feature/<slug>/
Pipeline mode: specification (produce artifacts only)

Scoping is pre-populated from the work definition — proceeding to domain
analysis.
```
Invoke `/feature-domains "<slug>"`.

In specification mode, `/feature-domains` returns after domain analysis
without chaining into spec authoring. It produces `domains.md` which
identifies the specs to write.

---

## Step 5b — Sequential spec authoring

**Spec authoring is mandatory.** Even for decisions-focused WDs, the
architectural choices made in ADRs have behavioral implications that must
be captured as specs. ADRs describe WHY a decision was made; specs define
WHAT the system must do as a result. Without specs, the adversarial
hardening and audit pipeline have nothing to falsify. Do not skip or
bypass spec authoring for any WD type.

Read `domains.md` to identify the specs that need to be authored.

**Dedupe against the group envelope first.** Read the WD file's
`artifact_deps:` from `.work/<group-slug>/WD-<nn>.md`. For any spec in
`domains.md` whose identity matches an `artifact_deps` spec entry in
APPROVED state, do NOT author it — the group already owns that spec and
WD-local re-authoring would create divergent copies. Log the skip:

```
  ⊘ <spec-id> — deferred to group-level spec <ref> (APPROVED)
```

Authoring proceeds only for specs not already covered by the envelope.
For each remaining spec to produce, **in sequence**:

1. Invoke `/spec-author "<feature-id>" "<title>"` as a separate subagent.
   Each invocation gets a clean context but reads previously registered
   specs via the resolver — so spec 2 sees spec 1's requirements, spec 3
   sees both. This is the compounding loop: each spec's falsification
   catches contradictions with prior specs.

2. After `/spec-author` completes, verify the spec is registered and in
   APPROVED state via `.spec/registry/manifest.json`. If still DRAFT,
   falsification was incomplete — stop and report the error.

3. Proceed to the next spec.

Display progress between specs:
```
Spec authoring: <completed>/<total>
  ✓ F24 — Pool-Aware Block Size Configuration (APPROVED)
  → F25 — Byte-Budget Block Cache (authoring...)
```

If every spec in `domains.md` is covered by the envelope, Step 5b emits a
no-op log line and Step 6 proceeds to finalize the WD — this is legitimate
when Phase B settled the full spec surface for this WD.

---

## Step 6 — Verify specs and finalize WD status

After all specs are authored, verify that every spec produced by this WD
is in APPROVED state. Check `.spec/registry/manifest.json`.

**If any spec is still DRAFT:** do NOT mark the WD as SPECIFIED.
```
⚠ Spec <ID> is still in DRAFT state — falsification incomplete.
Run /spec-author "<feature-id>" "<title>" to complete adversarial review.
```
Stop and wait for the user to resolve.

**If all specs are APPROVED:** transition the WD to SPECIFIED via
`work-claim.sh` (atomic CAS — see Step 4c for the rationale):

```bash
if ! bash .claude/scripts/work-claim.sh "<group-slug>" "WD-<nn>" SPECIFYING SPECIFIED; then
  echo "WD-<nn> is no longer in SPECIFYING — refusing to mark SPECIFIED."
  echo "Run /work-resume \"<group-slug>\" to see the current state."
  exit 1
fi
```

Then refresh the manifest table and the readiness JSON cache so other
skills (and parallel sessions) see the new state without waiting for the
next `/work-status` call:

```bash
bash .claude/scripts/work-resolve.sh "<group-slug>" >/dev/null
```

The manifest table is automatically synced by `work-resolve.sh` — do not
update it manually.

Do NOT proceed to `/feature-retro` or `/feature-complete` — those run
after implementation.

Display:
```
───────────────────────────────────────────────
📝 WORK PLAN complete · <group-slug> / WD-<nn>
───────────────────────────────────────────────
Specifications produced:
  <list of spec files written or updated>

The WD is ready for implementation:
  /work-start "<group-slug>" WD-<nn>
───────────────────────────────────────────────
```

---

## Sequential all mode

When invoked with `all`, `/work-plan` runs every READY work definition
in the group **one at a time**, dispatching a separate sub-agent for
each. The coordinator (this skill, in the user's conversation) only
carries one-line summaries of completed WDs — the heavy spec-authoring
work happens in each sub-agent's isolated context.

This is the structural automation of the
`/clear` + `/work-resume` + `/work-plan WD-N` rhythm: same per-WD
context economy, same dependency-respecting selection, no `/clear` or
`/work-resume` typed by the user during the run.

### Arbitration prompts during `all`

`/spec-author` Pass 2 surfaces falsification findings that require the
user's decision (which findings to apply, which to drop, etc.). In the
sequential-all flow, each sub-agent's `AskUserQuestion` calls **surface
to the user normally** — the coordinator pauses while the user
answers, then continues. This preserves spec quality.

If you need fire-and-forget behaviour at the cost of accepting auto-
defaults for arbitration, that is NOT this mode. It would require a
future `--autonomous` flag plus `/spec-author` learning the
`execution_strategy` mode-gate that test/implement/refactor already
use. For now: `all` is "automated coordinator, manual arbitration."

### Sequential-all flow

Replace Steps 3–6 with this block when `all` is the argument.

1. **Initial enumeration.** Read `_readiness.json` (refreshed by the
   resolver call in Step 2) and collect every WD whose status is
   `READY` (DRAFT with deps met). If zero, report and stop:
   ```
   No READY work definitions in '<group-slug>' — every DRAFT WD is
   either BLOCKED on artifact dependencies or already past DRAFT.
   Run /work-status "<group-slug>" to see what to unblock.
   ```

2. **Show the plan.** Sort the READY WDs by unblocking value (most
   downstream dependents first), tie-breaking by fewer artifact
   dependencies. Display:
   ```
   ── Sequential plan ────────────────────────────
   Group: <group-slug>
   READY WDs: <N>
   Initial order (by unblocking value):
     1. WD-<nn> — <title>  (unblocks: <list>)
     2. WD-<nn> — ...
   Note 1: Pass 2 falsification arbitration during /spec-author will
   surface here — you'll be prompted for design decisions on each
   WD's findings.
   Note 2: a WD's spec authoring may unblock a sibling that's BLOCKED
   on a spec dep — the loop re-enumerates between iterations, so the
   run may include WDs not in this initial list.
   ───────────────────────────────────────────────
   ```
   Use AskUserQuestion to confirm:
     - "Plan sequentially" (Recommended)
     - "Plan first 3 only" (or another cap)
     - "Stop"

3. **Iterate until no eligible WD remains.** Loop:

   a. **Re-enumerate.** Run `bash .claude/scripts/work-resolve.sh
      "<group-slug>" >/dev/null` then re-read `_readiness.json`. Re-
      enumerating is mandatory — finishing a WD in iteration N may
      satisfy a spec dep that promotes a sibling from BLOCKED to
      READY in iteration N+1.

   b. **Pick the next.** From the current READY list, pick the WD with
      the highest unblocking value. Skip WDs the run has already
      dispatched (track in a dispatched set). If none remain, exit.

   c. **Honor the cap** if the user set one in Step 2.

   d. **Dispatch ONE sub-agent that recursively invokes the
      single-WD `/work-plan`.** Do NOT hand-roll the feature creation,
      claim, and spec-authoring sequence in this coordinator — the
      single-WD `/work-plan` flow already does it correctly, including
      the SPECIFYING → SPECIFIED transition at its Step 6. Use this
      prompt verbatim:
      ```
      You are the sequential planner for <group-slug> / <wd-id>.

      Invoke /work-plan "<group-slug>" <wd-id>. The single-WD flow
      will create the feature directory, claim the WD via
      work-claim.sh (DRAFT → SPECIFYING), run /feature-domains and
      spec authoring, and transition to SPECIFIED at Step 6 once
      every produced spec is APPROVED.

      Do NOT pre-set execution_strategy to balanced or speed for this
      run. /spec-author Pass 2 must surface its arbitration prompts
      to the user — that's the whole point of sequential `all` for
      planning. Spec quality depends on user weighing in on
      falsification findings.

      Distinguish two failure modes in your final return:

      - If the /work-plan invocation reports a `[claim] CONFLICT:`
        message from work-claim.sh (another terminal advanced the WD),
        return:
          "<group-slug>--<wd-id>: SKIPPED — claim conflict"

      - Any other failure (feature directory creation, status.md
        write error, /spec-author falsification stuck, manifest write
        failure, unexpected exception) is an ERROR — return:
          "<group-slug>--<wd-id>: ERROR — <one-line detail>"

      Successful runs return:
        "<group-slug>--<wd-id>: <COMPLETE | STOPPED_AT_<stage>> — <detail>"

      Return exactly ONE line and nothing else after.
      ```

   e. **Wait for the sub-agent to return.**

   f. **Aggregate.** Append the sub-agent's summary to results and
      display:
      ```
      [<n>/<eligible>] <group-slug>--<wd-id>: <STATUS> — <detail>
      ```

   g. **Stop conditions.** Continue unless:
      - The sub-agent returned `ERROR` or `STOPPED_AT_<stage>` AND
        the user opts to halt (AskUserQuestion).
      - SKIPPED returns are silent — log and continue.

4. **Final aggregate.** When the loop exits:
   ```
   ── Sequential plan complete · <group-slug> ────
   Dispatched: <N>
   Specified: <n>
   Stopped mid-pipeline: <list with stage>
   Errored: <list with detail>
   Skipped (claim conflict): <list>
   ───────────────────────────────────────────────

   Next steps:
     <if any specified:> /work-start "<group-slug>" all — implement them sequentially
     <if any stopped/errored:> /feature-resume "<group>--<wd-id>" — inspect each
     <if some still BLOCKED:> /work-status "<group-slug>" — see what's left
   ```

### Concurrency caveats

Same as `/work-start <group> all`:
- Another terminal claiming the same WD → CONFLICT exit, sub-agent
  returns SKIPPED, coordinator continues.
- Status drift mid-run → re-enumeration at iteration N+1 filters
  ineligible WDs before dispatch.

Additionally for `/work-plan all`:
- **`/spec-author` Pass 2 arbitration surfaces to the user.** This is
  by design (preserves spec quality). The coordinator pauses while the
  user answers each finding. Account for this when planning long runs
  — you'll be in the loop for design decisions, not fire-and-forget.

---

## Notes

- The double-dash convention (`<group>--<wd>`) in the feature slug allows
  feature-resume, feature-retro, and feature-complete to auto-detect work
  group association without needing to read status.md.
- The brief.md includes work group context so domain analysis and spec
  authoring have visibility into the broader initiative.
- Status.md starts at scoping/complete because the WD's Summary and
  Acceptance Criteria serve as the pre-approved brief.
- After specification is complete, use `/work-start` for implementation.
- Do NOT run `/feature-retro` or `/feature-complete` after `/work-plan`.
  Retro and completion happen after implementation, not after spec authoring.
