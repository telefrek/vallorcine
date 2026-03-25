#!/usr/bin/env python3
"""Extract the end-of-planning file state from JSONL sessions.

Parses session JSONL files to find the point where planning completes
(stubs written, work-plan created) and extracts the file operations needed
to reconstruct that state from a git checkout.

Produces a state overlay directory that can be applied on top of a
parent_sha checkout to get the exact end-of-planning state.

Usage:
    python3 extract-planning-state.py \
        --project-dir ~/.claude/projects/<project-hash> \
        --sessions <session-id> [<session-id> ...] \
        --feature <slug> \
        --output-dir planning-state/<slug>/
"""

import argparse
import json
import os
import re
import sys


COMMAND_NAME_RE = re.compile(r"<command-name>/([^<]+)</command-name>")


def find_planning_boundary(lines):
    """Find the line number where planning completes.

    Planning is complete when:
    - work-plan.md has been written
    - Stub files have been written (Write to src/main paths)
    - No test files have been written yet

    Returns (boundary_line, planning_ops) where planning_ops is the list of
    file operations up to that point.
    """
    ops = []
    work_plan_written = False
    first_test_line = None

    for ln, line in enumerate(lines):
        try:
            entry = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue

        if entry.get("type") != "assistant":
            continue

        content = entry.get("message", {}).get("content", [])
        if not isinstance(content, list):
            continue

        for block in content:
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue

            name = block.get("name", "")
            inp = block.get("input", {})

            if name == "Write":
                path = inp.get("file_path", "")
                file_content = inp.get("content", "")
                fname = os.path.basename(path)

                # Detect test files — this marks end of planning
                if _is_test_file(fname):
                    if first_test_line is None:
                        first_test_line = ln
                    continue

                ops.append({
                    "line": ln,
                    "op": "write",
                    "path": path,
                    "content": file_content,
                })

                if "work-plan" in fname:
                    work_plan_written = True

            elif name == "Edit":
                path = inp.get("file_path", "")
                fname = os.path.basename(path)

                if _is_test_file(fname):
                    if first_test_line is None:
                        first_test_line = ln
                    continue

                ops.append({
                    "line": ln,
                    "op": "edit",
                    "path": path,
                    "old_string": inp.get("old_string", ""),
                    "new_string": inp.get("new_string", ""),
                    "replace_all": inp.get("replace_all", False),
                })

    # Boundary is just before the first test file, or end of session if no tests
    boundary = first_test_line if first_test_line is not None else len(lines)

    # Filter ops to only those before the boundary
    planning_ops = [op for op in ops if op["line"] < boundary]

    return boundary, planning_ops, work_plan_written


def _is_test_file(fname):
    """Check if a filename is a test file."""
    return bool(re.search(
        r"(Test\.java|_test\.py|\.test\.[jt]sx?|_test\.go|_spec\.rb|\.spec\.[jt]sx?|Tests?\.cs)$",
        fname,
    ))


def _is_feature_file(path):
    """Check if a path is a .feature/ managed file (not source code)."""
    return ".feature/" in path or ".feature\\" in path


def classify_ops(ops):
    """Classify operations into source stubs vs feature-dir files."""
    stubs = []
    feature_files = []
    other = []

    for op in ops:
        path = op["path"]
        if _is_feature_file(path):
            feature_files.append(op)
        elif "src/main" in path or "src/" in path:
            stubs.append(op)
        else:
            other.append(op)

    return stubs, feature_files, other


def write_overlay(ops, output_dir, project_root=None):
    """Write file operations as an overlay directory.

    For Write ops: write the file content directly.
    For Edit ops: write a .edit.json file with the edit instructions.

    The overlay can be applied to a checkout with apply-overlay.py.
    """
    os.makedirs(output_dir, exist_ok=True)

    manifest = []

    for op in ops:
        path = op["path"]

        # Make path relative if absolute
        if project_root and path.startswith(project_root):
            relpath = os.path.relpath(path, project_root)
        elif path.startswith("/"):
            # Try to extract relative path from common patterns
            # /home/user/Code/github/org/project/modules/...
            parts = path.split("/")
            # Find the project root marker
            for i, part in enumerate(parts):
                if part in ("modules", "src", ".feature", ".claude",
                            ".decisions", ".kb", ".curate"):
                    relpath = "/".join(parts[i:])
                    break
            else:
                relpath = os.path.basename(path)
        else:
            relpath = path

        if op["op"] == "write":
            # Write the file content directly
            out_path = os.path.join(output_dir, "files", relpath)
            os.makedirs(os.path.dirname(out_path), exist_ok=True)
            with open(out_path, "w") as f:
                f.write(op["content"])
            manifest.append({
                "op": "write",
                "path": relpath,
                "line": op["line"],
                "size": len(op["content"]),
            })

        elif op["op"] == "edit":
            # Write edit instructions
            edit_id = f"L{op['line']:04d}"
            out_path = os.path.join(output_dir, "edits", f"{edit_id}-{os.path.basename(relpath)}.json")
            os.makedirs(os.path.dirname(out_path), exist_ok=True)
            with open(out_path, "w") as f:
                json.dump({
                    "path": relpath,
                    "old_string": op["old_string"],
                    "new_string": op["new_string"],
                    "replace_all": op.get("replace_all", False),
                }, f, indent=2)
            manifest.append({
                "op": "edit",
                "path": relpath,
                "edit_file": os.path.relpath(out_path, output_dir),
                "line": op["line"],
            })

    # Write manifest
    with open(os.path.join(output_dir, "manifest.json"), "w") as f:
        json.dump({
            "operations": manifest,
            "total_ops": len(manifest),
        }, f, indent=2)

    return manifest


