# Pass 2.5 — Construct Clustering

You are grouping constructs into clusters for deep analysis. This is a graph
partitioning task — read the construct inventory and triage matrix, then
produce clusters that group tightly-connected constructs together. Do not read
source code. Do not analyze for bugs.

## Input

Read the construct inventory (Pass 1 output) for the full list of constructs
and their relationship edges.

Read the triage matrix (Pass 2 output) for the set of applicable cells per
construct.

These two files are your only inputs. Do NOT read source code files.

## Task

### Step 1: Build the edge graph

From the construct inventory, extract all relationship edges. Weight them by
clustering strength:

| Edge type | Weight | Rationale |
|-----------|--------|-----------|
| `data_flow` | 5 | Strongest signal — constructs that produce and consume the same data MUST be analyzed together |
| `inherits` | 4 | Subtype must be analyzed against its contract |
| `uses_type` | 3 | Type dependency creates implicit coupling |
| `creates` | 3 | Creator must understand what it creates |
| `reads_field` | 3 | Field access couples to internal representation |
| `shares_state` | 4 | Methods sharing mutable state MUST be analyzed together for concurrency and lifecycle bugs |
| `calls` (cross-file) | 3 | Cross-boundary calls indicate meaningful interaction |
| `calls` (same-file) | 1 | Often just internal delegation within a class |
| `contains` | 1 | Containment is structural, not behavioral — inner types may belong in different clusters if their edges pull elsewhere |

For edge weighting purposes, determine whether a `calls` edge is cross-file
or same-file by checking whether the source and target constructs appear under
different file headings in the inventory.

### Step 2: Identify applicable constructs

A construct is "applicable" if it has at least one applicable cell in the
triage matrix. Count the applicable cells per construct.

Constructs with zero applicable cells AND zero edges to applicable constructs
are **orphans** — they will be handled in Step 5.

### Step 3: Form initial clusters

Using a greedy connected-component approach:

1. Form **mandatory groups** using unsplittable edges, but only within a
   single type boundary:
   - All constructs connected (directly or transitively) by `shares_state`
     edges **on the same type** form a mandatory group. Methods on the same
     mutable class that share state must be analyzed together.
   - All constructs connected (directly or transitively) by `data_flow`
     edges **within the same file** form a mandatory group (e.g., serialize
     and deserialize on the same type).
   - `data_flow` edges that cross file/type boundaries (e.g., Writer.finish
     → Reader.open) are **strong preferences, not mandatory**. The clustering
     step should try to keep them together, but may place them in separate
     clusters. Cross-type data flow bridges are handled by Pass 3b
     reconciliation, which is purpose-built for cross-cluster producer/consumer
     analysis.
   - A `shares_state` group and a `data_flow` group connected only by a
     cross-type bridge may be in separate clusters.
2. For each mandatory group, expand by adding constructs connected by edges
   of weight >= 3 (inherits, uses_type, creates, reads_field, cross-file
   calls). Add a construct if it has 2+ weighted edges into the group, or if
   it has a single edge of weight >= 4.
3. Repeat expansion until no more constructs qualify.
4. Remaining applicable constructs not yet assigned: attach each to the
   cluster it has the strongest total edge weight to. If tied, prefer the
   cluster whose constructs share the same file.

### Step 4: Cluster sizing guidance

There are no hard limits on cluster size. The graph structure determines
natural cluster boundaries — unsplittable edges (`data_flow`, `shares_state`)
must be respected, and forcing splits that break these edges is worse than
having a larger cluster.

**Preferred range:** 6-15 applicable cells per cluster. This is a soft
preference, not a constraint.

**Merging small clusters:** If a cluster has fewer than 4 applicable cells,
consider merging it into the cluster it has the strongest edge weight to,
as long as the merge doesn't combine unrelated concerns. Very small clusters
add orchestrator overhead without analytical benefit.

**Large clusters are acceptable** when driven by unsplittable edges. If a
type has many methods sharing mutable state, those methods belong together
regardless of how many applicable cells that creates. A 25-cell cluster of
tightly-coupled constructs is better than two 12-cell clusters that can't
see each other's concurrency bugs.

**Complexity warning:** If any single cluster exceeds 25 applicable cells or
500 source lines, flag it in the output as a complexity warning. This may
indicate a type that would benefit from refactoring before audit, and the
orchestrator should surface this to the user. Format:

```
⚠ Cluster "{name}" has {n} applicable cells / {n} source lines.
  This suggests high coupling — consider refactoring before audit to
  reduce analysis cost and improve coverage.
```

### Step 5: Handle orphans

- Constructs with no applicable cells AND no edges to any applicable
  construct: skip them entirely. List them in a "Skipped constructs" section
  for transparency.
- Constructs with applicable cells but no edges to other applicable
  constructs: assign to the nearest cluster by file proximity (same file
  first, then adjacent files in the inventory listing).

### Step 6: Annotate clusters

For each cluster, derive:

1. **Cluster name:** A short descriptive label (2-4 words) reflecting the
   cluster's role. Examples: "Codec contract," "Reader lifecycle,"
   "Serialization pipeline," "Entry iteration." Do not use generic names
   like "Cluster 1."

2. **Data flow annotation:** If the cluster contains any `data_flow` edges,
   describe what data flows through the cluster and whether it crosses a
   trust boundary (from the data_flow edge annotations in the inventory).
   If no data_flow edges, write "No direct data flow."

3. **Files to read:** For each file that contains constructs in this cluster,
   list the specific line ranges that the deep analysis subagent should read.
   Merge adjacent or overlapping ranges (e.g., lines 44-116 instead of 44-49
   and 56-116). Add 5 lines of padding above the first construct and below
   the last construct in each file to capture surrounding context (field
   declarations, imports, etc.), clamped to file boundaries.

## Output

Write the cluster definitions file. Use this format:

```markdown
# Construct Clusters — <feature-name>

## Cluster 1: <Descriptive Name>

### Constructs
| Construct | File | Lines | Applicable cells |
|-----------|------|-------|-----------------|
| ClassName | FileName.ext | 10-200 | Input, Data, Capacity |
| ClassName.method | FileName.ext | 45-80 | Input, Error |

### Cluster ID: 1
### Applicable cells: <n>
### Source lines: <n>

### Data flow
<Description of data flowing through this cluster and trust boundaries,
or "No direct data flow.">

### Files to read
- `path/to/File.ext`: lines 5-205
- `path/to/Other.ext`: lines 40-120

---

## Cluster 2: <Next Cluster Name>
...

---

## Skipped constructs

| Construct | File | Reason |
|-----------|------|--------|
| ConstantClass | File.ext | No applicable cells, no edges to applicable constructs |

---

## Summary

Clusters: <n>
Total constructs assigned: <n>
Total applicable cells covered: <n> / <total from triage matrix>
Skipped constructs: <n>
```

One section per cluster, separated by horizontal rules. Clusters should be
ordered by applicable cell count (highest first) so the most complex clusters
are analyzed first by downstream subagents.

Write the file and return the summary.
