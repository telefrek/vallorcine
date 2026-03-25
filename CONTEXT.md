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

*Last updated: 2026-03-23*

**Adversarial TDD (aTDD) pipeline — designed, data extracted, validation harness
built, ready to begin validation runs against jlsm features.**

**What happened this session:**

- **aTDD pipeline designed** — 3 new agents (Spec Analyst, Breaker, Constrained
  Refactorer) and 3 new skills (`/atdd-round`, `/atdd-audit`, `/atdd-refactor`).
  Reuses existing Code Writer as Implementer with `known_issues.md` injection.
  Write authority and escalation paths added to `tdd-protocol.md`.
- **jlsm validation data extracted** — 130 JSONL sessions mapped to 15 features.
  Token usage extracted per-stage with TDD boundary detection. Git SHAs and parent
  commits verified for state reconstruction. 84 session files sanitized (PII removed,
  integrity verified with SHA256 checksums).
- **Validation harness built** — `aTDD-research/harness/` with scripts to set up
  worktrees at feature commits, collect results after Claude Code runs, and generate
  comparison reports (standard TDD cost vs aTDD additional cost vs bugs found).

**Where things stand:**
First validation runs complete for `encrypt-memory-data` (both greenfield and audit).
Results inform pipeline enhancements now shipping in standard TDD agents.

**encrypt-memory-data validation results (2026-03-24):**
- Greenfield aTDD: 3 rounds, 20 bugs, 2.2M billable tokens, 373 messages
- Audit aTDD: 3 rounds, 8 bugs (7+1+0), 1.4M billable tokens, 259 messages
- Greenfield: 9.1 bugs/M tokens. Audit: 5.7 bugs/M tokens (greenfield more efficient)
- Both converged: greenfield round 3 found repeat tendency only, audit round 3 found 0
- Round 2 valuable in audit — caught regression from round 1 fix (keySegment obfuscation)
- Key finding: T2-HEAPCOPY tendency repeated 3x across greenfield rounds — Implementer
  defaults to caching key material on heap, defeating off-heap threat model

**Pipeline enhancements from validation findings:**
- Test Writer: defensive test vectors (boundary values, error paths, security caching)
- Code Writer: fix-forward rule (scan for same anti-pattern after fixing a bug)
- Refactor Agent: assert-only validation check, exception swallowing check
- tdd-protocol: 5-minute Bash timeout on all test execution

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

- **aTDD as parallel path, not replacement** (2026-03-23) — adversarial TDD is a
  second pipeline option alongside standard TDD. Three tiers: Quick (easy), Standard
  (moderate), Adversarial (complex/critical). Selection at scoping time.

- **Spec Analyst generates dynamic Breaker prompts** (2026-03-23) — static adversarial
  prompts plateau at cycle 3-4. The Analyst reads implementation + tests + prior
  findings to generate a targeted prompt each round, avoiding redundant coverage.

- **Constrained Refactorer is a separate agent** (2026-03-23) — distinct from the
  standard Refactor Agent because it must honour `known_issues.md` as structural
  invariants. Mixing both modes into one agent makes debugging harder.

- **Implementer is the existing Code Writer** (2026-03-23) — no new agent needed.
  `known_issues.md` injected as additional context (RESOLVED patterns as hard
  constraints, TENDENCY as code review blockers).

- **Inter-round human gate with convergence signal** (2026-03-23) — intra-round is
  automated (Analyst → Breaker → Implementer). Between rounds, show confirmed bugs
  vs theoretical concerns. When Breaker can only produce untriggerable vectors,
  that's the convergence signal to stop.

- **atdd-status.md separate from status.md** (2026-03-23) — aTDD runs after standard
  TDD without clobbering pipeline state. Separate checkpoint file.

- **Validate with hard numbers before shipping** (2026-03-23) — run both pipelines
  against 15 jlsm features from identical starting points. Measure: additional bugs
  found, tokens per round, convergence curve. Replace speculative 2-4x cost estimate.

- **Research bundle for reproducibility** (2026-03-23) — sanitized JSONL logs, feature
  descriptions, git SHAs, automation scripts. Others can independently verify results.

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*

### Do next (high priority, clear direction)

- **aTDD validation runs** — run `/atdd-audit` against all 15 jlsm features,
  collect metrics, determine real cost multiplier and convergence curve. Starting
  with `striped-block-cache` (simplest). Time-sensitive: JSONL logs expire ~Apr 2.

- **Three-tier analysis: TDD vs TDD+Audit vs full aTDD** — the validation should
  measure not just aTDD vs TDD, but where a single audit pass falls on the
  cost/quality curve. Three comparison points per feature:
  1. **Standard TDD** — baseline bugs found, cost
  2. **TDD + Audit** — single post-implementation audit pass, additional bugs, ~1.3-1.5x cost
  3. **Full aTDD** — iterative rounds, additional bugs beyond audit, ~2-4x cost

  Key questions:
  - What % of aTDD-found bugs does a single audit catch? If 80% at 30% cost,
    most features should use TDD+Audit, not full aTDD.
  - Does the "everything is wrong" mindset belong in the standard Test Writer
    for high-risk domains (crypto, concurrency)? An enhanced prompt adding 2-3
    "skeptical" tests per construct during standard test writing is nearly free.
  - Where does the iterative convergence loop actually pay off? Likely only for
    code where fixing bug A reveals bug B (state machines, invariant-heavy APIs).

  Expected outcome: a decision framework for tier selection at scoping time,
  informed by real data rather than intuition. Encryption features likely justify
  full aTDD; most CRUD features should stop at TDD+Audit or enhanced Test Writer.

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
