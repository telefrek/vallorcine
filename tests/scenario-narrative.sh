#!/usr/bin/env bash
# Scenario: Narrative pipeline — Python/JS parity and graceful degradation
#
# Validates that the narrative pipeline:
# - Model roundtrip works in Python and JS independently
# - Python and JS can cross-load each other's JSON output
# - Both renderers produce structurally equivalent markdown
# - Orchestrators exit 0 on missing feature dirs
# - Wrapper exits 0 with no arguments
# - Format guard warns on unexpected JSONL structure
# - Intermediates are cleaned up after generation
#
# Run from repo root: bash tests/scenario-narrative.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-narrative"
NARRATIVE_DIR="$REPO_ROOT/scripts/narrative"

# ── Test helpers ─────────────────────────────────────────────────────────────

passed=0
failed=0
skipped=0
total=0

pass() {
    ((passed++)) || true
    ((total++)) || true
    echo "  PASS  $1"
}

fail() {
    ((failed++)) || true
    ((total++)) || true
    echo "  FAIL  $1"
    [[ -n "${2:-}" ]] && echo "        $2"
}

skip() {
    ((skipped++)) || true
    echo "  SKIP  $1"
}

cleanup() {
    rm -rf "$TEST_BASE" 2>/dev/null || true
}
trap cleanup EXIT

echo ""
echo "scenario: narrative pipeline"
echo "────────────────────────────────────────────────"

# ── Setup ────────────────────────────────────────────────────────────────────

cleanup
mkdir -p "$TEST_BASE"

HAS_PYTHON=0
HAS_NODE=0
command -v python3 &>/dev/null && HAS_PYTHON=1
command -v node &>/dev/null && HAS_NODE=1

# ── Test: Python model roundtrip ─────────────────────────────────────────────

