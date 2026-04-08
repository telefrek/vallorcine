#!/usr/bin/env python3
"""Analyze token usage for a Claude Code session.

Point at a session JSONL log and get:
  - Per-message token breakdown (input, output, cache read, cache create)
  - Activity classification (reads, writes, edits, builds, text)
  - Top N messages by input and output tokens
  - Cumulative token growth curve
  - Summary stats

Usage:
    # By session ID (searches all project dirs):
    python3 analyze-session.py <session-id>

    # By JSONL file path:
    python3 analyze-session.py /path/to/session.jsonl

    # Most recent session for a project:
    python3 analyze-session.py --recent <project-path-fragment>
    python3 analyze-session.py --recent jlsm
    python3 analyze-session.py --recent vallorcine

    # Compare two sessions:
    python3 analyze-session.py <session1> --compare <session2>

    # Show only summary (no per-message table):
    python3 analyze-session.py <session> --summary

    # Search for sessions mentioning a keyword:
    python3 analyze-session.py --search "striped-block-cache"
    python3 analyze-session.py --search "striped-block-cache" --project jlsm
"""

import argparse
import json
import os
import sys
from pathlib import Path


def find_session_file(session_id_or_path, project_fragment=None):
    """Find a session JSONL file by ID, path, or most recent."""
    # Direct path
    if os.path.isfile(session_id_or_path):
        return session_id_or_path

    # Search project dirs
    claude_dir = Path.home() / ".claude" / "projects"
    if not claude_dir.exists():
        return None

    for proj_dir in claude_dir.iterdir():
        if not proj_dir.is_dir():
            continue
        if project_fragment and project_fragment not in proj_dir.name:
            continue

        candidate = proj_dir / f"{session_id_or_path}.jsonl"
        if candidate.exists():
            return str(candidate)

    return None


def find_recent_session(project_fragment):
    """Find the most recent session for a project."""
    claude_dir = Path.home() / ".claude" / "projects"
    if not claude_dir.exists():
        return None

    best = None
    best_mtime = 0

    for proj_dir in claude_dir.iterdir():
        if not proj_dir.is_dir():
            continue
        if project_fragment not in proj_dir.name:
            continue

        for f in proj_dir.glob("*.jsonl"):
            mtime = f.stat().st_mtime
            if mtime > best_mtime:
                best_mtime = mtime
                best = str(f)

    return best


def search_sessions(keyword, project_fragment=None):
    """Search for sessions containing a keyword in the first 10KB."""
    claude_dir = Path.home() / ".claude" / "projects"
    if not claude_dir.exists():
        return []

    matches = []
    for proj_dir in claude_dir.iterdir():
        if not proj_dir.is_dir():
            continue
        if project_fragment and project_fragment not in proj_dir.name:
            continue

        for f in sorted(proj_dir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True):
            try:
                with open(f) as fh:
                    header = fh.read(10000)
                if keyword in header:
                    matches.append({
                        "path": str(f),
                        "project": proj_dir.name,
                        "session_id": f.stem,
                        "size": f.stat().st_size,
                        "mtime": f.stat().st_mtime,
                    })
            except OSError:
                continue

    return matches


def parse_session(filepath):
    """Parse a session JSONL and extract per-message token data."""
    messages = []

    with open(filepath) as f:
        for line_num, line in enumerate(f):
            try:
                entry = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue

            if entry.get("type") != "assistant":
                continue

            msg = entry.get("message", {})
            usage = msg.get("usage", {})
            content = msg.get("content", [])
            stop = msg.get("stop_reason")

            if stop is None:
                continue

            # Classify tool calls
            tool_calls = []
            text_len = 0

            for block in (content if isinstance(content, list) else []):
                if not isinstance(block, dict):
                    continue

                if block.get("type") == "tool_use":
                    name = block.get("name", "")
                    inp = block.get("input", {})
                    detail = ""

                    if name == "Read":
                        fp = inp.get("file_path", "")
                        detail = fp.split("/")[-1] if fp else ""
                    elif name in ("Write", "Edit"):
                        fp = inp.get("file_path", "")
                        detail = fp.split("/")[-1] if fp else ""
                    elif name == "Bash":
                        detail = inp.get("command", "")[:60]
                    elif name == "Agent":
                        detail = inp.get("description", "")[:40]
                    elif name == "Glob":
                        detail = inp.get("pattern", "")[:40]
                    elif name == "Grep":
                        detail = inp.get("pattern", "")[:40]

                    tool_calls.append({"name": name, "detail": detail})

                elif block.get("type") == "text":
                    text_len += len(block.get("text", ""))

            inp_tok = usage.get("input_tokens", 0)
            out_tok = usage.get("output_tokens", 0)
            cache_read = usage.get("cache_read_input_tokens", 0)
            cache_create = usage.get("cache_creation_input_tokens", 0)

            messages.append({
                "line": line_num,
                "input": inp_tok,
                "output": out_tok,
                "cache_read": cache_read,
                "cache_create": cache_create,
                "billable": inp_tok + out_tok,
                "tools": tool_calls,
                "text_len": text_len,
            })

    return messages


