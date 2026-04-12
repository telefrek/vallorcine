# vallorcine — Competitive Landscape

Market positioning and ecosystem context for prioritisation decisions.
Updated during marketplace research sessions, not every development session.

*Last updated: 2026-04-12*

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

Two additional competitive dimensions have emerged since early 2026:

**Tier 4: Code analysis and auditing** — Claude Code Security (Anthropic),
Qodo 2.0, and Trail of Bits all ship multi-agent or multi-pass analysis.
Vallorcine's audit pipeline operates here with a fundamentally different
architecture (spec-driven, topology-aware, knowledge-compounding).

**Tier 5: Spec-driven development** — Martin Fowler's team published a
comparison of Kiro, GitHub Spec Kit, and Tessl as the three SDD tools (2026).
This is now a recognized category. Vallorcine's spec layer goes further than
any of them — lifecycle states, displacement detection, adversarial authoring,
and specs driving audit passes rather than just code generation.

**New since April 2026:** A sixth dimension — **multi-feature work
coordination** — remains unaddressed by any competitor. Copilot Mission
Control tracks parallel tasks but has no dependency graph. Maestro-Orchestrate
decomposes single tasks across specialists. Neither computes readiness from
artifact state or coordinates specification/implementation modes across
features. Vallorcine's work layer is alone in this space.

---

## Closest competitors

### Tier 1 — Methodology enforcers

**Superpowers** (obra) — 42K GitHub stars. Accepted into official Anthropic
marketplace January 2026. TDD (red-green-refactor), Socratic brainstorming,
micro-task planning, subagent-driven code review, systematic debugging. Free,
MIT. The dominant structured-development plugin by community size.
**March-April 2026 updates:** Brainstorming reworked with hard gates — models
were skipping design and jumping to implementation, now blocked until design is
approved. Platform expansion to 6 tools: Claude Code, Cursor, OpenCode, Codex,
Gemini CLI, GitHub Copilot CLI. Still no persistent knowledge or analysis.
*Gap vs vallorcine: no KB, no ADRs, no specs, no curation, no retrospectives,
no work coordination, no code analysis pipeline. Session-scoped — each feature
starts from zero. The hard-gate addition confirms the problem we solve with
staged pipelines + idempotency, but their fix is enforcement-at-prompt-level
rather than structural separation of concerns.*

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
Deeply integrated with AWS services. **April 2026 updates:** `/quick-spec`
collapses three phases into one command; `/architecture-selection` adds
systematic architecture analysis between spec phases. Accelerates single-feature
spec workflow but does not address multi-feature coordination.
*Gap vs vallorcine: specs don't drive adversarial analysis. No spec lifecycle
states (DRAFT/APPROVED/INVALIDATED), no displacement detection, no spec revival.
No multi-pass auditing. No persistent KB or knowledge compounding. No multi-
feature work coordination. IDE-locked (not CLI). AWS-ecosystem coupling.*

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

**Maestro-Orchestrate** (josstei, 2026) — 22 specialized subagents, 4-phase
workflows (Design/Plan/Execute/Complete), parallel execution, persistent
sessions. Express vs Standard workflow paths with approval gates. Decomposes
single complex tasks across specialists — no cross-feature coordination.

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

**Knowledge graph plugins** (March 2026) — **Graphify** (codebase to persistent
knowledge graph, 71x token reduction), **Code-Review-Graph** (interactive
knowledge graph, 6.8x token reduction), **MemClaw** (per-project isolated
workspaces storing architecture decisions, conventions, task progress). These
address codebase comprehension (what does this code do?) rather than development
process knowledge (what bugs did we find, what patterns recur, what specs are
active?).

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

