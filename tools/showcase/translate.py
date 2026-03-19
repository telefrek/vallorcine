#!/usr/bin/env python3
"""Translate Claude Code JSONL session logs into structured story JSON.

Reads raw session JSONL files from ~/.claude/projects/ and produces an
intermediate JSON format suitable for rendering as markdown articles or
interactive web replays.

Usage:
    # Feature story — stitches all sessions for a feature slug
    python translate.py --feature encrypt-memory-data --project jlsm

    # Single session — auto-detects story type
    python translate.py --session 43347015-... --project jlsm

    # Explicit project path
    python translate.py --feature encrypt-memory-data --project-path ~/.claude/projects/-home-user-code-jlsm
"""

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class TokenUsage:
    input: int = 0
    output: int = 0
    cache_read: int = 0
    cache_create: int = 0

    def add(self, other: "TokenUsage"):
        self.input += other.input
        self.output += other.output
        self.cache_read += other.cache_read
        self.cache_create += other.cache_create


@dataclass
class Moment:
    type: str  # user_prompt, user_response, agent_prose, action, stage_transition,
               # session_break, subagent_summary, subagent_detail, escalation,
               # refactor_finding, test_result
    timestamp: str = ""
    content: str = ""
    interesting: bool = False
    # action-specific
    verb: str = ""           # wrote, edited, ran, committed
    target: str = ""         # file path or command
    summary: str = ""        # one-line summary
    # session_break-specific
    reason: str = ""         # crash, context_overflow, user_ended
    gap_duration_ms: int = 0
    state_at_break: str = ""
    recovery_method: str = ""
    # subagent-specific
    agent: str = ""
    description: str = ""
    duration_ms: int = 0
    files_written: list = field(default_factory=list)
    detail_moments: list = field(default_factory=list)  # full moments for interactive


@dataclass
class Chapter:
    stage: str
    command: str = ""
    title: str = ""
    started: str = ""
    duration_ms: int = 0
    tokens: TokenUsage = field(default_factory=TokenUsage)
    moments: list = field(default_factory=list)


@dataclass
class Story:
    story_type: str  # feature, curation, research, architect
    title: str = ""
    project: str = ""
    branch: str = ""
    sessions: list = field(default_factory=list)
    started: str = ""
    duration_ms: int = 0
    tokens: TokenUsage = field(default_factory=TokenUsage)
    model: str = ""
    chapters: list = field(default_factory=list)


# ---------------------------------------------------------------------------
# JSONL parsing
# ---------------------------------------------------------------------------

def load_jsonl(path: str) -> list[dict]:
    """Load a JSONL file, skipping malformed lines."""
    lines = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                lines.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return lines


def extract_command(content: str) -> tuple[Optional[str], Optional[str]]:
    """Extract command name and args from a user message with command tags."""
    name_match = re.search(r"<command-name>([^<]+)</command-name>", content)
    args_match = re.search(r"<command-args>(.*?)</command-args>", content, re.DOTALL)
    name = name_match.group(1) if name_match else None
    args = args_match.group(1).strip().strip('"') if args_match else None
    return name, args


def detect_story_type(commands: list[str]) -> str:
    """Determine story type from commands found in sessions."""
    for cmd in commands:
        if cmd.startswith("/feature"):
            return "feature"
        if cmd == "/curate":
            return "curation"
        if cmd == "/research":
            return "research"
        if cmd == "/architect":
            return "architect"
    return "feature"  # default


def extract_usage(msg: dict) -> TokenUsage:
    """Extract token usage from an assistant message."""
    usage = msg.get("message", {}).get("usage", {})
    inp = usage.get("input_tokens", 0)
    out = usage.get("output_tokens", 0)
    cache_read = usage.get("cache_read_input_tokens", 0)
    cache_create = usage.get("cache_creation_input_tokens", 0)
    return TokenUsage(input=inp, output=out,
                      cache_read=cache_read, cache_create=cache_create)


# ---------------------------------------------------------------------------
# Interesting moment detection
# ---------------------------------------------------------------------------

