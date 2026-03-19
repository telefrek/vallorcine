#!/usr/bin/env python3
"""Stage 2: Parse token streams into pipeline-aware AST.

Reads a TokenStream (from tokenize.py) and produces a Story AST with
typed nodes representing vallorcine pipeline structure.

This module knows about vallorcine's pipeline semantics — command names,
stage progression, agent roles, file conventions. It does NOT know about
rendering or presentation.

Classification is intentionally loose: unrecognized token sequences
fall back to Prose nodes rather than being dropped. New node types
are added as we encounter new patterns.

Usage:
    from parse import parse_story
    from model import TokenStream
    stream = TokenStream.load("/tmp/tokens.json")
    story = parse_story(stream, feature_slug="encrypt-memory-data")
    story.save("/tmp/story-ast.json")
"""

import os
import re
from datetime import datetime
from typing import Optional

from model import Token, TokenStream, TokenUsage, Node, NodeType, Story


# ---------------------------------------------------------------------------
# Stage mapping
# ---------------------------------------------------------------------------

COMMAND_TO_STAGE = {
    "/feature": "scoping",
    "/feature-quick": "scoping",
    "/feature-domains": "domains",
    "/feature-plan": "planning",
    "/feature-test": "testing",
    "/feature-implement": "implementation",
    "/feature-refactor": "refactor",
    "/feature-coordinate": "coordination",
    "/feature-pr": "pr",
    "/feature-retro": "retro",
    "/feature-complete": "complete",
    "/feature-resume": "resume",
    "/curate": "curation",
    "/research": "research",
    "/architect": "architect",
    "/kb": "knowledge",
    "/decisions": "decisions",
}


def detect_story_type(commands: list[str]) -> str:
    """Determine story type from commands found in the stream."""
    for cmd in commands:
        if cmd.startswith("/feature"):
            return "feature"
        if cmd == "/curate":
            return "curation"
        if cmd == "/research":
            return "research"
        if cmd == "/architect":
            return "architect"
    return "feature"


# ---------------------------------------------------------------------------
# Duration helpers
# ---------------------------------------------------------------------------

def parse_ts(ts: str) -> Optional[datetime]:
    """Parse an ISO timestamp."""
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


def duration_between(ts1: str, ts2: str) -> int:
    """Calculate duration in ms between two timestamps."""
    t1 = parse_ts(ts1)
    t2 = parse_ts(ts2)
    if t1 and t2:
        return max(0, int((t2 - t1).total_seconds() * 1000))
    return 0


# ---------------------------------------------------------------------------
# Token stream segmentation
# ---------------------------------------------------------------------------

def segment_by_command(tokens: list[Token]) -> list[tuple[Token, list[Token]]]:
    """Split token stream into segments, each starting with a command token.

    Returns list of (command_token, following_tokens) tuples.
    Tokens before the first command are grouped under a synthetic 'preamble'.
    """
    segments = []
    current_cmd = Token(type="command", metadata={"name": "_preamble", "args": ""})
    current_tokens = []

    for token in tokens:
        if token.type == "command":
            if current_tokens or current_cmd.metadata.get("name") != "_preamble":
                segments.append((current_cmd, current_tokens))
            current_cmd = token
            current_tokens = []
        else:
            current_tokens.append(token)

    if current_tokens:
        segments.append((current_cmd, current_tokens))

    return segments


# ---------------------------------------------------------------------------
# Pattern recognizers
# ---------------------------------------------------------------------------

