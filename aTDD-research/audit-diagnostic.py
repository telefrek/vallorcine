#!/usr/bin/env python3
"""Audit pipeline diagnostic tool.

Validates every performance expectation, behavioral compliance rule, and
quality metric from the audit pipeline design document against a completed
pipeline run.

Data sources:
  - exploration-decisions.jsonl (tiering, clearing, frontier decisions)
  - Claude Code session JSONL files (per-turn token usage, tool calls)
  - Pipeline output artifacts (scope, suspect, prove, fix, report)

Usage:
    python3 audit-diagnostic.py <pipeline-run-dir> [--json] [--sessions-dir <dir>]

    pipeline-run-dir: directory containing pipeline output artifacts
                      (scope-definition.md, cluster packets, etc.)
    --sessions-dir:   directory containing Claude Code session JSONL files
                      (defaults to ~/.claude/projects/...)
    --json:           output machine-readable JSON instead of human report
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime
from glob import glob

# --- Result tracking ---

PASS = "PASS"
FLAG = "FLAG"
FAIL = "FAIL"


class DiagnosticResult:
    def __init__(self):
        self.checks = []

    def add(self, category, name, status, detail=""):
        self.checks.append({
            "category": category,
            "name": name,
            "status": status,
            "detail": detail,
        })

    def summary(self):
        counts = {PASS: 0, FLAG: 0, FAIL: 0}
        for c in self.checks:
            counts[c["status"]] += 1
        return counts

    def to_dict(self):
        return {
            "checks": self.checks,
            "summary": self.summary(),
        }


# --- JSONL parsing ---

def stream_jsonl(filepath):
    """Stream JSONL file line by line. Yields parsed entries."""
    try:
        with open(filepath) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    continue
    except OSError:
        return


def count_assistant_turns(filepath):
    """Count assistant messages with stop_reason (completed turns)."""
    count = 0
    for entry in stream_jsonl(filepath):
        if entry.get("type") == "assistant":
            msg = entry.get("message", {})
            if msg.get("stop_reason") is not None:
                count += 1
    return count


def extract_token_usage(filepath):
    """Extract per-turn input/output token counts from a session JSONL."""
    turns = []
    for entry in stream_jsonl(filepath):
        if entry.get("type") == "assistant":
            msg = entry.get("message", {})
            usage = msg.get("usage", {})
            if msg.get("stop_reason") is not None:
                turns.append({
                    "input": usage.get("input_tokens", 0),
                    "output": usage.get("output_tokens", 0),
                    "cache_read": usage.get("cache_read_input_tokens", 0),
                    "cache_create": usage.get("cache_creation_input_tokens", 0),
                })
    return turns


def extract_tool_calls_from_session(filepath):
    """Extract all tool calls from a session JSONL.

    Returns list of {turn, name, file_path, command}.
    """
    tools = []
    turn = 0
    for entry in stream_jsonl(filepath):
        if entry.get("type") == "assistant":
            msg = entry.get("message", {})
            if msg.get("stop_reason") is not None:
                turn += 1
            content = msg.get("content", [])
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict) or block.get("type") != "tool_use":
                    continue
                name = block.get("name", "")
                inp = block.get("input", {})
                tool = {"turn": turn, "name": name}
                if name in ("Read", "Write", "Edit"):
                    tool["file_path"] = inp.get("file_path", "")
                elif name == "Bash":
                    tool["command"] = inp.get("command", "")
                elif name == "Agent":
                    tool["description"] = inp.get("description", "")
                    tool["prompt"] = inp.get("prompt", "")[:500]
                tools.append(tool)
    return tools


def extract_first_user_message(filepath):
    """Extract the first user message content as text."""
    for entry in stream_jsonl(filepath):
        if entry.get("type") == "user":
            content = entry.get("message", {}).get("content", "")
            if isinstance(content, str):
                return content
            elif isinstance(content, list):
                texts = []
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "text":
                        texts.append(block["text"])
                return "\n".join(texts)
    return ""


# --- Stage inference ---

STAGE_PATTERNS = [
    (re.compile(r"You are the Classification subagent", re.I), "scope-classification"),
    (re.compile(r"classification output files and finalize", re.I), "scope-classification"),
    (re.compile(r"You are the Exploration subagent", re.I), "scope-exploration"),
    (re.compile(r"You are the Assembly subagent", re.I), "scope-assembly"),
    (re.compile(r"You are the Suspect subagent.*cluster\s*(\d+)", re.I), "suspect"),
    (re.compile(r"You are the Prove subagent.*F-R", re.I), "prove"),
    (re.compile(r"You are the Fix subagent.*F-R", re.I), "fix"),
    (re.compile(r"You are the Regression subagent", re.I), "regression"),
    (re.compile(r"You are the Report subagent", re.I), "report"),
]


def infer_stage(first_message):
    """Infer pipeline stage from the first user message of a session."""
    for pattern, stage in STAGE_PATTERNS:
        m = pattern.search(first_message)
        if m:
            detail = m.group(1) if m.lastindex else ""
            return stage, detail
    return "unknown", ""


def classify_sessions(session_files):
    """Classify session JSONL files by pipeline stage.

    Returns dict mapping stage -> list of {file, detail, turns}.
    """
    stages = {}
    for filepath in session_files:
        first_msg = extract_first_user_message(filepath)
        stage, detail = infer_stage(first_msg)
        turns = count_assistant_turns(filepath)
        if stage not in stages:
            stages[stage] = []
        stages[stage].append({
            "file": filepath,
            "detail": detail,
            "turns": turns,
            "first_message_preview": first_msg[:200],
        })
    return stages


# --- Exploration decisions ---

EXPLORATION_SCHEMA = {
    "tier_decision": ["construct", "file", "lines", "tier", "reason", "fan_in", "depth"],
    "clearing_check": ["construct", "file", "prior_clearing", "cited_line",
                        "still_exists", "result", "reason"],
    "frontier_stop": ["construct", "file", "direction", "reason", "depth",
                       "budget_remaining"],
    "domain_signal": ["signal", "file", "line", "concerns_activated"],
    "prior_work": ["construct", "prior_classification", "action", "reason"],
}


def validate_exploration_decisions(filepath, results):
    """Validate exploration-decisions.jsonl against schema and rules."""
    if not os.path.exists(filepath):
        results.add("exploration", "Decision log exists",
                     FLAG, f"Not found: {filepath}")
        return {}

    decisions = {
        "tier_decision": [],
        "clearing_check": [],
        "frontier_stop": [],
        "domain_signal": [],
        "prior_work": [],
    }
    schema_errors = []
    line_num = 0

    for entry in stream_jsonl(filepath):
        line_num += 1
        entry_type = entry.get("type")

        if entry_type not in EXPLORATION_SCHEMA:
            schema_errors.append(f"L{line_num}: unknown type '{entry_type}'")
            continue

        # Check required fields
        required = EXPLORATION_SCHEMA[entry_type]
        missing = [f for f in required if f not in entry]
        if missing:
            schema_errors.append(
                f"L{line_num}: {entry_type} missing fields: {missing}")

        decisions.setdefault(entry_type, []).append(entry)

    # Schema completeness check
    if schema_errors:
        results.add("exploration", "All decisions have required fields",
                     FAIL, f"{len(schema_errors)} schema errors: "
                     + "; ".join(schema_errors[:5]))
    else:
        results.add("exploration", "All decisions have required fields",
                     PASS, f"{line_num} entries validated")

    # Fan-in check: no high-fan-in construct in boundary/ignore
    high_fan_in_threshold = 5
    fan_in_violations = []
    for d in decisions.get("tier_decision", []):
        fan_in = d.get("fan_in", 0)
        tier = d.get("tier", "")
        if fan_in >= high_fan_in_threshold and tier in ("boundary", "ignore"):
            fan_in_violations.append(
                f"{d.get('construct')} (fan_in={fan_in}, tier={tier})")

    if fan_in_violations:
        results.add("exploration", "No high-fan-in construct in boundary/ignore",
                     FAIL, f"{len(fan_in_violations)} violations: "
                     + "; ".join(fan_in_violations[:3]))
    else:
        results.add("exploration", "No high-fan-in construct in boundary/ignore",
                     PASS)

    # Prior work: NEEDS-REVISIT prioritized
    needs_revisit = [d for d in decisions.get("prior_work", [])
                     if d.get("prior_classification") == "NEEDS-REVISIT"]
    nr_not_explored = [d for d in needs_revisit
                       if d.get("action") not in ("re-explore", "promote")]
    if needs_revisit:
        if nr_not_explored:
            results.add("exploration", "NEEDS-REVISIT constructs prioritized",
                         FLAG, f"{len(nr_not_explored)}/{len(needs_revisit)} "
                         "not re-explored")
        else:
            results.add("exploration", "NEEDS-REVISIT constructs prioritized",
                         PASS, f"{len(needs_revisit)}/{len(needs_revisit)} "
                         "re-explored")

    # Prior work: INVALID skipped unless code changed
    invalid_entries = [d for d in decisions.get("prior_work", [])
                       if d.get("prior_classification") == "INVALID"]
    invalid_not_skipped = [d for d in invalid_entries
                           if d.get("action") != "skip"
                           and "code_changed" not in d.get("reason", "")
                           and "changed" not in d.get("reason", "")]
    if invalid_entries:
        if invalid_not_skipped:
            results.add("exploration", "INVALID constructs skipped unless changed",
                         FLAG, f"{len(invalid_not_skipped)} re-explored "
                         "without code change reason")
        else:
            results.add("exploration", "INVALID constructs skipped unless changed",
                         PASS)

    # Frontier stops justified
    frontier_stops = decisions.get("frontier_stop", [])
    valid_reasons = {"depth_limit", "budget_full", "no_more_edges"}
    bad_stops = [d for d in frontier_stops
                 if d.get("reason") not in valid_reasons]
    budget_stops = [d for d in frontier_stops
                    if d.get("reason") == "budget_full"]
    if frontier_stops:
        if bad_stops:
            results.add("exploration", "Frontier stops are justified",
                         FLAG, f"{len(bad_stops)} stops with invalid reason")
        else:
            results.add("exploration", "Frontier stops are justified",
                         PASS, f"{len(frontier_stops)} stops "
                         f"({len(budget_stops)} budget-limited)")

        if len(budget_stops) > len(frontier_stops) * 0.5:
            results.add("exploration", "Budget not exhausted prematurely",
                         FLAG, f"{len(budget_stops)}/{len(frontier_stops)} "
                         "stops due to budget")
        else:
            results.add("exploration", "Budget not exhausted prematurely",
                         PASS)

    # Tier distribution summary
    tier_counts = {"analyze": 0, "boundary": 0, "ignore": 0}
    for d in decisions.get("tier_decision", []):
        tier = d.get("tier", "unknown")
        tier_counts[tier] = tier_counts.get(tier, 0) + 1
    results.add("exploration", "Tier distribution",
                 PASS, f"analyze={tier_counts.get('analyze', 0)}, "
                 f"boundary={tier_counts.get('boundary', 0)}, "
                 f"ignore={tier_counts.get('ignore', 0)}")

    return decisions


# --- Pipeline artifact parsing ---

def parse_summary_counts(filepath, pattern_map):
    """Parse a pipeline output markdown file for count patterns.

    pattern_map: dict of {field_name: regex_pattern}
    Returns dict of {field_name: int_value}.
    """
    counts = {}
    if not os.path.exists(filepath):
        return counts

    try:
        with open(filepath) as f:
            content = f.read()
    except OSError:
        return counts

    for field, pattern in pattern_map.items():
        m = re.search(pattern, content)
        if m:
            try:
                counts[field] = int(m.group(1))
            except (ValueError, IndexError):
                pass
    return counts


def find_cluster_packets(run_dir):
    """Find all cluster-{N}-packet.md files."""
    return sorted(glob(os.path.join(run_dir, "cluster-*-packet.md")))


def find_suspect_outputs(run_dir):
    """Find all suspect-cluster-{N}.md files."""
    return sorted(glob(os.path.join(run_dir, "suspect-cluster-*.md")))


def find_prove_outputs(run_dir):
    """Find all prove-cluster-{N}.md files."""
    return sorted(glob(os.path.join(run_dir, "prove-cluster-*.md")))


def find_fix_outputs(run_dir):
    """Find all fix-cluster-{N}.md files."""
    return sorted(glob(os.path.join(run_dir, "fix-cluster-*.md")))


def estimate_token_count(filepath):
    """Rough token estimate: ~4 chars per token."""
    try:
        size = os.path.getsize(filepath)
        return size // 4
    except OSError:
        return 0


def parse_scope_definition(filepath):
    """Parse scope-definition.md for cluster assignments and ignore list."""
    result = {
        "clusters": {},      # cluster_id -> list of {construct, file}
        "ignore_files": [],   # list of file paths
        "cross_cluster_edges": [],
    }
    if not os.path.exists(filepath):
        return result

    try:
        with open(filepath) as f:
            content = f.read()
    except OSError:
        return result

    # These are best-effort parsers — exact format depends on pipeline output
    # Parse ignore tier files
    ignore_section = re.search(
        r"##\s*Ignore[^\n]*\n(.*?)(?=\n##|\Z)", content, re.S)
    if ignore_section:
        for line in ignore_section.group(1).splitlines():
            path_match = re.search(r"`([^`]+)`", line)
            if path_match:
                result["ignore_files"].append(path_match.group(1))

    return result


def parse_prove_results(filepath):
    """Parse prove-cluster-{N}.md by counting status entries.

    The file contains multiple "# Prove Result" sections, each with a
    "- **Status:** CONFIRMED|UNCONFIRMED|COMPILE-SKIP|TEST-ERROR" line.
    """
    counts = {"received": 0, "confirmed": 0, "unconfirmed": 0,
              "compile_skipped": 0, "test_errors": 0}
    if not os.path.exists(filepath):
        return counts

    try:
        with open(filepath) as f:
            content = f.read()
    except OSError:
        return counts

    statuses = re.findall(r"\*\*Status:\*\*\s*([\w-]+)", content)
    for status in statuses:
        counts["received"] += 1
        status_lower = status.lower()
        if status_lower == "confirmed":
            counts["confirmed"] += 1
        elif status_lower == "unconfirmed":
            counts["unconfirmed"] += 1
        elif status_lower in ("compile-skip", "compile_skip"):
            counts["compile_skipped"] += 1
        elif status_lower in ("test-error", "test_error"):
            counts["test_errors"] += 1

    return counts


def parse_fix_results(filepath):
    """Parse fix-cluster-{N}.md by counting status entries.

    The file contains multiple "# Fix Result" sections, each with a
    "- **Status:** FIXED|IMPOSSIBLE|..." line.
    """
    counts = {"fixed": 0, "invalid": 0, "design_change": 0,
              "needs_revisit": 0, "total": 0}
    if not os.path.exists(filepath):
        return counts

    try:
        with open(filepath) as f:
            content = f.read()
    except OSError:
        return counts

    statuses = re.findall(r"\*\*Status:\*\*\s*(.+?)(?:\n|$)", content)
    for status in statuses:
        counts["total"] += 1
        status_lower = status.lower().strip()
        if "fixed" in status_lower:
            counts["fixed"] += 1
        elif "invalid" in status_lower:
            counts["invalid"] += 1
        elif "design" in status_lower:
            counts["design_change"] += 1
        elif "revisit" in status_lower:
            counts["needs_revisit"] += 1

    return counts


# --- Check runners ---

def run_cost_checks(staged_sessions, results):
    """Run cost-related checks against session data."""
    total_input = 0
    total_output = 0
    total_cache_read = 0
    total_cache_create = 0
    all_sessions = []

    turn_limits = {
        "scope-classification": 15,
        "scope-exploration": 15,
        "scope-assembly": 15,
        "suspect": 10,
        "prove": 10,
        "fix": 10,
        "regression": 15,
        "report": 10,
    }

    # Per-stage cost aggregation
    stage_costs = {}

    for stage, sessions in staged_sessions.items():
        stage_input = 0
        stage_output = 0
        stage_cr = 0
        stage_cc = 0
        stage_turns = 0

        for sess in sessions:
            turns = sess["turns"]
            filepath = sess["file"]
            usage = extract_token_usage(filepath)

            sess_input = sum(t["input"] for t in usage)
            sess_output = sum(t["output"] for t in usage)
            sess_cr = sum(t["cache_read"] for t in usage)
            sess_cc = sum(t["cache_create"] for t in usage)
            sess_context = sess_input + sess_cr + sess_cc

            total_input += sess_input
            total_output += sess_output
            total_cache_read += sess_cr
            total_cache_create += sess_cc

            stage_input += sess_input
            stage_output += sess_output
            stage_cr += sess_cr
            stage_cc += sess_cc
            stage_turns += turns

            # First turn context size (system prompt overhead)
            first_ctx = 0
            if usage:
                t = usage[0]
                first_ctx = t["input"] + t["cache_read"] + t["cache_create"]

            all_sessions.append({
                "stage": stage,
                "detail": sess.get("detail", ""),
                "turns": turns,
                "context_tokens": sess_context,
                "output_tokens": sess_output,
                "first_turn_context": first_ctx,
            })

            # Per-subagent turn check
            limit = turn_limits.get(stage, 15)
            label = stage
            if sess.get("detail"):
                label = f"{stage} {sess['detail']}"
            if turns <= limit:
                results.add("cost", f"{label}: {turns} turns",
                             PASS, f"<={limit}, context={sess_context:,}")
            else:
                results.add("cost", f"{label}: {turns} turns",
                             FLAG, f"exceeded {limit}, context={sess_context:,}")

        stage_costs[stage] = {
            "input": stage_input, "output": stage_output,
            "cache_read": stage_cr, "cache_create": stage_cc,
            "turns": stage_turns, "sessions": len(sessions),
        }

    # Total cost estimate with cache pricing
    # Sonnet: input $3/M, cache_read $0.30/M, cache_create $3.75/M, output $15/M
    input_cost = total_input * 3.0 / 1_000_000
    cache_read_cost = total_cache_read * 0.30 / 1_000_000
    cache_create_cost = total_cache_create * 3.75 / 1_000_000
    output_cost = total_output * 15.0 / 1_000_000
    total_cost = input_cost + cache_read_cost + cache_create_cost + output_cost

    total_context = total_input + total_cache_read + total_cache_create
    cache_pct = (total_cache_read / total_context * 100) if total_context > 0 else 0

    results.add("cost", "Total pipeline cost",
                 PASS, f"${total_cost:.2f} "
                 f"(in=${input_cost:.2f} cr=${cache_read_cost:.2f} "
                 f"cc=${cache_create_cost:.2f} out=${output_cost:.2f})")
    results.add("cost", "Total context tokens",
                 PASS, f"{total_context:,} "
                 f"({cache_pct:.1f}% cache reads)")
    results.add("cost", "Total output tokens",
                 PASS, f"{total_output:,}")

    # Per-stage cost breakdown
    for stage, costs in sorted(stage_costs.items()):
        s_ctx = costs["input"] + costs["cache_read"] + costs["cache_create"]
        s_cost = (costs["input"] * 3.0 + costs["cache_read"] * 0.30
                  + costs["cache_create"] * 3.75
                  + costs["output"] * 15.0) / 1_000_000
        results.add("cost", f"Stage {stage}",
                     PASS, f"${s_cost:.2f}, {costs['sessions']} sessions, "
                     f"{costs['turns']} turns, context={s_ctx:,}")

    # System prompt overhead (first turn context across all sessions)
    first_turn_contexts = [s["first_turn_context"] for s in all_sessions
                           if s["first_turn_context"] > 0]
    if first_turn_contexts:
        avg_first = sum(first_turn_contexts) / len(first_turn_contexts)
        total_overhead = sum(first_turn_contexts)
        results.add("cost", "System prompt overhead",
                     PASS, f"avg {avg_first:,.0f} tokens/session, "
                     f"total {total_overhead:,} across {len(first_turn_contexts)} "
                     f"sessions")

    # Average turns per subagent
    if all_sessions:
        avg_turns = sum(s["turns"] for s in all_sessions) / len(all_sessions)
        results.add("cost", "Average turns/subagent",
                     PASS, f"{avg_turns:.1f} across {len(all_sessions)} sessions")

    return all_sessions


def run_behavioral_checks(staged_sessions, run_dir, results):
    """Run behavioral compliance checks against session tool calls."""
    scope_def = parse_scope_definition(
        os.path.join(run_dir, "scope-definition.md"))
    ignore_files = set(scope_def.get("ignore_files", []))

    # Artifact files that only orchestrator should read
    artifact_files = {
        "scope-definition.md", "scope-exclusions.md", "scope-prior.md",
    }

    # Patterns indicating spec/KB/ADR access
    context_patterns = re.compile(
        r"(spec-resolve|\.spec/|\.kb/CLAUDE\.md|\.kb/.*index|"
        r"\.decisions/.*index|adr-validate)", re.I)

    # Patterns indicating test output parsing
    test_parse_patterns = re.compile(
        r"(xml|surefire|junit.*report|grep.*test|awk.*test|sed.*test"
        r"|TEST-.*\.xml)", re.I)

    scope_stages = {"scope-classification", "scope-exploration", "scope-assembly"}
    # Report is allowed to read pipeline artifacts — it's its job
    artifact_exempt_stages = {"report"}

    for stage, sessions in staged_sessions.items():
        if stage in scope_stages or stage == "unknown":
            continue

        for sess in sessions:
            tools = extract_tool_calls_from_session(sess["file"])
            label = stage
            if sess.get("detail"):
                label = f"{stage} {sess['detail']}"
            sess_id = os.path.basename(sess["file"])[:12]

            # Check: no spec/KB/ADR reads from non-Scope sessions
            for tool in tools:
                if tool["name"] == "Read" and tool.get("file_path"):
                    fp = tool["file_path"]
                    if context_patterns.search(fp):
                        results.add("compliance",
                                     "No downstream spec/KB/ADR reads",
                                     FAIL, f"{label} ({sess_id}) read {fp}")

            # Check: no ignore-tier file reads
            if ignore_files:
                for tool in tools:
                    if tool["name"] == "Read" and tool.get("file_path"):
                        fp = tool["file_path"]
                        for ign in ignore_files:
                            if fp.endswith(ign) or ign in fp:
                                results.add("compliance",
                                             "No ignore-tier file reads",
                                             FAIL,
                                             f"{label} ({sess_id}) read "
                                             f"ignore-tier file {fp}")

            # Check: no artifact reads from subagents (Report is exempt)
            if stage not in ("unknown",) and stage not in artifact_exempt_stages:
                for tool in tools:
                    if tool["name"] == "Read" and tool.get("file_path"):
                        basename = os.path.basename(tool["file_path"])
                        if basename in artifact_files:
                            results.add("compliance",
                                         "No artifact reads from subagents",
                                         FAIL,
                                         f"{label} ({sess_id}) read {basename}")

            # Fix-specific checks
            if stage == "fix":
                # Fix never modifies tests
                for tool in tools:
                    if tool["name"] in ("Write", "Edit") and tool.get("file_path"):
                        fp = tool["file_path"]
                        if re.search(
                            r"(Test\.java|_test\.py|\.test\.[jt]sx?|"
                            r"_test\.go|_spec\.rb)", fp):
                            results.add("compliance",
                                         "Fix never modifies tests",
                                         FAIL,
                                         f"Fix ({sess_id}) modified {fp}")

                # Fix never parses test output
                for tool in tools:
                    if tool["name"] == "Bash" and tool.get("command"):
                        if test_parse_patterns.search(tool["command"]):
                            results.add("compliance",
                                         "Fix never parses test output",
                                         FAIL,
                                         f"Fix ({sess_id}): {tool['command'][:80]}")

                # Fix reads intent before source (skip prompt file reads)
                reads = [t for t in tools if t["name"] == "Read"
                         and t.get("file_path")
                         and "/prompts/" not in t["file_path"]]
                if reads:
                    first_read = reads[0]["file_path"]
                    is_test = bool(re.search(
                        r"(Test\.java|_test\.py|\.test\.[jt]sx?|"
                        r"_test\.go|_spec\.rb|Prove)", first_read))
                    if is_test:
                        results.add("compliance",
                                     f"Fix reads intent before source ({sess_id})",
                                     PASS)
                    else:
                        results.add("compliance",
                                     f"Fix reads intent before source ({sess_id})",
                                     FLAG, f"First non-prompt read was {os.path.basename(first_read)}")

    # If no violations found for aggregate checks, mark as pass
    check_names = {c["name"] for c in results.checks if c["category"] == "compliance"}
    for name in ["No downstream spec/KB/ADR reads",
                 "No ignore-tier file reads",
                 "No artifact reads from subagents",
                 "Fix never modifies tests",
                 "Fix never parses test output"]:
        if name not in check_names:
            results.add("compliance", name, PASS)


def count_suspect_findings(run_dir):
    """Count total findings from suspect output files."""
    total = 0
    for sf in find_suspect_outputs(run_dir):
        try:
            with open(sf) as f:
                content = f.read()
            # Count finding headers: ### F-R...
            total += len(re.findall(r"###\s+F-R\d+\.\d+\.\d+", content))
        except OSError:
            pass
    return total


def run_quality_checks(run_dir, results):
    """Run quality metric checks against pipeline output artifacts."""
    # Count suspect findings
    suspect_total = count_suspect_findings(run_dir)
    if suspect_total > 0:
        results.add("quality", "Suspect findings",
                     PASS, f"{suspect_total} findings produced")

    # Aggregate prove results
    total_received = 0
    total_confirmed = 0
    total_unconfirmed = 0
    total_compile_skipped = 0
    total_test_errors = 0

    prove_files = find_prove_outputs(run_dir)
    for pf in prove_files:
        counts = parse_prove_results(pf)
        total_received += counts.get("received", 0)
        total_confirmed += counts.get("confirmed", 0)
        total_unconfirmed += counts.get("unconfirmed", 0)
        total_compile_skipped += counts.get("compile_skipped", 0)
        total_test_errors += counts.get("test_errors", 0)

    # Aggregate fix results
    total_fixed = 0
    total_invalid = 0
    total_design_change = 0
    total_needs_revisit = 0

    fix_files = find_fix_outputs(run_dir)
    for ff in fix_files:
        counts = parse_fix_results(ff)
        total_fixed += counts.get("fixed", 0)
        total_invalid += counts.get("invalid", 0)
        total_design_change += counts.get("design_change", 0)
        total_needs_revisit += counts.get("needs_revisit", 0)

    # Confirmation rate
    if total_received > 0:
        conf_rate = total_confirmed / total_received * 100
        if conf_rate >= 60:
            results.add("quality", "Confirmation rate",
                         PASS, f"{conf_rate:.0f}% (>= 60%)")
        else:
            results.add("quality", "Confirmation rate",
                         FLAG, f"{conf_rate:.0f}% (< 60% target)")
    else:
        results.add("quality", "Confirmation rate",
                     FLAG, "No findings to confirm")

    # Fix rate
    if total_confirmed > 0:
        fix_rate = total_fixed / total_confirmed * 100
        if fix_rate >= 70:
            results.add("quality", "Fix rate",
                         PASS, f"{fix_rate:.0f}% (>= 70%)")
        else:
            results.add("quality", "Fix rate",
                         FLAG, f"{fix_rate:.0f}% (< 70% target)")

    # Impossibility rate
    total_impossible = total_invalid + total_design_change + total_needs_revisit
    if total_confirmed > 0:
        imp_rate = total_impossible / total_confirmed * 100
        if imp_rate < 30:
            results.add("quality", "Impossibility rate",
                         PASS, f"{imp_rate:.0f}% (< 30%)")
        else:
            results.add("quality", "Impossibility rate",
                         FLAG, f"{imp_rate:.0f}% (>= 30% — Fix may be "
                         "taking easy path)")

    # Finding reconciliation
    prove_total = (total_confirmed + total_unconfirmed
                   + total_compile_skipped + total_test_errors)
    if total_received > 0 and prove_total != total_received:
        results.add("quality", "Finding reconciliation (Suspect→Prove)",
                     FAIL, f"Suspect={total_received}, Prove accounts for "
                     f"{prove_total}")
    elif total_received > 0:
        results.add("quality", "Finding reconciliation (Suspect→Prove)",
                     PASS, f"{total_received} findings fully accounted")

    fix_total = total_fixed + total_impossible
    if total_confirmed > 0 and fix_total != total_confirmed:
        results.add("quality", "Finding reconciliation (Prove→Fix)",
                     FAIL, f"Prove confirmed={total_confirmed}, Fix accounts "
                     f"for {fix_total}")
    elif total_confirmed > 0:
        results.add("quality", "Finding reconciliation (Prove→Fix)",
                     PASS, f"{total_confirmed} confirmed findings fully resolved")

    # Cluster packet size
    packets = find_cluster_packets(run_dir)
    for packet in packets:
        tokens = estimate_token_count(packet)
        name = os.path.basename(packet)
        if tokens <= 4000:
            results.add("quality", f"Packet size: {name}",
                         PASS, f"~{tokens} tokens (<= 4K)")
        else:
            results.add("quality", f"Packet size: {name}",
                         FLAG, f"~{tokens} tokens (> 4K target)")

    # Summary counts
    results.add("quality", "Pipeline summary",
                 PASS, f"suspect={total_received} prove_confirmed="
                 f"{total_confirmed} fixed={total_fixed} "
                 f"impossible={total_impossible}")


# --- Output formatting ---

def format_human_report(results, run_dir):
    """Format results as human-readable report."""
    lines = []
    lines.append("=== Audit Pipeline Diagnostic ===")
    lines.append(f"Run: {run_dir}")
    lines.append(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    lines.append("")

    # Group by category
    categories = {}
    for check in results.checks:
        cat = check["category"]
        if cat not in categories:
            categories[cat] = []
        categories[cat].append(check)

    category_labels = {
        "cost": "Cost",
        "compliance": "Behavioral Compliance",
        "exploration": "Exploration Audit",
        "quality": "Quality Metrics",
    }

    for cat_key in ["cost", "compliance", "exploration", "quality"]:
        checks = categories.get(cat_key, [])
        if not checks:
            continue
        lines.append(f"--- {category_labels.get(cat_key, cat_key)} ---")
        for check in checks:
            status = check["status"]
            marker = {"PASS": "  PASS ", "FLAG": "  FLAG ", "FAIL": "  FAIL "}
            line = f"{marker.get(status, '  ???? ')}{check['name']}"
            if check["detail"]:
                line += f" — {check['detail']}"
            lines.append(line)
        lines.append("")

    # Summary
    summary = results.summary()
    lines.append(f"Summary: {summary[PASS]} PASS, {summary[FLAG]} FLAG, "
                 f"{summary[FAIL]} FAIL")
    return "\n".join(lines)


# --- Main ---

def main():
    parser = argparse.ArgumentParser(
        description="Audit pipeline diagnostic tool")
    parser.add_argument("run_dir",
                        help="Pipeline run directory (contains output artifacts)")
    parser.add_argument("--sessions-dir",
                        help="Directory containing session JSONL files")
    parser.add_argument("--json", action="store_true",
                        help="Output machine-readable JSON")
    args = parser.parse_args()

    run_dir = os.path.expanduser(args.run_dir)
    if not os.path.isdir(run_dir):
        print(f"Error: {run_dir} is not a directory", file=sys.stderr)
        sys.exit(1)

    results = DiagnosticResult()

    # Find session JSONL files
    session_files = []
    if args.sessions_dir:
        sessions_dir = os.path.expanduser(args.sessions_dir)
        session_files = sorted(glob(os.path.join(sessions_dir, "*.jsonl")))
    else:
        # Look for sessions in the run directory or subdirectories
        session_files = sorted(glob(os.path.join(run_dir, "**", "*.jsonl"),
                                     recursive=True))

    # Classify sessions by stage
    staged_sessions = {}
    if session_files:
        staged_sessions = classify_sessions(session_files)
        stage_summary = {k: len(v) for k, v in staged_sessions.items()}
        results.add("cost", "Session classification",
                     PASS, f"{len(session_files)} sessions: {stage_summary}")
    else:
        results.add("cost", "Session classification",
                     FLAG, "No session JSONL files found")

    # Run checks
    run_cost_checks(staged_sessions, results)

    run_behavioral_checks(staged_sessions, run_dir, results)

    exploration_log = os.path.join(run_dir, "exploration-decisions.jsonl")
    validate_exploration_decisions(exploration_log, results)

    run_quality_checks(run_dir, results)

    # Output
    if args.json:
        print(json.dumps(results.to_dict(), indent=2))
    else:
        print(format_human_report(results, run_dir))

    # Exit code: 0 if no FAIL, 1 if any FAIL
    summary = results.summary()
    sys.exit(1 if summary[FAIL] > 0 else 0)


if __name__ == "__main__":
    main()
