#!/usr/bin/env python3
"""Map Claude Code JSONL sessions to vallorcine features.

Scans all JSONL session files in a Claude Code project directory and produces
a session-map.json with:
  - Branch, timestamps, duration for each session
  - Slash commands found (especially /feature-* with slugs)
  - Token usage totals (input, output, cache_read, cache_create)
  - File-history-snapshot file count
  - Inferred feature slug (from branch name or slash commands)

Usage:
    python3 map-sessions.py <project-dir> [--output session-map.json]

Example:
    python3 map-sessions.py ~/.claude/projects/-home-user-myproject/
"""

import argparse
import json
import os
import re
import sys
from collections import defaultdict

# Slash command patterns in JSONL user messages
COMMAND_NAME_RE = re.compile(r"<command-name>/([^<]+)</command-name>")
COMMAND_ARGS_RE = re.compile(r"<command-args>([^<]*)</command-args>")

# Feature pipeline stages we care about for TDD token extraction
TDD_STAGES = {"feature-test", "feature-implement", "feature-refactor"}
ALL_FEATURE_STAGES = {
    "feature", "feature-quick", "feature-domains", "feature-plan",
    "feature-test", "feature-implement", "feature-refactor",
    "feature-pr", "feature-retro", "feature-complete", "feature-resume",
    "feature-cleanup", "feature-coordinate",
}

# Non-feature commands that tell us what a session was doing
OTHER_COMMANDS = {"research", "architect", "decisions", "kb", "curate",
                  "setup-vallorcine", "upgrade-vallorcine", "project-context"}


def extract_commands(content):
    """Extract slash commands from user message content.

    Only extracts from <command-name> tags (the actual invocation).
    Ignores SKILL.md content blocks that contain command documentation.

    Returns list of (command_name, args) tuples.
    """
    commands = []

    if isinstance(content, str):
        # Only use tagged format — this is the actual command invocation.
        # Raw /command text in content blocks is usually SKILL.md documentation
        # injected by Claude Code, not an actual user command.
        names = COMMAND_NAME_RE.findall(content)
        args_list = COMMAND_ARGS_RE.findall(content)
        for i, name in enumerate(names):
            args = args_list[i].strip() if i < len(args_list) else ""
            # Strip quotes that sometimes wrap slugs in args
            args = args.strip('"').strip("'")
            commands.append((name, args))

    elif isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                commands.extend(extract_commands(block["text"]))

    return commands


def extract_usage(message):
    """Extract token usage from an assistant message.

    Only counts messages with a non-null stop_reason (complete responses,
    not streaming chunks).
    """
    usage = message.get("usage", {})
    stop_reason = message.get("stop_reason")
    if stop_reason is None:
        return None

    return {
        "input": usage.get("input_tokens", 0),
        "output": usage.get("output_tokens", 0),
        "cache_read": usage.get("cache_read_input_tokens", 0),
        "cache_create": usage.get("cache_creation_input_tokens", 0),
    }


# Slug pattern: kebab-case identifiers (lowercase, hyphens, digits)
SLUG_RE = re.compile(r"^[a-z][a-z0-9]+(-[a-z0-9]+)*$")

# Commands that take a slug as their first argument (not a description)
SLUG_COMMANDS = {
    "feature-quick", "feature-domains", "feature-plan",
    "feature-test", "feature-implement", "feature-refactor",
    "feature-pr", "feature-retro", "feature-complete", "feature-resume",
    "feature-cleanup", "feature-coordinate",
}


def _is_slug(text):
    """Check if text looks like a feature slug (kebab-case, not natural language)."""
    return bool(SLUG_RE.match(text)) and len(text) <= 60


def infer_feature_slug(branch, commands):
    """Infer feature slug from branch name and commands.

    Priority:
    1. Slug-taking commands (feature-resume, feature-domains, etc.)
    2. /feature with slug-like first arg (not a description sentence)
    3. Branch name if it matches a known feature pattern
    """
    # Collect slugs from commands that definitively take a slug argument
    slugs_from_commands = set()
    for cmd, args in commands:
        if not args:
            continue

        first_arg = args.split()[0].strip('"').strip("'")
        if first_arg.startswith("-"):
            continue

        if cmd in SLUG_COMMANDS and _is_slug(first_arg):
            slugs_from_commands.add(first_arg)
        elif cmd == "feature" and _is_slug(first_arg):
            # /feature <slug> vs /feature <description>
            # A slug invocation has exactly one non-flag token.
            # A description has multiple non-flag words.
            non_flag_words = [w for w in args.split() if not w.startswith("-")]
            if len(non_flag_words) == 1:
                slugs_from_commands.add(first_arg)
            # else: natural language description, skip

    if slugs_from_commands:
        return sorted(slugs_from_commands)

    # Fall back to branch name
    if branch and branch not in ("main", "master", "unknown"):
        slug = branch.split("/")[-1]
        return [slug]

    return []


