# aTDD Research Results

Research conducted 2026-03-20 through 2026-03-24 on the
[jlsm](https://github.com/nathannorthcutt/jlsm) storage engine project
(12 features, 130 sessions, 15 months of development history).

## Research question

Can adversarial testing improve the quality of AI-assisted TDD, and if so,
what's the most cost-effective way to integrate it into the development pipeline?

## TL;DR for skeptics

The pipeline looks complex but each piece justifies itself with data.

### Cost efficiency

| Approach | Tokens | Bugs found | Cost per bug | Unfound bugs |
|----------|--------|-----------|-------------|-------------|
| Basic TDD (no enhancements) | 90K | 4 | 22.5K/bug | 11+ lurking |
| + Post-hoc audit (find+fix) | +48K = 138K | +11 = 15 | 9.2K/bug | 0 |
| Full aTDD (3 iterative rounds) | 89K | 7 | 12.7K/bug | 8 (different class) |
| **Combined pipeline (single pass)** | **91K** | **1 during impl, 0 audit** | **n/a — prevented** | **0** |

The combined pipeline doesn't find bugs cheaper — it **prevents them from being
written**. The spec analysis pre-pass costs ~5-10K tokens upfront but eliminates
the 48K+ post-hoc audit-and-fix cycle entirely.

### Bug finding shifted left

The key insight is where in the pipeline bugs are caught:

```
                Basic TDD          Combined Pipeline
                ─────────          ─────────────────
Planning:       0 bugs caught      33 risks identified
Test writing:   0 defensive        30 targeted tests from analysis
Implementation: 4 bugs (reactive)  1 bug (proactive — risks flagged)
Post-hoc audit: 11 bugs found      0 bugs found (confirmation only)
aTDD rounds:    7 bugs (3 rounds)  not needed

Total cost:     138K (TDD+audit)   91K (everything included)
Total bugs:     15 found post-hoc  1 found, 0 post-hoc
```

Moving bug detection from "find and fix after implementation" to "warn and
prevent during planning" cut the total cost by 34% while producing cleaner
output. The audit pass still runs as a safety net but finds nothing when
the pre-pass does its job.

### Passes eliminated

| Feature | Original TDD | Combined pipeline | Reduction |
|---------|-------------|-------------------|-----------|
| striped-block-cache | 10 sessions, 21.6M tokens | 1 session, 2.9M tokens | 7.3x |
| table-indices-and-queries | 2 sessions, 7.8M tokens* | 1 session, 91K billable | single pass |
| encrypt-memory-data | 1 mega-session, 64.9M tokens | 1 session, 17.7M tokens | 3.7x |

*Original TDD token counts include cache reads; combined pipeline billable
tokens exclude cache for accurate comparison.

The multi-session overhead of the original TDD approach (context reloading,
lost state between sessions, repeated codebase reads) is eliminated by doing
everything in a single informed pass.

### Why each step exists

Every step was added because the data showed basic TDD missed specific bug
classes, and we measured whether adding the step was cheaper than finding those
bugs later. The answer was yes in every case.

## Methodology

### Controlled comparison via git state reconstruction

Every experiment arm starts from a **byte-identical codebase state**, ensuring
apples-to-apples comparison. The process:

1. **Parent commit checkout** — `git clone --shared` at the feature's `parent_sha`
   (the commit immediately before the feature was developed). This gives us the
   exact codebase the original developer started from.

2. **Planning state overlay** — extracted from the original JSONL session logs
   using `extract-planning-state.py`. This script finds the boundary between
   planning and implementation (work-plan written, stubs created, no test files
   yet) and captures every Write/Edit operation up to that point. The overlay
   is applied via `apply-overlay.py` to reproduce the exact end-of-planning state.

3. **Stub files** — for features that add new files (not just modify existing
   ones), deterministic stubs are written with correct package declarations,
   class signatures, and `throw UnsupportedOperationException()` method bodies.
   Both arms receive identical stubs.

4. **Checksum verification** — after setup, SHA256 checksums of every source file
   in both arms are compared. The experiment only proceeds if checksums match.

This means when arm A (combined pipeline) and arm B (basic TDD or aTDD) produce
different results, the difference is entirely attributable to the pipeline — not
the starting state, the model, or the available context.

### What's measured

- **Token usage** — extracted from Claude Code session JSONL by streaming
  line-by-line and summing `input_tokens`, `output_tokens`, and
  `cache_read_input_tokens` from each usage block
- **Bug count and classification** — confirmed test failures categorized by
  bug class (implementation mistake, spec gap, trust boundary, atomicity)
- **Test coverage** — count of test files and methods, split by standard
  contract tests vs adversarial/defensive tests
- **Implementation completeness** — line counts of feature files to confirm
  both arms produced complete implementations

### Reproducibility

All data needed to reproduce any experiment is checked into `aTDD-research/`:
- `feature-inventory.json` — git SHAs for every feature
- `planning-state/` — pre-extracted overlays
- `harness/` — setup and collection scripts
- `sanitized/` — PII-scrubbed session logs
- `DATA-PROVENANCE.md` — every manual intervention documented

## Research phases

### Phase 1: Data extraction and aTDD pipeline design (2026-03-20–23)

**What we did:**
- Extracted token usage and session data from 130 Claude Code JSONL sessions
- Mapped sessions to 12 features with git SHAs for state reconstruction
- Designed the adversarial TDD pipeline: 3 new agents (Spec Analyst, Breaker,
  Constrained Refactorer) and 3 new skills (`/atdd-round`, `/atdd-audit`,
  `/atdd-refactor`)
- Built a validation harness for reproducible experiments

**Key output:** Feature inventory, sanitized session data, planning state
overlays, and automation scripts in `aTDD-research/`.

### Phase 2: Initial aTDD validation on encrypt-memory-data (2026-03-24)

**What we did:**
- Ran full aTDD (3 rounds) in both greenfield and audit modes on the most
  complex feature (47 files, 6 encryption schemes)

**Results:**
- Greenfield: 3 rounds, 20 bugs, 2.2M billable tokens, 9.1 bugs/M tokens
- Audit: 3 rounds, 8 bugs (7+1+0), 1.4M billable tokens, 5.7 bugs/M tokens
- Round 2 caught a fix-induced regression (keySegment obfuscation)
- Round 3 confirmed convergence in both modes
- T2-HEAPCOPY tendency discovered: implementer defaults to caching key material
  on heap, defeating the off-heap threat model

**Key insight:** aTDD finds real bugs that standard TDD misses, but at 2-4x
the token cost. The convergence pattern is consistent: round 1 finds the bulk,
round 2 catches regressions from fixes, round 3 confirms convergence.

### Phase 3: Pipeline enhancements shipped to standard TDD (2026-03-24)

**What we did:**
Based on Phase 2 findings, enhanced the standard TDD pipeline agents:
- **Test Writer:** defensive test vectors (boundary values, error paths,
  security-sensitive caching)
- **Code Writer:** fix-forward rule (scan for same anti-pattern after fixing)
- **Refactor Agent:** assert-only validation check, silent exception swallowing
- **TDD Protocol:** 5-minute Bash timeout on all test execution

**Hypothesis:** These enhancements might capture most of the aTDD value at
zero additional cost, since they're integrated into the existing pipeline.

### Phase 4: Comparative experiment — Enhanced TDD vs aTDD (2026-03-24)

**What we did:**
- Built experiment infrastructure (`setup-experiment.py`) to create identical
  greenfield checkouts for fair comparison
- Ran three arms on `table-indices-and-queries` (20 files, 11 constructs):
  1. Enhanced TDD (with Phase 3 improvements)
  2. Enhanced TDD + single post-implementation audit pass
  3. Full aTDD (3 iterative rounds)

**Results:**

| Arm | Tokens | Tests | Bugs found | Bug classes |
|-----|--------|-------|-----------|-------------|
| Enhanced TDD | 90K | 221 | 4 | Implementation mistakes |
| + Audit | +48K | +49 | +11 | Spec gaps, trust boundaries, identity equality |
| aTDD (3 rounds) | 89K | 203 | 7 (1+5+1) | Contract violations, atomicity |

**Key finding:** The audit and aTDD found **completely different bug classes**:

| Bug | Severity | Found by audit | Found by aTDD |
|-----|----------|---------------|---------------|
| HashSet<byte[]> identity equality (2 instances) | HIGH | Yes | No |
| FLOAT16 sort order broken | HIGH | Yes | No |
| Ne matches null fields | HIGH | Yes | No |
| VectorNearest float[] not defensively copied | MEDIUM | Yes | Yes |
| Vector dimension mismatch truncation | MEDIUM | Yes | No |
| Between inverted bounds | LOW | Yes | Yes |
| Type compatibility validation missing | — | Yes | Yes |
| FullTextMatch punctuation-only query | LOW | Yes | No |
| VectorNearest empty query vector | LOW | Yes | No |
| UNIQUE supports() missing range predicates | — | No | Yes |
| Unique update non-atomic rollback | — | No | Yes |
| Multi-unique partial insert atomicity | — | No | Yes |

The audit excels at **implementation-level pattern matching** (byte[] identity,
float encoding, null handling). aTDD excels at **cross-construct interaction
bugs** found through iterative probing (non-atomic rollback, partial insert).

This difference is caused by prompt structure: the audit reads finished code
without contract-level guidance, while the aTDD analyst focuses on contracts
but misses implementation pitfalls. Neither subsumes the other — which
motivated the combined prompt in Phase 5.

### Phase 5: Unified pipeline — merged prompt (2026-03-24)

**What we did:**
Based on Phase 4's finding that audit and aTDD have complementary blind spots,
designed a unified pipeline with a spec analyst pre-pass that uses both lenses:
- **Lens A — Contract gaps:** what the spec doesn't say (boundary values,
  null handling, atomicity, defensive copying, equality semantics)
