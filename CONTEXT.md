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

*Last updated: 2026-03-16*

**Releases: v0.2.2 and v0.2.3.** Major session — shipped parallel work units,
decision archaeology, four-concern architecture model, and many smaller features.

**What shipped this session:**
- v0.2.2: parallel work unit execution, execution strategy prompt, per-unit isolation
- v0.2.3: `/decisions backfill`, domain scout auto-invokes architect/research,
  classification fix, `/vallorcine-help` question answering, install bootstrapping fix
- Post-v0.2.3 (unreleased): `/decisions list`, `/decisions explain`, `/decisions candidates`,
  `/feature-cleanup`, `/feature-retro`, `/project-context`, `install.sh --diff`,
  dependency topology in `/feature-resume`, refactor step 2g (documentation check),
  `/quick` → `/feature-quick` rename, four-concern README/DESIGN restructure,
  token estimate vs actual tracking in status.md

**Where things stand:**
All work committed and pushed to main. Not yet released — significant changes
accumulated post-v0.2.3. Ready for v0.3.0 (or v0.2.4 depending on semver preference).
Active testing on jlsm project. WIP.md cleared.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*

- **Four-concern architecture model** (2026-03-16) — vallorcine organised around
  Knowledge (/kb, /research), Decisions (/architect, /decisions), Features
  (/feature-*), and System (/vallorcine-*, /project-context). README and DESIGN.md
  restructured to match. Commands named by concern.

- **/quick → /feature-quick rename** (2026-03-16) — aligns with feature-* naming
  convention. All 12 files with references updated. Old name removed.

- **Refactor step 2g: documentation check** (2026-03-16) — refactor agent now
  verifies project documentation stays current when features change modules, APIs,
  or patterns. Added after 2f (integration tests).

- **Principle 1: bash and markdown only** (2026-03-16) — hard constraint, not
  preference. No MCP servers, no hooks infrastructure, no package managers, no
  external runtimes. First filter for new features. Dropped hooks-for-non-TDD and
  Context7/live-docs from backlog as violations.

- **Refactor step 2h: security review** (2026-03-16) — holistic security audit
  after all other refactoring. Distinct from 2c (inline fixes): 2h assesses auth,
  data handling, trust boundaries, dependencies, and threat surface delta. Findings
  use HIGH/MEDIUM/LOW severity. Always pauses on findings. Flows into PR via
  cycle-log.

- **Draft ADRs warn but don't block** (2026-03-16) — Domain Scout classifies
  draft ADRs as `pending-decision` with a warning. User can proceed or formalize
  via `/decisions review`.

- **Decision candidates from transcript scanning** (2026-03-16) — PostSessionEnd
  hook stages candidates in `.decisions/.decision-candidates`. Notices surface at
  `/feature-domains` and `/feature-resume`. `/decisions candidates` to review.

- **PROJECT-CONTEXT.md for team knowledge** (2026-03-16) — committed file at
  project root. 90-day expiry, scoped entries, 50-entry cap. `/project-context`
  command (not `/context` — that's a Claude Code built-in).

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed.*
*Prioritised: do next → do soon → do when needed → do when scale demands it.*

### Do next (low effort, real risk mitigation)

- ~~Command name collision audit~~ — **done** (2026-03-16). Zero collisions found
  across 22 commands vs 45 Claude Code built-ins. `feature-` prefix strategy works.

- ~~ADR contradiction check~~ — **done** (2026-03-16). `scripts/adr-validate.sh`
  scans for duplicate accepted slugs. Added to pre-flight checks. Regression test
  at `tests/scenario-adr-contradiction.sh` (10 cases).

### Do soon (medium effort, clear designs)

- ~~`/decisions backfill`~~ — **updated** (2026-03-16). Added Step 0 size check:
  projects over `backfill_file_threshold` (default 50, in project-config.md)
  require explicit path. Spec in decisions.md and DEFERRED.md.

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