ESCALATION_PATTERNS = [
    r"escalat",
    r"contract conflict",
    r"can't satisfy",
    r"cannot satisfy",
    r"test.*fail",
    r"doesn't match.*contract",
]

REFACTOR_FINDING_PATTERNS = [
    r"structural (issue|concern)",
    r"security (issue|concern|finding)",
    r"flagged for review",
    r"pause.*human",
    r"checklist item 2[cd]",
]

RETRY_PATTERNS = [
    r"cycle [2-9]",
    r"retry",
    r"second attempt",
    r"trying again",
]


def is_interesting(text: str) -> tuple[bool, Optional[str]]:
    """Check if text contains interesting moment signals.
    Returns (is_interesting, reason) tuple."""
    text_lower = text.lower()
    for pattern in ESCALATION_PATTERNS:
        if re.search(pattern, text_lower):
            return True, "escalation"
    for pattern in REFACTOR_FINDING_PATTERNS:
        if re.search(pattern, text_lower):
            return True, "refactor_finding"
    for pattern in RETRY_PATTERNS:
        if re.search(pattern, text_lower):
            return True, "retry"
    return False, None


# ---------------------------------------------------------------------------
# Action summarization
# ---------------------------------------------------------------------------

def _is_bookkeeping_file(path: str) -> bool:
    """Check if a file is internal bookkeeping (not interesting for articles)."""
    basename = os.path.basename(path)
    # status.md and CLAUDE.md index files are internal pipeline state
    if basename == "status.md":
        return True
    if basename == "CLAUDE.md" and any(d in path for d in [".kb/", ".decisions/"]):
        return True
    return False


def summarize_tool_use(name: str, input_data: dict) -> Optional[Moment]:
    """Convert a tool_use block into an action moment, or None if not worth showing."""
    if name == "Write":
        path = input_data.get("file_path", "")
        if _is_bookkeeping_file(path):
            return None
        short = os.path.basename(path) if path else "file"
        return Moment(
            type="action", verb="wrote", target=path,
            summary=f"Wrote {short}",
        )
    elif name == "Edit":
        path = input_data.get("file_path", "")
        if _is_bookkeeping_file(path):
            return None
        short = os.path.basename(path) if path else "file"
        return Moment(
            type="action", verb="edited", target=path,
            summary=f"Edited {short}",
        )
    elif name == "Bash":
        cmd = input_data.get("command", "")
        desc = input_data.get("description", "")
        # Only surface interesting bash commands
        if any(kw in cmd for kw in ["git commit", "git push", "npm test", "pytest",
                                     "go test", "cargo test", "make test"]):
            return Moment(
                type="action", verb="ran", target=cmd[:120],
                summary=desc or f"Ran: {cmd[:80]}",
            )
        # Test runners detected by description
        if desc and any(kw in desc.lower() for kw in ["test", "commit", "push"]):
            return Moment(
                type="action", verb="ran", target=cmd[:120],
                summary=desc,
            )
        return None
    elif name == "Skill":
        skill = input_data.get("skill", "")
        return Moment(
            type="stage_transition",
            summary=f"Invoked /{skill}",
        )
    elif name == "Agent":
        desc = input_data.get("description", "")
        return Moment(
            type="subagent_summary", agent="subagent",
            description=desc,
            summary=f"Delegated: {desc}",
        )
    # Skip Read, Glob, Grep, ToolSearch — research noise
    return None


# ---------------------------------------------------------------------------
# Subagent processing
# ---------------------------------------------------------------------------

