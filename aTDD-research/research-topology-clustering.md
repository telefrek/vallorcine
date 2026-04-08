# Research: Topology-Aware Code Clustering for Bug Finding

**Date:** 2026-03-31
**Context:** Replacing naive edge-weight clustering in audit pipeline with
topology-aware neighborhoods grounded in program analysis research.

## Problem statement

The current audit pipeline clusters code constructs by summing structural
edge weights (calls=1, uses_type=3, shares_state=4, data_flow=5). This is
naive: it flattens qualitatively different relationship types into a single
number, loses topology information, and produces clusters that don't align
with where bugs actually live.

Validated by first pipeline run: 55 constructs forced into 1 cluster,
Suspect did shallow analysis, found 9 bugs vs. prior pipeline's 35 bugs
on the same code with 8 topology-unaware but smaller clusters.

## Key findings from research

### 1. Where bugs actually cluster (empirical evidence)

**Fault localization research (Jones & Harrold 2005, Abreu et al. 2007):**
Bugs do NOT cluster by structural proximity. A bug in module A frequently
manifests as a test failure in module B. Execution frequency correlation
with failures is a stronger predictor of bug location than structural
metrics (coupling, cohesion, complexity).

**Process metrics beat product metrics (Rahman & Devanbu 2013):**
Change history, author count, and change entropy predict bugs better than
LOC, complexity, or coupling. But for LLM-based analysis without change
history, the next best predictor is dependency density — how many dependency
chains pass through a construct.

**Logical coupling predicts bugs better than structural coupling
(Cataldo et al. 2009):** Modules that are coupled through shared invariants
or behavioral contracts (logical coupling) are a stronger predictor of bugs
than modules that reference each other structurally. The probability of a
bug increases when developers modify one side of a logical dependency
without modifying the other.

**Bugs cluster at assumption mismatches (Yau & Collofello 1980):**
The "ripple effect" literature found bugs cluster at the boundary of the
impact set — constructs that are just barely impacted by a change, where
the developer didn't think through the implications.

### 2. Execution topologies detectable by LLMs

| Topology | Detection method | LLM feasibility |
|----------|-----------------|-----------------|
| Data flow pipeline | Follow value through transformation chain, identify source/sink | High |
| State machine | Fields with enumerated values + methods that read/write them | High (lexical signals) |
| Resource scope | Acquire/release pairs (open/close, lock/unlock, begin/commit) | Very high |
| Producer/consumer | Symmetric method pairs on shared data format (write/read, encode/decode) | Very high |
| Observer/notification | Collection of listeners + register/unregister + notification loop | High |
| Dominator set | Construct through which all access to a set of others must pass | Moderate (graph reasoning) |
| Request/response cycle | Entry point dispatching to handlers based on discriminant | High |

### 3. Multi-edge graph analysis

**The flattening problem (Interdonato et al. 2020):**
Collapsing multiple edge types into a single weighted graph erases
qualitative differences. Three `calls` edges (weight 3) look the same as
one `data_flow` edge (weight 5), but the latter indicates implicit coupling.

**Multi-layer density (Berlingerio et al. 2011):**
A neighborhood is "good" if constructs are connected by multiple edge types
simultaneously. Count distinct edge types, don't sum weights. A construct
with 3 different edge types to the cluster is a stronger candidate than one
with 1 edge type at high weight.

**GenLouvain (Mucha et al. 2010):**
Multi-layer community detection that optimizes modularity across layers
simultaneously. Not LLM-executable but the insight applies: clusters should
be dense in multiple layers, not just one.

### 4. Bounded exploration strategies

**Local Community Detection (Clauset 2005):**
Start with a seed, expand greedily, stop when adding the next node would
increase boundary edges more than internal edges (conductance criterion).
Automatically determines neighborhood size from graph structure.

**Personalized PageRank sweep (Andersen et al. 2006):**
Start at seed, spread probability mass, sweep by PPR/degree ratio, cut at
minimum conductance. Produces conductance-optimal neighborhoods. Not
directly LLM-executable but the greedy heuristic equivalent is.

**Practical for LLMs:** LCD-style greedy expansion with conductance-based
stopping, seeded by topology-detected groups. This is a principled version
of what the current Pass 2.5 does informally.

### 5. Architecture recovery patterns (ACDC, Tzerpos & Holt 2000)

Seven subsystem patterns that map to our topology types:

| ACDC pattern | Our topology | Detection |
|-------------|-------------|-----------|
| Central dispatcher | Request/response | Method calling many others based on discriminant |
| Leaf collection | Utility neighborhood | Set of constructs used by one coordinator |
| Subgraph dominator | Resource scope | All paths to a set go through one construct |
| Support library | Shared dependency (boundary tier) | High fan-in, low fan-out |

