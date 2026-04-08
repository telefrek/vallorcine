#!/usr/bin/env python3
"""Analyze audit diagnostic JSONL logs to diagnose why audit passes miss bugs.

Runs 8 failure-mode analyses against diagnostic JSONL files produced by an
instrumented spec analyst run. Supports both single-file (solo mode) and
multi-file (parent + subagent) runs. Each analysis is independent.

Usage:
    # Single file (solo mode):
    python3 analyze-diagnostic.py /path/to/diagnostic.jsonl

    # Multi-file (parent + subagents) — pass the directory:
    python3 analyze-diagnostic.py --run-dir /tmp/vallorcine/
    # Reads all diagnostic-f7-*.jsonl files in the directory

    # Run specific analysis:
    python3 analyze-diagnostic.py /path/to/diagnostic.jsonl --analysis coverage
    python3 analyze-diagnostic.py /path/to/diagnostic.jsonl --analysis decay

    # With known bugs for false-negative detection (F3):
    python3 analyze-diagnostic.py /path/to/diagnostic.jsonl --known-bugs bugs.json

    # With ground-truth construct list for coverage analysis (F1):
    python3 analyze-diagnostic.py /path/to/diagnostic.jsonl --ground-truth constructs.json

Available analyses:
    coverage      - F1: Construct coverage vs ground truth
    patterns      - F2: Pattern coverage per construct
    depth         - F3: Reasoning depth analysis + false negatives
    crosscut      - F4: Cross-construct trace coverage
    kb            - F5: KB entry application rate
    decay         - F6: Attention decay by examination order
    satisficing   - F7: Satisficing by cumulative findings
    bias          - F8: Pattern distribution and order bias
    funnel        - Finding funnel: checks -> issues -> findings
    orchestration - Subagent orchestration analysis (multi-file only)
    all           - Run all analyses (default)
"""

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path


# ---------------------------------------------------------------------------
# Event normalization
# ---------------------------------------------------------------------------

def normalize_event(event):
    """Normalize field names to match the canonical schema.

    Handles known drift patterns observed in subagent output:
    - construct_id / name -> construct
    - status -> verdict
    - construct_skip -> skip (event type)
    """
    # Normalize event type
    event_type = event.get("event", "")
    if event_type == "construct_skip":
        event["event"] = "skip"

    # Normalize construct field: try construct, then name, then construct_id
    if "construct" not in event:
        if "name" in event:
            event["construct"] = event["name"]
        elif "construct_id" in event:
            event["construct"] = str(event["construct_id"])

    # Normalize verdict field: status -> verdict
    if "verdict" not in event and "status" in event:
        event["verdict"] = event["status"]

    # Normalize examination_order from construct_begin events
    if event.get("event") == "construct_begin":
        if "examination_order" not in event and "order" in event:
            event["examination_order"] = event["order"]

    return event


def extract_line_from_construct(construct_str):
    """Extract line number from a construct string like 'Foo.bar:123'.

    Returns (name_part, line_number) or (construct_str, None) if no line.
    """
    if not construct_str or not isinstance(construct_str, str):
        return str(construct_str) if construct_str else "", None

    # Match name:line pattern
    m = re.match(r'^(.+):(\d+)$', construct_str)
    if m:
        return m.group(1), int(m.group(2))
    return construct_str, None


def build_construct_key(construct_str):
    """Build a matching key from a construct string.

    If the string contains ':line', returns (name, line).
    Otherwise returns (name, None) for name-only matching.
    """
    return extract_line_from_construct(construct_str)


# ---------------------------------------------------------------------------
# Ground truth and known bugs loading
# ---------------------------------------------------------------------------

def load_ground_truth(path):
    """Load ground truth from JSON file.

    Supports both formats:
    - Old: simple string array ["Foo", "Bar"]
    - New: {"constructs": [{"file": "...", "construct": "...", "line": N}]}

    Returns a list of dicts with file, construct, line keys.
    """
    with open(path) as f:
        data = json.load(f)

    if isinstance(data, list):
        # Old format: simple string array
        return [{"construct": c, "file": None, "line": None} for c in data]

    if isinstance(data, dict) and "constructs" in data:
        return data["constructs"]

    return []


def load_known_bugs(path):
    """Load known bugs from JSON file.

    Returns list of dicts with file, construct, line, pattern, description.
    """
    with open(path) as f:
        return json.load(f)


def match_construct_to_ground_truth(construct_str, ground_truth):
    """Match a construct string from diagnostic output to a ground truth entry.

    Matching priority:
    1. Line number match (if both have line numbers and same file)
    2. Exact name match
    3. Name prefix match (agent name starts with gt name or vice versa)

    Returns the matched GT entry or None.
    """
    name, line = extract_line_from_construct(construct_str)

    # Try line-number match first (most reliable)
    if line is not None:
        for gt in ground_truth:
            if gt.get("line") == line:
                # If GT has a file, we could check it too, but line is
                # already very discriminating within a feature scope
                return gt

    # Exact name match
    for gt in ground_truth:
        gt_name = gt.get("construct", "")
        if name == gt_name:
            return gt

    # Prefix match: handle agent using longer names
    # e.g., GT="DeflateCodec.compress" matches "DeflateCodec.compress(byte[],int,int)"
    for gt in ground_truth:
        gt_name = gt.get("construct", "")
        if name.startswith(gt_name) or gt_name.startswith(name):
            return gt

    return None


