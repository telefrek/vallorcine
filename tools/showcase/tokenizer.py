#!/usr/bin/env python3
"""Stage 1: Tokenize Claude Code JSONL session logs into clean event streams.

Reads raw JSONL files, filters noise (progress events, file snapshots),
extracts clean tokens with timestamps, content, and metadata. Handles
multi-session stitching for feature stories and subagent discovery.

This module knows about Claude Code's JSONL format but NOT about
vallorcine's pipeline semantics — that's the parser's job.

Usage:
    from tokenize import tokenize_feature, tokenize_session
    stream = tokenize_feature("encrypt-memory-data", project_dir)
    stream.save("/tmp/tokens.json")
"""

import json
import os
import re
from datetime import datetime
from pathlib import Path
from typing import Optional

from model import Token, TokenStream, TokenUsage


# ---------------------------------------------------------------------------
# JSONL helpers
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


def flatten_tool_result_content(content) -> str:
    """Flatten tool result content to a string."""
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


def extract_command(content: str) -> tuple[Optional[str], Optional[str]]:
    """Extract command name and args from a user message with command tags."""
    name_match = re.search(r"<command-name>([^<]+)</command-name>", content)
    args_match = re.search(r"<command-args>(.*?)</command-args>", content, re.DOTALL)
    name = name_match.group(1) if name_match else None
    args = args_match.group(1).strip().strip('"') if args_match else None
    return name, args


def extract_usage(entry: dict) -> TokenUsage:
    """Extract token usage from an assistant message."""
    usage = entry.get("message", {}).get("usage", {})
    return TokenUsage(
        input=usage.get("input_tokens", 0),
        output=usage.get("output_tokens", 0),
        cache_read=usage.get("cache_read_input_tokens", 0),
        cache_create=usage.get("cache_creation_input_tokens", 0),
    )


def is_bookkeeping_file(path: str) -> bool:
    """Check if a file is internal bookkeeping."""
    basename = os.path.basename(path)
    if basename == "status.md":
        return True
    if basename == "CLAUDE.md" and any(d in path for d in [".kb/", ".decisions/"]):
        return True
    return False


# ---------------------------------------------------------------------------
# Interesting moment detection
# ---------------------------------------------------------------------------

ESCALATION_PATTERNS = [
    r"escalat", r"contract conflict", r"can't satisfy",
    r"cannot satisfy", r"doesn't match.*contract",
]
REFACTOR_PATTERNS = [
    r"structural (issue|concern)", r"security (issue|concern|finding)",
    r"flagged for review", r"pause.*human", r"checklist item 2[cd]",
]
RETRY_PATTERNS = [
    r"cycle [2-9]", r"retry", r"second attempt", r"trying again",
]


def detect_interest(text: str) -> tuple[bool, Optional[str]]:
    """Check if text contains interesting moment signals."""
    text_lower = text.lower()
    for p in ESCALATION_PATTERNS:
        if re.search(p, text_lower):
            return True, "escalation"
    for p in REFACTOR_PATTERNS:
        if re.search(p, text_lower):
            return True, "refactor_finding"
    for p in RETRY_PATTERNS:
        if re.search(p, text_lower):
            return True, "retry"
    return False, None


# ---------------------------------------------------------------------------
# Subagent processing
# ---------------------------------------------------------------------------

