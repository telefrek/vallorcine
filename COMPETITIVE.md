# vallorcine — Competitive Landscape

Market positioning and ecosystem context for prioritisation decisions.
Updated during marketplace research sessions, not every development session.

*Last updated: 2026-04-21*

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

**Multi-feature work coordination** — the sixth dimension — remains
unaddressed by any shipping competitor. Copilot Mission Control (now an
in-repo "Agents tab" as of Jan 2026) tracks parallel tasks but has no
dependency graph. Maestro-Orchestrate decomposes single tasks across
specialists. Cursor 3's Agents Window (Apr 2026) and Google Antigravity's
"Manager view" both surface parallel-agent UI but without artifact
lifecycle or readiness computation. Vallorcine's work layer is alone in
this space — but the *agent-orchestration UI* category it sits adjacent to
is becoming crowded.

**Significant shifts since the 2026-04-12 baseline (research refreshed
2026-04-21):**

- **Methodology-plugin space went mainstream.** Superpowers grew 42K → 163K
  stars (~4x in 5 weeks); feature-dev installs 89K → ~176K (~2x). The
  "niche methodology tool" framing no longer applies to competitors — but
  vallorcine is still not listed on the official Anthropic marketplace.
  Distribution gap is *wider*, not narrower.
- **Qodo 2.1 (Feb 17) already closed one of our flagged narrowing conditions.**
  Their new Rules System is codebase-indexed (not PR-scoped) and learns from
  actual codebases, not just PR feedback. The baseline's "PR-scoped not
  codebase-scoped" framing is now incorrect.
- **Cursor 3 (Apr 2) repositioned as agent-manager** with worktree-parallel
  execution, best-of-N model compare, and Bugbot rules that *self-improve
  from PR feedback* — the closest any IDE-scale tool has come to
  vallorcine's knowledge-compounding loop.
- **New direct-lane entrant: GSD** (~48K stars) positions explicitly on
  spec-driven development + context engineering. Same lane as vallorcine.
- **Cross-reference-aware ADR tooling** appeared in Ars Contexta (`/reflect`,
  `/reweave`). Our decision/KB cross-linking is no longer conceptually
  unique at the command level, though the spec-integration + adversarial
  authoring layers remain distinctive.
- **Auto-capture memory became a category** — claude-mem at 46.1K stars.
  Vallorcine's KB differentiation now lives in curation + cross-linking,
  not just "sessions remember things."
- **Kiro CLI 2.0 (Apr 14) went horizontal** (headless + Windows + subagents)
  but did not move onto the spec-quality axis. Spec lifecycle, adversarial
  authoring, and spec-driven auditing remain uncontested by Kiro.
- **Claude Code Security did not move.** Still security-scoped, still
  limited research preview. The spec-integration / persistent-knowledge /
  domain-lens gaps all remain open.
