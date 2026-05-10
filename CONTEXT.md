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

*Last updated: 2026-05-10*

**Four releases + a new kit-internal skill shipped 2026-05-10:
v0.17.0–v0.18.0 + `/save-wip`. The arc: KB schema canonicalization
(v0.17.0) made structured query possible (v0.18.0); dispatch-marker
recovery (v0.17.1) closed a silent task-list-corruption bug; KB→code
citation hook (v0.17.2) plus the index above completed the
faas-rippling-inspired triangle of write-time + read-time +
drift-detection enforcement.** Session is at a natural pause point;
next is empirical validation on jlsm.

### What shipped 2026-05-10

**v0.17.0 — Canonical KB frontmatter schema (PR #77).**
`kb/_refs/frontmatter.md` is the single authoritative schema for all
entry types (research, adversarial-finding, feature-footprint,
detail-companion, reference-fragment). Realigned the existing
adversarial-finding and feature-footprint templates as schema
instances. Added `kb/_refs/detail-companion.md` formalising the
`<subject>-detail.md` split with required frontmatter on companions
(was silently optional, breaking tag-overlap scans). `/research` made
type-aware: infers `research | adversarial-finding | feature-footprint`
from the context hint, picks the right template, validates frontmatter
before write, checks cross-folder filename uniqueness. Audit feedback
hint repointed at `patterns/<concern>` (the lens) instead of
`<topic>/adversarial-findings` (folder convention that never existed).
Three new `/curate` analyses (cross-folder filename collisions, schema
drift with 12 issue codes, type/location mismatch). Regression test
21/21.

**v0.17.1 — Dispatch marker for crash-resilient sub-agent dispatch
(PR #78).** Two failure modes were silently corrupting the
`/work-start` coordinator's view of in-flight work: (1) Agent tool
returning `[Tool result missing due to internal error]` (payload
lost), (2) Agent tool returning `The user doesn't want to proceed
with this tool use. The tool use was rejected.` (user pressed ESC).
Both left the task list at `in_progress` with no signal. Fix:
`scripts/work-dispatch.sh` writes a `_dispatch-<wd-id>.json` marker
per dispatch (begin/ack/fail/stuck/clear subcommands). `/work-start`
classifies returns into four shapes (clean / payload-lost /
user-stopped / parse-failed) and routes to the right marker action.
`/work-resume` gains rule 0: any unacknowledged marker pre-empts
every other routing rule, gathers filesystem evidence (WD status,
`.feature/` presence, cycle-log content), and recommends recovery.
19/19 fixture test.

**v0.17.2 — KB→code citation hook + drift backstop (PR #79).**
`scripts/check-kb-ref.sh` is a PostToolUse hook on Write/Edit/MultiEdit
that validates `// KB: <path>` (or `# KB:`, `<!-- KB: -->`) citations:
flags rotted citations (entry was renamed/deleted), flags
`applies_to`-mismatch (likely copy-paste citation), and suggests
matching entries when no citation is present. Auto-disables when
`.kb/` has no entries beyond `_refs/` so non-KB projects aren't
nagged. `/curate` Analysis 26 closes the loop after the fact, scoped
to changed source files. Two bugs caught and fixed during self-review
(backticks in double-quoted string interpreted as command
substitution; sed `|` delimiter clashed with `|` alternation).
Inspired by faas-rippling's `check-kb-ref.sh`; vallorcine's version
adds path validation, applies_to cross-checking, suggestions,
multi-citation, three comment syntaxes, auto-disable. 18/18 test.

**v0.18.0 — JSON index + faceted search (PR #80).**
`scripts/kb-index.sh` rebuilds `.kb/_index.json` from entry
frontmatter (excludes `CLAUDE.md`, `_refs/`, `_archive*`,
detail-companion entries; tolerates inline + block YAML lists; no
PyYAML dep; atomic write). `scripts/kb-search.sh --facet
<expression>` filters the index with comma-separated `key=value`
pairs (AND-combined; scalar fields exact equality, list fields
membership). New `/kb facet` subcommand documented in SKILL.md.
`/research` Step 7.5 calls `kb-index.sh` after every KB write so
the next facet query is latency-free. Smoke-tested against jlsm's
238-entry KB: `type=adversarial-finding,domain=validation` returned
7 matches in <1s. 19/19 test. The schema canonicalization in
v0.17.0 was the prerequisite — without consistent fields the index
would have been noise.

**`/save-wip` skill (PR #81, kit-internal — not shipped).** Mid-flight
counterpart to `/save-work`: refreshes CONTEXT.md "Current focus" +
"Open questions", writes WIP.md from a structured template (where
we are, branch state, in-flight tasks, next concrete action,
pointers, risks), gathers session learnings (critical here because
the user is about to `/clear`), and closes with an explicit "Safe
to `/clear` now" line. Preserves WIP.md (whereas `/save-work`
deletes it).

### Memory + retention policy updates (2026-05-10)

- `feedback_claude_is_the_reviewer.md` updated with explicit pipeline:
  Claude reviews, runs tests, approves with `gh pr review --approve`,
  merges with `gh pr merge --squash --delete-branch --admin` (because
  GitHub blocks self-approval; user pre-authorized the bypass).
- `feedback_release_retention.md` updated to auto-enforce retention on
  every `/release` without asking — keep last 2 patches per minor,
  last 3 minor versions of current major; surface deletions in the
  closing summary, only escalate if the sandbox blocks the delete.
- Retention swept post-v0.18.0: deleted v0.17.0 (3rd patch in 0.17.x),
  v0.15.0 (outside 3-minor window), v0.14.4, v0.14.3 (older sweep).
  Tags preserved in git.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

*10 decisions graduated to SETTLED.md (7 on 2026-04-23, 3 on 2026-05-09):
spec-reorg-behavioral-domains (executed), manifest-schema-v2,
primitives-vs-applications, correctness-over-context-cost, fix-now-not-defer,
@spec-annotations-as-traceability, planning-snapshot-WD-DRAFT-status,
spec-violations-are-contracts (2026-05-09), partial-impl-via-coverage-table
(2026-05-09), GSD-direct-competitor (2026-05-09). See SETTLED.md.*

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

- **Subagent dispatch is the structural automation of `/clear`**
  (2026-05-09) — `/clear` is a Claude Code UI operation; from inside a
  running skill, an agent CANNOT issue it. The legitimate equivalent
  is dispatching a subagent: each subagent gets fresh context by
  default, parent absorbs only the return summary. The new
  `/work-{plan,start} <group> all` modes are the structural form of
  the manual `/clear + /work-resume + /work-* WD-N` rhythm. Same
  per-WD context economy, no `/clear` typed during the run. Shipped
  in PR #76 / v0.16.8.

- **Recursive single-WD-skill dispatch over custom subagent prompts**
  (2026-05-09) — early `all` mode designs had the coordinator inline
  pipeline-dispatch logic in a custom subagent prompt. Adversarial
  review caught a duplicate-pipeline-dispatch bug AND identified that
  duplicating `work-claim.sh` calls in coordinator prompts would drift
  from the canonical single-WD flow. Fix: subagent prompt just says
  "invoke /work-start <group> WD-NN" and lets the single-WD flow do
  its job. State-transition logic stays in one place. Shipped in PR
  #76 / v0.16.8.

- **`flock` must wrap compute+write, not just writes**
  (2026-05-09) — first audit pass put `flock` around the manifest +
  cache writes only. Second audit pass found a snapshot race: two
  parallel runs read state at different times, the lock serialized
  writes, but the second writer could overwrite with stale content
  while still bumping mtime — invisible to the downstream
  mtime-based freshness check. Fix: lock the entire compute phase too
  so the second runner reads state AFTER the first runner's writes
  have landed. The cost is marginal (resolver computation is fast
  even under lock); the correctness gain is large. Shipped in PR #76
  / v0.16.8.

- **CAS via `work-claim.sh`, not raw `sed`** (2026-05-09) — the
  pre-existing `/work-{plan,start}` flow used raw `sed -i` to flip WD
  status (DRAFT → SPECIFYING, etc.). Adversarial review found a real
  concurrency hole: two terminals invoking `/work-plan WD-01` between
  Step 2 (resolver read of DRAFT) and Step 4c (sed) would both
  succeed, both think they're authoring, race on writes. Fix: a small
  `work-claim.sh` script that does read-check-write under flock (CAS
  semantics) and exits 1 + CONFLICT message when expected != actual.
  Pattern is reusable for future state-mutating skills. Shipped in PR
  #76 / v0.16.8.

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*
*Status tags: `[implemented]` = code exists, needs validation. `[designed]` = spec
exists, not yet coded. No tag = needs both design and implementation.*

### Do next

**Empirical validation of the v0.17–v0.18 KB tooling on jlsm.** Four
releases shipped in rapid sequence with structural test coverage but no
real-codebase validation. After `/upgrade-vallorcine` in jlsm:

1. **`/curate --init` on jlsm.** Confirm the three v0.17.0 KB
   structural-drift analyses (filename collisions, schema drift,
   type/location mismatch) AND the v0.17.2 citation-drift analysis fire
   on jlsm's 238-entry KB. The KB review earlier in this session
   surfaced specific drift cases (cross-folder collisions on
   `partial-init-no-rollback.md` and `mutation-outside-rollback-scope.md`,
   non-canonical `research_status` values, etc.) — verify they show up.

2. **KB→code citation hook on a real edit.** Edit a Java file under
   `modules/` that doesn't yet have a `// KB:` citation. Confirm
   `check-kb-ref.sh` fires post-Write with suggestions drawn from
   entries whose `applies_to` covers the file path. Verify the
   auto-disable check stays silent when editing files outside any
   entry's scope (no nagging where no entry applies).

3. **Faceted search.** Run `/kb facet 'type=adversarial-finding,domain=validation'`
   and similar. Verify results match what jlsm's KB inventory shows.
   Check the auto-rebuild path: edit one entry's frontmatter, rerun
   the same facet query, confirm the result reflects the edit
   without an explicit `kb-index.sh` invocation.

4. **Dispatch marker recovery.** On a real `/work-start <group> all`
   run, simulate a stuck dispatch (or wait for one to occur naturally
   — they happen). Confirm `/work-resume <group>` rule 0 surfaces the
   stuck WD with the recommended recovery path (re-dispatch vs
   `/feature-resume` vs decide-yourself).

The original v0.16.8 work-layer validation queue (sequential `all`
modes, two-terminal CAS, `/clear` + `/work-resume` rhythm, etc.)
remains outstanding underneath this. Sequence: validate the new KB
stack first (this session's deliverables), then revisit the v0.16.8
queue. Token-cost and UX claims for both stacks are unproven on real
work.

### Do soon (medium effort, clear designs)

- **Empirical validation of the annotation gate.** The forward
  enforcement is structural in tests, but no real `/feature` end-to-end
  run on jlsm has exercised the new gate yet. First production run will
  be the real validation. Watch for: false-positive PR blocks, format
  ambiguity in real test code, override-path UX. (Outstanding from
  v0.16.5.)

- **Empirical validation of /curate full-window thresholds.** PR #65 is
  in v0.16.4. Re-run /curate on jlsm and confirm previously-deferred
  items resurface and that `new since last scan` vs `ongoing` tagging
  reads naturally in the pick list. (Outstanding from v0.16.4.)

- **Empirical validation of `/spec-backfill`.** Shipped in v0.16.7;
  no real corpus run yet. jlsm has 75 specs / 12 domains, most
  authored before annotation enforcement — that's the intended use
  case. Watch for: candidate-ranking false positives, log resumption
  on `--all` mode interruption.

- **`work-claim.sh` for OTHER state-mutating skills.** The CAS pattern
  is reusable. Candidates:
  - `/feature-retro` writing KB entries (currently an unguarded write)
  - `/spec-write` registry manifest update (already serialized via
    atomic jq + tmp + mv but no CAS — last-writer-wins on concurrent
    spec writes from different WDs)
  Worth scoping when a real concurrency bug surfaces, not preemptively.

- **`--autonomous` flag for `/work-plan all`.** Today the flow pauses
  for `/spec-author` Pass 2 arbitration prompts (intentional — preserves
  spec quality at design decisions). A future `--autonomous` flag would
  add `/spec-author` mode-gating against `execution_strategy: balanced`
  and accept auto-defaults for falsification findings, enabling true
  fire-and-forget bulk planning at the cost of design oversight. Defer
  until a user actually wants it.

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