def recognize_conversation(tokens: list[Token], start: int) -> tuple[Optional[Node], int]:
    """Recognize a conversation pattern: alternating agent_prose and user_text.

    Returns (node, end_index) or (None, start) if no conversation found.
    """
    exchanges = []
    i = start

    while i < len(tokens):
        # Look for agent_prose followed by user_text
        if tokens[i].type == "agent_prose":
            question = tokens[i].content
            # Check if next meaningful token is user response
            j = i + 1
            # Skip intervening tool calls/results
            while j < len(tokens) and tokens[j].type in ("tool_call", "tool_result"):
                j += 1
            if j < len(tokens) and tokens[j].type == "user_text":
                exchanges.append({
                    "question": question[:500],
                    "answer": tokens[j].content[:500],
                    "timestamp": tokens[i].timestamp,
                })
                i = j + 1
                continue
        break

    if len(exchanges) >= 2:
        node = Node(
            node_type=NodeType.CONVERSATION,
            data={"exchange_count": len(exchanges)},
            children=[
                Node(
                    node_type=NodeType.EXCHANGE,
                    data=ex,
                    content=f"Q: {ex['question'][:100]}\nA: {ex['answer'][:100]}",
                )
                for ex in exchanges
            ],
        )
        if exchanges:
            node.duration_ms = duration_between(
                exchanges[0].get("timestamp", ""),
                exchanges[-1].get("timestamp", ""),
            )
        return node, i

    return None, start


def recognize_research(tokens: list[Token], start: int) -> tuple[Optional[Node], int]:
    """Recognize a research commission: /research command → prose → KB writes."""
    if start >= len(tokens):
        return None, start

    i = start
    topic = ""
    subject = ""
    kb_path = ""
    findings = []

    while i < len(tokens):
        t = tokens[i]
        if t.type == "agent_prose":
            # Look for research topic indicators
            content = t.content
            if "RESEARCH AGENT" in content or "Pre-flight check" in content:
                topic_match = re.search(r"Topic:\s*(\S+)", content)
                subject_match = re.search(r"Subject:\s*(\S+)", content)
                if topic_match:
                    topic = topic_match.group(1)
                if subject_match:
                    subject = subject_match.group(1)
            if "RESEARCH AGENT complete" in content:
                findings.append(content[:500])
                i += 1
                break
        elif t.type == "tool_call":
            target = t.metadata.get("target", "")
            if ".kb/" in target and t.metadata.get("tool") == "write":
                kb_path = target
        i += 1

    if kb_path or topic:
        return Node(
            node_type=NodeType.RESEARCH,
            data={
                "topic": topic,
                "subject": subject,
                "kb_path": os.path.basename(kb_path) if kb_path else "",
                "findings_summary": findings[0] if findings else "",
            },
            duration_ms=duration_between(
                tokens[start].timestamp if start < len(tokens) else "",
                tokens[min(i-1, len(tokens)-1)].timestamp,
            ),
        ), i

    return None, start


def recognize_architect(tokens: list[Token], start: int) -> tuple[Optional[Node], int]:
    """Recognize an architect session: constraints → evaluation → deliberation → ADR."""
    i = start
    question = ""
    decision = ""
    adr_path = ""
    candidates = []
    has_deliberation = False

    while i < len(tokens):
        t = tokens[i]
        if t.type == "agent_prose":
            content = t.content
            if "ARCHITECT AGENT" in content and "complete" not in content:
                question_match = re.search(r"RECOMMENDATION.*?—\s*(.+?)$", content, re.M)
                if question_match:
                    question = question_match.group(1)
            if "RECOMMENDATION" in content:
                # Extract recommended approach
                rec_match = re.search(r"Recommended approach:\s*(.+?)$", content, re.M)
                rej_match = re.search(r"Rejected:\s*(.+?)$", content, re.M)
                if rec_match:
                    decision = rec_match.group(1).strip()
                if rej_match:
                    candidates = [c.strip() for c in rej_match.group(1).split(",")]
                has_deliberation = True
            if "ARCHITECT AGENT complete" in content:
                i += 1
                break
        elif t.type == "tool_call":
            target = t.metadata.get("target", "")
            if "adr.md" in target:
                adr_path = target
        elif t.type == "user_text":
            # User confirmation or pushback during deliberation
            if has_deliberation:
                pass  # captured in the conversation flow
        i += 1

    if has_deliberation or adr_path:
        return Node(
            node_type=NodeType.ARCHITECT,
            data={
                "question": question,
                "decision": decision,
                "rejected": candidates,
                "adr_path": os.path.basename(adr_path) if adr_path else "",
            },
            interesting=bool(candidates),
            duration_ms=duration_between(
                tokens[start].timestamp,
                tokens[min(i-1, len(tokens)-1)].timestamp,
            ),
        ), i

    return None, start


