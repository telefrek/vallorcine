#!/usr/bin/env python3
"""Render a story JSON into article-ready markdown.

Takes the intermediate JSON produced by translate.py and generates a
markdown document suitable for blog posts, Medium articles, or static
site content.

Usage:
    python render_markdown.py story.json -o article.md
    python render_markdown.py story.json  # stdout
"""

import argparse
import json
import re
import sys
from datetime import datetime


# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------

def format_duration(ms: int) -> str:
    """Format milliseconds into human-readable duration."""
    if ms <= 0:
        return "< 1s"
    seconds = ms / 1000
    if seconds < 60:
        return f"{seconds:.0f}s"
    minutes = seconds / 60
    if minutes < 60:
        secs = int(seconds % 60)
        if secs:
            return f"{int(minutes)}m {secs}s"
        return f"{int(minutes)}m"
    hours = minutes / 60
    mins = int(minutes % 60)
    return f"{int(hours)}h {mins}m"


def format_tokens(tokens: dict, verbose: bool = False) -> str:
    """Format token counts into a readable string."""
    inp = tokens.get("input", 0)
    out = tokens.get("output", 0)
    cache_read = tokens.get("cache_read", 0)
    cache_create = tokens.get("cache_create", 0)

    # Total context = input + cache_create + cache_read
    # But cache_read is free/discounted, so show separately
    billable_in = inp + cache_create
    total_context = billable_in + cache_read

    if not total_context and not out:
        return ""

    def abbreviate(n):
        if n >= 1_000_000:
            return f"{n/1_000_000:.1f}M"
        if n >= 1_000:
            return f"{n/1_000:.1f}K"
        return str(n)

    if verbose and cache_read:
        return (f"{abbreviate(billable_in)} in ({abbreviate(cache_read)} cached) "
                f"/ {abbreviate(out)} out")
    return f"{abbreviate(billable_in)} in / {abbreviate(out)} out"


def format_timestamp(iso: str) -> str:
    """Format an ISO timestamp into a readable time."""
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        return dt.strftime("%H:%M")
    except (ValueError, TypeError):
        return ""


def clean_agent_prose(text: str) -> str:
    """Clean up agent prose for article presentation.
    Removes code fence decorative banners but keeps substantive content."""
    # Remove decorative box-drawing banners
    lines = text.split("\n")
    cleaned = []
    in_banner = False

    for line in lines:
        stripped = line.strip()
        # Skip pure box-drawing lines
        if stripped and all(c in "─━═│┌┐└┘├┤┬┴┼╔╗╚╝╠╣╦╩╬ " for c in stripped):
            continue
        # Skip ```-only lines that wrap banners
        if stripped == "```" and not in_banner:
            in_banner = True
            continue
        if stripped == "```" and in_banner:
            in_banner = False
            continue
        if in_banner:
            # Keep banner content but strip box chars
            clean = stripped.lstrip("─━═ ")
            if clean:
                cleaned.append(clean)
            continue
        cleaned.append(line)

    # Remove orphaned headings — heading lines with no body text following
    # them before the next heading or end of block
    final = []
    for i, line in enumerate(cleaned):
        stripped = line.strip()
        if stripped.startswith("#") and len(stripped) < 80:
            has_body = False
            for j in range(i + 1, len(cleaned)):
                next_stripped = cleaned[j].strip()
                if not next_stripped:
                    continue
                if next_stripped.startswith("#"):
                    break
                has_body = True
                break
            if not has_body:
                continue
        final.append(line)

    return "\n".join(final).strip()


def truncate_prose(text: str, max_lines: int = 30) -> str:
    """Truncate long prose blocks, keeping the first and last parts."""
    lines = text.split("\n")
    if len(lines) <= max_lines:
        return text
    keep = max_lines // 2
    return "\n".join(lines[:keep] + ["", "*[...]*", ""] + lines[-keep:])


# ---------------------------------------------------------------------------
# Story type renderers
# ---------------------------------------------------------------------------

def render_story(story: dict) -> str:
    """Render a story dict into markdown."""
    story_type = story.get("story_type", "feature")
    renderer = {
        "feature": render_feature_story,
        "curation": render_curation_story,
        "research": render_research_story,
        "architect": render_architect_story,
    }.get(story_type, render_feature_story)
    return renderer(story)


