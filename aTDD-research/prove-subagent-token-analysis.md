# Prove Subagent Token Analysis

Session: `51fd6abf-d847-4249-816f-862506af83f4`
Agents: 9 Prove subagents (4 shared_state, 2 contract_boundaries, 2 data_transformation, 1 dispatch_routing)
Date: 2026-04-02

## Executive Summary

Total cost: **$20.70** across 9 parallel Prove agents, consuming **41.2M context tokens** and **191K output tokens**. The dominant cost driver is **context window growth** (not file duplication). Each agent's context grows 5-12x from Turn 1 to its final turn, with the last 25% of turns consuming 33-38% of total context tokens. Compile/fix retry loops are a secondary but significant cost driver, responsible for 35 extra turns across the pipeline.

Sequential execution with shared cache would save approximately **$1-2** (from eliminating redundant cache_creation on 43 duplicate file reads). The real savings opportunity is **reducing turn count** — fewer compile retries and tighter task scoping.

## Per-Agent Breakdown

| Agent | Turns | Reads | Unique Files | Cost | Context Growth |
|-------|-------|-------|-------------|------|----------------|
| shared_state C2 | 134 | 25 | 12 | $4.13 | 12.2x |
| data_transformation C2 | 120 | 23 | 9 | $3.08 | 10.6x |
| shared_state C1 | 85 | 14 | 10 | $2.70 | 10.7x |
| shared_state C4 | 92 | 23 | 8 | $2.36 | 9.1x |
| contract_boundaries C2 | 98 | 24 | 13 | $2.26 | 9.9x |
| contract_boundaries C1 | 82 | 25 | 10 | $1.94 | 9.3x |
| dispatch_routing C1 | 81 | 22 | 8 | $1.90 | 7.6x |
| data_transformation C1 | 66 | 15 | 7 | $1.48 | 6.7x |
| shared_state C3 | 33 | 12 | 6 | $0.84 | 5.2x |

The cheapest agent (shared_state C3) finished in 33 turns. The most expensive (shared_state C2) took 134 turns — 4x the turns for 5x the cost. This is superlinear: more turns = each turn costs more due to context growth.

## Context Window Growth

Every agent shows the same pattern: context starts at 6-8K tokens (system prompt + initial task) and grows monotonically as conversation history accumulates.

**Percentile context sizes (tokens per turn):**

| Agent | P25 | P50 | P75 | P100 | Q4/Q1 ratio |
|-------|-----|-----|-----|------|-------------|
| shared_state C2 | 54,759 | 76,823 | 87,046 | 99,570 | 2.4x |
| data_transformation C2 | 46,241 | 54,926 | 62,323 | 86,048 | 2.4x |
| shared_state C1 | 41,071 | 57,564 | 80,303 | 87,554 | 2.9x |
| shared_state C4 | 38,524 | 53,582 | 63,239 | 74,434 | 2.5x |
| contract_boundaries C2 | 38,486 | 51,574 | 60,924 | 65,923 | 2.3x |
| contract_boundaries C1 | 38,733 | 49,159 | 55,135 | 62,117 | 2.3x |
| dispatch_routing C1 | 38,329 | 50,325 | 54,893 | 62,111 | 2.3x |
| data_transformation C1 | 36,479 | 45,140 | 49,222 | 54,524 | 2.2x |
| shared_state C3 | 29,135 | 34,700 | 40,093 | 42,426 | 2.9x |

The last 25% of turns consistently consume 33-38% of total context tokens. This is the context growth tax — late-session work costs 2-3x what early-session work costs per turn.

