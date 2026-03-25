#!/usr/bin/env python3
"""Collect aTDD results after a Claude Code session completes.

Reads the feature's aTDD state files, Claude Code session JSONL, and file
state to produce a structured results file for comparison.

Usage:
    python3 collect-results.py --jlsm-path /path/to/jlsm-atdd-feature \
                               --feature table-partitioning \
                               --results-dir results/
"""

import argparse
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime


def file_checksums(directory, extensions=None):
    """Compute SHA256 checksums for source files."""
    checksums = {}
    if extensions is None:
        extensions = {".java", ".py", ".ts", ".js", ".go", ".rs", ".kt", ".scala"}
    for root, dirs, files in os.walk(directory):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in
                   ("build", "target", "node_modules", "__pycache__", ".gradle")]
        for fname in files:
            if any(fname.endswith(ext) for ext in extensions):
                fpath = os.path.join(root, fname)
                relpath = os.path.relpath(fpath, directory)
                try:
                    h = hashlib.sha256()
                    with open(fpath, "rb") as f:
                        for chunk in iter(lambda: f.read(8192), b""):
                            h.update(chunk)
                    checksums[relpath] = h.hexdigest()
                except (OSError, IOError):
                    checksums[relpath] = "ERROR"
    return checksums


def read_file_safe(path):
    """Read a file, returning empty string if it doesn't exist."""
    try:
        with open(path) as f:
            return f.read()
    except (OSError, IOError):
        return ""


def parse_atdd_status(content):
    """Parse atdd-status.md into structured data."""
    result = {
        "max_rounds": 0,
        "current_round": 0,
        "status": "unknown",
        "rounds": [],
    }
    if not content:
        return result

    for line in content.split("\n"):
        if line.startswith("Max rounds:"):
            try:
                result["max_rounds"] = int(line.split(":")[1].strip())
            except (ValueError, IndexError):
                pass
        elif line.startswith("Current round:"):
            try:
                result["current_round"] = int(line.split(":")[1].strip())
            except (ValueError, IndexError):
                pass
        elif line.startswith("Status:"):
            result["status"] = line.split(":")[1].strip()

    # Parse round history table
    in_table = False
    for line in content.split("\n"):
        if "| Round |" in line:
            in_table = True
            continue
        if in_table and line.startswith("|") and "---" not in line:
            cols = [c.strip() for c in line.strip("|").split("|")]
            if len(cols) >= 6:
                try:
                    result["rounds"].append({
                        "round": int(cols[0]) if cols[0].isdigit() else 0,
                        "analyst_vectors": int(cols[1]) if cols[1].isdigit() else 0,
                        "breaker_tests": int(cols[2]) if cols[2].isdigit() else 0,
                        "confirmed_bugs": int(cols[3]) if cols[3].isdigit() else 0,
                        "theoretical": int(cols[4]) if cols[4].isdigit() else 0,
                        "status": cols[5],
                    })
                except (ValueError, IndexError):
                    pass

    return result


def parse_known_issues(content):
    """Parse known_issues.md into counts by type.

    Handles multiple formats:
    - Header format: ### RESOLVED-1 (Round 1): description
    - List format: - RESOLVED: description
    - Section format: ## Resolved patterns (count entries under it)
    """
    result = {
        "resolved": 0, "tendency": 0, "watch": 0,
        "suspect": 0, "freeze": 0,
        "adr_protected": 0, "impossible": 0,
    }
    if not content:
        return result

    for line in content.split("\n"):
        stripped = line.strip().lower()

        # Header format: ### RESOLVED-1, ### R-1, ### TENDENCY-1, etc.
        if stripped.startswith("### resolved") or stripped.startswith("### r-"):
            result["resolved"] += 1
        elif stripped.startswith("### tendency") or stripped.startswith("### t-"):
            result["tendency"] += 1
        elif stripped.startswith("### watch") or stripped.startswith("### w-"):
            result["watch"] += 1
        elif stripped.startswith("### suspect") or stripped.startswith("### s-"):
            result["suspect"] += 1
        elif stripped.startswith("### freeze") or stripped.startswith("### f-"):
            result["freeze"] += 1
        elif stripped.startswith("### adr-protected") or stripped.startswith("### adr_protected"):
            result["adr_protected"] += 1
        elif stripped.startswith("### impossible"):
            result["impossible"] += 1
        # List format: - RESOLVED: description
        elif stripped.startswith("- resolved:"):
            result["resolved"] += 1
        elif stripped.startswith("- tendency:"):
            result["tendency"] += 1
        elif stripped.startswith("- watch:"):
            result["watch"] += 1
        elif stripped.startswith("- suspect:"):
            result["suspect"] += 1
        elif stripped.startswith("- freeze:"):
            result["freeze"] += 1

    return result