def render_feature_story(story: dict) -> str:
    """Render a feature story as an article."""
    lines = []

    # Title and metadata
    title = story.get("title", "Feature")
    lines.append(f"# Building `{title}` with vallorcine")
    lines.append("")

    # Summary block
    duration = format_duration(story.get("duration_ms", 0))
    tokens = format_tokens(story.get("tokens", {}), verbose=True)
    sessions = len(story.get("sessions", []))
    chapters = story.get("chapters", [])
    model = story.get("model", "")

    meta_parts = []
    if duration:
        meta_parts.append(f"**Duration:** {duration}")
    if tokens:
        meta_parts.append(f"**Tokens:** {tokens}")
    if sessions > 1:
        meta_parts.append(f"**Sessions:** {sessions} (crash recovery)")
    if model:
        meta_parts.append(f"**Model:** {model}")

    if meta_parts:
        lines.append("> " + " | ".join(meta_parts))
        lines.append("")

    # Pipeline overview
    stages = []
    for ch in chapters:
        stage = ch.get("stage", "")
        dur = format_duration(ch.get("duration_ms", 0))
        stages.append(f"`{stage}` ({dur})")
    if stages:
        lines.append(f"**Pipeline:** {' → '.join(stages)}")
        lines.append("")

    lines.append("---")
    lines.append("")

    # Render each chapter
    for i, chapter in enumerate(chapters):
        lines.extend(render_feature_chapter(chapter, i + 1, len(chapters)))
        lines.append("")

    # Footer
    lines.append("---")
    lines.append("")
    lines.append("*Generated by [vallorcine](https://github.com/telefrek/vallorcine) showcase tools.*")

    return "\n".join(lines)


def render_feature_chapter(chapter: dict, num: int, total: int) -> list[str]:
    """Render a single feature chapter."""
    lines = []
    stage = chapter.get("stage", "")
    title = chapter.get("title", stage)
    duration = format_duration(chapter.get("duration_ms", 0))
    tokens = format_tokens(chapter.get("tokens", {}))

    # Chapter heading
    lines.append(f"## {num}. {title}")
    lines.append("")

    meta = f"*{duration}*"
    if tokens:
        meta += f" *| {tokens}*"
    lines.append(meta)
    lines.append("")

    moments = chapter.get("moments", [])
    i = 0
    while i < len(moments):
        moment = moments[i]
        mtype = moment.get("type", "")

        if mtype == "session_break":
            lines.extend(render_session_break(moment))

        elif mtype == "user_prompt":
            # Show the command invocation
            content = moment.get("content", "")
            if content:
                lines.append(f"```")
                lines.append(f"$ {content}")
                lines.append(f"```")
                lines.append("")

        elif mtype == "user_response":
            content = moment.get("content", "")
            if content:
                lines.append(f"> **User:** {content}")
                lines.append("")

        elif mtype == "agent_prose":
            content = moment.get("content", "")
            interesting = moment.get("interesting", False)
            if content:
                cleaned = clean_agent_prose(content)
                if not cleaned.strip():
                    i += 1
                    continue
                if interesting:
                    # Interesting prose gets full treatment
                    lines.append(truncate_prose(cleaned, 30))
                    lines.append("")
                else:
                    # Routine prose — keep if short, truncate aggressively if long
                    truncated = truncate_prose(cleaned, 12)
                    lines.append(truncated)
                    lines.append("")

        elif mtype == "escalation":
            content = moment.get("content", "")
            if content:
                cleaned = clean_agent_prose(content)
                lines.append(f"> **⚠ Escalation**")
                lines.append(f"> {truncate_prose(cleaned, 10)}")
                lines.append("")

        elif mtype == "refactor_finding":
            content = moment.get("content", "")
            if content:
                cleaned = clean_agent_prose(content)
                lines.append(f"> **🔍 Refactor finding**")
                lines.append(f"> {truncate_prose(cleaned, 10)}")
                lines.append("")

        elif mtype == "action":
            summary = moment.get("summary", "")
            if summary:
                lines.append(f"→ *{summary}*")
                lines.append("")

        elif mtype == "stage_transition":
            summary = moment.get("summary", "")
            if summary:
                lines.append(f"**{summary}**")
                lines.append("")

        elif mtype == "subagent_summary":
            lines.extend(render_subagent_summary(moment))

        elif mtype == "test_result":
            # Batch consecutive test results into one line
            results = [moment]
            while i + 1 < len(moments) and moments[i + 1].get("type") == "test_result":
                i += 1
                results.append(moments[i])
            lines.extend(render_test_results(results))

        i += 1

    return lines


def render_session_break(moment: dict) -> list[str]:
    """Render a session break as a narrative interruption."""
    lines = []
    gap = format_duration(moment.get("gap_duration_ms", 0))
    state = moment.get("state_at_break", "")
    recovery = moment.get("recovery_method", "")

    lines.append("---")
    lines.append("")
    parts = ["*Session interrupted.*"]
    if gap:
        parts.append(f"*Resumed {gap} later")
    if recovery:
        parts[-1] += f" via `{recovery}`"
    parts[-1] += ".*"
    if state:
        parts.append(f"*State at break: {state}.*")
    lines.append(" ".join(parts))
    lines.append("")
    lines.append("---")
    lines.append("")
    return lines