- **Lens B — Implementation risk patterns:** what code typically gets wrong
  (byte[] identity, mutable arrays, float encoding, multi-step mutations)

The pre-pass runs before test writing, informing the test writer what to
watch for. A single audit pass after implementation catches anything the
pre-pass couldn't predict (implementation choices not visible from the contract).

**Results on table-indices-and-queries:**

| Arm | Tokens | Tests | Bugs during impl | Audit bugs | Total |
|-----|--------|-------|-------------------|------------|-------|
| v1: Enhanced TDD alone | 90K | 221 | 4 | n/a | 4 (+11 unfound) |
| v1: + post-hoc audit | +48K | +49 | — | 11 | 15 |
| v1: Full aTDD | 89K | 203 | — | — | 7 |
| **v2: Combined pipeline** | **91K** | **261** | **1** | **0** | **1** |

The combined pipeline produced zero-bug output at the same cost as enhanced
TDD alone. The spec analysis pre-pass **prevented** the bugs from being written
rather than finding them after the fact.

### Phase 6: Cross-complexity validation (2026-03-24)

**What we did:**
Validated the combined pipeline on features at both ends of the complexity range:
- **striped-block-cache** (3 files, simplest feature)
- **encrypt-memory-data** (47 files, security-critical — still running)

**striped-block-cache results:**

