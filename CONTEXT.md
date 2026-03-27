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

*Last updated: 2026-03-27*

**5-pass analysis pipeline for /audit — validated against 26 known bugs,
24/26 found (92%), at 416K tokens (60% cheaper than old ~1M approach).**

**What happened this session (2026-03-27):**

- **Context pruning research** — KB entry at `.claude/research/context-pruning-techniques.md`
  covering 6 same-session techniques. Key finding: caching and pruning are adversarial
  (arXiv 2601.06007); batch clearing events to amortize cache invalidation.

- **5-pass analysis pipeline designed, implemented, and validated:**
  - Pass 1: Construct inventory + 8 relationship edge types (~49K tokens)
  - Pass 2: Concern triage across 7 areas (~63K tokens)
  - Pass 2.5: Construct clustering via graph partitioning (~55K tokens)
  - Pass 3a: Per-cluster deep analysis with attack-generation framing (~185K tokens)
  - Pass 3b: Cross-cluster reconciliation for producer/consumer bugs (~64K tokens)

- **`shares_state` edge type validated** — methods sharing mutable state (channel,
  flag, collection) must cluster together. Found B-19 (channel race) on first try;
  old pipeline found it 50% of runs. Type-scoped unsplittable: within same type
  is mandatory, cross-type bridges defer to Pass 3b.

- **Prompt refinements from validation failures:**
  - Data integrity: added "hardcoded instead of read" pattern (caught B-16/17/18)
  - Contract conformance: added "semantically nonsensical input" and "stale
    reporting methods" (targets B-25/B-26)
  - Concurrency: added shared I/O handles on parent objects (caught readBytes race)

- **Scaling validated:** encryption feature (13 files) costs ~249K for triage
  phases — linear scaling with file count confirmed.

- **Phase 4 design outlined** — write-and-return test writer (no compile loops),
  separate compile checker, per-cluster implementer with context management.

**Where things stand:**
Analysis pipeline is validated. Next: implement Phase 4 (test writing + fixing)
with context pruning applied to eliminate compile/fix loop bloat. Then integrate
the full pipeline into the shipped /audit skill.

**Pipeline cost (block-compression, 7 files, 26 known bugs):**
```
Pass 1:    49K tokens   (inventory + edges)
Pass 2:    63K tokens   (triage matrix)
Pass 2.5:  55K tokens   (clustering)
Pass 3a:  185K tokens   (6 clusters, 24/26 bugs + 44 extra findings)
Pass 3b:   64K tokens   (reconciliation, +3 cross-cluster bugs)
Total:    416K tokens   → 92% detection at 60% cost reduction
```

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

- **5-pass analysis pipeline replaces single-session spec analysis** (2026-03-27) —
  inventory → triage → clustering → per-cluster deep analysis → reconciliation.
  Each pass writes to disk; next pass reads the file, not the conversation history.
  416K tokens vs ~1M for equivalent coverage. Validated against 26 known bugs (92%).

- **Construct-level clustering, not file-level** (2026-03-27) — clusters follow data
  flow and shared state, not file boundaries. A 600-line file can span 3 clusters.
  Subagents read targeted line ranges, not full files.

- **`shares_state` edge type for mutable state clustering** (2026-03-27) — methods
  on the same mutable type that access the same field/resource must cluster together.
  Prevents splitting concurrency/lifecycle bugs across clusters. Validated: found
  channel race bug on first try (old pipeline: 50% hit rate).

- **Type-scoped unsplittable edges** (2026-03-27) — `shares_state` and `data_flow`
  are unsplittable within a single type. Cross-type data_flow bridges are strong
  preferences but can split — Pass 3b handles cross-cluster producer/consumer analysis.
  Without this rule, transitive closure merged Writer+Reader into one 65-cell cluster.

- **No hard limits on cluster size** (2026-03-27) — removed arbitrary cell/construct/line
  limits. Soft preference for 6-15 cells. Complexity warning at 25+ cells or 500+ lines
  surfaces to user as refactoring signal. Graph structure determines boundaries.

- **Attack-generation framing for deep analysis** (2026-03-27) — "what input breaks
  this?" not "does this look correct?" Per-cell independence prevents satisficing.
  Clearing requires specific line references, not "looks correct."

- **Language-agnostic pipeline design** (2026-03-27) — all edge types, concern areas,
  and prompts use semantic descriptions, not language-specific syntax or patterns.
  No grep/AST parsers needed. Works for any language the LLM can read.

- **Write-and-return test writers** (2026-03-27) — Phase 4 breakers write tests and
  exit. No compile loops in test writing. Separate compile-check phase. Eliminates
  50% post-write overhead measured in breaker agents.

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*

### Do next (high priority, clear direction)

- **Phase 4 implementation and validation** — design and test the write-and-return
  test writer (4a), compile checker (4b), fix-up subagent (4c), and per-cluster
  implementer (4d). Apply context pruning techniques to eliminate compile/fix loop
  bloat. Validate end-to-end: analysis findings → tests → fixes → verify.

- **Full end-to-end pipeline test** — run all phases (1 through 4d) on
  block-compression at af6b5cb. Score: do all 26 bugs get tests written, do
  tests fail before fixes, do fixes pass? Measure total token cost across
  entire pipeline.

- **Integrate into shipped /audit skill** — once end-to-end is validated, ship
  the 5-pass analysis pipeline + Phase 4 as the user-facing /audit command.
  Replace the existing single-session spec-analyst approach.

### Do soon (medium effort, clear designs)

- **Large repo curation testing** — `/curate` dogfooded on JLSM (19 commits).
  Needs testing on a larger repo (1000+ commits, 30+ contributors) to validate
  the 500-commit cap and co-change analysis performance in bash.

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
