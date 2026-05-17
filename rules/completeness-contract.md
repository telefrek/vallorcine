# Completeness Contract

This rule applies to every agent, skill, and dispatched subagent in vallorcine.
It governs how assigned scope is honored and how escalation works when
something genuinely prevents completion.

## The authority rule

You have no authority to defer assigned scope. The user is the only party who
can decide what work moves to a follow-on, gets dropped, or is intentionally
deferred. Your job is to complete the assigned work or escalate with proof —
not to make scope decisions on the user's behalf.

Default action: **fix it, finish it, ship it.** The bar is the assigned scope
(WD acceptance criteria, spec R-clauses, feature brief, user request) — not
"what I had time for" or "what seemed in scope to me."

## Trigger phrases (escalation signals, not completion modes)

When you find yourself writing any of these phrases, STOP. They are your cue
to construct an escalation, not to mark work COMPLETE:

- "candidate", "follow-on", "out of scope"
- "deferred", "future work", "for later"
- "we'll do this in a follow-up", "track separately"
- "not this PR's problem", "separate concern"
- "covered transitively", "edge case we can punt"
- "minor — can address later", "non-critical"

A return that claims `✓ COMPLETE` alongside any of these phrases is a contract
violation, regardless of how reasonable the deferral seems.

## Escalation channel

When you genuinely cannot complete assigned scope, escalate via AskUserQuestion
with this shape:

```
What is wired:
  <specific file:line citations of the state that IS working>

What is NOT wired:
  <specific file:line citations of the gap — what's missing or broken>

Why escalating rather than fixing:
  <the concrete blocker — the cost of picking blindly, the design ambiguity,
   the dependency that doesn't exist yet, the policy decision required>

Options (with cons, not just pros):
  1. <option A> — <what's good> — <what's bad / what it costs>
  2. <option B> — <what's good> — <what's bad / what it costs>
  3. <option C if any>

What I am NOT doing without approval:
  <the specific change you'd make if you had carte blanche>

What I AM doing:
  <the bounded work you're committing to in the meantime, if any>
```

Then **wait** for the user's decision. Do not mark COMPLETE.

The "What I am NOT doing" and "What I AM doing" lines are load-bearing —
they prevent the silent-deferral failure mode where the agent says
"escalating" but actually ships partial work and labels the rest as
follow-up.

The proof must be user-checkable:

- **Acceptable**: "Type `Codec<V>` referenced by `RadixWriter` does not exist —
  `grep -rn 'class Codec' src/` returns no matches."
- **Acceptable**: "Test `testCrossFamilyEquivalence` passes both before and
  after removing the new code path — the test does not exercise what it claims
  to verify."
- **Not acceptable**: "It's complex" / "we'd need to refactor" / "out of scope
  per my read" / "this would expand scope" / "I think this might be too much."

The first three are facts. The last set are judgment calls — and you don't
have authority for judgment calls about scope.

## Specific applications

The authority rule implies eight concrete contracts. Each catches a failure
mode the kit has seen repeatedly:

### 1. Verification contract

A test passing is not evidence the strong property holds. Two paths
producing identical output is a true assertion that proves nothing if
both paths route through the same legacy code.

Before claiming work COMPLETE, you must DEMONSTRATE (not just articulate)
that your tests catch the failure mode they're meant to catch:

1. **The fix is in the diff** — verifiable by `git diff`.
2. **A test asserts the actual property** at byte level, via reflective
   tripwire, via production-path assertion — not via round-trip behavior
   that the read path inverts.
3. **You SHOW why the test would fail without the fix.** Revert the fix
   locally (e.g., `git stash`), rerun the test, paste the failure into
   your return, then restore the fix (`git stash pop`).

The third clause is load-bearing. Without it, weak tests pass trivially
even when the fix is absent. With it, you have to either (a) write a
test strong enough to fail without the fix, or (b) discover your test
isn't strong enough and rewrite it.

"Looks right" is not closure. "I added a test" is not closure. The only
closure is "the test failed without the fix and passed with it, and
here is the evidence."

### 2. Production-path contract

Tests must exercise the live caller path, not internal SPI adapters or
direct construction of internal classes. Before writing a test, identify
the production entry point a real user hits to invoke this code, and
route the test through that entry point.

Per-component benchmarks and isolated SPI harnesses are useful for
understanding but are NOT evidence the production path behaves the same
way. If an ADR or spec change rests on measurements, those measurements
must be taken on the production path.

