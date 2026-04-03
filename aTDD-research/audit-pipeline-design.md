# Audit Pipeline Design

Design document for the vallorcine audit pipeline. This defines the cognitive
jobs, their responsibilities, contracts, and performance expectations.

**Status:** In progress — iterating job-by-job with adversarial review.

---

## Intent

A structured, language-agnostic code review that finds missing/incorrect
functionality, spec/ADR drift, and dead code across any scope (feature, spec,
file, method). Findings are proven with failing tests and closed with fixes.

Prior vallorcine artifacts (specs, KB, ADRs) make the audit faster (fewer
reasoning turns), cheaper (less code exploration and smaller context windows),
and more complete (known patterns surface findings that structural analysis
alone would miss). A project with no prior artifacts gets a correct but more
expensive audit. The cost floor is the source code under analysis — prior
artifacts reduce overhead above that floor.

## Success criteria

1. **Precision and recall** — finds what's there, doesn't invent what isn't.
   Benchmark: >=90% of known bugs detected.
2. **Runs unattended on well-formed input** — zero human intervention for a
   clean run. Malformed input fails fast with clear messages.
3. **Every finding classified** — confirmed failure, theoretical concern,
   not testable, compile-skipped, or spec drift. No orphaned findings.
4. **Incremental rounds >=50% cheaper** — round 2 token usage is at most
   half of round 1 when analyzing the same scope.
5. **Codebase strictly better** — more tests, fewer bugs, no unintended
   behavior changes, no regressions.

## Design principle (not measured, shapes decisions)

- Cost should be comparable to or less than equivalent unstructured work.

---

## Cost model

### The dominant cost driver: carry cost

Analysis of real audit session data (480-560 turn sessions) reveals that
**99.6% of all input token cost is carry cost** — re-sending the entire
conversation history on every turn. File reads account for less than 0.1%
of total cost.

Claude's input cost per turn is the entire conversation history. A context
window that grows linearly over N turns produces quadratic total cost
(sum of 1 + 2 + ... + N). A 480-turn session pays ~260x what a single-turn
interaction would cost for the same content.

### Implications for pipeline design

| Insight | Design consequence |
|---------|-------------------|
| Turns, not reads, drive cost | Optimize for fewer turns per session, not fewer file reads |
| Re-reading a file in a short session is cheap | Don't build summaries to avoid re-reads — summaries have carry cost too |
| 10 parallel 5-turn subagents < 2 sequential 25-turn subagents | Prefer many small parallel sessions over few large sequential ones |
| Spending more in Scope saves more downstream | Front-load analytical work to eliminate exploratory turns later |
| Summaries only save cost if `summary_size × session_turns < source_size × session_turns` | For short sessions, raw source is cheaper than carrying a summary |
| Launch overhead is trivial vs. carry cost | Don't avoid subagents to save launch cost |

### The "read once" fallacy

The prior pipeline design assumed reading a file multiple times was wasteful
and invested heavily in summarization to avoid re-reads. This is wrong:

- A 200-line file read in a 5-turn subagent costs 200 × 5 = 1,000 token-turns
- A 30-line summary of that file carried through 40 turns costs 30 × 40 = 1,200 token-turns
- The summary is MORE expensive AND less accurate (hallucination risk, missed implicit assumptions, staleness)

The correct optimization is **minimize turns per session**, not minimize reads
per pipeline run. Each downstream subagent should read the source it needs
directly, analyze in 3-10 turns, write findings, and terminate.

---

## Pipeline jobs

Five cognitive jobs, executed in order. Map (from the original six-job design)
was absorbed into Scope because the cost model shows that front-loading
analytical work into one session — even a longer one — eliminates more turns
downstream than it costs.

| # | Job | Purpose | Session model |
|---|-----|---------|---------------|
| 1 | **Scope** | Define boundary, read source, build construct graph, cluster, resolve context, produce per-cluster input packets | 3 subagents: Classification → Exploration → Assembly |
| 2 | **Suspect** | Identify where bugs could hide and what kind | One subagent per cluster (serial) |
| 3 | **Prove** | Demonstrate each suspected bug with a failing test | One subagent per finding (serial) |
| 4 | **Fix** | Make the failing tests pass without breaking anything else | One subagent per finding attempt + regression subagent per cluster |
| 5 | **Report** | Classify outcomes and produce the artifact that enables the next round | Single subagent |

**Finding IDs:** `F-R{round}.{cluster}.{seq}` — includes round number to
prevent collisions across incremental rounds.

**De-scoping protocol:** Any stage can shrink scope by moving constructs to
the exclusion list with a reason. No stage can grow scope. De-scoped items
are recorded in stage output and automatically become candidates for the next
round's Scope input.

**Execution model: serial by default.** All subagents run serially. The cost
savings come from short sessions with fresh context windows, not from
parallelism. Serial execution eliminates concurrent file modification
conflicts, race conditions between subagents, and orchestrator complexity
for tracking parallel completion. Parallel execution is an optimization to
add later only when proven safe — never a default.

**Orchestrator:** An LLM session that launches subagents via the Agent tool.
The orchestrator is a state machine — it MUST delegate all analytical work
to subagents. It reads structured output files to determine what to launch
next (cluster count, finding count, etc.) and displays progress to the user.

Orchestrator discipline:
- DO NOT read source files
- DO NOT analyze pipeline outputs beyond reading counts and file paths
- DO NOT run tests, compile code, or parse test output
- DO NOT make analytical decisions — all judgment belongs in subagents
- Every action the orchestrator takes must be: launch subagent, read
  one-line return, update progress, launch next subagent

**Progress display:** The orchestrator uses TodoWrite to maintain a task
list. Tasks are created at the start of each stage and marked complete
as subagents finish. The native Claude Code task display gives the user
clean, structured visibility into what's done, what's in progress, and
what's remaining.

---

## Job 1: Scope

### Purpose

Front-load analytical work so downstream subagents can be short and focused.
Scope is split into three subagents to avoid the carry cost that a single
long session would accumulate. Each subagent has a distinct responsibility
and produces structured output for the next.

### Subagent 1: Classification (interactive)

The only user-facing session. Resolves the entry point, gathers context,
and produces a starting point for Exploration.

**Entry point resolution:**
- Accept any entry point: spec reference, file list, class/method name,
  feature slug, or prior audit report
- Interrogate the user to confirm boundaries and resolve ambiguity
- Translate entry point into concrete initial file paths

**Prior work detection:**
- Detect existing audit reports for the same scope
- Identify what changed since the last audit (git diff)
- Load prior clearing reasoning, removed test classifications, and
  frontier information from `audit-prior.md`

**Context gathering (done once, consumed by all downstream stages):**
- Resolve relevant specs via spec-resolve.sh
- Select relevant KB entries and ADRs by reading index files (LLM judgment
  on small index files, then bash pulls selected entries)
- Resolve full content for selected entries — no downstream stage ever
  queries these systems

**Partition proposal (when scope exceeds single-pass budget):**
- Estimate whether the analysis surface fits a single round
- When decomposition is needed, propose rounds that minimize cross-round
  edges (partition quality over partition size)
- Target 30-80 constructs per round. Set a minimum — too many small rounds
  is worse than fewer medium rounds
- Present partition to user with uncertainty flags: "confident these are
  separable, less confident about these 3 constructs at the boundary"
- User confirms or adjusts before proceeding

**Outputs:**
- Initial file paths and confirmed boundaries
- Prior work summary (clearings, removed test classifications, frontier)
- Context package (resolved specs, KB entries, ADRs)
- Language and project structure detection

### Subagent 2: Exploration (non-interactive)

Starts from Classification's initial file paths and explores outward,
building the construct graph while making tiering decisions in real time.
Stops when it hits the analysis budget or exhausts reachable constructs.

**Exploration protocol:**
- Read source files starting from the entry points
- Identify constructs: name, kind, location (file + line range),
  parameters, return type, visibility, mutability
- Follow edges outward (imports, type references, method calls) to
  discover connected constructs
- Make tiering decisions during exploration:
  - **Analyze** — pull into scope for deep analysis
  - **Boundary** — read contract only (signatures, documented behavior),
    stop exploring this direction
  - **Ignore** — stop, don't explore further