def recognize_tdd_cycle(tokens: list[Token], start: int) -> tuple[Optional[Node], int]:
    """Recognize a TDD cycle from subagent start/result pairs."""
    if start >= len(tokens) or tokens[start].type != "subagent_start":
        return None, start

    desc = tokens[start].metadata.get("description", "")
    # Look for the matching subagent_result
    i = start + 1
    while i < len(tokens):
        t = tokens[i]
        if t.type == "subagent_result" and t.metadata.get("description", "") == desc:
            meta = t.metadata
            return Node(
                node_type=NodeType.TDD_CYCLE,
                data={
                    "unit_name": desc,
                    "duration_ms": meta.get("duration_ms", 0),
                    "files_written": meta.get("files_written", []),
                    "test_passed": meta.get("test_passed", 0),
                    "test_failed": meta.get("test_failed", 0),
                    "interesting_types": meta.get("interesting_types", []),
                    "summary": meta.get("summary", ""),
                },
                interesting=meta.get("interesting", False),
                duration_ms=meta.get("duration_ms", 0),
                tokens=t.tokens,
            ), i + 1
        # Don't cross command boundaries
        if t.type == "command":
            break
        i += 1

    return None, start


# ---------------------------------------------------------------------------
# Phase builder
# ---------------------------------------------------------------------------

def build_phase(cmd_token: Token, tokens: list[Token],
                feature_slug: Optional[str] = None) -> Optional[Node]:
    """Build a Phase node from a command and its following tokens.

    Returns None if the phase should be filtered out (wrong feature).
    """
    cmd_name = cmd_token.metadata.get("name", "")
    cmd_args = cmd_token.metadata.get("args", "")
    stage = COMMAND_TO_STAGE.get(cmd_name, cmd_name.lstrip("/"))

    # Feature filtering
    if feature_slug:
        if cmd_args and feature_slug in cmd_args:
            pass  # explicit match
        elif cmd_name in ("/feature", "/feature-quick") and not cmd_args:
            # Bare /feature — check if the slug appears in agent prose
            # or tool call targets within this phase's tokens
            slug_found = False
            for t in tokens:
                content = t.content or ""
                target = t.metadata.get("target", "")
                if (f"· {feature_slug}" in content
                        or f"— {feature_slug}" in content
                        or f".feature/{feature_slug}" in content
                        or f".feature/{feature_slug}" in target):
                    slug_found = True
                    break
            if not slug_found:
                return None
        elif cmd_name.startswith("/feature-"):
            pass  # pipeline continuation, keep
        elif cmd_name in ("/research", "/architect"):
            pass  # these are invoked during domains, keep
        else:
            return None

    title = f"{stage.title()}"
    if cmd_args:
        title += f" — {cmd_args}"

    phase = Node(
        node_type=NodeType.PHASE,
        data={"stage": stage, "command": cmd_name, "title": title},
    )

    # Set timestamps
    if cmd_token.timestamp:
        phase.data["started"] = cmd_token.timestamp
    if tokens:
        last_ts = ""
        for t in reversed(tokens):
            if t.timestamp:
                last_ts = t.timestamp
                break
        if last_ts and cmd_token.timestamp:
            phase.duration_ms = duration_between(cmd_token.timestamp, last_ts)

    # Aggregate tokens
    for t in tokens:
        phase.tokens.add(t.tokens)

    # Parse children from token sequence
    children = parse_phase_children(tokens)
    phase.children = children

    return phase