- **GitHub commoditized AI-bug-finding via its platform** (Incremental
  CodeQL GA'd Mar 24, AI-powered detections for Shell/Dockerfile/Terraform/PHP)
  rather than via a standalone AutoFL-style product. Academic research
  (AutoFL, LLMAO, LLM4FL) did not ship as products in the window.

---

## Closest competitors

### Tier 1 — Methodology enforcers

**Superpowers** (obra) — **163K GitHub stars as of April 2026 (up from 42K at
baseline; ~4x growth in 5 weeks).** v5.0.7 released 2026-03-31. Accepted
into official Anthropic marketplace January 2026. TDD (red-green-refactor),
Socratic brainstorming, micro-task planning, subagent-driven code review,
systematic debugging. Free, MIT. The dominant structured-development plugin
by community size — now an order of magnitude more visible than at baseline.
**March-April 2026 updates:** Brainstorming hard-gates (models were skipping
design, now blocked until design approved). **Inline Self-Review** replaced
prior subagent-dispatch review loops (claimed ~25 min overhead cut).
"20+ battle-tested skills" (up from ~14 at baseline). Still supports 6 tools
(Claude Code, Cursor, OpenCode, Codex, Gemini CLI, GitHub Copilot CLI).
Still no persistent knowledge or analysis.
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

**feature-dev** (Anthropic official) — **~176K installs as of April 2026
(up from 89K at baseline; roughly doubled in 5 weeks).** 7-phase structured
workflow: requirements → exploration → architecture → implementation → testing →
review → documentation. Official Anthropic backing makes it the "safe
default" — a position reinforced by the install growth. No visible feature
additions in the window; growth is distribution, not product surface.
*Gap vs vallorcine: monolithic (one command, not composable), no persistent KB,
no ADRs, no curation, no crash recovery, no work unit splitting, no session
continuity.*

**Kiro** (AWS, 2026) — agentic IDE using EARS (Easy Approach to Requirements
Syntax) notation for structured, testable requirements. Workflow: requirements →
user stories → acceptance criteria → technical design → implementation tasks.
Agent hooks trigger on file save/create/delete to keep specs and code in sync.
Deeply integrated with AWS services. **April 2026 updates:** `/quick-spec`
collapses three phases into one command; `/architecture-selection` adds
systematic architecture analysis between spec phases. **Kiro CLI 2.0
released 2026-04-14** adds headless mode (API-key-driven, CI/CD-usable),
native Windows support, and a subagent experience for parallelized work
with context isolation. This is a horizontal expansion — platform reach +
orchestration — **not a move into the spec-quality axis**. No adversarial
spec falsification, no lifecycle states, no spec-driven auditing.
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

**GSD — "Get Shit Done"** (gsd-build/get-shit-done, new on radar 2026-04-21) —
**~48.4K GitHub stars** [source: Augment Code article], v1.34.2 shipped
2026-04-06, ~1,693 commits across 47 releases since Dec 2025. Community OSS,
no disclosed funding. Positions explicitly as "spec-driven development +
context engineering" — the **closest new lookalike to vallorcine in the
window.** Crossed from obscure to marketplace-visible in March-April 2026.
*Watch closely — direct-lane entrant that didn't exist on the April 12 radar.
Understanding their spec model, whether they have lifecycle states, and
whether they do any adversarial review is the first question for the next
refresh.*

**The Agentic Startup** (rsmdt/the-startup) — multi-agent AI framework
framed as "Claude Code working like a startup team" with spec-first then
parallel specialist-agent execution. Lower profile than GSD, same lane.

**SDD Plugin** (LiorCohen/sdd) — small/nascent spec-driven plugin with
Given/When/Then acceptance criteria and phased implementation plans.

**Maestro-Orchestrate** (josstei, 2026) — 22 specialized subagents, 4-phase
workflows (Design/Plan/Execute/Complete), parallel execution, persistent
sessions. Express vs Standard workflow paths with approval gates. Decomposes
single complex tasks across specialists — no cross-feature coordination.

**claude-code-workflow-orchestration** (barkain) — multi-step workflow
orchestration with task decomposition, parallel agent execution, specialised
agent delegation. Native plan mode integration.

### Tier 3 — Memory / knowledge

**claude-mem** (thedotmack) — **46.1K GitHub stars as of April 2026** —
auto-capture memory has become a real category signal. SQLite + ChromaDB,
automatic capture via session hooks. Semantic summaries, hybrid search with
vector embeddings. Claims ~10x token efficiency. Push-model (always loaded).
Docs site at docs.claude-mem.ai.
*Gap vs vallorcine: passive capture, opaque storage, no structure, no ADR
concept. Accumulates but never curates. **Our KB differentiation now lives
in curation + cross-linking, not just "sessions remember things"** — the
auto-capture category is commoditizing.*

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

**Claude Code Security** (Anthropic, announced 2026-02-20) — the most
significant new analysis entrant. Multi-stage verification: (1) initial scan
tracing data flows across files, identifying complex multi-component
vulnerability patterns, (2) independent red-vs-blue adversarial verification
where a second agent challenges each finding through exploitability testing,
mitigation detection, and logical consistency checks. Accessible via the
`/security-review` slash command built into Claude Code; findings appear in
the Claude Code Security dashboard. Found 500+ vulnerabilities in production
open-source codebases. **Still labelled "limited research preview" for
Claude Enterprise/Team customers — not GA as of 2026-04-21.** Genuine
multi-pass adversarial analysis.
*Refresh status (2026-04-21): **CCS did NOT close any of the three flagged
narrowing conditions** — no spec integration, no persistent knowledge from
prior scans, no domain-scoped analysis beyond security. Still security-only.
SpecterOps' secure-code-review guidance (2026-03-26) added ecosystem tooling
around it (prompt injection scanning, base64 payload detection, secret
scanning, PreToolUse guard hook) but the product itself didn't expand scope.
Unrelated-but-notable: CVE-2026-2796 (deny-rule bypass when commands exceed
50 subcommands) was disclosed in April 2026 — reputational event for the
Claude Code brand, not a product regression for CCS specifically.*
*Gap vs vallorcine: security-focused only (not general bug categories).
Two passes (scan + verify), not N passes with progressive refinement. No
spec integration — findings aren't grounded in behavioral contracts. No
topology-aware clustering — scans by data flow trace, not by construct
neighborhood. No persistent knowledge — each scan starts fresh. No
domain-lens scoping. **Watch closely:** Anthropic has the resources and
platform access to expand this. If/when they ship a GA release that adds
persistent per-scan knowledge or extends red-blue to non-security domains,
re-evaluate immediately.*

**OpenAI Codex Security** (March 2026, research preview) — builds project
context, creates editable threat model, identifies complex vulnerabilities,
proposes fixes. Scanned 1.2M commits, found 792 critical and 10,561 high-
severity findings. Less transparency about methodology.
*Gap vs vallorcine: security-focused. Unclear whether truly multi-pass or
single-pass with post-hoc classification. No persistent knowledge.*

**Qodo 2.0/2.1** (Feb 2026, $70M raise March 2026) — multi-agent architecture
with 15+ specialized review agents (correctness, security, performance,
observability, requirements). F1 score 60.1%, highest recall at 56.7%.
**Qodo 2.1** (2026-02-17) added "Continuous Learning Rules System" —
marketed as "the first and only intelligent Rules System for AI governance"
(VentureBeat). Three features matter for the vallorcine comparison:
(1) **Automatic Rule Discovery** — a Rules Discovery Agent generates
standards from **actual codebases** (not just PRs) and PR feedback;
(2) **Intelligent Maintenance** — Rules Expert Agent catches conflicts,
duplicates, and decay; (3) **Scoped enforcement + permission-aware Context
Engine** — org / repo-group / repo inheritance, indexes 10-1000 repos. 11%
precision boost claim.
*Gap re-assessment (2026-04-21): the baseline framing of "PR-scoped not
codebase-scoped" **is no longer accurate.** Qodo's learning substrate is
codebase-wide; enforcement surface is still PR-gated, but they have closed
one of the three "narrowing conditions" flagged at baseline. Differentiation
now lives in: (a) **spec-driven integration** — Qodo rules are behavior-learned
from convention/quality signals, not spec-derived; (b) **adversarial review**
— Qodo's judge-agent filters findings but doesn't adversarially challenge
them; (c) **multi-feature coordination via .work/ layer** — Qodo still
operates per-PR, not per-feature-set; and (d) **multi-pass sequential
refinement** vs Qodo's multi-agent parallel. These axes hold — but the easy
differentiators are gone.*

**Sourcery** — "series of AI code reviewers each with different specialties"
plus validation pass for false positive reduction. Multi-angle review with
post-hoc filtering. Similar approach to Qodo but less mature.

**Trail of Bits Security Skills** (Claude Code plugin marketplace) —
`audit-context-building` skill with line-by-line analysis, First Principles
reasoning, invariant/assumption tracking, cross-function flow tracing.
Marketplace composition as of 2026-03-17 shows 35 plugins / 11 capabilities /
18 commands / 60 skills / 4 hooks — **materially smaller than the 94-plugin
/ 201-skill figure in the prior baseline**. Either the baseline counted
across multiple Trail of Bits marketplaces, or a consolidation happened.
[unverified which is correct — flag for next refresh.] New: **Dimensional
Analysis Plugin** (2026-03-25) uses the LLM to annotate code with dimensional
types, then flags mismatches mechanically. Claims 93% recall vs 50% for
baseline prompts. **This is the first multi-stage (LLM-then-mechanical-check)
signal from Trail of Bits** — if they generalize the pattern, it starts to
resemble a multi-pass pipeline rather than single-pass skills. Also noted:
**Agentic Actions Auditor** for CI/CD security. Claiming 200 bugs/week on
targeted engagements.
*Gap vs vallorcine: most skills still single-pass, security-focused, no
clustering, no persistent knowledge. But: the Dimensional Analysis pattern
is a watchpoint — one plugin doesn't close the gap, but the direction matters.*

**Snyk DeepCode AI** — hybrid symbolic + ML engine combining flow-sensitive
analysis, data-flow analysis, and symbolic execution. Trained on 25M+ data
flow cases. Specifically detects concurrency bugs, missing-check
vulnerabilities, memory safety issues. 80% fix accuracy.
*Not LLM-based — trained models, not reasoning. Domain-aware detection
(knows what a concurrency bug looks like) but not domain-scoped analysis.
Complementary rather than competitive.*

**CodeRabbit** — **Codegraph + cross-repo multi-repository analysis launched
March 2026** — builds cross-file dependency graph across linked repos,
detects downstream breakage when PRs change shared APIs / types / schemas.
This is the most direct signal that topology-aware clustering will be
commoditized — not yet at vallorcine's relationship-type differentiation
(state-sharing vs execution vs contracts), but approaching. Expanding
context graph with runtime traces, CI/CD data, observability signals. 46%
accuracy on real-world runtime bugs. Combines AST evaluation, SAST, and
generative AI. Ingests past PRs and chat-based learnings. **Traction: 2M+
repos connected, 13M+ PRs processed, 8,000+ paying customers; revenue
doubled within 6 months of $60M Series B (Sept 2025, $550M valuation,
NVIDIA-backed). Well-funded and growing fast.**
*Dependency-graph-level awareness, approaching but not yet topology-aware
clustering. Accumulated review preferences, not analytical knowledge.*

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

**Ars Contexta** (new on radar 2026-04-15) — Claude Code plugin with `/reduce`,
`/reflect`, `/reweave` commands for generating and cross-linking ADRs from
conversation. **Cross-reference-aware ADR tooling is a direct analog to
vallorcine's `related` / `decision_refs` / `kb_refs` cross-linking** — this
concept is no longer uniquely vallorcine-positioned at the command level,
though the spec-integration + adversarial authoring + lifecycle layers
remain distinctive. Worth a deeper look for the next refresh. Source:
blog.brightcoding.dev, April 15 2026.

**cc-skills** (terrylica) — 23 plugins, ADR-driven workflow with 11 bundled
skills including `adr-code-traceability` and `adr-graph-easy-architect`.
Claude Code open issue #13853 requests automatic ADR loading from
`~/.claude/adr/` (mirroring CLAUDE.md) — may eventually ship natively.

### Adjacent — Broader ecosystem

**Cursor** — AI IDE. **Cursor 3 (GA 2026-04-02) is the most significant
landscape change in the refresh window.** Interface overhaul replaces
Composer with an "Agents Window"; worktree-first parallel agents with
best-of-N (run the same prompt on multiple models in parallel worktrees,
side-by-side compare); Design Mode (browser UI annotation for agents);
**Bugbot now auto-learns review rules from PR feedback** — the closest any
IDE-scale tool has come to vallorcine's KB compounding loop, at per-repo
review scope (not cross-session knowledge accumulation). Composer 2 model
(2026-03-19, first Cursor model with continued pre-training). JetBrains
support via ACP (2026-03-04). Self-hosted cloud agents (2026-03-25).
Rules remain `.cursor/rules/*.mdc` files without structured relationships.
Huge user base — reported in advanced talks for a $2B round at $50B
pre-money [unverified], $2B ARR as of Feb 2026, 1M+ paying customers.
No built-in TDD enforcement, no KB/ADRs/curation.

**Windsurf** (Cognition AI, formerly Codeium) — **Windsurf 2.0 (April 2026)
ships with Agent Command Center and one-click handoff from Cascade (local
planning) to Devin (cloud execution)** following Cognition's ~$250M Windsurf
acquisition (Dec 2025). SWE-1.5 model powers Cascade. Pricing revamp in
March 2026. Markdown-based Workflows remain the customization surface. 59%
Fortune 500 claim [unverified, trade source]. Positioning shift: from "IDE
with AI" to "local planner + cloud executor." No TDD pipeline, no KB, no
ADRs, no curation.

**Augment Code** — indexes 400K+ files to build dependency graphs and
architectural pattern models. **February 2026: Context Engine went MCP**
(api.augmentcode.com/mcp), exposing Augment's semantic search to any
MCP-compatible agent (Claude Code, Cursor, Codex). Claims 70%+ agent
performance improvement in benchmarks. *Strategic shift:* Augment is
repositioning from IDE-native product to **context-infrastructure
underneath other tools** — potentially including under Claude Code.
Different competitive axis than rules/skills. Context Engine understands
API contracts across repositories, can flag contract violations during
review. Closest to "spec as live contract" by inferring specifications
from codebase rather than explicit authoring. Structural knowledge, not
analytical findings.

**Aider** — open-source CLI pair programmer. Deep git integration, auto-commits,
automatic lint+test after changes. Reactive testing (run after changes) not
prescriptive (write first). No KB, no ADRs, no methodology. Model-agnostic.

**Continue.dev** — open-source for VS Code/JetBrains. AI checks as markdown
files that show up as GitHub status checks. CI/CD native. Review-time focus,
not development-time methodology.

**GitHub Copilot** — issue-to-PR pipeline via Coding Agent + Workspace. Self-
review, security scanning, semantic code search. **Mission Control moved to
an in-repo "Agents tab" in Jan 2026** — centralized session logs with inline
previews, direct PR jumps. Copilot metrics GA (2026-02-27) added an
engineering-manager dashboard. Tracks parallel tasks but no dependency graph,
no artifact lifecycle, no readiness computation. **Major GitHub move in
the refresh window: AI-powered security detections (2026-03-24) now ship
alongside CodeQL, targeting Shell/Dockerfile/Terraform/PHP** (170K findings
over 30 days, >80% positive dev feedback in internal testing). **Incremental
CodeQL (GA 2026-03-24) cuts PR scan time by 80%** via a persistent Partial
Semantic Graph. *This is the commoditization-of-AI-bug-finding showing up
inside GitHub's platform* — not as a standalone AutoFL-style product.
General-purpose agent, not methodology-enforcing. Locked to GitHub ecosystem.

**CodePrism** (rustic-ai, open source, MIT) — Rust-powered MCP server building
Universal AST graph representation. 1000+ files/second indexing, graph-based
queries, system-level relationship understanding. Query engine, not analysis
pipeline — provides the graph but doesn't cluster or analyze. 100% AI-generated
code. Interesting as potential infrastructure. *No dated activity found in
the 2026-03-18 → 2026-04-21 refresh window — maintenance status unclear.*

**Google Antigravity** (announced Nov 18, 2025; public preview v1.22.2 by
April 2026) — agent-first IDE, VS Code fork, Gemini 3 + third-party model
support (Claude Opus/Sonnet 4.6, GPT-OSS). "Manager view" for parallel
agents across workspaces. ~6% developer adoption within 2 months of launch
per trade coverage. Free for individuals in preview. Google's entry
legitimizes agent-first IDEs as a category. No TDD/KB/spec equivalent.

**CodeQL** — compiles source to queryable relational database (AST, data flow,
control flow). QL queries can express topology-aware patterns. Closest to real
topology awareness in a shipping tool, but requires manual query authoring — no
automatic topology detection or clustering. **Incremental CodeQL (GA
2026-03-24) cuts PR scan time by 80%** via a persistent Partial Semantic
Graph — a structural change that makes CodeQL viable for per-PR gating at
large repo scale. AI-powered detections (2026-03-24) fill the gaps CodeQL
doesn't cover well (Shell, Dockerfile, Terraform, PHP). Together these are
GitHub's consolidated response to the AI bug-finding space — a platform-scale
commoditization, not a standalone AutoFL/LLMAO-style product.

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
Validates the approach but doesn't describe a pipeline. Reports up to 50%
error reduction with human-refined specs.

**Understanding Specification-Driven Code Generation with LLMs** (arxiv
2601.03878, SANER 2026 Registered Report) — describes CURRANTE, a VS Code
extension implementing a three-stage workflow: Specification → Tests →
Function. The closest academic analog to vallorcine's Enhanced TDD tier in
scope. Academic validation of the spec → tests → code pipeline is
accelerating. Our edge remains execution (multi-tier, KB accumulation,
cross-session, adversarial authoring) rather than the pipeline idea itself.

---

## Where vallorcine leads

### Unique differentiators

The table below enumerates what no shipping competitor matched as of the
previous refresh (2026-04-12). See "Status notes (2026-04-21)" below the
table for which items remain genuinely unique versus which are now narrowing.

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

### Status notes (2026-04-21)

**Still uniquely vallorcine (nothing in the window closes these):**
- **Spec lifecycle management** (DRAFT/APPROVED/INVALIDATED + displacement
  + revival). Kiro CLI 2.0 went horizontal, not into the spec-quality axis;
  Tessl still closed beta on Framework; GSD's spec model is not yet visible
  at lifecycle granularity.
- **Adversarial spec authoring** (two-pass falsification with enforcement
  path tracing). No competitor shipped anything adjacent.
- **Spec-driven auditing** (specs drive analysis, not just code generation).
  Unmatched — Kiro's specs drive codegen, Tessl's specs drive codegen,
  Qodo's rules are convention-derived. This is our strongest moat.
- **Multi-feature work coordination with computed readiness**
  (`.work/` + artifact-based deps + `work-resolve.sh`). Copilot Mission
  Control / Cursor 3 Agents Window / Google Antigravity "Manager view" all
  surface parallel-agent UI but none compute readiness from artifact state.
- **Pipeline mode decomposition** (spec-only / impl-only) for team
  parallelization.
- **Interface contracts** as first-class specs.
- **Crash recovery** via checkpoint-based resume.
- **Multi-pass progressive audit** (5-pass pipeline).

**Gap narrowing (real erosion in the window):**
- **Analytical knowledge compounding.** Qodo 2.1's codebase-indexed Rules
  System (Feb 17) learns rules from *actual codebases*, not just PR feedback.
  Still convention/quality rules rather than adversarial bug-pattern findings,
  but the "rules learn from a codebase" primitive is now theirs too. Cursor 3's
  Bugbot self-improving review rules (Apr 2) is the same pattern scaled to
  per-repo review. Our differentiation: **adversarial findings + cross-feature
  reuse**, not just "rules update from feedback."
- **Topology-aware clustering / domain-lens analysis.** CodeRabbit Codegraph
  cross-repo (March) approaches dependency-level topology with cross-repo
  awareness. Not yet relationship-type-differentiated (state/execution/contract),
  but well-funded and iterating. Our differentiation still holds at the
  *relationship-type* level.
- **Knowledge base (as a category).** claude-mem at 46.1K stars and
  Ars Contexta's cross-reference-aware ADR commands (`/reflect`, `/reweave`)
  mean "Claude Code plugin has persistent memory" is no longer uniquely
  positioned. Our differentiation now lives in **curation + cross-linking +
  adversarial-findings integration**, not in having a KB at all.
- **ADR cross-references.** Ars Contexta's command model (`/reflect`,
  `/reweave`) is conceptually adjacent to our `decision_refs` / `kb_refs`
  linkage. The integration with spec lifecycle and audit findings is still
  vallorcine-specific, but the cross-reference primitive itself is no longer
  novel at the concept level.

