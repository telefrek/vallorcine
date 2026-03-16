# vallorcine — Competitive Landscape

Market positioning and ecosystem context for prioritisation decisions.
Updated during marketplace research sessions, not every development session.

*Last updated: 2026-03-16*

---

## Closest competitors

### Workflow pipelines

**Superpowers** — TDD + lifecycle, in official marketplace.

**Deep Trilogy** — staged decompose→plan→implement with TDD, three separate plugins.

**claude-code-workflows** (shinpr) — multi-stage pipeline with fresh agent contexts
per phase. Similar staged approach, no KB layer.

**feature-dev** (Anthropic official) — 7-phase structured workflow. No KB layer,
no crash recovery, no work unit splitting.

**Jamie-BitFlight/claude_skills** — 25 modular plugins, language-agnostic SAM
pipeline. Breadth over depth; no ADR or KB integration.

### Knowledge / memory

**claude-plugin-adr** — ADR templates + shell scripts, no deliberation loop.

**claude-mem** — SQLite + ChromaDB, automatic capture via session hooks. Passive
capture, opaque storage, no ADR concept. Push-model (always loaded).

**memsearch** (Zilliz) — Markdown + vector index, automatic capture via session
hooks. Transparent storage, but session summaries not structured decisions.

**claude-cognitive** — file attention scoring via hooks. Solves large-codebase
file selection, not knowledge persistence or structured decisions.

**Claude Code auto-memory** — built-in CLAUDE.md self-writes. 200-line limit,
blunt context loading, no ADR concept. Passive and unstructured.

---

## Where vallorcine leads

- Crash recovery (unique)
- Token-aware work unit splitting (unique)
- KB↔pipeline integration (unique)
- Deliberation loop on ADRs (unique)
- Sequential scoping interview (unique)

---

## Confirmed gaps vs ecosystem

- LSP awareness (recommended as companion, not bundled — principle 1)

---

## Not worth building

**External LLM review in planning** — Deep Trilogy does this, adds latency and
cost. Our KB approach is more persistent.

**Autonomous looping** — Ralph Wiggum pattern, explicitly against design
principle 9.

**Hooks-based TDD enforcement** — TDD Guard and Superpowers use Claude Code hooks
to block file modifications. Requires platform-specific hooks infrastructure —
violates principle 1. Rules-based enforcement is reliable enough in practice.

**Coverage gating** — requires language-specific coverage tools. Violates
principle 1. Step 2e (missing test heuristic) is the language-agnostic proxy.

**Context7 / live docs** — requires MCP server. Violates principle 1.

## Closed gaps (previously listed)

- ~~/decisions list/filter~~ — shipped v0.2.4
- ~~Hooks integration~~ — dropped, violates principle 1
- ~~Coverage gating~~ — dropped, violates principle 1
- ~~Live docs in domain analysis~~ — dropped, violates principle 1