def main():
    parser = argparse.ArgumentParser(
        description="Extract end-of-planning file state from JSONL sessions"
    )
    parser.add_argument("--project-dir", required=True,
                        help="Claude Code project directory with JSONL files")
    parser.add_argument("--sessions", nargs="+", required=True,
                        help="Session IDs to scan (in chronological order)")
    parser.add_argument("--feature", required=True,
                        help="Feature slug")
    parser.add_argument("--output-dir", required=True,
                        help="Output directory for the state overlay")
    args = parser.parse_args()

    project_dir = os.path.expanduser(args.project_dir)
    slug = args.feature

    print(f"Extracting planning state for {slug}...", file=sys.stderr)

    all_ops = []
    boundary_found = False

    for sid in args.sessions:
        # Process main session JSONL
        jsonl_path = os.path.join(project_dir, f"{sid}.jsonl")
        if not os.path.exists(jsonl_path):
            print(f"  Warning: {sid}.jsonl not found, skipping", file=sys.stderr)
            continue

        with open(jsonl_path) as f:
            lines = f.readlines()

        boundary, ops, work_plan_written = find_planning_boundary(lines)
        print(f"  {sid[:12]}: {len(ops)} ops, boundary=L{boundary}, "
              f"work-plan={'yes' if work_plan_written else 'no'}", file=sys.stderr)

        all_ops.extend(ops)
        if work_plan_written:
            boundary_found = True

        # Also scan subagent JSONL files for planning-related work
        sub_dir = os.path.join(project_dir, sid, "subagents")
        if os.path.isdir(sub_dir):
            for fname in sorted(os.listdir(sub_dir)):
                if not fname.endswith(".jsonl"):
                    continue
                # Check meta for planning-related description
                meta_path = os.path.join(sub_dir, fname.replace(".jsonl", ".meta.json"))
                desc = ""
                if os.path.exists(meta_path):
                    try:
                        with open(meta_path) as mf:
                            desc = json.load(mf).get("description", "")
                    except (json.JSONDecodeError, ValueError):
                        pass

                is_planning = any(kw in desc.lower() for kw in
                                  ["stub", "work plan", "write plan", "plan and"])
                if not is_planning:
                    continue

                sub_path = os.path.join(sub_dir, fname)
                with open(sub_path) as f:
                    sub_lines = f.readlines()

                # For planning subagents, ALL source writes are stubs
                sub_ops = []
                for ln, line in enumerate(sub_lines):
                    try:
                        entry = json.loads(line)
                        if entry.get("type") != "assistant":
                            continue
                        content = entry.get("message", {}).get("content", [])
                        if not isinstance(content, list):
                            continue
                        for block in content:
                            if not isinstance(block, dict) or block.get("type") != "tool_use":
                                continue
                            name = block.get("name", "")
                            inp = block.get("input", {})
                            path = inp.get("file_path", "")
                            is_source = ("src/main" in path or "module-info" in path)
                            is_feature = ".feature/" in path
                            is_decisions = ".decisions/" in path
                            is_kb = ".kb/" in path

                            if not (is_source or is_feature or is_decisions or is_kb):
                                continue

                            if name == "Write":
                                sub_ops.append({
                                    "line": ln, "op": "write",
                                    "path": path, "content": inp.get("content", ""),
                                })
                            elif name == "Edit":
                                sub_ops.append({
                                    "line": ln, "op": "edit",
                                    "path": path,
                                    "old_string": inp.get("old_string", ""),
                                    "new_string": inp.get("new_string", ""),
                                    "replace_all": inp.get("replace_all", False),
                                })
                    except (json.JSONDecodeError, ValueError):
                        continue

                if sub_ops:
                    src_count = sum(1 for o in sub_ops
                                    if "src/main" in o.get("path", "")
                                    or "module-info" in o.get("path", ""))
                    print(f"    subagent {fname[:25]}: {len(sub_ops)} ops "
                          f"({src_count} source), desc=\"{desc}\"", file=sys.stderr)
                    all_ops.extend(sub_ops)

                    # Check if subagent wrote work-plan
                    for o in sub_ops:
                        if "work-plan" in o.get("path", ""):
                            boundary_found = True

    if not boundary_found:
        print(f"  Warning: work-plan.md not found in any session or subagent",
              file=sys.stderr)

    # Classify operations
    stubs, feature_files, other = classify_ops(all_ops)

    print(f"\n  Planning operations:", file=sys.stderr)
    print(f"    Source stubs: {len(stubs)}", file=sys.stderr)
    print(f"    Feature files: {len(feature_files)} (status.md, brief.md, etc.)", file=sys.stderr)
    print(f"    Other: {len(other)}", file=sys.stderr)

    # Write overlay — only stubs and feature files needed for greenfield
    manifest = write_overlay(all_ops, args.output_dir)

    print(f"\n  Overlay written to {args.output_dir}/", file=sys.stderr)
    print(f"  {len(manifest)} files/edits in manifest", file=sys.stderr)
    print(f"\n  To apply:", file=sys.stderr)
    print(f"    python3 apply-overlay.py --checkout <path> --overlay {args.output_dir}",
          file=sys.stderr)


if __name__ == "__main__":
    main()