**Eroded (competitive framing invalidated by this refresh):**
- The baseline claim that **Qodo is "PR-scoped, not codebase-scoped"** is
  no longer accurate. Qodo's Rules System learns codebase-wide. The
  enforcement surface is still PR, but the learning substrate isn't. Any
  vallorcine messaging that leans on "Qodo is just a PR reviewer" needs
  rewriting.

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

### Threat has materialized (narrowed in the last 6 weeks)

**Qodo 2.1 codebase-indexed Rules System (2026-02-17).** Qodo already made
one of the three moves we flagged as "would narrow the gap" — the Rules
Discovery Agent learns from *actual codebases*, not just PR feedback, with
org/repo-scoped inheritance and a permission-aware Context Engine indexing
10-1000 repos. The "PR-scoped not codebase-scoped" framing is now incorrect.
*Mitigation: differentiation moved to the axes they haven't yet touched —
spec-driven integration (Qodo rules are convention/quality-learned, not
spec-derived), adversarial review (judge-agent filters findings, doesn't
adversarially challenge them), multi-feature coordination, and multi-pass
progressive refinement. The easy framing ("they do PRs, we do codebases")
is gone.*

**Mainstreaming of methodology-plugin space.** Superpowers 42K → 163K
stars, feature-dev 89K → 176K installs. The "niche methodology tool"
framing no longer applies to our competitors. Our product advantages are
intact but we're now competing against much bigger brands for mindshare.
*Mitigation: this is a distribution problem more than a product problem.
See Confirmed Gaps — Community/Distribution (now the highest-severity open
item).*

