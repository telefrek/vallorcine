# WD-sizing feedback loop

**Status:** proposed — 2026-05-12
**Originating signal:** jlsm WD-08 paused mid-pipeline; the resume-cost
observation surfaced the upstream framing: "should `/work-decompose`
know which WDs are likely to need a resume?"

---

## Problem

`/work-decompose` Phase A carves WDs by dependency seams, not by per-WD
implementation footprint. Two WDs that look like equally clean carves
can have wildly different downstream cost — one finishes in a single
sub-agent budget, another needs 2–3 resumes because its scope spans
more domains, contracts, or test surface than fits.

Today this is handled reactively:

- Sub-agent hits budget mid-pipeline → returns a stopped state.
- Parent (`/work-start all` or `/work-run`) sees the WD as IMPLEMENTING
  on the next loop and dispatches `/feature-resume` (PR #95).
- Recovery is automatic; cost is ~1–2K tokens per resume to re-establish
  context.

The reactive path works but has two failure modes:

1. **Steady-state cost.** A group where every WD averages 1.5 resumes
   pays 50% overhead in re-context tokens. Across 10 WDs that's real
   money and meaningful wall-clock.
2. **No upstream signal.** Decompose's sizing choices receive no
   feedback. A user who consistently produces too-big WDs can't tell
   from `/work-decompose`'s output that's what's happening — they only
   see it later as resume noise.

The proposal: feed observed footprint data back to `/work-decompose` so
the user sees risk hints per tentative WD *before* committing.

---

## Goal

`/work-decompose` Step 3 (present Phase A output) shows per-tentative-WD
risk hints derived from observed historical footprints. High-risk WDs
route through a split prompt before Phase B.

The user always confirms; nothing auto-splits.

---

## Non-goals

- **Auto-splitting.** The user remains in control of carving.
- **Cross-project averages.** Different projects have different style
  and scale norms (e.g., jlsm Java WDs ≠ jlsm SQL WDs ≠ a TypeScript
  project's WDs). v1 stays per-project.
- **Token-cost normalization.** Budget exhaustion is the failure mode
  we measure; absolute token counts are out of scope.
- **Replacing dependency-based carving.** Phase A's seam analysis is
  still the primary decomposition driver. Risk hints are a sizing
  overlay on top, not a replacement.

---

## Design — three phases

### Phase 1 — Footprint emission

Extend `scripts/work-finalize.sh` to write a per-WD footprint row to
`.work/_footprint-log.jsonl` (one JSON object per line, append-only)
when a WD reaches COMPLETE state. `work-finalize.sh` already runs at
the end of `/feature-refactor` (Step 6b per DESIGN.md) and has access
to both the per-feature state (`.feature/<slug>/`) and the per-group
state (`.work/<group>/`), so it's the right insertion point.

#### Footprint schema (one row per WD)

```json
{
  "schema_version": 1,
  "wd_id": "WD-08",
  "group": "online-index-rebuild",
  "feature_slug": "online-index-rebuild--WD-08",
  "finished_at": "2026-05-12T18:30:00Z",
  "final_status": "COMPLETE",

  "_inputs": {
    "domains": ["engine", "sql"],
    "produces_count": 2,
    "artifact_deps_count": 5,
    "work_units_count": 3
  },

  "_outputs": {
    "stages_run": 5,
    "stages_stopped_at": null,
    "resumes_needed": 1,
    "resume_causes": ["budget"],
    "edited_files_count": 12,
    "annotations_added": 8
  }
}
```

The split between `_inputs` (known at decompose time) and `_outputs`
(observed at finalize time) is load-bearing — Phase 2 uses `_inputs`
attributes of new tentative WDs to predict `_outputs`-side risk based
on the historical correlation.

#### Sources for each field

| Field | Source |
|-------|--------|
| `wd_id`, `group`, `feature_slug` | function args + WD frontmatter |
| `finished_at` | `date -u +%FT%TZ` at finalize time |
| `final_status` | from `.feature/<slug>/status.md` `final_status` field |
| `domains`, `produces_count`, `artifact_deps_count` | WD frontmatter (`work_fm_array`) |
| `work_units_count` | count of `## Work Unit` headers in spec, or 0 if no sub-units |
| `stages_run`, `stages_stopped_at` | parse Stage Completion table in status.md |
| `resumes_needed` | count `resume-` substage transitions in `cycle-log.md` |
| `resume_causes` | extract reason from each `resume-` cycle-log entry; classify into `budget` \| `escalation` \| `error` \| `unknown` |
| `edited_files_count` | git diff since dispatch (cached in status.md if available, else compute) |
| `annotations_added` | grep `@spec <wd-id-or-spec>` in newly-edited files |

#### Resume cause classification

A resume entry in cycle-log.md looks like:

```
- 2026-05-12T18:25:00Z resume-after-budget-exhaustion — testing stage
```

Or:

```
- 2026-05-12T18:25:00Z resume-after-escalation — user resolved design choice
```

Or simply:

```
- 2026-05-12T18:25:00Z resuming-from-checkpoint
```

The classifier reads the resume-line tail. Budget-driven resumes are
the signal worth weighting heaviest for sizing decisions (other resume
causes don't indicate scope-too-big). The schema captures the
distribution so v2 can refine the model.

#### Atomicity + concurrency

- Append-only file → use `flock` shared lock; one writer at a time.
- Truncated last-line tolerance: the JSONL reader (Phase 2) skips any
  line that doesn't `jq -e` parse.
- Schema versioning at row level so v2 can add fields without breaking
  v1 readers.

### Phase 2 — Decompose-time read + risk computation

`/work-decompose` Step 3 (present Phase A output) reads
`.work/_footprint-log.jsonl` and computes risk hints per tentative WD.

#### Cohort model

Group historical WDs by `resumes_needed` count:

- **Green cohort** — `resumes_needed == 0` AND `final_status == COMPLETE`
- **Yellow cohort** — `resumes_needed == 1`
- **Red cohort** — `resumes_needed >= 2`

For each cohort, compute the median `_inputs` vector:

```
green_median = {
  domains: 1.5,
  produces_count: 1.2,
  artifact_deps_count: 2.1,
  work_units_count: 1.8
}
```

(Numbers illustrative; real values come from observed data.)

#### Risk scoring for a tentative WD

Phase A produces tentative WDs with provisional attributes (the WD
hasn't been written yet, but its domains / interface contracts /
estimated work-units are known from the seam analysis).

Compute a Manhattan distance to each cohort median:

```
d_green  = |T.domains - G.domains| + |T.produces - G.produces| + ...
d_yellow = ...
d_red    = ...
```

Assign the tentative WD to the closest cohort. Label accordingly:

| Closest cohort | Label | Color |
|----------------|-------|-------|
| green | "single-shot expected" | 🟢 |
| yellow | "expect 1 resume" | 🟡 |
| red | "expect 2+ resumes — consider splitting" | 🔴 |

#### Graceful degradation

- **Empty log** (new project, first decompose) → skip risk hints
  entirely. Print one line: `_No historical footprint data yet — risk
  hints will appear after the first WDs complete._` Continue normally.
- **<5 footprint rows** → show risk hints with an "[N samples; low
  confidence]" suffix.
- **All historical WDs are green** (no resume data) → don't show any
  red flags; just print the green-cohort median for reference.

#### Step 3 presentation

Current Step 3 already shows tentative WDs with their domains and
unblock relationships. Extend the table with a `Risk` column:

```
Tentative work definitions (Phase A):

| WD | Title                              | Domains              | Unblocks  | Risk |
|----|------------------------------------|----------------------|-----------|------|
| 1  | Engine API entry point             | engine               | WD-11     | 🟢   |
| 2  | Cross-mode integration testing     | engine, sql, storage | (none)    | 🔴 expect 2+ resumes |
| 3  | JFR + RebuildReport observability  | observability        | (none)    | 🟢   |
```

### Phase 3 — Risk-aware AskUserQuestion routing

After the existing Step 3 AskUserQuestion (Proceed to Phase B / Defer
all / Adjust the seams), check whether any tentative WD has the 🔴 label.

If yes, surface a follow-up `AskUserQuestion`:

```
WD-2 has high resume risk (similar past WDs needed 2+ resumes).
Historical footprint:
  - Yours: 3 domains, 2 produces, 5 artifact_deps, 4 work-units
  - Red cohort median: 2 domains, 1 produces, 3 artifact_deps, 3 work-units

Three options:
  - Split WD-2 (recommended) — drops into a guided split sub-prompt
  - Proceed anyway — accept the resume cost
  - Adjust the seams manually — re-enter Step 3
```

Loop until all 🔴 WDs are resolved (split, accepted, or adjusted).

#### Split sub-prompt (Phase 3 detail)

When user picks "Split WD-2":

1. Show the WD's seams from Phase A.
2. AskUserQuestion: how to split?
   - **By domain** (default) — produce one sub-WD per `domains[]` entry
   - **By produces** — one sub-WD per `produces` artifact
   - **By work-unit** — one sub-WD per `## Work Unit` in the tentative spec
   - **Other** — user describes the split criterion in text
3. Generate sub-WD shells, re-compute risk for each, loop back to Step 3.

---

## Edge cases and what each does

### EC1: New project, no log

Skip risk hints. Surface a one-line note. Proceed normally. After
N>=5 WDs complete, risk hints start appearing.

### EC2: Small project, mostly green log

The yellow/red cohort medians may be undefined (zero samples). Compute
green-cohort-only stats and use a static threshold for red (`domains >
green_median.domains * 2`) until the yellow/red cohorts populate.

### EC3: Mixed resume causes

Budget-driven resumes are the strong signal. Escalation-driven resumes
(user-required input mid-pipeline) and error-driven resumes (tool
failure) don't indicate scope-too-big. The cohort computation weights
budget-driven resumes 1.0 and others 0.0 — a WD that needed 3
escalation-driven resumes counts as green for sizing purposes.

### EC4: Footprint write fails

Append-only design with flock protection. If a write fails (disk full,
permission), `work-finalize.sh` logs a stderr warning but doesn't fail
the WD's finalize step — the footprint is observability, not
correctness. The next finalize attempt may succeed.

### EC5: Footprint log corrupted

Phase 2's reader (`jq -e` per line) silently drops malformed lines. If
all lines fail, treat as empty log (EC1 path).

### EC6: User keeps picking "Proceed anyway" on red WDs

That's their call. The signal isn't a block, it's a hint. The footprint
log records the result either way. If the user explicitly accepted a
red WD and it shipped without resume issues, the cohort medians
gradually shift — the system self-calibrates.

### EC7: Cross-group sizing differences

A project that has both jlsm-Java WDs (long-running) and
documentation-only WDs (fast) in the same `_footprint-log.jsonl` will
have bimodal cohort distributions. v1 ignores this and uses raw medians;
v2 could segment by domain (compute green medians per-domain).

---

## Tradeoffs considered & rejected

### Rejected: per-stage dispatch instead of per-WD

We considered moving the dispatch boundary from per-WD to per-stage
(one sub-agent per `/feature-plan`, one per `/feature-test`, etc.).
This eliminates mid-pipeline budget exhaustion entirely.

Rejected because:
- ~5x dispatch overhead (each WD becomes 5 dispatches instead of 1).
- Crash semantics get harder — each stage needs its own dispatch marker.
- Bigger refactor across `/work-start`, `/work-run`, the stage skills.
- The reactive recovery path already handles the failure mode for
  ~5–10% overhead in the common case. Per-stage dispatch's overhead
  would exceed that even on green WDs.

### Rejected: token-cost-based sizing

We considered measuring absolute token consumption per WD and using
that as the sizing metric instead of resume count.

Rejected because:
- Token cost is highly variable across projects (LOC density, test
  verbosity, refactor depth).
- Resume count is a binary observable signal — either it happened or
  it didn't. Token count requires reading the sub-agent JSONL, which
  is platform-specific and may not be reliably available.
- v2 could add token-cost as a secondary signal if v1's resume-count
  cohorts prove noisy.

### Rejected: cross-project footprint sharing

We considered a kit-global `.claude/_footprint-log.jsonl` that pooled
data across all projects using vallorcine.

Rejected because:
- Project styles vary enough that pooled medians would be meaningless
  (jlsm 800-line Java specs ≠ a 50-line TypeScript spec).
- Privacy concerns — implementation footprints can hint at codebase
  structure.
- v2 could add opt-in cross-project pooling with normalization, but
  the value is unclear.

### Rejected: auto-splitting

The user always confirms via `AskUserQuestion`. Auto-splitting on red
labels would:
- Surprise the user with WDs they didn't author.
- Risk over-correction (30 trivial WDs).
- Break the existing user-deliberation contract in Phase A.

The split sub-prompt is opt-in.

### Rejected: complexity score replacing existing seam analysis

Phase A's dependency-based seam analysis is correct in concept —
carve by what produces what. Replacing it with a footprint-driven
splitter would lose the seam awareness.

Risk hints are an overlay on Phase A, not a replacement.

---

## Implementation plan — 4 PRs

### PR D1 — Footprint emission (≈1 session)

**Touches:** `scripts/work-finalize.sh`, MANIFEST, install.sh, new test.

**Adds:**
- `_emit_footprint()` function in work-finalize.sh
- `.work/_footprint-log.jsonl` (gitignored by default; user can opt to
  commit for cross-developer sharing)
- Resume-cause classification logic
- `tests/scenario-footprint-emission.sh`: fixture WD → run finalize →
  assert footprint row appended with correct schema fields

**Risk:** low. work-finalize.sh is small; the addition is append-only.

### PR D2 — Decompose-time read + cohort computation (≈2 sessions)

**Touches:** `skills/work-decompose/SKILL.md` Step 3, new helper
`scripts/work-footprint-stats.sh`.

**Adds:**
- `work-footprint-stats.sh` subcommands:
  - `cohorts <log>` — emit JSON with green/yellow/red medians
  - `risk <log> <domains>,<produces>,<deps>,<wus>` — emit risk label
    for an input vector
- SKILL.md Step 3 instructs the LLM to call `work-footprint-stats.sh`
  and weave the Risk column into the tentative WDs table
- Graceful degradation paths for empty / low-sample logs
- Test: contract validation + LIVE test with a seeded log producing
  predictable risk labels

**Risk:** medium. Cohort computation needs care; LIVE tests are key.

### PR D3 — Risk-aware AskUserQuestion routing + split sub-prompt (≈1 session)

**Touches:** `skills/work-decompose/SKILL.md` Step 3 (post-AskUserQuestion).

**Adds:**
- Follow-up AskUserQuestion when any tentative WD is 🔴
- Split sub-prompt structure (4 split criteria + Other)
- Generated sub-WD shells get their own risk computation; loop back

**Risk:** low. Pure SKILL.md text changes; routing logic is documented
not code.

### PR D4 — Calibration + docs (≈0.5 session)

**Touches:** README.md, DESIGN.md, `scripts/work-footprint-stats.sh`.

**Adds:**
- `work-footprint-stats.sh report <log>` — pretty-print the current
  cohort medians (calibration check after several WDs ship)
- README + DESIGN entries describing the feedback loop
- DEFERRED.md entry pointing at v2 ideas (token-cost, per-domain
  segmentation, cross-project pooling)

**Risk:** low. Docs + small CLI extension.

---

## Open questions

1. **`.work/_footprint-log.jsonl` — committed or gitignored?**
   Gitignored by default keeps per-developer footprint private (no
   commit churn). Committed shares data across the team (faster
   convergence of cohort medians on team projects).
   *Recommendation:* gitignored in v1; users opt in by adjusting
   `.gitignore`.

2. **Threshold for "low confidence" warning.**
   <5 samples → low confidence is a guess. Could be 3, 10, or
   bootstrap-based.
   *Recommendation:* start with 5; revisit after observing real data.

3. **Should the split sub-prompt write the sub-WDs immediately,
   or just propose them and re-enter Step 3?**
   Immediate write is faster; propose-and-re-enter lets the user
   iterate.
   *Recommendation:* propose + re-enter. Matches Phase A's "tentative,
   confirmed via user" pattern.

4. **Phase 2 helper: bash or python?**
   Cohort math + JSON parsing is awkward in bash. Python would be
   cleaner but adds a runtime dep.
   *Recommendation:* bash with `jq`. jq is already a kit dep for the
   spec layer. Cohort math is simple medians.

5. **How to handle the WD that initially scored 🔴 but the user
   accepted and it ran green?** Lower the red threshold? Trust user
   judgment more?
   *Recommendation:* trust the data. Each row contributes to medians;
   green outcomes from "accepted reds" shift the distribution
   naturally.

---

## Success criteria (how we'll know it worked)

After v1 ships and 20+ WDs accumulate footprint data:

- 🔴-labelled WDs that were split should produce sub-WDs that mostly
  land in 🟢/🟡 cohorts (target: 80%).
- 🟢-labelled WDs should rarely need resumes (target: <20% resume rate).
- 🟡-labelled WDs should resume ~1x on average.
- The user's reaction to red labels should be predominantly "split"
  (not "proceed anyway" — if it is, the threshold's wrong).

Track these via `work-footprint-stats.sh report` over time.

---

## What this is NOT

- Not a replacement for `/work-decompose`'s seam analysis.
- Not auto-splitting.
- Not cross-project averaging.
- Not a budget meter — token counts aren't measured.
- Not blocking — every recommendation is a hint with "Proceed anyway"
  available.
