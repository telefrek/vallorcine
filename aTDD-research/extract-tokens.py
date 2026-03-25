#!/usr/bin/env python3
"""Extract TDD-stage-bounded token usage and file state from JSONL sessions.

Given a session-map.json and a project directory, extracts:
  - Per-stage token usage (scoping, domains, planning, testing, impl, refactor)
  - File modifications timeline (Write/Edit tool calls with paths)
  - Git commits with SHAs (for state reconstruction)
  - TDD boundary detection (where planning ends and testing begins)

Handles both subagent-delegated TDD (feature-coordinate) and inline TDD.

For inline sessions, TDD boundary is detected by:
  1. First test file write (Write/Edit to *Test.java, *_test.py, *.test.ts, etc.)
  2. First test run (gradle test, pytest, jest, etc.)
  3. First read of work-plan.md or stub files

Usage:
    python3 extract-tokens.py <project-dir> <session-map.json> [--output token-report.json]
"""

import argparse
import json
import os
import re
import sys

# Map command names to stage labels
COMMAND_TO_STAGE = {
    "feature": "scoping",
    "feature-quick": "scoping",
    "feature-domains": "domains",
    "feature-plan": "planning",
    "feature-test": "testing",
    "feature-implement": "implementation",
    "feature-refactor": "refactor",
    "feature-pr": "pr",
    "feature-retro": "retro",
    "feature-complete": "complete",
    "feature-coordinate": "coordination",
}

TDD_STAGES = {"testing", "implementation", "refactor", "tdd-cycle"}

COMMAND_NAME_RE = re.compile(r"<command-name>/([^<]+)</command-name>")
COMMAND_ARGS_RE = re.compile(r"<command-args>([^<]*)</command-args>")
SLUG_RE = re.compile(r"^[a-z][a-z0-9]+(-[a-z0-9]+)*$")

# Test file patterns (language-agnostic)
TEST_FILE_RE = re.compile(
    r"(Test\.java|_test\.py|\.test\.[jt]sx?|_test\.go|_spec\.rb|\.spec\.[jt]sx?|Tests?\.cs)$"
)
# Test runner commands
TEST_RUN_RE = re.compile(
    r"(gradlew.*test|pytest|jest|mocha|go\s+test|dotnet\s+test|cargo\s+test|npm\s+test"
    r"|gradlew.*check|gradle.*test)",
    re.IGNORECASE,
)
# Git commit pattern to extract SHA
GIT_COMMIT_SHA_RE = re.compile(r"\[[\w/.-]+\s+([0-9a-f]{7,40})\]")
# Stub/plan file patterns
PLAN_FILE_RE = re.compile(r"(work-plan\.md|brief\.md|domains\.md|status\.md|stub)")


def parse_command(content):
    """Extract (command_name, slug) from user message content."""
    if isinstance(content, str):
        names = COMMAND_NAME_RE.findall(content)
        args_list = COMMAND_ARGS_RE.findall(content)
        for i, name in enumerate(names):
            if name in COMMAND_TO_STAGE:
                args = args_list[i].strip().strip('"').strip("'") if i < len(args_list) else ""
                slug = None
                non_flag_words = [w for w in args.split() if not w.startswith("-")]
                if non_flag_words:
                    candidate = non_flag_words[0].strip('"').strip("'")
                    if SLUG_RE.match(candidate):
                        if name == "feature" and len(non_flag_words) > 1:
                            slug = None
                        else:
                            slug = candidate
                return name, slug
        return None, None
    elif isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                cmd, slug = parse_command(block["text"])
                if cmd:
                    return cmd, slug
        return None, None
    return None, None