def classify_activity(tools):
    """Classify a message's activity based on its tool calls."""
    names = [t["name"] for t in tools]
    details = " ".join(t["detail"] for t in tools)

    if not names:
        return "think"

    if "Agent" in names:
        return "subagent"

    has_read = "Read" in names
    has_write = "Write" in names or "Edit" in names
    has_bash = "Bash" in names
    has_search = "Glob" in names or "Grep" in names

    if has_bash and ("gradlew" in details or "test" in details or "check" in details):
        return "build"
    if has_bash and "git" in details:
        return "git"
    if has_write and "AdversarialTest" in details:
        return "test-write"
    if has_write and ("spec-analysis" in details or "known_issues" in details):
        return "analysis-write"
    if has_write and ".kb/" in details or "CLAUDE.md" in details:
        return "kb"
    if has_write:
        return "code-write"
    if has_read:
        return "read"
    if has_search:
        return "search"
    if has_bash:
        return "bash"

    return "other"


def format_tools(tools, max_len=60):
    """Format tool calls for display."""
    parts = []
    for t in tools[:3]:
        if t["detail"]:
            parts.append("{}({})".format(t["name"], t["detail"][:30]))
        else:
            parts.append(t["name"])
    result = ", ".join(parts)
    if len(tools) > 3:
        result += " +{} more".format(len(tools) - 3)
    return result[:max_len]


def print_timeline(messages):
    """Print per-message token timeline."""
    print("{:>3} {:>5} {:>8} {:>7} {:>8} {:>8} {:>9}  {}".format(
        "#", "Line", "Input", "Output", "Cache$", "CacheR", "Billable", "Tools/Activity"))
    print("{} {} {} {} {} {} {}  {}".format(
        "---", "-----", "--------", "-------", "--------", "--------", "---------",
        "-" * 50))

    for i, m in enumerate(messages):
        tools_str = format_tools(m["tools"])
        if not tools_str and m["text_len"] > 0:
            tools_str = "[text: {} chars]".format(m["text_len"])

        print("{:>3} {:>5} {:>8,} {:>7,} {:>8,} {:>8,} {:>9,}  {}".format(
            i, m["line"], m["input"], m["output"],
            m["cache_create"], m["cache_read"], m["billable"], tools_str))


def print_summary(messages, label=""):
    """Print summary statistics."""
    if not messages:
        print("No messages found.")
        return

    total_input = sum(m["input"] for m in messages)
    total_output = sum(m["output"] for m in messages)
    total_billable = total_input + total_output
    total_cache_read = sum(m["cache_read"] for m in messages)
    total_cache_create = sum(m["cache_create"] for m in messages)
    max_output = max(m["output"] for m in messages)
    max_output_idx = next(i for i, m in enumerate(messages) if m["output"] == max_output)
    max_input = max(m["input"] for m in messages)
    max_input_idx = next(i for i, m in enumerate(messages) if m["input"] == max_input)

    # Activity breakdown
    activities = {}
    for m in messages:
        act = classify_activity(m["tools"])
        if act not in activities:
            activities[act] = {"count": 0, "billable": 0}
        activities[act]["count"] += 1
        activities[act]["billable"] += m["billable"]

    if label:
        print("\n=== {} ===".format(label))
    print("\n{:>20}: {:>10,}".format("Total messages", len(messages)))
    print("{:>20}: {:>10,}".format("Input tokens", total_input))
    print("{:>20}: {:>10,}".format("Output tokens", total_output))
    print("{:>20}: {:>10,}".format("Billable tokens", total_billable))
    print("{:>20}: {:>10,}".format("Cache read", total_cache_read))
    print("{:>20}: {:>10,}".format("Cache create", total_cache_create))
    print("{:>20}: {:>10,}  (#{}, {})".format(
        "Max single output", max_output, max_output_idx,
        format_tools(messages[max_output_idx]["tools"])))
    print("{:>20}: {:>10,}  (#{}, {})".format(
        "Max single input", max_input, max_input_idx,
        format_tools(messages[max_input_idx]["tools"])))

    print("\n  Activity breakdown:")
    print("  {:<20} {:>5} {:>10}".format("Activity", "Msgs", "Billable"))
    print("  {} {} {}".format("-" * 20, "-" * 5, "-" * 10))
    for act in sorted(activities, key=lambda a: activities[a]["billable"], reverse=True):
        print("  {:<20} {:>5} {:>10,}".format(
            act, activities[act]["count"], activities[act]["billable"]))

    # Top 3 by output
    print("\n  Top 3 by output tokens:")
    by_output = sorted(enumerate(messages), key=lambda x: x[1]["output"], reverse=True)
    for idx, m in by_output[:3]:
        print("    #{}: {:>7,} output — {}".format(idx, m["output"], format_tools(m["tools"])))


