# vallorcine — Examples

Practical walkthroughs for common workflows. Each example shows the commands
you'd run and what to expect.

---

## Building a feature from scratch

A full pipeline run, from idea to PR-ready code.

**1. Start the scoping interview**

```
/feature "add rate limiting middleware to the HTTP server"
```

The Scoping Agent asks questions one at a time to understand the feature.
Answer naturally — it adapts the number of questions based on your responses.
When it has enough context, it presents a brief for confirmation.

**2. Run domain analysis**

```
/feature-domains "rate-limiting-middleware"
```

The Domain Scout checks `.kb/` and `.decisions/` for relevant prior work.
If it finds gaps, it commissions `/research` or `/architect` runs and tells
you exactly what to run before continuing.

**3. Generate the work plan**

```
/feature-plan "rate-limiting-middleware"
```

The Work Planner writes contracts and stubs into your source tree. If the
feature's estimated session size exceeds ~15K tokens (roughly 5+ constructs
at the ~3K-per-construct heuristic) and there are clean dependency
boundaries, it proposes splitting into work units that each run their own
TDD cycle. Step 4 also picks an `execution_strategy` — `cost` (sequential,
default), `balanced` (batched parallel), or `speed` (max parallelism). The
first two run sequentially via Step 5 below; the `balanced` / `speed`
strategies are covered in the parallel-coordinator section later in this
document.

**4. Write tests, then (optionally) harden, then implement**

```
/feature-test "rate-limiting-middleware"
/feature-harden "rate-limiting-middleware"     # optional — see below
/feature-implement "rate-limiting-middleware"
```

