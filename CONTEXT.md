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

*Last updated: 2026-03-20*

**Preparing for next release — narrative pipeline shipped, architect and decisions
commands significantly enhanced, setup commands consolidated.**

**What shipped this cycle (since v0.5.3):**

- **Narrative pipeline in `/feature-retro`** — 3-stage pipeline (tokenizer → parser
  → renderer) integrated as Step 6. Generates `narrative.md` with badges, Mermaid
  gantt, phase-by-phase breakdown, progressive disclosure. Full Python + JavaScript
  parity. Graceful degradation when no runtime available.
- **ADR out-of-scope extraction** — curate-scan.sh Analysis 9 extracts "What This
  Decision Does NOT Solve" items from confirmed ADRs. `/curate` presents them and
  offers to create deferred stubs. `/architect` Step 6c now auto-creates deferred
  stubs for out-of-scope items going forward.
- **`/setup-vallorcine` consolidation** — absorbed `/feature-init`. Single command
  now initializes KB, decisions, feature pipeline, and project profile.
- **Architect iterative research** — Step 4c commissions follow-up research when
  initial candidates don't adequately cover the constraint space (up to 3 iterations).
- **Architect composite candidates** — Step 4b2 identifies when combining two
  candidates would satisfy constraints better than either alone.
- **`/decisions revisit`** — replaces `/decisions review`. Accepts topic/description
  search, conversational "why" step, revision condition checking, and feature kickoff
  after revision.
- **Architect neutral presentation** — non-negotiable rule against expressing
  preferences before Step 6a deliberation.
- **Mandatory doc review in `/release`** — Step 1.5 checks README, EXAMPLES, DESIGN,
  CONTEXT against changes before drafting release notes.

**Where things stand:**
All on main, ready for release cut. Documentation updated for all new capabilities.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

- **JS parity required for narrative pipeline** (2026-03-20) — Principle 1 mandates
  both Python and JS if either is provided. Full port of 5 pipeline files verified
  with identical output.

- **ADR out-of-scope items as deferred stubs** (2026-03-20) — accepted ADRs contain
  "What This Decision Does NOT Solve" sections invisible to `/decisions triage`.
  Retroactive: `/curate` Analysis 9 finds them. Proactive: `/architect` Step 6c
  auto-creates deferred stubs. Found via JLSM: 44 items across 13 ADRs.

- **Consolidate /feature-init into /setup-vallorcine** (2026-03-20) — no project has
  used one concern without the other. Supersedes SETTLED.md separation decision.

- **Architect iterative research** (2026-03-20) — after scoring, if coverage is thin
  (no strong candidates, missing constraint dimensions), commission targeted follow-up
  research. Up to 3 iterations. Found via JLSM dogfood.

- **Architect composite candidates** (2026-03-20) — evaluate combinations of
  approaches when no single candidate covers all constraints. Boundary rule defines
  which component handles which sub-problem.

- **/decisions revisit replaces /decisions review** (2026-03-20) — single command
  accepts slug or topic, conversational "why" pre-step, revision condition checking,
  feature kickoff after revision.

- **Architect neutral presentation** (2026-03-20) — non-negotiable rule: never express
  preference before Step 6a deliberation. Found via JLSM: architect was declaring
  winners during candidate identification.

- **Mandatory doc review in /release** (2026-03-20) — Step 1.5 checks README, EXAMPLES,
  DESIGN, CONTEXT against changes before release notes can be drafted.

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*

### Do next (high priority, clear direction)

- **Large repo curation testing** — `/curate` dogfooded on JLSM (19 commits).
  Needs testing on a larger repo (1000+ commits, 30+ contributors) to validate
  the 500-commit cap and co-change analysis performance in bash.

### Do soon (medium effort, clear designs)

- **Work unit split thresholds** — 15K crossover and 3.5K per-construct are
  reasoned estimates, not measured. Token tracking is collecting actuals — needs
  data review once enough features have run with tracking enabled.

### Do when needed (useful but workarounds exist)

- **/feature-split** — split in-progress feature when scope expands. Workaround:
  finish current feature, start a new one.

- **HANDOFF.md convention** — `/save-work` mostly covers this. May just need
  documentation rather than new code.

- **KB coding agent** — third KB role that reads entries and implements against
  them. Current workflow (read KB manually) works.

### Do when scale demands it (team/scale features)

- **KB `depends-on` field** — frontmatter field for structural staleness. P2/P3
  tension with fan-out reads on dependency chains. Date-based staleness sufficient
  for current scale.

- **Team KB commands** — `/kb sync`, `/kb consolidate`, `/kb status`. Useful for
  teams but vallorcine is primarily single-developer today.

- **LSP integration** — README documentation of companion plugins. Nice-to-have.

- **Pipeline observability** — velocity metrics, KB utilization tracking.
  Premature until more projects use vallorcine.

- **KB cross-referencing** — reverse mapping (decisions → KB). One-way exists.
  Low urgency until KB is large enough to need it.

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
Not vibes-based.

**No ceremony without value.** Resist adding steps that always run regardless
of need. 0-signal complexity check is silent. 0-question scoping is valid.

**Prefer one clean interface over two adequate ones.** When choices came down
to two approaches, we consistently chose simpler to use even if harder to
implement: enter-to-proceed, sequential questions, pull model.