def main():
    parser = argparse.ArgumentParser(description="Analyze Claude Code session token usage")
    parser.add_argument("session", nargs="?", help="Session ID, JSONL path, or omit with --recent/--search")
    parser.add_argument("--recent", metavar="PROJECT", help="Most recent session for project (fragment match)")
    parser.add_argument("--search", metavar="KEYWORD", help="Search sessions for keyword")
    parser.add_argument("--project", metavar="FRAGMENT", help="Filter to project (with --search)")
    parser.add_argument("--compare", metavar="SESSION2", help="Compare with another session")
    parser.add_argument("--summary", action="store_true", help="Summary only, skip per-message table")
    parser.add_argument("--top", type=int, default=5, help="Number of top messages to show")
    args = parser.parse_args()

    # Search mode
    if args.search:
        matches = search_sessions(args.search, args.project)
        if not matches:
            print("No sessions found matching '{}'".format(args.search), file=sys.stderr)
            sys.exit(1)
        print("Sessions matching '{}':".format(args.search))
        for m in matches[:10]:
            print("  {} ({:,} bytes) — {}".format(m["session_id"][:20], m["size"], m["project"]))
        if len(matches) == 1:
            filepath = matches[0]["path"]
            print("\nAnalyzing the single match:\n")
        else:
            print("\nRe-run with a session ID to analyze.", file=sys.stderr)
            sys.exit(0)

    # Recent mode
    elif args.recent:
        filepath = find_recent_session(args.recent)
        if not filepath:
            print("No sessions found for project matching '{}'".format(args.recent), file=sys.stderr)
            sys.exit(1)
        print("Most recent session: {}\n".format(os.path.basename(filepath)))

    # Direct session
    elif args.session:
        filepath = find_session_file(args.session)
        if not filepath:
            print("Session not found: {}".format(args.session), file=sys.stderr)
            sys.exit(1)

    else:
        parser.print_help()
        sys.exit(1)

    # Parse and display
    messages = parse_session(filepath)

    if not args.summary:
        print_timeline(messages)

    print_summary(messages, os.path.basename(filepath).replace(".jsonl", ""))

    # Compare mode
    if args.compare:
        filepath2 = find_session_file(args.compare)
        if not filepath2:
            print("\nComparison session not found: {}".format(args.compare), file=sys.stderr)
            sys.exit(1)

        messages2 = parse_session(filepath2)
        if not args.summary:
            print("\n" + "=" * 80 + "\n")
            print_timeline(messages2)
        print_summary(messages2, os.path.basename(filepath2).replace(".jsonl", ""))

        # Comparison
        b1 = sum(m["billable"] for m in messages)
        b2 = sum(m["billable"] for m in messages2)
        print("\n--- Comparison ---")
        print("  Session 1: {:>10,} billable, {:>3} messages".format(b1, len(messages)))
        print("  Session 2: {:>10,} billable, {:>3} messages".format(b2, len(messages2)))
        if b1 > 0:
            print("  Ratio:     {:.2f}x".format(b2 / b1))


if __name__ == "__main__":
    main()
