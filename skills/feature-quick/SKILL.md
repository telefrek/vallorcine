---
description: "Lightweight entry point for small, well-understood changes"
argument-hint: "<description>"
---

# /feature-quick "<description>"

A lightweight entry point for small, well-understood changes that don't need
scoping interviews, domain analysis, or work planning. Same TDD discipline as
the full pipeline — test → implement → refactor — with minimal setup.

Use this when:
- You already know exactly what needs to be built
- The change follows an established pattern in the codebase
- No architectural decisions are needed
- A full /feature pipeline would take longer than the work itself

Use /feature instead when:
- The change touches multiple systems or domains
- You need to decide between approaches
- The scope isn't clear yet
- The feature will take more than a session to implement

---

## Pre-flight guard

Check that `.feature/project-config.md` exists.
If not: "Run /setup-vallorcine to set up the project profile first."

---

## Idempotency pre-flight

Generate `quick-slug` from the description in kebab-case, prefixed with `q-`:
e.g. "add isActive to User" → `q-add-isactive-to-user`

Check if `.feature/<quick-slug>/status.md` exists.

**If it exists:**
Read it and report current state exactly as /feature-resume would.
Say: "This quick task was already started. Resuming." and jump to the
appropriate stage. Do not restart.

**If it does not exist:**
Create `.feature/<quick-slug>/` and write initial status.md.
Proceed to Step 1.

---

---

## Step 1 — Complexity assessment (ALWAYS FIRST, before any other work)

Before clarifying or proceeding, evaluate the description against the complexity
signals below. This check runs on the raw description alone — do not scan the
codebase yet.

### Complexity signals — count how many apply

**Scope signals**
- [ ] Mentions 2 or more distinct constructs (classes, modules, services)
- [ ] Uses words like "and", "also", "as well as", "plus" connecting distinct behaviours
- [ ] Touches more than one domain (e.g. "update the API and the database schema")
- [ ] Implies a new abstraction or pattern that doesn't exist yet

**Uncertainty signals**
- [ ] Description is vague about the expected interface or behaviour
- [ ] Contains "not sure how to", "figure out", "design", "decide between"
- [ ] No clear location in the codebase ("somewhere in the backend")

**Decision signals**
- [ ] Requires choosing between approaches ("should I use X or Y")
- [ ] Involves an architectural boundary (auth, persistence, external service)
- [ ] Would benefit from an ADR or KB lookup before writing code

**Size signals**
- [ ] Implies more than ~3 new constructs
- [ ] Would likely span more than one session to implement
- [ ] Feels like a "feature" rather than a "change"

### Thresholds and responses

**0–1 signals:** Proceed as /feature-quick. Display your understanding and continue.

**2–3 signals:** Soft warning. Display the assessment and ask for confirmation:

```
⚡ QUICK · <quick-slug>
───────────────────────────────────────────────
⚠️  This might be bigger than a /feature-quick task.

Signals I noticed:
  · <signal 1>
  · <signal 2>

/feature-quick works best for focused, single-construct changes.
For this, /feature would give you: scoping confirmation, domain analysis,
work planning with stub contracts, and crash recovery across sessions.

Options:
  1. Continue as /feature-quick — I'll keep it tight and flag scope creep if I find it
  2. Switch to /feature — run /feature "<description>" for the full pipeline

Use AskUserQuestion with options:
  - "Stay as quick"
  - "Switch to full /feature"
───────────────────────────────────────────────
```

If "Stay as quick": continue as /feature-quick, note the signals in status.md and proceed with
heightened scope vigilance (see Step 3).

**4+ signals:** Hard redirect. The description is clearly feature-scale:

```
⚡ QUICK · <quick-slug>
───────────────────────────────────────────────
⛔  This looks like a feature, not a quick task.

Signals I noticed:
  · <signal 1>
  · <signal 2>
  · <signal 3>
  · <signal 4>

/feature-quick is for single-construct, single-session changes. This description
suggests multiple constructs, multiple domains, or decisions that need
scoping before writing code.

Recommended: /feature "<description>"

I can still run this as /feature-quick if you're certain it's smaller than it sounds.

Use AskUserQuestion with options:
  - "Continue as quick (I understand the risk)"
  - "Switch to /feature"
───────────────────────────────────────────────
```

Only proceed as /feature-quick if user selects "Continue as quick".
Record forced override in status.md: `complexity_override: true`.

### After complexity check — understand the task

**If proceeding as /feature-quick after passing or confirming:**

Read the description. Make a judgment call:

**If the description is unambiguous** (clear construct, clear behaviour, clear
location in the codebase): display your understanding and proceed immediately.

```
I'll implement: <one sentence restatement>
Construct:      <what will be created or changed>
Location:       <where in the codebase>
Tests will verify: <the key behaviour>

Proceeding to tests. Say "stop" if this isn't right.
```

**If the description is ambiguous** (unclear scope, unclear expected behaviour,
or could mean multiple things): ask at most 2 targeted questions. Do not ask
about anything the implementation itself can decide.

Good questions:
- "Should this replace the existing X or sit alongside it?"
- "What should happen when the input is empty/null?"
- "Does this need to be backwards compatible with Y?"

Bad questions (don't ask these — decide them yourself):
- "What should I name the method?"
- "Should I add error handling?" (yes, always)
- "Should I write tests for edge cases?" (yes, always)

After at most one round of clarification, proceed. Do not interview.

---

## Step 2 — Write status.md

Write `.feature/<quick-slug>/status.md`:

```markdown
---
feature: "<quick-slug>"
created: "<YYYY-MM-DD HH:MM>"
last_updated: "<YYYY-MM-DD HH:MM>"
mode: "quick"
---

# Quick Task Status — <quick-slug>

## Description
<one-sentence restatement of the task>

## Construct
<what is being created or changed, and where>

## Current Position
**Stage:** testing
**Substage:** not-started
**Last successful checkpoint:** task described
**Complexity signals:** <n> detected
**Complexity override:** false

## Stage Completion

| Stage | Status | Completed | Notes |
|-------|--------|-----------|-------|
| Testing | not-started | — | cycle 1 |
| Implementation | not-started | — | cycle 1 |
| Refactor | not-started | — | cycle 1 |

## TDD Cycle Tracker

| Cycle | Tests written | Tests passing | Refactor done | Missing tests |
|-------|--------------|---------------|---------------|---------------|
```

Write `.feature/<quick-slug>/cycle-log.md`:

```markdown
---
feature: "<quick-slug>"
created: "<YYYY-MM-DD>"
mode: "quick"
---
# Cycle Log — <quick-slug>
---
## <YYYY-MM-DD> — started
**Agent:** Quick Command
**Summary:** Task started. <description>
---
```

Update `.feature/CLAUDE.md` Active Features table (mode: quick).

---

## Step 3 — Scan the codebase and check for governing specs

Read project-config.md for source directory, test directory, and conventions.

Scan the relevant part of the codebase — the module or file the change touches.
Do not do a broad scan. Read only what is needed to:
- Understand the existing interface the change extends or touches
- Know what test file to write into (or whether to create a new one)
- Confirm the change is as small as described (if it's larger, say so)

**Spec resolution (mandatory if `.spec/` exists).** Quick tasks that touch a
construct governed by an APPROVED spec must annotate the same way the full
pipeline does — otherwise traceability gets quietly skipped on the smallest
changes. Run:

```bash
if [[ -f .spec/CLAUDE.md || -d .spec/registry ]]; then
  mkdir -p .feature/<quick-slug>
  bash .claude/scripts/spec-resolve.sh "<task description>" 8000 \
    > .feature/<quick-slug>/spec-bundle.md
  bash .claude/scripts/spec-coverage.sh init \
    .feature/<quick-slug>/spec-coverage.md \
    .feature/<quick-slug>/spec-bundle.md
fi
```

If the bundle is empty (no specs match this scope) or `.spec/` doesn't
exist, the coverage file is vacuous and the rest of the spec workflow is a
no-op. If the bundle has rows, this task is now subject to the same
annotation rules as a full feature — Steps 4 and 5 below must add `@spec`
annotations and run `spec-coverage.sh update`, and Step 7 must verify the
gate before closing.

If the codebase scan reveals the change is larger than the description suggests:
```
⚠️  SCOPE CHECK · Quick → Feature
───────────────────────────────────────────────
This looks bigger than a /feature-quick task.
I found: <what makes it larger — be specific>

<If complexity_override: true in status.md:>
Note: you already confirmed proceeding as /feature-quick despite complexity signals.
Flagging for visibility — continuing unless you say stop.

<Otherwise:>
Options:
  1. Continue as /feature-quick — I'll implement what you described and note the larger
     context for later
  2. Upgrade to /feature — run /feature "<description>" for full pipeline support
```
Wait for response before continuing (unless complexity_override is already set,
in which case log the finding and continue).

---

## Step 4 — Write tests (failing)

Write tests for the described behaviour. Same rules as /feature-test:
- Against the public interface only
- Test names describe behaviour
- Must be verified to fail before proceeding
- **If `.feature/<quick-slug>/spec-coverage.md` has rows:** every test that
  satisfies a loaded requirement carries `@spec <spec-id>.R<n>` per
  `rules/spec-annotation-protocol.md`. After writing tests, run:
  ```bash
  bash .claude/scripts/spec-coverage.sh update \
    .feature/<quick-slug>/spec-coverage.md --all
  ```
  and verify each Test cell that should be annotated is now non-pending.

Display:
```
── Tests ───────────────────────────────────────
Tests I'll write:
  1. test_<n> — <scenario>
  2. test_<n> — <scenario>
Use AskUserQuestion with options:
  - "Approve"
  - "Describe changes"
  (include Other for custom input)
```
Write on "Approve" or immediately if the user provides changes.

Run the test suite. Confirm all new tests fail.
Update status.md: Testing cycle 1 → `complete`, substage → "tests verified failing".
Append `tests-written` to cycle-log.md.

Display:
```
── Tests written ───────────────────────────────
<n> tests written and verified failing.

───────────────────────────────────────────────
Use AskUserQuestion with options:
  - "Proceed"
  - "Stop"
───────────────────────────────────────────────
```
If "Proceed": proceed to Step 5.

---

## Step 5 — Implement

Implement the change. Same rules as /feature-implement:
- Minimum correct implementation
- Follow project-config.md conventions
- Never modify tests
- Escalate genuine contract conflicts (don't work around them)
- **Carry `@spec` annotations forward from the test** to the implementation
  method or smallest enforcing site, when the matching test was annotated.

Run tests after each logical unit. When all pass:

If `.feature/<quick-slug>/spec-coverage.md` has rows, refresh impl coverage:
```bash
bash .claude/scripts/spec-coverage.sh update \
  .feature/<quick-slug>/spec-coverage.md --all
```
Verify every loaded requirement has at least one annotated cell before
proceeding to Step 6. Fix annotations if cells are still pending.

Update status.md: Implementation cycle 1 → `complete`.
Append `implemented` to cycle-log.md.

Display:
```
── Implementation complete ──────────────────────
All tests passing.

───────────────────────────────────────────────
Use AskUserQuestion with options:
  - "Proceed"
  - "Stop"
───────────────────────────────────────────────
```
If "Proceed": proceed to Step 6.

---

## Step 6 — Refactor

Same checklist as /feature-refactor, same cycle limits (warn at 3, stop at 5),
same missing-test escalation rules. **Skip Step 4b (adversarial audit pass)** —
quick tasks don't have spec analysis findings to audit against, and the scope
is too small for adversarial testing to add value.

For a /feature-quick task the refactor is usually fast — most of the checklist will be
"nothing to do here" for a small change. Work through it anyway; security and
missing-test checks are the ones most likely to find something even on small changes.

Run full test suite after refactor. Must be all passing.
Update status.md: Refactor cycle 1 → `complete`, Refactor stage → `complete`.
Append `refactor-complete` to cycle-log.md.

---

## Step 7 — Close

If `.feature/<quick-slug>/spec-coverage.md` has rows, run the coverage gate
before closing. The gate is the structural enforcement of the annotation
protocol — quick tasks must clear it the same way full features do:

```bash
if [[ -f .feature/<quick-slug>/spec-coverage.md ]]; then
  bash .claude/scripts/spec-coverage.sh gate \
    .feature/<quick-slug>/spec-coverage.md
fi
```

If the gate fails: surface the uncovered list, give the user three
resolutions (annotate / waive / override with reason in the close note).
Do not mark the task complete until either the gate passes or the user
explicitly accepts the gap.

Update `.feature/CLAUDE.md` — move to Completed / Archived if the change is
committed and no further work is planned. Or leave in Active if it is part of
a larger piece of work still in progress.


Display:
```
───────────────────────────────────────────────
⚡ QUICK complete · <quick-slug>
  Tokens : <TOKEN_USAGE>
───────────────────────────────────────────────
Done. <n> tests passing.

Changes:
  <bullet list of what was written or changed>

<If the task revealed larger scope:>
Note: this touched <area> which may be worth a full /feature pass later.

───────────────────────────────────────────────
Use AskUserQuestion with options:
  - "Draft PR now"
  - "Skip"
  (run /feature-pr "<quick-slug>" any time)
───────────────────────────────────────────────
```

If "Draft PR now": invoke /feature-pr "<quick-slug>" as a sub-agent immediately.
If "Skip": stop.
