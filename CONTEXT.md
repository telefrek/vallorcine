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

*Last updated: 2026-03-18*

**Codebase curation — designed, built, dogfooded, and polished `/curate`.**

**What shipped this session:**
- **`/curate` command** — correlation engine that combines vallorcine's structured
  history with git data to find stale decisions, knowledge gaps, implicit dependencies,
  test-source drift, and orphaned areas. Bash scan script + Claude correlation +
  conversational numbered pick list for triage.
- **`curate-scan.sh`** — 8 analyses: churn hotspots, co-change clusters, artifact
  correlation, orphaned areas, KB staleness, ADR revisit conditions, test-source
  drift, and backfill candidates from archived features.
- **`index-verify.sh`** — self-healing index verification. Detects and repairs
  missing rows in `.kb/CLAUDE.md` and `.decisions/CLAUDE.md` after crashes.
  Called automatically by `/curate` before scanning.
- **Pre-PR commit verification** — `/feature-pr` Step 0.5 scans for untracked
  `.kb/`, `.decisions/`, source, and test files before drafting. Offers to stage them.
- **`/upgrade-vallorcine` auto-commit** — upgrades now commit kit changes immediately
  as `chore: upgrade vallorcine to vX.X.X`. Stashes in-flight staged changes first.
- **Seed file protection** — `install.sh` never overwrites user-populated KB/decisions
  indexes, even with `FORCE_UPDATE=1` or version mismatch auto-force.
- **Runtime file gitignore** — installer adds `.statusline-baseline`, `.token-state`,
  `.token-checkpoint`, `.feature/`, `.curate/` to user's `.gitignore`.
- **Script permissions** — installer pre-approves vallorcine scripts in `settings.json`
  (explicit per-script, not wildcard).
- **73 tests passing** (37 install + 24 curate scan + 12 index verify).
- **Dogfooded on JLSM** — found and fixed: empty root indexes (crash recovery gap),
  orphaned KB/ADR files after pipeline, curation loop not returning to pick list.
- **Documentation** — DESIGN.md (five concerns, curation architecture, mermaid diagram),
  README.md (five concerns, commands table, usage examples), plugin/marketplace
  descriptions, COMPETITIVE.md positioning, GitHub repo description and topics.

**Where things stand:**
All work on main branch (uncommitted). Ready to cut a PR and release. Dogfood on
JLSM confirmed working end-to-end: `--init` scan → numbered findings → fix items
→ clean rescan.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

- **Curation as correlation engine** (2026-03-18) — dropped the "concern graph"
  abstraction in favor of correlating git history against existing artifacts.
  Four value buckets: ADR drift, KB+hindsight, implicit dependencies, orphaned
  areas. Business objectives can't be inferred from git history — focus on
  structural quality signals.

- **`.curate/` namespace** (2026-03-18) — own directory like `.kb/` and `.decisions/`.
  Gitignored (per-developer state). `curation-state.md` for scan state + review log.

- **Numbered pick list for curation findings** (2026-03-18) — each finding gets a
  number, description, and action. User picks by number instead of free text.
  Loop: after completing an item, re-present remaining items. "done" exits.

- **Seed files never overwritten** (2026-03-18) — `install.sh` uses `_install_seed`
  for KB/decisions indexes. Ignores FORCE_UPDATE. Found via dogfood: every force
  install was wiping JLSM's populated indexes with empty templates.

- **Index self-healing** (2026-03-18) — `index-verify.sh` checks directory contents
  against index rows. Repairs missing entries from crash-interrupted bottom-up
  updates. Called by `/curate` before scanning.

- **Pre-PR commit verification** (2026-03-18) — `/feature-pr` Step 0.5 scans for
  untracked `.kb/` and `.decisions/` files. Catches orphaned knowledge files from
  crash-interrupted domain analysis or retrospectives.

- **Upgrade auto-commit** (2026-03-18) — `/upgrade-vallorcine` commits kit changes
  as a standalone `chore:` commit. Stashes in-flight staged changes. Prevents kit
  updates from leaking into feature PRs.

- **Backfill consolidated into curate** (2026-03-18) — `/curate` scans archived
  feature domains for implicit decisions. Single entry point instead of separate
  `/decisions backfill`. Help routing updated.

- **Explicit script permissions** (2026-03-18) — per-script permission entries in
  `settings.json`, not wildcard. Prevents arbitrary scripts in `.claude/scripts/`
  from auto-executing.

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
