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

*Last updated: 2026-04-24*

**v0.14.3 shipped (main@`f23cc79`). Active branch `fix/kb-scan-actionable`
— three coordinated fixes that make `.kb/` actionable across the
coordinator, audit Suspect, and audit prove-fix. PR not yet opened; two
follow-on investigations running on the same jlsm session (other
workflow deviations, audit cost-per-bug) before cutting the PR.**

### What's shipped since 2026-04-21

**v0.14.1 → v0.14.2 release sequence:**
- v0.14.1 (2026-04-21 evening, commit `35e8e31`) — bundled the `/curate`
  drift detection analyses (18 + 19) that were staged at the end of the
  spec migration day.
- v0.14.2 (commit `7fc33dd`) — four GSD-gap capabilities from the
  2026-04-21 competitive audit:
  - **PR #51** — `/audit` FIX_IMPOSSIBLE escalation flow (relax-test /
    wontfix / spec-author / defer), closing the graveyard path for
    audit findings blocked by pin tests.
  - **PR #52** — `/spec-write` quantitative ambiguity gate (GSD
    capability #3): `spec-ambiguity-score.sh` computes
    `([UNVERIFIED]+[UNRESOLVED]+[CONFLICT]) / total_requirements` and
    surfaces the score at DRAFT → APPROVED promotion time.
  - **PR #53** — `/audit` security lens (GSD capability #1):
    `prompts/audit/lens-security.md` with TESTABLE vs ADVISORY finding
    taxonomy, 4 new exploration signals (credential store, PII, auth
    middleware, deserialization). Addresses the encryption-audit gap
    (10 bugs found via generic lens, 3 classes missed: timing channels,
    IV reuse, ciphertext integrity).
  - **PR #54** — `/work-start --parallel [N]` (GSD capability #2):
    wave-based multi-WD dispatch using the existing readiness model.

**Also merged post-v0.14.2:**
- **PR #55** — docs: DESIGN manifest sync + `/feature` pipeline audit
  surfacing.
- **PR #56** — `/audit` wontfix findings now route through
  `open_obligations` on the most-relevant spec, resurfacing via
  `/curate` analysis 19 aging logic once past the threshold. Closes the
  last graveyard path for FIX_IMPOSSIBLE outcomes.

### The v0.14.3 bundle (this PR on `chore/v0.14.3-bundle`)

Three workstreams collapsed into one PR for reviewability. Six commits:

**Fixes:**
- **`fix(spec): v2 manifest schema compatibility`** — dual-schema (v1 +
  v2) manifest compat across `spec-resolve.sh`, `work-lib.sh`,
  `work-finalize.sh`, `curate-scan.sh`, `spec-stats.sh`. Root cause:
  the 2026-04-20 spec migration flipped the manifest from
  `{features: {FXX: ...}}` (v1) to `{schema_version: 2, specs: [...]}`
  (v2), and several read-path scripts were still hardcoded against v1
  keys — they silently failed under `set -euo pipefail` or fell through
  to `NEEDS_DOMAIN_INFERENCE=true` for every call, blocking
  `/work-start`, `/spec-write`, `/feature-plan`, `/feature-test`,
  `/spec-author`, and `/audit` on v2 repos. Added four dual-schema
  manifest query helpers to `spec-lib.sh`.
- **`fix(tests): close four pre-existing scenario-test failures`** —
  found during the manifest-v2 sweep, closed here per the
  fix-now-not-defer rule: `scenario-index-verify` arithmetic bug,
  `scenario-narrative` stale exit-code assertions, `scenario-version-skew`
  legacy install-layout reference, `scenario-work-pipeline` v1-manifest
  fixture paired with v2-style WD deps.