def match_bug_to_checks(bug, checks):
    """Match a known bug to check events.

    Uses line number matching when available, falls back to name matching.
    Returns list of matching check events.
    """
    bug_line = bug.get("line")
    bug_construct = bug.get("construct", "")

    matching = []
    for chk in checks:
        chk_construct = chk.get("construct", "")
        chk_name, chk_line = extract_line_from_construct(chk_construct)

        # Line match (strongest signal)
        if bug_line is not None and chk_line is not None:
            if bug_line == chk_line:
                matching.append(chk)
                continue

        # Name match (prefix-based for overload tolerance)
        if _names_match(chk_name, bug_construct):
            matching.append(chk)

    return matching


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def stream_events(path):
    """Yield parsed and normalized events from a JSONL file, line by line."""
    with open(path) as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("//") or line.startswith("#"):
                continue
            try:
                event = json.loads(line)
                yield normalize_event(event)
            except json.JSONDecodeError as e:
                print(f"  WARN: skipping malformed line {line_num} in "
                      f"{path}: {e}", file=sys.stderr)


def collect_events(path):
    """Single pass: bucket events by type from one JSONL file.

    Returns dict of {event_type: [events]}. Each event gets a
    _source_file field added for multi-file attribution.
    """
    buckets = defaultdict(list)
    source = Path(path).name
    for event in stream_events(path):
        event_type = event.get("event")
        if event_type:
            event["_source_file"] = source
            buckets[event_type].append(event)
    return buckets


def collect_events_multi(paths):
    """Collect events from multiple JSONL files into unified buckets.

    Also returns per-file buckets for per-agent analysis.
    """
    unified = defaultdict(list)
    per_file = {}

    for path in paths:
        file_buckets = collect_events(path)
        per_file[Path(path).name] = file_buckets
        for event_type, events in file_buckets.items():
            unified[event_type].extend(events)

    return unified, per_file


def find_diagnostic_files(run_dir, prefix="diagnostic-f7"):
    """Find all diagnostic JSONL files in a directory."""
    run_path = Path(run_dir)
    files = sorted(run_path.glob(f"{prefix}*.jsonl"))
    if not files:
        # Try without prefix
        files = sorted(run_path.glob("diagnostic-*.jsonl"))
    return [str(f) for f in files]


# ---------------------------------------------------------------------------
# F1: Construct coverage
# ---------------------------------------------------------------------------

def _names_match(agent_name, gt_name):
    """Check if an agent construct name matches a ground truth name.

    Handles:
    - Exact match
    - Agent uses signature: "DeflateCodec.compress(byte[],int,int)" matches "DeflateCodec.compress"
    - Agent uses short name: "compress" matches "DeflateCodec.compress"
    - Agent uses qualified: "TrieSSTableReader.readAndDecompressBlock" matches same
    """
    if agent_name == gt_name:
        return True
    # Agent name starts with GT name + delimiter
    if (agent_name.startswith(gt_name + "(")
            or agent_name.startswith(gt_name + ":")):
        return True
    # GT name starts with agent name + delimiter
    if (gt_name.startswith(agent_name + "(")
            or gt_name.startswith(agent_name + ":")):
        return True
    # Agent uses unqualified name: "append" or "append(Entry)"
    # GT uses qualified: "TrieSSTableWriter.append"
    if "." in gt_name:
        gt_method = gt_name.rsplit(".", 1)[1]
        if (agent_name == gt_method
                or agent_name.startswith(gt_method + "(")
                or agent_name.startswith(gt_method + ":")):
            return True
    return False


def analyze_coverage(buckets, ground_truth=None, per_file=None, **_):
    """F1: Were all constructs discovered and examined?"""
    print("\n=== F1: Construct Coverage ===\n")

    # Constructs found by agent(s) — collect both name and line info
    discovered = set()
    discovered_details = []  # list of (name, line_or_None)
    for inv in buckets.get("scope_inventory", []):
        for c in inv.get("constructs", []):
            if isinstance(c, dict):
                name = c.get("name", str(c))
            else:
                name = c
            discovered.add(name)
            n, l = extract_line_from_construct(name)
            discovered_details.append((n, l))

    # Constructs examined (had construct_begin)
    examined = set()
    examined_details = []
    for cb in buckets.get("construct_begin", []):
        c = cb.get("construct", "")
        examined.add(c)
        n, l = extract_line_from_construct(c)
        examined_details.append((n, l, c))

    # Constructs skipped
    skipped = set()
    for sk in buckets.get("skip", []):
        skipped.add(sk.get("construct", ""))

    print(f"Discovered in scope_inventory: {len(discovered)}")
    print(f"Examined (construct_begin):     {len(examined)}")
    print(f"Explicitly skipped:             {len(skipped)}")

    # Per-agent breakdown (multi-file)
    if per_file and len(per_file) > 1:
        print(f"\nPer-agent breakdown:")
        for fname, fbuckets in sorted(per_file.items()):
            agent_examined = set(cb.get("construct", "")
                                 for cb in fbuckets.get("construct_begin", []))
            agent_skipped = set(sk.get("construct", "")
                                for sk in fbuckets.get("skip", []))
            print(f"  {fname}: examined={len(agent_examined)}, "
                  f"skipped={len(agent_skipped)}")

    # Ground truth comparison using line-number matching
    if ground_truth:
        gt_matched = []
        gt_missed = []
        gt_lines = {gt.get("line"): gt for gt in ground_truth
                    if gt.get("line") is not None}
        gt_names = {gt.get("construct"): gt for gt in ground_truth}

        for gt in ground_truth:
            gt_line = gt.get("line")
            gt_name = gt.get("construct", "")
            matched = False

            # Check if any examined construct matches by line
            for ex_name, ex_line, ex_raw in examined_details:
                if gt_line is not None and ex_line is not None:
                    if gt_line == ex_line:
                        matched = True
                        break
                # Fallback: name prefix match (bidirectional)
                if _names_match(ex_name, gt_name):
                    matched = True
                    break

            # Also check discovered (scope_inventory) if not examined
            if not matched:
                for d_name, d_line in discovered_details:
                    if gt_line is not None and d_line is not None:
                        if gt_line == d_line:
                            matched = True
                            break
                    if _names_match(d_name, gt_name):
                        matched = True
                        break

            if matched:
                gt_matched.append(gt)
            else:
                gt_missed.append(gt)

        print(f"\nGround truth coverage: {len(gt_matched)}/{len(ground_truth)}"
              f" ({len(gt_matched)/len(ground_truth)*100:.0f}%)")

        # Which GT constructs were examined vs only discovered vs missed
        gt_examined = []
        gt_discovered_only = []
        for gt in gt_matched:
            gt_line = gt.get("line")
            gt_name = gt.get("construct", "")
            was_examined = False
            for ex_name, ex_line, ex_raw in examined_details:
                if gt_line is not None and ex_line is not None:
                    if gt_line == ex_line:
                        was_examined = True
                        break
                if _names_match(ex_name, gt_name):
                    was_examined = True
                    break
            if was_examined:
                gt_examined.append(gt)
            else:
                gt_discovered_only.append(gt)

        print(f"  Examined:        {len(gt_examined)}")
        print(f"  Discovered only: {len(gt_discovered_only)}")
        print(f"  Missed entirely: {len(gt_missed)}")

        if gt_missed:
            print(f"\nMISSED ground truth constructs:")
            for gt in gt_missed:
                print(f"  - {gt.get('construct', '?')}:{gt.get('line', '?')} "
                      f"({gt.get('file', '?')})")

        if gt_discovered_only:
            print(f"\nDISCOVERED but NOT EXAMINED:")
            for gt in gt_discovered_only:
                print(f"  - {gt.get('construct', '?')}:{gt.get('line', '?')} "
                      f"({gt.get('file', '?')})")

    return {
        "discovered": len(discovered),
        "examined": len(examined),
        "skipped": len(skipped),
    }