def find_adversarial_tests(jlsm_path):
    """Find all adversarial test files created by the Breaker."""
    patterns = [
        "**/.*AdversarialTest.java",
        "**/*_adversarial_test.py",
        "**/*.adversarial.test.*",
        "**/*Adversarial*Test*",
    ]
    tests = []
    for root, dirs, files in os.walk(jlsm_path):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in
                   ("build", "target", "node_modules")]
        for fname in files:
            if "adversarial" in fname.lower() or "Adversarial" in fname:
                fpath = os.path.join(root, fname)
                relpath = os.path.relpath(fpath, jlsm_path)
                # Count test methods
                try:
                    with open(fpath) as f:
                        content = f.read()
                    # Java: @Test annotations
                    test_count = len(re.findall(r"@Test", content))
                    # Python: def test_
                    test_count += len(re.findall(r"def test_", content))
                    # JS/TS: it(, test(
                    test_count += len(re.findall(r"\b(?:it|test)\s*\(", content))
                except (OSError, IOError):
                    test_count = 0

                tests.append({
                    "file": relpath,
                    "test_methods": test_count,
                })

    return tests


def find_session_jsonls(jlsm_path):
    """Find all Claude Code session JSONL files for this project.

    Looks in ~/.claude/projects/ for the matching project hash.
    Returns a list of JSONL file paths, newest first.
    """
    claude_projects = os.path.expanduser("~/.claude/projects")
    if not os.path.isdir(claude_projects):
        return []

    # Claude Code uses the absolute path with / replaced by -
    # /tmp/atdd-validation/foo → -tmp-atdd-validation-foo
    path_hash = jlsm_path.replace("/", "-")
    # The hash in ~/.claude/projects/ keeps the leading -
    project_dir = os.path.join(claude_projects, path_hash)

    if not os.path.isdir(project_dir):
        # Also try without leading -
        if path_hash.startswith("-"):
            alt = os.path.join(claude_projects, path_hash[1:])
            if os.path.isdir(alt):
                project_dir = alt
            else:
                return []
        else:
            return []

    jsonls = sorted(
        glob.glob(os.path.join(project_dir, "*.jsonl")),
        key=os.path.getmtime,
        reverse=True,
    )
    return jsonls


