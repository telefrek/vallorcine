# Diagnostic Audit — block-compression

You are running an instrumented spec analysis audit. Your primary job is the
same as a normal audit — find bugs in the block-compression feature. But this
run has a second, equally important job: **emit structured diagnostic logs**
that record every decision you make during analysis.

The diagnostic data matters as much as the findings. We are studying why audit
passes miss bugs, and your logs are the raw data for that study.

---

## Execution modes

This prompt supports three execution modes. Choose based on how you are running:

### Mode A: Solo (no subagents)

You do everything yourself — scope, analysis, cross-construct, findings.
Write all events to a single JSONL file.

### Mode B: Parent orchestrator (with subagents)

You handle scope loading, clustering, subagent dispatch, result collection,
and cross-construct analysis. Subagents handle per-construct analysis within
their assigned clusters.

### Mode C: Subagent

You were dispatched by a parent orchestrator with a specific cluster of
constructs and context. You do per-construct analysis only on your assigned
cluster and write to your own JSONL file.

**Determine your mode before starting.** If you plan to use subagents for
parallel analysis, you are Mode B. If you were given a cluster assignment
and a subagent output file, you are Mode C. Otherwise, you are Mode A.

---

## Output files

### Mode A (solo)

Write all events to: `/tmp/vallorcine/diagnostic-f7.jsonl`

### Mode B (parent)

Write orchestration events to: `/tmp/vallorcine/diagnostic-f7-parent.jsonl`

Each subagent writes to: `/tmp/vallorcine/diagnostic-f7-sub<N>.jsonl`
(where N = cluster number, starting at 1)

### Mode C (subagent)

Write to the file assigned by the parent (e.g., `/tmp/vallorcine/diagnostic-f7-sub1.jsonl`)

### Write protocol (all modes)

Create the file at the start. Append one JSON line per event. Do NOT buffer
events in memory and write them at the end — write each event IMMEDIATELY
after the decision it records. If the session crashes mid-analysis, we need
whatever events were written up to that point.

Use the Bash tool to append lines:
```bash
echo '{"event":"...","seq":N,...}' >> /tmp/vallorcine/diagnostic-f7-<suffix>.jsonl
```

Maintain a running `seq` counter starting at 1. Every event gets the next seq.
Each agent (parent and each subagent) has its own independent seq counter.

All events include a `run_id` field set to `"f7-diag-001"` so the analysis
script can correlate events across files.

---

## Phase 0 — Establish baseline (Mode A and B only)

Run the project's verification command to confirm all tests pass:
```bash
./gradlew check
```

If anything fails, STOP. Report failures and do not proceed.

Emit:
```jsonl
{"event":"baseline","seq":1,"run_id":"f7-diag-001","status":"pass|fail","details":"..."}
```

---

## Phase 1 — Load scope and context (Mode A and B)

### Step 1.1 — Read scope

Read `.feature/block-compression/atdd-scope.md` to get the file list.

### Step 1.2 — Read each source file and emit construct inventory

For EACH source file in scope, read the file, then IMMEDIATELY emit a
`scope_inventory` event listing EVERY construct in that file:

```jsonl
{"event":"scope_inventory","seq":N,"run_id":"f7-diag-001","file":"<filename>","line_count":NNN,"constructs":["..."],"construct_count":N}
```

**What counts as a construct:**
- Every top-level class, interface, record, or enum
- Every inner/nested class, record, or enum
- Every static factory method
- Every public or package-private method longer than 5 lines
- Every constructor with validation logic
- Record compact constructors (separate from the record itself)

Do NOT start analyzing yet. Just inventory. Be exhaustive — a construct you
don't list here will never be analyzed.

### Step 1.3 — Load external context

Read each of these and emit a `context_loaded` event:

1. **KB entries:** Read `.kb/CLAUDE.md`, find adversarial-finding entries
   relevant to compression, serialization, I/O, concurrency. For EACH entry
   you read, emit:
   ```jsonl
   {"event":"context_loaded","seq":N,"run_id":"f7-diag-001","source":"kb","entry":"<ENTRY-NAME>","derived_checks":["specific check 1","specific check 2"]}
   ```
   The `derived_checks` field must contain SPECIFIC things to check, not the
   general category. "offset+length overflow in bounds check methods" not
   "bounds checking."

2. **Project rules:** Read `.claude/rules/` files. Emit one event per rule
   file with derived checks.

3. **ADRs:** Read `.decisions/` entries referenced in the work plan. Emit
   one event per ADR.

4. **Existing tests:** Read each test file listed in atdd-scope.md. Emit
   one event per test file summarizing what IS covered (so you know what
   NOT to duplicate).

### Step 1.4 — Build the master checklist

After loading all context, assemble the full checklist by combining:

**Lens A patterns (6):**
1. boundary-values (empty, zero, max, single element)
2. null-handling (constructor args, method params, stored fields, returns)
3. error-exhaustiveness (invalid combos, inverted ranges, type mismatches)
4. composite-atomicity (if step A succeeds but B fails, what state?)
5. defensive-copying (mutable inputs crossing trust boundaries)
6. equality-semantics (identity vs content for keys, especially byte[])

**Lens B Level 1 patterns (10):**
1. array-as-map-key (identity equality trap)
2. mutable-reference-storage (arrays/collections stored without copy)
3. float-double-encoding (sign-bit, NaN, precision)
4. non-atomic-mutation (check-then-act, delete-then-insert)
5. incomplete-sealed-coverage (switch/instanceof missing subtypes)
6. silent-truncation (Math.min instead of fail-fast)
7. null-in-predicate (not-equals with null fields)
8. resource-lifecycle (double-close, use-after-close)
9. deferred-validation (should happen at construction, deferred to use)
10. integer-overflow-in-arithmetic (multiplication, addition exceeding int range)

**Lens B Level 2 patterns (3):**
1. caller-validation (trust boundary enforcement)
2. fail-fast-violation (out-of-range accepted instead of rejected at entry)
3. semantically-wrong-valid-input (NaN, negative capacity, inverted ranges)

