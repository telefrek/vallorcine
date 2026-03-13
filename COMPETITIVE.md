# vallorcine — Competitive Landscape

Market positioning and ecosystem context for prioritisation decisions.
Updated during marketplace research sessions, not every development session.

*Last updated: 2026-03-13*

---

## Closest competitors

**Superpowers** — TDD + lifecycle, in official marketplace.

**Deep Trilogy** — staged decompose→plan→implement with TDD, three separate plugins.

**claude-plugin-adr** — ADR templates + shell scripts, no deliberation loop.

---

## Where vallorcine leads

- Crash recovery (unique)
- Token-aware work unit splitting (unique)
- KB↔pipeline integration (unique)
- Deliberation loop on ADRs (unique)
- Sequential scoping interview (unique)

---

## Confirmed gaps vs ecosystem

- Hooks integration
- LSP awareness
- /decisions list/filter command
- Coverage gating
- Live docs in domain analysis

---

## Not worth building

**External LLM review in planning** — Deep Trilogy does this, adds latency and
cost. Our KB approach is more persistent.

**Autonomous looping** — Ralph Wiggum pattern, explicitly against design
principle 8.