### High priority (could erode lead within 6 months)

**Cursor 3's self-improving Bugbot + agent-manager positioning.** Cursor
went from "IDE with AI" to "agent manager" with worktree-parallel best-of-N
and Bugbot that learns review rules from PR feedback — the closest any
IDE-scale tool has come to our KB compounding loop. Cursor's scale
(~$2B ARR, 1M+ paying customers) dwarfs ours. If they add spec-driven
structure or cross-session knowledge accumulation, they approach from the
IDE side with a distribution advantage we can't match.
*Mitigation: their rules-learning is per-repo review scope, not cross-session
structural knowledge. Our spec lifecycle and multi-feature coordination
are architecturally upstream of review. Stay ahead on spec-integration
and the audit → KB adversarial feedback loop.*

**Claude Code Security expanding beyond security.** Baseline concern unchanged
— Anthropic's two-pass adversarial model (scan + red/blue verification) is
architecturally sound, and they have platform access. **This refresh (2026-04-21)
finds they did NOT move on any of the three narrowing conditions (spec
integration, persistent knowledge, domain-scoped analysis beyond security).**
Still "limited research preview." That keeps this a high-priority watch, not
a realized threat. Watchpoint: a GA release that adds persistent per-scan
knowledge or extends red-blue to non-security domains.

