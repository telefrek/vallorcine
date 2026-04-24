# Getting Started with vallorcine

Vallorcine is a Claude Code kit for shipping real features on real codebases
without losing the context you build up along the way. It turns research,
architecture decisions, specifications, tests, and code into connected
assets that feed each other — so your 5th feature is faster than your 1st
instead of slower.

This document is the new-user overview. It explains:
- The four knowledge layers and how they relate
- The feature pipeline in plain language
- When you need work groups (multi-feature coordination)
- Curation — how the system catches drift
- A decision tree for "what do I run when?"

If you already have vallorcine installed and just want the command
reference, read [README.md](README.md). For the architecture and the ten
core design principles, read [DESIGN.md](DESIGN.md).

---

## The mental model: four knowledge layers

Vallorcine keeps four kinds of information separate, each with its own
directory and its own lifecycle.

```
.kb/         — research findings (how things work)
.decisions/  — architecture decisions (why we chose X over Y)
.spec/       — behavioral contracts (what the system guarantees)
.feature/    — active feature work (what we're building right now)
```

A fifth directory, `.capabilities/`, is a lightweight index of what the
project can do — searchable by natural language, useful for "do we
support X?" questions and as input to future feature scoping. It's
created alongside the four layers but isn't part of the core mental
model.

### When each layer gets created

`/setup-vallorcine` bootstraps `.kb/`, `.decisions/`, `.capabilities/`,
and `.feature/` in one shot on first install. `.spec/` is deliberately
*not* created by `/setup-vallorcine` — specs are opt-in. When you're
ready to start writing specs for a feature area, run `/spec-init` once
to initialize the spec registry, then use `/spec-author` per feature.
This matches the lazy-spec philosophy: the spec layer has real
ergonomic cost, and you don't want it active until you have behavior
worth specifying. See
[GETTING-STARTED-EXISTING.md](GETTING-STARTED-EXISTING.md) for the
incremental-adoption path on brownfield projects.

Think of them as the four questions a mature project has to answer:

| Layer | Answers | Written by | Read by |
|-------|---------|-----------|---------|
| **Knowledge** (`.kb/`) | *How does X work?* Research on algorithms, libraries, protocols. | `/research`, `/feature-retro` | `/architect`, `/feature-domains`, `/feature-test` |
| **Decisions** (`.decisions/`) | *Why did we choose X over Y?* ADRs with full deliberation. | `/architect`, `/decisions backfill` | `/feature-domains`, `/feature-plan`, `/spec-author` |
| **Specifications** (`.spec/`) | *What does the system guarantee?* Behavioral contracts with requirement IDs. | `/spec-author`, `/spec-write` | `/feature-plan`, `/feature-test`, `/audit`, `/spec-verify` |
| **Features** (`.feature/`) | *What are we building right now?* Session state + test plan + implementation context. | `/feature` and its pipeline stages | The pipeline itself (crash recovery, resume) |

### How they feed each other

The layers aren't independent — they form a flow:

```
Research (KB)  ──feeds──▶  Architecture decisions (ADRs)
     │                              │
     │                              ▼
     │                         Specifications
     │                              │
     ├────────────────┬─────────────┤
     ▼                ▼             ▼
Domain analysis ──▶  Test plan  ──▶  Implementation
                     (tests)         (code)
     │                ▲               │
     │                │               │
     │         Audit finds bugs ──────┘
     │         (patterns go back to KB)
     ▼
Feature retrospective
     │
     └──▶ writes back to KB (new patterns learned)
           writes back to decisions (drift noted)
```

Concrete example:

1. You run `/research "HNSW graph construction"` — an agent investigates,
   writes findings to `.kb/algorithms/vector-indexing/hnsw.md` with a
   `last_researched` date.
2. Later, when choosing an ANN algorithm, `/architect` pulls that KB
   entry into deliberation — you don't re-research HNSW, you build on
   what's there. The resulting ADR lands in `.decisions/ann-algorithm/`.
3. When you write a spec for the indexing behavior, `/spec-author` reads
   both the KB entry and the ADR as input — the spec codifies what the
   system will guarantee, using the algorithm choice the ADR settled.
4. `/feature-plan` reads the spec as its primary context. Tests are
   generated from the spec's requirements (R1, R2, ...). Implementation
   makes those tests pass.
5. `/audit` runs adversarial analysis against the implementation,
   looking for the spec's requirements being violated under edge
   conditions. Bugs found here become KB entries (adversarial patterns)
   that `/feature-test` uses on the *next* feature — so the same class
   of bug gets prevented before it's written.