# ---------------------------------------------------------------------------
# F2: Pattern coverage
# ---------------------------------------------------------------------------

def analyze_patterns(buckets, **_):
    """F2: How many patterns were checked per construct?"""
    print("\n=== F2: Pattern Coverage ===\n")

    # Collect checks per construct
    checks_per_construct = defaultdict(list)
    for chk in buckets.get("check", []):
        construct = chk.get("construct", "unknown")
        checks_per_construct[construct].append(chk)

    # Also count kb_checks
    kb_per_construct = defaultdict(list)
    for kc in buckets.get("kb_check", []):
        construct = kc.get("construct", "unknown")
        kb_per_construct[construct].append(kc)

    # Collect unique patterns seen across all constructs
    all_patterns = set()
    pattern_per_construct = defaultdict(set)
    for chk in buckets.get("check", []):
        pattern = chk.get("pattern", "unknown")
        construct = chk.get("construct", "unknown")
        all_patterns.add(pattern)
        pattern_per_construct[construct].add(pattern)

    print(f"Unique patterns checked: {len(all_patterns)}")
    print(f"Constructs with checks:  {len(checks_per_construct)}")
    print()

    # Per-construct breakdown
    print(f"{'Construct':<45} {'Checks':>6} {'KB':>4} {'Patterns':>8} "
          f"{'Issues':>6}")
    print("-" * 75)

    construct_stats = []
    for construct in sorted(checks_per_construct.keys()):
        checks = checks_per_construct[construct]
        kb_checks = kb_per_construct.get(construct, [])
        patterns = pattern_per_construct[construct]
        issues = sum(1 for c in checks if c.get("verdict") == "issue")
        print(f"{construct:<45} {len(checks):>6} {len(kb_checks):>4} "
              f"{len(patterns):>8} {issues:>6}")
        construct_stats.append({
            "construct": construct,
            "checks": len(checks),
            "kb_checks": len(kb_checks),
            "patterns": len(patterns),
            "issues": issues,
        })

    # Pattern frequency
    print(f"\nPattern frequency (how many constructs each pattern was "
          f"checked against):")
    pattern_freq = defaultdict(int)
    for chk in buckets.get("check", []):
        pattern_freq[chk.get("pattern", "unknown")] += 1

    for pattern, count in sorted(pattern_freq.items(), key=lambda x: -x[1]):
        print(f"  {pattern:<45} {count:>4}x")

    return construct_stats


# ---------------------------------------------------------------------------
# F3: Reasoning depth + false negatives
# ---------------------------------------------------------------------------