**Lens B Level 3 patterns (3):**
1. mutable-state-exposure (returned references to internal state)
2. modifiable-collection-return (consumers can corrupt internals)
3. unexpected-return-state (null, empty, partial when caller doesn't expect)

**Lens B Level 4 patterns (3):**
1. carrier-invariant-enforcement (null fields, negative counts at construction)
2. mutable-field-equality (arrays in records — identity vs content)
3. immutability-leak (state leaking through accessors on carriers)

**KB-derived patterns:** (from Step 1.3 — add each derived_check here)

**Project-rule-derived patterns:** (from Step 1.3)

This gives you approximately 25+ base patterns plus KB/rule additions. Every
one of these gets checked against every non-skipped construct. No exceptions.

---

## Phase 1.5 — Clustering and dispatch (Mode B only)

If you are the parent orchestrator using subagents, this phase replaces
going directly to Phase 2.

### Step 1.5.1 — Cluster constructs

Group constructs into clusters of ≤8 constructs each. Cluster by dependency
proximity — constructs that call each other or share data carriers should be
in the same cluster.

For each cluster, emit:
```jsonl
{"event":"cluster_assignment","seq":N,"run_id":"f7-diag-001","cluster_id":"c1","constructs":["CompressionMap","CompressionMap.Entry","CompressionMap.serialize","CompressionMap.deserialize"],"construct_count":4,"rationale":"serialization cluster — tightly coupled constructs sharing Entry data carrier"}
```

### Step 1.5.2 — Decide what context each subagent needs

For EACH cluster, determine:
- Which source files the subagent needs to read (the files containing its constructs)
- Which dependency files it needs (signatures of constructs in OTHER clusters that
  its constructs call or are called by)
- Which KB entries are relevant to its constructs
- Which project rules apply
- Which test files provide coverage context

This is the critical orchestration decision. A subagent that doesn't receive
a dependency file CANNOT analyze cross-construct data flow involving that
dependency. Log this decision explicitly.

### Step 1.5.3 — Dispatch subagents

For EACH cluster, dispatch a subagent and emit:
```jsonl
{"event":"subagent_dispatch","seq":N,"run_id":"f7-diag-001","cluster_id":"c1","subagent_file":"diagnostic-f7-sub1.jsonl","context_provided":{"files":["CompressionMap.java","SSTableFormat.java"],"kb_entries":["BOUNDS-CHECK-OVERFLOW","INTEGER-OVERFLOW-IN-SIZE-CALC"],"project_rules":["constrained-memory-model"],"dependencies_provided":["TrieSSTableWriter.flushCurrentBlock (creates Entry)","TrieSSTableReader.readAndDecompressBlock (consumes Entry)"],"dependencies_omitted":["TrieSSTableReader.readFooter (not directly related to this cluster)"]}}
```

**The `dependencies_omitted` field is mandatory.** List every construct from
OTHER clusters that you chose NOT to provide to this subagent, and why. This
is the data we need to diagnose orchestration-caused misses.

When dispatching the subagent, include in its prompt:
1. Its cluster assignment (which constructs to analyze)
2. The master checklist from Step 1.4
3. Instruction to operate in **Mode C**
4. Its output file path
5. The run_id and cluster_id
6. The context you're providing (files, KB entries, dependency summaries)

### Step 1.5.4 — Collect subagent results

After each subagent completes, emit:
```jsonl
{"event":"subagent_result","seq":N,"run_id":"f7-diag-001","cluster_id":"c1","subagent_file":"diagnostic-f7-sub1.jsonl","findings_returned":3,"constructs_examined":4,"constructs_skipped":0}
```

---

## Phase 1C — Subagent startup (Mode C only)

If you are a subagent, start here.

### Step 1C.1 — Emit agent_start

```jsonl
{"event":"agent_start","seq":1,"run_id":"f7-diag-001","cluster_id":"c1","agent_type":"subagent","output_file":"diagnostic-f7-sub1.jsonl"}
```

### Step 1C.2 — Log received context

Emit a `context_received` event documenting exactly what the parent gave you:
```jsonl
{"event":"context_received","seq":2,"run_id":"f7-diag-001","cluster_id":"c1","constructs_assigned":["CompressionMap","CompressionMap.Entry","CompressionMap.serialize","CompressionMap.deserialize"],"files_provided":["CompressionMap.java","SSTableFormat.java"],"kb_entries_provided":["BOUNDS-CHECK-OVERFLOW"],"dependency_summaries_provided":["TrieSSTableWriter.flushCurrentBlock","TrieSSTableReader.readAndDecompressBlock"],"master_checklist_patterns":25}
```

### Step 1C.3 — Read your assigned files

Read the source files assigned to you. Emit `scope_inventory` for each,
but ONLY for the constructs in your cluster assignment. Note any constructs
you see in the files that are NOT in your assignment — you should still be
aware of them for cross-reference purposes but they are not your analysis
targets.

```jsonl
{"event":"scope_inventory","seq":3,"run_id":"f7-diag-001","cluster_id":"c1","file":"CompressionMap.java","line_count":219,"constructs":["CompressionMap","CompressionMap.Entry","CompressionMap.Entry.<compact_constructor>","CompressionMap.serialize","CompressionMap.deserialize"],"construct_count":5,"out_of_scope_constructs":["CompressionMap.readInt","CompressionMap.readLong","CompressionMap.writeInt","CompressionMap.writeLong"]}
```

Then proceed to Phase 2.

---

## Phase 2 — Per-construct analysis (all modes)

Process constructs ONE AT A TIME. For each construct:

### Step 2.1 — Emit construct_begin

```jsonl
{"event":"construct_begin","seq":N,"run_id":"f7-diag-001","cluster_id":"c1|null","construct":"<name>","file":"<file>","lines":"<start>-<end>","examination_order":N,"cumulative_findings":N}
```

`examination_order` starts at 1 and increments for each construct (per-agent,
not global). `cumulative_findings` is the total issues found so far across
all prior constructs in this agent's scope.

Mode C subagents include their `cluster_id`. Mode A sets `cluster_id` to null.

### Step 2.2 — Check EVERY pattern

Walk the ENTIRE master checklist from Phase 1 (or the checklist provided by
the parent for Mode C). For EACH pattern, emit a `check` event:

```jsonl
{"event":"check","seq":N,"run_id":"f7-diag-001","cluster_id":"c1|null","construct":"<name>","lens":"A|B","level":null|1|2|3|4,"pattern":"<pattern-name>","verdict":"issue|no_issue|uncertain","confidence":"high|medium|low","reasoning":"<WHY this is or isn't an issue — not just THAT it is or isn't>","lines":"<relevant lines>","cross_ref":null|"<other construct>"}
```

**CRITICAL RULES FOR CHECK EVENTS:**

1. **Every pattern gets a check event.** If a pattern doesn't apply to this
   construct type (e.g., "array-as-map-key" for a constants class), emit it
   with verdict "no_issue" and reasoning explaining why it's not applicable.

2. **The reasoning field must contain a safety argument, not just an assertion.**
   BAD: "Bounds check exists on line 51"
   GOOD: "Bounds check on line 51 uses `remaining - needed` (subtraction form) which cannot integer-overflow because remaining is derived from data.length (always >= 0) and needed is validated positive on line 48"

3. **If you cannot articulate why something is safe, the verdict is "uncertain",
   not "no_issue".** Uncertain findings become investigation items.

4. **Do not skip a pattern because a previous construct had the same verdict.**
   Each construct is checked independently. CompressionMap.serialize and
   CompressionMap.deserialize may have the same pattern but different code —
   check both.

5. **For Level 2 (inputs), actually identify the callers.** Name them. If you
   haven't read the caller's code, say so in the reasoning and set confidence
   to "low". If you are a subagent and the caller is outside your cluster,
   note this: "caller TrieSSTableWriter.flushCurrentBlock is outside my
   cluster — relying on parent-provided dependency summary."

6. **For Level 4 (data carriers), trace the carrier to its consumers.** If a
   record is created in one construct and consumed in another, your reasoning
   must reference both. If the consumer is outside your cluster (Mode C),
   note the limitation.

### Step 2.3 — Check KB entries

For EACH KB adversarial-finding entry in your checklist, emit a `kb_check`:

```jsonl
{"event":"kb_check","seq":N,"run_id":"f7-diag-001","cluster_id":"c1|null","construct":"<name>","kb_entry":"<KB-ENTRY-NAME>","applied":true|false,"verdict":"issue|no_issue","reasoning":"<why this KB pattern does or doesn't apply here>","lines":"<relevant lines>"}
```

`applied=false` means the KB pattern's preconditions aren't present in this
construct (e.g., checking BOUNDS-CHECK-OVERFLOW against a method that does
no bounds checking). Still emit the event — we need to see the decision.

### Step 2.4 — Skip decision (if applicable)

If a construct has no executable logic (e.g., constants-only class, empty
module-info), you MAY skip the full checklist. But you MUST emit:

```jsonl
{"event":"skip","seq":N,"run_id":"f7-diag-001","cluster_id":"c1|null","construct":"<name>","reason":"<specific reason>"}
```

A skip is a declaration that this construct cannot contain bugs. If you're
wrong, the skip event will show us why.

### Step 2.5 — Emit construct_end

```jsonl
{"event":"construct_end","seq":N,"run_id":"f7-diag-001","cluster_id":"c1|null","construct":"<name>","checks_performed":N,"issues_found":N,"clearances":N,"examination_order":N,"cumulative_findings":N}
```

`cumulative_findings` here includes any issues found in THIS construct.
`checks_performed` = issues_found + clearances + uncertain.

---

## Phase 3 — Cross-construct analysis (Mode A and B only)

After ALL constructs have been analyzed (directly or via subagents), do a
cross-cutting pass. Mode C subagents skip this phase — they report findings
and the parent does cross-construct analysis with full visibility.

### Step 3.1 — Identify data carriers

List every record, DTO, or shared mutable type that flows between constructs.
For block-compression, this likely includes at minimum:
- `CompressionMap.Entry` (created by writer, serialized, deserialized, used by reader)
- `Footer` (read from disk, used to locate other structures)
- `byte[]` blocks (compressed by writer, decompressed by reader)
- `Map<Byte, CompressionCodec>` (built from varargs, used for dispatch)

### Step 3.2 — Trace each carrier

For each data carrier, trace it from creation to consumption. Emit:

```jsonl
{"event":"cross_construct_trace","seq":N,"run_id":"f7-diag-001","data_carrier":"<type>","source_construct":"<creator>","sink_construct":"<consumer>","trace_path":["step 1","step 2","..."],"verdict":"issue|no_issue","reasoning":"<what could go wrong at the boundary>","crosses_cluster_boundary":true|false}
```

The `crosses_cluster_boundary` field (Mode B only) indicates whether this
trace spans constructs that were in different subagent clusters. If true,
no subagent could have found this issue independently — it's inherently a
parent-level finding.

Ask specifically:
- Is the carrier re-validated at each consumption point, or does the consumer
  trust the producer?
- Could the carrier be in a state the consumer doesn't handle? (corrupt disk
  data, partial writes, concurrent modification)