6. `/feature-retro` at the end of the feature writes back: new KB
   entries from what you learned, updates to ADRs if assumptions
   shifted, and a narrative that captures the arc.

The writing directions are strictly partitioned. Each agent can only
write to its designated layer — `/research` cannot write ADRs, `/audit`
cannot modify specs, etc. This is what keeps the layers from turning
into a single mess of mixed-concern files.

---

## The feature pipeline

`/feature "<description>"` walks a single feature from an idea to a PR
through a structured TDD pipeline. Each stage has a clear input
(previous stage's output on disk) and a clear output (next stage's
input). If a session crashes, you resume where you stopped — the state
lives in `.feature/<slug>/status.md`, not in conversation memory.

The stages, in order:

1. **Scoping** — 3-4 question interview to nail down the brief. Produces
   `.feature/<slug>/brief.md`.
2. **Domains** — identifies which domains the feature touches, pulls in
   relevant KB, ADRs, and specs. Commissions new research/ADRs if gaps
   are found. Routes to `/spec-author` if the project uses specs and
   the feature needs a new one.
3. **Planning** — produces `.feature/<slug>/work-plan.md` with every
   construct (class, function, type, file) the feature will add or
   change. Picks an execution strategy: `cost` (sequential, one unit at
   a time), `balanced` (batched parallel), `speed` (max parallelism).
4. **Testing** — Test Writer Agent generates a test plan from spec
   requirements (if specs exist) or from the brief + domain patterns.
   Every test fails first (red phase confirmed).
5. **Hardening** (optional) — adversarial test pass against domain-lens
   behavioral attacks on the contracts, before implementation.
6. **Implementation** — Code Writer Agent makes the tests pass, never
   modifies the tests. If a test seems wrong, it escalates rather than
   editing.
7. **Refactor** — quality review (8-item checklist), then delegates to
   `/audit` for adversarial bug finding. Audit findings either get
   fixed inline or escalate for triage (never silently ignored).
8. **PR draft** — `/feature-pr` assembles title, description, checklist
   from the feature's artifacts. Human reviews, edits, and submits.
9. **Retrospective** — `/feature-retro` writes back learnings to KB,
   updates to decisions, and optionally generates a narrative article.

### When to use `/feature` vs `/feature-quick`

- **`/feature`** for substantial work: multi-file changes, anything
  touching business logic, anything requiring tests. Full pipeline with
  spec analysis, planning, TDD, audit.
- **`/feature-quick`** for single-session trivial changes: add a field,
  rename a method, add a helper. No planning document, no multi-session
  state. If you type `/feature-quick` and it detects complexity signals
  (cross-cutting changes, multiple files, "refactor", new dependencies),
  it will suggest escalating to `/feature` instead.

When in doubt, run `/vallorcine-help "<what you're about to do>"` — it
routes you to the right entry point.

---

## Work groups — multi-feature coordination

A single `/feature` run is great for self-contained changes. Real
projects have larger initiatives: "migrate auth from session tokens to
JWT", "add encryption to the storage layer", "replace the query planner".
These span multiple features, have real cross-feature dependencies, and
benefit from being planned as a coordinated batch.

Work groups (`.work/<group-slug>/`) are how vallorcine represents this.

### The work-group flow

```
/work "<goal>"                — create the work group, capture the goal
/work-decompose "<slug>"      — break the goal into work definitions
                                (WDs) with explicit dependencies
/work-status "<slug>"         — show readiness: what's READY, BLOCKED,
                                IN_PROGRESS, COMPLETE
/work-plan "<slug>" next      — specify a WD (produce specs/ADRs for it)
/work-start "<slug>" next     — implement a specified WD
                                (runs the full feature pipeline)
```

### What makes work groups powerful

**Artifact-based dependencies.** A WD declares what it produces (a spec,
an interface contract, an ADR) and what it depends on (produced by
another WD). Readiness is computed mechanically — when a dependency's
artifact lands, the consuming WD automatically moves from BLOCKED to
READY. No manual tracking.

**Two pipeline modes per WD:**
- **Specification-only** (`/work-plan`) — for WDs whose job is to
  produce a spec or an ADR, not code. Ends when the artifact is
  APPROVED.
- **Implementation-only** (`/work-start`) — for WDs whose spec already
  exists. Skips domain analysis and spec authoring, goes straight to
  planning → tests → code.

**Parallel dispatch** (`/work-start <group> --parallel [N]`) runs every
SPECIFIED WD as a concurrent sub-agent in isolated contexts. A wave of
five WDs can finish in roughly the time of one instead of five. The
concurrency caveats (shared KB writes, test contention, cost budget)
are documented inline in the skill.