def analyze_depth(buckets, known_bugs=None, **_):
    """F3: How deep is the reasoning? Are clearances justified?"""
    print("\n=== F3: Reasoning Depth ===\n")

    checks = buckets.get("check", [])
    if not checks:
        print("No check events found.")
        return {}

    # Word count distribution
    word_counts = []
    issue_wc = []
    clearance_wc = []

    for chk in checks:
        reasoning = chk.get("reasoning", "")
        wc = len(reasoning.split())
        word_counts.append(wc)
        if chk.get("verdict") == "issue":
            issue_wc.append(wc)
        elif chk.get("verdict") == "no_issue":
            clearance_wc.append(wc)

    print(f"Total checks:     {len(checks)}")
    print(f"  Issues:         {len(issue_wc)}")
    print(f"  Clearances:     {len(clearance_wc)}")
    print(f"  Uncertain:      {len(checks) - len(issue_wc) - len(clearance_wc)}")
    print()

    if word_counts:
        avg_all = sum(word_counts) / len(word_counts)
        print(f"Reasoning word count (all):        "
              f"avg={avg_all:.0f}  min={min(word_counts)}  "
              f"max={max(word_counts)}")
    if issue_wc:
        avg_issue = sum(issue_wc) / len(issue_wc)
        print(f"Reasoning word count (issues):     "
              f"avg={avg_issue:.0f}  min={min(issue_wc)}  "
              f"max={max(issue_wc)}")
    if clearance_wc:
        avg_clear = sum(clearance_wc) / len(clearance_wc)
        print(f"Reasoning word count (clearances): "
              f"avg={avg_clear:.0f}  min={min(clearance_wc)}  "
              f"max={max(clearance_wc)}")

    # Short clearances (potential shallow analysis)
    short_threshold = 15
    short_clearances = [c for c in checks
                        if c.get("verdict") == "no_issue"
                        and len(c.get("reasoning", "").split()) < short_threshold]
    if short_clearances:
        print(f"\nShort clearances (<{short_threshold} words) — potential "
              f"shallow analysis:")
        for c in short_clearances[:20]:  # Cap output
            wc = len(c.get("reasoning", "").split())
            print(f"  {c.get('construct', '?'):<35} "
                  f"{c.get('pattern', '?'):<30} {wc:>3}w  "
                  f"\"{c.get('reasoning', '')[:80]}...\"")
        if len(short_clearances) > 20:
            print(f"  ... and {len(short_clearances) - 20} more")

    # False negative detection
    if known_bugs:
        print(f"\n--- False Negative Analysis ---")
        print(f"Known bugs provided: {len(known_bugs)}")

        found_count = 0
        f1_count = 0
        f2_count = 0
        f3_count = 0

        for bug in known_bugs:
            bug_desc = bug.get("description", "")
            bug_construct = bug.get("construct", "")
            bug_pattern = bug.get("pattern", "")
            bug_line = bug.get("line")

            # Find checks that match this bug's construct
            matching_checks = match_bug_to_checks(bug, checks)

            if not matching_checks:
                print(f"\n  BUG: {bug_desc}")
                print(f"    Construct: {bug_construct}:{bug_line}")
                print(f"    MISSED — no checks on this construct at all (F1)")
                f1_count += 1
            else:
                # Check if any check found this issue
                found = any(c.get("verdict") == "issue"
                            and bug_pattern.lower()
                            in c.get("pattern", "").lower()
                            for c in matching_checks)
                if found:
                    print(f"\n  BUG: {bug_desc}")
                    print(f"    Construct: {bug_construct}:{bug_line}")
                    print(f"    FOUND — correctly identified")
                    found_count += 1
                else:
                    # Check if there's a clearance on the relevant pattern
                    cleared = [c for c in matching_checks
                               if c.get("verdict") == "no_issue"
                               and bug_pattern.lower()
                               in c.get("pattern", "").lower()]
                    if cleared:
                        print(f"\n  BUG: {bug_desc}")
                        print(f"    Construct: {bug_construct}:{bug_line}")
                        print(f"    FALSE NEGATIVE — cleared but is a real "
                              f"bug (F3)")
                        for c in cleared:
                            print(f"    Clearance reasoning: "
                                  f"\"{c.get('reasoning', '')}\"")
                            print(f"    Source: "
                                  f"{c.get('_source_file', '?')}")
                        f3_count += 1
                    else:
                        print(f"\n  BUG: {bug_desc}")
                        print(f"    Construct: {bug_construct}:{bug_line}")
                        checks_on = len(matching_checks)
                        print(f"    PATTERN NOT CHECKED — {checks_on} "
                              f"checks on construct but pattern "
                              f"'{bug_pattern}' never checked (F2)")
                        f2_count += 1

        print(f"\n--- Bug Classification Summary ---")
        print(f"  FOUND:          {found_count}")
        print(f"  F1 (not looked): {f1_count}")
        print(f"  F2 (no pattern): {f2_count}")
        print(f"  F3 (false neg):  {f3_count}")

    return {
        "total_checks": len(checks),
        "avg_word_count": (sum(word_counts) / len(word_counts)
                           if word_counts else 0),
        "short_clearances": len(short_clearances),
    }


# ---------------------------------------------------------------------------
# F4: Cross-construct traces
# ---------------------------------------------------------------------------

def analyze_crosscut(buckets, **_):
    """F4: Were data flows across construct boundaries analyzed?"""
    print("\n=== F4: Cross-Construct Traces ===\n")

    traces = buckets.get("cross_construct_trace", [])
    print(f"Cross-construct traces emitted: {len(traces)}")

    if not traces:
        print("NO cross-construct analysis performed.")
        print("This is a strong F4 signal — agent analyzed constructs "
              "in isolation.")
        return {"traces": 0}

    # Data carriers traced
    carriers = set()
    cross_cluster = 0
    for t in traces:
        carriers.add(t.get("data_carrier", "unknown"))
        if t.get("crosses_cluster_boundary"):
            cross_cluster += 1

    print(f"Unique data carriers traced: {len(carriers)}")
    if cross_cluster:
        print(f"Traces crossing cluster boundaries: {cross_cluster}")
    print()

    for t in traces:
        verdict = t.get("verdict", "?")
        marker = ("BUG" if verdict == "issue"
                  else "OK " if verdict == "no_issue" else "???")
        xc = " [CROSS-CLUSTER]" if t.get("crosses_cluster_boundary") else ""
        print(f"  [{marker}] {t.get('data_carrier', '?')}: "
              f"{t.get('source_construct', '?')} -> "
              f"{t.get('sink_construct', '?')}{xc}")
        if t.get("reasoning"):
            print(f"         {t['reasoning'][:100]}")

    # Cross-references in regular checks
    cross_refs = [c for c in buckets.get("check", []) if c.get("cross_ref")]
    print(f"\nChecks with cross_ref to other constructs: {len(cross_refs)}")

    return {"traces": len(traces), "carriers": len(carriers),
            "cross_refs": len(cross_refs), "cross_cluster": cross_cluster}


