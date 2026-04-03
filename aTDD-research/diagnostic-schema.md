# Audit Diagnostic JSONL Schema

Schema for instrumenting spec analyst agent runs to diagnose why audit passes
miss bugs that subsequent passes find.

## Purpose

The agent emits one JSONL line per decision point during analysis. This gives
visibility into what was examined, what was checked, what was cleared, and why.
Today we only see positive findings — this schema adds the negatives.

## Schema compliance

**Every field shown in the event definitions below is REQUIRED unless explicitly
marked as OPTIONAL. Omitting a required field is a schema violation.** Do not
rename fields, do not substitute synonyms (e.g., `status` for `verdict`,
`construct_id` for `construct`), do not add fields not listed here.

Field names are exact strings. Use them verbatim:
- The field is called `construct`, not `construct_id`, `name`, or `id`
- The field is called `verdict`, not `status` or `result`
- The event is called `skip`, not `construct_skip`

**Construct naming convention:** Every `construct` field value uses the format
`ConstructName.methodName:start_line` where `start_line` is the line number of
the method/class/record definition in the source file. Examples:
- `CompressionMap.deserialize:150`
- `DeflateCodec.compress:57`
- `TrieSSTableReader.Footer:459`
- `CompressionCodec.deflate:87` (no-arg overload)
- `CompressionCodec.deflate:98` (int overload)

The line number removes all ambiguity for overloaded methods. The name part is
human-readable context; the line number is the matching key. Use the line where
the method signature appears (the `public`/`private`/`static` declaration line).

## Execution modes

- **Solo (Mode A):** Single agent writes all events to one JSONL file.
- **Parent (Mode B):** Orchestrator writes scope, clustering, dispatch, and
  cross-construct events. Subagents do per-construct analysis.
- **Subagent (Mode C):** Writes per-construct analysis for its assigned cluster.

All events include `run_id` for cross-file correlation. Mode B/C events include
`cluster_id`. Each agent maintains its own `seq` counter.

## Event types

### baseline

Emitted once at the start. Records whether the project verification passed.

**REQUIRED fields:** `event`, `seq`, `run_id`, `status`, `details`

```json
{
  "event": "baseline",
  "seq": 1,
  "run_id": "f7-diag-001",
  "status": "pass",
  "details": "gradlew check passed, all tests green"
}
```

### scope_inventory

Emitted once per source file after reading it. Lists every construct found.

**REQUIRED fields:** `event`, `seq`, `file`, `line_count`, `constructs`, `construct_count`

The `constructs` array contains strings in `Name:line` format.

```json
{
  "event": "scope_inventory",
  "seq": 1,
  "file": "CompressionMap.java",
  "line_count": 219,
  "constructs": [
    "CompressionMap:30",
    "CompressionMap.Entry:43",
    "CompressionMap.Entry.<compact_constructor>:44",
    "CompressionMap.serialize:121",
    "CompressionMap.deserialize:150"
  ],
  "construct_count": 5
}
```

**Diagnoses:** F1 (incomplete construct discovery)

### context_loaded

Emitted once per external context source loaded (KB entry, project rule,
existing test file). Records what specific checks were derived from it.

**REQUIRED fields:** `event`, `seq`, `source`, `entry`, `derived_checks`

```json
{
  "event": "context_loaded",
  "seq": 2,
  "source": "kb",
  "entry": "BOUNDS-CHECK-OVERFLOW",
  "derived_checks": [
    "offset+length overflow in bounds checks",
    "subtraction form vs addition form"
  ]
}
```

Sources: `kb`, `project_rule`, `adr`, `existing_test`

**Diagnoses:** F5 (KB/rules as vibes)

### construct_begin

Emitted when starting analysis of a construct. Declares examination order
and cumulative findings count at that point.

**REQUIRED fields:** `event`, `seq`, `construct`, `file`, `lines`,
`examination_order`, `cumulative_findings`

```json
{
  "event": "construct_begin",
  "seq": 10,
  "construct": "CompressionMap.deserialize:150",
  "file": "CompressionMap.java",
  "lines": "150-186",
  "examination_order": 1,
  "cumulative_findings": 0
}
```

**Diagnoses:** F6 (attention decay), F7 (satisficing), F8 (order bias)

### check

Individual pattern check against a construct. EVERY check emits this event,
including clearances (verdict=no_issue). The reasoning field must explain
WHY something is or isn't an issue — not just assert that it is/isn't.