**Theoretical minimum (if context didn't grow):** The sum across all agents is 6.2M tokens vs the actual 41.2M tokens. Context growth accounts for **85% of total context cost**.

## File Overlap (Cross-Agent Duplication)

40 unique files read across all agents. 12 files read by 2+ agents. 28 files read by only 1 agent.

**Files read by all 9 agents:**
- `LsmVectorIndex.java` (the main source under audit)
- `build.gradle` (for compilation)
- `prove.md` (the agent's task prompt)

**Files read by 3-5 agents:**
- `LsmVectorIndexFloat16Test.java` (5 agents)
- `VectorIndex.java` interface (4 agents)
- Various test files (3-4 agents each)

**Duplication ratio: 2.08x** — 83 total file-reads for 40 unique files. 43 redundant reads.

The overlap is concentrated in 3 universally-read files and the VectorIndex interface. The test files are less duplicated because each agent works on a different cluster of findings.

**Pairwise overlap matrix (shared files between agent pairs):**

Most pairs share 3-6 files (the universal files). The highest overlap is shared_state C1 and C2 at 6 files — these work on the same concern area and share more test scaffolding.

## Compile/Fix Retry Analysis

| Agent | Total Compiles | Retry Compiles | Longest Streak | Compile Context (% of total) |
|-------|---------------|----------------|----------------|------------------------------|
| data_transformation C2 | 20 | 12 | 3 | 1.1M (17%) |
| shared_state C4 | 13 | 11 | **7** | 764K (16%) |
| shared_state C2 | 10 | 4 | 2 | 725K (7%) |
| contract_boundaries C2 | 9 | 4 | 2 | 494K (10%) |
| contract_boundaries C1 | 6 | 2 | 2 | 309K (8%) |
| data_transformation C1 | 5 | 1 | 1 | 234K (8%) |
| dispatch_routing C1 | 5 | 1 | 1 | 260K (7%) |
| shared_state C1 | 3 | 0 | 1 | 202K (4%) |
| shared_state C3 | 1 | 0 | 1 | 37K (3%) |

**Total retry compiles across all agents: 35 out of 72 total compiles (49%).**

Two agents stand out:
- **data_transformation C2**: 20 compile turns, 12 retries, 3 consecutive compile streak. This agent spent 17% of its context budget just compiling.
- **shared_state C4**: 13 compile turns, 11 retries, **7 consecutive compiles** — the longest streak. At turn 92 with 74K context, each retry compile costs ~74K tokens just in context.

The compile retries add roughly 35 extra turns across the pipeline. At average context of ~52K tokens/turn, that is approximately **1.8M tokens of wasted context** on retry turns alone.

## Token Spending by Activity

| Activity | Context Tokens | % of Total |
|----------|---------------|------------|
| Other (reasoning, planning, Grep, Glob) | 18.6M | 45% |
| Read (file reads) | 6.9M | 16% |
| Test (running tests) | 6.1M | 14% |
| Compile (building) | 5.2M | 12% |
| Edit (writing code) | 4.3M | 10% |

The "Other" category (45%) is turns where the agent is reasoning, planning, or using tools like Grep/Glob. This is the largest category because the agent reasons between actions, and each reasoning turn carries the full context window.

## Cost Structure Summary

| Component | Tokens | Cost | % of Total |
|-----------|--------|------|------------|
| Cache reads | 41.2M | $12.35 | 60% |
| Cache creation | 1.5M | $5.49 | 26% |
| Output | 191K | $2.86 | 14% |
| Non-cached input | 863 | $0.00 | 0% |
| **TOTAL** | | **$20.70** | |

Almost all input tokens are served from cache (99.997%). The cost split is 60% cache reads, 26% cache creation, 14% output.

## Sequential vs Parallel: What Would Actually Save Money?

### What sequential execution saves
- **Cache creation on 43 redundant file reads.** If agents run sequentially, files read by agent N are already in cache when agent N+1 needs them. This converts cache_creation ($3.75/1M) to cache_read ($0.30/1M).
- Estimated savings: **$1-2** (cache_creation is 26% of total and not all of it is duplicated files).

### What sequential execution does NOT save
- **Context window growth.** Each agent's conversation history grows independently regardless of execution order. The 41.2M context tokens are driven by turn count, not file reads.
- **Compile retries.** These are agent-specific failures unrelated to execution order.
- **Output tokens.** The agent writes the same tests regardless.

### What WOULD save significant money

1. **Reducing turn count (biggest lever).** The theoretical minimum context cost (if every turn had Turn 1's context size) is 6.2M vs actual 41.2M. Reducing turns by 30% would save more than any caching strategy.

2. **Eliminating compile retries.** 35 retry compiles equal approximately 1.8M wasted context tokens. Solutions:
   - Pre-compile a skeleton test file before handing off to the agent
   - Provide the agent with known-good import lists and test scaffolding
   - Use a compilation check phase that does not carry full conversation history

3. **Phase-splitting within each agent.** If a Prove agent's work naturally splits into "analyze, write test, fix compilation, run test", each phase could be a fresh session reading a handoff file. A 120-turn session becomes three 40-turn sessions, and each session starts with a small context window.

4. **Reducing number of agents.** shared_state has 4 agents. If clusters C1-C4 could be merged into 2, we would eliminate 2 agents' worth of system prompt and initial context overhead (minor) but more importantly avoid the duplicate file reads and reduce total turn count.

## Tool Call Distribution

Global tool call counts across all 9 agents:
- Bash: 191 (compilation + test execution)
- Read: 183 (file reads)
- Edit: 47 (code modifications)
- Grep: 40 (code search)
- Write: 20 (new file creation)
- Glob: 11 (file discovery)

Total tool calls: 492 across 791 assistant turns (0.62 tool calls/turn average).