# ---------------------------------------------------------------------------
# F5: KB application rate
# ---------------------------------------------------------------------------

def analyze_kb(buckets, **_):
    """F5: Were KB entries mechanically applied to every construct?"""
    print("\n=== F5: KB Application Rate ===\n")

    # KB entries loaded
    kb_loaded = [cl for cl in buckets.get("context_loaded", [])
                 if cl.get("source") == "kb"]
    # Also check context_received (subagent mode)
    for cr in buckets.get("context_received", []):
        for kb_name in cr.get("kb_entries_provided", []):
            if not any(kl.get("entry") == kb_name for kl in kb_loaded):
                kb_loaded.append({"entry": kb_name, "source": "kb"})

    kb_names = [cl.get("entry", "unknown") for cl in kb_loaded]

    # Constructs examined
    examined = set()
    for cb in buckets.get("construct_begin", []):
        examined.add(cb.get("construct", ""))

    # KB checks performed
    kb_checks = buckets.get("kb_check", [])

    print(f"KB entries loaded:       {len(kb_names)}")
    print(f"Constructs examined:     {len(examined)}")
    expected = len(kb_names) * len(examined)
    print(f"Expected KB checks:      {len(kb_names)} x {len(examined)} = "
          f"{expected}")
    print(f"Actual KB checks:        {len(kb_checks)}")

    if expected > 0:
        rate = len(kb_checks) / expected * 100
        print(f"Application rate:        {rate:.1f}%")
    print()

    # Matrix: KB entry x construct
    kb_matrix = defaultdict(dict)
    for kc in kb_checks:
        kb_entry = kc.get("kb_entry", "unknown")
        construct = kc.get("construct", "unknown")
        kb_matrix[kb_entry][construct] = kc.get("verdict", "?")

    if kb_names and examined:
        print(f"KB application matrix:")
        examined_list = sorted(examined)
        # Abbreviate construct names
        abbrevs = [c.split(".")[-1][:12] for c in examined_list]
        print(f"{'KB Entry':<35}", end="")
        for a in abbrevs:
            print(f" {a:>12}", end="")
        print()

        for kb_name in kb_names:
            print(f"{kb_name:<35}", end="")
            for construct in examined_list:
                verdict = kb_matrix.get(kb_name, {}).get(construct, "—")
                if verdict == "issue":
                    marker = "BUG"
                elif verdict == "no_issue":
                    marker = "ok"
                elif verdict == "—":
                    marker = "NOT CHECKED"
                else:
                    marker = verdict
                print(f" {marker:>12}", end="")
            print()

    return {"kb_loaded": len(kb_names), "kb_checks": len(kb_checks),
            "examined": len(examined)}


# ---------------------------------------------------------------------------
# F6: Attention decay
# ---------------------------------------------------------------------------

def analyze_decay(buckets, per_file=None, **_):
    """F6: Does analysis quality degrade with examination order?"""
    print("\n=== F6: Attention Decay ===\n")

    # Analyze per-agent if multi-file, otherwise unified
    agents_to_analyze = {}
    if per_file and len(per_file) > 1:
        agents_to_analyze = per_file
    else:
        agents_to_analyze = {"all": buckets}

    for agent_name, agent_buckets in sorted(agents_to_analyze.items()):
        if len(agents_to_analyze) > 1:
            print(f"--- Agent: {agent_name} ---\n")

        ends = agent_buckets.get("construct_end", [])
        if not ends:
            print("No construct_end events found.\n")
            continue

        # Build construct -> checks mapping for this agent
        agent_checks = agent_buckets.get("check", [])
        checks_by_construct = defaultdict(list)
        for chk in agent_checks:
            checks_by_construct[chk.get("construct", "")].append(chk)

        # Sort by examination order
        ends_sorted = sorted(ends,
                             key=lambda e: e.get("examination_order", 0))

        print(f"{'Order':>5} {'Construct':<40} {'Checks':>6} {'Issues':>6} "
              f"{'Clearances':>10}")
        print("-" * 75)

        checks_by_order = []
        for end in ends_sorted:
            order = end.get("examination_order", "?")
            construct = end.get("construct", "?")
            # Use checks_performed from construct_end if available,
            # otherwise count from check events
            checks_count = end.get("checks_performed", 0)
            if checks_count == 0:
                checks_count = len(checks_by_construct.get(construct, []))
            issues = end.get("issues_found", 0)
            if issues == 0:
                issues = sum(1 for c in checks_by_construct.get(construct, [])
                             if c.get("verdict") == "issue")
            clearances = end.get("clearances", 0)
            if clearances == 0:
                clearances = sum(
                    1 for c in checks_by_construct.get(construct, [])
                    if c.get("verdict") == "no_issue")
            print(f"{order:>5} {construct:<40} {checks_count:>6} "
                  f"{issues:>6} {clearances:>10}")
            checks_by_order.append(checks_count)

        # First half vs second half
        if len(checks_by_order) >= 4:
            mid = len(checks_by_order) // 2
            first_avg = sum(checks_by_order[:mid]) / mid
            second_avg = (sum(checks_by_order[mid:])
                          / (len(checks_by_order) - mid))
            ratio = second_avg / first_avg if first_avg > 0 else 0

            print(f"\nFirst-half avg checks:  {first_avg:.1f}")
            print(f"Second-half avg checks: {second_avg:.1f}")
            print(f"Ratio (second/first):   {ratio:.2f}")

            if ratio < 0.6:
                print("STRONG DECAY SIGNAL — second half gets <60% of "
                      "first half's scrutiny")
            elif ratio < 0.8:
                print("MODERATE DECAY — some falloff in later constructs")
            else:
                print("MINIMAL DECAY — relatively consistent across order")

        # Reasoning depth by order
        order_by_construct = {}
        for cb in agent_buckets.get("construct_begin", []):
            order_by_construct[cb.get("construct", "")] = \
                cb.get("examination_order", 0)

        wc_by_order = defaultdict(list)
        for chk in agent_checks:
            construct = chk.get("construct", "")
            order = order_by_construct.get(construct, -1)
            if order >= 0:
                wc = len(chk.get("reasoning", "").split())
                wc_by_order[order].append(wc)

        if wc_by_order:
            print(f"\nReasoning word count by examination order:")
            for order in sorted(wc_by_order.keys()):
                wcs = wc_by_order[order]
                avg = sum(wcs) / len(wcs) if wcs else 0
                print(f"  Order {order:>2}: avg={avg:.0f}  n={len(wcs)}")
        print()

    return {}