**GSD ("Get Shit Done", ~48K stars).** Direct-lane entrant that explicitly
positions on "spec-driven development + context engineering" — same framing
as vallorcine. Crossed from obscure to visible in the March-April window.
*Mitigation: unknown — we haven't analyzed their spec model, lifecycle
approach, or review discipline yet. First task for next refresh: a
head-to-head feature comparison so we know whether they're a lookalike in
name only or a real lane competitor.*

### Medium priority (watch, no immediate action needed)

**Kiro CLI 2.0 went horizontal, not vertical.** Baseline concern was "if
Kiro adds adversarial spec falsification, spec lifecycle states, or
spec-driven auditing, they compete directly." This refresh: Kiro CLI 2.0
(Apr 14) added headless mode, Windows, and subagents — platform reach and
orchestration, **not spec quality.** Kiro's spec model still ends at the
three-file handoff. Downgrading from High to Medium. Re-evaluate if Kiro
adds lifecycle states or adversarial review in a future release.

**Tessl's spec-as-source approach gaining traction.** Unchanged from baseline
— Framework still closed beta, Spec Registry claims 10,000+ specs. If/when
Framework opens, they become the closest direct competitor on
knowledge-resident-in-repo positioning.

**GitHub Spec Kit becoming a standard.** Unchanged. 80K+ stars, no major
first-party release in the window. Third-party integrations (SpecKit
Companion VS Code extension, Caramelo UI) growing around it. Watch whether
any format becomes de-facto.

