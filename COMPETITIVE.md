# vallorcine — Competitive Landscape

Market positioning and ecosystem context for prioritisation decisions.
Updated during marketplace research sessions, not every development session.

*Last updated: 2026-03-31*

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

**New since March 2026:** A fourth concern — **code analysis and auditing** —
has emerged as a competitive dimension. Claude Code Security (Anthropic),
OpenAI Codex Security, and Qodo 2.0 all ship multi-agent or multi-pass
analysis. Vallorcine's audit pipeline operates in this space but with a
fundamentally different architecture (spec-driven, topology-aware, knowledge-
compounding). See "Analysis and auditing" section below.

---

## Closest competitors

### Tier 1 — Methodology enforcers

**Superpowers** (obra) — 42K GitHub stars (up from 29K in Feb). Accepted into
official Anthropic marketplace January 2026. TDD (red-green-refactor), Socratic
brainstorming, micro-task planning, subagent-driven code review, systematic
debugging. Free, MIT. The dominant structured-development plugin by community
size. Has not added analysis, auditing, or knowledge persistence capabilities.
*Gap vs vallorcine: no KB, no ADRs, no curation, no retrospectives, no session
continuity, no token tracking, no code analysis pipeline. Session-scoped — each
feature starts from zero.*

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

**Kiro** (AWS, 2026) — agentic IDE using EARS (Easy Approach to Requirements
Syntax) notation for structured, testable requirements. Workflow: requirements →
user stories → acceptance criteria → technical design → implementation tasks.
Agent hooks trigger on file save/create/delete to keep specs and code in sync.
Deeply integrated with AWS services. Closest shipping product to spec-as-source-
of-truth, but specs drive code generation, not analysis passes or auditing.
*Gap vs vallorcine: specs don't drive adversarial analysis. No multi-pass
auditing. No persistent KB or knowledge compounding. IDE-locked (not CLI).
AWS-ecosystem coupling. No topology-aware analysis.*

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

**Gemini Code Assist** — added "memory" for coding standards/style/best
practices that persists across reviews. Preference memory, not analytical
knowledge. Review-scoped, not development-scoped.

**Beads** (framework) — stores task graphs and planning data as versioned JSONL
in git. Agent memory survives across sessions. Closest to vallorcine's KB for
task planning, but not for bug-finding or analytical knowledge.

**claude-cognitive** — file attention scoring via hooks. Solves large-codebase
file selection, not knowledge persistence or structured decisions.

**Claude Code auto-memory** — built-in CLAUDE.md self-writes. 200-line limit,
blunt context loading, no ADR concept. Passive and unstructured.

### Analysis and auditing (new competitive dimension)

**Claude Code Security** (Anthropic, Feb 2026) — the most significant new
entrant. Multi-stage verification: (1) initial scan tracing data flows across
files, identifying complex multi-component vulnerability patterns, (2) independent
red-vs-blue adversarial verification where a second agent challenges each finding
through exploitability testing, mitigation detection, and logical consistency
checks. Found 500+ vulnerabilities in production open-source codebases. Available
to Enterprise/Team customers. This is genuine multi-pass adversarial analysis.
*Gap vs vallorcine: security-focused only (not general bug categories).
Two passes (scan + verify), not N passes with progressive refinement. No spec
integration — findings aren't grounded in behavioral contracts. No topology-aware
clustering — scans by data flow trace, not by construct neighborhood. No
persistent knowledge — each scan starts fresh. No domain-lens scoping.*
*Watch closely: Anthropic has the resources to expand this into general-purpose
analysis. If they add spec integration or persistent knowledge, the gap narrows.*

**OpenAI Codex Security** (March 2026, research preview) — builds project
context, creates editable threat model, identifies complex vulnerabilities,
proposes fixes. Scanned 1.2M commits, found 792 critical and 10,561 high-
severity findings. Less transparency about methodology.
*Gap vs vallorcine: security-focused. Unclear whether truly multi-pass or
single-pass with post-hoc classification. No persistent knowledge.*