# ---------------------------------------------------------------------------
# F7: Satisficing
# ---------------------------------------------------------------------------

def analyze_satisficing(buckets, per_file=None, **_):
    """F7: Does the agent ease off after finding 'enough' bugs?"""
    print("\n=== F7: Satisficing ===\n")

    agents_to_analyze = {}
    if per_file and len(per_file) > 1:
        agents_to_analyze = per_file
    else:
        agents_to_analyze = {"all": buckets}

    for agent_name, agent_buckets in sorted(agents_to_analyze.items()):
        if len(agents_to_analyze) > 1:
            print(f"--- Agent: {agent_name} ---\n")

        ends = agent_buckets.get("construct_end", [])
        if not ends:
            print("No construct_end events found.\n")
            continue

        # Build construct -> checks count for fallback
        agent_checks = agent_buckets.get("check", [])
        checks_by_construct = defaultdict(int)
        for chk in agent_checks:
            checks_by_construct[chk.get("construct", "")] += 1

        begins = agent_buckets.get("construct_begin", [])
        cf_at_start = {}
        for cb in begins:
            construct = cb.get("construct", "")
            cf_at_start[construct] = cb.get("cumulative_findings", 0)

        print(f"{'CumulFindings':>13} {'Construct':<40} {'Checks':>6}")
        print("-" * 65)

        cf_to_checks = defaultdict(list)
        for end in sorted(ends, key=lambda e: cf_at_start.get(
                e.get("construct", ""), 0)):
            construct = end.get("construct", "?")
            checks = end.get("checks_performed", 0)
            if checks == 0:
                checks = checks_by_construct.get(construct, 0)
            cf = cf_at_start.get(construct, "?")
            print(f"{cf:>13} {construct:<40} {checks:>6}")
            if isinstance(cf, int):
                cf_to_checks[cf].append(checks)

        # Compare: checks when cumulative_findings < 3 vs >= 3
        low_cf = []
        high_cf = []
        threshold = 3
        for cf, check_list in cf_to_checks.items():
            if cf < threshold:
                low_cf.extend(check_list)
            else:
                high_cf.extend(check_list)

        if low_cf and high_cf:
            avg_low = sum(low_cf) / len(low_cf)
            avg_high = sum(high_cf) / len(high_cf)
            print(f"\nAvg checks when cumulative_findings < {threshold}: "
                  f"{avg_low:.1f} (n={len(low_cf)})")
            print(f"Avg checks when cumulative_findings >= {threshold}: "
                  f"{avg_high:.1f} (n={len(high_cf)})")

            if avg_high < avg_low * 0.7:
                print("SATISFICING SIGNAL — agent does fewer checks after "
                      "finding bugs")
            else:
                print("No satisficing signal — effort roughly consistent "
                      "regardless of findings count")
        print()

    return {}


# ---------------------------------------------------------------------------
# F8: Order / salience bias
# ---------------------------------------------------------------------------

def analyze_bias(buckets, **_):
    """F8: Does examination order or first findings anchor the agent?"""
    print("\n=== F8: Order / Salience Bias ===\n")

    checks = buckets.get("check", [])
    findings = buckets.get("finding", [])

    if not checks:
        print("No check events found.")
        return {}

    # Pattern distribution
    pattern_counts = defaultdict(int)
    for chk in checks:
        pattern_counts[chk.get("pattern", "unknown")] += 1

    total = sum(pattern_counts.values())
    print(f"Pattern distribution ({total} total checks):")
    for pattern, count in sorted(pattern_counts.items(),
                                 key=lambda x: -x[1]):
        pct = count / total * 100
        bar = "#" * int(pct / 2)
        print(f"  {pattern:<40} {count:>4} ({pct:>5.1f}%) {bar}")

    # First finding anchoring
    if findings:
        first_finding = min(findings,
                            key=lambda f: f.get("seq", float("inf")))
        first_cat = first_finding.get("category", "unknown")
        print(f"\nFirst finding category: {first_cat}")

        same_cat = sum(1 for f in findings
                       if f.get("category") == first_cat)
        print(f"Findings in same category: {same_cat}/{len(findings)}")

        if len(findings) > 2 and same_cat / len(findings) > 0.5:
            print("ANCHORING SIGNAL — majority of findings share first "
                  "finding's category")

    # Lens distribution by examination order
    order_by_construct = {}
    for cb in buckets.get("construct_begin", []):
        order_by_construct[cb.get("construct", "")] = \
            cb.get("examination_order", 0)

    lens_by_order = defaultdict(lambda: defaultdict(int))
    for chk in checks:
        construct = chk.get("construct", "")
        order = order_by_construct.get(construct, -1)
        lens = chk.get("lens", "?")
        level = chk.get("level", "")
        key = f"{lens}" + (f"-L{level}" if level else "")
        lens_by_order[order][key] += 1

    if lens_by_order:
        print(f"\nLens/level distribution by examination order:")
        all_keys = sorted(set(k for d in lens_by_order.values() for k in d))
        print(f"{'Order':>5}", end="")
        for k in all_keys:
            print(f" {k:>8}", end="")
        print()

        for order in sorted(lens_by_order.keys()):
            if order < 0:
                continue
            print(f"{order:>5}", end="")
            for k in all_keys:
                print(f" {lens_by_order[order].get(k, 0):>8}", end="")
            print()

    return {}


