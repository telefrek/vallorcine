# vallorcine — Competitive Landscape

Market positioning and ecosystem context for prioritisation decisions.
Updated during marketplace research sessions, not every development session.

*Last updated: 2026-03-18*

---

## Market context

The Claude Code plugin ecosystem has grown rapidly — 834+ plugins across 43
marketplaces as of January 2026, with estimates of 9,000+ extensions by
February. The official Anthropic marketplace is the primary discovery channel.

The competitive landscape splits into three tiers:

**Tier 1: Methodology enforcers** — opinionated about *how* you develop.
TDD-first, structured stages, development discipline.

**Tier 2: Workflow automators** — opinionated about *what steps* you take.
Phase-based pipelines but not methodology-enforcing.

**Tier 3: Memory / knowledge tools** — solve context persistence across
sessions. No development methodology.

**Vallorcine spans all three tiers.** No other tool does. That is the
positioning story: *Superpowers makes you write tests first. Vallorcine makes
your 5th feature faster than your 1st.*

---

## Closest competitors

### Tier 1 — Methodology enforcers

**Superpowers** (obra) — 29K GitHub stars. Accepted into official Anthropic
marketplace January 2026. TDD (red-green-refactor), Socratic brainstorming,
micro-task planning, subagent-driven code review, systematic debugging. Free,
MIT. The dominant structured-development plugin by community size.
*Gap vs vallorcine: no KB, no ADRs, no curation, no retrospectives, no session
continuity, no token tracking. Session-scoped — each feature starts from zero.*

**TDD Guard** (nizos) — hooks-based TDD enforcement. Blocks file modifications
when tests are skipped. Supports Jest, Vitest, pytest, Go, Rust. Narrow scope —
enforcement only, no workflow.

**ATDD** (swingerman) — acceptance test driven development with team
orchestration (team lead coordinating specialist agents). Niche.

### Tier 2 — Workflow automators

**feature-dev** (Anthropic official) — 89K installs. 7-phase structured
workflow: requirements → exploration → architecture → implementation → testing →
review → documentation. Official Anthropic backing makes it the "safe default."
*Gap vs vallorcine: monolithic (one command, not composable), no persistent KB,
no ADRs, no curation, no crash recovery, no work unit splitting, no session
continuity.*

**Deep Trilogy** (Pierce Lamb) — three plugins: `/deep-project` (decomposition),
`/deep-plan` (planning with multi-LLM review), `/deep-implement` (TDD with
adversarial self-review). Strong on complex project planning. High context
overhead.

**claude-code-workflows** (shinpr) — multi-stage pipeline with fresh agent
contexts per phase. Similar staged approach, no KB layer.

**Jamie-BitFlight/claude_skills** — 25 modular plugins, language-agnostic SAM
pipeline. Breadth over depth; no ADR or KB integration.

**Shipyard** — Superpowers-style lifecycle + IaC validation (Terraform, Ansible,
Docker, K8s) + security auditing. Positioned for production/DevOps workflows.

**claude-code-workflow-orchestration** (barkain) — multi-step workflow
orchestration with task decomposition, parallel agent execution, specialised
agent delegation. Native plan mode integration.

### Tier 3 — Memory / knowledge

**claude-mem** (thedotmack) — SQLite + ChromaDB, automatic capture via session
hooks. Semantic summaries, hybrid search with vector embeddings. Claims ~10x
token efficiency. Push-model (always loaded). Has a docs site and dedicated
website.
*Gap vs vallorcine: passive capture, opaque storage, no structure, no ADR
concept. Accumulates but never curates.*

**memsearch** (Zilliz) — markdown-first memory system. Session summaries +
semantic search via local ONNX embeddings (no API key). Git-friendly. Runs
memory recall in a forked subagent with isolated context window.
*Gap vs vallorcine: transparent storage but session summaries, not structured
decisions. No curation or review of accumulated knowledge.*

**AZKG** (witt3rd) — agent-maintained Zettelkasten knowledge management.
Automatic relationship discovery, atomic notes from conversations. Closest
to vallorcine's KB concept but auto-capture rather than curated research.

**claude-supermemory** (SuperMemory AI) — persistent memory with real-time
learning across sessions.

**claude-cognitive** — file attention scoring via hooks. Solves large-codebase
file selection, not knowledge persistence or structured decisions.

**Claude Code auto-memory** — built-in CLAUDE.md self-writes. 200-line limit,
blunt context loading, no ADR concept. Passive and unstructured.

### Adjacent — Architecture governance

**Archgate** — turns ADRs into executable rules with CI enforcement. Each ADR
gets a `.rules.ts` companion with automated checks. Runs in CI, pre-commit, and
feeds context to AI agents. Editor plugins for Claude Code and Cursor.
*Complementary, not competitive — handles enforcement (after the decision) but
not the decision-making process. Potential integration partner.*

**claude-plugin-adr** (andronics) — ADR templates + shell scripts, no
deliberation loop.

**blueprint-derive-adr** (laurigates) — derives ADRs from existing projects by
analysing code structure and dependencies. Automates MADR-style generation.

**adr-management** (melodic-software) — manages ADR lifecycle. Available on
playbooks.com.

### Adjacent — Broader ecosystem