**Qodo 2.0** (Feb 2026) — multi-agent architecture with 15+ specialized review
agents (correctness, security, performance, observability, requirements). Each
agent contributes domain-specific findings on the same PR. F1 score 60.1%,
highest recall at 56.7% on their benchmark.
*Gap vs vallorcine: multi-agent parallel (domain specialization) not multi-pass
sequential (progressive refinement). PR-scoped, not codebase-scoped. No
topology awareness. No persistent knowledge compounding. No spec integration.
But: domain-specialized agents are the closest thing to domain-lens analysis
in a shipping product. Watch for expansion from PR-scope to codebase-scope.*

**Sourcery** — "series of AI code reviewers each with different specialties"
plus validation pass for false positive reduction. Multi-angle review with
post-hoc filtering. Similar approach to Qodo but less mature.

**Trail of Bits Security Skills** (Claude Code plugin) — `audit-context-building`
skill with line-by-line analysis, First Principles reasoning, invariant/assumption
tracking, cross-function flow tracing. Structured single-pass analysis with
methodological rigor. Security-focused.
*Gap vs vallorcine: single pass, security-focused, no clustering, no persistent
knowledge. But: invariant/assumption tracking is conceptually adjacent to our
expectation extraction.*

**Snyk DeepCode AI** — hybrid symbolic + ML engine combining flow-sensitive
analysis, data-flow analysis, and symbolic execution. Trained on 25M+ data
flow cases. Specifically detects concurrency bugs, missing-check
vulnerabilities, memory safety issues. 80% fix accuracy.
*Not LLM-based — trained models, not reasoning. Domain-aware detection
(knows what a concurrency bug looks like) but not domain-scoped analysis.
Complementary rather than competitive.*

**CodeRabbit** — added "code graph analysis" in 2026 for cross-file dependency
understanding. Expanding context graph with runtime traces, CI/CD data,
observability signals. 46% accuracy on real-world runtime bugs. Combines AST
evaluation, SAST, and generative AI. Ingests past PRs and chat-based learnings.
*Dependency-graph-level awareness, not topology-aware clustering. Accumulated
review preferences, not analytical knowledge.*

### Adjacent — Architecture governance

**Archgate** — turns ADRs into executable rules with CI enforcement. Each ADR
gets a `.rules.ts` companion with automated checks. Runs in CI, pre-commit, and
feeds context to AI agents. Editor plugins for Claude Code and Cursor.
*Complementary, not competitive — handles enforcement (after the decision) but
not the decision-making process. Potential integration partner.*

**GitHub Spec Kit** (official GitHub, open source, 72.7K stars) — scaffolding
for spec-driven workflows. Python CLI with templates for 22+ AI agent platforms.
v0.1.4 as of Feb 2026. Provides persistent project context through structured
spec documents but does not do analysis or bug prevention — it is scaffolding,
not a pipeline.
*Interesting as a standard-setter for spec formats. Watch whether it evolves
from scaffolding to analysis.*

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

**Augment Code** — indexes 400K+ files to build dependency graphs and
architectural pattern models. Context Engine understands API contracts across
repositories, can flag contract violations during review. Closest to "spec as
live contract" by inferring specifications from codebase rather than explicit
authoring. Structural knowledge, not analytical findings.

**Aider** — open-source CLI pair programmer. Deep git integration, auto-commits,
automatic lint+test after changes. Reactive testing (run after changes) not
prescriptive (write first). No KB, no ADRs, no methodology. Model-agnostic.

**Continue.dev** — open-source for VS Code/JetBrains. AI checks as markdown
files that show up as GitHub status checks. CI/CD native. Review-time focus,
not development-time methodology.

**GitHub Copilot** — issue-to-PR pipeline via Coding Agent + Workspace. Self-
review, security scanning, semantic code search (March 2026). General-purpose
agent, not methodology-enforcing. Locked to GitHub ecosystem.

**CodePrism** (rustic-ai, open source, MIT) — Rust-powered MCP server building
Universal AST graph representation. 1000+ files/second indexing, graph-based
queries, system-level relationship understanding. Query engine, not analysis
pipeline — provides the graph but doesn't cluster or analyze. 100% AI-generated
code. Interesting as potential infrastructure.

