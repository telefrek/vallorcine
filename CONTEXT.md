# vallorcine — Session Context

Handoff document for continuing work across fresh conversations.
Read DESIGN.md first for system architecture. This file covers the *active*
state of the project — what's happening now and what's next.

**Related files (pull-model — read only when needed):**
- `SETTLED.md` — stable design history, graduated decisions
- `COMPETITIVE.md` — market positioning and ecosystem gaps
- `DEFERRED.md` — good-but-not-now ideas; promote to Open questions when ready

**Section update cadences:**
- `Current focus` — replaced every session
- `Recent decisions` — rolling window, ~last 3 sessions; oldest graduate to SETTLED.md
- `Open questions` — live list; items resolve into SETTLED.md or get dropped
- `Deferred ideas` — pointer only; content lives in DEFERRED.md
- `Working preferences` — stable, shapes how we work together

---

## Current focus

*Last updated: 2026-05-05*

**Three patch releases shipped 2026-05-04 → 2026-05-05, all driven by
jlsm-surfaced kit defects: v0.16.4, v0.16.5, v0.16.6. The session also
made `@spec` annotation enforcement a structural exit precondition
across the writer pipeline (no longer advisory). One follow-up is
parked in `WIP.md` and queued as "Do next" below: PR B (spec-backfill
+ /curate annotation-drift analysis) for cleaning up existing
uncovered code in mature projects.**

### What shipped 2026-05-04 → 2026-05-05