**Qodo 2.0/2.1** (Feb 2026, $70M raise March 2026) — multi-agent architecture
with 15+ specialized review agents (correctness, security, performance,
observability, requirements). F1 score 60.1%, highest recall at 56.7%.
**Qodo 2.1** (Feb 17, 2026) added "Continuous Learning Rules System" —
auto-discovers coding standards from the codebase, maintains them, enforces
during reviews, tracks analytics. 11% precision/recall improvement. This is
the closest analog to vallorcine's KB for review patterns, but operates at
the convention level (naming, formatting, patterns), not bug-pattern or
behavioral-specification level.
*Gap vs vallorcine: multi-agent parallel (domain specialization) not multi-pass
sequential (progressive refinement). PR-scoped, not codebase-scoped. Rules
system captures conventions, not adversarial findings or spec violations. No
topology awareness. No spec integration. But: domain-specialized agents +
persistent rules make this the most complete single competitor. Watch closely
— $70M raise means rapid expansion is likely.*

**Sourcery** — "series of AI code reviewers each with different specialties"
plus validation pass for false positive reduction. Multi-angle review with
post-hoc filtering. Similar approach to Qodo but less mature.

**Trail of Bits Security Skills** (Claude Code plugin, 94 plugins, 201 skills,
84 agents as of March 2026) — `audit-context-building` skill with line-by-line
analysis, First Principles reasoning, invariant/assumption tracking, cross-
function flow tracing. New: **Dimensional Analysis Plugin** (March 25) for
LLM-annotated types with mechanical mismatch detection. **Agentic Actions
Auditor** for CI/CD security. Claiming 200 bugs/week on targeted engagements.
Security-focused, growing rapidly.
*Gap vs vallorcine: single pass per skill, security-focused, no clustering, no
persistent knowledge. But: invariant/assumption tracking is conceptually adjacent
to our expectation extraction. Scale and breadth are impressive — 201 skills
covering many security domains. Watch for consolidation into multi-pass pipelines.*

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

### Adjacent — Architecture governance and spec-driven development

**Archgate** — turns ADRs into executable rules with CI enforcement. Each ADR
gets a `.rules.ts` companion with automated checks. Runs in CI, pre-commit, and
feeds context to AI agents. Editor plugins for Claude Code and Cursor.
*Complementary, not competitive — handles enforcement (after the decision) but
not the decision-making process. Potential integration partner.*

**GitHub Spec Kit** (official GitHub, open source, 80K+ stars) — scaffolding
for spec-driven workflows. Python CLI with templates for 24+ AI agent platforms.
VS Code companion extension for visual spec browsing. Martin Fowler's team
published a comparison of Kiro, Spec Kit, and Tessl as the three SDD tools —
**spec-driven development is now a recognized category.**
*Interesting as a standard-setter for spec formats. Specs are documents that
guide implementation — no lifecycle states, no displacement detection, no
spec-to-audit pipeline.*