def extract_session_tokens(jsonl_paths):
    """Extract token usage from one or more session JSONL files.

    Returns totals plus derived metrics:
    - billable_input: input + cache_create (what Anthropic charges)
    - context_per_turn: input + cache_read + cache_create (window pressure)
    - peak_context: highest single-turn context usage (session survival limit)
    - dollar_cost_estimate: rough USD estimate at current Sonnet pricing
    """
    totals = {
        "input": 0, "output": 0, "cache_read": 0, "cache_create": 0,
        "messages": 0, "peak_context": 0,
    }
    if not jsonl_paths:
        return totals

    if isinstance(jsonl_paths, str):
        jsonl_paths = [jsonl_paths]

    for jsonl_path in jsonl_paths:
        if not jsonl_path or not os.path.exists(jsonl_path):
            continue
        try:
            with open(jsonl_path) as f:
                for line in f:
                    try:
                        entry = json.loads(line)
                        if entry.get("type") == "assistant":
                            msg = entry.get("message", {})
                            usage = msg.get("usage", {})
                            if msg.get("stop_reason") is not None:
                                inp = usage.get("input_tokens", 0)
                                out = usage.get("output_tokens", 0)
                                c_read = usage.get("cache_read_input_tokens", 0)
                                c_create = usage.get("cache_creation_input_tokens", 0)

                                totals["input"] += inp
                                totals["output"] += out
                                totals["cache_read"] += c_read
                                totals["cache_create"] += c_create
                                totals["messages"] += 1

                                # Track peak context window pressure
                                turn_context = inp + c_read + c_create
                                if turn_context > totals["peak_context"]:
                                    totals["peak_context"] = turn_context
                    except (json.JSONDecodeError, ValueError):
                        continue
        except (OSError, IOError):
            pass

    # Derived metrics
    totals["billable_input"] = totals["input"] + totals["cache_create"]
    totals["total_context"] = totals["input"] + totals["cache_read"] + totals["cache_create"]
    totals["total_billable"] = totals["billable_input"] + totals["output"]
    totals["total_all"] = totals["billable_input"] + totals["output"] + totals["cache_read"]

    return totals


