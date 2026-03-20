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
feature is large enough (6+ constructs with clean dependency boundaries),
it proposes splitting into work units that each run their own TDD cycle.

**4. Write tests, then implement**

```
/feature-test "rate-limiting-middleware"
/feature-implement "rate-limiting-middleware"
```

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
chain through test → implement → refactor → next unit without pausing.

The pipeline always pauses for two things regardless of mode:

- **Structural issues** (interface/contract changes in refactor steps 2c/2d)
  — these affect other units and need your judgement
- **Missing tests** (refactor step 2e) — a quality gate, not friction

Type anything into the session at any time to pause autonomous mode.
The pipeline picks up cleanly from where it stopped.

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
/research algorithms caching "LRU vs LFU eviction strategies"
```

Arguments: `<topic> <category> "<subject>"`. The Research Agent writes
findings to `.kb/algorithms/caching/lru-vs-lfu-eviction-strategies.md`.

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

Revisit a confirmed decision with a fresh deliberation:

```
/decisions review "rate-limit-state-store"
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

`/setup-vallorcine` is a one-time command that initialises everything:
`.kb/`, `.decisions/`, `.feature/`, project profile (language, framework,
test runner, conventions), and `.gitignore` entries.

Not sure where to start?

```
/vallorcine-help
```

It reads your project context and suggests the right command to run.