- Depth limit: no more than 2 hops from an analyze-tier construct for
  boundary tier. Beyond 2 hops = ignore.
- Fan-in promotes (many dependents = must analyze regardless of size)
- Stop when analyze-tier construct count hits the budget or all
  reachable constructs within depth limit are classified

**Prior work integration:**
- Previously-cleared constructs: verify the prior clearing still holds
  (cited defense still exists on cited line, no new paths bypass it).
  If clearing holds, keep as cleared — do not add to analyze tier.
  If clearing is invalidated, promote to analyze tier.
- NEEDS-REVISIT findings from prior rounds: prioritize these constructs
  for re-exploration with the prior context about what was tried
- Frontier from prior rounds: explore these areas first to advance
  coverage rather than re-covering known ground
- INVALID findings: do not re-explore unless surrounding code changed

**Scope tiering (three tiers):**
- **Analyze** — constructs under deep analysis. Bugs are expected here.
- **Boundary** — adjacent constructs whose contracts are relevant but not
  under analysis. Signatures, types, documented behavior only.
- **Ignore** — everything else. Hard constraint — downstream stages cannot
  read these files. Not a suggestion.

**Boundary contract extraction:**
- For boundary-tier constructs, read signatures and documented behavior
  (targeted offset/limit reads, not full files)
- Record: what does this construct guarantee to callers? What does it
  assume about inputs?

**Domain detection (for concern area activation):**
- During source reading, detect codebase signals that activate
  domain-conditional concerns:
  - HTTP handlers, route definitions → information flow, injection, auth
  - Thread pools, synchronized blocks, async/await → concurrency concerns
  - External service calls, message queues → distributed consistency
  - Crypto imports, key/hash/cipher usage → cryptographic misuse
  - Environment variable reads, config file parsing → configuration sensitivity

**Outputs:**
- Complete construct graph (analyze + boundary tiers with file paths,
  line ranges, edges with weights)
- Boundary contracts for boundary-tier constructs
- Ignore list with reasons
- Detected domain signals
- Frontier — what was at the edge of scope and why exploration stopped
  (feeds next round)
- Exclusions — what was moved out of scope and why
- `exploration-decisions.jsonl` — structured decision log for diagnostic
  analysis (see below)

**Exploration decision log (required):**

Every tiering decision, clearing verification, frontier stop, and domain
signal detection is logged as a JSONL entry. All fields are required — a
missing field is a defect flagged by the diagnostic tool.

Entry types:

```jsonl
{"type":"tier_decision","construct":"Name","file":"path","lines":[10,85],"tier":"analyze|boundary|ignore","reason":"fan_in_high|depth_limit|budget_full|edge_weight|user_confirmed","fan_in":12,"depth":1}
{"type":"clearing_check","construct":"Name","file":"path","prior_clearing":"validation on line 48","cited_line":48,"still_exists":true,"result":"cleared|promoted","reason":"defense_intact|line_changed|new_path_added"}
{"type":"frontier_stop","construct":"Name","file":"path","direction":"outward_from_X","reason":"depth_limit|budget_full|no_more_edges","depth":2,"budget_remaining":3}
{"type":"domain_signal","signal":"http_handler|crypto_import|thread_pool|external_service|env_variable","file":"path","line":15,"concerns_activated":["injection","info_flow"]}
{"type":"prior_work","construct":"Name","prior_classification":"NEEDS-REVISIT|INVALID|DESIGN-CHANGE|cleared","action":"re-explore|skip|promote","reason":"..."}
```

This log enables the diagnostic to:
- Verify no high-fan-in construct was placed in boundary or ignore
- Verify NEEDS-REVISIT constructs were prioritized over known ground
- Verify INVALID constructs were skipped unless surrounding code changed
- Check whether budget ran out early (scope too conservative) or was
  never reached (scope too aggressive)
- Map domain signals to clusters and verify concern activation consistency
- Audit why specific constructs were excluded (traceable decisions)

### Subagent 3: Assembly (non-interactive)

Receives Exploration's structured output and Classification's context
package. Works entirely over structured data — never reads source code.

**Clustering:**
- Partition analyze-tier constructs into clusters for downstream subagents
- Unsplittable groups: constructs sharing mutable state or within-type
  data flow
- Constructs in the same file must be in the same cluster (prevents
  concurrent file modification conflicts in Fix)
- Cluster by coupling strength, not by file or size
- Target cluster sizes that fit a single short downstream session
  (3-8 constructs)
- Record cross-cluster edges explicitly