- **`fix(pipeline): prevent parallel-subagent hangs`** — mode-gates
  every unconditional `AskUserQuestion` in the three pipeline skills
  (`/feature-test`, `/feature-implement`, `/feature-refactor`) so they
  bypass to `cycle-log.md` + `escalated-<reason>` substage + `ESCALATED`
  return in parallel mode instead of hanging on a missing human.
  Strengthens `/feature-refactor`'s parallel-mode exit with an explicit
  termination contract ("your very next message MUST be the summary
  line — no more tools"). Adds Step 1a to `/feature-coordinate`
  documenting the subagent dispatch contract every coordinator must
  embed. Root-caused from the 2026-04-23 jlsm WU-3 hang (subagent wrote
  `status.md = COMPLETE` at 10:41:32, then kept running ~2 min before
  the user had to Ctrl+C). Regression:
  `scenario-parallel-subagent-hang-prevention.sh` (10 structural
  invariants).

**Documentation:**
- **`docs: freshness pass through v0.14.2 + held branches`** — CONTEXT
  refresh, 7 decisions graduated to SETTLED.md, DEFERRED marked
  security-aware lens as done.
- **`docs: add GETTING-STARTED + GETTING-STARTED-EXISTING guides`** —
  two new repo-only onboarding docs (316 + 333 lines) for people
  landing on the GitHub page. Not shipped via MANIFEST. README gains a
  "New here?" link section; `/vallorcine-help` gains URL hints for
  conceptual questions.
- **`docs: spot-check fixes for EXAMPLES + COMPETITIVE + GETTING-STARTED`**
  — corrected the `.spec/` bug I introduced in GETTING-STARTED (`.spec/`
  is `/spec-init`-gated, not created by `/setup-vallorcine`); added
  `/feature-harden` to the EXAMPLES.md walkthrough (was missing);
  reconciled the split threshold in EXAMPLES to match SETTLED (~15K
  tokens / 5+ constructs); added four new walkthrough sections to
  EXAMPLES (parallel execution via `/feature-coordinate`, spec workflow,
  standalone `/audit`, `/capabilities`); refreshed COMPETITIVE's "Closed
  gaps" with the four v0.14.2 GSD-parity shipments and sharpened the
  standalone-security-scanner boundary; added `/feature-harden` and
  `/capabilities` to the `.claude/rules/kit-development.md` user-facing
  command list.

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

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*
*Status tags: `[implemented]` = code exists, needs validation. `[designed]` = spec
exists, not yet coded. No tag = needs both design and implementation.*

### Do next

**Wrap the `fix/kb-scan-actionable` investigation, then open the PR.**

The morning's WIP framing (KB isn't being loaded) was half-right. The
shipped fix covers three distinct failure modes uncovered empirically
on jlsm session `763f30a6-4194-4137-812f-97502540135e`:

| Surface | Subagents | Empirical finding | Fix shipped |
|---|---:|---|---|
| WU-TDD coordinator dispatch | 4 | All 4 dispatch prompts omit Step 8 entirely (zero KB keywords across 39K chars) | `/feature-coordinate` Step 1a now carries a **KB tendency-scan contract (MANDATORY)** fragment; Step 8 is MANDATORY with `tendency-scan-complete` substage + cycle-log append; coordinator-side verification greps for evidence post-return |
| Audit Suspect | 27 | KB *does* flow through to packet (17/17 have KB content) — Suspect treats it as passive reference, not attack vectors; 2/95 findings cite KB | `suspect.md` adds a KB attack-pattern sweep step; finding schema gets `KB refs:`; summary reports `KB-driven` count |
| Audit prove-fix | 83 | `prove-fix.md` has zero KB integration; 0/95 outputs cite KB | `prove-fix.md` Phase 1a1 KB fix-pattern lookup; `kb_refs` input/output; orchestrator forwards `kb_refs` per finding |