def process_session(filepath):
    """Process a single JSONL session file.

    Returns a dict with session metadata, commands, token usage, and
    file-history-snapshot info.
    """
    session_id = os.path.basename(filepath).replace(".jsonl", "")
    result = {
        "session_id": session_id,
        "branch": "unknown",
        "first_timestamp": None,
        "last_timestamp": None,
        "commands": [],  # (command, args) tuples
        "tokens": {
            "input": 0,
            "output": 0,
            "cache_read": 0,
            "cache_create": 0,
        },
        "message_count": 0,  # assistant messages with stop_reason
        "file_snapshot_count": 0,
        "tracked_files": set(),
        "cli_version": None,
        "model": None,
    }

    try:
        with open(filepath) as f:
            for line in f:
                try:
                    entry = json.loads(line)
                except (json.JSONDecodeError, ValueError):
                    continue

                entry_type = entry.get("type")
                timestamp = entry.get("timestamp")

                # Track timestamps
                if timestamp:
                    if result["first_timestamp"] is None:
                        result["first_timestamp"] = timestamp
                    result["last_timestamp"] = timestamp

                # Branch from user entries
                if entry_type == "user":
                    if result["branch"] == "unknown" and entry.get("gitBranch"):
                        result["branch"] = entry["gitBranch"]
                    if result["cli_version"] is None and entry.get("version"):
                        result["cli_version"] = entry["version"]

                    # Extract commands
                    content = entry.get("message", {}).get("content", "")
                    commands = extract_commands(content)
                    result["commands"].extend(commands)

                # Token usage from assistant entries
                elif entry_type == "assistant":
                    message = entry.get("message", {})
                    if result["model"] is None and message.get("model"):
                        result["model"] = message["model"]

                    usage = extract_usage(message)
                    if usage:
                        result["message_count"] += 1
                        for key in ("input", "output", "cache_read", "cache_create"):
                            result["tokens"][key] += usage[key]

                # File history snapshots
                elif entry_type == "file-history-snapshot":
                    snapshot = entry.get("snapshot", {})
                    backups = snapshot.get("trackedFileBackups", {})
                    if backups:
                        result["file_snapshot_count"] += 1
                        for path in backups:
                            result["tracked_files"].add(path)

    except (OSError, IOError) as e:
        print(f"  Warning: could not read {filepath}: {e}", file=sys.stderr)
        return None

    # Convert set to sorted list for JSON serialization
    result["tracked_files"] = sorted(result["tracked_files"])

    return result


def load_aliases(alias_path):
    """Load feature slug aliases from a JSON file.

    Returns a dict mapping variant slug to canonical slug.
    Entries with null values are excluded features (non-feature branches).
    """
    if not alias_path or not os.path.exists(alias_path):
        return {}
    with open(alias_path) as f:
        return json.load(f)


def build_feature_map(sessions, aliases=None):
    """Group sessions by inferred feature slug.

    Returns a dict mapping feature slug to list of session summaries,
    plus an "unmatched" list for sessions that couldn't be mapped.
    """
    if aliases is None:
        aliases = {}
    features = defaultdict(lambda: {
        "sessions": [],
        "branches": set(),
        "total_tokens": {"input": 0, "output": 0, "cache_read": 0, "cache_create": 0},
        "total_messages": 0,
        "first_timestamp": None,
        "last_timestamp": None,
        "all_commands": [],
        "tracked_files": set(),
    })
    unmatched = []

    for session in sessions:
        commands = session["commands"]
        slugs = infer_feature_slug(session["branch"], commands)

        if not slugs:
            unmatched.append(session["session_id"])
            continue

        # Apply aliases: resolve to canonical slug, skip nulls (excluded)
        resolved = []
        for slug in slugs:
            if slug in aliases:
                canonical = aliases[slug]
                if canonical is not None:
                    resolved.append(canonical)
                # null = excluded (non-feature branch), skip entirely
            else:
                resolved.append(slug)
        slugs = resolved

        if not slugs:
            unmatched.append(session["session_id"])
            continue

        for slug in slugs:
            feat = features[slug]
            feat["sessions"].append(session["session_id"])
            feat["branches"].add(session["branch"])
            for key in ("input", "output", "cache_read", "cache_create"):
                feat["total_tokens"][key] += session["tokens"][key]
            feat["total_messages"] += session["message_count"]
            feat["all_commands"].extend(
                f"/{cmd} {args}".strip() for cmd, args in commands
            )
            feat["tracked_files"].update(session["tracked_files"])

            ts = session["first_timestamp"]
            if ts and (feat["first_timestamp"] is None or ts < feat["first_timestamp"]):
                feat["first_timestamp"] = ts
            ts = session["last_timestamp"]
            if ts and (feat["last_timestamp"] is None or ts > feat["last_timestamp"]):
                feat["last_timestamp"] = ts

    # Convert sets for JSON
    for slug, feat in features.items():
        feat["branches"] = sorted(feat["branches"])
        feat["tracked_files"] = sorted(feat["tracked_files"])
        # Deduplicate commands while preserving order
        seen = set()
        unique_commands = []
        for cmd in feat["all_commands"]:
            if cmd not in seen:
                seen.add(cmd)
                unique_commands.append(cmd)
        feat["all_commands"] = unique_commands

    return dict(features), unmatched