def process_subagent(jsonl_path: str, meta_path: str) -> Moment:
    """Process a subagent JSONL into a summary moment + detail moments."""
    meta = {}
    if os.path.exists(meta_path):
        with open(meta_path) as f:
            meta = json.load(f)

    lines = load_jsonl(jsonl_path)
    if not lines:
        return Moment(
            type="subagent_summary",
            agent=meta.get("agentType", "unknown"),
            description=meta.get("description", ""),
            summary="(empty subagent session)",
        )

    # Collect timestamps, tokens, actions, interesting moments
    first_ts = ""
    last_ts = ""
    tokens = TokenUsage()
    actions = []
    detail_moments = []
    files_written = []
    interesting_moments = []
    test_results = []

    for entry in lines:
        ts = entry.get("timestamp", "")
        if ts and not first_ts:
            first_ts = ts
        if ts:
            last_ts = ts

        msg_type = entry.get("type", "")

        if msg_type == "assistant":
            tokens.add(extract_usage(entry))
            content_blocks = entry.get("message", {}).get("content", [])
            if not isinstance(content_blocks, list):
                continue

            for block in content_blocks:
                if block.get("type") == "text":
                    text = block["text"]
                    interesting, reason = is_interesting(text)
                    if interesting:
                        moment = Moment(
                            type=reason or "agent_prose",
                            timestamp=ts, content=text[:500],
                            interesting=True,
                        )
                        interesting_moments.append(moment)
                    detail_moments.append(Moment(
                        type="agent_prose", timestamp=ts,
                        content=text[:1000],
                    ))

                elif block.get("type") == "tool_use":
                    action = summarize_tool_use(block["name"], block.get("input", {}))
                    if action:
                        action.timestamp = ts
                        actions.append(action)
                        detail_moments.append(action)
                        if action.verb == "wrote":
                            files_written.append(action.target)

        elif msg_type == "user":
            content = entry.get("message", {}).get("content", "")
            # Check for test results in tool outputs
            if isinstance(content, list):
                for block in content:
                    if block.get("type") == "tool_result":
                        result_text = str(block.get("content", ""))
                        if any(kw in result_text.lower() for kw in
                               ["passed", "failed", "error", "test"]):
                            # Summarize test result
                            passed = len(re.findall(r"(?:PASS|passed|✓|✅)", result_text))
                            failed = len(re.findall(r"(?:FAIL|failed|✗|❌)", result_text))
                            if passed or failed:
                                test_results.append({"passed": passed, "failed": failed})

    # Calculate duration
    duration_ms = 0
    if first_ts and last_ts:
        from datetime import datetime, timezone
        try:
            t1 = datetime.fromisoformat(first_ts.replace("Z", "+00:00"))
            t2 = datetime.fromisoformat(last_ts.replace("Z", "+00:00"))
            duration_ms = int((t2 - t1).total_seconds() * 1000)
        except (ValueError, TypeError):
            pass

    # Build summary text
    desc = meta.get("description", "subagent")
    write_count = len(files_written)
    summary_parts = [desc]
    if write_count:
        summary_parts.append(f"{write_count} file{'s' if write_count != 1 else ''} written")
    if test_results:
        total_passed = sum(r["passed"] for r in test_results)
        total_failed = sum(r["failed"] for r in test_results)
        if total_failed:
            summary_parts.append(f"tests: {total_passed} passed, {total_failed} failed")
        elif total_passed:
            summary_parts.append(f"{total_passed} tests passing")
    if interesting_moments:
        summary_parts.append(f"{len(interesting_moments)} interesting moment{'s' if len(interesting_moments) != 1 else ''}")

    return Moment(
        type="subagent_summary",
        agent=meta.get("agentType", "unknown"),
        description=desc,
        duration_ms=duration_ms,
        summary=" — ".join(summary_parts),
        files_written=files_written,
        interesting=bool(interesting_moments),
        detail_moments=[asdict(m) for m in detail_moments] if detail_moments else [],
    )


# ---------------------------------------------------------------------------
# Session processing
# ---------------------------------------------------------------------------

def get_chapter_stage(command: str) -> str:
    """Map a command name to a pipeline stage."""
    stage_map = {
        "/feature": "scoping",
        "/feature-quick": "scoping",
        "/feature-domains": "domains",
        "/feature-plan": "planning",
        "/feature-test": "testing",
        "/feature-implement": "implementation",
        "/feature-refactor": "refactor",
        "/feature-pr": "pr",
        "/feature-retro": "retro",
        "/feature-complete": "complete",
        "/feature-resume": "resume",
        "/feature-coordinate": "coordination",
        "/curate": "curation",
        "/research": "research",
        "/architect": "architect",
        "/kb": "knowledge",
        "/decisions": "decisions",
    }
    return stage_map.get(command, command.lstrip("/"))


