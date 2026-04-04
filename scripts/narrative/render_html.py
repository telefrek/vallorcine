#!/usr/bin/env python3
"""Stage 3 (HTML): Render a Story AST into a standalone HTML narrative.

Consumes the AST produced by parse.py and generates a single-file HTML
document with all CSS inline. No external dependencies (CDN, JS libraries,
web fonts). Uses native <details>/<summary> for collapsible content and
inline SVG for the timeline visualization.

Design principles:
    1. Dark theme — easy on the eyes, matches terminal aesthetics
    2. Phase-colored navigation — each pipeline stage has a distinct accent
    3. Collapsible detail — skim the cards, expand for full content
    4. Standalone — one file, no network requests, works offline
    5. Audit-aware — renders audit pipelines with finding cards and lens views

Usage:
    python render_html.py story-ast.json -o narrative.html
    python render_html.py story-ast.json  # stdout
"""

import argparse
import html
import sys
from typing import Callable

from model import Node, NodeType, Story, TokenUsage


# ---------------------------------------------------------------------------
# Formatting helpers (ported from render_narrative.py)
# ---------------------------------------------------------------------------

def format_duration(ms: int) -> str:
    """Format milliseconds into human-readable duration."""
    if ms == 0:
        return "\u2014"  # em dash for unknown/not measured
    if ms < 0:
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


def format_tokens_short(usage: TokenUsage) -> str:
    """Abbreviate token counts — e.g. '142K in / 38K out'."""
    billable = usage.billable_input
    if not billable and not usage.output:
        return "0"
    return f"{_abbreviate(billable)} in / {_abbreviate(usage.output)} out"


def format_tokens_detail(usage: TokenUsage) -> str:
    """Detailed token string including cache stats."""
    billable = usage.billable_input
    if not billable and not usage.output:
        return ""
    parts = [f"{_abbreviate(billable)} in"]
    if usage.cache_read:
        parts.append(f"({_abbreviate(usage.cache_read)} cached)")
    parts.append(f"/ {_abbreviate(usage.output)} out")
    return " ".join(parts)


def _abbreviate(n: int) -> str:
    """Abbreviate large numbers: 1500 -> '1.5K', 1500000 -> '1.5M'."""
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(n)


def _cost_estimate(usage: TokenUsage) -> str:
    """Estimate API cost from token counts using Opus pricing.

    Pricing (per million tokens, as of 2025):
        Input:        $15.00
        Output:       $75.00
        Cache read:    $1.50
        Cache create: $18.75

    Billable input = input + cache_create (each at their own rate).
    """
    input_cost = (usage.input / 1_000_000) * 15.00
    output_cost = (usage.output / 1_000_000) * 75.00
    cache_read_cost = (usage.cache_read / 1_000_000) * 1.50
    cache_create_cost = (usage.cache_create / 1_000_000) * 18.75
    total = input_cost + output_cost + cache_read_cost + cache_create_cost
    if total < 0.01:
        return "< $0.01"
    return f"${total:.2f}"


def _esc(text: str) -> str:
    """HTML-escape text content."""
    return html.escape(text, quote=True)


# ---------------------------------------------------------------------------
# Phase colors and metadata
# ---------------------------------------------------------------------------

PHASE_COLORS: dict[str, str] = {
    "scoping": "#4a9eff",
    "domains": "#4a9eff",
    "planning": "#b44aff",
    "testing": "#4aff7a",
    "implementation": "#ffb74a",
    "refactor": "#4af5ff",
    "coordination": "#b44aff",
    "pr": "#4a9eff",
    "retro": "#b44aff",
    "resume": "#ffb74a",
    "curation": "#4af5ff",
    "research": "#4a9eff",
    "architect": "#b44aff",
    "knowledge": "#4af5ff",
    "decisions": "#b44aff",
    # Audit phases
    "audit": "#ff6b4a",
    "scope": "#ff6b4a",
    "suspect": "#ffb74a",
    "prove-fix": "#4aff7a",
    "report": "#4a9eff",
}

PHASE_EMOJI: dict[str, str] = {
    "scoping": "&#x1F50D;",
    "domains": "&#x1F5FA;",
    "planning": "&#x1F3D7;",
    "testing": "&#x1F9EA;",
    "implementation": "&#x2699;",
    "refactor": "&#x1F527;",
    "coordination": "&#x1F500;",
    "pr": "&#x1F4CB;",
    "retro": "&#x1F504;",
    "resume": "&#x1F501;",
    "curation": "&#x1F52C;",
    "research": "&#x1F4DA;",
    "architect": "&#x1F3DB;",
    "knowledge": "&#x1F4D6;",
    "decisions": "&#x2696;",
    "audit": "&#x1F6E1;",
    "scope": "&#x1F50D;",
    "suspect": "&#x26A0;",
    "prove-fix": "&#x2705;",
    "report": "&#x1F4CB;",
}

# Lens colors for audit findings
LENS_COLORS: dict[str, str] = {
    "contracts": "#4a9eff",
    "state": "#b44aff",
    "data-flow": "#4aff7a",
    "transformation": "#ffb74a",
    "concurrency": "#ff6b4a",
    "lifecycle": "#4af5ff",
    "error-handling": "#ff6b4a",
    "boundary": "#b44aff",
}


# ---------------------------------------------------------------------------
# CSS
# ---------------------------------------------------------------------------