**CodeQL** — compiles source to queryable relational database (AST, data flow,
control flow). QL queries can express topology-aware patterns. Closest to real
topology awareness in a shipping tool, but requires manual query authoring — no
automatic topology detection or clustering.

### Adjacent — Academic frontier

**LLMAO** (squaresLab) — fine-tuned LLMs (350M-16B params) for line-level fault
localization without test coverage. Improves Top-1 over MLFL baselines by
2.3%-54.4%. First test-free LLM fault localization.

**AutoFL** (COINSE) — LLM navigates codebase via function calls to localize
faults from a single failing test. Outperforms spectrum-based fault localization
by 338%. Generates explanations alongside fault locations.

**GNN defect prediction** (Nature Scientific Reports 2025) — integrated graph
neural network using multi-level graph representations (AST, CFG, DFG) with
dual-branch attention-based GNN for joint defect prediction and code quality
assessment. Academic frontier, not shipped.

**Spec-driven development paper** (arxiv 2602.00180, Feb 2026) — frames
theoretical basis for spec-driven AI development. Notes LLMs generate vulnerable
code at 9.8%-42.1% across benchmarks; explicit specs significantly reduce this.
Validates the approach but doesn't describe a pipeline.

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
| Spec-driven auditing | Specs drive analysis passes, not just code generation | Bugs caught by spec falsification before code is written |
| Topology-aware clustering | Multi-dimensional construct graphs clustered by domain lens | Analysis targets where bugs actually live, not structural proximity |
| Domain-lens analysis | Concern-scoped passes (concurrency, state, contracts, etc.) | Prunes irrelevant domains, focuses analysis by concern type |
| Analytical knowledge compounding | KB entries from prior audits improve future audits | Pipeline gets smarter per feature — 3 patterns from features 1-2 caught bugs in feature 4 |
| Multi-pass progressive audit | 5-pass pipeline where each pass informs the next | 92% bug detection at 60% cost vs single-pass |

### The compounding advantage

No competitor has a continuous improvement layer. The landscape splits into
tools that help you build (then forget) and tools that remember (but never
review). Vallorcine does both:

- **Features compound the knowledge** — domain analysis reads the KB, planning
  reads ADRs, retrospectives write back to both.
- **Curation keeps it honest** — `/curate` detects stale decisions, knowledge
  gaps, implicit dependencies, and orphaned areas between features.
- **Audits compound analytically** — KB adversarial findings and tendency
  profiles from prior features improve future audit detection rates.
- **The result:** a codebase that gets smarter over time — not just during
  active feature work, but between features too.

### Head-to-head comparison

| Capability | vallorcine | Claude Code Security | Qodo 2.0 | Kiro | Superpowers | Copilot |
|---|---|---|---|---|---|---|
| TDD pipeline | Enforced | No | No | No | Enforced | No |
| Spec authoring | Adversarial 2-pass | No | No | EARS notation | No | No |
| Spec-driven analysis | Specs drive audit | No | No | Specs drive codegen | No | No |
| Code analysis | Topology-aware, domain-lens | Data flow tracing | 15 specialized agents | No | No | Security scanning |
| Multi-pass audit | 5-pass progressive | 2-pass (scan+verify) | Parallel (not sequential) | No | No | Single-pass |
| Domain-lens scoping | Automatic detection + pruning | Security only | Agent specialization | No | No | No |
| Knowledge base | Curated KB | No | No | No | No | No |
| Knowledge compounding | Cross-feature | No | PR learnings | No | No | No |
| Architecture decisions | Deliberation loop | No | No | No | No | No |
| Curation | Correlation engine | No | No | No | No | No |
| Crash recovery | Checkpoint-based | N/A | No | No | No | No |
| Composable stages | Yes (20+ commands) | N/A | N/A | Partial | Partial | Workspace |
| Scope | Codebase | Codebase | PR | Project | Session | PR/Issue |
| Community size | Small | Anthropic backing | Growing | AWS backing | 42K stars | Massive |

---

## Competitive threats — what to watch

### High priority (could erode lead within 6 months)