def extract_tool_calls(content):
    """Extract tool calls from assistant message content.

    Returns list of {name, file_path, command, description, tool_use_id}.
    """
    tools = []
    if not isinstance(content, list):
        return tools

    for block in content:
        if not isinstance(block, dict) or block.get("type") != "tool_use":
            continue
        name = block.get("name", "")
        inp = block.get("input", {})
        tool = {"name": name, "id": block.get("id", "")}

        if name in ("Write", "Edit"):
            tool["file_path"] = inp.get("file_path", "")
            tool["is_test"] = bool(TEST_FILE_RE.search(tool["file_path"]))
            tool["is_impl"] = "src/main" in tool["file_path"] or (
                "src/" in tool["file_path"] and not tool["is_test"]
            )
        elif name == "Bash":
            tool["command"] = inp.get("command", "")
            tool["is_test_run"] = bool(TEST_RUN_RE.search(tool["command"]))
            tool["is_git_commit"] = "git commit" in tool["command"]
            tool["is_git_add"] = "git add" in tool["command"]
        elif name == "Agent":
            tool["description"] = inp.get("description", "")
            tool["subagent_type"] = inp.get("subagent_type", "")
        elif name == "Read":
            tool["file_path"] = inp.get("file_path", "")

        tools.append(tool)
    return tools


def extract_tool_results(content):
    """Extract tool results from user message content.

    Returns list of {tool_use_id, content_text, is_subagent_result,
    total_tokens, duration_ms, git_sha}.
    """
    results = []
    if not isinstance(content, list):
        return results

    for block in content:
        if not isinstance(block, dict) or block.get("type") != "tool_result":
            continue

        result = {"tool_use_id": block.get("tool_use_id", "")}
        result_content = block.get("content", "")

        # Flatten content to text
        text = ""
        if isinstance(result_content, str):
            text = result_content
        elif isinstance(result_content, list):
            for item in result_content:
                if isinstance(item, dict) and item.get("type") == "text":
                    text += item["text"] + "\n"

        result["text"] = text[:500]  # Keep first 500 chars for context

        # Check for subagent result
        if "agentId:" in text and "<usage>" in text:
            result["is_subagent_result"] = True
            match = re.search(r"total_tokens:\s*(\d+)", text)
            result["total_tokens"] = int(match.group(1)) if match else 0
            match = re.search(r"duration_ms:\s*(\d+)", text)
            result["duration_ms"] = int(match.group(1)) if match else 0
        else:
            result["is_subagent_result"] = False

        # Check for git commit SHA in output
        sha_match = GIT_COMMIT_SHA_RE.search(text)
        if sha_match:
            result["git_sha"] = sha_match.group(1)

        results.append(result)
    return results


def classify_subagent(description):
    """Classify a subagent description into a stage."""
    desc_lower = description.lower()
    wu_match = re.search(r"WU-(\d+)", description, re.IGNORECASE)
    wu = f"WU-{wu_match.group(1)}" if wu_match else None

    if any(kw in desc_lower for kw in ["test-implement-refactor", "tdd cycle", "tdd"]):
        return "tdd-cycle", wu
    if "test" in desc_lower and "implement" in desc_lower:
        return "tdd-cycle", wu
    if "implement" in desc_lower and "refactor" not in desc_lower:
        return "implementation", wu
    if "refactor" in desc_lower:
        return "refactor", wu
    if "test" in desc_lower and "implement" not in desc_lower:
        return "testing", wu
    if "stub" in desc_lower or "work plan" in desc_lower or "plan" in desc_lower:
        return "planning", wu
    if "domain" in desc_lower:
        return "domains", wu
    if "research" in desc_lower:
        return "research", None
    if "architect" in desc_lower:
        return "architecture", None
    return "other", wu


def sum_usage_in_range(lines, start, end):
    """Sum assistant message token usage for a line range."""
    totals = {"input": 0, "output": 0, "cache_read": 0, "cache_create": 0, "messages": 0}
    for i in range(start, min(end, len(lines))):
        try:
            entry = json.loads(lines[i])
            if entry.get("type") == "assistant":
                msg = entry.get("message", {})
                usage = msg.get("usage", {})
                if msg.get("stop_reason") is not None:
                    totals["input"] += usage.get("input_tokens", 0)
                    totals["output"] += usage.get("output_tokens", 0)
                    totals["cache_read"] += usage.get("cache_read_input_tokens", 0)
                    totals["cache_create"] += usage.get("cache_creation_input_tokens", 0)
                    totals["messages"] += 1
        except (json.JSONDecodeError, ValueError):
            continue
    return totals