The **dominator pattern** is high value: if construct D dominates {A, B, C}
in the dependency graph, {D, A, B, C} is a mandatory group.

### 6. How developers actually understand code (Pennington 1987)

Developers chunk code by **data flow first, then control flow**. This
empirically validates prioritizing data flow relationships over structural
call relationships in clustering. The "beacon" concept (recognizable
patterns like open/close, read/write) maps to topology detection.

## Proposed approach

### Phase 1: Topology-first mandatory grouping

Replace edge-weight mandatory groups with topology detection:
- State machines → all participants mandatory-group
- Resource scopes → all code between acquire/release mandatory-group
- Producer/consumer pairs → both sides mandatory-group
- Dominator sets → dominator + dominated mandatory-group

### Phase 2: Multi-layer density expansion

Replace edge-weight expansion with multi-edge-type counting:
- Count distinct edge types connecting candidate to cluster
- 3 edge types at weight 1 > 1 edge type at weight 5
- Edge types: def_use, contract, transformation, control_influence, invariant

### Phase 3: Conductance-based stopping

Replace fixed size targets with conductance criterion:
- Stop expanding when next candidate adds more cross-boundary edges than
  within-boundary edges
- Automatically produces small clusters for loose coupling, large for tight
- No artificial 6-15 cell target

## Edge type taxonomy (proposed replacement for weighted structural edges)

| Edge type | What it captures | Detection method |
|-----------|-----------------|-----------------|
| def_use | A writes state that B reads before redefinition | Trace field writes/reads |
| contract | A produces output that B consumes with implicit contract | Parameter/return type + assumptions |
| transformation | Data changes form between A and B | Follow value through type changes, encoding, serialization |
| control_influence | A's result determines whether/how B executes | Conditional checks on A's output before calling B |
| invariant_co_maintenance | A and B both maintain a shared property | Shared validation patterns, coordinated assertions |
| lifecycle | A and B participate in the same acquire/use/release cycle | Resource pattern detection |

## Sources

### Fault localization and bug clustering
- Jones & Harrold 2005, "Empirical Evaluation of Tarantula" — IEEE TSE
- Abreu et al. 2007, "On the Accuracy of Spectrum-based Fault Localization" (Ochiai)
- Nagappan & Ball 2005, "Use of Relative Code Churn Measures" — ICSE
- Hassan 2009, "Predicting Faults Using Complexity of Code Changes"
- Rahman & Devanbu 2013, "How, and Why, Process Metrics Are Better"
- Cataldo et al. 2009, "Software Dependencies and Their Impact on Failures"
- Yau & Collofello 1980, "Ripple effect analysis"
- Engler et al. 2001, "Bugs as Deviant Behavior" — SOSP

### Program analysis
- Weiser 1981, "Program Slicing" — IEEE TSE
- Rapps & Weyuker 1985, "Selecting Test Data Using Data Flow Information"
- Harrold & Rothermel 1994, OO data flow analysis
- DeMillo et al. 1996, "Critical Slicing for Software Fault Localization"
- Ball & Larus 1996, "Efficient Path Profiling" — MICRO

### Multi-layer graph analysis
- Interdonato et al. 2020, "Community detection in multilayer networks" — DMKD
- Magnani et al. 2021, "Community Detection in Multiplex Networks" — ACM CS
- Mucha et al. 2010, "Community Structure in Multiplex Networks" — Science
- Berlingerio et al. 2011, "Dense subgraphs in multidimensional networks" — ASONAM
- Milo et al. 2002, "Network Motifs" — Science

### Bounded exploration
- Andersen et al. 2006, "Local Graph Partitioning using PageRank" — FOCS
- Clauset 2005, "Finding local community structure" — PRE
- Spielman & Teng 2013, "Local Clustering for Massive Graphs" — SICOMP

### Architecture recovery
- Tzerpos & Holt 2000, "ACDC" — WCRE
- Mancoridis et al. 1999, "Bunch" — ICSM
- Garcia et al. 2013, "ARC" — ISSTA
- Dit et al. 2013, "Feature location survey" — JSME

### Program comprehension
- Pennington 1987, "Comprehension strategies in programming"
- Von Mayrhauser & Vans 1995, "Program comprehension during maintenance"
- Brooks 1983, Top-down comprehension model

### Design pattern detection
- Tsantalis et al. 2006, "Design Pattern Detection Using Similarity Scoring" — IEEE TSE
