# vallorcine — Session Context

Handoff document for continuing work across fresh conversations.
Read DESIGN.md first for system architecture. This file covers the *why*
behind decisions and the living state of the project.

**Section update cadences:**
- `Current focus` — replaced every session
- `Recent decisions` — rolling window, ~last 3 sessions; oldest move to Settled
- `Settled design` — stable, reference only, rarely touched
- `Open questions` — live list; items resolve into Settled or get dropped
- `Deferred ideas` — good thoughts not being worked on now
- `Working preferences` — stable, shapes how we work together

---

## Current focus

*Last updated: 2026-03-13*

**Session goal:** Add autonomous TDD loop mode so users can opt out of manual stage-by-stage confirmation during implement → refactor cycles.

**Just completed:**
- Added `automation_mode` field to status.md template (not-set / autonomous / manual)
- Updated `feature-implement.md` — Step 0 asks the automation question once on
  first run, stores choice in status.md, persists for the life of the feature
- Autonomous mode: implement completes → chains directly to refactor with a
  one-line status + "type stop to pause" — no prompt
- Manual mode: existing enter-to-proceed behaviour unchanged
- Added structural escalation pause in `feature-refactor.md` (2c/2d) — pauses
  autonomous mode for interface/contract changes regardless of mode setting
- Missing tests escalation (2e) always pauses — never automatic, both modes
- Updated `feature-resume.md` — surfaces automation_mode in status display
- Hooks: decided against — Code Writer already runs tests via bash tool calls;
  hooks would add context cost without meaningful gain for the TDD loop

**Where things stand:**
Autonomous TDD loop complete. Package ready for v0.1.0 GitHub push.
Next: push to telefrek/vallorcine, test plugin install, submit to awesome-claude-code.

---

## Recent decisions

*Rolling window — move oldest entries to Settled when this exceeds ~10 items*

### 2026-03-13 — Autonomous TDD loop mode

Added opt-in automation that chains implement → refactor → next unit tests
without stopping. User chooses mode once at first `/feature-implement` run;
choice persists in status.md for the feature lifetime.

Two deliberate non-automations: (1) missing tests escalation (2e) always pauses
both modes — it's a quality gate, not friction. (2) structural issues in 2c/2d
also always pause — interface changes affect other units and need human judgement.

Hooks considered and rejected: Code Writer already runs tests via bash tool calls
on its own judgement. Hooking PostToolUse on Write would add context cost (50–200
lines of test output per file write) without improving what the agent already does.
The right use of hooks is additive tooling (linting, security scanning) not
duplicating existing agent behaviour.

### 2026-03-13 — Plugin system support

Researched Claude Code plugin ecosystem (launched Oct 2025, in public beta).
Confirmed: plugins handle distribution (install/update via /plugin command),
not workflow. Our TDD pipeline, KB/Decisions, session context, /release, and
/upgrade-vallorcine are the novel layer — nothing in the plugin ecosystem covers them.

Decision: add plugin manifest alongside shell installer, not replace it.
Two reasons: (1) plugin path (/plugin marketplace add) is lower friction for
new users; (2) shell path enables /upgrade-vallorcine with version stamps and explicit
user-file preservation logic that /plugin marketplace update doesn't provide.
Neither path is strictly better — they complement each other.

Rejected: rewriting the kit as a pure plugin (would lose upgrade.sh logic,
version stamp, and the deliberate user-file preservation on upgrade).

### 2026-03-13 — GitHub repo structure and versioning

Problem: kit was developed as a zip, no version tracking, no local dev workflow.
Decision: standard repo layout with README, CHANGELOG, .gitignore, VERSION (semver).
install.sh now reads VERSION, writes a version stamp to the target project
(.claude/.vallorcine-version), and warns when the installed version differs
from the package version. Added --dev flag: installs into repo root for local
testing; .claude/ is gitignored so test state never contaminates source.
RESUME.md updated to prefer repo-based workflow (Option A) with zip as fallback.
Branch convention: wip/<topic> for in-progress work.


### 2026-03-13 — CONTEXT.md rolling structure

Problem: flat CONTEXT.md grows unbounded; after many sessions a fresh Claude
spends significant tokens reading stale settled history alongside current state.
Decision: four-section structure with explicit cadences. Current focus and
Recent decisions stay short. Settled design grows but is reference-only.
Rejected: separate files per session (too many files, harder to load cleanly);
timestamp-based pruning (mechanical, loses the why behind decisions).