def parse_phase_children(tokens: list[Token]) -> list[Node]:
    """Parse a sequence of tokens within a phase into child AST nodes."""
    children = []
    i = 0

    while i < len(tokens):
        t = tokens[i]

        # Session boundaries
        if t.type == "session_end":
            # Look ahead for session_start to create a break
            if i + 1 < len(tokens) and tokens[i + 1].type == "session_start":
                gap = duration_between(t.timestamp, tokens[i + 1].timestamp)
                children.append(Node(
                    node_type=NodeType.SESSION_BREAK,
                    data={
                        "reason": "crash",
                        "gap_duration_ms": gap,
                    },
                    duration_ms=gap,
                ))
                i += 2  # skip both session_end and session_start
                continue
            i += 1
            continue

        if t.type == "session_start":
            i += 1
            continue

        # Try pattern recognizers in priority order
        # TDD cycles (subagent patterns)
        if t.type == "subagent_start":
            desc = t.metadata.get("description", "")
            if any(kw in desc.lower() for kw in ["test-implement", "tdd", "wu-"]):
                node, new_i = recognize_tdd_cycle(tokens, i)
                if node:
                    children.append(node)
                    i = new_i
                    continue

        # Non-TDD subagents (stubs, status files, etc.)
        if t.type == "subagent_start":
            node, new_i = recognize_tdd_cycle(tokens, i)  # reuse for any subagent
            if node:
                # Reclassify as generic if not TDD
                desc = t.metadata.get("description", "")
                if not any(kw in desc.lower() for kw in ["test-implement", "tdd", "wu-"]):
                    node.node_type = NodeType.ACTION_GROUP
                children.append(node)
                i = new_i
                continue

        # Subagent results without matching starts (from background agents)
        if t.type == "subagent_result":
            meta = t.metadata
            children.append(Node(
                node_type=NodeType.TDD_CYCLE if any(
                    kw in meta.get("description", "").lower()
                    for kw in ["test-implement", "tdd", "wu-"]
                ) else NodeType.ACTION_GROUP,
                data={
                    "unit_name": meta.get("description", ""),
                    "summary": meta.get("summary", ""),
                    "duration_ms": meta.get("duration_ms", 0),
                    "files_written": meta.get("files_written", []),
                    "test_passed": meta.get("test_passed", 0),
                    "test_failed": meta.get("test_failed", 0),
                    "interesting_types": meta.get("interesting_types", []),
                },
                interesting=meta.get("interesting", False),
                duration_ms=meta.get("duration_ms", 0),
                tokens=t.tokens,
            ))
            i += 1
            continue

        # Conversations (agent asks, user answers, repeat)
        if t.type == "agent_prose":
            conv_node, new_i = recognize_conversation(tokens, i)
            if conv_node:
                children.append(conv_node)
                i = new_i
                continue

        # Stage transitions (command invocations via Skill tool)
        if t.type == "command":
            cmd_name = t.metadata.get("name", "")
            children.append(Node(
                node_type=NodeType.STAGE_TRANSITION,
                data={"command": cmd_name, "args": t.metadata.get("args", "")},
            ))
            i += 1
            continue

        # Test results
        if t.type == "tool_result" and t.metadata.get("is_test"):
            # Batch consecutive test results
            results = [t]
            j = i + 1
            while j < len(tokens) and tokens[j].type == "tool_result" and tokens[j].metadata.get("is_test"):
                results.append(tokens[j])
                j += 1

            total_passed = sum(r.metadata.get("passed", 0) for r in results)
            total_failed = sum(r.metadata.get("failed", 0) for r in results)

            children.append(Node(
                node_type=NodeType.TEST_RESULT,
                data={
                    "passed": total_passed,
                    "failed": total_failed,
                    "run_count": len(results),
                },
                interesting=total_failed > 0,
            ))
            i = j
            continue

        # Tool calls — batch consecutive ones
        if t.type == "tool_call":
            actions = [t]
            j = i + 1
            while j < len(tokens) and tokens[j].type == "tool_call":
                actions.append(tokens[j])
                j += 1

            children.append(Node(
                node_type=NodeType.ACTION_GROUP,
                data={
                    "actions": [
                        {
                            "verb": a.metadata.get("tool", ""),
                            "target": os.path.basename(a.metadata.get("target", "")),
                            "summary": a.metadata.get("input_summary", ""),
                        }
                        for a in actions
                    ],
                },
            ))
            i = j
            continue

        # Agent prose (interesting or routine)
        if t.type == "agent_prose":
            interesting = t.metadata.get("interesting", False)
            reason = t.metadata.get("interest_reason", "")

            if interesting and reason == "escalation":
                children.append(Node(
                    node_type=NodeType.ESCALATION,
                    content=t.content[:1000],
                    interesting=True,
                ))
            else:
                children.append(Node(
                    node_type=NodeType.PROSE,
                    content=t.content[:2000],
                    interesting=interesting,
                    tokens=t.tokens,
                ))
            i += 1
            continue

        # User text outside of a conversation pattern
        if t.type == "user_text":
            children.append(Node(
                node_type=NodeType.EXCHANGE,
                data={"answer": t.content[:500]},
                content=t.content[:500],
            ))
            i += 1
            continue

        # Anything else — skip
        i += 1

    return children