**Per-cluster input packet assembly:**
- For each cluster, assemble a self-contained input packet containing:
  - Construct list with file paths and line ranges
  - Relevant edges (within-cluster + cross-cluster boundary annotations)
  - Boundary construct contracts (from Exploration's extraction)
  - Relevant spec requirements, KB entries, ADRs (from Classification's
    context package, embedded not referenced)
  - Prior clearing reasoning for previously-analyzed constructs (if any)
  - Applicable concern areas (core concerns always included;
    domain-conditional concerns activated based on Exploration's
    detected domain signals)
  - Budget signal (construct count, applicable concern areas)
- Each packet is everything a downstream subagent needs in its initial
  prompt — the subagent should not need to read any artifact files or
  fetch any context

**Domain signal mapping:**
- Map Exploration's detected domain signals to specific clusters
- A cluster touching HTTP handlers gets injection + info flow + auth
  concerns activated; a pure data structure cluster does not
- Include only activated concerns in each cluster's packet

**Outputs:**
- `scope-definition.md` — tiers, construct graph, cluster assignments,
  detected domains
- `cluster-{N}-packet.md` — self-contained input for cluster N
- `scope-exclusions.md` — what was moved out of scope and why

### Scope must NOT

- Make judgments about what's likely buggy (that's Suspect's job)
- Grow scope beyond what the user confirms
- Proceed past budget threshold without user confirmation of partition
- Leave context resolution to downstream stages — all context must be
  gathered and embedded by Scope

### Performance expectations

These are testable assertions. Violation of any expectation during a real run
indicates either a prompt bug or a wrong assumption in this design.

| Expectation | How to verify | What violation means |
|-------------|---------------|---------------------|
| Each Scope subagent completes in <=15 turns | Count turns per subagent | Subagent is doing work that belongs in a different subagent |
| Total Scope cost is lower than equivalent single-session approach | Compare 3-subagent cost to estimated single-session cost | Splitting didn't reduce carry cost enough to justify handoff overhead |
| No downstream subagent queries specs/KB/ADRs | Grep subagent transcripts for spec-resolve, kb index reads | Cluster packets are incomplete |
| No downstream subagent reads ignore-tier files | Grep subagent transcripts for ignore-tier file paths | Ignore list isn't enforced |
| No downstream subagent reads artifacts to fetch context | Grep for reads of scope-definition.md, scope-context.md, etc. from subagents | Packets aren't self-contained |
| Downstream subagents complete in <=10 turns each | Count turns per subagent session | Subagent is doing exploratory work that belongs in Scope |
| Boundary contracts are consumed from packets, not re-read from source | Grep for source file reads of boundary-tier constructs in subagents | Contract extraction was incomplete |
| Incremental scope (prior report exists) is >50% cheaper than fresh | Compare fresh vs incremental scope costs | Prior work detection isn't reducing work |
| Exploration prioritizes new territory over known ground | Compare constructs explored vs. prior-cleared constructs | Exploration is re-covering old ground instead of advancing frontier |
| Each cluster packet is <4K tokens | Measure packet sizes | Packets carry unnecessary context or raw source |
| Same-file constructs are in the same cluster | Check cluster assignments against file paths | Assembly missed same-file grouping |

### Failure modes and mitigations

| Failure mode | Mitigation | Verification |
|-------------|-----------|-------------|
| Bug IS the boundary — producer/consumer in different rounds miss mismatch | Boundary contracts record guarantees + assumptions; Report auto-promotes boundary constructs involved in findings to analyze tier for next round | Check if findings reference boundary constructs; if so, next round must promote them |
| Boring construct shed — small high-fan-in utility deferred | Fan-in promotes regardless of size/complexity; never shed based on "boringness" | Verify no high-fan-in construct is in ignore or boundary tier |
| Death by a thousand rounds — too many small rounds | Minimum round size (30 constructs); partition quality metric (minimize cross-round edges) | Count rounds; flag if any round <30 constructs without justification |
| Prior work false negative — prior audit missed a bug, clearing locks it in | Exploration re-verifies prior clearings by checking cited defense still exists. If invalidated, promote to analyze tier. | Track how many prior clearings are invalidated per round |
| User confirms wrong partition | Scope flags uncertainty on boundary constructs; Report detects partition errors (findings concentrated at boundaries) | Track finding-to-boundary-construct ratio; flag if >50% of findings involve boundary constructs |
| Exploration re-covers known ground instead of advancing | Prior work integration prioritizes: NEEDS-REVISIT → frontier → adjacent-to-findings → re-validate cleared. Exploration budget is spent on new territory first. | Compare new vs. previously-seen constructs in analyze tier |

---

## Job 2: Suspect

### Purpose

Find every bug in an assigned cluster by reasoning about concrete attacks.
Each Suspect subagent is a short, parallel session (5-10 turns) that reads
source directly, analyzes constructs against applicable concern areas, and
writes structured findings and clearings.

### Session model

One subagent per cluster, run serially. Each subagent receives a cluster
packet in its initial prompt and reads source files via offset/limit for
the constructs in its cluster. The session is short — analyze, write
findings, terminate.

### Concern areas

Suspect checks each construct against applicable concern areas. The core set
is always checked. Domain-conditional concerns are included only when Scope
detected relevant codebase signals and activated them in the cluster packet.

**Core (always checked):**

| # | Concern | What it finds |
|---|---------|---------------|
| 1 | **Validation gaps** | Bad values accepted without verification. Includes range, type, null, size, overflow — any input the code uses without checking. Subsumes the old "input validation" and "capacity/bounds" concerns. |
| 2 | **Transformation fidelity** | Data changes form and loses meaning. Precision loss in numeric conversion, encoding errors, lossy serialization, truncation during format change. The bug is not that data is missing — it's that data is wrong after transformation. |
| 3 | **Contract violations** | Observable behavior differs from documented or implied promise. Wrong return value, wrong exception type, violated postcondition, misleading method name, stale documentation. |
| 4 | **State machine correctness** | Operation sequences produce invalid state. Implicit ordering assumptions, re-entrant calls during transitions, use after terminal state, partial initialization. Generalizes the old "resource lifecycle" concern — open/close is one state machine, but the concern is broader. |
| 5 | **Silent failure** | Code handles a case by doing nothing or doing the wrong thing without signaling. Swallowed exceptions, default branches that mask errors, missing enum cases, fallbacks that hide problems from callers. |
| 6 | **Semantic/logic errors** | Correct implementation of wrong algorithm. Off-by-one, inverted conditions, wrong precedence, algorithm that doesn't match the domain requirement. Distinct from contract violations — the contract itself may be wrong or absent. |

**Domain-conditional (activated by Scope):**

| # | Concern | Activation signal | What it finds |
|---|---------|-------------------|---------------|
| 7 | **Information flow / data exposure** | HTTP handlers, API responses, logging frameworks | Sensitive data reaches logs, error messages, responses, metrics. The inverse of validation: not "can bad data get in" but "can private data get out." |
| 8 | **Auth/authorization logic** | User/role models, access control checks, session management | Missing or misplaced access control checks. Privilege escalation through indirect paths, IDOR, confused deputy, batch jobs with elevated privileges. |
| 9 | **Distributed consistency / partial failure** | External service calls, message queues, distributed storage | Multi-component operations partially succeed. Missing compensation/rollback, stale reads, message reordering, non-atomic multi-step operations. |
| 10 | **Injection / neutralization** | String construction for interpreters (SQL, HTML, shell, templates) | Untrusted data interpreted as control instructions. Distinct from validation — a value can pass all range/type checks and still be an injection vector. The concern is the boundary between data and control planes. |
| 11 | **Cryptographic misuse** | Crypto imports, key/hash/cipher usage | Correct encryption that provides no security. Wrong mode, predictable nonces, key reuse, timing-vulnerable comparisons, insufficient key derivation. |
| 12 | **Configuration / environment sensitivity** | Environment variable reads, config files, path construction | Implicit environmental dependencies. Hardcoded paths, assumed locale/timezone, missing env vars with no fallback, defaults that are wrong in production. |

### Per-construct analysis protocol

For each construct × applicable concern:

1. **Attack** — what specific input, condition, or sequence breaks this
   construct for this concern? Be concrete: name the value, the path, the
   sequence. Cite line numbers.
2. **Verdict:**
   - **FINDING** — specific attack works. Record: attack description,
     expected wrong behavior, severity (high/medium/low), line numbers,
     relevant spec requirement (if any).
   - **CLEARED** — specific mechanism prevents the attack. Record: what
     mechanism (cite line number and code), why it's sufficient. "Looks
     correct" is not a valid clearing — must name the defense.

For data-flow edges within the cluster:
3. **Producer/consumer check** — what does the producer guarantee? What
   does the consumer assume? Do they match? If not, that's a finding on
   the edge, attributed to whichever end is wrong.

For cross-cluster edges:
4. **Boundary observation** — note data flowing out of this cluster with
   what guarantees, so Report can check whether the receiving cluster's
   analysis is consistent.

### Context management within session

- Read source for construct(s) via offset/limit (line ranges from packet)
- Analyze one construct at a time against its applicable concerns
- Write findings/clearings immediately
- Carry forward only summary lines (finding ID + one-line description)
  between constructs — not the full analysis reasoning
- Cross-reference within cluster is allowed (construct A's analysis can
  reference construct B's clearing) since both are in the same session

### Suspect must NOT

- Read files outside the cluster's file list (from packet)
- Read ignore-tier files
- Query specs/KB/ADRs (already embedded in packet)
- Expand scope (de-scope is allowed — move construct to exclusion with reason)
- Filter findings by severity (report everything; Report classifies later)
- Use vague clearings ("looks correct", "seems fine", "no issues found")
- Skip constructs (simple constructs have simple bugs; if truly no
  applicable concerns, say so explicitly with reasoning)

### Outputs

| Artifact | Contents | Consumer |
|----------|----------|----------|
| `suspect-cluster-{N}.md` | Findings, clearings, boundary observations for cluster N | Prove, Report |

Output format per finding:
```
### F-{cluster}.{seq}: {one-line description}
- **Construct:** {name} ({file}:{lines})
- **Concern:** {concern area name}
- **Attack:** {specific input/condition/sequence}
- **Expected wrong behavior:** {what happens}
- **Severity:** {high|medium|low}
- **Spec requirement:** {ID or "none"}
- **Lines:** {relevant line numbers}
```

Output format per clearing:
```
| Construct | Concern | Clearing | Evidence (line) |
```

### Performance expectations

| Expectation | How to verify | What violation means |
|-------------|---------------|---------------------|
| Each Suspect subagent completes in <=10 turns | Count turns per subagent | Cluster is too large or subagent is doing exploratory work |
| Suspect reads source only via offset/limit with line ranges from packet | Grep for full-file reads in subagent transcript | Packet line ranges are wrong or incomplete |
| Suspect never reads files outside its cluster's file list | Grep for out-of-cluster file reads | Scope's clustering missed a dependency |
| Suspect never queries specs/KB/ADRs | Grep for spec-resolve, kb reads in subagent | Packet context is incomplete |
| Every applicable concern × construct produces a finding or clearing | Count findings + clearings vs. expected (constructs × applicable concerns) | Suspect is skipping work |
| Zero vague clearings | Grep for clearings without line citations | Prompt isn't enforcing evidence requirement |
| Findings reference specific line numbers | Grep findings for line citations | Suspect is reasoning from summary, not source |
| Cross-cluster boundary observations exist for every cross-cluster edge | Compare boundary observations to cross-cluster edges in packet | Suspect is ignoring boundary edges |

### Failure modes and mitigations

| Failure mode | Mitigation | Verification |
|-------------|-----------|-------------|
| Suspect reads source and disagrees with packet's boundary contracts | Packet contracts come from Scope's direct source reading — same source. If Suspect sees different code, the file changed between Scope and Suspect (race condition in pipeline). Mitigation: Scope and downstream run on same git commit. | Compare git HEAD at Scope start vs. Suspect start |
| Suspect produces too many low-value findings (noise) | Severity field lets Report filter. But the real mitigation is Prove — a finding that can't be demonstrated with a failing test is reclassified as "theoretical concern." The pipeline is self-correcting. | Track findings that survive to confirmed-failure vs. theoretical |
| Suspect misses bugs because concern areas don't cover the failure mode | Core concerns are based on empirical research across domains. Domain-conditional activation covers specialized areas. Gap: truly novel bug categories. Mitigation: Report tracks "bugs found by Fix regression testing that Suspect didn't flag" — these reveal concern area gaps. | Count bugs found in Fix regression that have no corresponding Suspect finding |
| Suspect session grows long on large clusters | Scope targets cluster sizes of 3-8 constructs. If a cluster has 15, Scope should have split it. Suspect can de-scope: move lowest-priority constructs to exclusion. | Track cluster sizes and subagent turn counts |
| Domain-conditional concerns activated but Suspect doesn't know how to check them | Concern descriptions in packet include "what it finds" guidance. But some concerns (crypto misuse, distributed consistency) require domain expertise the model may lack. Mitigation: accept lower recall on specialized concerns; the core concerns still run. **Future optimization:** include domain-specific expertise framing in Suspect prompt for activated concerns (e.g., "You are a cryptography security expert" when crypto misuse is activated). Low-cost persona intervention that may significantly improve recall on specialized concerns. | Track finding rate per concern area — consistently zero findings for an activated concern suggests the model can't effectively check it |

---

## Job 3: Prove

### Purpose

Demonstrate each suspected bug with a failing test. Prove owns the full
test lifecycle: write, compile, fix compilation errors, run, and classify
the result. Findings that can't be proven are reclassified or removed.
Tests that pass (bug doesn't manifest) are deleted — no dead tests left
in the codebase.

### Session model

One subagent per finding, run serially. Each subagent receives a single
finding and the relevant construct's file path and line range from the
cluster packet. Short session — read source, write test, compile, run,
classify. 4-6 turns per subagent.

This is per-finding, not per-cluster, because the cost model shows that
10 serial 5-turn subagents are dramatically cheaper than 1 subagent with
50 turns — even though the total "work done" is the same. Each subagent
gets a fresh context window with no carry cost from prior findings.

Optional cross-cluster subagent(s) for boundary mismatches identified
by Report's cross-cluster comparison.

### Inputs

| Source | Contents | Purpose |
|--------|----------|---------|
| `suspect-cluster-{N}.md` | Findings with attack, expected wrong behavior, line numbers | What to test |
| `cluster-{N}-packet.md` | File paths, line ranges, boundary contracts, context | Where to read source, what's available |
| Project test conventions | Test framework, directory structure, naming patterns | How to write the test |

### Per-finding protocol

For each finding in the cluster:

1. **Read construct source** — offset/limit using line ranges from packet.
   Understand the API: types, method signatures, constructors, required
   setup. This is not re-analysis — Prove reads to understand how to call
   the code, not whether it's buggy.

2. **Write test** — one test method per finding:
   - **Setup** minimum state to reach the buggy path
   - **Provide** the specific adversarial input from the finding (exact values)
   - **Assert** correct behavior (test fails because buggy code doesn't do it)
   - **Name:** `test_{construct}_{concern}_{summary}`
   - **Intent comment** (mandatory): finding ID, spec requirement (if any),
     what the bug is, what correct behavior looks like, guidance for Fix

3. **Compile** — run the project's compile command for the test file.
   - **Compiles:** proceed to run.
   - **Fails:** read error, apply fix (import, signature, type correction),
     recompile. Maximum 2 compile attempts total.
   - **Still fails after 2 attempts:** mark test as `COMPILE-SKIP` with
     reason, disable test annotation, proceed to next finding.

4. **Run** — execute the single test.
   - **Test fails (expected):** finding confirmed. Record as `CONFIRMED`.
     This is the success path — the test demonstrates the bug.
   - **Test passes (unexpected):** the bug doesn't manifest under this
     attack. **Delete the test.** Reclassify finding as `UNCONFIRMED —
     test passed, attack did not trigger bug`. Don't leave passing tests
     that were meant to fail.
   - **Test errors (setup problem):** test infrastructure issue, not a
     finding issue. Mark as `TEST-ERROR` with details. Delete the test.

5. **Forget** — carry forward only the summary line (finding ID, status,
   test method name if confirmed). Drop source code, test code, and
   reasoning from context before processing next finding.

### Cross-cluster findings

Suspect produces boundary observations on cross-cluster edges. When
boundary observations from two clusters indicate a producer/consumer
mismatch (detected by the orchestrator or Report):

- A dedicated cross-cluster Prove subagent is launched
- It receives a narrow packet: just the cross-cluster finding, the
  relevant constructs from both clusters (file paths, line ranges),
  and boundary contracts
- Same protocol: write test, compile, run, classify
- Short session — the finding is already specific, so setup is
  straightforward

### Test quality requirements

- **One test per finding** — no combining multiple findings into one test.
  Each test isolates one bug for Fix to address independently.
- **Minimal setup** — construct only the state needed to reach the buggy
  path. No test fixtures, no helper classes, no shared state between tests.
- **No test dependencies** — each test is independently runnable.
- **Intent comment is mandatory** — Fix reads this comment to understand
  what the test expects without re-reading Suspect's analysis. Format:
  ```
  // Finding: F-{cluster}.{seq}
  // Spec: {requirement ID or "none"}
  // Bug: {one-line description of the bug}
  // Correct behavior: {what should happen instead}
  // Fix guidance: {where in the source to look}
  // Regression: {what to watch for when fixing}
  ```
- **Assert correct behavior, not buggy behavior** — the test fails because
  the code does the wrong thing, not because we assert the wrong thing.
  When the fix is applied, the test should pass without modification.

### Prove must NOT

- Re-analyze whether the finding is valid (that's Suspect's job — Prove
  tests it empirically)
- Read files outside the cluster's file list
- Modify source code (that's Fix's job)
- Leave tests in the codebase that pass — passing "adversarial" tests are
  noise that creates future confusion and maintenance burden
- Retry a test more than once (flaky tests are a test quality problem,
  not a finding quality problem)
- Write tests for clearings (only findings get tests)

### Outputs

| Artifact | Contents | Consumer |
|----------|----------|---------|
| Test files | One test method per confirmed finding, in project test directory | Fix |
| `prove-cluster-{N}.md` | Per-finding status (confirmed/unconfirmed/compile-skip/test-error), test method names | Fix, Report |

Output format:
```
# Prove Results — Cluster {N}

## Summary
- Findings received: {count}
- Confirmed (test fails): {count}
- Unconfirmed (test passed — deleted): {count}
- Compile-skipped: {count}
- Test errors: {count}

## Confirmed Findings
| Finding | Test method | Construct | What test demonstrates |
|---------|-------------|-----------|----------------------|

## Unconfirmed Findings
| Finding | Why test passed | Implication |
|---------|----------------|-------------|

## Compile-Skipped
| Finding | Compile error | Why not fixable |
|---------|---------------|-----------------|

## Test Errors
| Finding | Error | What went wrong |
|---------|-------|----------------|
```

### Performance expectations

| Expectation | How to verify | What violation means |
|-------------|---------------|---------------------|
| Each Prove subagent completes in <=15 turns | Count turns per subagent | Too many findings per cluster or compile loops |
| >=80% of findings compile on first attempt | Track first-attempt compilation rate | Suspect's findings don't have enough detail for test writing, or test framework conventions aren't in the packet |
| >=60% of findings are confirmed (test fails) | Track confirmation rate | Suspect is producing too many false positives |
| Zero passing tests remain in codebase after Prove | Grep test directory for test methods matching prove naming pattern that pass | Prove isn't cleaning up |
| Each test has an intent comment | Grep test files for finding ID pattern | Prompt isn't enforcing comment requirement |
| No source modifications by Prove | Check git diff for source (non-test) file changes during Prove | Prove is doing Fix's job |
| Prove reads source only via offset/limit | Grep for full-file reads | Packet line ranges insufficient |
| Cross-cluster Prove subagents are launched only for identified mismatches | Count cross-cluster subagent launches vs. boundary observations | Over-launching wastes cost; under-launching misses cross-cluster bugs |

### Failure modes and mitigations

| Failure mode | Mitigation | Verification |
|-------------|-----------|-------------|
| Prove can't write a compilable test because it doesn't understand the project's test framework | Test framework info and conventions must be in the cluster packet. If compilation rate is <50%, the packet is missing test infrastructure context. | Track compilation rate; if low, add test framework examples to Scope's packet assembly |
| Prove deletes a test that actually found a different bug than intended | The test passed, meaning the specific attack from the finding didn't trigger. If the test was accidentally testing something else that works, deleting it is correct — it wasn't testing the finding. Prove writes tests that assert correct behavior; if correct behavior is observed, there's no bug to demonstrate. | Review unconfirmed findings manually in early pipeline runs |
| Prove produces tests that fail for the wrong reason (setup error, not actual bug) | Run classification catches TEST-ERROR vs. assertion failure. If the test throws during setup rather than failing an assertion, it's a test quality problem. Mark as test-error, delete. | Track test-error rate; if high, Prove's setup code is wrong |
| Too many findings per cluster overwhelms Prove session | Scope targets 3-8 constructs per cluster × ~2 applicable concerns each = 6-16 findings max. If Suspect produces 30+ findings for a cluster, either the cluster is too large or Suspect is over-reporting. Prove processes what it can and de-scopes the rest. | Track findings-per-cluster distribution |
| Cross-cluster findings are missed because no reconciliation step exists | Boundary observations from Suspect are compared after all cluster Suspect subagents complete. Mismatches are identified and routed to cross-cluster Prove subagents. This comparison is lightweight — structured data, no source reading. The orchestrator or Report can do it. | Track whether boundary observations are actually compared |

---

## Job 4: Fix

### Purpose

Make confirmed failing tests pass without breaking anything else. Fix has
a hard invariant: **when Fix completes, all tests pass.** The codebase is
never left in a broken state. Bugs are either fixed, or their tests are
removed with documented reasoning that feeds the next audit round.

### Session model

Two phases, strict role separation, all serial:

1. **Fix subagents** (per finding, serial) — modify source code ONLY.
   Cannot modify or remove tests. Each finding gets a fresh subagent
   per attempt. If an attempt fails, a new subagent is launched with
   the accumulated attempt summaries (not the prior session's context).
   Iterate until the test passes or is proven impossible.
2. **Regression subagent** (per cluster, after all Fix subagents for
   the cluster complete) — the sole authority that can modify or remove
   tests. Reviews impossibility proofs, validates relaxation requests,
   resolves pre-existing test regressions. Ensures all tests pass
   before terminating.

Same-file constructs are always in the same cluster (enforced by
Assembly). Fix subagents for same-file constructs run serially,
preventing concurrent file modification conflicts.

### Inputs

| Source | Contents | Purpose |
|--------|----------|---------|
| Test files (from Prove) | Failing tests with intent comments | What to fix and why |
| `cluster-{N}-packet.md` | File paths, line ranges | Where source code lives |
| `prove-cluster-{N}.md` | Confirmed findings, test method names | Which tests to target |
| Pre-existing test references | Test files identified by Scope for regression checking | What else might break |

### Phase 1: Fix subagents

One subagent per finding, run serially. Each subagent operates under the
assumption: **a valid fix exists in the code — find it or prove it
doesn't.**

Each attempt is a fresh session:

1. **Read test intent comments** — these are the primary input. The comment
   describes the bug, what correct behavior looks like, where to look in
   source, and what to watch for. Fix understands the problem from the
   comment before reading source.

2. **Read construct source** — offset/limit using line ranges from packet.
   Confirm the bug described in the intent comment, identify the minimal
   edit.

3. **If this is attempt 2+:** also read prior attempt summaries (what was
   tried, why it failed). These are short structured summaries, not the
   prior session's full context.

4. **Fix source** — minimum edit to make the test pass. Preserve API
   contracts. One edit region when possible.

5. **Compile** — if compilation fails, read error (one line), fix syntax,
   recompile.

6. **Run construct-specific tests** — only this finding's Prove test.
   - **Pass:** emit summary, done.
   - **Fail:** emit structured attempt summary (what was tried, why it
     failed, the assertion message). The orchestrator launches a new
     subagent with this summary added to the prior attempt summaries.

7. **If proven impossible:** the fix cannot be applied without violating
   a constraint that the Fix subagent cannot resolve. Emit structured
   impossibility proof:
   - What approaches were tried (across all attempts)
   - Why each approach failed
   - The specific architectural constraint or test conflict
   - Whether the fix requires a behavioral change that would break
     a pre-existing test (relaxation request for regression subagent)

**Fresh session per attempt:** Each attempt starts with a clean context
window. The only accumulated state is the attempt summaries — short
structured text (~100 tokens per prior attempt). Attempt 5 reads:
intent comment + source + 4 attempt summaries. No carry cost from
prior attempts' reasoning, source reads, or compile output.

**Test output discipline:** Fix reads only pass/fail status and the
assertion message (expected X, got Y) from test output. No stack traces,
no XML parsing, no bash grep of output. The intent comment already
describes the bug — test output confirms whether the fix worked, nothing
more.

**Fix subagents CANNOT:**
- Modify or remove tests (only source code)
- Parse test output beyond pass/fail + assertion message
- Read Suspect's analysis (intent comments are sufficient)
- Expand scope beyond the assigned construct
- Make speculative improvements to surrounding code

### Phase 2: Regression subagent

One subagent per cluster. Launches after all Phase 1 Fix subagents
complete. The regression subagent is the **sole authority** that can
modify or remove tests. It acts as mediator between the Fix subagents'
work and the full test suite.

**Process:**

1. **Run full test suite** — all Prove tests (confirmed) plus all
   pre-existing tests identified by Scope.

2. **If all pass:** done. Emit clean report.

3. **Review impossibility proofs** from Fix subagents. For each test
   marked as impossible:

   a. **Validate the proof.** Is the reasoning sound? Was a viable
      approach missed? Is the architectural constraint real?

   b. **Remove the test** in all cases — the codebase must be clean.
      But classify the removal:
      - **Proof valid, finding invalid:** the bug Suspect identified
        doesn't exist or can't manifest. Mark as `INVALID — {reason}`.
        This finding should not be re-raised in future audit rounds.
      - **Proof valid, fix requires design change:** the bug is real
        but the fix is beyond audit scope. Mark as `DESIGN-CHANGE —
        {what's needed}`. Future rounds can revisit after the design
        change.
      - **Proof weak/invalid, bug likely real:** Fix gave up too
        easily. Mark as `NEEDS-REVISIT — {what was tried, what to
        try differently}`. Future rounds should re-attempt with
        the additional context about what didn't work.

4. **Review relaxation requests.** Fix subagents may request behavioral
   changes that break pre-existing tests (e.g., changing exception
   types). For each:

   a. Is the behavioral change correct? (Does the new behavior better
      match the contract/spec than the old?)
   b. If yes: accept the relaxation. Modify the pre-existing test with
      proof of safety (old assertion, new assertion, why new is correct).
      Run one additional Fix pass for that construct to apply the fix
      that was blocked.
   c. If no: reject. The Fix subagent's impossibility proof stands.
      Remove the Prove test and classify per step 3.
   d. Maximum one source fix pass after accepting relaxations (all
      accepted relaxations are known, so the fix subagent has complete
      information).

5. **Resolve any remaining pre-existing test failures** caused by
   source fixes that weren't covered by relaxation requests:

   a. Read failing pre-existing test (assertion, not full output).
   b. Read the source modification that caused the failure.
   c. Determine: fix the source (refine, don't revert) or fix the
      test (with proof of safety).
   d. Run full suite after each resolution. Forward motion only.

6. **Exit condition: all tests pass.** Termination is guaranteed
   because every failing test is resolved by exactly one of: source
   fix, test modification (with proof), or test removal (with
   classification). Failure count strictly decreases each iteration.

### Fix invariant

**After Fix completes, `test suite passes` is always true.**

Four possible outcomes per finding:
- **Fixed:** source modified, test passes, no regressions.
- **Invalid:** regression subagent validated that the finding is not a
  real bug. Test removed, finding marked `INVALID` so future rounds
  don't re-raise it.
- **Design change required:** bug is real but fix requires architectural
  changes beyond audit scope. Test removed, finding marked
  `DESIGN-CHANGE` with details for future work.
- **Needs revisit:** bug is likely real but this pass couldn't fix it.
  Test removed, finding marked `NEEDS-REVISIT` with what was tried and
  what to try differently. Available for next audit round.

No fifth outcome exists. The codebase is never left with failing tests.

### Outputs

| Artifact | Contents | Consumer |
|----------|----------|---------|
| Modified source files | Bug fixes applied | (committed to repo) |
| Modified test files | Pre-existing tests updated with proof-of-safety comments (if any) | Report |
| `fix-cluster-{N}.md` | Per-construct fix summary, regression results, removed tests with classifications | Report |

Output format:
```
# Fix Results — Cluster {N}

## Invariant: ALL TESTS PASS

## Per-Construct Fixes
### {ConstructName} ({file}:{lines})
- **Status:** fixed | impossible
- **Findings addressed:** F-{N}.{seq}, ...
- **Change:** {one-line description of source modification}
- **Tests passing:** {list}
- **Impossibility proofs:** {if any — what was tried, why it failed}
- **Relaxation requests:** {if any — what behavioral change is needed}

## Regression Review
### Impossibility Proof Reviews
| Finding | Proof valid? | Classification | Detail |
|---------|-------------|----------------|--------|

### Relaxation Requests
| Finding | Accepted? | Pre-existing test modified | Proof of safety |
|---------|-----------|--------------------------|-----------------|

### Pre-existing Test Regressions
| Test | Cause | Resolution | Proof of safety (if test modified) |
|------|-------|------------|-----------------------------------|

## Removed Tests
[If none: "None — all findings fixed."]
### {test method}
- **Finding:** F-{N}.{seq}
- **Classification:** INVALID | DESIGN-CHANGE | NEEDS-REVISIT
- **Detail:** {what was tried, why it can't be fixed, what future
  rounds should know}

## Summary
- Constructs fixed: {count}
- Findings fixed: {count}
- Findings invalid: {count}
- Findings needing design change: {count}
- Findings needing revisit: {count}
- Pre-existing tests modified: {count}
- All tests passing: YES
```

### Performance expectations

| Expectation | How to verify | What violation means |
|-------------|---------------|---------------------|
| >=70% of findings are fixed in Phase 1 | Track Phase 1 fix rate | Either findings are too hard to fix or intent comments lack guidance |
| Fix subagents never modify tests | Grep Fix subagent transcripts for test file edits | Role separation violated |
| Fix reads intent comments before reading source | Check read order in subagent transcript | Fix is diagnosing from source instead of using intent |
| Fix never parses XML test output or runs grep on test output | Grep subagent transcript for xml, grep, awk, sed on test files | Context pollution — the old pipeline's biggest cost driver |
| Test output reads contain only pass/fail + assertion message | Measure test output token count in Fix sessions | Test output not being truncated |
| Regression subagent reaches "all tests pass" | Check final test run result | Fix invariant violated — critical failure |
| Impossibility proofs include specific approaches tried | Check proof entries for "tried X, failed because Y" structure | Fix is declaring impossibility without genuine effort |
| <30% of findings are declared impossible | Track impossibility rate | Fix is taking the easy path — proving impossibility instead of fixing |
| Removed tests have classification (INVALID / DESIGN-CHANGE / NEEDS-REVISIT) | Check removed test entries for classification field | Regression subagent removing without proper review |
| At most 1 source fix pass after relaxation acceptance | Count post-relaxation Fix invocations | Regression is spawning unbounded fix loops |

### Failure modes and mitigations

| Failure mode | Mitigation | Verification |
|-------------|-----------|-------------|
| Fix declares everything impossible | Default assumption is "fix exists — find it." Impossibility requires structured proof (approaches tried, why each failed, specific constraint). Performance expectation flags >30% impossibility rate. Root cause is likely prompt framing. | Track impossibility rate per run; compare across runs |
| Regression accepts weak impossibility proofs | Regression must validate proofs, not rubber-stamp them. Weak proofs get `NEEDS-REVISIT` classification, not `INVALID`. Track `NEEDS-REVISIT` rate — if high, either Fix is lazy or the bugs are genuinely hard. | Review NEEDS-REVISIT entries; compare to findings that were fixed in subsequent rounds |
| Relaxation requests used to avoid hard fixes | Relaxation only applies when a fix changes observable behavior that a pre-existing test asserts. It cannot be used to weaken the Prove test itself. Regression validates that the behavioral change is actually correct. | Track relaxation request rate; grep for relaxation requests on Prove tests (should be zero) |
| Pre-existing test modifications mask regressions | Proof-of-safety required for every test modification. Report surfaces all modifications for human review. | Review proof-of-safety entries per run |
| Regression session grows long with many failures | One-test-at-a-time protocol bounds per-test work. If >10 tests fail in initial regression run, that suggests a systemic issue — regression should identify the common cause before processing individually. | Track regression iteration count vs. initial failure count |
| Fix doesn't use intent comments, falls back to test output parsing | Explicit prohibition: "DO NOT parse test output." Performance expectation catches violation via transcript grep. | Grep Fix transcripts for XML/grep/awk/sed patterns |

---

## Job 5: Report

### Purpose

Synthesize all pipeline outputs into two artifacts: a human-readable
report for the user and a structured machine-readable artifact that
feeds the next audit round's Scope. Report also performs one analytical
task: comparing boundary observations across clusters to identify
potential cross-cluster findings for the next round.

### Session model

Single subagent. Reads all pipeline output files (structured markdown,
no source code). Short session — this is synthesis over structured data,
not analysis over source.

### Inputs

| Source | Contents | Purpose |
|--------|----------|---------|
| `scope-definition.md` | Tiers, construct graph, clusters, detected domains | What was analyzed |
| `scope-exclusions.md` | What was deferred and why | Feeds next round |
| `suspect-cluster-{N}.md` (all) | Findings, clearings, boundary observations | What was found |
| `prove-cluster-{N}.md` (all) | Confirmation rates, unconfirmed/deleted tests | What was proven |
| `fix-cluster-{N}.md` (all) | Fixes, impossibility proofs, removed tests, classifications | What was fixed |

### Responsibilities

**Cross-cluster boundary comparison:**
- Collect boundary observations from all Suspect cluster outputs
- For each cross-cluster data-flow edge: compare the producer cluster's
  stated guarantees with the consumer cluster's assumptions
- If mismatch found: record as `CROSS-CLUSTER-UNRESOLVED` with both
  clusters, both constructs, the mismatch description, and a
  recommendation for next round's Scope to co-cluster these constructs
- This is the only analytical work Report does — it's a comparison over
  structured data, no source reading

**User-facing report:**
- Pipeline summary: scope, clusters, construct count, concern areas
  checked
- Findings summary: total found by Suspect, confirmed by Prove,
  fixed, removed (by classification)
- Fixes applied: per-construct list of what changed
- Pre-existing test modifications with proof of safety (surfaced for
  human review even in unattended mode)
- Removed tests with classifications and reasoning
- Cross-cluster unresolved findings (if any)
- Pipeline health metrics (for user to assess pipeline quality):
  - Suspect → Prove confirmation rate (target: >=60%)
  - Fix success rate (target: >=70%)
  - Impossibility rate (flag if >30%)
  - Concern area finding distribution (which concerns found bugs?)
  - Test removal classification distribution

**Machine-readable artifact for next Scope:**
- Analyzed constructs with their clearing reasoning (so next round
  does reduced analysis, not full re-analysis)
- Constructs excluded from this round (candidates for next round)
- Removed test classifications:
  - `INVALID` — do not re-raise this finding
  - `DESIGN-CHANGE` — re-raise only after the specified design change
    has been made
  - `NEEDS-REVISIT` — re-attempt with different approach, include
    what was tried and why it failed
- Cross-cluster unresolved findings with co-clustering recommendation
- Boundary contracts observed (producer guarantees, consumer
  assumptions) for constructs at cluster edges
- Concern areas activated and their per-area finding rates
- Spec coverage summary (if specs were in scope): which requirements
  were verified, which have no corresponding code behavior, which
  code behaviors have no corresponding requirement

### Report must NOT

- Read source code (all information comes from pipeline artifacts)
- Re-analyze findings (Suspect analyzed, Prove confirmed, Fix resolved)
- Modify source or test files
- Filter or hide findings based on severity (present everything;
  user decides what matters)
- Invent findings not present in pipeline outputs

### Outputs

| Artifact | Contents | Consumer |
|----------|----------|---------|
| `audit-report.md` | Human-readable report | User |
| `audit-prior.md` | Machine-readable artifact for next round | Next round's Scope |

**audit-report.md format:**
```
# Audit Report — {scope description}

**Date:** {YYYY-MM-DD}
**Round:** {1 | 2 | ...}
**Scope:** {files/constructs/spec analyzed}

## Pipeline Summary

| Stage | Input | Output | Key metric |
|-------|-------|--------|------------|
| Scope | {entry point} | {N} constructs, {N} clusters | {N} boundary, {N} ignored |
| Suspect | {N} constructs × {N} concerns | {N} findings, {N} cleared | {domains activated} |
| Prove | {N} findings | {N} confirmed, {N} unconfirmed | {confirmation rate}% |
| Fix | {N} confirmed | {N} fixed, {N} removed | {fix rate}% |
| Report | all outputs | this report | {N} cross-cluster unresolved |

## Bugs Fixed
### F-{N}.{seq}: {description}
- **Construct:** {name} ({file}:{lines})
- **Concern:** {area}
- **Fix:** {what changed}

## Removed Tests (Not Fixed)
### F-{N}.{seq}: {description}
- **Classification:** INVALID | DESIGN-CHANGE | NEEDS-REVISIT
- **Reasoning:** {why}
- **Next round guidance:** {what to do differently}

## Pre-existing Test Modifications
[Surfaced for human review]
### {TestClass.testMethod}
- **Old assertion:** {what}
- **New assertion:** {what}
- **Proof of safety:** {why}

## Cross-Cluster Unresolved
[If none: "None — all cross-cluster edges consistent."]
### {producer construct} → {consumer construct}
- **Producer cluster:** {N}, **Consumer cluster:** {N}
- **Mismatch:** {producer guarantees X, consumer assumes Y}
- **Recommendation:** co-cluster in next round

## Spec Coverage
[If specs were in scope]
| Requirement | Status | Evidence |
|-------------|--------|---------|

## Pipeline Health
| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| Confirmation rate | {N}% | >=60% | {OK|FLAG} |
| Fix rate | {N}% | >=70% | {OK|FLAG} |
| Impossibility rate | {N}% | <30% | {OK|FLAG} |
| Concern area coverage | {N}/{N} areas found bugs | — | — |
| Cross-cluster unresolved | {N} | 0 | {OK|FLAG} |
```

**audit-prior.md format:**
```
# Audit Prior — {scope description}

**Date:** {YYYY-MM-DD}
**Round:** {N}
**Git commit:** {SHA at time of audit}

## Analyzed Constructs
| Construct | File | Lines | Status | Clearing reasoning |
|-----------|------|-------|--------|-------------------|

## Excluded Constructs
| Construct | File | Reason excluded | Priority for next round |
|-----------|------|-----------------|------------------------|

## Removed Test Classifications
| Finding | Classification | What was tried | Next round guidance |
|---------|---------------|----------------|---------------------|

## Cross-Cluster Unresolved
| Producer | Consumer | Mismatch | Co-cluster recommendation |
|----------|----------|----------|--------------------------|

## Boundary Contracts Observed
| Construct | Guarantees | Assumes | Cluster |
|-----------|-----------|---------|---------|

## Concern Area Results
| Concern | Activated | Findings | Confirmation rate |
|---------|-----------|----------|-------------------|

## Spec Coverage
| Requirement | Status |
|-------------|--------|
```

### Performance expectations

| Expectation | How to verify | What violation means |
|-------------|---------------|---------------------|
| Report completes in <=10 turns | Count turns | Report is doing analytical work beyond boundary comparison |
| Report reads no source files | Grep transcript for source file reads | Report is re-analyzing instead of synthesizing |
| audit-prior.md contains every analyzed construct with clearing reasoning | Compare construct list to scope-definition.md | Next round's Scope won't have complete prior work data |
| audit-prior.md contains every removed test with classification | Compare to fix-cluster outputs | Next round may re-raise invalid findings |
| Cross-cluster boundary comparison covers all cross-cluster edges | Compare boundary observations to scope-definition.md cross-cluster edges | Some cross-cluster interactions were silently dropped |
| Pipeline health metrics are computed and flagged | Check report for metric table with target comparison | No visibility into pipeline quality |
| audit-prior.md records git commit SHA | Check for SHA field | Next round can't determine what changed since this audit |

### Failure modes and mitigations

| Failure mode | Mitigation | Verification |
|-------------|-----------|-------------|
| Report drops findings between pipeline stages | Report counts findings at each stage transition (Suspect → Prove → Fix) and flags discrepancies. If Suspect produced 15 findings and Fix resolved 12, Report must account for the other 3 (unconfirmed by Prove, deleted, etc.). | Compare finding counts across stages in pipeline summary |
| audit-prior.md is too large for next Scope to consume | Prior data is structured tables, not narrative. Construct count determines size. For very large audits (200+ constructs), Scope can read selectively (only changed constructs + their prior clearings). | Measure audit-prior.md token count; flag if >8K tokens |
| Cross-cluster boundary comparison misses a mismatch | Boundary observations use structured format (construct, guarantee, assumption). Comparison is mechanical — match guarantees to assumptions. Misses would come from Suspect not producing boundary observations (a Suspect problem, not Report). | Track boundary observation count vs. cross-cluster edge count |
| Report invents findings not in pipeline outputs | Report synthesizes, it does not analyze. All findings must trace to a Suspect finding ID. Cross-cluster unresolved findings trace to specific boundary observations. | Verify every report finding has a source finding ID |
| Pipeline health metrics look bad but user ignores them | Metrics are informational — the user decides whether to iterate. Report can recommend ("confirmation rate is 45%, below 60% target — consider reviewing Suspect concern area calibration") but doesn't block. | Track whether flagged metrics improve across rounds |

---

## Design assumptions to validate

These assumptions underpin the pipeline design. Each should be validated
with real pipeline runs and updated if proven wrong.

| Assumption | How to validate | What changes if wrong |
|-----------|----------------|----------------------|
| Carry cost dominates (99%+ of input tokens) | Measure input token breakdown in pipeline runs | If carry cost is lower, summary-based approach may be viable |
| Short serial subagents are cheaper than fewer long ones | Compare total cost of many-short vs. few-long runs on same scope | Adjust session model — maybe longer sessions with more work are acceptable |
| Scope's 3-subagent split reduces carry cost vs. single session | Compare 3-subagent Scope cost to estimated single-session cost | Merge subagents if handoff overhead exceeds carry cost savings |
| Scope's front-loaded source reading eliminates enough downstream turns to justify its cost | Compare Scope cost to downstream turn savings | If savings are marginal, make Scope lighter and let downstream do more |
| Cross-cluster findings can be deferred to the next round without significant quality loss | Compare finding rates on cross-cluster bugs: round 1 (deferred) vs. round 1 (reconciliation step) | If deferral misses high-severity bugs, add a reconciliation micro-step |
| Intent comments provide sufficient context for Fix without reading Suspect's analysis | Track Fix success rate and compare to runs where Fix had Suspect access | If Fix rate drops without Suspect, consider embedding finding details in comments |
| Fresh-session-per-attempt Fix is cheaper than iterating within one session | Compare total cost of multi-attempt vs. single-session Fix | If fresh sessions have too much overhead, allow bounded iteration within a session |
| Domain-conditional concern activation by Scope is accurate | Track false activation (concern activated, zero findings) and missed activation (concern not activated, bug found in that area by other means) | Adjust activation signals or default more concerns to always-on |
| Two audit rounds are sufficient for most codebases | Track finding rate in round 3+ | If round 3 consistently finds high-severity bugs, the pipeline needs better single-round coverage |
| The pipeline is cheap enough to run multiple times | Measure total pipeline cost per round | If a single round costs >$5 for 50 constructs, cost optimization is needed before multi-round is practical |
| Orchestrator LLM session stays near-zero cost with strict discipline | Measure orchestrator turn count and token cost | If orchestrator is doing analytical work despite prohibitions, investigate prompt or add structural enforcement |
| Serial execution is sufficient (parallelism not needed for acceptable wall-clock time) | Measure wall-clock time for serial pipeline runs | If serial is too slow for user experience, selectively add parallelism for proven-safe stages |

---

## Diagnostic tool

### Purpose

A Python script that runs against a completed pipeline run and validates
every performance expectation, behavioral compliance rule, and quality
metric defined in this document. The tool eliminates manual investigation
— run it after any pipeline execution and get a structured pass/fail
report.

### Data sources

The diagnostic consumes three types of data. It does not require any
custom logging from the orchestrator — it infers stage mapping from
subagent session content.

| Source | What it provides | Written by |
|--------|-----------------|-----------|
| `exploration-decisions.jsonl` | Every tiering, clearing, frontier, domain, and prior-work decision | Exploration subagent |
| Claude Code session JSONL files | Per-turn token usage, tool calls (reads, writes, bash), message content | Claude Code (automatic) |
| Pipeline output artifacts | scope-definition.md, cluster packets, suspect/prove/fix/report outputs | Pipeline subagents |

### Stage inference

The diagnostic identifies which session belongs to which pipeline stage
by parsing the first user message in each session JSONL. The subagent
prompt contains the stage name and cluster/finding ID (e.g., "You are
the Suspect subagent for cluster 2"). No orchestrator manifest needed.

### Checks

#### Cost checks (from session JSONL)

| Check | Target | How computed |
|-------|--------|-------------|
| Total pipeline cost | < equivalent unstructured review | Sum all session input + output tokens, apply per-token pricing |
| Per-subagent turn count | Scope subagents <=15, Suspect <=10, Prove <=10, Fix <=10, Report <=10 | Count messages with role=assistant per session |
| Orchestrator turn count | <=3 turns per stage transition | Identify orchestrator session, count turns |
| Scope 3-subagent total vs. estimated single-session | 3-subagent should be cheaper | Compute theoretical single-session cost from total constructs × estimated turns |
| Carry cost percentage | >95% (validates cost model assumption) | Per turn: carry = input_tokens[t] - new_content[t] |

#### Behavioral compliance (from session JSONL tool calls)

| Check | Rule | How detected |
|-------|------|-------------|
| No downstream spec/KB/ADR reads | Only Scope reads these | Grep non-Scope sessions for spec-resolve, kb index, decisions index reads |
| No ignore-tier file reads | Hard constraint | Compare all Read tool calls against ignore list from scope-definition.md |
| No artifact reads from subagents | Packets are self-contained | Grep non-orchestrator sessions for reads of scope-definition.md, scope-exclusions.md |
| Fix never modifies tests | Role separation | Grep Fix sessions for Write/Edit calls to test file paths |
| Fix never parses test output | Context pollution ban | Grep Fix sessions for bash calls containing xml, grep, awk, sed on test output |
| Fix reads intent before source | Correct diagnosis order | Check first Read call per Fix session — should be test file, not source |
| Suspect clearings cite lines | No vague clearings | Parse suspect output for clearings, verify each has a line number |
| Suspect findings cite lines | Evidence-based | Parse suspect output for findings, verify each has line numbers |
| Orchestrator never reads source | State machine only | Grep orchestrator session for Read calls to non-artifact files |

#### Exploration audit (from exploration-decisions.jsonl)

| Check | Rule | How detected |
|-------|------|-------------|
| No high-fan-in construct in boundary/ignore | Fan-in promotes | Find tier_decision entries where fan_in > threshold and tier != "analyze" |
| NEEDS-REVISIT constructs were prioritized | Prior work integration | Check prior_work entries: all NEEDS-REVISIT should have action="re-explore" or "promote" |
| INVALID constructs skipped unless code changed | Don't re-raise | Check prior_work entries: INVALID should have action="skip" unless reason includes code change |
| Frontier stops are justified | Budget or depth, not laziness | Check frontier_stop entries: all should have reason in {depth_limit, budget_full, no_more_edges} |
| Domain signals map to correct concerns | Activation accuracy | Cross-reference domain_signal entries against cluster packets' activated concerns |
| All decisions have required fields | Log completeness | Validate every JSONL entry against schema — missing fields are defects |
| Clearing checks verify cited lines | Not rubber-stamping | Check clearing_check entries: still_exists should be based on actual line content |

#### Quality metrics (from pipeline output artifacts)

| Check | Target | How computed |
|-------|--------|-------------|
| Confirmation rate | >=60% | Confirmed findings / total findings from Suspect |
| Fix rate | >=70% | Fixed findings / confirmed findings from Prove |
| Impossibility rate | <30% | Impossible findings / confirmed findings |
| Test removal rate | Flag if >30% | Removed tests / total Prove tests written |
| Finding reconciliation | 0 dropped | Count findings at each stage: Suspect total = Prove confirmed + unconfirmed + compile-skip + test-error; Prove confirmed = Fix fixed + impossible |
| Same-file constructs in same cluster | 100% | Parse scope-definition.md cluster assignments, verify no file appears in multiple clusters |
| Boundary observation coverage | 100% of cross-cluster edges | Compare boundary observations in suspect outputs to cross-cluster edges in scope-definition.md |
| Prior clearing re-validation | All prior-cleared constructs checked | Count clearing_check entries vs. prior-cleared construct count |
| Cluster packet size | <4K tokens each | Measure token count of each cluster-{N}-packet.md |

### Output format

```
=== Audit Pipeline Diagnostic ===
Run: <pipeline-run-dir>
Date: <YYYY-MM-DD>

--- Cost ---
Total tokens: 1,234,567 (input: 1,100,000 / output: 134,567)
Estimated cost: $X.XX
Subagent sessions: 23
Avg turns/subagent: 6.2

  PASS  Scope Classification: 8 turns (<=15)
  PASS  Scope Exploration: 12 turns (<=15)
  PASS  Scope Assembly: 5 turns (<=15)
  PASS  Suspect C1: 7 turns (<=10)
  FLAG  Suspect C2: 14 turns (<=10) — exceeded turn budget
  PASS  Prove F-R1.1.1: 5 turns (<=10)
  ...

--- Behavioral Compliance ---
  PASS  No downstream spec/KB/ADR reads
  PASS  No ignore-tier file reads
  FAIL  Fix session abc123 modified test file (tests/FooTest.java:42)
  PASS  Fix never parsed test output
  ...

--- Exploration Audit ---
  Tier decisions: 42 analyze, 15 boundary, 23 ignore
  PASS  No high-fan-in construct in boundary/ignore
  PASS  3/3 NEEDS-REVISIT constructs re-explored
  FLAG  Budget exhausted at 40 constructs (12 frontier stops due to budget)
  PASS  All domain signals correctly mapped to cluster concerns
  PASS  All decision log entries have required fields
  ...

--- Quality Metrics ---
  PASS  Confirmation rate: 72% (>=60%)
  PASS  Fix rate: 85% (>=70%)
  PASS  Impossibility rate: 12% (<30%)
  PASS  Finding reconciliation: 0 dropped
  FLAG  2 boundary observations missing for cross-cluster edges
  ...

--- Design Assumptions ---
  PASS  Carry cost: 99.2% (>95% expected)
  PASS  Serial wall-clock: 4m 32s
  FLAG  Orchestrator: 8 turns (higher than expected — review transcript)
  ...

Summary: 38 PASS, 3 FLAG, 1 FAIL
```

PASS = expectation met. FLAG = expectation not met but not a hard failure
(investigate). FAIL = hard rule violated (behavioral compliance).

### Implementation notes

- Pure Python, no dependencies beyond stdlib (json, os, re, glob)
- Streams JSONL files line-by-line (no bulk loading)
- Schema validation for exploration-decisions.jsonl is strict — missing
  fields are reported as defects, not silently ignored
- Stage inference from session content uses regex on the first user
  message: look for "Suspect.*cluster (\d+)", "Prove.*F-R", "Fix.*F-R",
  etc.
- Token cost calculation uses the same formula as the existing
  extract-tokens.py in aTDD-research/
- Output to stdout by default; `--json` flag for machine-readable output
  that can be diffed across runs