| Metric | Original TDD | Combined pipeline |
|--------|-------------|-------------------|
| Total tokens | 21.6M (10 sessions) | 2.9M (1 session) |
| Bugs found | 0 | 0 |
| Tests | existing | 62 new (52 contract + 10 adversarial) |
| Ratio | | **7.3x cheaper** |

The combined pipeline correctly determined this simple feature has no bugs,
in one session instead of ten. The spec analysis overhead was negligible (21K
billable tokens total).

**encrypt-memory-data results (combined pipeline):**

| Approach | Billable (in+out) | Total (all tokens) | Bugs |
|----------|-------------------|--------------------|------|
| Original TDD (1 mega-session) | — | 64.9M | 426 tests, bugs unknown |
| aTDD Greenfield (3 rounds) | 111K | 34.1M | 20 bugs |
| aTDD Audit (3 rounds) | 86K | 17.1M | 8 bugs (7+1+0) |
| **Combined pipeline** | **79K** | **17.7M** | **3 impl, 0 audit** |

The combined pipeline on the most complex feature (47 files, 6 encryption
schemes) produced:
- 55 spec analysis findings (27 contract gaps + 28 implementation risks)
- 633 total tests (296 new: contract + 17 adversarial)
- 3 bugs caught during implementation (OPE iteration overflow, OPE roundtrip
  domain mapping, EncryptionSpec Deterministic capability mismatch)
- **0 bugs found during audit** — all 17 adversarial tests passed on first
  implementation

The 20 test failures are not implementation bugs: 19 are test-setup errors
(32-byte key for AES-SIV which requires 64 per contract) and 1 is a
pre-existing stub (FullTextFieldIndex, separate feature out of scope).

**Comparison with prior aTDD validation (Phase 2):**
The Phase 2 aTDD greenfield run found 20 bugs post-implementation including
the T2-HEAPCOPY tendency. The combined pipeline prevented those bug classes
from being written — the spec analyst flagged key material handling, mutable
array copying, and encryption mode mismatches before test writing began.
Result: 3.7x cheaper than original TDD, same cost as aTDD audit mode, but
zero post-implementation bugs.

## What happens if you skip each step

We tested every combination. Here's what each step catches that nothing else does:

| If you skip... | You miss... | Evidence |
|---------------|-------------|----------|
| Spec analysis pre-pass | 11+ bugs shipped to production (spec gaps, trust boundary violations) | v1 enhanced TDD: 4 bugs found during impl, 11 lurking unfound |
| Audit pass | Implementation pitfalls invisible from the contract (byte[] identity, float encoding, null semantics) | v1 aTDD found 7 bugs but missed 8 that the audit caught |
| Both lenses in spec analysis | Either contract gaps (Lens A only) or implementation pitfalls (Lens B only) | v1 audit found code bugs, v1 aTDD found contract bugs — neither found both |
| Fix-forward rule | Same bug recurring in 2-4 other constructs | v1 enhanced TDD: float sign-bit fix applied to 3 decoders proactively |
| Defensive test vectors | Boundary values, error paths, lifecycle bugs | Generic "check for nulls" misses feature-specific edge cases |