# ---------------------------------------------------------------------------
# Story assembly
# ---------------------------------------------------------------------------

def parse_story(stream: TokenStream, feature_slug: Optional[str] = None,
                story_type: Optional[str] = None) -> Story:
    """Parse a token stream into a Story AST."""

    # Segment by commands
    segments = segment_by_command(stream.tokens)

    # Detect story type if not provided
    if not story_type:
        commands = [seg[0].metadata.get("name", "") for seg in segments]
        story_type = detect_story_type(commands)

    # Build phases
    phases = []
    for cmd_token, seg_tokens in segments:
        if cmd_token.metadata.get("name") == "_preamble":
            continue  # skip pre-command tokens
        phase = build_phase(cmd_token, seg_tokens, feature_slug)
        if phase:
            phases.append(phase)

    # Filter: for feature stories, remove phases that don't belong
    if feature_slug and story_type == "feature":
        filtered = []
        in_feature = False
        for phase in phases:
            stage = phase.data.get("stage", "")
            title = phase.data.get("title", "")

            if feature_slug in title:
                # Explicit slug match in command args
                in_feature = True
            elif stage == "scoping":
                # Scoping without explicit slug — check all descendants
                def _has_slug(nodes):
                    for n in nodes:
                        if feature_slug in (n.content or ""):
                            return True
                        if feature_slug in str(n.data):
                            return True
                        if n.children and _has_slug(n.children):
                            return True
                    return False
                slug_in_children = _has_slug(phase.children)
                if slug_in_children:
                    in_feature = True
                else:
                    in_feature = False
                    continue
            elif stage in ("research", "architect", "knowledge", "decisions"):
                # These are invoked mid-pipeline, keep if we're in the feature
                pass
            elif in_feature and stage in ("domains", "planning", "testing",
                                          "implementation", "refactor",
                                          "coordination", "pr", "retro",
                                          "complete", "resume"):
                # Pipeline continuation
                pass
            else:
                in_feature = False
                continue

            if in_feature:
                filtered.append(phase)
        phases = filtered

    # Extract metadata
    story = Story(
        story_type=story_type,
        title=feature_slug or "",
        sessions=stream.sessions,
        project=stream.project,
    )

    # Fill metadata from session_start tokens
    for t in stream.tokens:
        if t.type == "session_start":
            if not story.branch:
                story.branch = t.metadata.get("branch", "")
            if not story.model:
                story.model = t.metadata.get("model", "")
            if not story.started:
                story.started = t.timestamp

    # Aggregate
    story.phases = phases
    story.duration_ms = sum(p.duration_ms for p in phases)
    for p in phases:
        story.tokens.add(p.tokens)

    return story