**REQUIRED fields:** `event`, `seq`, `construct`, `lens`, `level`, `pattern`,
`verdict`, `confidence`, `reasoning`

**OPTIONAL fields:** `lines`, `cross_ref`

```json
{
  "event": "check",
  "seq": 11,
  "construct": "CompressionMap.deserialize:150",
  "lens": "B",
  "level": 1,
  "pattern": "integer-overflow-in-arithmetic",
  "verdict": "issue",
  "confidence": "high",
  "reasoning": "blockCount * ENTRY_SIZE on line 158 uses int arithmetic...",
  "lines": "158-160",
  "cross_ref": null
}
```

Valid lenses: `A`, `B`
Valid levels (Lens B only): `1`, `2`, `3`, `4`
Valid verdicts: `issue`, `no_issue`, `uncertain`
Valid confidence: `high`, `medium`, `low`

**Diagnoses:** F2 (incomplete patterns), F3 (shallow analysis), F8 (order bias)

### kb_check

Specific check of a KB adversarial-finding entry against a construct.
Separate from general checks to measure KB application rate independently.

**REQUIRED fields:** `event`, `seq`, `construct`, `kb_entry`, `applied`,
`verdict`, `reasoning`

**OPTIONAL fields:** `lines`

```json
{
  "event": "kb_check",
  "seq": 14,
  "construct": "CompressionMap.deserialize:150",
  "kb_entry": "BOUNDS-CHECK-OVERFLOW",
  "applied": true,
  "verdict": "issue",
  "reasoning": "Line 160 uses addition form matching KB pattern exactly.",
  "lines": "158-160"
}
```

**Diagnoses:** F5 (KB application rate)

### construct_end

Emitted when finishing a construct. Summary stats for decay analysis.

**REQUIRED fields:** `event`, `seq`, `construct`, `checks_performed`,
`issues_found`, `clearances`, `examination_order`, `cumulative_findings`

```json
{
  "event": "construct_end",
  "seq": 20,
  "construct": "CompressionMap.deserialize:150",
  "checks_performed": 18,
  "issues_found": 3,
  "clearances": 15,
  "examination_order": 1,
  "cumulative_findings": 3
}
```

**Diagnoses:** F6 (attention decay), F7 (satisficing)

### skip

Construct identified in scope_inventory but not deeply analyzed.
Must state reason.

**REQUIRED fields:** `event`, `seq`, `construct`, `reason`

```json
{
  "event": "skip",
  "seq": 30,
  "construct": "SSTableFormat:51",
  "reason": "constants-only class, no executable logic"
}
```

**Diagnoses:** F1 (incomplete construct discovery)

### cross_construct_trace

Data flow analysis across construct boundaries. Traces a data carrier
or shared resource from source to sink.

**REQUIRED fields:** `event`, `seq`, `data_carrier`, `source_construct`,
`sink_construct`, `trace_path`, `verdict`, `reasoning`

```json
{
  "event": "cross_construct_trace",
  "seq": 50,
  "data_carrier": "CompressionMap.Entry",
  "source_construct": "TrieSSTableWriter.flushCurrentBlock:196",
  "sink_construct": "TrieSSTableReader.readAndDecompressBlock:327",
  "trace_path": [
    "flushCurrentBlock creates Entry",
    "serialize writes to disk",
    "deserialize reconstructs Entry",
    "readAndDecompressBlock uses entry.compressedSize"
  ],
  "verdict": "issue",
  "reasoning": "No re-validation of entry fields after deserialization"
}
```

**Diagnoses:** F4 (missing cross-construct analysis)

### finding

Final finding emitted to output. References source check events by seq.

**REQUIRED fields:** `event`, `seq`, `id`, `construct`, `severity`,
`category`, `summary`, `source_checks`

```json
{
  "event": "finding",
  "seq": 60,
  "id": "F1",
  "construct": "CompressionMap.deserialize:150",
  "severity": "high",
  "category": "integer-overflow",
  "summary": "blockCount * ENTRY_SIZE overflows int",
  "source_checks": [11, 14]
}
```

**Diagnoses:** F7 (output filtering — compare check issues vs findings emitted)

### cluster_assignment (Mode B only)

Emitted by parent when clustering constructs for subagent dispatch.

**REQUIRED fields:** `event`, `seq`, `run_id`, `cluster_id`, `constructs`,
`construct_count`, `rationale`