def render_subagent_summary(moment: dict) -> list[str]:
    """Render a subagent summary as a compact block."""
    lines = []
    desc = moment.get("description", "Subagent")
    duration = format_duration(moment.get("duration_ms", 0))
    summary = moment.get("summary", "")
    files = moment.get("files_written", [])
    interesting = moment.get("interesting", False)

    # Compact one-line for routine, expanded for interesting
    if interesting:
        lines.append(f"### 🔧 {desc} ({duration})")
        lines.append("")
        if summary:
            # Parse the summary for structured info
            lines.append(summary)
            lines.append("")
    else:
        if summary:
            lines.append(f"**{desc}** ({duration}) — {summary}")
        else:
            lines.append(f"**{desc}** ({duration})")
        lines.append("")

    return lines


def render_test_results(results: list[dict]) -> list[str]:
    """Render a batch of test results into a summary line."""
    lines = []
    total_interesting = sum(1 for r in results if r.get("interesting"))

    # Strip redundant "Tests: " prefix from summaries for batching
    def clean_summary(s):
        return s.removeprefix("Tests: ") if s.startswith("Tests: ") else s

    if len(results) == 1:
        r = results[0]
        summary = r.get("summary", "")
        if r.get("interesting"):
            lines.append(f"⚠ {summary}")
        else:
            lines.append(f"✓ {summary}")
    else:
        # Aggregate batch into totals
        import re as _re
        total_passed = 0
        total_failed = 0
        for r in results:
            s = r.get("summary", "")
            p = _re.search(r"(\d+) passed", s)
            f = _re.search(r"(\d+) failed", s)
            if p:
                total_passed += int(p.group(1))
            if f:
                total_failed += int(f.group(1))
        if total_failed:
            lines.append(f"⚠ Tests: {total_passed} passed, {total_failed} failed")
        else:
            # Just show last result if all passing
            lines.append(f"✓ {summaries[-1]}")

    lines.append("")
    return lines


# ---------------------------------------------------------------------------
# Non-feature story renderers (stub — expand when needed)
# ---------------------------------------------------------------------------

def render_curation_story(story: dict) -> str:
    """Render a curation story."""
    lines = []
    lines.append(f"# Curation session — {story.get('title', 'code review')}")
    lines.append("")

    duration = format_duration(story.get("duration_ms", 0))
    tokens = format_tokens(story.get("tokens", {}))
    lines.append(f"> **Duration:** {duration} | **Tokens:** {tokens}")
    lines.append("")

    for i, chapter in enumerate(story.get("chapters", [])):
        lines.extend(render_feature_chapter(chapter, i + 1, len(story.get("chapters", []))))
        lines.append("")

    lines.append("---")
    lines.append("*Generated by [vallorcine](https://github.com/telefrek/vallorcine) showcase tools.*")
    return "\n".join(lines)


def render_research_story(story: dict) -> str:
    """Render a research story."""
    lines = []
    lines.append(f"# Research session — {story.get('title', 'investigation')}")
    lines.append("")

    for i, chapter in enumerate(story.get("chapters", [])):
        lines.extend(render_feature_chapter(chapter, i + 1, len(story.get("chapters", []))))
        lines.append("")

    lines.append("---")
    lines.append("*Generated by [vallorcine](https://github.com/telefrek/vallorcine) showcase tools.*")
    return "\n".join(lines)


def render_architect_story(story: dict) -> str:
    """Render an architect decision story."""
    lines = []
    lines.append(f"# Architecture decision — {story.get('title', 'decision')}")
    lines.append("")

    for i, chapter in enumerate(story.get("chapters", [])):
        lines.extend(render_feature_chapter(chapter, i + 1, len(story.get("chapters", []))))
        lines.append("")

    lines.append("---")
    lines.append("*Generated by [vallorcine](https://github.com/telefrek/vallorcine) showcase tools.*")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Render a story JSON into article-ready markdown."
    )
    parser.add_argument("story_file", help="Path to the story JSON file")
    parser.add_argument("--output", "-o", help="Output file (default: stdout)")

    args = parser.parse_args()

    with open(args.story_file) as f:
        story = json.load(f)

    markdown = render_story(story)

    if args.output:
        with open(args.output, "w") as f:
            f.write(markdown)
        print(f"Wrote {len(markdown)} bytes to {args.output}", file=sys.stderr)
    else:
        print(markdown)


if __name__ == "__main__":
    main()