def process_session(project_dir, session_id):
    """Process a single JSONL session and extract everything we need.

    Returns a session record with:
      - commands: list of (line, command, slug)
      - subagents: list of {line, description, stage, wu, total_tokens, duration}
      - file_modifications: list of {line, path, is_test, is_impl, tool}
      - git_commits: list of {line, sha, message_preview}
      - tdd_boundary: line number where TDD work begins (first test write/run)
      - file_snapshots: list of {line, files}
      - usage_by_range: token usage for key ranges
    """
    filepath = os.path.join(project_dir, f"{session_id}.jsonl")
    if not os.path.exists(filepath):
        return None

    try:
        with open(filepath) as f:
            lines = f.readlines()
    except (OSError, IOError):
        return None

    record = {
        "session_id": session_id,
        "total_lines": len(lines),
        "commands": [],
        "subagents": [],
        "file_modifications": [],
        "git_commits": [],
        "test_runs": [],
        "file_snapshots": [],
        "tdd_boundary_line": None,
        "planning_boundary_line": None,
    }

    pending_agents = {}  # tool_use_id -> {line, description, stage, wu}
    pending_git_commits = {}  # tool_use_id -> line

    for line_num, line in enumerate(lines):
        try:
            entry = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue

        entry_type = entry.get("type")

        if entry_type == "assistant":
            content = entry.get("message", {}).get("content", [])
            tools = extract_tool_calls(content)

            for tool in tools:
                if tool["name"] in ("Write", "Edit") and tool.get("file_path"):
                    mod = {
                        "line": line_num,
                        "path": tool["file_path"],
                        "is_test": tool.get("is_test", False),
                        "is_impl": tool.get("is_impl", False),
                        "tool": tool["name"],
                    }
                    record["file_modifications"].append(mod)

                    # Detect TDD boundary: first test file write
                    if mod["is_test"] and record["tdd_boundary_line"] is None:
                        record["tdd_boundary_line"] = line_num

                elif tool["name"] == "Bash":
                    if tool.get("is_test_run"):
                        record["test_runs"].append({"line": line_num, "command": tool["command"][:100]})
                        if record["tdd_boundary_line"] is None:
                            record["tdd_boundary_line"] = line_num

                    if tool.get("is_git_commit"):
                        pending_git_commits[tool["id"]] = line_num

                elif tool["name"] == "Agent":
                    stage, wu = classify_subagent(tool.get("description", ""))
                    pending_agents[tool["id"]] = {
                        "line": line_num,
                        "description": tool.get("description", ""),
                        "stage": stage,
                        "wu": wu,
                    }

        elif entry_type == "user":
            content = entry.get("message", {}).get("content", "")

            # Parse feature commands
            cmd, slug = parse_command(content)
            if cmd:
                record["commands"].append({
                    "line": line_num,
                    "command": cmd,
                    "slug": slug,
                })
                # Detect planning boundary
                if cmd in ("feature-plan",) and record["planning_boundary_line"] is None:
                    record["planning_boundary_line"] = line_num
                # Detect TDD boundary from explicit commands
                if cmd in ("feature-test", "feature-implement") and record["tdd_boundary_line"] is None:
                    record["tdd_boundary_line"] = line_num

            # Parse tool results
            if isinstance(content, list):
                results = extract_tool_results(content)
                for result in results:
                    # Subagent results
                    if result.get("is_subagent_result") and result["tool_use_id"] in pending_agents:
                        agent = pending_agents.pop(result["tool_use_id"])
                        record["subagents"].append({
                            "line": agent["line"],
                            "result_line": line_num,
                            "description": agent["description"],
                            "stage": agent["stage"],
                            "work_unit": agent["wu"],
                            "total_tokens": result.get("total_tokens", 0),
                            "duration_ms": result.get("duration_ms", 0),
                        })

                    # Git commit results (SHA from output)
                    if result.get("git_sha"):
                        commit_line = pending_git_commits.pop(result["tool_use_id"], line_num)
                        record["git_commits"].append({
                            "line": commit_line,
                            "sha": result["git_sha"],
                            "result_text": result["text"][:200],
                        })

        elif entry_type == "file-history-snapshot":
            snapshot = entry.get("snapshot", {})
            backups = snapshot.get("trackedFileBackups", {})
            if backups:
                record["file_snapshots"].append({
                    "line": line_num,
                    "file_count": len(backups),
                    "files": {
                        path: info.get("backupFileName")
                        for path, info in backups.items()
                    },
                })

    # Compute token usage for key ranges
    record["usage"] = {}

    tdd_line = record["tdd_boundary_line"]
    if tdd_line is not None:
        record["usage"]["pre_tdd"] = sum_usage_in_range(lines, 0, tdd_line)
        record["usage"]["tdd"] = sum_usage_in_range(lines, tdd_line, len(lines))
    else:
        record["usage"]["full_session"] = sum_usage_in_range(lines, 0, len(lines))

    # Also compute subagent-based TDD totals
    tdd_subagent_tokens = 0
    for sa in record["subagents"]:
        if sa["stage"] in TDD_STAGES:
            tdd_subagent_tokens += sa["total_tokens"]
    record["usage"]["tdd_subagent_tokens"] = tdd_subagent_tokens

    return record