**v0.16.4 (PR #65) — `/curate` persistence + threshold cumulation.**
User-reported on jlsm: "/curate found 0 actionable items" after the
user had skipped multiple findings on a prior run. Three coupled
defects:
- Step 5's curation-state.md template was a full-file replacement,
  wiping every prior `deferred`/`suggested` row each run.
- Pre-flight read deferred items but no step re-presented them in the
  pick list.
- Pressure / gravity / drift thresholds ran against `LAST_SHA..HEAD`
  only, so signals diluted below thresholds on frequent-cadence runs.

Fix: new `scripts/curate-review-log.sh` (append-only review log with
`migrate / append / unresolved / report` subcommands), full-window
analysis in `curate-scan.sh` with `new since last scan` / `ongoing`
tagging, new Step 2.5 in the SKILL that merges previously-deferred
items into the pick list, structured key taxonomy (16 prefixes:
`adr-pressure:`, `kb-stale:`, `link-rot:`, etc.). 11/11 new tests +
61/61 existing curate-scan green.

**v0.16.5 — bundled spec-resolve perf + `@spec` annotation enforcement.**

- **PR #66 — `spec-resolve.sh` budget + Step 7b/7c perf.** Default
  budget bumped 8000 → 25000 (real specs run 9-12K tokens each — prior
  default produced empty bundles). Step 7b conflict scan and Step 7c
  displacement scan rewritten as single awk passes — 30+ second hangs
  on multi-spec bundles eliminated. Output line format byte-identical;
  `Force-included` header line guarantees the bundle is never empty
  when there are direct candidates. 4/4 new + 21/21 existing tests.
- **PR #67 — forward enforcement of `@spec` annotation coverage.**
  Adversarial workflow audit found exactly one place in the kit
  explicitly told writers to add `@spec` annotations (`/spec-verify`
  Step 1.2), and it was gated behind a `spec-bundle.md` artifact no
  upstream skill ever wrote. Every entry point converged on the same
  broken handoff. Closed by:
  - New always-loaded `rules/spec-annotation-protocol.md` defining
    format, comment syntax per language, where/when to annotate.
  - New `scripts/spec-coverage.sh` (init / update / gate / waive /
    report) backed by `.feature/<slug>/spec-coverage.md`. Also
    produces `spec-bundle.md`.
  - Mandatory exit checks at `/feature-test` and `/feature-implement`.
  - Hard gate at `/feature-pr` with annotate / waive / override paths.
  - `/feature-quick` spec-aware mode.
  - `/audit` reconcile writes `@spec` to fix code as it mints new
    R-ids.
  - `/feature-retro` and `/feature-complete` surface coverage state.
  - 14/14 new spec-coverage scenario tests + 64/64 install.

**v0.16.6 (PR #68) — ADR quote handling + narrative WD-slug parse.**
- `work_check_adr_dep` had asymmetric quote handling: WD-side parser
  stripped quotes; ADR-side didn't. ADRs with `status: "accepted"`
  silently BLOCKED dependent WDs because `"accepted" != accepted`.
  Fix: post-extraction strip of single + double quotes on the ADR
  side.
- Narrative parser dropped phases for `<group>--wd-NN` slugs because
  the parent `/work-start "<group>" <N>` JSONL token had no `--wd-`
  infix in args. Fix: structured group-prefix + WD-number match in
  both `build_phase` first-pass filter and `parse_story` second-pass
  state machine. Mirrored in `parse.js` (also closed pre-existing
  parity gap by adding `/audit` to JS `COMMAND_TO_STAGE`).
- 8/8 new + 16/16 existing narrative + all `scenario-work-*` and
  `scenario-spec-*` and `scenario-curate-*` suites green.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

*7 decisions graduated to SETTLED.md (2026-04-23): spec-reorg-behavioral-domains
(executed), manifest-schema-v2, primitives-vs-applications, correctness-over-
context-cost, fix-now-not-defer, @spec-annotations-as-traceability, planning-
snapshot-WD-DRAFT-status. See SETTLED.md.*

- **Spec violations are contracts, not backlog** (2026-04-16) — spec-verify
  repairs violations inline (fix code or amend spec). Obligations created only
  on explicit user deferral, never as default path.

- **Partial implementation state needed** (2026-04-19) — current model is binary
  (APPROVED or DRAFT). Need a clean representation for "90% implemented, 10%
  explicitly deferred." Domain reorg may solve naturally (implemented parts in
  one spec, stubs in another). Still open — revisit once 2-3 jlsm WDs have
  completed so the data on real "90% done" shapes is available.

- **GSD is a real direct-lane competitor, not a shallow lookalike**
  (2026-04-21). See COMPETITIVE.md for the full head-to-head. Positioning
  emphasizes depth-of-spec-rigor (lifecycle, displacement, audit integration,
  computed readiness), not the "spec-driven" label (GSD owns that mindshare
  at 55K+ stars). Called out here because it shapes ongoing positioning work.

- **Mode-gated AskUserQuestion + subagent termination contract** (2026-04-23)
  — pipeline skills (`/feature-test`, `/feature-implement`,
  `/feature-refactor`) must never call `AskUserQuestion` in a subagent
  context: there is no human attached, and the `Agent` tool call blocks the
  coordinator until the subagent emits a final message. Every site that
  previously used "pause regardless of automation_mode" now has a
  `balanced | speed` bypass recording `escalated-<reason>` to cycle-log +
  substage, returning `ESCALATED`. Pairs with an explicit termination
  contract at `/feature-refactor`'s parallel-mode exit — the single-line
  summary *is* the return, no more tools after `status.md = complete`.
  Bundled in `chore/v0.14.3-bundle` (this PR).

- **Dual-schema manifest compatibility is permanent, not transitional**
  (2026-04-23) — v1 manifests (`{features: {FXX: ...}}`) remain valid for
  legacy projects that haven't migrated. All read-path scripts use
  `spec-lib.sh` helpers (`spec_file_for_id`, `spec_manifest_ids`,
  `spec_manifest_state`, `spec_manifest_domains_for`) that detect the
  schema at read time and adapt. Writes to v2 manifests use v2 shape; v1
  writes use v1 shape. Decision implication: we do NOT plan a forced
  migration window or auto-upgrade tool — v1 stays working indefinitely
  so projects can migrate (or not) at their own pace. Shipped as
  bundled in `chore/v0.14.3-bundle` (this PR).

- **`@spec` annotation is a structural exit precondition, not advisory**
  (2026-05-04) — `/feature-test` and `/feature-implement` substages
  refuse to advance until every loaded spec requirement has at least
  one `@spec` annotation in tests or implementation. `/feature-pr`
  hard-gates the PR draft on coverage. Override paths are surfaced
  explicitly to the user (annotate / waive with reason / override gate
  with reason recorded in PR description). The forward-enforcement
  pattern stops new gaps from accumulating; backfill (PR B) cleans up
  existing uncovered code. Shipped in PR #67 / v0.16.5.

- **Append-only state files for cross-run persistence** (2026-05-04) —
  When a SKILL.md template carries a full-file format that includes
  rolling state (e.g. /curate's old Review Log section in
  curation-state.md), Claude rewrites the full file each invocation
  and silently destroys prior rows. Fix shape: separate the rolling
  state into a dedicated append-only file managed exclusively by a
  helper script (curate-review-log.sh, spec-coverage.sh). The SKILL
  template only handles immutable scan-state. Pattern is reused by
  PR #65 (curate review log) and PR #67 (spec coverage table).

- **Threshold analyses run against the full configured window**
  (2026-05-04) — `/curate` thresholds (pressure / gravity / drift /
  staleness / hub files) operate on the configured 3-month window
  regardless of `LAST_SHA`. `LAST_SHA` is preserved as a tag — findings
  carry a Status column distinguishing `new since last scan` from
  `ongoing since prior scan`. Prior incremental-window behavior caused
  signals to dilute below thresholds on frequent-cadence runs.
  Shipped in PR #65 / v0.16.4.

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*
*Status tags: `[implemented]` = code exists, needs validation. `[designed]` = spec
exists, not yet coded. No tag = needs both design and implementation.*

### Do next

**PR B — `/spec-backfill` + `/curate` annotation-drift analysis.**
PR #67 (v0.16.5) made annotation a structural exit precondition for
NEW pipeline runs but left existing uncovered code in mature corpora
(jlsm has 75 specs / 12 domains, most authored before annotation
enforcement existed). PR B closes that gap. Designed scope:

1. **`scripts/spec-trace.sh --uncovered <spec-id>`** — extend the
   existing tool to emit a parseable list of R-ids with zero `@spec`
   references. Used as the primitive by both the new skill and the
   curate analysis.
2. **`/spec-backfill <spec-id>` skill** (~150-line SKILL.md). Walks
   uncovered requirements one at a time. For each R, runs subject-token
   grep across the codebase looking for likely enforcement points (same
   heuristic as the displacement scan in `spec-resolve.sh` Step 7c).
   Presents candidates via AskUserQuestion ("R3 about
   `TokenValidator.expiry_check` — likely sites: (a) ..., (b) ..., (c)
   Other, (d) Skip"). Applies the annotation. Writes a backfill log so
   progress survives interruption. Re-runs `spec-trace` at end to
   confirm coverage moved.
3. **`/spec-backfill --all`** — corpus-wide one-shot mode. Iterates
   every APPROVED spec, runs the per-spec flow. The catch-up tool for
   mature jlsm-style projects.
4. **`/curate` annotation-drift analysis (#23)** — APPROVED specs
   whose requirements have <50% annotation coverage, ordered by age +
   churn of matching code. Routes to `/spec-backfill <id>`. Surfaces
   the problem at regular curation cadence so it never re-accumulates.
5. **`tests/scenario-spec-backfill.sh`** — covers per-spec walk,
   candidate suggestion, annotation application, log resumption,
   `--all` corpus iteration.

Should reuse `spec-coverage.sh` (the artifact PR #67 introduced) as the
"what's annotated and what isn't" book — keeps the user's mental model
coherent.

### Do soon (medium effort, clear designs)

- **Empirical validation of the annotation gate.** The forward
  enforcement is structural in tests, but no real `/feature` end-to-end
  run on jlsm has exercised the new gate yet. First production run will
  be the real validation. Watch for: false-positive PR blocks, format
  ambiguity in real test code, override-path UX.

- **Empirical validation of /curate full-window thresholds.** PR #65 is
  in v0.16.4. Re-run /curate on jlsm and confirm previously-deferred
  items resurface and that `new since last scan` vs `ongoing` tagging
  reads naturally in the pick list.

- **Partial implementation state model** — binary APPROVED/DRAFT
  insufficient for specs that are 90% implemented. Revisit once 2-3
  jlsm WDs have completed implementation. The new annotation coverage
  table (PR #67) gives the per-requirement grain that may inform this
  — explicit `pending` rows for not-yet-implemented requirements
  could be the partial-implementation primitive.

- **Flaky-test surfacing in `/feature-retro`** — scan cycle-log.md for
  flakiness signals (timeouts on first run + passed-on-rerun, "flaky",
  "retry" keywords) and emit a dedicated retro section. See
  `DEFERRED.md`.

- **Positioning shift (still outstanding — carries over from v0.14.3):**
  emphasize depth-of-spec-rigor axis over the "spec-driven" label
  across user-facing docs. Bundle with the next docs pass.

### Do when needed (useful but workarounds exist)

- **Large repo curation testing** — `/curate` needs testing on a repo
  with 1000+ commits, 30+ contributors.

- **spec-trace.sh sub-lettered IDs** — R39a-h pattern not matched by
  numeric-only regex. Annotations exist in code but uncounted. Fix
  when reorg drops FXX IDs.

- **#45 cosmetic `upgrade.sh` output bug** — low priority; originally
  on the v0.14.1 stack, still open.

- **Fix the older spec-layer gaps (11 identified, 2026-04-21)** — 4
  critical: feature-implement spec awareness, feature-refactor spec
  awareness, spec-write two-file invalidation, work-decompose spec
  state validation. PR #67 (annotation enforcement) likely covered or
  changed several. Re-audit before scoping.

- **Older 6 pipeline failure patterns (2026-04-21)** — one-sided
  invalidation, audit outpacing specs, assert-only guards, dead code
  wiring, spec asymmetry. Re-audit similarly — annotation enforcement
  may have neutralized some.

### Do when scale demands it (team/scale features)

- **Team KB commands** — `/kb sync`, `/kb consolidate`, `/kb status`.

- **Pipeline observability** — velocity metrics, KB utilization
  tracking.

- **Distributed work layer** — multi-party decomposition and merge
  (deferred — team-mode feature).

---

## Deferred ideas

*Kept in `DEFERRED.md` — pull-model, not loaded every session.*
*Read it when looking for future work to promote to Open questions.*

---

## Working preferences

*Stable — shapes how we work together*

**Conversational, not form-like.** Agents feel like a systematic colleague.
Prompts, questions, output read naturally.

**Explain the why, not just the what.** One sentence of context with every
question or decision.

**Agents are routers and specialists, not autonomy machines.** User stays in
the loop at every meaningful boundary. No silent chaining. No surprises.

**Token awareness is a first-class concern.** Quantitative where possible.
Not vibes-based. Always measure by API token pricing, never assume subscription.

**No ceremony without value.** Resist adding steps that always run regardless
of need. 0-signal complexity check is silent. 0-question scoping is valid.

**Prefer one clean interface over two adequate ones.** When choices came down
to two approaches, we consistently chose simpler to use even if harder to
implement: enter-to-proceed, sequential questions, pull model.