**Trail of Bits' Dimensional Analysis pattern.** New multi-stage (LLM
annotate → mechanical verify) design signals experimentation beyond
single-pass skills. One plugin doesn't close the gap, but if the pattern
spreads across their skill library it starts to resemble multi-pass
pipelines. Also worth tracking: marketplace size data conflict (35 plugins
in the current listing vs 94 baseline) — reconcile before next refresh.

**CodeRabbit Codegraph cross-repo scale.** 2M+ repos, 13M+ PRs, revenue
doubled in 6 months. Codegraph cross-repo multi-repo analysis (March 2026)
is dependency-level, not relationship-type-differentiated, but they're
well-funded ($60M Series B, $550M valuation) and iterating fast. If they
add state-sharing / execution / contract differentiation, the topology
clustering gap narrows materially.

**Academic → product via GitHub, not standalone.** AutoFL / LLMAO / LLM4FL
have not shipped as commercial products. Instead, GitHub consolidated
AI-bug-finding inside its platform: Incremental CodeQL GA (2026-03-24, 80%
faster PR scans via persistent Partial Semantic Graph) and AI-powered
security detections for Shell / Dockerfile / Terraform / PHP. This is the
commoditization risk showing up at platform scale rather than as a
standalone tool — different shape than the baseline modeled.