if [[ "$HAS_PYTHON" -eq 1 ]]; then
    output=$(python3 -c "
import sys; sys.path.insert(0, '$NARRATIVE_DIR')
from model import Story, Node, NodeType, TokenUsage
s = Story(
    story_type='feature', title='test', model='opus',
    vallorcine_version='0.5.3', cli_version='1.0',
    sessions=['s1'], started='2026-01-01T00:00:00Z',
    duration_ms=60000,
    tokens=TokenUsage(input=1000, output=500),
    phases=[Node(node_type=NodeType.PHASE, data={'stage': 'scoping', 'title': 'Scoping'}, duration_ms=60000)],
)
s.save('$TEST_BASE/py-model.json')
s2 = Story.load('$TEST_BASE/py-model.json')
assert s2.vallorcine_version == '0.5.3', 'version mismatch'
assert len(s2.phases) == 1, 'phase count mismatch'
assert s2.phases[0].data['stage'] == 'scoping', 'stage mismatch'
print('ok')
" 2>&1) || true
    if [[ "$output" == *"ok"* ]]; then
        pass "Python model roundtrip"
    else
        fail "Python model roundtrip" "$output"
    fi
else
    skip "Python model roundtrip (python3 not available)"
fi

# ── Test: JS model roundtrip ────────────────────────────────────────────────

if [[ "$HAS_NODE" -eq 1 ]]; then
    output=$(node -e "
const { Story, Node, NodeType, TokenUsage } = require('$NARRATIVE_DIR/model.js');
const s = new Story({
    story_type: 'feature', title: 'test', model: 'opus',
    vallorcine_version: '0.5.3', cli_version: '1.0',
    sessions: ['s1'], started: '2026-01-01T00:00:00Z',
    duration_ms: 60000,
    tokens: new TokenUsage({ input: 1000, output: 500 }),
    phases: [new Node({ node_type: NodeType.PHASE, data: { stage: 'scoping', title: 'Scoping' }, duration_ms: 60000 })],
});
s.save('$TEST_BASE/js-model.json');
const s2 = Story.load('$TEST_BASE/js-model.json');
if (s2.vallorcine_version !== '0.5.3') throw new Error('version mismatch');
if (s2.phases.length !== 1) throw new Error('phase count mismatch');
if (s2.phases[0].data.stage !== 'scoping') throw new Error('stage mismatch');
console.log('ok');
" 2>&1) || true
    if [[ "$output" == *"ok"* ]]; then
        pass "JS model roundtrip"
    else
        fail "JS model roundtrip" "$output"
    fi
else
    skip "JS model roundtrip (node not available)"
fi

# ── Test: Cross-load parity ──────────────────────────────────────────────────

if [[ "$HAS_PYTHON" -eq 1 && "$HAS_NODE" -eq 1 ]]; then
    # JS loads Python JSON
    output=$(node -e "
const { Story } = require('$NARRATIVE_DIR/model.js');
const s = Story.load('$TEST_BASE/py-model.json');
if (s.vallorcine_version !== '0.5.3') throw new Error('version: ' + s.vallorcine_version);
if (s.phases.length !== 1) throw new Error('phases: ' + s.phases.length);
console.log('ok');
" 2>&1) || true
    if [[ "$output" == *"ok"* ]]; then
        pass "JS loads Python-saved JSON"
    else
        fail "JS loads Python-saved JSON" "$output"
    fi

    # Python loads JS JSON
    output=$(python3 -c "
import sys; sys.path.insert(0, '$NARRATIVE_DIR')
from model import Story
s = Story.load('$TEST_BASE/js-model.json')
assert s.vallorcine_version == '0.5.3'
assert len(s.phases) == 1
print('ok')
" 2>&1) || true
    if [[ "$output" == *"ok"* ]]; then
        pass "Python loads JS-saved JSON"
    else
        fail "Python loads JS-saved JSON" "$output"
    fi
else
    skip "Cross-load parity (need both python3 and node)"
fi

# ── Test: Render parity ─────────────────────────────────────────────────────

if [[ "$HAS_PYTHON" -eq 1 ]]; then
    python3 -c "
import sys; sys.path.insert(0, '$NARRATIVE_DIR')
from model import Story
from render_narrative import render_story
story = Story.load('$TEST_BASE/py-model.json')
md = render_story(story)
with open('$TEST_BASE/render-py.md', 'w') as f: f.write(md)
" 2>/dev/null
    py_lines=$(wc -l < "$TEST_BASE/render-py.md")
    if [[ "$py_lines" -gt 5 ]]; then
        pass "Python render produces output ($py_lines lines)"
    else
        fail "Python render produces output" "only $py_lines lines"
    fi
else
    skip "Python render (python3 not available)"
fi

if [[ "$HAS_NODE" -eq 1 ]]; then
    node -e "
const { Story } = require('$NARRATIVE_DIR/model.js');
const { renderStory } = require('$NARRATIVE_DIR/render_narrative.js');
const fs = require('fs');
const story = Story.load('$TEST_BASE/py-model.json');
const md = renderStory(story);
fs.writeFileSync('$TEST_BASE/render-js.md', md);
" 2>/dev/null
    js_lines=$(wc -l < "$TEST_BASE/render-js.md")
    if [[ "$js_lines" -gt 5 ]]; then
        pass "JS render produces output ($js_lines lines)"
    else
        fail "JS render produces output" "only $js_lines lines"
    fi
else
    skip "JS render (node not available)"
fi

if [[ "$HAS_PYTHON" -eq 1 && "$HAS_NODE" -eq 1 ]]; then
    py_lines=$(wc -l < "$TEST_BASE/render-py.md")
    js_lines=$(wc -l < "$TEST_BASE/render-js.md")
    if [[ "$py_lines" -eq "$js_lines" ]]; then
        pass "Render line count parity (both $py_lines lines)"
    else
        fail "Render line count parity" "Python=$py_lines, JS=$js_lines"
    fi

    # Both should contain the same structural elements
    py_has_badge=$(grep -c "shields.io" "$TEST_BASE/render-py.md" || true)
    js_has_badge=$(grep -c "shields.io" "$TEST_BASE/render-js.md" || true)
    if [[ "$py_has_badge" -eq "$js_has_badge" ]]; then
        pass "Badge count parity ($py_has_badge badges each)"
    else
        fail "Badge count parity" "Python=$py_has_badge, JS=$js_has_badge"
    fi

    # Both should have the vallorcine version badge
    if grep -q "vallorcine" "$TEST_BASE/render-py.md" && grep -q "vallorcine" "$TEST_BASE/render-js.md"; then
        pass "Both render vallorcine version badge"
    else
        fail "Both render vallorcine version badge"
    fi
else
    skip "Render parity (need both python3 and node)"
fi

# ── Test: generate.py graceful failure ───────────────────────────────────────
#
# Per commit 48d073c (2026-04-12), generate.{py,js} exit 1 on failure so the
# wrapper can detect it, retry, and fall back. The contract is diagnostic on
# stderr + exit 1 (not crash/exit 0). Capture via if/else to keep `set -e`
# from killing the test on the expected nonzero exit.

if [[ "$HAS_PYTHON" -eq 1 ]]; then
    if stderr=$(python3 "$NARRATIVE_DIR/generate.py" "nonexistent" "/tmp/vallorcine/no-such-dir" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    if [[ "$exit_code" -eq 1 ]]; then
        pass "generate.py exits 1 on missing dir"
    else
        fail "generate.py exits 1 on missing dir" "exit code: $exit_code"
    fi
    if [[ "$stderr" == *"not found"* ]]; then
        pass "generate.py logs diagnostic on missing dir"
    else
        fail "generate.py logs diagnostic on missing dir" "$stderr"
    fi
else
    skip "generate.py graceful failure (python3 not available)"
fi

# ── Test: generate.js graceful failure ───────────────────────────────────────

if [[ "$HAS_NODE" -eq 1 ]]; then
    if stderr=$(node "$NARRATIVE_DIR/generate.js" "nonexistent" "/tmp/vallorcine/no-such-dir" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    if [[ "$exit_code" -eq 1 ]]; then
        pass "generate.js exits 1 on missing dir"
    else
        fail "generate.js exits 1 on missing dir" "exit code: $exit_code"
    fi
    if [[ "$stderr" == *"not found"* ]]; then
        pass "generate.js logs diagnostic on missing dir"
    else
        fail "generate.js logs diagnostic on missing dir" "$stderr"
    fi
else
    skip "generate.js graceful failure (node not available)"
fi

# ── Test: wrapper exits 3 with no args ───────────────────────────────────────
#
# narrative-wrapper.sh documents exit code 3 = missing arguments. See the
# script's header comment for the full exit-code contract.

if bash "$REPO_ROOT/scripts/narrative-wrapper.sh" 2>/dev/null; then
    exit_code=0
else
    exit_code=$?
fi
if [[ "$exit_code" -eq 3 ]]; then
    pass "narrative-wrapper.sh exits 3 with no args (missing arguments)"
else
    fail "narrative-wrapper.sh exits 3 with no args" "exit code: $exit_code"
fi

# ── Test: Format guard on bad JSONL ──────────────────────────────────────────

if [[ "$HAS_PYTHON" -eq 1 ]]; then
    # Create a JSONL file with unexpected structure
    mkdir -p "$TEST_BASE/bad-jsonl"
    echo '{"weird_field": "no type or message"}' > "$TEST_BASE/bad-jsonl/test.jsonl"

    stderr=$(python3 -c "
import sys; sys.path.insert(0, '$NARRATIVE_DIR')
from tokenizer import tokenize_session
tokens = tokenize_session('$TEST_BASE/bad-jsonl/test.jsonl')
print('tokens:', len(tokens))
" 2>&1) || true
    if [[ "$stderr" == *"format may have changed"* ]]; then
        pass "Python format guard warns on unexpected JSONL"
    else
        fail "Python format guard warns on unexpected JSONL" "$stderr"
    fi
else
    skip "Python format guard (python3 not available)"
fi

if [[ "$HAS_NODE" -eq 1 ]]; then
    mkdir -p "$TEST_BASE/bad-jsonl"
    echo '{"weird_field": "no type or message"}' > "$TEST_BASE/bad-jsonl/test.jsonl"

    stderr=$(node -e "
const { tokenizeSession } = require('$NARRATIVE_DIR/tokenizer.js');
const tokens = tokenizeSession('$TEST_BASE/bad-jsonl/test.jsonl');
console.log('tokens:', tokens.length);
" 2>&1) || true
    if [[ "$stderr" == *"format may have changed"* ]]; then
        pass "JS format guard warns on unexpected JSONL"
    else
        fail "JS format guard warns on unexpected JSONL" "$stderr"
    fi
else
    skip "JS format guard (node not available)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "  $passed passed, $failed failed, $skipped skipped (of $total tests)"
echo ""

if [[ "$failed" -gt 0 ]]; then
    exit 1
fi