- Are invariants enforced at creation AND checked at consumption, or only one?

---

## Phase 4 — Emit findings (all modes)

For each check or trace with verdict="issue" or verdict="uncertain", emit a
finding:

```jsonl
{"event":"finding","seq":N,"run_id":"f7-diag-001","cluster_id":"c1|null","id":"F<N>","construct":"<name>","severity":"high|medium|low","category":"<bug-category>","summary":"<one-line description>","source_checks":[<seq numbers of the check events that identified this>]}
```

**Do not filter findings by confidence.** If a check said "issue" or
"uncertain", it becomes a finding. The analysis script will handle
prioritization — your job is completeness.

Mode C subagents: your finding IDs should be prefixed with your cluster
(e.g., "c1-F1", "c1-F2") to avoid collisions with other subagents.

---

## Phase 5 — Write breaker prompt (Mode A and B only)

Write `.feature/block-compression/breaker-prompt.md` with all findings
(including those from subagents) formatted as attack vectors for the Breaker
agent. Standard format — group by category, include specific suspicions and
target lines.

---

## Reminders

- **Write diagnostic events IMMEDIATELY.** Do not batch them.
- **Do not abbreviate or summarize check events.** Each one is a data point.
- **Do not skip patterns you think are "obviously not applicable."** Emit the
  check with verdict=no_issue and say why. We need the negative data.
- **Assume there are bugs you haven't found.** After every 3 constructs,
  re-read this assumption. You have found N so far. Assume there are still
  at least 5 more. Do not reduce effort because you have "enough" findings.
- **The diagnostic JSONL is the primary deliverable of this run.** The breaker
  prompt is secondary. If you must choose between thoroughness of logging and
  speed of completion, choose thoroughness.
- **Subagents: log your limitations.** If you can't fully analyze a cross-construct
  relationship because the other construct is outside your cluster, say so in
  your check reasoning. This is not a failure — it's data about what the
  parent's clustering decision cost you.
