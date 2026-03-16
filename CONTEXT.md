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

**Just released: v0.2.0** — team concurrency safety, scenario tests, KB staleness.

**What shipped in v0.2.0:**
- Pre-flight checks (version skew, merge driver auto-setup, KB freshness)
- Index merge driver for `.kb/CLAUDE.md` and `.decisions/CLAUDE.md`
- KB staleness detection with inline `/research` for gaps and stale entries
- Per-phase token tracking via session JSONL
- 62 tests across 7 test files (install + 6 scenario tests)
- Research brief fully consumed — competitors, feature ideas, open questions triaged
- Known team issues documented in DESIGN.md

**Where things stand:**
v0.2.0 released and published to GitHub. All prior work merged. Clean main branch.
No active WIP branches.

---

## Recent decisions

*Rolling window — graduate oldest entries to SETTLED.md when this exceeds ~10 items*
*All decisions through v0.2.0 graduated to SETTLED.md on 2026-03-16.*

---

## Open questions

*Live list — resolve into SETTLED.md or drop when addressed*

- **/decisions command** — list/filter existing ADRs. Suggested early, never
  built. Useful once a project accumulates many decisions. Confirmed gap vs
  competitors. **Ranked: high priority.**

- **KB coding agent** — third KB role that reads entries and implements against
  them. Would close the loop between research and implementation.

- **Work unit split thresholds** — 15K crossover and 3.5K per-construct are
  reasoned estimates, not measured. Real-world use will reveal if adjustment needed.

- **install.sh --run-tests flag** — validation flag for fresh installs and
  upgrades. Would run scenario scripts against a temp repo to verify the
  installation works before using it on a real project.

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
