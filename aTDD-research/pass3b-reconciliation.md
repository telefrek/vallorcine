# Pass 3b — Cross-Cluster Reconciliation

You are reconciling findings across all clusters. Your job is to find bugs
that span cluster boundaries — issues that no single-cluster subagent could
see because they only had visibility into their own cluster. This is a
lightweight, document-only pass.

Do not read source code. Do not re-analyze constructs. Your only inputs are
the structured outputs of previous passes.

## Input

Read these files (and ONLY these files):

1. **All `pass3a-cluster-{N}.md` files** — the findings, cleared cells, data
   flow analysis, and summaries from every cluster subagent
2. **The construct inventory** (Pass 1 output) — for relationship edges,
   especially edges that cross cluster boundaries
3. **The cluster definitions** (Pass 2.5 output) — for understanding which
   constructs were assigned to which cluster
4. **`spec-context.md`** (if it exists) — the spec requirements bundle. Used
   to check whether findings map to spec requirements and whether any spec
   requirements have no corresponding analysis coverage.

Do NOT read source code files. You are reasoning about structured findings
and relationship graphs, not about code.

## Task

### Step 1 — Build the cross-cluster edge map

From the construct inventory, identify all relationship edges where the
source and target constructs are in DIFFERENT clusters. These are the
boundary edges. For each one, record:

- Source construct and its cluster
- Target construct and its cluster
- Edge type and weight
- Whether the edge is `data_flow` (these are highest priority)

Also identify any boundary edges that Pass 3a subagents flagged — look for
notes like "data flows to {construct} which is outside this cluster." Collect
these boundary annotations from all cluster findings.

### Step 2 — Producer/consumer mismatch analysis

For each `data_flow` edge that crosses a cluster boundary:

1. Read the source cluster's findings for the producer construct — what
   attacks were found? What was cleared and why?
2. Read the target cluster's findings for the consumer construct — what
   attacks were found? What assumptions does it make about incoming data?
3. Check for mismatches:
   - Does the producer validate data that the consumer assumes is validated?
   - Does the producer's clearing reasoning ("value bounded by X") hold
     when the consumer uses the data differently?
   - Did one side find a vulnerability that the other side's clearing
     reasoning depends on being absent?

A mismatch exists when Cluster A's findings or clearing reasoning about a
producer contradicts Cluster B's assumptions about the data that producer
sends. This is the highest-value output of reconciliation.

### Step 3 — Systemic pattern detection

Scan all cluster findings for repeated patterns:

- Same concern area appearing as a finding across 3+ clusters (e.g.,
  "Input validation" findings in clusters 1, 3, and 4 all involve missing
  bounds checks on size parameters)
- Same attack shape recurring (e.g., integer overflow in arithmetic on
  untrusted values, missing null checks on deserialized data)
- Same clearing weakness (e.g., multiple clusters cleared cells with
  "only caller passes safe values" — fragile if a new caller is added)

A systemic pattern means the codebase has a tendency, not just isolated
bugs. These inform KB entries and project-level test vectors.

### Step 4 — Gap analysis

Check for constructs that may have been under-analyzed:

1. **Boundary orphans:** Constructs that appear in cross-cluster edges but
   had zero applicable cells in the triage matrix. Were they correctly
   triaged as not applicable, or were they missed because they sit at a
   boundary?
2. **Unmatched boundary annotations:** Pass 3a subagents flagged edges
   leaving their cluster — did the receiving cluster's subagent analyze the
   other side of that edge? If not, the edge was never fully analyzed.
3. **Skipped constructs with edges:** Constructs listed in the "Skipped
   constructs" section of the cluster definitions that have edges to
   constructs with findings. A skipped construct that feeds data to a
   construct with a vulnerability may be part of the attack path.

### Step 5 — Complementary finding synthesis

Look for findings from different clusters that combine into a larger issue:

- Cluster A found that a producer can emit invalid data under certain
  conditions + Cluster B found that a consumer does not validate that
  field = combined finding: invalid data flows end-to-end unchecked
- Cluster A found a resource lifecycle issue in a shared type + Cluster B
  found concurrent access to that same type = combined finding: lifecycle
  bug under concurrency
- Cluster A cleared a cell because "caller validates" + the caller is in
  Cluster B which found that the caller's validation is incomplete =
  the clearing reasoning is invalidated

These combinations are findings that exist ONLY because of cross-cluster
visibility. No single subagent could have found them.

### Step 6 — Spec coverage analysis (only when spec-context.md exists)

If spec context was provided, build a coverage map:

1. **Collect all spec requirement references** from Pass 3a findings (the
   `Spec requirement` field) and from cleared cells with spec conformance
   concern area.

2. **Compare against the full requirement list** in spec-context.md. For each
   requirement:
   - **Covered** — at least one finding or cleared cell references it
   - **Uncovered** — no cluster analyzed it. This means either (a) triage
     didn't map it to any construct, or (b) the requirement describes behavior
     at a boundary that falls between clusters.
   - **Undocumented behavior count** — findings tagged "undocumented" that
     describe code behavior no spec requirement covers.

3. Uncovered requirements are gaps — not necessarily bugs, but areas where the
   audit cannot confirm the implementation matches the spec. Report them so the
   user can decide whether to extend the audit or accept the gap.

## Output

Write findings to `pass3b-reconciliation.md`.

Use this format:

```markdown
# Cross-Cluster Reconciliation

## Cross-Cluster Findings

### X-{seq}: {one-line summary}

- **Source clusters:** {cluster IDs and names}
- **Constructs involved:** {list of constructs from different clusters}
- **Type:** producer-consumer mismatch | complementary finding | invalidated clearing
- **Description:** {what the cross-cluster issue is}
- **How it combines information:** {specifically what Cluster A's analysis
  says and what Cluster B's analysis says, and why the combination reveals
  a bug neither could see alone}
- **Severity:** high | medium | low

### X-{seq}: {next finding}

...

## Systemic Patterns

### Pattern: {pattern name}

- **Affected clusters:** {cluster IDs and names}
- **Construct count:** {how many constructs exhibit this pattern}
- **Description:** {what the pattern is and why it's systemic}
- **Representative findings:** {finding IDs from individual clusters that
  exemplify the pattern}

### Pattern: {next pattern}

...

## Gap Analysis

### Unanalyzed boundary edges

| Source construct | Source cluster | Target construct | Target cluster | Edge type | Gap reason |
|-----------------|---------------|-----------------|----------------|-----------|------------|
| Foo.produce | Cluster 1 | Bar.consume | Cluster 2 | data_flow | Target had no applicable cells |

### Skipped constructs with finding-adjacent edges

| Construct | Edge to | Edge type | Finding | Risk |
|-----------|---------|-----------|---------|------|
| SkippedType | Foo.method | uses_type | F-2.3 | May be part of attack path |

## Spec Coverage (omit section if no spec context)

### Requirement coverage

| Requirement | Status | Evidence |
|-------------|--------|----------|
| R1 | covered | F-1.2 (finding), Cluster 1 cleared cell |
| R3 | covered | F-2.1 (finding) |
| R5 | uncovered | Not mapped to any construct in triage |

### Undocumented behaviors

| Finding | Construct | Behavior | Notes |
|---------|-----------|----------|-------|
| F-1.4 | Foo.bar | Silently accepts negative offset | No spec requirement covers negative input handling |

### Coverage summary

- Total spec requirements: {count}
- Covered by analysis: {count}
- Uncovered (gap): {count}
- Undocumented behaviors found: {count}

## Summary

- Cross-cluster findings: {count}
- Systemic patterns: {count}
- Boundary edges analyzed: {count}
- Unanalyzed boundary gaps: {count}
- Skipped constructs with finding-adjacent edges: {count}
- Spec requirements covered: {count} / {total} (omit if no spec context)
```

## Rules

### No source code

You do not read source code. You reason from findings, clearing reasoning,
edge annotations, and cluster definitions. If you cannot determine whether
a cross-cluster issue exists from the documents alone, flag it as a gap
rather than inventing an analysis.

### No re-analysis of within-cluster concerns

If a cell was cleared with specific reasoning by a cluster subagent, do not
second-guess the clearing unless another cluster's findings contradict it.
Your job is cross-cluster synthesis, not audit review.

### Concrete combinations only

Every cross-cluster finding must cite specific findings or clearing entries
from at least two different clusters. "These clusters might interact" is not
a finding. "F-1.3 found the producer can emit negative sizes, and F-2.1's
clearing reasoning assumes sizes are non-negative" is a finding.

### No severity inflation

A systemic pattern is not automatically "high" severity. Three low-severity
findings of the same shape are a systemic pattern with low per-instance
severity. The pattern itself is informational — it guides KB entries and
project-level awareness, not immediate test priority.

### Empty sections are fine

If there are no producer-consumer mismatches, say so. If there are no
systemic patterns, say so. A reconciliation pass that finds nothing
cross-cluster is a valid outcome — it means the cluster boundaries were
well-chosen and the subagents had sufficient visibility.

Write the file and return the summary.
