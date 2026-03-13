# vallorcine — Settled Design History

Stable design decisions that have graduated from active development.
Pull-model: read only when you need the rationale behind a past decision.

*Entries move here from CONTEXT.md Recent decisions once they are no longer
actively being revised.*

---

## Origin and purpose

Built for jlsm (Java 25 LSM-Tree library) as a Claude Code workflow system.
Goal: KB for algorithm research persisting across sessions without polluting
context. Evolved into full two-subsystem kit: TDD pipeline + KB/Decisions.
Reusable package. Install with `bash install.sh`.

## Pull model (not push)

Auto-loading KB via CLAUDE.md @imports rejected: token cost grows every session.
Pull model keeps session start fixed at ~2K forever.
Root CLAUDE.md is pointer-only, never content.

## File-based state over in-memory

In-conversation memory rejected: sessions end, context overflows, restarts happen.
status.md as mutable checkpoint — interruptible and restartable at any point.

## status.md + cycle-log.md separation

status.md: mutable current state. cycle-log.md: append-only history.
Mirrors write-ahead log / event sourcing. Gives idempotency for free.

## Prompted continuation

Rejected fully automatic (loses checkpoints, compounds errors).
Rejected fully manual (user must remember commands).
Prompted continuation: ↵ to continue, spawns sub-agent.

Always pause (high review value): brief→domains, domains→plan, plan→test.
Enter-default: test→implement, implement→refactor, refactor→PR.

## Visual headers and token estimates

`─── EMOJI  AGENT · slug · Cycle N ───` opening, `── Section ────` markers.
Closing footer with token estimate. Purpose: session readability.
Estimates are approximations — Claude Code doesn't expose real counts.

## Consolidated single package

Started as two zips. Consolidated: shared install, Domain Scout depends on KB.

## Idempotency pattern

Read status.md → if complete stop → if in-progress resume → if not-started proceed.

## Write authority partitioning

Each agent writes only to designated files. Escalation paths for cross-domain
problems. Enforced by explicit rules in command files and agent definitions.

## Tests are the specification

Tests written before implementation. Code Writer never modifies tests.
Contract conflicts escalate to Test Writer.

## Context budget as first-class concern

Always-loaded files capped and pointer-only. Index files have 80-line hard caps
with archival. Subject files capped at 200 lines. 15K work-unit crossover is
a direct expression of this principle.

## Human confirmation before irreversible writes

Architect: deliberation loop before adr.md. Scoping: brief confirmation before
brief.md. Cheapest place to catch mistakes.

## Agents are routers, not autonomy machines

/vallorcine-help is the clearest example: reads context, asks one question, hands a
pre-filled command. Never does pipeline work itself.

## KB topic management via /kb topic

/kb topic command; .kb/CLAUDE.md Topic Map is authoritative live list.
research.md reads it first, offers to run /kb topic as sub-agent if missing.

## Agents own the files (principle 9)

All kit-managed files carry managed-by notices. Manual edits bypass safety checks.

## /quick complexity check

4 signal categories. 0-1: silent. 2-3: soft warning. 4+: hard redirect.

## Work units

Split when single-unit load > 15K AND clean dependency boundary exists.
1-3 never split. Each unit runs own test→implement→refactor cycle.

## Project this was built for

jlsm — pure Java 25 modular LSM-Tree library.
Modules: jlsm-core, jlsm-indexing, jlsm-vector.
Build: Gradle (Groovy DSL). Test: JUnit 5.
Vector indexing work (float16, HNSW, IVF-Flat) drove KB and work-unit design.

## CONTEXT.md rolling structure (2026-03-13)

Problem: flat CONTEXT.md grows unbounded; after many sessions a fresh Claude
spends significant tokens reading stale settled history alongside current state.
Decision: four-section structure with explicit cadences. Current focus and
Recent decisions stay short. Settled design grows but is reference-only.
Rejected: separate files per session (too many files, harder to load cleanly);
timestamp-based pruning (mechanical, loses the why behind decisions).

## Enter to proceed everywhere (2026-03-13)

Original: "type yes/no" for all confirmation prompts.
Problem: unnecessary friction; requiring affirmation words feels form-like.
Decision: Enter always means proceed. Format: `  ↵  action  ·  or type: stop`
Numbered choices (1/2/3) reserved for genuine divergence with no safe default.
Also: prompt-conventions.md as always-loaded 62-line rules file rather than
copying format into every command file (drift risk) or shared on-demand file
(extra read per invocation).

## Sequential scoping interview (2026-03-13)

Original: agent presents all question categories at once (wall of questions).
Problem: shallow answers, worse briefs.
Decision: agent privately ranks unknowns by impact, asks one per turn.
`── Question i of n ──` header. N shifts down if answers resolve multiple
unknowns. 0 questions valid if description is fully specified.
