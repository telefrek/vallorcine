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

*Last updated: 2026-03-19*

**Showcase tools — 3-stage pipeline for turning JSONL session logs into narrative articles.**

**What shipped this session:**
- **`tools/showcase/render_narrative.py`** — stage 3 renderer producing polished
  markdown from Story ASTs. HTML-styled conversation blocks with speaker colors
  (blue=vallorcine, green=user), Mermaid gantt with Discovery/Execution/Delivery
  sections and work unit sub-bars, progressive disclosure (prominent content inline,
  background collapsed), shields.io badges, retro checklist parsing, phase breakdown
  table with token percentages and anchor links.
- **Parser hardening (parse.py)** — duration now excludes user wait time, crash gaps,
  crashed subagent limbo, and subagent internal idle (permission prompts). Terminal
  stages (retro/complete) correctly reset feature tracking. Subagent idle keyed by
  tool_use_id instead of description.
- **Tokenizer hardening (tokenizer.py)** — streaming via `iter_jsonl` generator (O(1)
  memory per line), subagent user wait detection, description override from parent's
  Agent tool call, model backfill from assistant messages, CLI version capture, token
  usage deduplication, boundary-aware slug matching, corrupt meta file handling.
- **Model updates (model.py)** — streaming `TokenStream.save()`, `cli_version` field
  on Story, `_usage_dict()` replacing `asdict()`.
- **Performance review** — 6 optimizations: streaming tokenizer, literal interest
  detection, lazy meta index, streaming serialization, boundary-aware slug matching,
  token usage deduplication.
- **Code review** — Python expert reviewed all 4 files for correctness, performance,
  and resource constraints. 7 issues found and fixed.
- **33-bug test plan** — `TEST_PLAN.md` documents all bugs with reproduction steps.
- **Validated on 3 real JLSM features** — encrypt-memory-data (2 sessions, 1h 27m),
  table-partitioning (4 sessions, 1h 24m), float16-vector-support (4 sessions, 39m).

**Where things stand:**
All work committed on `feat/showcase-tools` branch. Ready for PR. Deferred items:
interactive snippet player, diagnostic output mode, README sample snippets,
vallorcine version tracking.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

- **Build our own from JSONL logs** (2026-03-19) — asciinema dropped (marker injection
  has subagent visibility problems). Built a translator that produces narrative
  markdown from the rich structured JSONL data Claude Code already writes.

- **3-stage pipeline** (2026-03-19) — tokenizer (JSONL→tokens), parser (tokens→AST),
  renderers (AST→output). File-based intermediates between stages for crash recovery
  and debuggability. Each stage has a single concern.

- **HTML inline styles over GitHub alerts** (2026-03-19) — `[!NOTE]`/`[!TIP]` etc.
  are GitHub-specific and render as raw text in most markdown clients. HTML `<div>`
  with inline styles works universally. Color scheme: blue=vallorcine, green=user,
  amber=warning, red=crash.

- **Duration = active work time only** (2026-03-19) — phase durations subtract user
  wait time (assistant→user gaps), crash gaps, crashed subagent limbo, and subagent
  internal idle (permission prompts). A 15h wall-clock feature shows as 1h 27m of
  vallorcine active work.

- **Terminal stages reset feature tracking** (2026-03-19) — retro and complete are
  pipeline terminal stages. They're included in the story but reset `in_feature`
  so subsequent commands from a different feature don't bleed through.

- **Gantt sections by work type** (2026-03-19) — Discovery/Execution/Delivery
  sections in the Mermaid gantt show the shape of work. Crash boundaries shown
  via alerts in the body instead. Work units rendered as sub-bars under
  coordination phases.

- **Progressive disclosure for background narration** (2026-03-19) — prominent
  content (conversations, escalations, research/architect cards) shown inline.
  Internal narration (prose, file writes, test results) collapsed into a single
  expandable "Show N steps" block per phase.

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
