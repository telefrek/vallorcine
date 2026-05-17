# Central-invariant gate

**Status:** proposed → implementing (v0.22.0)
**Originating signal:** Finding 6 from 2026-05 jlsm session report —
"pipeline stages aren't gated on the central invariant." Deferred from
v0.21.0 PR #104 because no design existed.

---

## Problem

The v0.21.0 hardening pass (PR #104) added:

1. The completeness contract requires subagents to self-falsify before
   claiming COMPLETE (Verification contract §1).
2. The validator script catches subagents that wrote trigger phrases or
   skipped AC mapping.

What's still missing: **external falsification.** A subagent that
self-falsifies in good faith can still miss the central invariant — the
load-bearing claim the WD makes. Validators catch betrayal phrases, not
shallow reasoning.

The 2026-05 jlsm `R53 cross-family equivalence` case is the canonical
example: the subagent wrote a test that asserted iterator equivalence
across families. The test passed. The subagent claimed COMPLETE in good
faith. But the test was vacuously satisfied — both iteration paths
routed through the same legacy code, so identical output proved nothing
about whether the new code path was even being exercised.

No trigger phrase. AC mapping present. Validator clean. Bug shipped.

The fix is structural: **a fresh subagent, given the WD's central
claim + the diff, tries to falsify it.** Same burden-shift as
`/audit` — "find the bug or prove it doesn't exist." But scoped to one
WD's central claim, not the corpus.

---

## Goal

Before `/feature-pr` drafts a PR for a completed WD, a falsifier
subagent reviews:

- The WD's acceptance criteria
- The diff (changes since base)
- Relevant spec R-clauses (from spec-coverage.md)

The falsifier returns one of:

- **✓ Invariant holds** — with specific evidence
- **✗ Invariant fails** — with the concrete failure scenario
- **? Unclear** — with the specific obstacles to falsification

`/feature-pr` proceeds only on ✓. ✗ and ? block the PR draft and
route to the user via AskUserQuestion with the falsifier's verdict as
context.

---

## Non-goals

- **Multi-pass analysis.** `/audit` already does the heavy
  multi-pass+lens analysis. The gate is single-pass, single-WD.
- **Corpus-wide review.** The gate scopes to ONE WD's diff. The user
  can run `/audit` for cross-WD work.
- **Replacing the verification contract.** The contract still requires
  subagent self-falsification. The gate is a second, independent
  falsification — defense in depth, not replacement.
- **Free.** The gate adds ~$0.50–$2 per WD in subagent dispatch cost.
  Cheaper than `/audit`, but not free.
- **Auto-fixing.** If the gate finds ✗, it surfaces to user. It does
  not automatically dispatch a fix.

---

## Design

### Placement

`/feature-pr` is the natural home. The skill already runs gates
(Step 1a spec-coverage, Step 1b quality-bar) before drafting. The
central-invariant gate becomes **Step 1c**, after the quality-bar
gate and before Step 2 (Draft the PR).

Rationale for `/feature-pr` placement (not `/feature-coordinate`):

- Per-WD scope. `/feature-pr` runs once per WD; coordinate runs once
  per batch of work units within a WD.
- Diff is freshest. By Step 1c, all implementation + refactor commits
  are present.
- Quality-bar adjacency. Co-located with other pre-draft gates.
- Single-WD perspective. The falsifier looks at *this WD's central
  invariant*, not the work-unit-level invariants the coordinator
  manages.

### Inputs to the falsifier subagent

1. **WD reference** — the originating `.work/<group>/WD-<id>.md` (if
   the feature was launched via `/work-start`). If the feature is
   standalone (`/feature` directly), the falsifier uses
   `.feature/<slug>/brief.md` as the WD analog.
2. **Diff** — `git diff <base>..HEAD` where base is the branch this
   WD was carved from.
3. **Spec coverage map** — `.feature/<slug>/spec-coverage.md` (already
   present from Step 1a) — gives the R-clauses this WD touches.
4. **Spec bodies** — for each R-clause in the coverage map, the source
   spec markdown.
5. **The completeness contract** — `rules/completeness-contract.md`
   (always-loaded).

### Subagent prompt structure

The falsifier prompt (separate file at `prompts/feature-pr/central-invariant-falsify.md`)
contains:

```
You are the Central Invariant Falsifier for /feature-pr. Your only job
is to find reasons this WD/feature does NOT ship its central goal.

You are NOT trying to be balanced. You are trying to falsify the claim
"this branch ships the assigned scope." If the claim survives, the PR
is safer to draft.

[completeness contract preamble inserted at top]

## Inputs

- WD acceptance criteria (or feature brief): {{paste from .work or .feature}}
- Diff: {{paste of git diff base..HEAD, capped at 200K characters}}
- Spec R-clauses touched: {{from spec-coverage.md}}
- Spec bodies for touched R-clauses: {{paste}}

## Method

1. **Identify THE central invariant.** What is the ONE load-bearing
   claim this WD/feature makes? (E.g., "the v8 reader correctly parses
   all family-id-1 files", "the audit pipeline finds bugs in the
   target file", "this refactor preserves observable behavior").
   State it in one sentence.

2. **Trace the production code path.** Find the entry point a real
   caller hits to invoke the changed code. NOT the internal SPI
   adapter, NOT the unit test's direct-construction path. Read the
   live code path end-to-end.

3. **Construct the falsifier test.** Describe (in pseudocode or
   plain prose) a test that would FAIL if the central invariant
   doesn't hold but the WD's submitted tests still pass. Examples
   of falsifier shapes:
   - Vacuous equivalence: write a test that strips the new code
     path entirely and run the existing tests. Do they still pass?
   - Mocked-vs-live: replace the SPI adapter with the production
     dependency. Does the behavior change?
   - End-to-end vs unit: run the existing assertion via the public
     API instead of internal construction. Does the assertion still
     hold?

4. **Check the falsifier against the diff.** Is the falsifier test
   in the diff? If not, the WD has at least one weakness.

5. **Render verdict:**
   - ✓ HOLDS — the central invariant is supported by tests that
     route through the production path and would fail under the
     falsifier scenario. Cite specific test+file evidence.
   - ✗ FAILS — describe the concrete way the invariant fails.
     Include the failing scenario and the code/test gap that
     allows it.
   - ? UNCLEAR — describe what would need to be true to give a ✓
     or ✗ verdict, and what's currently missing (insufficient
     context, unreadable code, etc.).

## Output format

Single block at end of response:

VERDICT: <HOLDS | FAILS | UNCLEAR>
INVARIANT: <the one-sentence central invariant>
EVIDENCE: <one-paragraph evidence — test files, line refs, falsifier
           description, or specific failure scenario>
```

### Orchestrator branching

`/feature-pr` Step 1c:

```
1. Identify the WD (or feature brief) and the base branch
2. Dispatch the falsifier subagent with inputs above
3. Parse VERDICT line from return
4. On ✓ HOLDS:
   - Display the invariant + evidence one-line summary
   - Proceed to Step 2 (Draft the PR)
5. On ✗ FAILS:
   - Display verdict + evidence
   - AskUserQuestion: "Falsifier found a central-invariant failure.
                       [evidence]. How to proceed?"
     Options:
       - Stop and fix — pause the pipeline; user investigates
       - Override gate (record verdict in PR description) — proceed
         with the falsifier's verdict captured in the PR's "Notes
         for reviewer" section. Reserved for cases where the user
         disagrees with the falsifier's analysis and wants to ship.
       - Stop entirely — exit /feature-pr
6. On ? UNCLEAR:
   - Display verdict + obstacles
   - AskUserQuestion: "Falsifier could not reach a verdict because
                       [obstacles]. How to proceed?"
     Options:
       - Re-dispatch with more context — let the user specify the
         missing piece (a file path, a spec ID, a clarifying note)
         that the falsifier needs
       - Proceed anyway (record uncertainty in PR description)
       - Stop and inspect manually
```

The override paths are intentional — the user is the ultimate
authority on whether to ship. The gate's job is to surface the
question, not to block.

### Subagent contract enforcement

The falsifier's return is itself subject to the completeness
contract. After the falsifier returns, `/feature-pr` runs:

```bash
bash .claude/scripts/validate-subagent-return.sh \
    /tmp/vallorcine/falsifier-return-<slug>.txt
```

If `rc=1` (trigger phrases in the falsifier's own return), block
and route to user — the falsifier itself shouldn't be deferring.

### Cost model

Per dispatch:
- ~5K tokens input (WD + diff snippets + R-clauses) at Sonnet rates
- ~2–5K tokens output (verdict + evidence)
- ~$0.05–$0.20 per call at Sonnet 4.6 prices

Worst case (Opus 4.7, large diff capped at 200K chars):
- ~50K tokens input + 10K output = ~$2 per call

Compared to /audit (~$13/bug found), the gate is 5–10× cheaper and
runs per-WD instead of per-corpus-audit.

### Skipping the gate

Some WDs don't have a meaningful central invariant beyond their AC
mapping — e.g., a pure refactor WD or a docs-only WD. For these,
the contract preamble + validator + spec-coverage gate are
sufficient.

`/feature-pr` Step 1c can be skipped by setting
`central_invariant_gate: skip` in `.feature/<slug>/status.md` BEFORE
running `/feature-pr`. The skill displays a prominent notice that
the gate was skipped and records the skip in the PR description's
"Notes for reviewer" section.

Skip is opt-in per feature. Default is to run the gate.

---

## Edge cases

**EC1 — Standalone feature (no .work directory).** If the feature
was launched via `/feature "<description>"` directly (not via
/work-start), there's no WD file. The falsifier uses
`.feature/<slug>/brief.md` as the source of the central invariant.

**EC2 — Empty diff.** A `/feature-pr` invocation on a feature with
no changes shouldn't run the gate. Detect via
`git diff --quiet base..HEAD` and skip.

**EC3 — Diff exceeds 200K characters.** For large diffs (rare but
possible for major refactors), the falsifier receives a summary +
the most-changed files. The truncation note appears in the
falsifier's evidence so the user knows verdict was on a sampled
diff.

**EC4 — Spec coverage map missing.** If `.feature/<slug>/spec-coverage.md`
doesn't exist (older features predating spec-coverage), the
falsifier proceeds without R-clauses. Verdict quality is lower but
still useful.

**EC5 — Falsifier dispatch fails / times out.** The gate is
advisory; if the dispatch itself errors, log the failure and
proceed to Step 2 with a note in the PR description. Do not
silently re-dispatch.

**EC6 — Falsifier's verdict is wrong.** The user is the ultimate
authority. Override paths exist for both ✗ and ?. The PR
description records what the gate said and what the user did,
which provides a trail for retrospectives.

---

## Open questions

**OQ1 — Sonnet vs Opus for the falsifier?** Sonnet 4.6 is fast and
cheap; Opus 4.7 is more rigorous. Recommendation: Sonnet for default,
Opus when the user explicitly requests deep analysis (a future
`--rigorous` flag). Need empirical data on Sonnet's false-negative
rate before locking in.

**OQ2 — Diff cap at 200K or smaller?** 200K is roughly half of
Claude's effective working window. Larger diffs sample less of the
context but are rare. Could lower to 100K to leave more room for
falsifier reasoning. Pick after first 10 real dispatches.

**OQ3 — Where does the falsifier prompt live?** Two options:
  (a) `prompts/feature-pr/central-invariant-falsify.md` — colocated
      with feature-pr skill, installed via install.sh prompts loop
  (b) `prompts/audit/central-invariant-falsify.md` — colocated with
      other adversarial prompts under audit
  Recommendation: (a) — the gate is part of /feature-pr's surface,
  and the audit/ prompts are scoped to the /audit pipeline.

**OQ4 — Should the gate also run before /feature-complete?**
`/feature-complete` is the final-archive stage. A second gate there
would catch cases where the user pushes a PR and merges without
re-running /feature-pr. But /feature-complete typically runs after
PR merge — adding a gate would be after-the-fact. Punt to v0.23 if
we see the gap.

**OQ5 — Multi-WD features.** A feature can encompass several work
units. Currently /feature-pr drafts one PR for the whole feature.
The central invariant is the *feature's* invariant, not per-WU. The
gate operates at feature scope, which is correct. But: if the work
plan has 5 WUs each with their own invariants, the falsifier might
miss WU-specific bugs. Mitigation: the WU-level verification
contract (subagent self-falsification per the rules) catches those.
The gate is the feature-level final check.

---

## Rejected alternatives

**RA1 — Run the gate inside /feature-coordinate.** Too early — the
diff isn't final until refactor finishes. /feature-pr is the
natural latest-and-greatest read.

**RA2 — Make the gate a separate /feature-falsify skill.** Adds a
manual step the user has to remember. Defense in depth requires
the gate to be automatic, not opt-in. (Skip-via-status.md is the
escape hatch.)

**RA3 — Use the same /audit pipeline for the gate.** /audit is
$13/bug and multi-pass. The gate is $1/WD and single-pass. They
serve different purposes; conflating them inflates cost and
dilutes the gate's per-WD focus.

**RA4 — Auto-fix on ✗ verdict.** Auto-fixing erodes user authority.
The user decides whether the falsifier's analysis is correct and
how to address it.

**RA5 — Skip the validator on the falsifier's return.** Subagents
can ship trigger phrases even when asked to find bugs. Running the
validator on the falsifier's return is consistent with the
contract — no exemptions.

---

## Implementation plan

**P1 — Subagent prompt** (~1 session)
- Write `prompts/feature-pr/central-invariant-falsify.md`
- Test prompt manually against a known case (the R53 equivalence
  bug if reproducible, otherwise a synthetic one)

**P2 — /feature-pr Step 1c wiring** (~1 session)
- Add Step 1c to `skills/feature-pr/SKILL.md` after Step 1b
  quality-bar gate
- Branching logic for ✓ / ✗ / ?
- Skip-via-status.md detection
- AskUserQuestion calls for ✗ and ?
- Validator pass on falsifier's own return

**P3 — Tests + install plumbing** (~0.5 session)
- `tests/test-central-invariant-gate.sh` — structural checks (Step
  1c present, prompt installed, MANIFEST entry)
- MANIFEST entry for new prompt file
- install.sh entry for new prompt file
- Run full test suite to confirm no regressions

**P4 — Docs + changelog** (~0.5 session)
- CHANGELOG entry for v0.22.0
- README mention (one line in the "what /feature-pr does" section
  if any)
- Cross-reference from `rules/completeness-contract.md` to the gate
  as an example of defense in depth

---

## Success criteria

- ✓ verdict is the common case for well-built WDs (target: ≥80% of
  /feature-pr invocations)
- ✗ verdict surfaces real bugs (false-positive rate: monitor for
  first 20 real dispatches)
- ? verdict is rare (<10% — indicates obstacles in the inputs)
- Cost stays under $2/WD at Sonnet rates
- The gate catches at least one bug the validator + spec-coverage
  miss in the first 10 dispatches (proof-of-concept threshold)