### 2026-03-13 — Enter to proceed everywhere

Original: "type yes/no" for all confirmation prompts.
Problem: unnecessary friction; requiring affirmation words feels form-like.
Decision: Enter always means proceed. Format: `  ↵  action  ·  or type: stop`
Numbered choices (1/2/3) reserved for genuine divergence with no safe default.
Also: prompt-conventions.md as always-loaded 62-line rules file rather than
copying format into every command file (drift risk) or shared on-demand file
(extra read per invocation).

### 2026-03-13 — Sequential scoping interview

Original: agent presents all question categories at once (wall of questions).
Problem: shallow answers, worse briefs.
Decision: agent privately ranks unknowns by impact, asks one per turn.
`── Question i of n ──` header. N shifts down if answers resolve multiple
unknowns. 0 questions valid if description is fully specified.

### 2026-03-13 — KB topic management via /kb topic

Originally: approved topic list hardcoded in research.md.
Problem: adding topics required editing a command file directly.
Decision: /kb topic command; .kb/CLAUDE.md Topic Map is authoritative live list.
research.md reads it first, offers to run /kb topic as sub-agent if missing.

### 2026-03-13 — Agents own the files (principle 9)

All kit-managed files carry managed-by notices naming the command to use.
Rationale: manual edits bypass agent safety checks (idempotency reads, cap
enforcement, index consistency, append-only log rules).

### 2026-03-13 — /quick complexity check

Added as Step 1 before codebase scan (cheap, description-only).
4 signal categories: scope, uncertainty, decision, size.
0-1 signals: silent proceed. 2-3: soft warning, Enter continues.
4+: hard redirect, numbered choice required.
complexity_override: true in status.md prevents re-asking at Step 3.

### 2026-03-13 — Work units

Problem: large features create bloated Code Writer sessions.
Decision: Work Planner Step 2b proposes split when single-unit load > 15K
tokens AND a clean dependency boundary exists.
Weights: stub ~1K, test ~2K, work-plan section ~0.5K, dep interface ~0.5K.
Thresholds: 1-3 never split. 4-5 with clean boundary. 6+ with boundary split.
Each unit runs own test→implement→refactor. Integration tests deferred to final
unit. --unit WU-N flag on inner-loop commands.

---

## Settled design

*Stable decisions — reference only*

### Origin and purpose

Built for jlsm (Java 25 LSM-Tree library) as a Claude Code workflow system.
Goal: KB for algorithm research persisting across sessions without polluting
context. Evolved into full two-subsystem kit: TDD pipeline + KB/Decisions.
Reusable package. Install with `bash install.sh`.

### Pull model (not push)

Auto-loading KB via CLAUDE.md @imports rejected: token cost grows every session.
Pull model keeps session start fixed at ~2K forever.
Root CLAUDE.md is pointer-only, never content.

### File-based state over in-memory

In-conversation memory rejected: sessions end, context overflows, restarts happen.
status.md as mutable checkpoint — interruptible and restartable at any point.

### status.md + cycle-log.md separation

status.md: mutable current state. cycle-log.md: append-only history.
Mirrors write-ahead log / event sourcing. Gives idempotency for free.

### Prompted continuation

Rejected fully automatic (loses checkpoints, compounds errors).
Rejected fully manual (user must remember commands).
Prompted continuation: ↵ to continue, spawns sub-agent.

Always pause (high review value): brief→domains, domains→plan, plan→test.
Enter-default: test→implement, implement→refactor, refactor→PR.

### Visual headers and token estimates

`─── EMOJI  AGENT · slug · Cycle N ───` opening, `── Section ────` markers.
Closing footer with token estimate. Purpose: session readability.
Estimates are approximations — Claude Code doesn't expose real counts.

### Consolidated single package

Started as two zips. Consolidated: shared install, Domain Scout depends on KB.

### Idempotency pattern

Read status.md → if complete stop → if in-progress resume → if not-started proceed.

### Write authority partitioning

Each agent writes only to designated files. Escalation paths for cross-domain
problems. Enforced by explicit rules in command files and agent definitions.

### Tests are the specification

Tests written before implementation. Code Writer never modifies tests.
Contract conflicts escalate to Test Writer.

### Context budget as first-class concern

Always-loaded files capped and pointer-only. Index files have 80-line hard caps
with archival. Subject files capped at 200 lines. 15K work-unit crossover is
a direct expression of this principle.

### Human confirmation before irreversible writes