**Claude Code Security expanding beyond security.** Anthropic's two-pass
adversarial model (scan + red/blue verification) is architecturally sound. If
they add: (1) spec integration, (2) persistent knowledge from prior scans, or
(3) domain-scoped analysis beyond security, the gap narrows significantly.
Anthropic has the resources and the platform access to move fast here.
*Mitigation: our topology-aware clustering and knowledge compounding are hard
to replicate without the empirical validation infrastructure (diagnostic tools,
cost models, pass-over-pass yield curves). Stay ahead on pipeline sophistication.*

**Qodo expanding from PR-scope to codebase-scope.** Their 15 specialized agents
are the closest shipping implementation of domain-lens analysis. Currently
PR-scoped. If they ship codebase-scoped analysis with persistent knowledge
across PRs, they become a direct competitor on the analysis dimension.
*Mitigation: our domain lenses are topology-aware (driven by construct graph
structure), not just agent specialization (fixed domains regardless of code).
This is a deeper integration that's harder to replicate.*

**Kiro adding analysis to its spec workflow.** Kiro already has EARS specs
and agent hooks for spec-code sync. If they add adversarial spec falsification
or spec-driven auditing, they compete directly on spec-driven bug prevention.
*Mitigation: our adversarial authoring (two-pass falsification with enforcement
path tracing) is validated. Kiro's specs drive generation, not analysis — the
architectural shift to analysis-driving-specs is non-trivial.*

### Medium priority (watch, no immediate action needed)

**GitHub Spec Kit becoming a standard.** 72.7K stars, templates for 22+
platforms. If it defines the standard spec format, tools will build around it.
Vallorcine's `.spec/` format is internal — may need to interop with Spec Kit
format if it becomes dominant.

**CodeRabbit adding topology.** Their code graph analysis is dependency-level
today. If they add relationship-type-differentiated topology (state sharing vs
execution flow vs contracts), they could offer graph-based analysis without
vallorcine's full pipeline.

**Academic tools shipping.** AutoFL (338% improvement over spectrum-based FL)
and LLMAO (test-free fault localization) are research tools today. If they ship
as products or get integrated into Copilot/Cursor/Qodo, the general "AI finds
bugs" capability becomes commodity. Our edge is the pipeline architecture
(spec-driven, topology-aware, knowledge-compounding), not the raw analysis.

### Low priority (structurally different approaches)

**Snyk DeepCode AI** — trained models, not LLM reasoning. Complementary.

**CodeQL** — manual query authoring. Powerful but requires expertise. Different
user population.

**Augment Code** — inferred contracts from codebase, not authored specs. Different
philosophy (discover vs prescribe).

---

## Confirmed gaps vs ecosystem

| Gap | Who has it | Severity | Our position |
|---|---|---|---|
| Community / distribution | Superpowers (42K), feature-dev (89K) | High | Feature-complete; distribution is the bottleneck |
| Official marketplace listing | Superpowers, feature-dev | High | Should prioritise — primary discovery channel |
| Spec format interop | GitHub Spec Kit (72.7K stars) | Medium | Watch — may need to interop if it becomes standard |
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

**Security-specific scanning** — Claude Code Security and Codex Security own
this space with platform-level resources. Compete on general bug-finding quality
and knowledge compounding, not on security vulnerability databases.

---

## Potential partnerships

**Archgate** — their ADR enforcement complements our ADR decision-making.
Vallorcine's `/architect` helps you make the decision; Archgate's CI rules
enforce it. Worth exploring integration path.

**CodePrism** — their Rust-powered graph infrastructure (1000+ files/second)
could provide the construct graph that our card construction pass currently
asks the LLM to build. If their graph representation is rich enough, it
could replace or supplement the execution/state sweeps with ground-truth
data. Worth evaluating for cost reduction.

**GitHub Spec Kit** — if their spec format becomes standard, our `/spec-author`
could output Spec Kit-compatible format alongside `.spec/` internal format.
Interop, not replacement.

---

## Closed gaps (previously listed)

- ~~/decisions list/filter~~ — shipped v0.2.4
- ~~Hooks integration~~ — dropped, violates principle 1
- ~~Coverage gating~~ — dropped, violates principle 1
- ~~Live docs in domain analysis~~ — dropped, violates principle 1