def tokenize_subagent(jsonl_path: str, meta_path: str) -> Token:
    """Process a subagent JSONL into a subagent_result token."""
    meta = {}
    if os.path.exists(meta_path):
        with open(meta_path) as f:
            meta = json.load(f)

    lines = load_jsonl(jsonl_path)
    if not lines:
        return Token(
            type="subagent_result",
            metadata={
                "agent_type": meta.get("agentType", "unknown"),
                "description": meta.get("description", ""),
                "summary": "(empty subagent session)",
            },
        )

    first_ts = ""
    last_ts = ""
    tokens = TokenUsage()
    files_written = []
    interesting_moments = []
    test_passed = 0
    test_failed = 0

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
                    interesting, reason = detect_interest(block["text"])
                    if interesting:
                        interesting_moments.append(reason)
                elif block.get("type") == "tool_use":
                    name = block.get("name", "")
                    inp = block.get("input", {})
                    if name in ("Write", "Edit"):
                        path = inp.get("file_path", "")
                        if path and not is_bookkeeping_file(path):
                            files_written.append(os.path.basename(path))

        elif msg_type == "user":
            content = entry.get("message", {}).get("content", [])
            if isinstance(content, list):
                for block in content:
                    if block.get("type") == "tool_result":
                        result_text = flatten_tool_result_content(block.get("content", ""))
                        passed = len(re.findall(r"(?:PASS|passed|✓|✅|ok)", result_text, re.I))
                        failed = len(re.findall(r"(?:FAIL|failed|✗|❌|ERROR)", result_text, re.I))
                        test_passed += passed
                        test_failed += failed

    duration_ms = 0
    if first_ts and last_ts:
        try:
            t1 = datetime.fromisoformat(first_ts.replace("Z", "+00:00"))
            t2 = datetime.fromisoformat(last_ts.replace("Z", "+00:00"))
            duration_ms = int((t2 - t1).total_seconds() * 1000)
        except (ValueError, TypeError):
            pass

    desc = meta.get("description", "subagent")
    summary_parts = [desc]
    if files_written:
        summary_parts.append(f"{len(files_written)} files written")
    if test_passed or test_failed:
        if test_failed:
            summary_parts.append(f"tests: {test_passed} passed, {test_failed} failed")
        else:
            summary_parts.append(f"{test_passed} tests passing")
    if interesting_moments:
        summary_parts.append(f"{len(interesting_moments)} interesting moments")

    return Token(
        type="subagent_result",
        timestamp=first_ts,
        content=" — ".join(summary_parts),
        metadata={
            "agent_type": meta.get("agentType", "unknown"),
            "description": desc,
            "summary": " — ".join(summary_parts),
            "duration_ms": duration_ms,
            "files_written": files_written,
            "interesting": bool(interesting_moments),
            "interesting_types": interesting_moments,
            "test_passed": test_passed,
            "test_failed": test_failed,
            "detail_file": jsonl_path,
        },
        tokens=tokens,
    )


# ---------------------------------------------------------------------------
# Session tokenization
# ---------------------------------------------------------------------------