### When you don't need work groups

If your whole change fits in a single feature, skip work groups entirely.
`/feature "<description>"` handles it directly — work groups are for
initiatives that genuinely span multiple coordinated features.

---

## Curation — catching drift

The four layers accumulate assets. Over time, they drift:

- An ADR says "we chose approach X" but the code actually implements Y.
- A KB entry was researched 6 months ago; the library has changed.
- A spec claims R5 is enforced by `UserService`, but the annotation is
  gone and nothing verifies the requirement anymore.
- A work group has 3 WDs still open with no updates for weeks.

`/curate` is the command that scans for these signals periodically.

- **`/curate --init`** — first-time scan on an existing codebase. Pulls
  candidate decisions and research topics out of git history, surfacing
  things that *should* have been captured. Good starting point on
  brownfield projects — see [GETTING-STARTED-EXISTING.md](GETTING-STARTED-EXISTING.md).
- **`/curate`** — incremental scan. Runs in minutes. Reviews quality
  signals since the last run: stale decisions, knowledge gaps, spec
  drift, aging obligations.
- **`/curate --deeper`** — 6-month scan instead of the default 3, for
  periodic deep reviews.

Findings are presented as a numbered list. You pick by number; curate
routes each one to the right follow-up command (`/spec-verify`,
`/research`, `/architect`, `/decisions revisit`, etc.). Nothing is
auto-fixed — curation surfaces, humans decide.

---

## What to run when — decision tree

```
Are you starting something new?
│
├─ Small, single-file, no tests needed
│  → /feature-quick "<description>"
│
├─ Normal feature (tests, multi-file, business logic)
│  → /feature "<description>"
│
└─ Multi-feature initiative (e.g., "migrate auth to JWT")
   → /work "<goal>"
     → /work-decompose "<slug>"
     → /work-plan "<slug>" next    (specify each WD)
     → /work-start "<slug>" next   (implement each specified WD)

Are you looking for existing knowledge?
│
├─ General question about how something works
│  → /kb "<question>"             (queries research)
│
├─ Looking for a past decision
│  → /decisions "<question>"       (queries ADRs)
│  → /decisions list                (browse all)
│
├─ Looking for behavioral guarantees
│  → /spec "<question>"            (queries specs)
│
└─ Just want to know what's going on
   → /project-context              (all active team-shared context)

Do you need to research or decide something?
│
├─ Research a topic into the KB
│  → /research "<subject>"
│
├─ Make an architecture decision
│  → /architect "<problem>"
│
└─ Revisit a past decision that might be wrong now
   → /decisions revisit "<slug or topic>"

Are you onboarding an existing codebase?
│
└─ → /setup-vallorcine             (one-time kit setup)
     → /curate --init              (pull candidates from git history)
     → See GETTING-STARTED-EXISTING.md for the full path

Not sure?
│
└─ → /vallorcine-help              (the router — asks you one question,
                                     hands you the right command)
```

---

## Where to go next

- **[README.md](README.md)** — full command reference and install guide.
- **[GETTING-STARTED-EXISTING.md](GETTING-STARTED-EXISTING.md)** — how to
  onboard an existing codebase gradually instead of trying to spec
  everything upfront.
- **[DESIGN.md](DESIGN.md)** — the architecture: ten core principles,
  write-authority partitioning, crash recovery, token budgets.
- **[COMPETITIVE.md](COMPETITIVE.md)** — how vallorcine fits into the
  Claude Code plugin ecosystem and what it does that other kits don't.
- **[EXAMPLES.md](EXAMPLES.md)** — end-to-end walkthroughs: building a
  feature, querying the KB, crash recovery, the autonomous TDD loop.

### First 30 minutes with vallorcine

If you just installed vallorcine on a fresh project:

1. Run `/setup-vallorcine` — creates `.kb/`, `.decisions/`,
   `.capabilities/`, `.feature/`, and the project config. `.spec/` is
   not created yet; run `/spec-init` separately when you're ready to
   start writing specs.
2. Run `/vallorcine-help` — get a guided tour of what each concern does.
3. Pick a small first feature and run `/feature-quick "<description>"`
   — learn the rhythm before you commit to the full pipeline.
4. Once you have one feature under your belt, run `/feature` on a
   normal-sized change and watch how domain analysis, tests, and code
   connect — and run `/spec-init` when that feature introduces
   behavior worth specifying.

If you installed on an existing codebase that already has significant
history, read [GETTING-STARTED-EXISTING.md](GETTING-STARTED-EXISTING.md)
next — the recommended path is different.