def aggregate_features(session_records, feature_sessions):
    """Aggregate session records into per-feature summaries.

    feature_sessions: dict mapping slug -> list of session_ids
    """
    features = {}

    for slug, session_ids in sorted(feature_sessions.items()):
        feat = {
            "slug": slug,
            "session_count": len(session_ids),
            "tdd_tokens": 0,
            "pre_tdd_tokens": 0,
            "total_tokens": 0,
            "tdd_subagent_tokens": 0,
            "work_units": [],
            "git_commits": [],
            "file_modifications": [],
            "test_runs": 0,
            "tdd_method": "unknown",  # "subagent", "inline", "mixed"
            "sessions": [],
        }

        has_subagent_tdd = False
        has_inline_tdd = False

        for sid in session_ids:
            rec = session_records.get(sid)
            if not rec:
                continue

            session_summary = {
                "session_id": sid,
                "total_lines": rec["total_lines"],
                "tdd_boundary_line": rec["tdd_boundary_line"],
                "commands": rec["commands"],
                "git_commits": rec["git_commits"],
                "subagent_count": len(rec["subagents"]),
            }

            # Token usage
            usage = rec["usage"]
            if "tdd" in usage:
                tdd = usage["tdd"]
                pre = usage["pre_tdd"]
                tdd_total = tdd["input"] + tdd["output"] + tdd["cache_read"] + tdd["cache_create"]
                pre_total = pre["input"] + pre["output"] + pre["cache_read"] + pre["cache_create"]
                feat["tdd_tokens"] += tdd_total
                feat["pre_tdd_tokens"] += pre_total
                feat["total_tokens"] += tdd_total + pre_total
                has_inline_tdd = True
                session_summary["tdd_tokens"] = tdd_total
                session_summary["pre_tdd_tokens"] = pre_total
                session_summary["usage"] = {"pre_tdd": pre, "tdd": tdd}
            elif "full_session" in usage:
                full = usage["full_session"]
                full_total = full["input"] + full["output"] + full["cache_read"] + full["cache_create"]
                feat["total_tokens"] += full_total
                session_summary["full_session_tokens"] = full_total
                session_summary["usage"] = {"full_session": full}

            # Subagent TDD
            sa_tdd = usage.get("tdd_subagent_tokens", 0)
            feat["tdd_subagent_tokens"] += sa_tdd
            if sa_tdd > 0:
                has_subagent_tdd = True

            # Work units from subagents
            for sa in rec["subagents"]:
                if sa["stage"] in TDD_STAGES:
                    feat["work_units"].append({
                        "session_id": sid,
                        "description": sa["description"],
                        "stage": sa["stage"],
                        "work_unit": sa["work_unit"],
                        "total_tokens": sa["total_tokens"],
                        "duration_ms": sa["duration_ms"],
                    })

            # Git commits
            feat["git_commits"].extend(rec["git_commits"])

            # File modifications (just count by type for summary)
            test_mods = sum(1 for m in rec["file_modifications"] if m["is_test"])
            impl_mods = sum(1 for m in rec["file_modifications"] if m["is_impl"])
            feat["file_modifications"].append({
                "session_id": sid,
                "test_file_edits": test_mods,
                "impl_file_edits": impl_mods,
                "total_edits": len(rec["file_modifications"]),
            })

            feat["test_runs"] += len(rec["test_runs"])
            feat["sessions"].append(session_summary)

        # Determine TDD method
        if has_subagent_tdd and has_inline_tdd:
            feat["tdd_method"] = "mixed"
        elif has_subagent_tdd:
            feat["tdd_method"] = "subagent"
        elif has_inline_tdd:
            feat["tdd_method"] = "inline"

        # Best TDD token estimate: prefer subagent (more accurate) over inline
        feat["tdd_tokens_best"] = max(feat["tdd_subagent_tokens"], feat["tdd_tokens"])

        features[slug] = feat

    return features