**Tessl Framework** (closed beta, 2026) — the most aggressive spec approach:
spec-as-source where code is generated from specs and marked
`// GENERATED FROM SPEC - DO NOT EDIT`. Reverse-engineers specs from existing
code. Maintains 1:1 mapping between spec files and code files. Spec Registry
in open beta.
*Opposite design philosophy from vallorcine: specs replace code (generation)
vs specs guide development (collaboration). No lifecycle states, no displacement
detection, no adversarial verification. But: structurally the most comparable
approach to treating specs as first-class artifacts. Watch for evolution toward
spec lifecycle management.*

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
review, security scanning, semantic code search. **Mission Control** (GA 2026)
adds a dashboard for assigning, steering, and tracking multiple concurrent
Coding Agent tasks — "engineering manager UI for AI teammates." Tracks parallel
tasks but no dependency graph, no artifact lifecycle, no readiness computation.
General-purpose agent, not methodology-enforcing. Locked to GitHub ecosystem.

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
| **Multi-feature work coordination** | Artifact-based dependencies, computed readiness, pipeline modes | Right work happens in the right order across features |
| **Spec lifecycle management** | DRAFT→APPROVED→INVALIDATED, displacement detection, revival | Specs stay current — contradictions caught, not silently accumulated |
| **Pipeline mode decomposition** | Spec-only and impl-only modes for team parallelization | One person specs, another implements — same pipeline, different modes |
| **Interface contracts** | Specs with `kind: interface-contract` for shared surfaces | Cross-feature boundaries are specified and tracked, not assumed |
| Spec-driven auditing | Specs drive analysis passes, not just code generation | Bugs caught by spec falsification before code is written |
| Topology-aware clustering | Multi-dimensional construct graphs clustered by domain lens | Analysis targets where bugs actually live, not structural proximity |
| Domain-lens analysis | Concern-scoped passes (concurrency, state, contracts, etc.) | Prunes irrelevant domains, focuses analysis by concern type |
| Analytical knowledge compounding | KB entries from prior audits improve future audits | Pipeline gets smarter per feature — 3 patterns from features 1-2 caught bugs in feature 4 |
| Multi-pass progressive audit | 5-pass pipeline where each pass informs the next | 92% bug detection at 60% cost vs single-pass |
| Crash recovery | Checkpoint-based resume from exact substage | Sessions crash — work is never lost |
| Token-aware work unit splitting | Splits features when context cost exceeds 15K | Large features don't degrade output quality |
| KB↔pipeline integration | Research feeds domain analysis, planning, testing | Knowledge compounds — 5th feature is faster than 1st |
| Deliberation loop on ADRs | Constraint profiling → candidates → evaluation → confirmation | Decisions are governed, not assumed |
| Codebase curation | Cross-session quality review via correlation engine | Stale decisions, knowledge gaps, spec drift detected between features |
| Composable commands | Each stage is a separate slash command | Users control granularity — skip, repeat, or reorder stages |
| Retrospectives | Post-feature learning that feeds back into KB/ADRs | The project gets smarter with each feature |

### The compounding advantage

No competitor has a continuous improvement layer. The landscape splits into
tools that help you build (then forget) and tools that remember (but never
review). Vallorcine does both:

- **Features compound the knowledge** — domain analysis reads the KB, planning
  reads ADRs and specs, retrospectives write back to both.
- **Work groups coordinate the sequence** — artifact-based dependencies ensure
  specs are approved before implementation starts, interface contracts are
  settled before consumers build against them.
- **Specs compound the contracts** — displacement detection ensures new behavior
  doesn't silently contradict existing guarantees. Revival reuses invalidated
  specs as reference input for their replacements.
- **Audits compound analytically** — KB adversarial findings and tendency
  profiles from prior features improve future audit detection rates.
- **Curation keeps it honest** — 17 analyses detect stale decisions, spec-code
  drift, knowledge gaps, work group stalls, and orphaned areas.
- **The result:** a codebase that gets smarter over time — not just during
  active feature work, but between features too.

### The work coordination gap

The competitive landscape has tools for task decomposition (Copilot Mission
Control, Maestro-Orchestrate, Deep Trilogy) but none for **artifact-aware
work coordination**. The distinction:

- **Task decomposition** splits a goal into steps and tracks completion.
- **Work coordination** tracks dependencies on specific artifacts at specific
  states — a spec must be APPROVED before an implementation WD becomes READY.
  Completing one WD automatically unblocks others by producing the artifacts
  they depend on.

This is the gap between "assign tasks to agents" and "ensure the right work
happens in the right order." Pipeline modes (spec-only, impl-only) extend this
to team workflows where different people own different phases.

### Head-to-head comparison