def tokenize_session(jsonl_path: str, subagent_dir: Optional[str] = None) -> list[Token]:
    """Tokenize a single session JSONL into clean events."""
    lines = load_jsonl(jsonl_path)
    if not lines:
        return []

    session_id = Path(jsonl_path).stem
    tokens_out = []
    pending_agents = {}  # tool_use_id -> description

    # Session start
    for entry in lines:
        ts = entry.get("timestamp", "")
        branch = entry.get("gitBranch", "")
        model = entry.get("message", {}).get("model", "")
        if ts:
            tokens_out.append(Token(
                type="session_start",
                timestamp=ts,
                metadata={
                    "session_id": session_id,
                    "branch": branch or "",
                    "model": model or "",
                },
            ))
            break

    for entry in lines:
        msg_type = entry.get("type", "")
        ts = entry.get("timestamp", "")

        # Skip noise
        if msg_type in ("progress", "file-history-snapshot", "last-prompt",
                        "pr-link", "queue-operation", "system"):
            continue

        if msg_type == "user":
            msg = entry.get("message", {})
            content = msg.get("content", "")

            # Command invocation
            if isinstance(content, str) and "<command-name>" in content:
                cmd_name, cmd_args = extract_command(content)
                if cmd_name:
                    tokens_out.append(Token(
                        type="command",
                        timestamp=ts,
                        content=f"{cmd_name} {cmd_args}" if cmd_args else cmd_name,
                        metadata={"name": cmd_name, "args": cmd_args or ""},
                    ))
                continue

            # User text (not a command)
            if isinstance(content, str) and content.strip():
                if "<system-reminder>" in content:
                    continue
                if "<task-notification>" in content:
                    continue
                tokens_out.append(Token(
                    type="user_text",
                    timestamp=ts,
                    content=content[:2000],
                ))
                continue

            # Tool results
            if isinstance(content, list):
                for block in content:
                    if block.get("type") != "tool_result":
                        continue
                    tool_use_id = block.get("tool_use_id", "")
                    result_content = flatten_tool_result_content(block.get("content", ""))

                    # Subagent result
                    if tool_use_id in pending_agents and subagent_dir:
                        agent_desc = pending_agents.pop(tool_use_id)
                        # Try to find subagent JSONL by agent ID
                        agent_id_match = re.search(r"agentId[:\s]+['\"]?([a-f0-9]+)['\"]?",
                                                   result_content)
                        sa_token = None

                        if agent_id_match:
                            raw_id = agent_id_match.group(1)
                            sa_jsonl = os.path.join(subagent_dir, f"agent-{raw_id}.jsonl")
                            sa_meta = os.path.join(subagent_dir, f"agent-{raw_id}.meta.json")
                            if os.path.exists(sa_jsonl):
                                sa_token = tokenize_subagent(sa_jsonl, sa_meta)

                        # Fallback: match by description
                        if not sa_token and subagent_dir:
                            for meta_file in Path(subagent_dir).glob("*.meta.json"):
                                with open(meta_file) as mf:
                                    meta = json.load(mf)
                                if meta.get("description") == agent_desc:
                                    sa_id = meta_file.stem.replace(".meta", "")
                                    sa_jsonl = os.path.join(subagent_dir, f"{sa_id}.jsonl")
                                    if os.path.exists(sa_jsonl):
                                        sa_token = tokenize_subagent(sa_jsonl, str(meta_file))
                                        break

                        if sa_token:
                            tokens_out.append(sa_token)
                        else:
                            tokens_out.append(Token(
                                type="subagent_result",
                                timestamp=ts,
                                content=result_content[:500],
                                metadata={
                                    "description": agent_desc,
                                    "summary": result_content[:300],
                                },
                            ))
                        continue

                    # Test results
                    if any(kw in result_content.lower() for kw in ["pass", "fail", "error"]):
                        passed = len(re.findall(r"(?:PASS|passed|✓|✅|ok)", result_content, re.I))
                        failed = len(re.findall(r"(?:FAIL|failed|✗|❌|ERROR)", result_content, re.I))
                        if passed or failed:
                            tokens_out.append(Token(
                                type="tool_result",
                                timestamp=ts,
                                content=f"{passed} passed, {failed} failed" if failed else f"{passed} passed",
                                metadata={
                                    "tool_use_id": tool_use_id,
                                    "is_test": True,
                                    "passed": passed,
                                    "failed": failed,
                                },
                            ))

        elif msg_type == "assistant":
            msg = entry.get("message", {})
            usage = extract_usage(entry)
            content_blocks = msg.get("content", [])
            if not isinstance(content_blocks, list):
                continue

            for block in content_blocks:
                block_type = block.get("type", "")

                if block_type == "text":
                    text = block.get("text", "")
                    if not text.strip():
                        continue
                    interesting, reason = detect_interest(text)
                    tokens_out.append(Token(
                        type="agent_prose",
                        timestamp=ts,
                        content=text[:2000],
                        metadata={
                            "interesting": interesting,
                            "interest_reason": reason or "",
                        },
                        tokens=usage,
                    ))

                elif block_type == "tool_use":
                    tool_name = block.get("name", "")
                    tool_input = block.get("input", {})
                    tool_id = block.get("id", "")

                    # Track Agent calls
                    if tool_name == "Agent":
                        desc = tool_input.get("description", "")
                        pending_agents[tool_id] = desc
                        tokens_out.append(Token(
                            type="subagent_start",
                            timestamp=ts,
                            metadata={
                                "description": desc,
                                "agent_type": tool_input.get("subagent_type", "general-purpose"),
                                "tool_use_id": tool_id,
                            },
                        ))
                        continue

                    # Skill invocation
                    if tool_name == "Skill":
                        skill = tool_input.get("skill", "")
                        tokens_out.append(Token(
                            type="command",
                            timestamp=ts,
                            content=f"/{skill}",
                            metadata={"name": f"/{skill}", "args": ""},
                        ))
                        continue

                    # File writes/edits (skip bookkeeping)
                    if tool_name in ("Write", "Edit"):
                        path = tool_input.get("file_path", "")
                        if path and not is_bookkeeping_file(path):
                            tokens_out.append(Token(
                                type="tool_call",
                                timestamp=ts,
                                metadata={
                                    "tool": tool_name.lower(),
                                    "target": path,
                                    "input_summary": f"{'Wrote' if tool_name == 'Write' else 'Edited'} {os.path.basename(path)}",
                                },
                            ))
                        continue

                    # Bash commands (only interesting ones)
                    if tool_name == "Bash":
                        cmd = tool_input.get("command", "")
                        desc = tool_input.get("description", "")
                        if any(kw in cmd for kw in ["git commit", "git push", "npm test",
                                                     "pytest", "go test", "cargo test",
                                                     "make test", "gh pr"]):
                            tokens_out.append(Token(
                                type="tool_call",
                                timestamp=ts,
                                metadata={
                                    "tool": "bash",
                                    "target": cmd[:120],
                                    "input_summary": desc or f"Ran: {cmd[:80]}",
                                },
                            ))
                        elif desc and any(kw in desc.lower() for kw in
                                          ["test", "commit", "push", "pr"]):
                            tokens_out.append(Token(
                                type="tool_call",
                                timestamp=ts,
                                metadata={
                                    "tool": "bash",
                                    "target": cmd[:120],
                                    "input_summary": desc,
                                },
                            ))

    # Session end
    last_ts = ""
    for entry in reversed(lines):
        last_ts = entry.get("timestamp", "")
        if last_ts:
            break
    if last_ts:
        tokens_out.append(Token(
            type="session_end",
            timestamp=last_ts,
            metadata={"session_id": session_id, "reason": "end"},
        ))

    return tokens_out