def _flatten_tool_result_content(content) -> str:
    """Flatten tool result content to a string for pattern matching.
    Content can be a string, a list of dicts with 'text' fields, or nested."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                parts.append(item.get("text", str(item)))
            else:
                parts.append(str(item))
        return "\n".join(parts)
    return str(content)


def process_session(jsonl_path: str, subagent_dir: Optional[str] = None,
                    feature_filter: Optional[str] = None) -> list[Chapter]:
    """Process a single session JSONL into chapters.

    If feature_filter is set, only include chapters that reference the
    feature slug in their command args or agent prose content.
    """
    lines = load_jsonl(jsonl_path)
    if not lines:
        return []

    chapters = []
    current_chapter = None
    pending_agent_calls = {}  # tool_use_id -> Agent tool_use moment

    for entry in lines:
        msg_type = entry.get("type", "")
        ts = entry.get("timestamp", "")

        # Skip noise
        if msg_type in ("progress", "file-history-snapshot", "last-prompt",
                        "pr-link", "queue-operation"):
            continue

        if msg_type == "system":
            continue

        if msg_type == "user":
            msg = entry.get("message", {})
            content = msg.get("content", "")

            # Command invocation — starts a new chapter
            if isinstance(content, str) and "<command-name>" in content:
                cmd_name, cmd_args = extract_command(content)
                if cmd_name:
                    # Close previous chapter
                    if current_chapter:
                        _finalize_chapter(current_chapter, ts)
                        chapters.append(current_chapter)

                    stage = get_chapter_stage(cmd_name)
                    title_suffix = f" — {cmd_args}" if cmd_args else ""
                    current_chapter = Chapter(
                        stage=stage,
                        command=cmd_name,
                        title=f"{stage.title()}{title_suffix}",
                        started=ts,
                    )

                    # Add the command invocation as a moment
                    current_chapter.moments.append(Moment(
                        type="user_prompt", timestamp=ts,
                        content=f"{cmd_name} {cmd_args}" if cmd_args else cmd_name,
                    ))
                continue

            # User text response (not a command)
            if isinstance(content, str) and content.strip():
                # Skip system-reminder and task-notification content
                if "<system-reminder>" in content:
                    continue
                if "<task-notification>" in content:
                    continue
                if current_chapter:
                    current_chapter.moments.append(Moment(
                        type="user_response", timestamp=ts,
                        content=content[:500],
                    ))
                continue

            # Tool result — check for subagent results, test results
            if isinstance(content, list):
                for block in content:
                    if block.get("type") != "tool_result":
                        continue
                    tool_use_id = block.get("tool_use_id", "")
                    result_content = _flatten_tool_result_content(block.get("content", ""))

                    # Check if this is a result for a pending Agent call
                    if tool_use_id in pending_agent_calls and subagent_dir:
                        agent_moment = pending_agent_calls.pop(tool_use_id)
                        # Find the subagent JSONL by agent ID in the result.
                        # The ID appears as "agentId: a1234abcdef" in text
                        # but files are named "agent-a1234abcdef.jsonl"
                        agent_id_match = re.search(r"agentId[:\s]+['\"]?([a-f0-9]+)['\"]?", result_content)
                        if agent_id_match:
                            raw_id = agent_id_match.group(1)
                            agent_id = f"agent-{raw_id}"
                            sa_jsonl = os.path.join(subagent_dir, f"{agent_id}.jsonl")
                            sa_meta = os.path.join(subagent_dir, f"{agent_id}.meta.json")
                            if os.path.exists(sa_jsonl):
                                sa_moment = process_subagent(sa_jsonl, sa_meta)
                                if current_chapter:
                                    current_chapter.moments.append(sa_moment)
                                continue
                        # If no agent ID in text, try matching by description
                        # against meta.json files in the subagent directory
                        if not agent_id_match and subagent_dir:
                            for meta_file in Path(subagent_dir).glob("*.meta.json"):
                                with open(meta_file) as mf:
                                    meta = json.load(mf)
                                if meta.get("description") == agent_moment.description:
                                    sa_id = meta_file.stem.replace(".meta", "")
                                    sa_jsonl = os.path.join(subagent_dir, f"{sa_id}.jsonl")
                                    if os.path.exists(sa_jsonl):
                                        sa_moment = process_subagent(sa_jsonl, str(meta_file))
                                        if current_chapter:
                                            current_chapter.moments.append(sa_moment)
                                        agent_id_match = True  # flag to skip fallback
                                        break

                        # Last resort: create a summary from the result text
                        if not agent_id_match and current_chapter:
                            current_chapter.moments.append(Moment(
                                type="subagent_summary",
                                timestamp=ts,
                                description=agent_moment.description,
                                summary=result_content[:300],
                            ))
                        continue

                    # Summarize test results if visible
                    if current_chapter and any(kw in result_content.lower()
                                               for kw in ["pass", "fail", "error"]):
                        passed = len(re.findall(r"(?:PASS|passed|✓|✅|ok)", result_content, re.I))
                        failed = len(re.findall(r"(?:FAIL|failed|✗|❌|ERROR)", result_content, re.I))
                        if passed or failed:
                            summary = f"{passed} passed" if not failed else f"{passed} passed, {failed} failed"
                            current_chapter.moments.append(Moment(
                                type="test_result", timestamp=ts,
                                summary=f"Tests: {summary}",
                                interesting=failed > 0,
                            ))

        elif msg_type == "assistant":
            if not current_chapter:
                continue

            msg = entry.get("message", {})
            current_chapter.tokens.add(extract_usage(entry))
            content_blocks = msg.get("content", [])
            if not isinstance(content_blocks, list):
                continue

            for block in content_blocks:
                block_type = block.get("type", "")

                if block_type == "text":
                    text = block.get("text", "")
                    if not text.strip():
                        continue
                    interesting, reason = is_interesting(text)
                    moment_type = reason if (interesting and reason in
                                             ("escalation", "refactor_finding")) else "agent_prose"
                    current_chapter.moments.append(Moment(
                        type=moment_type, timestamp=ts,
                        content=text[:2000],
                        interesting=interesting,
                    ))

                elif block_type == "tool_use":
                    tool_name = block.get("name", "")
                    tool_input = block.get("input", {})
                    tool_id = block.get("id", "")

                    # Track Agent calls for later matching with results
                    if tool_name == "Agent":
                        pending_agent_calls[tool_id] = Moment(
                            type="subagent_summary", timestamp=ts,
                            description=tool_input.get("description", ""),
                        )
                        continue

                    action = summarize_tool_use(tool_name, tool_input)
                    if action:
                        action.timestamp = ts
                        current_chapter.moments.append(action)

    # Close final chapter — use the last timestamp from within the chapter's
    # own moments, not the session file's end (which may be hours later if
    # the session continued with unrelated work after this chapter).
    if current_chapter:
        last_moment_ts = ""
        for m in reversed(current_chapter.moments):
            if m.timestamp:
                last_moment_ts = m.timestamp
                break
        if not last_moment_ts:
            # Fallback to file end
            for entry in reversed(lines):
                last_moment_ts = entry.get("timestamp", "")
                if last_moment_ts:
                    break
        _finalize_chapter(current_chapter, last_moment_ts)
        chapters.append(current_chapter)

    # Post-process: filter chapters by feature slug if requested.
    # A chapter belongs if:
    #   - its command args contain the slug, OR
    #   - an action writes to a file path containing the slug, OR
    #   - agent prose contains the slug in a stage heading/status context, OR
    #   - it's a pipeline stage following a matching chapter (continuity)
    if feature_filter:
        def chapter_matches_feature(ch: Chapter) -> bool:
            # Direct match: command args contain slug
            if feature_filter in ch.title:
                return True
            # Check for file writes targeting the feature directory
            for m in ch.moments:
                if m.type == "action" and feature_filter in (m.target or ""):
                    return True
                # Agent prose with slug in a stage banner or status context
                # (not just a passing mention in a user response)
                if m.type == "agent_prose" and feature_filter in (m.content or ""):
                    # Heuristic: slug appears in a structured heading or status
                    content = m.content or ""
                    # Look for slug in stage headings like "SCOPING AGENT · slug"
                    # or "Feature Status — slug" or "encrypt-memory-data"
                    if (f"· {feature_filter}" in content or
                        f"— {feature_filter}" in content or
                        f".feature/{feature_filter}" in content):
                        return True
            return False

        filtered = []
        in_feature = False
        for ch in chapters:
            if chapter_matches_feature(ch):
                in_feature = True
                filtered.append(ch)
            elif in_feature and ch.command and ch.command.startswith("/feature"):
                # Continuation of the same feature pipeline — check it doesn't
                # start a different feature
                if ch.stage == "scoping":
                    # New scoping = new feature, stop continuity
                    in_feature = False
                else:
                    filtered.append(ch)
            else:
                in_feature = False
        chapters = filtered

    # Post-process all chapters: clean up noise
    for ch in chapters:
        ch.moments = _clean_moments(ch.moments)

    return chapters


def _clean_moments(moments: list) -> list:
    """Post-process moments to remove noise and batch repetitive actions."""
    cleaned = []

    # 1. Strip leading test results (before first agent_prose) — these
    #    are results from previous chapter's tool calls bleeding over
    seen_prose = False
    for m in moments:
        if m.type in ("agent_prose", "user_response"):
            seen_prose = True
        if m.type == "test_result" and not seen_prose:
            continue  # skip early test noise
        cleaned.append(m)

    # 2. Batch consecutive CLAUDE.md edits into a single "Updated KB indexes" action
    batched = []
    i = 0
    while i < len(cleaned):
        m = cleaned[i]
        if (m.type == "action" and m.target and
                os.path.basename(m.target) == "CLAUDE.md"):
            # Count consecutive CLAUDE.md edits
            j = i + 1
            while (j < len(cleaned) and cleaned[j].type == "action" and
                   cleaned[j].target and
                   os.path.basename(cleaned[j].target) == "CLAUDE.md"):
                j += 1
            count = j - i
            if count > 1:
                batched.append(Moment(
                    type="action", verb="edited",
                    target="CLAUDE.md",
                    summary=f"Updated KB/decisions indexes ({count} files)",
                    timestamp=m.timestamp,
                ))
                i = j
                continue
        batched.append(m)
        i += 1

    # 3. Remove orphaned heading-only prose — agent_prose that is just a
    #    markdown heading (### ...) followed by no substantive content before
    #    the next heading or chapter end. These appear when the content under
    #    a heading was all bookkeeping (status.md edits) that got filtered.
    final = []
    for i, m in enumerate(batched):
        if m.type == "agent_prose" and m.content:
            stripped = m.content.strip()
            # Check if this is a heading-only block
            if (stripped.startswith("#") and
                    "\n" not in stripped and len(stripped) < 80):
                # Look ahead: is the next non-empty moment another heading
                # or the end?
                has_content = False
                for j in range(i + 1, min(i + 3, len(batched))):
                    nxt = batched[j]
                    if nxt.type == "agent_prose":
                        nxt_stripped = (nxt.content or "").strip()
                        if nxt_stripped.startswith("#"):
                            break  # another heading — this one is orphaned
                        has_content = True
                        break
                    elif nxt.type in ("action", "user_response", "test_result",
                                      "escalation", "refactor_finding",
                                      "subagent_summary"):
                        has_content = True
                        break
                if not has_content:
                    continue  # skip orphaned heading
        final.append(m)

    return final


def _finalize_chapter(chapter: Chapter, end_ts: str):
    """Calculate chapter duration from timestamps."""
    if chapter.started and end_ts:
        from datetime import datetime
        try:
            t1 = datetime.fromisoformat(chapter.started.replace("Z", "+00:00"))
            t2 = datetime.fromisoformat(end_ts.replace("Z", "+00:00"))
            chapter.duration_ms = int((t2 - t1).total_seconds() * 1000)
        except (ValueError, TypeError):
            pass


# ---------------------------------------------------------------------------
# Multi-session stitching
# ---------------------------------------------------------------------------

def find_project_dir(project_hint: str) -> Optional[str]:
    """Find the Claude Code project directory matching a hint."""
    claude_dir = Path.home() / ".claude" / "projects"
    if not claude_dir.exists():
        return None

    # Try exact match first
    for d in claude_dir.iterdir():
        if d.is_dir() and project_hint in d.name:
            return str(d)

    # Try case-insensitive
    hint_lower = project_hint.lower()
    for d in claude_dir.iterdir():
        if d.is_dir() and hint_lower in d.name.lower():
            return str(d)

    return None


def find_sessions_for_feature(project_dir: str, slug: str) -> list[str]:
    """Find all session JSONL files that reference a feature slug."""
    sessions = []
    for f in sorted(Path(project_dir).glob("*.jsonl")):
        # Quick scan for the slug
        with open(f) as fh:
            content = fh.read(500_000)  # first 500K should be enough
            if slug not in content:
                # Check rest of file
                rest = fh.read()
                if slug not in rest:
                    continue
        sessions.append(str(f))

    # Sort by first timestamp
    def first_timestamp(path):
        with open(path) as fh:
            for line in fh:
                try:
                    d = json.loads(line)
                    ts = d.get("timestamp", "")
                    if ts:
                        return ts
                except json.JSONDecodeError:
                    continue
        return ""

    sessions.sort(key=first_timestamp)
    return sessions


def stitch_sessions(session_paths: list[str], story_type: str, title: str,
                    feature_filter: Optional[str] = None) -> Story:
    """Stitch multiple sessions into a single story."""
    story = Story(story_type=story_type, title=title)
    all_chapters = []

    prev_last_ts = None

    for i, path in enumerate(session_paths):
        session_id = Path(path).stem
        story.sessions.append(session_id)

        # Find subagent directory
        subagent_dir = os.path.join(os.path.dirname(path), session_id, "subagents")
        if not os.path.isdir(subagent_dir):
            subagent_dir = None

        # Extract session metadata from first meaningful line
        lines = load_jsonl(path)
        for entry in lines:
            ts = entry.get("timestamp", "")
            branch = entry.get("gitBranch", "")
            model = entry.get("message", {}).get("model", "")
            if not story.started and ts:
                story.started = ts
            if not story.branch and branch:
                story.branch = branch
            if not story.model and model:
                story.model = model
            if ts or branch or model:
                break

        # Insert session break if this isn't the first session
        if i > 0 and prev_last_ts:
            first_ts = ""
            for entry in lines:
                first_ts = entry.get("timestamp", "")
                if first_ts:
                    break

            gap_ms = 0
            if prev_last_ts and first_ts:
                from datetime import datetime
                try:
                    t1 = datetime.fromisoformat(prev_last_ts.replace("Z", "+00:00"))
                    t2 = datetime.fromisoformat(first_ts.replace("Z", "+00:00"))
                    gap_ms = int((t2 - t1).total_seconds() * 1000)
                except (ValueError, TypeError):
                    pass

            # Determine recovery method from first command
            recovery = ""
            for entry in lines:
                content = entry.get("message", {}).get("content", "")
                if isinstance(content, str) and "<command-name>" in content:
                    cmd_name, cmd_args = extract_command(content)
                    recovery = f"{cmd_name} {cmd_args}" if cmd_args else cmd_name or ""
                    break

            # Determine state at break from last chapter
            state = ""
            if all_chapters:
                last = all_chapters[-1]
                state = f"Last stage: {last.stage}"
                if last.title:
                    state = f"{last.title} in progress"

            break_moment = Moment(
                type="session_break",
                reason="crash",
                gap_duration_ms=gap_ms,
                state_at_break=state,
                recovery_method=recovery.strip(),
                timestamp=first_ts,
            )

            # Add break as first moment of first chapter from new session,
            # or create a standalone resume chapter
            new_chapters = process_session(path, subagent_dir, feature_filter)
            if new_chapters:
                new_chapters[0].moments.insert(0, break_moment)
            all_chapters.extend(new_chapters)
        else:
            all_chapters.extend(process_session(path, subagent_dir, feature_filter))

        # Track last timestamp for gap calculation
        for entry in reversed(lines):
            ts = entry.get("timestamp", "")
            if ts:
                prev_last_ts = ts
                break

    story.chapters = all_chapters

    # Calculate totals — sum chapter durations (excludes inter-session gaps)
    if all_chapters:
        story.started = all_chapters[0].started
        story.duration_ms = sum(ch.duration_ms for ch in all_chapters)

        for ch in all_chapters:
            story.tokens.add(ch.tokens)

    return story


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

def story_to_dict(story: Story) -> dict:
    """Convert a Story to a JSON-serializable dict, dropping empty fields."""
    def clean(obj):
        if isinstance(obj, dict):
            return {k: clean(v) for k, v in obj.items()
                    if v and v != 0 and v != [] and v != ""}
        elif isinstance(obj, list):
            return [clean(item) for item in obj]
        return obj

    return clean(asdict(story))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Translate Claude Code JSONL logs into structured story JSON."
    )
    parser.add_argument("--feature", help="Feature slug to build a story for")
    parser.add_argument("--session", help="Single session UUID to translate")
    parser.add_argument("--project", help="Project name hint (matched against ~/.claude/projects/)")
    parser.add_argument("--project-path", help="Explicit project directory path")
    parser.add_argument("--output", "-o", help="Output file (default: stdout)")

    args = parser.parse_args()

    if not args.feature and not args.session:
        parser.error("One of --feature or --session is required")

    # Resolve project directory
    project_dir = args.project_path
    if not project_dir and args.project:
        project_dir = find_project_dir(args.project)
        if not project_dir:
            print(f"Error: no project directory found matching '{args.project}'", file=sys.stderr)
            sys.exit(1)
    if not project_dir:
        parser.error("One of --project or --project-path is required")

    print(f"Project directory: {project_dir}", file=sys.stderr)

    if args.feature:
        # Feature story — find and stitch sessions
        sessions = find_sessions_for_feature(project_dir, args.feature)
        if not sessions:
            print(f"Error: no sessions found for feature '{args.feature}'", file=sys.stderr)
            sys.exit(1)
        print(f"Found {len(sessions)} session(s) for '{args.feature}'", file=sys.stderr)
        story = stitch_sessions(sessions, "feature", args.feature,
                               feature_filter=args.feature)

    else:
        # Single session
        session_path = os.path.join(project_dir, f"{args.session}.jsonl")
        if not os.path.exists(session_path):
            print(f"Error: session file not found: {session_path}", file=sys.stderr)
            sys.exit(1)

        subagent_dir = os.path.join(project_dir, args.session, "subagents")
        if not os.path.isdir(subagent_dir):
            subagent_dir = None

        chapters = process_session(session_path, subagent_dir)

        # Auto-detect story type
        commands = [ch.command for ch in chapters if ch.command]
        stype = detect_story_type(commands)

        story = Story(story_type=stype, sessions=[args.session], chapters=chapters)

        # Fill metadata
        lines = load_jsonl(session_path)
        for entry in lines:
            if not story.started and entry.get("timestamp"):
                story.started = entry["timestamp"]
            if not story.branch and entry.get("gitBranch"):
                story.branch = entry["gitBranch"]
            if not story.model:
                model = entry.get("message", {}).get("model", "")
                if model:
                    story.model = model
            if story.started and story.branch and story.model:
                break

        for ch in chapters:
            story.tokens.add(ch.tokens)

        if chapters:
            story.duration_ms = sum(ch.duration_ms for ch in chapters)
            story.title = chapters[0].title

    # Output
    result = story_to_dict(story)
    output = json.dumps(result, indent=2)

    if args.output:
        with open(args.output, "w") as f:
            f.write(output)
        print(f"Wrote {len(output)} bytes to {args.output}", file=sys.stderr)
    else:
        print(output)


if __name__ == "__main__":
    main()