`/feature-harden` sits between test writing and implementation. It adds
an adversarial test pass against domain-lens behavioral attacks on the
contracts (concurrency races, boundary conditions, resource-lifecycle
edges — which lens runs depends on the feature's domains). The command
auto-selects `skip` / `lite` / `full` based on the feature's risk
profile, so you can usually leave it in the flow and let it decide. If
you want the pipeline to skip it entirely, `/feature-harden "<slug>"
--skip` marks it done without running.

In autonomous mode, hardening chains automatically between test and
implement. In manual mode, invoke it yourself between the two — or
skip it.

On first `/feature-implement`, you'll be asked to choose a TDD loop mode:

```
── How would you like to run the TDD loop? ─────
  ↵  autonomous  — test → implement → refactor cycles run without stopping.
                   Interrupt anytime by typing in the session.
                   I'll pause if I find something that needs your input.

  manual  — I'll confirm each step before continuing.
```

Press Enter for autonomous or type `manual`. This choice is saved for
the life of the feature — you won't be asked again.

**5. Refactor and prepare the PR**

In autonomous mode, refactoring chains automatically after implementation.
In manual mode:

```
/feature-refactor "rate-limiting-middleware"
/feature-pr "rate-limiting-middleware"
```

**6. After the PR merges**

```
/feature-complete "rate-limiting-middleware"
```

Archives the feature directory to `.feature/_archive/`.

---

## Coordinating multi-feature goals with work groups

When a goal spans multiple features — a module rewrite, a new subsystem,
a family of related specs — the `.work/` layer coordinates it. A work
group decomposes the goal into work definitions (WDs) with artifact-based
dependencies. Readiness is computed mechanically by `work-resolve.sh`
from each WD's declared inputs, so completing one WD automatically
unblocks whatever depended on it.

```
/work "implement-transport-layer"
```

Scopes the group interactively — what's in, what's out, rough ordering.
Writes `.work/implement-transport-layer/work.md`.

```
/work-decompose "implement-transport-layer"
```

Breaks the group into WDs. Each WD declares `artifact_deps` (specs, ADRs,
interface contracts it needs at required states) and `produces` (what it
will deliver). Interface contracts are specs with `kind: interface-contract`
— shared surfaces between WDs, so one team can stub a contract and
another can consume it before the first lands.

```
/work-status "implement-transport-layer"
```

Reports readiness across the group — WDs marked READY (all deps met),
BLOCKED (waiting on another WD's output), IN_PROGRESS, or COMPLETE. Use
`/work-status --all` for a summary across every active group.

```
/work-plan "implement-transport-layer" WD-01
```

Runs the specification-only pipeline on a WD — domain analysis and spec
authoring, stopping before implementation. WD moves to SPECIFIED.

```
/work-start "implement-transport-layer" next
```

Picks the next ready WD and runs the implementation pipeline against its
already-produced specs. Omit `next` and name a specific `WD-nn` to target
one. On completion, `work-resolve.sh` automatically re-evaluates the
group and marks downstream WDs READY.

Work groups are a pull-model layer: they inject context into `/architect`,
`/spec-author`, `/feature-domains`, and `/feature-plan` only when you're
working inside a group, so solo feature work pays no cost.

---

## Working with work units

For larger features, the Work Planner splits work into units. Each unit
runs its own test → implement → refactor cycle.

```
/feature-test "rate-limiting-middleware" --unit WU-1
/feature-implement "rate-limiting-middleware" --unit WU-1
```

You don't need to track which unit is next — if you omit `--unit`, the
pipeline picks the next eligible unit automatically. Use `--unit` only
when you want to target a specific one.

Check progress across all units:

```
/feature-resume "rate-limiting-middleware"
```

---

## Autonomous TDD loop

Choose autonomous mode at first `/feature-implement` to let the pipeline
chain through test → implement → refactor → audit → next unit without pausing.

The pipeline runs a spec analysis pre-pass before test writing (identifying
contract gaps and implementation risk patterns) and an adversarial audit pass
after refactoring (writing targeted tests against the real implementation).
The first audit loop runs automatically; additional rounds require approval.

The pipeline always pauses for two things regardless of mode:

- **Structural issues** (interface/contract changes in refactor steps 2c/2d)
  — these affect other units and need your judgement
- **Missing tests** (refactor step 2e) — a quality gate, not friction
- **Additional audit rounds** (when cross-construct bugs are found)
  — you decide whether deeper adversarial testing is worthwhile

Type anything into the session at any time to pause autonomous mode.
The pipeline picks up cleanly from where it stopped.

---

## Parallel execution with the feature coordinator

When a feature was planned with `execution_strategy: balanced` or `speed`
and has multiple work units with a dependency graph, the TDD loop runs
under `/feature-coordinate` instead of the usual sequential
test → implement → refactor chain. The coordinator dispatches work units
as concurrent sub-agents, waits for them, then launches the next batch.

Entry point, invoked automatically by the pipeline at the end of planning
when strategy is `balanced`/`speed`:

```
/feature-coordinate "rate-limiting-middleware"
```

Behavior depends on the strategy:

- **`balanced`** — grouped batches. All units with satisfied dependencies
  launch together, coordinator waits for the batch to finish, then
  launches the next batch. Predictable checkpoints between batches.
- **`speed`** — completion-driven. As each unit finishes, any newly
  unblocked units launch immediately — a unit deep in the dependency
  chain starts the moment its last predecessor finishes, without waiting
  for an unrelated batch to complete.

Each sub-agent runs the full `/feature-test` → `/feature-implement` →
`/feature-refactor` pipeline against its assigned work unit in an
isolated context. Progress is tracked in a single TodoWrite list owned
by the coordinator (sub-agents don't write to TodoWrite — it's a shared
surface). Per-unit progress is also visible in each unit's
`.feature/<slug>/units/WU-N/status.md`.

### Multi-feature dispatch — sequential vs parallel

When a work group has multiple SPECIFIED WDs ready to implement (or
multiple READY WDs needing specification), two modes automate the
chain. Both dispatch one sub-agent per WD; they differ only in
concurrency and which trade-offs you accept.

**Sequential `all` — for context economy.** Runs WDs one at a time,
each in its own sub-agent context. The coordinator's parent context
stays small (~6K of dispatch state + summaries) while each sub-agent
does ~200K of planning/testing/implementation work in isolation. Use
this when multi-WD planning would otherwise hit the context wall.

```
/work-plan "implement-transport-layer" all      # specify every READY WD
/work-start "implement-transport-layer" all     # implement every SPECIFIED WD
```

The coordinator re-runs the resolver between iterations, so a WD
unblocked by the previous iteration's completion gets picked up
automatically. `work-claim.sh` prevents same-WD races if you have
another terminal active. Arbitration prompts during `/spec-author`
Pass 2 surface to you normally — the coordinator pauses, you answer,
the run continues.

**Parallel — for wall-clock speed.** Dispatches every SPECIFIED WD as
a concurrent sub-agent, optionally capped at N simultaneous runs:

```
/work-start "implement-transport-layer" --parallel 3
```

The coordinator shows the dispatch plan, asks you to confirm (parallel
mode burns N× the tokens of a sequential run), then fans out.
Concurrency caveats — shared KB writes, test contention, cost budget —
are surfaced before you confirm.

### Cheap resume after `/clear`

Multi-WD planning sessions hit a context wall around 500K tokens
because each skill switch re-seeds caches. `/clear` between WDs avoids
that, and `/work-resume` is the cheap re-entry point:

```
/clear
/work-resume "implement-transport-layer"
```

`/work-resume` reads a cached `_readiness.json` (refreshed
automatically when WD status changes) and shows where the group is
plus the next command to run — `/work-plan`, `/work-start`,
`/feature-resume`, or an unblock action. With no argument, `/work-resume`
lists every active work group with a one-line summary.

Or skip the manual `/clear`-and-resume rhythm entirely with
`/work-{plan,start} <group> all` — same context-economy benefit,
automated.

---

## Crash recovery

Session crash, timeout, or context overflow? Resume cleanly:

```
/feature-resume "rate-limiting-middleware"
```

This reads `status.md` and tells you exactly where you are and what
command to run next. The pipeline is designed to be interrupted at any
point — every command checks its stage before doing work.

See all active features at once:

```
/feature-resume --list
```

Get a detailed session briefing (useful for standup or context-switching):

```
/feature-resume "rate-limiting-middleware" --status
```

Condensed team/standup format:

```
/feature-resume "rate-limiting-middleware" --share
```

---

## Researching a topic

Build up the knowledge base with structured research that persists across
sessions.

```
/research "LRU vs LFU eviction strategies"
```

Argument: `"<subject>"` — describe what you want to know. The Research Agent
determines topic, category, and placement by scanning existing KB content and
doing preliminary web research. For cross-cutting subjects, it may identify
multiple facets and write separate focused articles. You confirm the facet
plan before anything is written.

Research is automatically surfaced during `/feature-domains` when the
Domain Scout identifies relevant prior work.

---

## Querying the knowledge base

Ask questions in plain language — the KB agent searches the hierarchy
and synthesises an answer from what's been researched:

```
/kb "what are the tradeoffs between HNSW and IVF?"
```

Load a specific entry directly:

```
/kb lookup algorithms vector-indexing "HNSW graph construction"
```

Create a new topic area:

```
/kb topic "infrastructure" "Cloud services, deployment, CI/CD, monitoring"
```

---

## Making architecture decisions

Start a deliberation when you need to choose between approaches:

```
/architect "choose between Redis and in-process cache for rate limit state"
```

The Architect Agent builds a constraint profile, scores candidates against
your KB research, and runs a deliberation loop before writing the ADR.
You confirm before anything is written — ADRs are never created silently.

---

## Reviewing past decisions

Query decisions in natural language:

```
/decisions "what did we decide about caching?"
/decisions "have we ruled out GraphQL anywhere?"
/decisions "what assumptions are we carrying about the database layer?"
```

Revisit decisions by topic — search across all accepted ADRs:

```
/decisions revisit "encryption"
```

The architect asks why you're revisiting, checks revision conditions against
the current codebase, and opens a deliberation loop. If the decision is
revised, it offers to start a `/feature` that enters the pipeline at planning
with the architectural context already loaded.

You can also revisit by slug for a specific decision:

```
/decisions revisit "rate-limit-state-store"
```

Defer a topic for later:

```
/decisions defer "migration to gRPC" --until "after v2 launch"
```

Review all deferred items:

```
/decisions triage
```

---

## Writing and maintaining specs

Specs are opt-in — not every project uses them, and within a project
you add them lazily as features introduce behavior worth specifying
(see [GETTING-STARTED-EXISTING.md](GETTING-STARTED-EXISTING.md) for the
adoption rationale). The spec layer has its own small pipeline.

**1. Initialize the spec corpus** (once per project, when you're ready
to start writing specs):

```
/spec-init
```

This creates `.spec/registry/manifest.json`, the domain taxonomy seed,
and shard indexes. Safe to run even if other layers are already set
up — it's a no-op if the spec corpus already exists.

**2. Author a hardened spec** through two-pass adversarial review:

```
/spec-author "F12" "token bucket rate limiter"
```

The Spec Author Agent runs a structured-draft pass, then a falsification
pass that adversarially challenges the draft — trying to break each
requirement with edge cases, boundary conditions, and contradictory
scenarios. You confirm the final requirement set before it lands in
`.spec/` with DRAFT state.

**3. Register and promote.** `/spec-author` calls `/spec-write` under
the hood to land the file, but you can also register a hand-authored
spec:

```
/spec-write "F12" "token bucket rate limiter"
```

`/spec-write` checks for conflicts and displacement (new specs that
contradict existing APPROVED specs) before registering. If displacement
is detected, you choose how to resolve (accept replacement, narrow
scope, or defer). Quantitative ambiguity is gated at this step — specs
with score >0.20 (`[UNVERIFIED]+[UNRESOLVED]+[CONFLICT]` fraction) stay
DRAFT until clarified.

**4. Verify against implementation** after the feature lands:

```
/spec-verify "F12"
```

`/spec-verify` traces each requirement to its enforcement point in
code (via `@spec FXX.RN` annotations), flags drift, and repairs inline
— either updating the code to match the spec or amending the spec to
match the reality. It's a repair loop, not a gap report.

**5. Query specs** when you need them:

```
/spec "what guarantees do we make about rate limit windows?"
```

`/spec` searches requirements across all specs, surfaces gaps (domains
with no spec coverage), and traces change impact ("if I change R5, what
else breaks?"). Useful during feature scoping to see what's already
promised.

**6. Subdivide a mature spec** when it has grown past one file's worth
of behavior with multiple distinct concerns:

```
/spec-split "encryption.primitives-lifecycle"
```

A mature spec — typically 50+ requirements with 2+ section headers —
is a candidate for subdivision into a parent + concern-specific
children. Each child is a full spec in its own right; the parent
retains R-numbered cross-cutting requirements that span all children
(e.g. "all DEKs must be wrappable under their tenant root key").
Children own concern-specific requirements (key-rotation, DEK lifecycle,
revocation, etc.).

`/spec-split` identifies natural concern boundaries from the existing
section structure, proposes them via `AskUserQuestion` (with edit
option), then transactionally executes:

- Carves child files from the parent's body, **preserving R-number
  identity** (R45 stays R45 in the child)
- Rewrites the parent to retain only cross-cutting requirements
- Updates the manifest with `parent_spec` references
- Sweeps `@spec parent.Rxx` annotations in production source dirs,
  rewriting to `@spec parent.child.Rxx` for moved requirements
- Runs `spec-validate` on parent + every child
- **Auto-rollbacks** on any post-write validation failure (rollback
  log preserved at `.spec/.split-log/<id>-<timestamp>.json` for
  one release in case manual inspection is needed)

After a split, `/spec-author` Pass 2/3 falsification on a child loads
the parent + all siblings as full files (cross-family contradiction
detection). `/spec-resolve` auto-includes the parent chain when a
child is selected. The hierarchy is recursive — a child can itself
subdivide later.

`/spec-split` is not usually run cold. Two natural triggers surface
candidates first:

- `/curate` housekeeping flags subdivision candidates in its
  "Subdivision Candidates" report section, with a suggested
  `/spec-split <id>` per candidate.
- `/spec-author` Pass 2 surfaces a just-in-time signal alongside
  Pass 2 findings when an amendment tips the in-progress spec into
  subdivision territory: "consider `/spec-split <id>` after this
  amendment lands."

Decline is a first-class outcome — subdivision should never be forced
on indivisible concerns. If a spec is mature but its requirements
form a single tightly-coupled concern, leave it whole. The user can
note the decline reason in the spec's design narrative; future
`/curate` passes will not surface it again immediately.

See `.spec/CLAUDE.md` (the "Layered specs" section) for the file
system layout, ID grammar (`a.b.c.d` → `domains/a/b/c/d.md`), and
validation rules.

---

## Running the audit pipeline standalone

`/audit` runs at the end of every `/feature` flow via `/feature-refactor`,
but it's also a standalone command for adversarial analysis of existing
code — either to revisit shipped features, validate a refactor, or
respond to a bug report with a systematic search.

Standalone entry points:

```
/audit "auth-middleware-rewrite"      # feature slug — audits that feature's constructs
/audit "src/crypto/wrap.rs"           # file path — audits all constructs in that file
/audit "encryption/primitives-lifecycle"  # spec id — audits against that spec's requirements
/audit "reports/2026-03-15-vector-index.md"  # prior audit report — resumes from it
```

The audit pipeline runs a multi-pass analysis (inventory → triage →
construct clustering → per-cluster deep analysis → reconciliation)
with pre-prove gates that filter findings before the expensive
prove-fix cycle. Every finding gets either proved with a failing test
+ fix, recorded as a spec obligation (wontfix cases, per PR #56), or
surfaced as advisory (non-testable — timing channels, for instance).

Domain-conditional lenses activate based on what the code does. The
security lens (v0.14.2+) triggers on credential stores, PII, auth
middleware, and deserialization — it adds adversary-model reasoning
(key lifecycle, IV/nonce reuse, ciphertext integrity, constant-time
comparisons) on top of the generic audit passes.

Budget caps are respected: Phase 0 detects already-fixed findings from
prior runs to avoid re-proving them. If a finding can't be fixed
because an existing test pins the current behavior, the FIX_IMPOSSIBLE
escalation flow gives you four routes (relax the pin test, wontfix
with obligation, spec-author to resolve the conflict, or defer).

---

## Capability tracking

`/capabilities` is a lightweight index of what the project can do —
useful for product questions ("do we support X?"), onboarding, and as
input to feature scoping.

```
/capabilities "do we support rate limiting per tenant?"   # natural-language search
/capabilities list                                         # browse by domain
/capabilities add "tenant-scoped rate limiting"            # create a new entry
/capabilities update "rate-limiting"                       # refine an existing entry
/capabilities backfill                                     # bootstrap from existing
                                                           # features, specs, ADRs
```

On a brownfield project, `/capabilities backfill` is the fastest way to
populate `.capabilities/` without manual entry — it reads existing
features, APPROVED specs, and accepted ADRs and proposes capability
entries for your review. Nothing lands without confirmation.

Capability entries are kept small and natural-language-searchable. They
are not specs — specs describe *guarantees*, capabilities describe
*what's available*. A spec tells you "if you call `rateLimit(tenant,
n)`, the system enforces the limit within 100ms"; a capability tells
you "rate limiting exists and is tenant-scoped."

---

## Quick tasks

For small changes that don't need the full pipeline — a single construct,
a bug fix, a config change:

```
/feature-quick "add isActive field to User model"
```

The complexity check runs first. If the task is genuinely small (0-1
complexity signals), it proceeds silently. If it detects scope creep
(4+ signals), it redirects you to `/feature` instead.

---

## First-time setup

After installing vallorcine into a project:

```
/setup-vallorcine
```

`/setup-vallorcine` is a one-time command that initialises the core
layers: `.kb/`, `.decisions/`, `.capabilities/`, `.feature/`, a project
profile (language, framework, test runner, conventions), and
`.gitignore` entries.

The spec layer (`.spec/`) is deliberately *not* created here — run
`/spec-init` separately when you're ready to start writing specs. This
matches the lazy-spec adoption path: specs have real ergonomic cost and
are opt-in per feature area.

Not sure where to start?

```
/vallorcine-help
```

It reads your project context and suggests the right command to run.

---

## Curation — finding quality gaps

Run a curation scan to surface quality signals across your codebase:

```
/curate
```

On an existing codebase, use `--init` for the first scan:

```
/curate --init
```

Curate finds ADR drift, stale KB entries, implicit dependencies, orphaned
areas, and out-of-scope items buried in accepted ADRs. For each finding,
it offers an action — research, review, or create a deferred stub so the
item shows up in `/decisions triage`.

Example finding: your `table-partitioning` ADR scoped out "replication
protocol" and "cross-partition transactions." Curate surfaces these as
deferred work you can choose to track:

```
── Out-of-scope items from table-partitioning ──────
This ADR (accepted 2026-03-15) scoped out these items:

  [1] Replication protocol (Raft/Paxos per partition) — separate decision needed
  [2] Cross-partition transaction coordination — separate decision

For each: create-stub · skip
Or: create-all · skip-all
```

Once promoted to deferred stubs, these items appear in `/decisions triage`.

---

## Narrative articles from feature retros

After completing a feature, `/feature-retro` generates a narrative markdown
article alongside the retrospective summary (when Python or Node.js is
available):

```
/feature-retro "encrypt-memory-data"
```

The narrative is written to `.feature/<slug>/narrative.md` and includes:
- shields.io badges (duration, tokens, model, vallorcine version)
- Mermaid gantt chart showing pipeline phases (Discovery/Execution/Delivery)
- Phase-by-phase breakdown with conversations, escalations, TDD cycles
- Progressive disclosure — skim via badges and headlines, deep dive via expandable blocks
- Duration showing only active work time (user wait and crash gaps excluded)