# ---------------------------------------------------------------------------
# Multi-session stitching
# ---------------------------------------------------------------------------

def find_project_dir(project_hint: str) -> Optional[str]:
    """Find the Claude Code project directory matching a hint."""
    claude_dir = Path.home() / ".claude" / "projects"
    if not claude_dir.exists():
        return None
    for d in claude_dir.iterdir():
        if d.is_dir() and project_hint in d.name:
            return str(d)
    hint_lower = project_hint.lower()
    for d in claude_dir.iterdir():
        if d.is_dir() and hint_lower in d.name.lower():
            return str(d)
    return None


def find_sessions_for_feature(project_dir: str, slug: str) -> list[str]:
    """Find all session JSONL files that reference a feature slug."""
    sessions = []
    for f in sorted(Path(project_dir).glob("*.jsonl")):
        with open(f) as fh:
            content = fh.read()
            if slug in content:
                sessions.append(str(f))

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


def tokenize_feature(slug: str, project_dir: str) -> TokenStream:
    """Tokenize all sessions for a feature into a single token stream."""
    session_paths = find_sessions_for_feature(project_dir, slug)
    if not session_paths:
        return TokenStream()

    stream = TokenStream(project=project_dir)

    for path in session_paths:
        session_id = Path(path).stem
        stream.sessions.append(session_id)

        subagent_dir = os.path.join(os.path.dirname(path), session_id, "subagents")
        if not os.path.isdir(subagent_dir):
            subagent_dir = None

        session_tokens = tokenize_session(path, subagent_dir)
        stream.tokens.extend(session_tokens)

    return stream


def tokenize_single_session(session_id: str, project_dir: str) -> TokenStream:
    """Tokenize a single session."""
    path = os.path.join(project_dir, f"{session_id}.jsonl")
    if not os.path.exists(path):
        return TokenStream()

    subagent_dir = os.path.join(project_dir, session_id, "subagents")
    if not os.path.isdir(subagent_dir):
        subagent_dir = None

    stream = TokenStream(
        sessions=[session_id],
        project=project_dir,
        tokens=tokenize_session(path, subagent_dir),
    )
    return stream
