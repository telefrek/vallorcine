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

*Last updated: 2026-04-16*

**Work-start blocked by decisions-only WDs. Deep spec audit in progress.**

**What happened (2026-04-15/16):**

Attempted `/work-start decisions-backlog` in jlsm. Discovered all 13 WDs in the
decisions-backlog group are decisions-only (produce only ADRs, no specs or
implementation). This is structurally wrong — every spec change requires an
implementation pass. The work layer was completely disconnected from the
spec→audit→test→code chain that already exists in jlsm.

**Key findings:**

- **Decisions-only WDs are invalid.** Agreed: there is no valid "decisions-only"
  WD type. Every WD must scope through to implementation consequences.
- **26 DRAFT specs (F01-F26) deeply integrated with code** — 63 adversarial test
  classes reference spec IDs, audit artifacts link to specs, code comments cite
  spec requirements (`F17.R1-R3`). Not decorative artifacts.
- **Work layer doesn't see the spec layer.** `/work-decompose` had no visibility
  into `.spec/` state — created WDs around ADR resolution and completely missed
  that specs already existed downstream of those decisions.
- **Coverage script unreliable.** R-number matching across specs gives false
  positives (F13 claimed 88% coverage, actual dedicated tests cover ~15 reqs).
  Script at `jlsm/tools/spec-audit/` needs redesign.
- **8 anchor spec audits completed** — requirement-by-requirement verification
  against implementation code. Three tiers emerged:
  - **Tier A (solid):** F13, F08, F15, F17, F02 — ~240 reqs, ~0 real gaps.
    Ready for APPROVED with spec wording fixes.
  - **Tier B (bugs found):** F11 — 2 genuine code bugs (mergeTopK tie handling
    R60, suppressed exceptions lost R103). Needs code fixes before promotion.
  - **Tier C (aspirational):** F04, F05 — 12 genuine gaps where specs describe
    target architecture but implementation is a working simplification (F04:
    no RAPID consensus/expander graph; F05: catalog not crash-safe, builder
    not public, state filtering missing).

**Where things stand:**
Anchor audits complete. Next: walk partial specs (F03, F06, F07, F09, F10, F14,
F18) using the same process, then cross-check greenfield and WD-created specs
against approved anchors. After spec integrity is established, fix the existing
jlsm WDs, validate `/work-start` flow, then fix `/work-decompose` to prevent
this pattern.

**Analysis scripts at:** `jlsm/tools/spec-audit/` (req-inventory, ref-map,
adr-linkage, test-coverage, run-audit.sh). Dashboard output at
`tools/spec-audit/output/summary.md`.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

*14 decisions graduated to SETTLED.md (2026-04-12): work layer (5), spec
hardening (9). See SETTLED.md for details.*

- **Decisions-only WDs are invalid** (2026-04-16) — every WD that produces or
  modifies specs must include an implementation pass. If a decision results in
  no spec changes and no code changes, it's a close/re-defer, not a WD.

- **Spec promotion requires cross-check** (2026-04-16) — before DRAFT→APPROVED,
  a spec must be verified against all APPROVED specs in its domain. Anchors go
  first (nothing to cross-check), subsequent specs have a growing constraint set.

- **Three-tier spec health model** (2026-04-16) — Tier A (code matches spec,
  promote), Tier B (spec correct but code has bugs, fix then promote), Tier C
  (spec describes target architecture, code is a working simplification, keep
  DRAFT with annotations).

- **Work-decompose must check spec state** (2026-04-16) — decomposition without
  visibility into `.spec/` produces WDs disconnected from reality. The algorithm
  must read spec registry as part of its analysis.

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*
*Status tags: `[implemented]` = code exists, needs validation. `[designed]` = spec
exists, not yet coded. No tag = needs both design and implementation.*

### Do next

- **Complete jlsm spec integrity audit** — walk partial specs (F03, F06, F07,
  F09, F10, F14, F18) then cross-check greenfield and WD-created specs against
  approved anchors. Four-round promotion process:
  - Round 1 (done): anchor promotion (5 Tier A specs → APPROVED)
  - Round 2: partial specs (7 specs, cross-check against anchors)
  - Round 3: greenfield specs (11 specs, cross-check against Rounds 1+2)
  - Round 4: WD-created specs (F27-F48, cross-check against everything)

- **Fix jlsm F11 code bugs** — R60 (mergeTopK tie handling) and R103
  (suppressed exceptions lost in closeIterators). Real implementation defects.

- **Unblock jlsm work-start** — restructure decisions-backlog WDs to include
  implementation scope, then validate `/work-start` flow end-to-end.

### Do soon (medium effort, clear designs)

- **Fix `/work-decompose`** — must check `.spec/` state during decomposition,
  prevent decisions-only WDs, ensure every WD scopes through implementation.
  Test with synthetic work group + jlsm validation run.

- **Spec cross-check mechanism** — before DRAFT→APPROVED promotion, cross-check
  against all APPROVED specs in same domain/overlapping types. Doesn't exist
  yet. Design question: spec-side `enforced_by` annotations, code-side `F13.R59`
  test comments, or script-side type tracing.

- **Redesign coverage script** — current R-number matching gives false positives
  across specs. Needs spec-scoped matching (only count R-numbers in files that
  reference the specific spec ID in context).

### Do when needed (useful but workarounds exist)

- **Large repo curation testing** — `/curate` needs testing on a repo with
  1000+ commits, 30+ contributors.

### Do when scale demands it (team/scale features)

- **Team KB commands** — `/kb sync`, `/kb consolidate`, `/kb status`.

- **Pipeline observability** — velocity metrics, KB utilization tracking.

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