| Capability | vallorcine | Qodo 2.1 | Kiro | Claude Code Security | Tessl | Superpowers | Copilot |
|---|---|---|---|---|---|---|---|
| TDD pipeline | Enforced | No | No | No | No | Enforced | No |
| Spec authoring | Adversarial 2-pass | No | EARS notation | No | From code (generated) | No | No |
| Spec lifecycle | DRAFT/APPROVED/INVALIDATED | No | 3 phases (no states) | No | 1:1 mapping | No | No |
| Displacement detection | Automatic | No | No | No | No | No | No |
| Spec-driven analysis | Specs drive audit | No | Specs drive codegen | No | Specs drive codegen | No | No |
| Code analysis | Topology-aware, domain-lens | 15 specialized agents | No | Data flow tracing | No | No | Security scanning |
| Multi-pass audit | 5-pass progressive | Parallel (not sequential) | No | 2-pass (scan+verify) | No | No | Single-pass |
| Multi-feature coordination | Artifact deps + readiness | No | No | No | No | No | Mission Control (no deps) |
| Pipeline modes | Spec-only / impl-only | No | No | No | No | No | No |
| Knowledge base | Curated KB | Rules system (conventions) | No | No | No | No | No |
| Knowledge compounding | Cross-feature, adversarial | Convention rules (11% improvement) | No | No | No | No | No |
| Architecture decisions | Deliberation loop | No | /architecture-selection | No | No | No | No |
| Curation | Correlation engine (17 analyses) | Rule conflict detection | No | No | No | No | No |
| Crash recovery | Checkpoint-based | N/A | No | N/A | No | No | No |
| Composable stages | Yes (40+ commands) | N/A | Partial | N/A | No | Partial | Workspace |
| Scope | Codebase | PR | Project | Codebase | Project | Session | PR/Issue |
| Funding / community | Small | $70M raise | AWS backing | Anthropic | Closed beta | 42K stars | Massive |

---

## Competitive threats — what to watch

### High priority (could erode lead within 6 months)

**Qodo post-$70M raise.** Most complete single competitor: 15 specialized
agents + persistent rules system + convention learning. $70M means rapid
expansion. If they add: (1) codebase-scoped analysis (not just PR), (2) rules
that capture bug patterns (not just conventions), or (3) multi-feature
coordination, the gap narrows significantly on multiple dimensions at once.
*Mitigation: our lenses are topology-aware (driven by construct graph), not
agent specialization (fixed domains). Our KB captures adversarial findings and
behavioral patterns, not naming conventions. Hard to replicate without the
spec → audit → KB feedback loop.*

**Claude Code Security expanding beyond security.** Anthropic's two-pass
adversarial model (scan + red/blue verification) is architecturally sound. If
they add: (1) spec integration, (2) persistent knowledge from prior scans, or
(3) domain-scoped analysis beyond security, the gap narrows significantly.
Anthropic has the resources and the platform access to move fast here.
*Mitigation: our topology-aware clustering and knowledge compounding are hard
to replicate without the empirical validation infrastructure (diagnostic tools,
cost models, pass-over-pass yield curves). Stay ahead on pipeline sophistication.*

**Kiro adding analysis to its spec workflow.** Kiro already has EARS specs,
agent hooks for spec-code sync, and now `/architecture-selection`. If they add
adversarial spec falsification, spec lifecycle states, or spec-driven auditing,
they compete directly on spec-driven bug prevention.
*Mitigation: our spec lifecycle (displacement, revival, interface contracts)
and adversarial authoring (two-pass falsification with enforcement path tracing)
are validated. Kiro's specs drive generation, not analysis — the architectural
shift to analysis-driving-specs is non-trivial.*

### Medium priority (watch, no immediate action needed)

**Tessl's spec-as-source approach gaining traction.** If Tessl exits closed
beta with strong spec lifecycle management, they compete on "specs as first-
class artifacts" even though the philosophy differs (generation vs guidance).
Martin Fowler's comparison legitimizes the SDD category — watch whether Tessl's
approach or the guidance approach wins mindshare.

**GitHub Spec Kit becoming a standard.** 80K+ stars, templates for 24+
platforms, VS Code extension. If it defines the standard spec format, tools
will build around it. Vallorcine's `.spec/` format is internal — may need to
interop with Spec Kit format if it becomes dominant.

**Trail of Bits scaling to 200+ skills.** 201 skills across 94 plugins, 200
bugs/week on targeted engagements. Individual skills are single-pass, but the
breadth is impressive. If they consolidate into multi-pass pipelines or add
persistent knowledge across audit engagements, the security analysis gap narrows.

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
| Spec format interop | GitHub Spec Kit (80K+ stars), Tessl | Medium | Watch — may need to interop if SDD format standardises |
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