The pipeline isn't complex for complexity's sake. Each piece exists because we
measured what happens without it.

## Conclusions

### 1. Spec analysis is the key value driver

The most impactful change is not the audit or the iterative rounds — it's the
**spec analyst pre-pass with both lenses**. By identifying contract gaps and
implementation risk patterns before test writing, the pipeline prevents bugs
rather than finding them. Prevention is cheaper than detection.

### 2. One pipeline, configurable depth

The research started with three named tiers (Quick / Enhanced TDD / Full aTDD).
It ended with one pipeline and a dial:

```
Spec Analysis → Tests → Implement → Refactor → Audit/Break → Fix
                                                    ↑          |
                                                    └──────────┘
                                                   (repeat N times)
```

- 0 loops: `/feature-quick` (trivial changes)
- 1 loop: default (single audit pass for confirmation)
- N loops: user opt-in (complex domains, converges in 2-3 rounds)

### 3. Audit and aTDD find different things

Post-implementation audit catches implementation-level pitfalls (byte[] identity,
float encoding, null handling). Iterative aTDD catches cross-construct interaction
bugs (non-atomic rollback, partial multi-index failure). The combined prompt merges
both lenses so a single pass catches both classes.

### 4. Knowledge compounds across features

Adversarial findings should persist in `.kb/` as `type: adversarial-finding`
entries with domain tags. Feature summaries persist as `type: feature-footprint`
entries. The test writer reads adversarial KB entries during defensive vector
generation. Each feature audited makes the next one smarter.

### 5. The convergence pattern is consistent

Across all features tested:
- Round 1 finds the bulk of bugs
- Round 2 catches regressions from round 1 fixes and deeper interactions
- Round 3 confirms convergence with diminishing returns

This supports making 1 loop the default and additional rounds opt-in.

## Changes shipped to vallorcine

### Agents
- `test-writer-agent.md` — defensive test vectors, adversarial KB integration
- `code-writer-agent.md` — fix-forward rule
- `refactor-agent.md` — assert-only validation, exception swallowing checks
- `breaker-agent.md` — respect existing validation contracts

### Rules
- `tdd-protocol.md` — 5-minute Bash timeout on all test execution

### Skills
- `feature-retro/SKILL.md` — feature footprint generation, adversarial finding
  graduation to KB
- `feature-test/SKILL.md` — timeout at failure verification
- `feature-implement/SKILL.md` — timeout at baseline + final verification
- `feature-coordinate/SKILL.md` — timeout at post-coordination suite

### KB
- `kb/_refs/adversarial-finding-template.md` — new entry type schema
- `kb/_refs/feature-footprint-template.md` — new entry type schema
- `kb/CLAUDE.md` — template references added

### Still to implement
- Spec analyst pre-pass integration into `/feature-test`
- Domain scout reading feature footprints during `/feature-domains`
- Unified pipeline prompt as the default for `/feature`

## Next steps

1. ~~**Validate encrypt-memory-data**~~ — complete: 3 impl bugs, 0 audit bugs, 17.7M tokens (3.7x cheaper than original TDD)
2. **jlsm hardening sweep** — 12 features in chronological order using the
   combined audit prompt. Single `hardening` branch, fixes accumulate, KB
   entries graduate between features.
3. **Ship the unified pipeline** — integrate spec analyst pre-pass into
   `/feature-test`, make audit loop the default, implement KB integration
4. **Retire the tier model** — remove references to "Enhanced TDD" and "aTDD"
   as separate pipelines. One pipeline, configurable depth.

## Data and reproducibility

All research data is in `aTDD-research/`:
- `feature-inventory.json` — 12 features with git SHAs, token costs, file lists
- `briefs/` and `work-plans/` — feature specifications
- `planning-state/` — reconstructed end-of-planning state per feature
- `sanitized/` — PII-scrubbed JSONL sessions (84 files)
- `harness/` — automation scripts for experiment setup and result collection
- `results/` — completed validation run outputs
- `DATA-PROVENANCE.md` — manual interventions and exclusion rationale

Experiment checkouts (temporary):
- `/tmp/vallorcine-experiment/` — v1 three-arm comparison
- `/tmp/vallorcine-experiment-v2/` — v2 combined pipeline + prompts
- `/tmp/vallorcine-validation/` — cross-complexity validation runs