# ---------------------------------------------------------------------------
# Finding funnel
# ---------------------------------------------------------------------------

def analyze_funnel(buckets, **_):
    """How many issues were found in checks vs emitted as findings?"""
    print("\n=== Finding Funnel ===\n")

    checks = buckets.get("check", [])
    kb_checks = buckets.get("kb_check", [])
    cross = buckets.get("cross_construct_trace", [])
    findings = buckets.get("finding", [])

    check_issues = sum(1 for c in checks if c.get("verdict") == "issue")
    check_uncertain = sum(1 for c in checks
                          if c.get("verdict") == "uncertain")
    kb_issues = sum(1 for c in kb_checks if c.get("verdict") == "issue")
    cross_issues = sum(1 for c in cross if c.get("verdict") == "issue")
    total_issues = check_issues + kb_issues + cross_issues

    print(f"Check events with verdict=issue:          {check_issues}")
    print(f"Check events with verdict=uncertain:      {check_uncertain}")
    print(f"KB check events with verdict=issue:        {kb_issues}")
    print(f"Cross-construct traces with verdict=issue: {cross_issues}")
    print(f"Total issues identified in analysis:       {total_issues}")
    print(f"Findings emitted to output:                {len(findings)}")

    if total_issues > 0:
        conversion = len(findings) / total_issues * 100
        print(f"Conversion rate:                           {conversion:.0f}%")

        if conversion < 80:
            dropped = total_issues - len(findings)
            print(f"\nDROPPED FINDINGS SIGNAL — {dropped} issues found but "
                  f"not emitted as findings")
            print("This suggests output filtering (F7/output compression)")

    return {"total_issues": total_issues,
            "findings_emitted": len(findings)}


# ---------------------------------------------------------------------------
# Orchestration analysis (multi-file only)
# ---------------------------------------------------------------------------

def analyze_orchestration(buckets, known_bugs=None, per_file=None, **_):
    """Analyze parent orchestration decisions for subagent-caused misses."""
    print("\n=== Orchestration Analysis ===\n")

    dispatches = buckets.get("subagent_dispatch", [])
    results = buckets.get("subagent_result", [])
    clusters = buckets.get("cluster_assignment", [])

    if not dispatches:
        print("No subagent dispatches found — solo mode or parent didn't "
              "log dispatches.")
        print("Skipping orchestration analysis.")
        return {}

    # Cluster summary
    print(f"Clusters: {len(clusters)}")
    print(f"Subagent dispatches: {len(dispatches)}")
    print(f"Subagent results: {len(results)}")
    print()

    for cluster in clusters:
        cid = cluster.get("cluster_id", "?")
        constructs = cluster.get("constructs", [])
        rationale = cluster.get("rationale", "")
        print(f"  Cluster {cid}: {len(constructs)} constructs")
        for c in constructs:
            print(f"    - {c}")
        if rationale:
            print(f"    Rationale: {rationale}")
        print()

    # Context provided vs omitted per dispatch
    print("Context decisions per subagent dispatch:")
    for disp in dispatches:
        cid = disp.get("cluster_id", "?")
        ctx = disp.get("context_provided", {})
        print(f"\n  Cluster {cid} ({disp.get('subagent_file', '?')}):")
        print(f"    Files:                {len(ctx.get('files', []))}")
        print(f"    KB entries:           "
              f"{len(ctx.get('kb_entries', []))}")
        print(f"    Dependencies provided: "
              f"{len(ctx.get('dependencies_provided', []))}")
        omitted = ctx.get("dependencies_omitted", [])
        print(f"    Dependencies OMITTED:  {len(omitted)}")
        for dep in omitted:
            print(f"      - {dep}")

    # Subagent results summary
    if results:
        print(f"\nSubagent results:")
        total_findings = 0
        for res in results:
            cid = res.get("cluster_id", "?")
            findings = res.get("findings_returned", 0)
            examined = res.get("constructs_examined", 0)
            skipped = res.get("constructs_skipped", 0)
            total_findings += findings
            print(f"  Cluster {cid}: {findings} findings, "
                  f"{examined} examined, {skipped} skipped")
        print(f"  Total subagent findings: {total_findings}")

    return {"dispatches": len(dispatches), "results": len(results)}


# ---------------------------------------------------------------------------
# Normalization report
# ---------------------------------------------------------------------------