The workflow-deviation scan also surfaced **D4: Phase 0 short-circuit
bypassed for upstream-mitigated findings** — 16 of 36 IMPOSSIBLE
returns on the jlsm run were mitigated by a prior prove-fix's upstream
guard, but Phase 0 only checked the local construct and the agent went
through full Phase 1 anyway. Bundled on this branch: `prove-fix.md`
Phase 0 budget raised 2 → 4 turns, new 0c "upstream-mitigation check"
reads up to 2 sibling `prove-fix-*.md` outputs and short-circuits to
`IMPOSSIBLE / UPSTREAM_MITIGATED` when a caller-side guard blocks the
attack path.

Status: 22/22 regression invariants pass, 59/59 install tests pass,
all related audit scenarios green (lens-security 23/23, state-gate 5/5,
wontfix-obligation 5/5, aggregate-results 32/32, check-test-coverage
13/13, dedup-findings 12/12), no regressions on hang-prevention
scenario (10/10).

**Cost-per-bug snapshot (Opus 4.7 API rates):** jlsm audit total
$1,333, 95 findings, **$14.03/finding** (on trend with 7-audit historical
$13.61 avg). Prove-fix is 82% of audit-subagent cost. D4 targets ~11%
prove-fix waste (~$86/audit at this size); KB-actionable fixes
(D1-D3) target another ~15-25% of findings that should pre-clear.
Combined ceiling: projected $/finding floor ~$11 on audits with
similar KB density.

Non-findings verified: the initial "Suspect writing test files" signal
was a classifier bug (prove-fix dispatch prompts reference
`Suspect: <filename>`); TodoWrite discipline holding (0 subagent
violations). Context thrash (D5 — 37/126 agents re-read same file 5+
times) is intentional per the re-read-before-edit protocol; revisit
only if post-D4 cost data shows it's still material.

**Next: open the PR.**

**Positioning shift (still outstanding — carries over from v0.14.3):**
emphasize depth-of-spec-rigor axis over the "spec-driven" label across
user-facing docs. Not a blocker for the current PR; bundle with the
next docs pass.

### Do soon (medium effort, clear designs)

- **Fix spec-layer gaps (11 identified)** — 4 critical: feature-implement spec
  awareness, feature-refactor spec awareness, spec-write two-file invalidation,
  work-decompose spec state validation. Full gap analysis in session memory.
  Status: not started since 2026-04-21. Check first whether any are already
  covered by the manifest-v2 dual-schema work before scoping.

- **Fix 6 pipeline failure patterns** — one-sided invalidation, audit outpacing
  specs, assert-only guards, dead code wiring, spec asymmetry, feature-centric
  organization. Each has root cause and fix task documented. Status:
  feature-centric organization resolved by the 2026-04-20 spec migration
  (behavioral domains). The others still stand.

- **Partial implementation state model** — binary APPROVED/DRAFT insufficient for
  specs that are 90% implemented. Need either per-requirement states, split specs,
  or APPROVED-with-obligations. Data from verification pass will inform design.
  Revisit once 2-3 jlsm WDs have completed implementation and we can read
  their emergent patterns.

- **Flaky-test surfacing in `/feature-retro`** — scan cycle-log.md for
  flakiness signals (timeouts on first run + passed-on-rerun, "flaky",
  "retry" keywords) and emit a dedicated retro section. Triggered by the
  2026-04-23 jlsm WU-3 run which noted a pre-existing
  `SharedStateAdversarialTest` timeout-then-pass that would otherwise be
  buried. See `DEFERRED.md`.

### Do when needed (useful but workarounds exist)

- **Large repo curation testing** — `/curate` needs testing on a repo with
  1000+ commits, 30+ contributors.

- **spec-trace.sh sub-lettered IDs** — R39a-h pattern not matched by numeric-only
  regex. Annotations exist in code but uncounted. Fix when reorg drops FXX IDs.

- **#45 cosmetic `upgrade.sh` output bug** — low priority; originally on the
  v0.14.1 stack, still open.

### Do when scale demands it (team/scale features)

- **Team KB commands** — `/kb sync`, `/kb consolidate`, `/kb status`.

- **Pipeline observability** — velocity metrics, KB utilization tracking.

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
