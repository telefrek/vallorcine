---
description: "Run adversarial audit pipeline against shipped code"
argument-hint: "<entry-point>"
---

# /audit "<entry-point>"

Runs the adversarial audit pipeline. Accepts any entry point: feature slug,
file list, spec reference, or prior audit report path. Finds bugs, proves
them with failing tests, fixes the code, and leaves the codebase clean.

---

## Orchestrator discipline — MANDATORY

You are a state machine. Your ONLY job is to dispatch subagents serially
and relay their one-line summaries. You use TodoWrite to show progress.

**What you may do:**
- Check file existence (does audit-report.md exist? yes/no)
- Read one-line return summaries from subagents
- Parse counts from return summaries (cluster count, finding count,
  lens count)
- Display progress via TodoWrite
- Decide which subagent comes next based on return summaries
- Run mechanical pipeline scripts (reconcile-cards.py, extract-views.py)
  — these are data transformations, not analytical work

**What you must NEVER do — these are HARD RULES, not suggestions:**
- DO NOT read any pipeline output file (scope-definition.md,
  cluster-*-packet.md, suspect-*.md, prove-fix-*.md,
  audit-report.md, exploration-decisions.jsonl, construct-cards.yaml,
  analysis-cards.yaml, lens-*-cards.yaml, active-lenses.md)
- DO NOT read source code files
- DO NOT run build/test commands (./gradlew, npm test, cargo test, etc.)
- DO NOT run git commands (git diff, git log, etc.)
- DO NOT parse XML test results, grep test output, or count test files
- DO NOT write any pipeline output file
- DO NOT make analytical decisions about scope, bugs, tests, or fixes
- DO NOT do the work of ANY subagent yourself, even if it seems simple

**How to detect a violation:** If you are about to use Bash, Read, Write,
Edit, or Grep for anything other than checking file existence or reading
a return summary, STOP. That work belongs in a subagent.

**Why:** Every tool call result accumulates in your context window. You
exist for the entire pipeline. A single file read adds ~500 tokens that
you carry through every subsequent turn. Subagents absorb work in
isolated context windows that are discarded after they return.

---

## Pipeline overview

Five jobs, executed serially. All subagents run one at a time.
Mechanical scripts run between subagent phases (no LLM cost).

```
Scope:      Classification → Exploration → Card Construction
            (interactive)    (discovery)    (assertion sweeps)
                                  ↓
            [reconcile-cards.py] → [extract-views.py detect]
                                  ↓
            Domain Pruning → [extract-views.py project] → Assembly
            (lens challenge)                               (domain-lens clustering)
                                  ↓
Suspect:    Lens1/C1 → Lens1/C2 → ... → Lens2/C1 → ... → LensK/CN
                                  ↓
Prove-Fix:  Finding 1 → Finding 2 → ... → Finding M
            (sequential — each finding: write test → confirm/impossible → fix)
                                  ↓
Report:     Single subagent → audit-report.md + audit-prior.md
            (includes cross-domain finding combination)
                                  ↓
Reconcile:  Single subagent → spec-updates.md + kb-suggestions.md
            (optional — only when .spec/ exists)
```

---

## Determine entry point

Parse the argument to determine what kind of audit this is:

- **Feature slug** (e.g., "float16-vector-support"): look for
  `.feature/<slug>/` directory
- **File path or glob** (e.g., "src/index/*.java"): direct file audit
- **Spec reference** (e.g., "spec:F01"): audit code against spec
- **Prior report** (e.g., "audit-report.md" path): incremental audit

If the argument is ambiguous, ask the user:
```
What would you like to audit?
  1. A feature (provide the feature slug)
  2. Specific files (provide file paths or globs)
  3. Code against a spec (provide spec ID)
  4. Re-run from a prior audit report
```

Store the entry point type and value for the Classification subagent.

---

## Budget

After determining the entry point, ask the user for a budget:

```
What's your budget for this audit?

  Discovery and analysis run first (~$20-30) to identify findings.
  The prove-fix phase (testing + fixing each finding) is where most
  cost goes — roughly $5-7 per finding.

  Enter a dollar amount, or press Enter for the default ($300):
```

- If the user provides a number: store as `AUDIT_BUDGET`
- If the user presses Enter or says "default": set `AUDIT_BUDGET=300`
- If the user says "unlimited" or "no limit": leave `AUDIT_BUDGET` empty

The budget applies **only to the prove-fix phase**. Discovery, suspect
analysis, test cleanup, and reporting always run regardless of budget.

---

## Resume detection

Before starting any work, run the state management script to determine
pipeline state. This is **mechanical, not LLM judgment**.

### For new audits

After determining the entry point, locate or initialize the audit state:

```bash
# Locate the audit directory
AUDIT_DIR=$(python3 .claude/prompts/audit/audit-state.py locate <type> <value>)

# Check for existing state
python3 .claude/prompts/audit/audit-state.py resume "$AUDIT_DIR"
```

The resume command outputs one of:
- `RESUME_AT=init` — no prior runs, start fresh
- `RESUME_AT=new_run` — prior run is complete, start a new run
- `RESUME_AT=<step>` + `RUN_DIR=<path>` — interrupted run, resume at step

### When starting fresh (init or new_run)

```bash
python3 .claude/prompts/audit/audit-state.py init <type> <value>
```

This creates the run directory and state.json. Parse `INIT_RUN_DIR` from
the output — all pipeline artifacts for this run go in that directory.

### When resuming

Display to the user:
```
Resuming audit — picking up at <RESUME_AT>.
Run directory: <RUN_DIR>
```
Wait for user confirmation. Initialize TodoWrite with completed steps
already checked. Start from the resume step.

### After each step completes

Update state immediately:
```bash
python3 .claude/prompts/audit/audit-state.py complete "$AUDIT_DIR" <step> [key=value ...]
```

Include metadata when available:
- After assembly: `clusters=9 lenses=4`
- After suspect: `findings=39`
- After prove-fix: `fixed=20 impossible=10 fix_impossible=0 deferred=0`

**All pipeline artifacts go in the run directory** (`RUN_DIR`), not in
`.feature/<slug>/` directly. This keeps runs isolated — no stale files
from prior runs can confuse the pipeline.

---

## Progress tracking

Before launching the first subagent (or after resume detection),
initialize the TodoWrite checklist:

```
◻ Step 1.1: Classification
◻ Step 1.2: Exploration
◻ Step 1.3: Card Construction
◻ Step 1.4: Reconciliation + Lens Detection
◻ Step 1.5: Domain Pruning
◻ Step 1.6: View Projection
◻ Step 1.7: Assembly
◻ Job 2: Suspect
◻ Job 3: Prove-Fix
◻ Job 3b: Test Cleanup
◻ Job 4: Report
◻ Job 5: Reconciliation (if .spec/ exists)
```

Update rules:
- **Steps 1.1–1.7:** Mark each step complete immediately when it finishes.
  Do NOT mark the next step complete until it actually finishes.
- **Jobs 2–3:** Update the label with running counts as subagents return.
  Examples: "Suspect (3/8 clusters, 12 findings)", "Prove-Fix (5/12
  findings, 4 fixed, 1 impossible)". Mark complete only when all subagents
  for that job finish.
- **Job 4:** Mark complete when Report returns.
- **Job 5:** Only shown if `.spec/` exists. Mark complete when Reconciliation
  returns.

---

## Job 1: Scope

### Step 1.1 — Classification subagent

Launch a subagent. Tell it:

> You are the Classification subagent for an audit pipeline.
> Read `.claude/prompts/audit/classification.md` for your complete
> instructions.
>
> Entry point: <type> = <value>
> Working directory: <cwd>
>
> Resolve scope deterministically. Do NOT ask the user questions.
> Write your outputs and return a summary.