def main():
    parser = argparse.ArgumentParser(
        description="Collect aTDD results after Claude Code session"
    )
    parser.add_argument("--jlsm-path", required=True,
                        help="Path to jlsm (or worktree) where aTDD ran")
    parser.add_argument("--feature", required=True,
                        help="Feature slug")
    parser.add_argument("--results-dir", default="results",
                        help="Results directory (default: results/)")
    args = parser.parse_args()

    jlsm_path = os.path.abspath(os.path.expanduser(args.jlsm_path))
    slug = args.feature
    results_dir = os.path.join(os.path.abspath(args.results_dir), slug)
    os.makedirs(results_dir, exist_ok=True)

    print(f"\n=== Collecting aTDD results: {slug} ===", file=sys.stderr)

    # Read aTDD state files
    feature_dir = os.path.join(jlsm_path, ".feature", slug)
    archive_dir = os.path.join(jlsm_path, ".feature", "_archive", slug)

    # Try feature dir first, then archive
    if os.path.isdir(feature_dir):
        state_dir = feature_dir
    elif os.path.isdir(archive_dir):
        state_dir = archive_dir
    else:
        print(f"  Warning: no .feature/{slug}/ directory found", file=sys.stderr)
        state_dir = feature_dir  # will produce empty reads

    atdd_status_content = read_file_safe(os.path.join(state_dir, "atdd-status.md"))
    known_issues_content = read_file_safe(os.path.join(state_dir, "known_issues.md"))
    breaker_prompt_content = read_file_safe(os.path.join(state_dir, "breaker-prompt.md"))
    gaps_content = read_file_safe(os.path.join(state_dir, "gaps.md"))
    refactor_diff_content = read_file_safe(os.path.join(state_dir, "refactor-diff.md"))

    # Parse structured data
    atdd_status = parse_atdd_status(atdd_status_content)
    known_issues = parse_known_issues(known_issues_content)
    adversarial_tests = find_adversarial_tests(jlsm_path)

    # Token usage from session
    session_jsonls = find_session_jsonls(jlsm_path)
    session_tokens = extract_session_tokens(session_jsonls)

    # Post-run file state
    post_checksums = file_checksums(jlsm_path)

    # Load pre-run state for diff
    pre_state_path = os.path.join(results_dir, "pre-run-state.json")
    pre_checksums = {}
    if os.path.exists(pre_state_path):
        with open(pre_state_path) as f:
            pre_state = json.load(f)
        pre_checksums = pre_state.get("source_checksums", {})

    # Compute file diffs
    new_files = set(post_checksums.keys()) - set(pre_checksums.keys())
    modified_files = {f for f in set(post_checksums.keys()) & set(pre_checksums.keys())
                      if post_checksums[f] != pre_checksums[f]}
    deleted_files = set(pre_checksums.keys()) - set(post_checksums.keys())

    # Build results
    results = {
        "feature": slug,
        "collected_at": datetime.utcnow().isoformat() + "Z",
        "atdd_status": atdd_status,
        "known_issues": known_issues,
        "adversarial_tests": {
            "file_count": len(adversarial_tests),
            "total_test_methods": sum(t["test_methods"] for t in adversarial_tests),
            "files": adversarial_tests,
        },
        "session_tokens": session_tokens,
        "session_jsonls": session_jsonls,
        "file_changes": {
            "new_files": sorted(new_files),
            "modified_files": sorted(modified_files),
            "deleted_files": sorted(deleted_files),
        },
        "raw_content": {
            "atdd_status_md": atdd_status_content[:2000] if atdd_status_content else "",
            "known_issues_md": known_issues_content[:5000] if known_issues_content else "",
            "gaps_md": gaps_content[:3000] if gaps_content else "",
        },
    }

    # Save results
    output_path = os.path.join(results_dir, "atdd-results.json")
    with open(output_path, "w") as f:
        json.dump(results, f, indent=2)

    # Save post-run state
    post_state = {
        "label": "post-atdd",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "source_checksums": post_checksums,
    }
    with open(os.path.join(results_dir, "post-run-state.json"), "w") as f:
        json.dump(post_state, f, indent=2)

    # Copy adversarial test files
    tests_dir = os.path.join(results_dir, "new-tests")
    os.makedirs(tests_dir, exist_ok=True)
    for test in adversarial_tests:
        src = os.path.join(jlsm_path, test["file"])
        dst = os.path.join(tests_dir, os.path.basename(test["file"]))
        try:
            with open(src) as f_in:
                with open(dst, "w") as f_out:
                    f_out.write(f_in.read())
        except (OSError, IOError):
            pass

    # Print summary
    print(f"\n  Results:", file=sys.stderr)
    print(f"    Rounds completed: {atdd_status['current_round']}", file=sys.stderr)
    print(f"    Status: {atdd_status['status']}", file=sys.stderr)
    print(f"    Adversarial test files: {len(adversarial_tests)}", file=sys.stderr)
    print(f"    Adversarial test methods: {sum(t['test_methods'] for t in adversarial_tests)}",
          file=sys.stderr)
    print(f"    Confirmed bugs (RESOLVED): {known_issues['resolved']}", file=sys.stderr)
    print(f"    Tendencies: {known_issues['tendency']}", file=sys.stderr)
    print(f"    Watch items: {known_issues['watch']}", file=sys.stderr)
    if known_issues.get('adr_protected'):
        print(f"    ADR-protected: {known_issues['adr_protected']}", file=sys.stderr)
    print(f"    Tokens:", file=sys.stderr)
    print(f"      Billable input:  {session_tokens.get('billable_input', 0):>12,}  (input + cache_create)",
          file=sys.stderr)
    print(f"      Output:          {session_tokens['output']:>12,}", file=sys.stderr)
    print(f"      Total billable:  {session_tokens.get('total_billable', 0):>12,}  (what you pay)",
          file=sys.stderr)
    print(f"      Cache read:      {session_tokens['cache_read']:>12,}  (free but fills window)",
          file=sys.stderr)
    print(f"      Peak context:    {session_tokens.get('peak_context', 0):>12,}  /1,000,000 window",
          file=sys.stderr)
    print(f"      Total all:       {session_tokens.get('total_all', 0):>12,}", file=sys.stderr)
    print(f"    Sessions found: {len(session_jsonls)}", file=sys.stderr)
    print(f"    Files changed: {len(new_files)} new, {len(modified_files)} modified",
          file=sys.stderr)
    print(f"\n  Written to: {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