Architect: deliberation loop before adr.md. Scoping: brief confirmation before
brief.md. Cheapest place to catch mistakes.

### Agents are routers, not autonomy machines

/vallorcine-help is the clearest example: reads context, asks one question, hands a
pre-filled command. Never does pipeline work itself.

### Project this was built for

jlsm — pure Java 25 modular LSM-Tree library.
Modules: jlsm-core, jlsm-indexing, jlsm-vector.
Build: Gradle (Groovy DSL). Test: JUnit 5.
Vector indexing work (float16, HNSW, IVF-Flat) drove KB and work-unit design.

---

## Open questions

*Live list — resolve into Settled or drop when addressed*

- **/decisions command** — list/filter existing ADRs. Suggested early, never
  built. Useful once a project accumulates many decisions. Confirmed gap vs
  competitors — claude-plugin-adr ecosystem expects status filtering
  (Proposed/Accepted/Deprecated/Superseded). **Ranked: high priority.**

- **Code Writer escalation iteration counter** — no hard stop if Code Writer
  escalates to Test Writer repeatedly on the same contract conflict. Needs cycle limit.

- **KB coding agent** — third KB role that reads entries and implements against
  them. Would close the loop between research and implementation.

- **Work unit split thresholds** — 15K crossover and 3.5K per-construct are
  reasoned estimates, not measured. Real-world use will reveal if adjustment needed.

- **cycle-log.md archival** — no cap or archival rule. Long-running features
  accumulate significant log entries. Consider archiving to cycle-log-archive.md
  when file exceeds ~100 lines, similar to .decisions/CLAUDE.md.

- **CONTEXT.md maintenance discipline** — only useful if updated. The
  `/save-work` command is the mechanism but depends on remembering.
  Could /feature-complete prompt for CONTEXT.md updates automatically?

---

## Deferred ideas

*Good thoughts not being worked on — kept to avoid losing them*

- **Hooks for non-TDD tooling** — hooks are useful for additive tooling the
  agents don't naturally do: linting on write, security scanning, formatting.
  Not for test running (Code Writer already does this via bash). Future: a
  `hooks/` directory with opt-in linting hooks configurable via project-config.md.

- **LSP integration** — Code Writer currently works with text files. LSP plugins
  (pyright, vtsls, rust-analyzer, gopls) give Claude real-time type information,
  find-all-references, and immediate type error feedback. Could be a recommended
  companion rather than built-in — document in README which LSP plugins pair well
  with vallorcine's Code Writer stage.

- **Context7 / live docs in Domain Scout** — Domain Scout identifies libraries
  in scope during domain analysis. Could optionally pull current framework docs
  via Context7 MCP for fast-moving libraries. Opt-in via project-config.md flag.
  Addresses hallucination risk on recent API changes.

- **/decisions list** — browse and filter existing ADRs by status, date, or
  keyword from within Claude Code. Companion to the existing /decisions review command.
  See open questions above for priority rationale.

- **Project-level CONTEXT.md** — for projects *using* the kit, a similar
  rolling-context pattern for accumulated project wisdom. Different from ADRs —
  more like "things we've learned about this codebase."

- **Diff-based install** — install.sh skips or overwrites. A diff mode showing
  what changed between installed and package version would help upgrading.

- **Coverage gating in refactor** — Refactor Agent checks for missing tests (2e)
  but doesn't enforce a threshold. Projects with coverage tooling could have it
  read reports and flag drops below a configured minimum.

- **/feature-split** — take an in-progress feature and split it into two when
  scope expands. Archive current, preserve brief, help create two new features.

---

## Competitive landscape notes

*Recorded 2026-03-13 from marketplace research — for context when prioritising*

Closest competitors: **Superpowers** (TDD + lifecycle, in official marketplace),
**Deep Trilogy** (staged decompose→plan→implement with TDD, three separate plugins),
**claude-plugin-adr** (ADR templates + shell scripts, no deliberation loop).

**Where vallorcine leads:** crash recovery (unique), token-aware work unit
splitting (unique), KB↔pipeline integration (unique), deliberation loop on ADRs
(unique), sequential scoping interview (unique).

**Confirmed gaps vs ecosystem:** hooks integration, LSP awareness, /decisions
list/filter command, coverage gating, live docs in domain analysis.

**Not worth building:** external LLM review in planning (Deep Trilogy does this,
adds latency and cost, our KB approach is more persistent). Autonomous looping
(Ralph Wiggum pattern — explicitly against our design principle 8).

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