The subagent will:
- Resolve the entry point to initial file paths
- Detect prior audit reports and load prior work
- Gather specs, KB entries, ADRs
- Detect language and project structure
- Write classification.md with scope summary

Expected return format:
"Classification complete — <n> initial files, <n> specs resolved,
prior_round=<yes|no>, language=<lang>"

**After Classification returns, confirm scope with the user:**

Display the return summary and ask:

```
Audit scope resolved:
  <paste the Classification return summary>

Proceed? (yes / adjust scope / cancel)
```

If the user wants to adjust, note their changes and re-run Classification
with the adjusted entry point. If they cancel, stop the pipeline.

Mark **Step 1.1: Classification** complete.

### Step 1.2 — Exploration subagent

Launch a subagent. Tell it:

> You are the Exploration subagent for an audit pipeline.
> Read `.claude/prompts/audit/exploration.md` for your complete
> instructions.
>
> Read the classification output at `.feature/<slug>/classification.md`
> for your starting files, prior work summary, and context package.
>
> Write exploration-decisions.jsonl as you work — every tiering
> decision, clearing check, and frontier stop must be logged.
>
> Return a summary line when done.

Expected return format:
"Exploration complete — <n> analyze, <n> boundary, <n> ignore,
<n> domain signals, frontier=<n> stops"

Mark **Step 1.2: Exploration** complete.

### Step 1.3 — Card Construction subagent

Launch a subagent. Tell it:

> You are the Card Construction subagent for an audit pipeline.
> Read `.claude/prompts/audit/card-construction.md` for your complete
> instructions.
>
> Read the exploration output at `.feature/<slug>/exploration-graph.md`
> for the construct list, locations, and boundary contracts.
> Read the classification context at `.feature/<slug>/classification.md`.
>
> Build construct cards using assertion-first sweeps.
>
> Return a summary line when done.

Expected return format:
"Cards built — <n> constructs, <n> batches, <n> with assumptions,
<n> with empty contracts"

Mark **Step 1.3: Card Construction** complete.

### Step 1.4 — Reconciliation + View Detection (mechanical scripts)

Run the reconciliation script to add incoming edges and derive
co_mutators/co_readers:

```bash
python3 .claude/prompts/audit/reconcile-cards.py .feature/<slug>/
```

Expected output:
"Reconciled <n> cards — <n> inconsistencies, <n> with co_mutators"

Then run view extraction phase 1 to detect candidate domain lenses:

```bash
python3 .claude/prompts/audit/extract-views.py detect .feature/<slug>/
```

Expected output:
"Detected <n> candidate lenses, <n> eliminated — active: <lens names>"

Mark **Step 1.4: Reconciliation + Lens Detection** complete.

### Step 1.5 — Domain Pruning subagent

Launch a subagent. Tell it:

> You are the Domain Pruning subagent for an audit pipeline.
> Read `.claude/prompts/audit/domain-pruning.md` for your complete
> instructions.
>
> Read `.feature/<slug>/active-lenses.md` for candidate lenses.
> Read `.feature/<slug>/exploration-graph.md` for domain signal
> corroboration.
>
> Challenge each candidate lens. Update active-lenses.md with
> CONFIRMED or PRUNED status.
>
> Return a summary line when done.

Expected return format:
"Domain pruning — <n> confirmed, <n> pruned: <pruned names or 'none'>"

Mark **Step 1.5: Domain Pruning** complete.

### Step 1.6 — View Projection (mechanical script)

Run view extraction phase 2 to produce per-lens card projections:

```bash
python3 .claude/prompts/audit/extract-views.py project .feature/<slug>/
```

Expected output:
"Projected <n> lenses, <n> total card projections — <details>"

Mark **Step 1.6: View Projection** complete.

### Step 1.7 — Assembly subagent

Launch a subagent. Tell it:

> You are the Assembly subagent for an audit pipeline.
> Read `.claude/prompts/audit/assembly.md` for your complete instructions.
>
> Read the reconciled cards at `.feature/<slug>/analysis-cards.yaml`,
> the confirmed lenses at `.feature/<slug>/active-lenses.md`,
> the per-lens projections at `.feature/<slug>/lens-*-cards.yaml`,
> and the classification context at `.feature/<slug>/classification.md`.
>
> DO NOT read source code. Work only with structured data.
>
> Return a summary line when done.

Expected return format:
"Assembly complete — <n> lenses, <n> total clusters, <n> unique
constructs clustered, <n> constructs in multiple lenses, <n> excluded"

Parse the lens count and total cluster count from the return. You need
these to dispatch Suspect subagents.

Mark **Step 1.7: Assembly** complete.

---

## Job 2: Suspect

For each cluster packet (organized by lens), launch a subagent serially.
The Assembly return tells you the total cluster count across all lenses.
Cluster packets are named `cluster-<lens>-<N>-packet.md`.

For each cluster, tell the subagent:

> You are the Suspect subagent for <lens>/cluster <N>.
> Read `.claude/prompts/audit/suspect.md` for your complete instructions.
>
> Your cluster packet is at
> `.feature/<slug>/cluster-<lens>-<N>-packet.md`.
> It contains everything you need — construct cards, domain lens,
> analysis guidance, boundary contracts, specs, KB. Read source files
> directly using the file paths and line ranges from the construct cards.
>
> Your analysis is scoped to the <lens> domain. Focus your attack
> reasoning on <lens> concerns as described in the packet's domain
> guidance section.
>
> DO NOT read any file not referenced in your construct cards.
> DO NOT query specs, KB, or ADRs — they are embedded in your packet.
>
> Return a summary line when done.

Expected return format:
"Suspect <lens>/C<N> — <n> findings, <n> cleared, <n> boundary
observations, <n> card-driven"

After each subagent returns:
1. Parse finding count from return
2. Accumulate total findings across all clusters and lenses
3. Update **Job 2** label: "Suspect (<completed>/<total> clusters,
   <accumulated> findings)"

After all Suspect subagents complete, mark **Job 2: Suspect** complete.
If zero total findings, skip to Job 4 (Report).

---

## Job 3: Prove-Fix

Process findings ONE AT A TIME, sequentially. Each finding gets its own
subagent with a fresh context window. The subagent writes a test to prove
the bug, then fixes the source code if confirmed.

### Build the finding list

After Suspect completes, enumerate all findings across all suspect files.
Read the first line of each `### F-R` heading in each suspect file to
build the ordered list. **Do not read the finding details — just the IDs
and titles.**

### Lens → test class mapping

Each domain lens has ONE shared adversarial test class. Determine the
test directory from the project's build structure (e.g.,
`src/test/java/<package>/` for Java). Test class naming:

| Lens | Test class name |
|------|----------------|
| shared_state | `SharedStateAdversarialTest` |
| contract_boundaries | `ContractBoundariesAdversarialTest` |
| data_transformation | `DataTransformationAdversarialTest` |
| dispatch_routing | `DispatchRoutingAdversarialTest` |
| resource_lifecycle | `ResourceLifecycleAdversarialTest` |

Add rows for any other active lenses following the same pattern.

### Processing order

Process findings grouped by lens, then by cluster, then by sequence
number. Shorter lenses first for early signal:

1. Count findings per lens
2. Sort lenses by finding count (ascending)
3. Within each lens, process clusters in order (C1, C2, ...)
4. Within each cluster, process findings in sequence order

### Dispatch loop

For each finding, launch ONE subagent:

> Read `.claude/prompts/audit/prove-fix.md` for your full instructions,
> then execute them.
>
> Your assignment:
> - Finding: <finding ID> — "<finding title>"
> - Construct: <construct name and location>
> - Domain lens: <lens>
> - Test class: <test class path from mapping above>
> - Suspect file: `.feature/<slug>/suspect-<lens>-cluster-<N>.md`
>   (your finding only — <finding ID>)
> - Cluster packet: `.feature/<slug>/cluster-<lens>-<N>-packet.md`
> - Write output to: `.feature/<slug>/prove-fix-<short-id>.md`