### 3. Measurement contract

Where the assigned scope calls for a measurement — performance, allocation
count, conformance count, end-to-end behavior — verbal arguments are NOT
substitutes. Run the measurement or escalate as PARTIAL with proof.

"The wrapping cost is uniform across families and cannot reverse the
ordering" is a hypothesis. Until you run it, it is not a finding.

### 4. Annotation contract

A `@spec R<n>` annotation is a claim that the annotated code enforces the
R-clause. Before adding an annotation, verify the code actually implements
the behavior. For "retired" or "removed" claims, grep the WHOLE codebase
for the deprecated symbol, not just the file you edited.

A spec marked SATISFIED with code that doesn't enforce the requirement is
worse than an unsatisfied spec — it tells downstream consumers (work-plan,
audit, spec-author) that the requirement holds when it doesn't.

### 5. Quality-bar contract

The repository's check command (./gradlew check, pnpm test, cargo test,
etc.) must pass before a PR is drafted or a WD is marked COMPLETE.
"Preexisting failures" is NOT an exemption.

If failures are genuinely preexisting and out of the current WD's scope,
they must be moved to `.flake-allowlist.md` with: (a) the failing test,
(b) the reason it's flaky/broken, (c) the assignee, (d) the deadline.
No deadline = no exemption.

### 6. Scope-reconciliation contract

Before returning COMPLETE, compare your output against the assigned
acceptance criteria item-by-item. For each AC item, point to the
specific code, test, or doc that satisfies it. If you cannot point to
something for an AC item, you have not completed the work — escalate
per the channel above or finish.

### 7. Test-replacement contract

If a test codifies a bug as the contract (the test passes BECAUSE the
buggy behavior is what it asserts), DELETE the test and write a new
one that asserts the FIXED behavior. Do not preserve "adversarial"
tests that lock in broken behavior, do not work around them, do not
add a new test alongside.

Subagents default to additive change — adding tests, not deleting.
That default ships bugs. Explicit permission to delete is required
because the alternative (work around the bug-codifying test) is the
path of least resistance.

A test deletion in a return MUST be accompanied by the new test that
replaces it, and the new test must satisfy the Verification contract
(§1 — revert-test-restore proof).

### 8. Structured-return contract

Returns must contain verifiable artifacts, not paragraphs of intent.
For each closed finding, the return must include:

- The fix's file:line citation (so the orchestrator can re-read it)
- The asserting test's name + file:line
- The revert-test-restore evidence from §1
- For deleted tests (§7): the deleted test's name + the replacement test's name

For escalated findings, the return must use the escalation channel
template (see below) — not a `TODO`, not a "follow-up note", not a
"will address later" sentence.

Paragraphs of intent ("I cleaned this up", "I made it more robust") are
not artifacts. Without specific items requested, returns drift into
prose. The orchestrator's validator catches some of this (trigger phrase
detection); the structured-return contract catches the rest by requiring
verifiable references.

## How dispatch uses this rule

Skills that dispatch subagents must include an explicit preamble in the
dispatch prompt:

```
BEFORE STARTING: read and honor rules/completeness-contract.md.
Violations of the authority rule, the verification contract, the
production-path contract, the measurement contract, the annotation
contract, the quality-bar contract, or the scope-reconciliation
contract are contract failures — not stylistic preferences. If you
find yourself about to violate one, construct the escalation per the
contract's escalation channel.
```

Orchestrators (work-orchestrator, feature-coordinate, work-run) must
validate returns from dispatched subagents against this contract before
accepting COMPLETE. Returns containing trigger phrases or missing AC
coverage must be routed back to the user via AskUserQuestion before
being accepted as COMPLETE.

## Scope confirmation is not deferral

Asking the user "what counts as in-scope for this WD?" BEFORE starting
is scope confirmation, not deferral — and is fine. Encouraged, even,
when the assigned scope is genuinely ambiguous.

Deferral is when you've started, made a judgment about what to drop, and
shipped less than assigned. The contract governs deferral, not scope
confirmation.

## Distinction from genuine PARTIAL

A genuine PARTIAL return is one where you completed all the work you
could and escalated the blocking issue with proof, then waited for the
user's call. The user may then approve continuing without the blocked
piece, in which case the work is legitimately PARTIAL — by user decision,
not by Claude's deferral.

What's prohibited is silently shipping PARTIAL while claiming COMPLETE.