def main():
    parser = argparse.ArgumentParser(
        description="Extract TDD-stage-bounded token usage from JSONL sessions"
    )
    parser.add_argument("project_dir", help="Claude Code project directory")
    parser.add_argument("session_map", help="session-map.json from map-sessions.py")
    parser.add_argument("--output", "-o", default="token-report.json")
    parser.add_argument("--features", "-f", nargs="*", help="Only these slugs")
    args = parser.parse_args()

    project_dir = os.path.expanduser(args.project_dir)
    with open(args.session_map) as f:
        session_map = json.load(f)

    feature_map = session_map["features"]
    target_features = args.features or list(feature_map.keys())

    # Process all sessions for target features
    all_session_ids = set()
    feature_sessions = {}
    for slug in target_features:
        if slug not in feature_map:
            continue
        sids = feature_map[slug]["sessions"]
        feature_sessions[slug] = sids
        all_session_ids.update(sids)

    print(f"Processing {len(all_session_ids)} sessions for {len(feature_sessions)} features...",
          file=sys.stderr)

    session_records = {}
    for i, sid in enumerate(sorted(all_session_ids), 1):
        print(f"  [{i}/{len(all_session_ids)}] {sid[:20]}...", file=sys.stderr, end="\r")
        rec = process_session(project_dir, sid)
        if rec:
            session_records[sid] = rec
    print(f"  Processed {len(session_records)} sessions", file=sys.stderr)

    # Aggregate by feature
    features = aggregate_features(session_records, feature_sessions)

    # Build output
    output = {
        "project_dir": project_dir,
        "features": features,
        "session_details": {
            sid: {
                "total_lines": rec["total_lines"],
                "tdd_boundary_line": rec["tdd_boundary_line"],
                "planning_boundary_line": rec["planning_boundary_line"],
                "commands": rec["commands"],
                "subagents": rec["subagents"],
                "git_commits": rec["git_commits"],
                "file_snapshot_count": len(rec["file_snapshots"]),
                "file_snapshots": rec["file_snapshots"],
                "test_runs": len(rec["test_runs"]),
                "file_modifications_count": len(rec["file_modifications"]),
                "usage": rec["usage"],
            }
            for sid, rec in session_records.items()
        },
    }

    output_path = args.output
    if not os.path.isabs(output_path):
        output_path = os.path.join(os.getcwd(), output_path)

    with open(output_path, "w") as f:
        json.dump(output, f, indent=2)

    print(f"\nToken report written to {output_path}", file=sys.stderr)

    # Summary table
    print("\n=== Feature TDD Token Summary ===\n", file=sys.stderr)
    print(
        f"  {'Feature':<35s} {'Method':>8s} {'TDD best':>12s} "
        f"{'Pre-TDD':>12s} {'Total':>12s} {'Commits':>7s} {'Tests':>5s}",
        file=sys.stderr,
    )
    print(f"  {'─'*35} {'─'*8} {'─'*12} {'─'*12} {'─'*12} {'─'*7} {'─'*5}", file=sys.stderr)
    for slug in sorted(features.keys()):
        f = features[slug]
        print(
            f"  {slug:<35s} {f['tdd_method']:>8s} {f['tdd_tokens_best']:>12,} "
            f"{f['pre_tdd_tokens']:>12,} {f['total_tokens']:>12,} "
            f"{len(f['git_commits']):>7d} {f['test_runs']:>5d}",
            file=sys.stderr,
        )


if __name__ == "__main__":
    main()