For the short-id in the output filename, use the finding ID with dots
replaced by dashes (e.g., F-R5.cb.1.1 → prove-fix-F-R5-cb-1-1.md).

Wait for the subagent to return its summary line. Record the result.

Expected return format:
"<finding ID>: <CONFIRMED_AND_FIXED | IMPOSSIBLE | FIX_IMPOSSIBLE> —
<one-line summary>"

### Error handling

If a subagent fails (API error, timeout, 0 tokens returned, no output
file written):
1. **Retry once** — transient API errors (500, 529) usually resolve.
   Re-launch the same subagent with the same prompt.
2. If the retry also fails: mark the finding as DEFERRED with reason
   "subagent failure — <error description>". Do NOT stop the pipeline.
3. Continue to the next finding. Deferred findings can be retried in
   a subsequent run.
4. Report the failure: `[N/total] <finding ID>: DEFERRED (API error)`

After each subagent returns successfully:
1. Parse the result from the return summary
2. Accumulate totals (fixed, impossible, fix_impossible, deferred)
3. Report progress to the user:
   `[N/total] <finding ID>: <result> — <summary>`
4. Update **Job 3** label: "Prove-Fix (<completed>/<total>, <fixed>
   fixed, <impossible> impossible, <deferred> deferred)"

After all findings are processed, mark **Job 3: Prove-Fix** complete.
If zero confirmed findings, skip to Report.

### Budget control

If `AUDIT_BUDGET` is set (from `--budget <N>` flag):

1. After each prove-fix subagent completes, run the cost check:
   ```bash
   bash .claude/scripts/audit-budget.sh
   ```
   This returns the running session cost as a single number (e.g., `247.50`).

2. Compare the returned cost against `AUDIT_BUDGET`:
   - **>= budget:** Stop dispatching. Mark all remaining findings as DEFERRED.
     Report: `Budget reached ($X of $Y). N findings deferred.`
   - **>= 80% of budget:** Warn: `Budget 80% consumed ($X of $Y). N remaining.`
     Continue dispatching.

3. In the completion summary, include:
   `Budget: $X spent of $Y limit (N findings deferred)`

4. Budget does NOT affect Jobs 3b (test cleanup), 4 (report), or 5
   (reconciliation). Those always run regardless of budget.

When passing the budget to the prove-fix orchestrator subagent prompt, add:
```
Budget limit: $<AUDIT_BUDGET>. After each finding, run:
  bash .claude/scripts/audit-budget.sh
Stop dispatching if the result >= <AUDIT_BUDGET>.
```

If `AUDIT_BUDGET` is not set, omit the budget lines from the orchestrator
prompt entirely — the orchestrator runs unbounded.

---

## Job 3b: Test Cleanup (after prove-fix, before report)

After all prove-fix agents complete, pre-existing tests may assert old
(buggy) behavior that the fixes changed. These are not regressions — they
are tests written against the previous behavior that need updating to
match the corrected behavior.

Launch a subagent:

> You are the Test Cleanup subagent for an audit pipeline.
>
> The prove-fix stage has fixed <N> bugs. Some pre-existing tests may
> now fail because they were asserting the old (buggy) behavior.
>
> Run the full project test suite. For each failing pre-existing test
> (NOT the adversarial tests written by this audit):
>
> 1. Read the failing test method and its assertion
> 2. Read the prove-fix output that changed the behavior it tests
> 3. Check: do the failing test and the passing audit test both
>    reference the SAME spec requirement (via `covers:` comments,
>    finding IDs, or construct/method under test)?
> 4. Classify the failure into one of three categories:
>
> **STALE** — test asserts OLD (buggy) behavior the fix corrected:
>   - Update the test to assert the NEW (correct) behavior
>   - Add a comment: "// Updated by audit <finding ID>: <old behavior>
>     was a bug, now correctly <new behavior>"
>
> **SPEC AMBIGUITY** — both the failing test and the audit test are
> valid interpretations of the same spec requirement, but they expect
> opposite behavior. The spec allows both readings:
>   - Do NOT modify either test
>   - Flag: "SPEC AMBIGUITY: <test method> and audit test <method>
>     interpret <spec>.<requirement> differently.
>     Failing test expects: <behavior A>
>     Audit test expects: <behavior B>
>     The spec requirement allows both — it needs tightening."
>   - Include the spec requirement text and both interpretations
>
> **REGRESSION** — the fix genuinely broke unrelated behavior:
>   - Do NOT modify the test
>   - Flag: "REGRESSION: fix <finding ID> broke <test method> —
>     the fix may need revision"
>
> Return: "Test cleanup — <N> stale updated, <N> spec ambiguities,
> <N> regressions"

Expected return: stale test count + regression count.

If spec ambiguities found, display them and ask the user to decide:
```
<N> spec ambiguity detected — a requirement allows conflicting interpretations:

  <spec>.<requirement>: "<requirement text>"
    Test A (<method>) expects: <behavior A>
    Test B (<method>) expects: <behavior B>

  The requirement needs tightening. Which interpretation should the code follow?
    1. <behavior A> (update Test B)
    2. <behavior B> (update Test A)
    3. Defer — leave both tests, resolve in /spec-author
```

Apply the user's decision: update the losing test and add a comment
noting the decision. If deferred, note both tests as conflicting in
the audit report.

If regressions found, display them and ask the user before proceeding
to Report:
```
<N> pre-existing tests broke as regressions (not stale assertions):
  <test method> — broken by <finding ID>

These fixes may need revision. Continue to Report? (yes / review)
```

If zero failures in the full suite, skip this step entirely — no
subagent needed.

Mark **Job 3b: Test Cleanup** complete.

---

## Job 4: Report

Launch a single subagent:

> You are the Report subagent.
> Read `.claude/prompts/audit/report.md` for your complete instructions.
>
> Read all pipeline output files in `.feature/<slug>/`:
> - scope-definition.md
> - scope-exclusions.md
> - active-lenses.md
> - suspect-*-cluster-*.md (all, across all lenses)
> - prove-fix-*.md (all)
>
> Perform cross-domain finding combination for constructs that appear
> in findings from multiple domain lenses.
>
> Write audit-report.md and audit-prior.md.
>
> Return a summary block for display.

Display the Report subagent's summary as the final output:

```
── Audit complete ─────────────────────────────
  Scope: <n> constructs, <n> clusters, <n> domain lenses active
  Findings: <n> suspected, <n> fixed, <n> impossible, <n> fix_impossible
  Cross-domain compositions: <n>
  Deferred (budget): <n>
  Spec conflicts: <n> (or "none")
  Pipeline health: fix=<n>% impossible=<n>%
  Report: .feature/<slug>/audit-report.md
───────────────────────────────────────────────
```

If the report summary mentions spec conflicts, display the resolution flow:

```
── Spec conflicts detected ────────────────────
A fix from this audit contradicts an existing spec requirement.
This is a design tradeoff, not a bug — both the fix and the spec
had valid reasons. A decision is needed.

  CONFLICT-1: <description>
    Fix: <finding ID> — <what the fix changed>
    Spec: <spec>.<req> — <requirement text>
    Tradeoff: <why this is a tension>

Options for each conflict:
  1. Keep the fix, update the spec
     → I'll update the spec requirement to match the new behavior
       and check if other specs depend on the old behavior

  2. Revert the fix, keep the spec
     → I'll revert the source change and mark the finding as
       FIX_IMPOSSIBLE with the spec requirement as the reason

  3. Defer — decide later
     → I'll log the conflict as an open obligation on the spec

Which option for CONFLICT-1? (1 / 2 / 3)
```