CSS = """
:root {
    --bg: #1a1a2e;
    --bg-surface: #16213e;
    --bg-card: #1e2a47;
    --bg-elevated: #253253;
    --text: #e0e0e0;
    --text-dim: #8892a0;
    --text-bright: #ffffff;
    --border: #2a3a5c;
    --accent-blue: #4a9eff;
    --accent-purple: #b44aff;
    --accent-green: #4aff7a;
    --accent-amber: #ffb74a;
    --accent-teal: #4af5ff;
    --accent-red: #ff6b4a;
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    background: var(--bg);
    color: var(--text);
    line-height: 1.6;
    max-width: 1100px;
    margin: 0 auto;
    padding: 2rem 1.5rem;
}

a { color: var(--accent-blue); text-decoration: none; }
a:hover { text-decoration: underline; }
code, .mono {
    font-family: "SF Mono", "Fira Code", "Cascadia Code", Consolas, monospace;
    font-size: 0.9em;
    background: var(--bg-elevated);
    padding: 0.15em 0.4em;
    border-radius: 3px;
}

/* Hero */
.hero {
    text-align: center;
    padding: 2rem 0 1.5rem;
    border-bottom: 1px solid var(--border);
    margin-bottom: 2rem;
}
.hero h1 {
    font-size: 1.8rem;
    font-weight: 700;
    color: var(--text-bright);
    margin-bottom: 1rem;
}
.hero .subtitle {
    color: var(--text-dim);
    font-size: 0.95rem;
    margin-bottom: 1rem;
}

/* Badges */
.badge-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    justify-content: center;
    margin: 1rem 0;
}
.badge {
    display: inline-block;
    font-size: 0.75rem;
    font-weight: 600;
    padding: 0.3em 0.7em;
    border-radius: 4px;
    color: var(--text-bright);
    white-space: nowrap;
}

/* Phase nav */
.phase-nav {
    display: flex;
    flex-wrap: wrap;
    gap: 0.4rem;
    margin: 1.5rem 0;
    padding: 0.75rem;
    background: var(--bg-surface);
    border-radius: 8px;
    border: 1px solid var(--border);
}
.phase-nav a {
    font-size: 0.85rem;
    padding: 0.35em 0.8em;
    border-radius: 4px;
    transition: background 0.15s;
}
.phase-nav a:hover {
    background: var(--bg-elevated);
    text-decoration: none;
}

/* Phase sections */
.phase {
    margin: 2rem 0;
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
}
.phase-header {
    padding: 1rem 1.25rem;
    display: flex;
    align-items: center;
    gap: 0.75rem;
}
.phase-header h2 {
    font-size: 1.25rem;
    font-weight: 600;
    color: var(--text-bright);
    flex: 1;
}
.phase-body {
    padding: 0.75rem 1.25rem 1.25rem;
}

/* Metric cards */
.metric-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
    margin-bottom: 1rem;
}
.metric-card {
    background: var(--bg-elevated);
    border-radius: 6px;
    padding: 0.6rem 1rem;
    min-width: 120px;
    flex: 1;
}
.metric-card .label {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--text-dim);
}
.metric-card .value {
    font-size: 1.1rem;
    font-weight: 600;
    color: var(--text-bright);
}

/* Conversation bubbles */
.bubble {
    margin: 0.5rem 0;
    padding: 0.75rem 1rem;
    border-radius: 8px;
    max-width: 85%;
    line-height: 1.5;
}
.bubble-agent {
    background: #1e3a5f;
    border-left: 3px solid var(--accent-blue);
    margin-right: auto;
}
.bubble-user {
    background: #1a3a2a;
    border-left: 3px solid var(--accent-green);
    margin-left: auto;
}
.bubble .speaker {
    font-size: 0.75rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    margin-bottom: 0.25rem;
}
.bubble-agent .speaker { color: var(--accent-blue); }
.bubble-user .speaker { color: var(--accent-green); }

/* Cards (research, architect, finding) */
.card {
    background: var(--bg-card);
    border-radius: 8px;
    border: 1px solid var(--border);
    padding: 1rem 1.25rem;
    margin: 0.75rem 0;
}
.card-title {
    font-weight: 600;
    color: var(--text-bright);
    margin-bottom: 0.5rem;
}

/* Alert boxes */
.alert {
    padding: 0.75rem 1rem;
    border-radius: 6px;
    margin: 0.5rem 0;
    border-left: 4px solid;
}
.alert-warning {
    background: #3d2f1f;
    border-color: #d29922;
}
.alert-error {
    background: #3d1f1f;
    border-color: #f85149;
}
.alert-success {
    background: #1a3a2a;
    border-color: #3fb950;
}
.alert-info {
    background: #1e3a5f;
    border-color: #4184e4;
}

/* Status badges */
.status-badge {
    display: inline-block;
    font-size: 0.75rem;
    font-weight: 600;
    padding: 0.2em 0.6em;
    border-radius: 12px;
    text-transform: uppercase;
    letter-spacing: 0.03em;
}
.status-confirmed { background: #1a3a2a; color: #4aff7a; }
.status-impossible { background: #3d1f1f; color: #f85149; }
.status-fix-impossible { background: #3d2f1f; color: #d29922; }
.status-phase0 { background: #253253; color: #4af5ff; }

/* Lens pills */
.lens-pill {
    display: inline-block;
    font-size: 0.7rem;
    font-weight: 600;
    padding: 0.15em 0.5em;
    border-radius: 10px;
    margin-left: 0.4rem;
}

/* TDD summary table */
table {
    width: 100%;
    border-collapse: collapse;
    margin: 0.75rem 0;
    font-size: 0.9rem;
}
th, td {
    padding: 0.5rem 0.75rem;
    text-align: left;
    border-bottom: 1px solid var(--border);
}
th {
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--text-dim);
    font-weight: 600;
}

/* Collapsible */
details {
    margin: 0.5rem 0;
}
details > summary {
    cursor: pointer;
    padding: 0.4rem 0;
    font-weight: 500;
    color: var(--text-dim);
    list-style: none;
}
details > summary::before {
    content: "\\25B6\\00A0";
    font-size: 0.7em;
}
details[open] > summary::before {
    content: "\\25BC\\00A0";
}
details > .detail-body {
    padding: 0.5rem 0 0.5rem 1rem;
    border-left: 2px solid var(--border);
    margin: 0.25rem 0;
}

/* Session break */
.session-break {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    margin: 1.25rem 0;
    color: var(--accent-red);
    font-weight: 500;
}
.session-break::before,
.session-break::after {
    content: "";
    flex: 1;
    height: 1px;
    background: var(--accent-red);
    opacity: 0.4;
}

/* SVG timeline */
.timeline-container {
    margin: 1.5rem 0;
    overflow-x: auto;
}
.timeline-container svg {
    display: block;
    margin: 0 auto;
}

/* Footer */
footer {
    margin-top: 3rem;
    padding-top: 1.5rem;
    border-top: 1px solid var(--border);
    color: var(--text-dim);
    font-size: 0.85rem;
}
footer .cost-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 0.75rem;
    margin: 1rem 0;
}

/* Work plan */
.work-plan ol {
    padding-left: 1.25rem;
    margin: 0.5rem 0;
}
.work-plan li {
    margin: 0.3rem 0;
}
.work-plan .estimate {
    color: var(--text-dim);
    font-size: 0.85rem;
}

/* Action group */
.action-list {
    list-style: none;
    padding: 0;
    font-size: 0.85rem;
}
.action-list li {
    padding: 0.2rem 0;
    color: var(--text-dim);
}
.action-list li code {
    color: var(--text);
}

/* Audit pipeline table */
.pipeline-table {
    margin: 1rem 0;
}
.pipeline-table td:first-child {
    font-weight: 600;
}

/* Finding cards grid */
.findings-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: 0.75rem;
    margin: 1rem 0;
}
.finding-card {
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 1rem;
}
.finding-card .finding-id {
    font-family: "SF Mono", Consolas, monospace;
    font-size: 0.8rem;
    color: var(--text-dim);
}
.finding-card .finding-title {
    font-weight: 600;
    color: var(--text-bright);
    margin: 0.25rem 0;
}
.finding-card .construct {
    font-family: "SF Mono", Consolas, monospace;
    font-size: 0.85rem;
    color: var(--accent-teal);
}
.finding-card .file-path {
    font-family: "SF Mono", Consolas, monospace;
    font-size: 0.8rem;
    color: var(--text-dim);
}
.finding-card .fix-desc, .finding-card .impossibility-reason {
    margin-top: 0.5rem;
    font-size: 0.9rem;
    line-height: 1.4;
}

/* Lens summary */
.lens-summary {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
    margin: 1rem 0;
}
.lens-group {
    background: var(--bg-card);
    border-radius: 8px;
    border: 1px solid var(--border);
    padding: 0.75rem 1rem;
    min-width: 150px;
}
.lens-group .lens-name {
    font-weight: 600;
    font-size: 0.85rem;
    margin-bottom: 0.25rem;
}
.lens-group .lens-count {
    font-size: 1.5rem;
    font-weight: 700;
    color: var(--text-bright);
}
"""