**Cursor** — AI IDE with rules system (`.cursor/rules/*.mdc`), plan mode, agent
workflows, parallel agents. Huge user base. No built-in TDD enforcement, no KB,
no ADRs, no curation. General-purpose IDE, not methodology.

**Windsurf** (Cognition AI, formerly Codeium) — AI IDE with "Cascade" agentic
system. Markdown-based Workflows deployable org-wide for process enforcement.
Enterprise play. No TDD pipeline, no KB, no ADRs, no curation.

**Aider** — open-source CLI pair programmer. Deep git integration, auto-commits,
automatic lint+test after changes. Reactive testing (run after changes) not
prescriptive (write first). No KB, no ADRs, no methodology. Model-agnostic.

**Continue.dev** — open-source for VS Code/JetBrains. AI checks as markdown
files that show up as GitHub status checks. CI/CD native. Review-time focus,
not development-time methodology.

**GitHub Copilot** — issue-to-PR pipeline via Coding Agent + Workspace. Self-
review, security scanning, semantic code search (March 2026). General-purpose
agent, not methodology-enforcing. Locked to GitHub ecosystem.

**Qodo** (formerly CodiumAI) — test generation, code review, quality workflows.
Test-first philosophy. Strong on testing but doesn't provide KB, ADRs, curation,
or phased development. Model-agnostic.

---

## Where vallorcine leads

### Unique differentiators (no competitor has these)

| Differentiator | What it means | Why it matters |
|---|---|---|
| Crash recovery | Checkpoint-based resume from exact substage | Sessions crash — work is never lost |
| Token-aware work unit splitting | Splits features when context cost exceeds 15K | Large features don't degrade output quality |
| KB↔pipeline integration | Research feeds domain analysis, planning, testing | Knowledge compounds — 5th feature is faster than 1st |
| Deliberation loop on ADRs | Constraint profiling → candidates → evaluation → confirmation | Decisions are governed, not assumed |
| Sequential scoping interview | Structured requirements gathering with confirmation | Scope is locked before work begins |
| Codebase curation | Cross-session quality review via correlation engine | Stale decisions, knowledge gaps, drift detected between features |
| Composable commands | Each stage is a separate slash command | Users control granularity — skip, repeat, or reorder stages |
| Retrospectives | Post-feature learning that feeds back into KB/ADRs | The project gets smarter with each feature |

### The compounding advantage

No competitor has a continuous improvement layer. The landscape splits into
tools that help you build (then forget) and tools that remember (but never
review). Vallorcine does both:

- **Features compound the knowledge** — domain analysis reads the KB, planning
  reads ADRs, retrospectives write back to both.
- **Curation keeps it honest** — `/curate` detects stale decisions, knowledge
  gaps, implicit dependencies, and orphaned areas between features.
- **The result:** a codebase that gets smarter over time — not just during
  active feature work, but between features too.

### Head-to-head comparison

| Capability | vallorcine | Superpowers | feature-dev | Cursor | Windsurf | Copilot |
|---|---|---|---|---|---|---|
| TDD pipeline | Enforced | Enforced | Phase-based | No | No | No |
| Knowledge base | Curated KB | No | No | No | No | No |
| Architecture decisions | Deliberation loop | No | No | No | No | No |
| Curation | Correlation engine | No | No | No | No | No |
| Composable stages | Yes (20+ commands) | Partial | No (monolithic) | Plan mode | Workflows | Workspace |
| Crash recovery | Checkpoint-based | No | No | No | No | No |
| Session continuity | Resume + coordinate | No | No | No | No | No |
| Retrospectives | KB/ADR feedback | No | No | No | No | No |
| Token tracking | Per-stage actuals | No | No | No | No | No |
| Community size | Small | 29K stars | 89K installs | Massive | Large | Massive |
| Marketplace listing | Not yet | Official | Official | N/A | N/A | N/A |

---

## Confirmed gaps vs ecosystem

| Gap | Who has it | Severity | Our position |
|---|---|---|---|
| Community / distribution | Superpowers (29K), feature-dev (89K) | High | Feature-complete; distribution is the bottleneck |
| Official marketplace listing | Superpowers, feature-dev | High | Should prioritise — primary discovery channel |
| CI/CD integration | Archgate, Continue, Copilot | Medium | Out of scope (principle 1), Archgate is complementary |
| Org-wide deployment | Windsurf Workflows, Cursor team rules | Medium | Not our audience yet (single-developer focus) |
| Auto-capture memory | claude-mem, memsearch | Low | Deliberate design choice — curated > captured |
| LSP awareness | Cursor, Windsurf (native) | Low | Recommended as companion, not bundled (principle 1) |

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

**Auto-capture memory** — claude-mem/memsearch approach. Passive capture
accumulates noise. Our curated KB is a deliberate design choice — structured
research over session summaries.

**Multi-model support** — we're a Claude Code plugin. This is our platform.

---

## Potential partnerships

**Archgate** — their ADR enforcement complements our ADR decision-making.
Vallorcine's `/architect` helps you make the decision; Archgate's CI rules
enforce it. Worth exploring integration path.

---

## Closed gaps (previously listed)

- ~~/decisions list/filter~~ — shipped v0.2.4
- ~~Hooks integration~~ — dropped, violates principle 1
- ~~Coverage gating~~ — dropped, violates principle 1
- ~~Live docs in domain analysis~~ — dropped, violates principle 1