For option 1: read the conflicting spec, update the requirement to match
the fix, and run `spec-resolve.sh` to check if any other spec's `requires`
references the changed requirement. If so, flag the downstream specs.

For option 2: revert the fix (git checkout the changed lines), update the
prove-fix output to FIX_IMPOSSIBLE, and note the spec requirement as the
architectural constraint.

For option 3: add `[UNRESOLVED]` marker to the spec requirement and add
an `open_obligations` entry. The spec becomes DRAFT if it was APPROVED.

If cross-cluster unresolved findings exist, suggest a follow-up round:

```
<n> cross-cluster findings could not be analyzed in this round.
Recommend another round with co-clustered constructs.
  Type yes for another round · or: done
```

---

## Job 5: Reconciliation (optional)

This job only runs when `.spec/` exists. Check for the directory before
launching.

```bash
# Check if .spec/ exists — mechanical check, not LLM judgment
test -d .spec/
```

If `.spec/` does not exist, skip this job. Mark it as "Reconciliation
(skipped — no specs)".

If `.spec/` exists, launch a single subagent:

> You are the Reconcile Findings subagent.
> Read `.claude/prompts/audit/reconcile-findings.md` for your complete
> instructions.
>
> Feature slug: <slug>
> Run directory: <RUN_DIR>
>
> Read all prove-fix outputs and the audit report from the run directory.
> Check .spec/ and .kb/ for existing entries.
>
> Write spec-updates.md and kb-suggestions.md to `.feature/<slug>/`.
>
> Return a summary line when done.

Expected return format:
"Reconciliation: <n> spec updates suggested, <n> KB patterns found,
spec coverage: <n>/<total> requirements exercised"

Parse the counts from the return summary. Then read the generated files
to present actionable content — not just file paths.

### 5a. Read and present spec updates

If spec updates were suggested (count > 0), read `.feature/<slug>/spec-updates.md`.
Also read `.feature/<slug>/kb-suggestions.md` if KB patterns were found.

Present BOTH menus together in a single output block so the user sees
everything at once:

```
── Feedback loop ──────────────────────────────

Spec updates (<n> suggested):

  1. <requirement text — one line, observable behavior>
  2. <requirement text>
  ...

  apply  — add all <n> requirements to their specs now
  review — show full details before deciding
  skip   — defer (resurfaces via /curate spec-code drift)

KB patterns (<n> updates + <n> new):

  1. <Update/New> <pattern name> — <one-line description>
  2. <Update/New> <pattern name> — <one-line description>
  ...

  create  — create/update all <n> KB entries now
  select  — choose which to create
  skip    — defer (patterns stay in kb-suggestions.md for later)
```

**STOP here and wait for the user to respond.** Do not proceed until the
user tells you what to do with the spec updates and KB patterns. The user
may respond to one or both menus in any order. Process each choice as it
comes.

If **apply** (specs): for each suggested requirement, read the target spec
file, append the requirement to the appropriate category section, and run
`spec-validate.sh` to verify the spec is still valid. Report what was added.

If **review** (specs): display the full requirement blocks with notes, then
re-offer apply/skip per item.

If **skip** (specs): note in the audit report that suggestions were deferred.
They will resurface when `/curate` detects spec-code drift (the code was
fixed but the spec wasn't updated).

If **create** (KB): for each pattern, invoke
`/research <topic> <category> "<subject>"` as a sub-agent with the pattern's
description and affected constructs as context.

If **select** (KB): present each pattern individually for create/skip.

If **skip** (KB): note as deferred.

### 5b. Show spec coverage

After the user has responded to both menus (or if no updates/patterns
were found), show spec coverage:

```
Spec coverage: <exercised>/<total> <spec-ID> requirements exercised
  (<N> unexercised — either well-implemented or not reached by this audit)
──────────────────────────────────────────────
```

Mark **Job 5: Reconciliation** complete.