def main():
    parser = argparse.ArgumentParser(
        description="Map Claude Code JSONL sessions to vallorcine features"
    )
    parser.add_argument(
        "project_dir",
        help="Path to Claude Code project directory containing .jsonl files",
    )
    parser.add_argument(
        "--output", "-o",
        default="session-map.json",
        help="Output file path (default: session-map.json)",
    )
    parser.add_argument(
        "--aliases", "-a",
        default=None,
        help="Path to feature-aliases.json for slug merging/exclusion",
    )
    args = parser.parse_args()

    project_dir = os.path.expanduser(args.project_dir)
    if not os.path.isdir(project_dir):
        print(f"Error: {project_dir} is not a directory", file=sys.stderr)
        sys.exit(1)

    # Find all JSONL files
    jsonl_files = sorted(
        f for f in os.listdir(project_dir) if f.endswith(".jsonl")
    )
    print(f"Found {len(jsonl_files)} JSONL session files", file=sys.stderr)

    # Process each session
    sessions = []
    for i, filename in enumerate(jsonl_files, 1):
        filepath = os.path.join(project_dir, filename)
        print(f"  [{i}/{len(jsonl_files)}] {filename[:40]}...", file=sys.stderr, end="\r")
        session = process_session(filepath)
        if session:
            sessions.append(session)
    print(f"  Processed {len(sessions)} sessions successfully", file=sys.stderr)

    # Load aliases and build feature map
    aliases = load_aliases(args.aliases)
    feature_map, unmatched = build_feature_map(sessions, aliases)
    print(f"  Mapped to {len(feature_map)} features, {len(unmatched)} unmatched sessions",
          file=sys.stderr)

    # Build output
    output = {
        "project_dir": project_dir,
        "total_sessions": len(sessions),
        "features": feature_map,
        "unmatched_sessions": unmatched,
        "sessions": {
            s["session_id"]: {
                "branch": s["branch"],
                "first_timestamp": s["first_timestamp"],
                "last_timestamp": s["last_timestamp"],
                "commands": [f"/{cmd} {args}".strip() for cmd, args in s["commands"]],
                "tokens": s["tokens"],
                "message_count": s["message_count"],
                "file_snapshot_count": s["file_snapshot_count"],
                "tracked_file_count": len(s["tracked_files"]),
                "cli_version": s["cli_version"],
                "model": s["model"],
            }
            for s in sessions
        },
    }

    # Write output
    output_path = args.output
    if not os.path.isabs(output_path):
        output_path = os.path.join(os.getcwd(), output_path)

    with open(output_path, "w") as f:
        json.dump(output, f, indent=2)

    print(f"\nSession map written to {output_path}", file=sys.stderr)

    # Print summary
    print("\n=== Feature Summary ===\n", file=sys.stderr)
    for slug in sorted(feature_map.keys()):
        feat = feature_map[slug]
        tokens = feat["total_tokens"]
        billable = tokens["input"] + tokens["cache_create"]
        print(
            f"  {slug:40s}  {len(feat['sessions']):2d} sessions  "
            f"{feat['total_messages']:4d} msgs  "
            f"billable_in={billable:>10,}  out={tokens['output']:>10,}",
            file=sys.stderr,
        )

    if unmatched:
        print(f"\n  {len(unmatched)} unmatched sessions (main/unknown branch, no feature commands)",
              file=sys.stderr)


if __name__ == "__main__":
    main()