```json
{
  "event": "cluster_assignment",
  "seq": 5,
  "run_id": "f7-diag-001",
  "cluster_id": "c1",
  "constructs": [
    "CompressionMap:30",
    "CompressionMap.Entry:43",
    "CompressionMap.serialize:121",
    "CompressionMap.deserialize:150"
  ],
  "construct_count": 4,
  "rationale": "serialization cluster — tightly coupled constructs sharing Entry data carrier"
}
```

**Diagnoses:** F1 (were all constructs assigned?), F4 (were related constructs kept together?)

### subagent_dispatch (Mode B only)

Emitted by parent when sending work to a subagent. Records exactly what
context was provided and what was omitted.

**REQUIRED fields:** `event`, `seq`, `run_id`, `cluster_id`, `subagent_file`,
`context_provided`

```json
{
  "event": "subagent_dispatch",
  "seq": 6,
  "run_id": "f7-diag-001",
  "cluster_id": "c1",
  "subagent_file": "diagnostic-f7-sub1.jsonl",
  "context_provided": {
    "files": ["CompressionMap.java", "SSTableFormat.java"],
    "kb_entries": ["BOUNDS-CHECK-OVERFLOW", "INTEGER-OVERFLOW-IN-SIZE-CALC"],
    "project_rules": ["constrained-memory-model"],
    "dependencies_provided": ["TrieSSTableWriter.flushCurrentBlock (creates Entry)"],
    "dependencies_omitted": ["TrieSSTableReader.readFooter (not directly related)"]
  }
}
```

**Diagnoses:** Orchestration failures — did the parent withhold context a subagent needed?

### subagent_result (Mode B only)

Emitted by parent after collecting a subagent's output.

**REQUIRED fields:** `event`, `seq`, `run_id`, `cluster_id`, `subagent_file`,
`findings_returned`, `constructs_examined`, `constructs_skipped`

```json
{
  "event": "subagent_result",
  "seq": 20,
  "run_id": "f7-diag-001",
  "cluster_id": "c1",
  "subagent_file": "diagnostic-f7-sub1.jsonl",
  "findings_returned": 3,
  "constructs_examined": 4,
  "constructs_skipped": 0
}
```

### agent_start (Mode C only)

First event emitted by a subagent, identifying itself.

**REQUIRED fields:** `event`, `seq`, `run_id`, `cluster_id`, `agent_type`,
`output_file`

```json
{
  "event": "agent_start",
  "seq": 1,
  "run_id": "f7-diag-001",
  "cluster_id": "c1",
  "agent_type": "subagent",
  "output_file": "diagnostic-f7-sub1.jsonl"
}
```

### context_received (Mode C only)

Emitted by subagent documenting what the parent provided.

**REQUIRED fields:** `event`, `seq`, `run_id`, `cluster_id`,
`constructs_assigned`, `files_provided`, `kb_entries_provided`,
`dependency_summaries_provided`, `master_checklist_patterns`

```json
{
  "event": "context_received",
  "seq": 2,
  "run_id": "f7-diag-001",
  "cluster_id": "c1",
  "constructs_assigned": ["CompressionMap:30", "CompressionMap.Entry:43"],
  "files_provided": ["CompressionMap.java", "SSTableFormat.java"],
  "kb_entries_provided": ["BOUNDS-CHECK-OVERFLOW"],
  "dependency_summaries_provided": ["TrieSSTableWriter.flushCurrentBlock"],
  "master_checklist_patterns": 25
}
```

**Diagnoses:** Cross-reference with subagent_dispatch to verify parent/subagent agreement.

## Failure mode → analysis mapping

| Failure | Key query | Data needed |
|---------|-----------|-------------|
| F1: Incomplete constructs | scope_inventory constructs vs ground truth | scope_inventory, skip |
| F2: Incomplete patterns | checks per construct vs expected pattern count | check, construct_end |
| F3: Shallow analysis | reasoning depth on false negatives | check (verdict=no_issue on real bugs) |
| F4: Missing cross-construct | cross_construct_trace count vs data carrier count | cross_construct_trace |
| F5: KB as vibes | kb_check count vs (KB entries x constructs) | context_loaded, kb_check |
| F6: Attention decay | checks per construct by examination_order | construct_begin, construct_end |
| F7: Satisficing | checks per construct by cumulative_findings | construct_begin, construct_end |
| F8: Order bias | pattern distribution skew, first-finding anchoring | check, finding |