# ---------------------------------------------------------------------------
# SVG Timeline
# ---------------------------------------------------------------------------

def _render_timeline_svg(story: Story) -> str:
    """Generate an SVG horizontal timeline showing phase bars and session markers."""
    if not story.phases:
        return ""

    total_ms = story.duration_ms or sum(p.duration_ms for p in story.phases) or 1
    width = 900
    bar_height = 28
    top_margin = 30
    label_margin = 20
    session_marker_height = bar_height + 16
    svg_height = top_margin + bar_height + label_margin + 30

    parts: list[str] = []
    parts.append(f'<svg viewBox="0 0 {width} {svg_height}" '
                 f'width="{width}" height="{svg_height}" '
                 f'xmlns="http://www.w3.org/2000/svg" '
                 f'style="font-family: -apple-system, sans-serif;">')

    # Background track
    parts.append(f'  <rect x="0" y="{top_margin}" width="{width}" '
                 f'height="{bar_height}" rx="4" fill="#253253" />')

    # Phase bars
    cumulative_ms = 0
    for i, phase in enumerate(story.phases):
        stage = phase.data.get("stage", "")
        color = PHASE_COLORS.get(stage, "#4a9eff")
        phase_ms = max(phase.duration_ms, total_ms // 100)  # min 1% for visibility
        x = (cumulative_ms / total_ms) * width
        w = max((phase_ms / total_ms) * width, 2)

        parts.append(f'  <rect x="{x:.1f}" y="{top_margin}" '
                     f'width="{w:.1f}" height="{bar_height}" '
                     f'rx="3" fill="{color}" opacity="0.85" />')

        # Label if wide enough
        if w > 50:
            label = stage.title()
            tx = x + w / 2
            ty = top_margin + bar_height / 2 + 4
            parts.append(f'  <text x="{tx:.1f}" y="{ty:.1f}" '
                         f'text-anchor="middle" font-size="11" '
                         f'font-weight="600" fill="#fff">{_esc(label)}</text>')

        # Bottom label
        lx = x + w / 2
        ly = top_margin + bar_height + label_margin
        if w > 30:
            dur_label = format_duration(phase.duration_ms)
            parts.append(f'  <text x="{lx:.1f}" y="{ly:.1f}" '
                         f'text-anchor="middle" font-size="9" '
                         f'fill="#8892a0">{_esc(dur_label)}</text>')

        cumulative_ms += phase_ms

    # Session boundary markers (vertical dashed lines)
    # Walk phases looking for session_break children
    cum = 0
    for phase in story.phases:
        for child in phase.children:
            if child.node_type == NodeType.SESSION_BREAK:
                sx = (cum / total_ms) * width
                parts.append(f'  <line x1="{sx:.1f}" y1="{top_margin - 8}" '
                             f'x2="{sx:.1f}" y2="{top_margin + session_marker_height}" '
                             f'stroke="#f85149" stroke-width="1.5" '
                             f'stroke-dasharray="4,3" opacity="0.7" />')
        cum += max(phase.duration_ms, total_ms // 100)

    # Total duration annotation
    dur_text = format_duration(story.duration_ms)
    parts.append(f'  <text x="{width / 2}" y="16" text-anchor="middle" '
                 f'font-size="12" fill="#8892a0">Total: {_esc(dur_text)}</text>')

    parts.append('</svg>')
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Render context
# ---------------------------------------------------------------------------

class RenderContext:
    """Carries state across render calls within a single story."""

    def __init__(self, story: Story):
        self.story = story
        self.current_phase = ""
        self.phase_index = 0
        self.test_total_passed = 0
        self.test_total_failed = 0


# ---------------------------------------------------------------------------
# HTML helpers
# ---------------------------------------------------------------------------

def _metric_card(label: str, value: str) -> str:
    return (f'<div class="metric-card">'
            f'<div class="label">{_esc(label)}</div>'
            f'<div class="value">{_esc(value)}</div>'
            f'</div>')


def _status_badge(status: str) -> str:
    """Render an audit finding status badge."""
    s = status.upper().replace("_", " ")
    if "CONFIRMED" in s or s == "FIXED":
        return f'<span class="status-badge status-confirmed">{_esc(s)}</span>'
    if "FIX IMPOSSIBLE" in s:
        return f'<span class="status-badge status-fix-impossible">{_esc(s)}</span>'
    if "IMPOSSIBLE" in s:
        return f'<span class="status-badge status-impossible">{_esc(s)}</span>'
    return f'<span class="status-badge">{_esc(s)}</span>'


def _lens_pill(lens: str) -> str:
    """Render a colored lens pill."""
    color = LENS_COLORS.get(lens, "#8892a0")
    return (f'<span class="lens-pill" '
            f'style="background:{color}22;color:{color};border:1px solid {color}44">'
            f'{_esc(lens)}</span>')


def _truncate(text: str, max_chars: int = 300) -> tuple[str, bool]:
    """Truncate at word boundary."""
    if len(text) <= max_chars:
        return text, False
    cut = text.rfind(" ", 0, max_chars)
    if cut == -1:
        cut = max_chars
    return text[:cut], True


# ---------------------------------------------------------------------------
# Confirmation filter (same as markdown renderer)
# ---------------------------------------------------------------------------

_CONFIRMATION_RESPONSES = frozenset({
    "yes", "y", "no", "n", "ok", "okay", "sure", "continue",
    "create", "auto", "stop", "done", "skip", "proceed",
})


def _is_confirmation(text: str) -> bool:
    stripped = text.strip().rstrip(".!").lower()
    return stripped in _CONFIRMATION_RESPONSES


# TDD phases
_TDD_PHASES = frozenset({
    "testing", "implementation", "refactor", "coordination", "resume",
})


# ---------------------------------------------------------------------------
# Node renderers — one function per node type
# ---------------------------------------------------------------------------

def _render_conversation(node: Node, ctx: RenderContext) -> str:
    """Render a conversation as chat bubbles."""
    parts: list[str] = []
    exchanges = node.children

    is_scoping = ctx.current_phase == "scoping"

    bubbles: list[str] = []
    for child in exchanges:
        q = child.data.get("question", "")
        a = child.data.get("answer", "")
        if q and q.strip():
            q_short, q_trunc = _truncate(q)
            if q_trunc:
                bubbles.append(
                    f'<details class="bubble bubble-agent">'
                    f'<summary><span class="speaker">vallorcine</span> '
                    f'{_esc(q_short)}...</summary>'
                    f'<div class="detail-body">{_esc(q)}</div></details>'
                )
            else:
                bubbles.append(
                    f'<div class="bubble bubble-agent">'
                    f'<div class="speaker">vallorcine</div>'
                    f'{_esc(q)}</div>'
                )
        if a and not _is_confirmation(a):
            a_short, a_trunc = _truncate(a)
            if a_trunc:
                bubbles.append(
                    f'<details class="bubble bubble-user">'
                    f'<summary><span class="speaker">User</span> '
                    f'{_esc(a_short)}...</summary>'
                    f'<div class="detail-body">{_esc(a)}</div></details>'
                )
            else:
                bubbles.append(
                    f'<div class="bubble bubble-user">'
                    f'<div class="speaker">User</div>'
                    f'{_esc(a)}</div>'
                )

    if not bubbles:
        return ""

    content = "\n".join(bubbles)

    if is_scoping:
        return content

    count = node.data.get("exchange_count", len(exchanges))
    return (f'<details><summary>Conversation &mdash; {count} exchanges</summary>'
            f'<div class="detail-body">{content}</div></details>')


def _render_exchange(node: Node, ctx: RenderContext) -> str:
    """Render a standalone exchange."""
    answer = node.data.get("answer", node.content or "")
    if not answer or _is_confirmation(answer):
        return ""
    a_short, a_trunc = _truncate(answer)
    if a_trunc:
        return (f'<details class="bubble bubble-user">'
                f'<summary><span class="speaker">User</span> '
                f'{_esc(a_short)}...</summary>'
                f'<div class="detail-body">{_esc(answer)}</div></details>')
    return (f'<div class="bubble bubble-user">'
            f'<div class="speaker">User</div>'
            f'{_esc(answer)}</div>')


def _render_tdd_cycle(node: Node, ctx: RenderContext) -> str:
    """Render an interesting TDD cycle as a highlighted card."""
    if not node.interesting:
        return ""  # routine cycles handled by summary table

    name = _esc(node.data.get("unit_name", "Work unit"))
    duration = format_duration(node.duration_ms or node.data.get("duration_ms", 0))
    summary = node.data.get("summary", "")
    types = node.data.get("interesting_types", [])
    passed = node.data.get("test_passed", 0)
    failed = node.data.get("test_failed", 0)

    cls = "alert-warning" if ("escalation" in types or failed > 0) else "alert-info"

    lines = [f'<div class="alert {cls}">']
    lines.append(f'<strong>{name}</strong> &mdash; {_esc(duration)}')
    if failed:
        lines.append(f'<br>Tests: {passed} passed, {failed} failed')
    elif passed:
        lines.append(f'<br>Tests: {passed} passed')
    if types:
        lines.append(f'<br>Signals: {_esc(", ".join(types))}')
    if summary:
        parts = [p.strip() for p in summary.split(" — ")]
        for part in parts[1:]:
            lines.append(f'<br>&bull; {_esc(part)}')
    lines.append('</div>')
    return "\n".join(lines)


def _render_tdd_summary_table(cycles: list[Node], ctx: RenderContext) -> str:
    """Render routine TDD cycles as a compact table."""
    if not cycles:
        return ""

    story_total = (ctx.story.tokens.billable_input + ctx.story.tokens.output) or 1

    rows: list[str] = []
    for c in cycles:
        name = _esc(c.data.get("unit_name", "\u2014"))
        duration = format_duration(c.data.get("duration_ms", 0))
        passed = c.data.get("test_passed", 0)
        files = len(c.data.get("files_written", []))
        tests = f'<span style="color:var(--accent-green)">&#x2705; {passed}</span>' if passed else "\u2014"
        wu_total = c.tokens.billable_input + c.tokens.output
        pct = (wu_total / story_total) * 100

        rows.append(f'<tr><td>{name}</td><td>{_esc(duration)}</td>'
                    f'<td>{tests}</td><td>{files}</td><td>{pct:.0f}%</td></tr>')

    return (
        '<table>'
        '<thead><tr><th>Work Unit</th><th>Duration</th>'
        '<th>Tests</th><th>Files</th><th>% of total</th></tr></thead>'
        '<tbody>' + "\n".join(rows) + '</tbody></table>'
    )


def _render_brief(node: Node, ctx: RenderContext) -> str:
    """Render a feature brief as a blockquote card."""
    content = node.content or node.data.get("content", "")
    confirmed = node.data.get("confirmed", None)

    parts = ['<div class="card">']
    parts.append('<div class="card-title">Feature Brief</div>')
    if confirmed is True:
        parts.append('<span class="status-badge status-confirmed">Confirmed</span>')
    elif confirmed is False:
        parts.append('<span class="status-badge status-impossible">Rejected</span>')
    if content:
        short, trunc = _truncate(content, 500)
        if trunc:
            parts.append(f'<details><summary><blockquote>{_esc(short)}...</blockquote></summary>'
                         f'<blockquote>{_esc(content)}</blockquote></details>')
        else:
            parts.append(f'<blockquote>{_esc(content)}</blockquote>')
    parts.append('</div>')
    return "\n".join(parts)


def _render_research(node: Node, ctx: RenderContext) -> str:
    """Render a research card."""
    topic = _esc(node.data.get("topic", ""))
    subject = _esc(node.data.get("subject", ""))
    kb_path = _esc(node.data.get("kb_path", ""))
    findings = node.data.get("findings_summary", "")

    parts = ['<div class="card">']
    title = "&#x1F4DA; Research"
    if topic:
        title += f": {topic}"
    parts.append(f'<div class="card-title">{title}</div>')
    if subject:
        parts.append(f'<div>Subject: {subject}</div>')
    if kb_path:
        parts.append(f'<div>KB: <code>{kb_path}</code></div>')
    if findings:
        short, trunc = _truncate(findings, 400)
        if trunc:
            parts.append(f'<details><summary>{_esc(short)}...</summary>'
                         f'<div class="detail-body">{_esc(findings)}</div></details>')
        else:
            parts.append(f'<div>{_esc(findings)}</div>')
    parts.append('</div>')
    return "\n".join(parts)


def _render_architect(node: Node, ctx: RenderContext) -> str:
    """Render an architecture decision card."""
    question = _esc(node.data.get("question", ""))
    decision = _esc(node.data.get("decision", ""))
    rejected = node.data.get("rejected", [])
    adr_path = _esc(node.data.get("adr_path", ""))

    parts = ['<div class="card">']
    parts.append('<div class="card-title">&#x1F3DB; Architecture Decision</div>')
    if question:
        parts.append(f'<div><strong>Question:</strong> {question}</div>')
    if decision:
        parts.append(f'<div><strong>Decision:</strong> {decision}</div>')
    if rejected:
        struck = ", ".join(f"<del>{_esc(r)}</del>" for r in rejected)
        parts.append(f'<div><strong>Rejected:</strong> {struck}</div>')
    if adr_path:
        parts.append(f'<div><strong>ADR:</strong> <code>{adr_path}</code></div>')
    parts.append('</div>')
    return "\n".join(parts)


def _render_work_plan(node: Node, ctx: RenderContext) -> str:
    """Render a work plan as a numbered list."""
    units = node.data.get("units", [])
    if not units and node.content:
        return (f'<div class="card work-plan">'
                f'<div class="card-title">Work Plan</div>'
                f'<div>{_esc(node.content)}</div></div>')

    parts = ['<div class="card work-plan">']
    parts.append('<div class="card-title">Work Plan</div>')
    parts.append('<ol>')
    for u in units:
        name = _esc(u.get("name", u.get("unit_name", "")))
        estimate = u.get("estimate", "")
        est_html = f' <span class="estimate">({_esc(estimate)})</span>' if estimate else ""
        parts.append(f'<li>{name}{est_html}</li>')
    parts.append('</ol>')
    parts.append('</div>')
    return "\n".join(parts)


def _render_stage_transition(node: Node, ctx: RenderContext) -> str:
    """Render a stage transition command."""
    cmd = node.data.get("command", "")
    if not cmd:
        return ""
    args = _esc(node.data.get("args", ""))
    display = f'<code>{_esc(cmd)}</code>'
    if args:
        display += f" {args}"
    return f'<div style="color:var(--text-dim);margin:0.3rem 0"><strong>&rarr;</strong> {display}</div>'


def _render_session_break(node: Node, ctx: RenderContext) -> str:
    """Render a crash/recovery boundary."""
    gap = format_duration(node.data.get("gap_duration_ms", 0))
    return (f'<div class="session-break">'
            f'&#x26A0;&#xFE0F; Session crashed. Resumed {_esc(gap)} later.</div>')


def _render_test_result(node: Node, ctx: RenderContext) -> str:
    """Render a test result badge."""
    if ctx.current_phase not in _TDD_PHASES:
        return ""

    passed = node.data.get("passed", 0)
    failed = node.data.get("failed", 0)
    runs = node.data.get("run_count", 1)

    ctx.test_total_passed += passed
    ctx.test_total_failed += failed

    if failed:
        return (f'<div class="alert alert-warning">'
                f'&#x26A0;&#xFE0F; Tests: {passed} passed, {failed} failed '
                f'({runs} runs)</div>')
    return (f'<div style="color:var(--accent-green);margin:0.3rem 0">'
            f'&#x2705; Tests: {passed} passed ({runs} runs)</div>')


def _render_escalation(node: Node, ctx: RenderContext) -> str:
    """Render an escalation as a warning alert."""
    content = node.content or ""
    body = ""
    if content.strip():
        short, trunc = _truncate(content, 400)
        if trunc:
            body = (f'<details><summary>{_esc(short)}...</summary>'
                    f'<div class="detail-body">{_esc(content)}</div></details>')
        else:
            body = f'<div>{_esc(content)}</div>'

    return (f'<div class="alert alert-warning">'
            f'&#x26A0;&#xFE0F; <strong>Escalation</strong>{body}</div>')


def _render_action_group(node: Node, ctx: RenderContext) -> str:
    """Render file operations or subagent action summary."""
    # Subagent-style
    if "unit_name" in node.data:
        name = _esc(node.data.get("unit_name", "Action"))
        duration = format_duration(node.duration_ms or node.data.get("duration_ms", 0))
        summary = node.data.get("summary", "")
        detail = ""
        if summary:
            parts = [p.strip() for p in summary.split(" — ")]
            detail = " &mdash; ".join(_esc(p) for p in parts[1:]) if len(parts) > 1 else ""
        suffix = f" &mdash; {detail}" if detail else ""
        return (f'<div style="color:var(--text-dim);margin:0.3rem 0">'
                f'<strong>{name}</strong> <em>({_esc(duration)})</em>{suffix}</div>')

    # Tool call batch
    actions = node.data.get("actions", [])
    if not actions:
        return ""

    if len(actions) <= 3:
        items = [_esc(a.get("summary", f"{a.get('verb', '?')} {a.get('target', '')}"))
                 for a in actions]
        return (f'<div style="color:var(--text-dim);margin:0.3rem 0">'
                f'&#x1F4DD; <em>{"; ".join(items)}</em></div>')

    items = "\n".join(
        f'<li><code>{_esc(a.get("verb", ""))}</code> {_esc(a.get("target", ""))}</li>'
        for a in actions
    )
    return (f'<details><summary>&#x1F4DD; <strong>{len(actions)} file operations'
            f'</strong></summary>'
            f'<ul class="action-list">{items}</ul></details>')


def _render_prose(node: Node, ctx: RenderContext) -> str:
    """Render agent prose."""
    content = node.content or ""
    if not content.strip():
        return ""

    if node.interesting:
        short, trunc = _truncate(content, 600)
        if trunc:
            return (f'<div class="card">{_esc(short)}...'
                    f'<details><summary>Show full</summary>'
                    f'<div class="detail-body">{_esc(content)}</div></details></div>')
        return f'<div class="card">{_esc(content)}</div>'

    lines = content.split("\n")
    if len(lines) <= 5:
        return f'<div style="margin:0.3rem 0;color:var(--text-dim)">{_esc(content)}</div>'

    summary = _esc(lines[0][:120])
    return (f'<details><summary>{summary}...</summary>'
            f'<div class="detail-body">{_esc(content)}</div></details>')


def _render_metric(node: Node, ctx: RenderContext) -> str:
    """Render a computed metric."""
    label = node.data.get("label", "")
    value = node.data.get("value", node.content or "")
    if not label and not value:
        return ""
    return _metric_card(str(label), str(value))


def _render_pr(node: Node, ctx: RenderContext) -> str:
    """Render PR creation."""
    url = node.data.get("url", "")
    title = _esc(node.data.get("title", "Pull Request"))
    parts = ['<div class="card">']
    parts.append(f'<div class="card-title">&#x1F4CB; {title}</div>')
    if url:
        parts.append(f'<div><a href="{_esc(url)}">{_esc(url)}</a></div>')
    if node.content:
        parts.append(f'<div style="margin-top:0.5rem">{_esc(node.content)}</div>')
    parts.append('</div>')
    return "\n".join(parts)


def _render_retro(node: Node, ctx: RenderContext) -> str:
    """Render retrospective summary."""
    content = node.content or ""
    if not content.strip():
        return ""
    short, trunc = _truncate(content, 500)
    parts = ['<div class="card">']
    parts.append('<div class="card-title">&#x1F504; Retrospective</div>')
    if trunc:
        parts.append(f'<details><summary>{_esc(short)}...</summary>'
                     f'<div class="detail-body">{_esc(content)}</div></details>')
    else:
        parts.append(f'<div>{_esc(content)}</div>')
    parts.append('</div>')
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Audit-specific renderers
# ---------------------------------------------------------------------------

def _render_audit_cycle(node: Node, ctx: RenderContext) -> str:
    """Render an audit cycle with its findings and pipeline summary."""
    parts: list[str] = []
    stage = _esc(node.data.get("stage", ""))
    target = _esc(node.data.get("target", ""))
    finding_count = node.data.get("finding_count", 0)

    parts.append('<div class="card">')
    title = "Audit Cycle"
    if stage:
        title += f": {stage}"
    if target:
        title += f" &mdash; {target}"
    parts.append(f'<div class="card-title">&#x1F6E1; {title}</div>')

    # Metric row
    metrics = []
    if finding_count:
        metrics.append(_metric_card("Findings", str(finding_count)))
    if node.duration_ms:
        metrics.append(_metric_card("Duration", format_duration(node.duration_ms)))
    tok_str = format_tokens_detail(node.tokens)
    if tok_str:
        metrics.append(_metric_card("Tokens", tok_str))
    if metrics:
        parts.append(f'<div class="metric-row">{"".join(metrics)}</div>')

    # Render children (findings, prose, etc.)
    for child in node.children:
        rendered = _render_node(child, ctx)
        if rendered:
            parts.append(rendered)

    parts.append('</div>')
    return "\n".join(parts)


def _render_audit_finding(node: Node, ctx: RenderContext) -> str:
    """Render an individual audit finding as a card."""
    finding_id = _esc(node.data.get("finding_id", ""))
    title = _esc(node.data.get("title", node.data.get("description", "")))
    status = node.data.get("status", "")
    construct = _esc(node.data.get("construct", ""))
    file_path = _esc(node.data.get("file_path", node.data.get("file", "")))
    lens = node.data.get("lens", "")
    fix_desc = node.data.get("fix_description", node.data.get("fix", ""))
    impossibility = node.data.get("impossibility_reason", node.data.get("reason", ""))
    phase0 = node.data.get("phase0", False)

    parts = ['<div class="finding-card">']

    # Header line: ID + status + lens
    header = ""
    if finding_id:
        header += f'<span class="finding-id">{finding_id}</span> '
    if status:
        header += _status_badge(status) + " "
    if lens:
        header += _lens_pill(lens)
    if phase0:
        header += ' <span class="status-badge status-phase0">Phase 0</span>'
    if header:
        parts.append(f'<div>{header}</div>')

    if title:
        parts.append(f'<div class="finding-title">{title}</div>')
    if construct:
        parts.append(f'<div class="construct">{construct}</div>')
    if file_path:
        parts.append(f'<div class="file-path">{file_path}</div>')
    if fix_desc:
        parts.append(f'<div class="fix-desc">{_esc(str(fix_desc))}</div>')
    if impossibility:
        parts.append(f'<div class="impossibility-reason" style="color:var(--accent-red)">'
                     f'{_esc(str(impossibility))}</div>')

    parts.append('</div>')
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Dispatch table
# ---------------------------------------------------------------------------

RENDERERS: dict[str, Callable[[Node, RenderContext], str]] = {
    NodeType.CONVERSATION: _render_conversation,
    NodeType.EXCHANGE: _render_exchange,
    NodeType.TDD_CYCLE: _render_tdd_cycle,
    NodeType.RESEARCH: _render_research,
    NodeType.ARCHITECT: _render_architect,
    NodeType.STAGE_TRANSITION: _render_stage_transition,
    NodeType.SESSION_BREAK: _render_session_break,
    NodeType.TEST_RESULT: _render_test_result,
    NodeType.ESCALATION: _render_escalation,
    NodeType.ACTION_GROUP: _render_action_group,
    NodeType.PROSE: _render_prose,
    NodeType.METRIC: _render_metric,
    NodeType.BRIEF: _render_brief,
    NodeType.WORK_PLAN: _render_work_plan,
    NodeType.PR: _render_pr,
    NodeType.RETRO: _render_retro,
    NodeType.AUDIT_CYCLE: _render_audit_cycle,
    NodeType.AUDIT_FINDING: _render_audit_finding,
}


def _render_node(node: Node, ctx: RenderContext) -> str:
    """Dispatch a node to its type-specific renderer."""
    renderer = RENDERERS.get(node.node_type)
    if renderer:
        return renderer(node, ctx)
    if node.content:
        return f'<div style="margin:0.3rem 0">{_esc(node.content[:500])}</div>'
    return ""


# ---------------------------------------------------------------------------
# Prominent / background type classification (same as markdown renderer)
# ---------------------------------------------------------------------------

_PROMINENT_TYPES = frozenset({
    NodeType.CONVERSATION, NodeType.EXCHANGE, NodeType.ESCALATION,
    NodeType.SESSION_BREAK, NodeType.RESEARCH, NodeType.ARCHITECT,
    NodeType.AUDIT_CYCLE, NodeType.AUDIT_FINDING,
})

_BACKGROUND_TYPES = frozenset({
    NodeType.PROSE, NodeType.ACTION_GROUP, NodeType.TEST_RESULT,
    NodeType.STAGE_TRANSITION, NodeType.METRIC,
})


# ---------------------------------------------------------------------------
# Phase renderer
# ---------------------------------------------------------------------------

def _render_phase(node: Node, ctx: RenderContext) -> str:
    """Render a complete phase section."""
    stage = node.data.get("stage", "")
    title = node.data.get("title", stage.title())
    duration = format_duration(node.duration_ms)
    ctx.current_phase = stage

    # Strip feature slug from title
    story_title = ctx.story.title
    if story_title and f"\u2014 {story_title}" in title:
        title = title.replace(f" \u2014 {story_title}", "").strip()
    if story_title and f"- {story_title}" in title:
        title = title.replace(f" - {story_title}", "").strip()

    color = PHASE_COLORS.get(stage, "#4a9eff")
    emoji = PHASE_EMOJI.get(stage, "&#x1F4CC;")
    phase_id = f"phase-{ctx.phase_index}"
    ctx.phase_index += 1

    parts: list[str] = []
    parts.append(f'<section class="phase" id="{phase_id}">')
    parts.append(f'<div class="phase-header" style="background:{color}15;'
                 f'border-bottom:2px solid {color}">')
    parts.append(f'<h2>{emoji} {_esc(title)}</h2>')
    parts.append(f'<span style="color:var(--text-dim);font-size:0.85rem">'
                 f'{_esc(duration)}</span>')
    parts.append('</div>')
    parts.append('<div class="phase-body">')

    # Metric cards
    metrics: list[str] = []
    metrics.append(_metric_card("Duration", duration))
    tok_str = format_tokens_detail(node.tokens)
    if tok_str:
        metrics.append(_metric_card("Tokens", tok_str))
    cost = _cost_estimate(node.tokens)
    if cost != "< $0.01":
        metrics.append(_metric_card("Est. Cost", cost))
    if metrics:
        parts.append(f'<div class="metric-row">{"".join(metrics)}</div>')

    # Categorize children
    routine_cycles: list[Node] = []
    interesting_cycles: list[Node] = []
    prominent: list[Node] = []
    background: list[Node] = []

    for child in node.children:
        if child.node_type == NodeType.TDD_CYCLE:
            if child.interesting:
                interesting_cycles.append(child)
            else:
                routine_cycles.append(child)
        elif child.node_type in _PROMINENT_TYPES:
            prominent.append(child)
        elif child.node_type == NodeType.BRIEF or child.node_type == NodeType.WORK_PLAN:
            prominent.append(child)
        elif child.node_type == NodeType.PR or child.node_type == NodeType.RETRO:
            prominent.append(child)
        else:
            background.append(child)

    # Prominent children inline
    for child in prominent:
        rendered = _render_node(child, ctx)
        if rendered:
            parts.append(rendered)

    # Interesting TDD cycles expanded
    for cycle in interesting_cycles:
        rendered = _render_tdd_cycle(cycle, ctx)
        if rendered:
            parts.append(rendered)

    # Routine TDD cycles as table
    if routine_cycles:
        parts.append(_render_tdd_summary_table(routine_cycles, ctx))

    # Background narration collapsed
    if background:
        bg_parts: list[str] = []
        for child in background:
            rendered = _render_node(child, ctx)
            if rendered:
                bg_parts.append(rendered)
        if bg_parts:
            file_ops = sum(1 for c in background
                          if c.node_type == NodeType.ACTION_GROUP)
            prose_count = sum(1 for c in background
                            if c.node_type == NodeType.PROSE)
            summary_parts = []
            if prose_count:
                summary_parts.append(f"{prose_count} steps")
            if file_ops:
                summary_parts.append(f"{file_ops} file operations")
            summary_label = ", ".join(summary_parts) if summary_parts else "details"

            parts.append(f'<details><summary>&#x1F4CB; Show {_esc(summary_label)}'
                         f'</summary><div class="detail-body">')
            parts.extend(bg_parts)
            parts.append('</div></details>')

    parts.append('</div>')  # phase-body
    parts.append('</section>')
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Audit summary helpers
# ---------------------------------------------------------------------------

def _collect_audit_findings(story: Story) -> list[Node]:
    """Walk the AST and collect all audit_finding nodes."""
    findings: list[Node] = []

    def _walk(nodes: list[Node]):
        for n in nodes:
            if n.node_type == NodeType.AUDIT_FINDING:
                findings.append(n)
            if n.children:
                _walk(n.children)

    for phase in story.phases:
        _walk(phase.children)
    return findings


def _render_audit_lens_summary(findings: list[Node]) -> str:
    """Render a lens-grouped summary of audit findings."""
    if not findings:
        return ""

    by_lens: dict[str, list[Node]] = {}
    for f in findings:
        lens = f.data.get("lens", "unknown")
        by_lens.setdefault(lens, []).append(f)

    parts = ['<h3>Findings by Lens</h3>', '<div class="lens-summary">']
    for lens, items in sorted(by_lens.items()):
        color = LENS_COLORS.get(lens, "#8892a0")
        confirmed = sum(1 for i in items
                       if "CONFIRMED" in (i.data.get("status", "")).upper())
        impossible = sum(1 for i in items
                        if "IMPOSSIBLE" in (i.data.get("status", "")).upper())
        parts.append(
            f'<div class="lens-group" style="border-top:3px solid {color}">'
            f'<div class="lens-name" style="color:{color}">{_esc(lens)}</div>'
            f'<div class="lens-count">{len(items)}</div>'
            f'<div style="font-size:0.8rem;color:var(--text-dim)">'
        )
        if confirmed:
            parts.append(f'&#x2705; {confirmed} fixed ')
        if impossible:
            parts.append(f'&#x274C; {impossible} impossible ')
        parts.append('</div></div>')
    parts.append('</div>')
    return "\n".join(parts)


def _render_audit_findings_grid(findings: list[Node], ctx: RenderContext) -> str:
    """Render all findings in a grid layout."""
    if not findings:
        return ""
    parts = ['<h3>All Findings</h3>', '<div class="findings-grid">']
    for f in findings:
        parts.append(_render_audit_finding(f, ctx))
    parts.append('</div>')
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Count helpers
# ---------------------------------------------------------------------------

def count_new_tests(story: Story) -> int:
    """Count new tests from TDD cycles."""
    total = 0

    def _walk(nodes: list[Node]):
        nonlocal total
        for n in nodes:
            if n.node_type == NodeType.TDD_CYCLE:
                total += n.data.get("test_passed", 0)
            if n.children:
                _walk(n.children)

    for phase in story.phases:
        _walk(phase.children)
    return total


# ---------------------------------------------------------------------------
# Hero section
# ---------------------------------------------------------------------------

def _render_hero(story: Story, ctx: RenderContext) -> str:
    """Render the hero header section."""
    parts: list[str] = []

    # Title
    title = story.title or "Session"
    story_type = story.story_type
    if story_type == "feature":
        heading = f"Building <code>{_esc(title)}</code> with vallorcine"
    elif story_type == "curation":
        heading = f"Curating <code>{_esc(title)}</code>"
    elif story_type == "research":
        heading = f"Researching <code>{_esc(title)}</code>"
    elif story_type == "architect":
        heading = f"Architecture: <code>{_esc(title)}</code>"
    elif story_type == "audit":
        heading = f"Audit: <code>{_esc(title)}</code>"
    else:
        heading = f"<code>{_esc(title)}</code>"

    parts.append('<header class="hero">')
    parts.append(f'<h1>{heading}</h1>')

    # Subtitle with project/branch
    subtitle_parts = []
    if story.project:
        subtitle_parts.append(_esc(story.project))
    if story.branch:
        subtitle_parts.append(f'<code>{_esc(story.branch)}</code>')
    if story.started:
        subtitle_parts.append(_esc(story.started))
    if subtitle_parts:
        parts.append(f'<div class="subtitle">{" &middot; ".join(subtitle_parts)}</div>')

    # Badge row
    duration = format_duration(story.duration_ms)
    tokens_short = format_tokens_short(story.tokens)
    new_tests = count_new_tests(story)
    model = story.model or "unknown"
    sessions = len(story.sessions)

    parts.append('<div class="badge-row">')

    def _badge(label: str, value: str, color: str) -> str:
        return f'<span class="badge" style="background:{color}">{_esc(label)}: {_esc(value)}</span>'

    parts.append(_badge("Duration", duration, "#1e3a5f"))
    parts.append(_badge("Tokens", tokens_short, "#3a1e5f"))
    parts.append(_badge("Model", model, "#3a3a3a"))
    cost = _cost_estimate(story.tokens)
    parts.append(_badge("Est. Cost", cost, "#5f3a1e"))
    if story.cli_version:
        parts.append(_badge("Claude Code", f"v{story.cli_version}", "#3a3a3a"))
    if story.vallorcine_version:
        parts.append(_badge("vallorcine", f"v{story.vallorcine_version}", "#5f3a1e"))
    if new_tests:
        parts.append(_badge("New Tests", str(new_tests), "#1e3a2a"))
    if sessions > 1:
        parts.append(_badge("Sessions", f"{sessions} (crash recovery)", "#5f5f1e"))
    parts.append('</div>')

    # SVG Timeline
    timeline = _render_timeline_svg(story)
    if timeline:
        parts.append(f'<div class="timeline-container">{timeline}</div>')

    parts.append('</header>')
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Phase navigation
# ---------------------------------------------------------------------------

def _render_phase_nav(story: Story) -> str:
    """Render clickable phase navigation tabs."""
    if len(story.phases) <= 1:
        return ""

    parts = ['<nav class="phase-nav">']
    for i, phase in enumerate(story.phases):
        stage = phase.data.get("stage", "")
        title = phase.data.get("title", stage.title())
        # Strip feature slug
        if story.title and f"\u2014 {story.title}" in title:
            title = title.replace(f" \u2014 {story.title}", "").strip()
        if story.title and f"- {story.title}" in title:
            title = title.replace(f" - {story.title}", "").strip()
        color = PHASE_COLORS.get(stage, "#4a9eff")
        emoji = PHASE_EMOJI.get(stage, "")
        duration = format_duration(phase.duration_ms)
        parts.append(f'<a href="#phase-{i}" style="color:{color}">'
                     f'{emoji} {_esc(title)} '
                     f'<span style="font-size:0.75rem;color:var(--text-dim)">'
                     f'({_esc(duration)})</span></a>')
    parts.append('</nav>')
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Phase breakdown table
# ---------------------------------------------------------------------------

def _render_phase_breakdown(story: Story) -> str:
    """Render the phase breakdown table shown between nav and content."""
    if not story.phases:
        return ""

    total_tokens = (story.tokens.billable_input + story.tokens.output) or 1

    parts: list[str] = []
    parts.append('<details><summary><strong>Phase Breakdown</strong></summary>')
    parts.append('<div class="detail-body">')
    parts.append('<table><thead><tr>')
    parts.append('<th>Phase</th><th>Duration</th><th>Tokens (in)</th>'
                 '<th>Tokens (out)</th><th>Est. Cost</th><th>% of total</th>')
    parts.append('</tr></thead><tbody>')

    for i, phase in enumerate(story.phases):
        stage = phase.data.get("stage", "\u2014")
        title = phase.data.get("title", stage.title())
        if story.title and f"\u2014 {story.title}" in title:
            title = title.replace(f" \u2014 {story.title}", "").strip()
        color = PHASE_COLORS.get(stage, "#4a9eff")
        dur = format_duration(phase.duration_ms)
        inp = _abbreviate(phase.tokens.billable_input)
        out = _abbreviate(phase.tokens.output)
        cost = _cost_estimate(phase.tokens)
        phase_total = phase.tokens.billable_input + phase.tokens.output
        pct = (phase_total / total_tokens) * 100

        parts.append(
            f'<tr><td><a href="#phase-{i}" style="color:{color}">'
            f'{_esc(title)}</a></td>'
            f'<td>{_esc(dur)}</td><td>{_esc(inp)}</td><td>{_esc(out)}</td>'
            f'<td>{_esc(cost)}</td><td>{pct:.0f}%</td></tr>'
        )

    parts.append('</tbody></table>')
    parts.append('</div></details>')
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Footer
# ---------------------------------------------------------------------------

def _render_footer(story: Story) -> str:
    """Render the footer with token breakdown and metadata."""
    parts: list[str] = []
    parts.append('<footer>')

    # Token breakdown
    u = story.tokens
    parts.append('<h3>Token &amp; Cost Breakdown</h3>')
    parts.append('<div class="cost-grid">')
    parts.append(_metric_card("Billable Input", _abbreviate(u.billable_input)))
    parts.append(_metric_card("Output", _abbreviate(u.output)))
    parts.append(_metric_card("Cache Read", _abbreviate(u.cache_read)))
    parts.append(_metric_card("Cache Create", _abbreviate(u.cache_create)))
    parts.append(_metric_card("Total Context", _abbreviate(u.total_context)))
    parts.append(_metric_card("Est. Total Cost", _cost_estimate(u)))
    parts.append('</div>')

    # Metadata
    meta_parts = []
    if story.model:
        meta_parts.append(f"Model: {_esc(story.model)}")
    if story.cli_version:
        meta_parts.append(f"Claude Code: v{_esc(story.cli_version)}")
    if story.vallorcine_version:
        meta_parts.append(f"vallorcine: v{_esc(story.vallorcine_version)}")
    if story.sessions:
        meta_parts.append(f"Sessions: {len(story.sessions)}")
    if story.started:
        meta_parts.append(f"Started: {_esc(story.started)}")
    if meta_parts:
        parts.append(f'<div style="margin-top:1rem">{" &middot; ".join(meta_parts)}</div>')

    parts.append('<div style="margin-top:1rem;font-size:0.8rem">')
    parts.append('Generated by <a href="https://github.com/telefrek/vallorcine">vallorcine</a> '
                 'showcase tools.')
    parts.append('</div>')
    parts.append('</footer>')
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Main render function
# ---------------------------------------------------------------------------

def render_story(story: Story) -> str:
    """Render a Story AST into a complete standalone HTML document."""
    ctx = RenderContext(story)
    is_audit = story.story_type == "audit"

    parts: list[str] = []

    # Document head
    title_text = _esc(story.title or "Narrative")
    parts.append('<!DOCTYPE html>')
    parts.append('<html lang="en">')
    parts.append('<head>')
    parts.append(f'<meta charset="utf-8">')
    parts.append(f'<meta name="viewport" content="width=device-width, initial-scale=1">')
    parts.append(f'<title>{title_text} \u2014 vallorcine narrative</title>')
    parts.append(f'<style>{CSS}</style>')
    parts.append('</head>')
    parts.append('<body>')

    # Hero
    parts.append(_render_hero(story, ctx))

    # Main content
    parts.append('<main>')

    # Phase nav
    parts.append(_render_phase_nav(story))

    # Phase breakdown table
    parts.append(_render_phase_breakdown(story))

    # Audit-specific summary sections
    if is_audit:
        findings = _collect_audit_findings(story)
        if findings:
            parts.append(_render_audit_lens_summary(findings))
            # Findings grid is collapsed — serves as navigable index
            # Per-phase rendering below shows findings in full context
            parts.append('<details class="findings-index">')
            parts.append(f'<summary>All {len(findings)} findings (expand to browse)</summary>')
            parts.append(_render_audit_findings_grid(findings, ctx))
            parts.append('</details>')

    # Phase sections
    for phase in story.phases:
        parts.append(_render_phase(phase, ctx))

    parts.append('</main>')

    # Footer
    parts.append(_render_footer(story))

    parts.append('</body>')
    parts.append('</html>')

    return "\n".join(parts)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    """CLI entry point: load a Story AST JSON and render to HTML."""
    parser = argparse.ArgumentParser(
        description="Render a Story AST into a standalone HTML narrative."
    )
    parser.add_argument("story_file", help="Path to story AST JSON file")
    parser.add_argument("--output", "-o", help="Output file (default: stdout)")
    args = parser.parse_args()

    story = Story.load(args.story_file)
    html_output = render_story(story)

    if args.output:
        with open(args.output, "w") as f:
            f.write(html_output)
        print(f"Wrote {len(html_output)} bytes to {args.output}", file=sys.stderr)
    else:
        print(html_output)


if __name__ == "__main__":
    main()