def print_normalization_report(per_file):
    """Report on schema compliance across subagents."""
    if not per_file or len(per_file) <= 1:
        return

    print("\n=== Schema Compliance Report ===\n")

    for fname, fbuckets in sorted(per_file.items()):
        checks = fbuckets.get("check", [])
        begins = fbuckets.get("construct_begin", [])

        if not checks and not begins:
            print(f"  {fname}: no check/begin events")
            continue

        # Check which fields are present
        issues = []
        if checks:
            sample = checks[0]
            if "construct_id" in sample and "construct" not in sample:
                issues.append("uses 'construct_id' instead of 'construct'")
            if "status" in sample and "verdict" not in sample:
                issues.append("uses 'status' instead of 'verdict'")
            if "name" in sample and "construct" not in sample:
                issues.append("uses 'name' instead of 'construct'")

        if begins:
            sample = begins[0]
            if "examination_order" not in sample:
                issues.append("missing 'examination_order' in construct_begin")
            if "cumulative_findings" not in sample:
                issues.append("missing 'cumulative_findings' in construct_begin")

        skips = fbuckets.get("construct_skip", [])
        if skips:
            issues.append("uses 'construct_skip' event instead of 'skip'")

        if issues:
            print(f"  {fname}: DRIFT DETECTED")
            for issue in issues:
                print(f"    - {issue}")
        else:
            print(f"  {fname}: compliant")


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

def print_summary(buckets, per_file=None):
    """Quick overview of the diagnostic log."""
    print("\n=== Diagnostic Log Summary ===\n")

    if per_file and len(per_file) > 1:
        print(f"Files loaded: {len(per_file)}")
        for fname in sorted(per_file.keys()):
            event_count = sum(len(v) for v in per_file[fname].values())
            print(f"  {fname}: {event_count} events")
        print()

    for event_type in ["baseline", "scope_inventory", "context_loaded",
                        "context_received", "cluster_assignment",
                        "subagent_dispatch", "subagent_result",
                        "agent_start", "construct_begin", "check",
                        "kb_check", "construct_end", "skip",
                        "cross_construct_trace", "finding"]:
        count = len(buckets.get(event_type, []))
        if count > 0:
            print(f"  {event_type:<25} {count:>5} events")

    checks = buckets.get("check", [])
    if checks:
        verdicts = defaultdict(int)
        for c in checks:
            verdicts[c.get("verdict", "unknown")] += 1
        print(f"\n  Check verdicts:")
        for v, count in sorted(verdicts.items(), key=lambda x: -x[1]):
            print(f"    {v:<15} {count:>5}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

ANALYSES = {
    "coverage": analyze_coverage,
    "patterns": analyze_patterns,
    "depth": analyze_depth,
    "crosscut": analyze_crosscut,
    "kb": analyze_kb,
    "decay": analyze_decay,
    "satisficing": analyze_satisficing,
    "bias": analyze_bias,
    "funnel": analyze_funnel,
    "orchestration": analyze_orchestration,
}


def main():
    parser = argparse.ArgumentParser(
        description="Analyze audit diagnostic JSONL for failure mode "
                    "detection")
    parser.add_argument("jsonl_path", nargs="?",
                        help="Path to diagnostic JSONL file (solo mode)")
    parser.add_argument("--run-dir",
                        help="Directory containing multiple diagnostic "
                             "JSONL files (multi-agent mode)")
    parser.add_argument("--prefix", default="diagnostic-f7",
                        help="File prefix for --run-dir glob "
                             "(default: diagnostic-f7)")
    parser.add_argument("--analysis", default="all",
                        choices=list(ANALYSES.keys()) + ["all"],
                        help="Which analysis to run (default: all)")
    parser.add_argument("--known-bugs",
                        help="JSON file with known bugs for false-negative "
                             "detection")
    parser.add_argument("--ground-truth",
                        help="JSON file with ground-truth construct list")

    args = parser.parse_args()

    if not args.jsonl_path and not args.run_dir:
        parser.error("Provide either a JSONL file path or --run-dir")

    # Load optional reference data
    known_bugs = None
    if args.known_bugs:
        known_bugs = load_known_bugs(args.known_bugs)

    ground_truth = None
    if args.ground_truth:
        ground_truth = load_ground_truth(args.ground_truth)

    # Load events
    per_file = None
    if args.run_dir:
        paths = find_diagnostic_files(args.run_dir, args.prefix)
        if not paths:
            print(f"Error: no diagnostic files found in {args.run_dir}",
                  file=sys.stderr)
            sys.exit(1)
        print(f"Loading {len(paths)} diagnostic files from {args.run_dir}")
        buckets, per_file = collect_events_multi(paths)
    else:
        path = args.jsonl_path
        if not Path(path).exists():
            print(f"Error: {path} not found", file=sys.stderr)
            sys.exit(1)
        buckets = collect_events(path)

    # Common kwargs for all analyses
    kwargs = {
        "known_bugs": known_bugs,
        "ground_truth": ground_truth,
        "per_file": per_file,
    }

    print_summary(buckets, per_file)
    print_normalization_report(per_file)

    if args.analysis == "all":
        analyze_coverage(buckets, **kwargs)
        analyze_patterns(buckets, **kwargs)
        analyze_depth(buckets, **kwargs)
        analyze_crosscut(buckets, **kwargs)
        analyze_kb(buckets, **kwargs)
        analyze_decay(buckets, **kwargs)
        analyze_satisficing(buckets, **kwargs)
        analyze_bias(buckets, **kwargs)
        analyze_funnel(buckets, **kwargs)
        analyze_orchestration(buckets, **kwargs)
    else:
        ANALYSES[args.analysis](buckets, **kwargs)


if __name__ == "__main__":
    main()