**Auto-capture memory as a category.** claude-mem at 46.1K stars and
memsearch dedicated Claude Code plugin signal that "sessions remember things"
is becoming a default expectation, not a differentiator. Our KB differentiation
now lives in *curation + cross-linking + adversarial-findings integration*.

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
| **Community / distribution** | Superpowers (163K), feature-dev (176K), GSD (~48K) | **Critical** | Still feature-complete. Distribution gap is *wider*, not narrower — competitors 2-4x'd in 5 weeks. Primary constraint on vallorcine's near-term growth. |
| **Official marketplace listing** | Superpowers, feature-dev | **Critical** | Still unlisted. The primary discovery channel. Should be blocking priority. |
| Spec format interop | GitHub Spec Kit (80K+ stars), Tessl | Low | Spec Kit is unstructured markdown with no frontmatter/lifecycle/cross-refs — conceptual model mismatch, adapter not worth building. Reassess if format standardizes. |
| Agent-first IDE surface | Cursor 3 Agents Window, Google Antigravity Manager view, Copilot Mission Control | Medium | Structurally different (we're CLI + agent pipeline, not IDE). Not our audience directly, but ambient familiarity with parallel-agent UI shapes user expectations. |
| CI/CD integration | Archgate, Continue, Copilot | Medium | Out of scope (principle 1). Archgate is complementary. |
| Org-wide deployment | Windsurf Workflows, Cursor team rules | Medium | Not our audience yet (single-developer focus). Revisit if we target teams. |
| Auto-capture memory | claude-mem (46K), memsearch, Cursor 3 Bugbot rules-learning | Low | Deliberate design choice — curated > captured. But the category growth means we should be explicit about *why* curation wins in our positioning. |
| Cross-repo dependency graph | CodeRabbit Codegraph, Augment Context Engine MCP | Medium | We have in-repo topology via construct graph and audit neighborhoods. Cross-repo is not a design goal today. Reassess if jlsm or showcase projects grow to span repos. |
| LSP awareness | Cursor, Windsurf (native) | Low | Recommended as companion, not bundled (principle 1). |

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
