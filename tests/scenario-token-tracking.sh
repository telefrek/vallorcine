#!/usr/bin/env bash
# Scenario: Token tracking hooks produce correct output
#
# Validates that:
# - Stop hook logs tokens on stage transitions
# - Stop hook updates Actual Tokens column in status.md
# - Stop hook logs final stage before terminal state cleanup
# - Stop hook cleans up state file on terminal state
# - Stop hook is a no-op when stage hasn't changed
# - Statusline does NOT write to token-log.md
# - Statusline resets baseline on stage transition
# - Cold start initializes tracking for active features
# - Cold start skips terminal features
#
# Run from repo root: bash tests/scenario-token-tracking.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-token-tracking"

# ── Test helpers ─────────────────────────────────────────────────────────────

passed=0
failed=0
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

cleanup() {
    rm -rf "$TEST_BASE" 2>/dev/null || true
}
trap cleanup EXIT

echo ""
echo "scenario: token tracking"
echo "────────────────────────────────────────────────"

# ── Setup: create a mock project with transcript ─────────────────────────────

cleanup
mkdir -p "$TEST_BASE/project/.claude/scripts"
mkdir -p "$TEST_BASE/project/.feature/test-feature"

# Copy scripts
cp "$REPO_ROOT/scripts/token-stop-hook.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/token-usage.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/statusline.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/subagent-hook.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/statusline-wrapper.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/subagent-hook-wrapper.sh" "$TEST_BASE/project/.claude/scripts/"

# Create a mock transcript directory matching _find_transcript's path scheme
PROJECT_PATH="$TEST_BASE/project"
# _find_transcript strips leading / and replaces / with -
project_id=$(echo "$PROJECT_PATH" | sed 's|^/||; s|/|-|g')
TRANSCRIPT_DIR="$HOME/.claude/projects/-${project_id}"
mkdir -p "$TRANSCRIPT_DIR"

# Create a mock transcript with realistic token usage entries
TRANSCRIPT="$TRANSCRIPT_DIR/test-session.jsonl"
cat > "$TRANSCRIPT" <<'JSONL'
{"type":"assistant","message":{"stop_reason":"end_turn","usage":{"input_tokens":100,"output_tokens":200,"cache_creation_input_tokens":50,"cache_read_input_tokens":300}}}
{"type":"assistant","message":{"stop_reason":"end_turn","usage":{"input_tokens":150,"output_tokens":350,"cache_creation_input_tokens":75,"cache_read_input_tokens":400}}}
{"type":"assistant","message":{"stop_reason":"end_turn","usage":{"input_tokens":500,"output_tokens":1000,"cache_creation_input_tokens":100,"cache_read_input_tokens":600}}}
{"type":"assistant","message":{"stop_reason":"end_turn","usage":{"input_tokens":800,"output_tokens":2000,"cache_creation_input_tokens":200,"cache_read_input_tokens":1000}}}
JSONL

# Helper to create status.md with a given stage/substage
write_status() {
    local stage="$1"
    local substage="$2"
    cat > "$PROJECT_PATH/.feature/test-feature/status.md" <<EOF
---
feature: "test-feature"
created: "2026-03-18 19:30"
---

# Feature Status — test-feature

## Current Position
**Stage:** $stage
**Substage:** $substage

## Stage Completion

| Stage | Status | Completed | Est. Tokens | Actual Tokens | Notes |
|-------|--------|-----------|-------------|---------------|-------|
| Scoping | complete | 2026-03-18 | ~5K | — | |
| Domains | complete | 2026-03-18 | ~4K | — | |
| Planning | complete | 2026-03-18 | ~8K | — | |
| Testing | complete | 2026-03-18 | ~8K | — | |
| Implementation | complete | 2026-03-18 | ~8K | — | |
| Refactor | complete | 2026-03-18 | ~6K | — | |
EOF
}

# Helper to create .token-state (JSON format)
write_token_state() {
    local stage="$1"
    local start_line="${2:-1}"
    cat > "$PROJECT_PATH/.claude/.token-state" <<EOF
{"feature_dir":".feature/test-feature","cached_stage":"$stage","transcript":"$TRANSCRIPT","start_line":$start_line,"timestamp":"2026-03-18T13:00:00Z"}
EOF
}

# Helper to create .token-state in legacy shell variable format
write_token_state_legacy() {
    local stage="$1"
    local start_line="${2:-1}"
    cat > "$PROJECT_PATH/.claude/.token-state" <<EOF
feature_dir=.feature/test-feature
cached_stage=$stage
transcript=$TRANSCRIPT
start_line=$start_line
timestamp=2026-03-18T13:00:00Z
EOF
}

# ── Test 1: Stage transition logs tokens to token-log.md ─────────────────────

echo ""
echo "  testing: stop hook stage transitions"

# Setup: tracking scoping, status.md says domains (transition happened)
write_status "domains" "resolving"
write_token_state "scoping" "1"
rm -f "$PROJECT_PATH/.feature/test-feature/token-log.md"

(cd "$PROJECT_PATH" && echo "" | bash .claude/scripts/token-stop-hook.sh)

if [[ -f "$PROJECT_PATH/.feature/test-feature/token-log.md" ]] && \
   grep -q "| scoping |" "$PROJECT_PATH/.feature/test-feature/token-log.md"; then
    pass "stop hook logs tokens on scoping→domains transition"
else
    fail "stop hook logs tokens on scoping→domains transition" \
        "token-log.md missing or no scoping entry"
fi

# ── Test 2: Stop hook updates Actual Tokens in status.md ─────────────────────

if grep "Scoping" "$PROJECT_PATH/.feature/test-feature/status.md" | grep -qv "—"; then
    pass "stop hook updates Actual Tokens column in status.md"
else
    fail "stop hook updates Actual Tokens column in status.md" \
        "Scoping row still shows —"
fi

# ── Test 3: Stop hook updates state file to new stage (JSON format) ──────────

if grep -q '"cached_stage":"domains"' "$PROJECT_PATH/.claude/.token-state" 2>/dev/null; then
    pass "stop hook updates cached_stage to new stage"
else
    fail "stop hook updates cached_stage to new stage"
fi

# ── Test 4: Same stage is a no-op ───────────────────────────────────────────

# Now status.md says domains, cached_stage is domains — no transition
line_count_before=$(wc -l < "$PROJECT_PATH/.feature/test-feature/token-log.md")

(cd "$PROJECT_PATH" && echo "" | bash .claude/scripts/token-stop-hook.sh)

line_count_after=$(wc -l < "$PROJECT_PATH/.feature/test-feature/token-log.md")
if [[ "$line_count_before" == "$line_count_after" ]]; then
    pass "stop hook is no-op when stage unchanged"
else
    fail "stop hook is no-op when stage unchanged" \
        "token-log.md grew from $line_count_before to $line_count_after lines"
fi

# ── Test 5: Terminal state logs final stage THEN cleans up ───────────────────

echo ""
echo "  testing: terminal state handling"

# Setup: tracking refactor, status.md transitions to pr/created
write_status "pr" "created"
write_token_state "refactor" "1"

# Reset token-log to track what gets appended
rm -f "$PROJECT_PATH/.feature/test-feature/token-log.md"

(cd "$PROJECT_PATH" && echo "" | bash .claude/scripts/token-stop-hook.sh)

if [[ -f "$PROJECT_PATH/.feature/test-feature/token-log.md" ]] && \
   grep -q "| refactor |" "$PROJECT_PATH/.feature/test-feature/token-log.md"; then
    pass "stop hook logs final stage (refactor) before terminal cleanup"
else
    fail "stop hook logs final stage (refactor) before terminal cleanup" \
        "token-log.md missing or no refactor entry"
fi

# ── Test 6: Terminal state updates Actual Tokens for final stage ─────────────

if grep "Refactor" "$PROJECT_PATH/.feature/test-feature/status.md" | grep -qv "—"; then
    pass "stop hook updates Actual Tokens for final stage"
else
    fail "stop hook updates Actual Tokens for final stage" \
        "Refactor row still shows —"
fi

# ── Test 7: Terminal state cleans up state file ──────────────────────────────

if [[ ! -f "$PROJECT_PATH/.claude/.token-state" ]]; then
    pass "stop hook removes state file on terminal state"
else
    fail "stop hook removes state file on terminal state" \
        ".token-state still exists"
fi

# ── Test 8: Terminal + same stage cleans up without double-logging ────────────

# Simulate: already in terminal, hook fires again
write_status "pr" "created"
write_token_state "pr" "1"
rm -f "$PROJECT_PATH/.feature/test-feature/token-log.md"

(cd "$PROJECT_PATH" && echo "" | bash .claude/scripts/token-stop-hook.sh)

if [[ ! -f "$PROJECT_PATH/.feature/test-feature/token-log.md" ]]; then
    pass "terminal + same stage does not create token-log entries"
else
    fail "terminal + same stage does not create token-log entries" \
        "token-log.md was created"
fi

if [[ ! -f "$PROJECT_PATH/.claude/.token-state" ]]; then
    pass "terminal + same stage cleans up state file"
else
    fail "terminal + same stage cleans up state file"
fi

# ── Test 9: Statusline does NOT write to token-log.md ────────────────────────

echo ""
echo "  testing: statusline isolation"

# Setup: active feature with stage transition for statusline to detect
write_status "testing" "writing-tests"
write_token_state "planning" "1"
rm -f "$PROJECT_PATH/.feature/test-feature/token-log.md"

# Statusline needs JSON on stdin with context window info
statusline_input='{"context_window":{"used_percentage":25.5,"context_window_size":200000}}'

(cd "$PROJECT_PATH" && echo "$statusline_input" | bash .claude/scripts/statusline.sh > /dev/null 2>&1)

if [[ ! -f "$PROJECT_PATH/.feature/test-feature/token-log.md" ]]; then
    pass "statusline does not write to token-log.md on stage transition"
else
    if grep -q "| planning |" "$PROJECT_PATH/.feature/test-feature/token-log.md" 2>/dev/null; then
        fail "statusline does not write to token-log.md on stage transition" \
            "statusline wrote a planning row to token-log.md"
    else
        pass "statusline does not write to token-log.md on stage transition"
    fi
fi

# ── Test 10: Statusline resets baseline on stage transition ──────────────────

BASELINE_FILE="$PROJECT_PATH/.claude/.statusline-baseline"
if [[ -f "$BASELINE_FILE" ]] && grep -q '"baseline_stage":"testing"' "$BASELINE_FILE"; then
    pass "statusline resets baseline to new stage (JSON format)"
else
    fail "statusline resets baseline to new stage (JSON format)" \
        "baseline not updated to testing"
fi

# ── Test 11: Cold start initializes tracking ─────────────────────────────────

echo ""
echo "  testing: cold start"

rm -f "$PROJECT_PATH/.claude/.token-state"
write_status "implementation" "implementing"

(cd "$PROJECT_PATH" && echo "" | bash .claude/scripts/token-stop-hook.sh)

if [[ -f "$PROJECT_PATH/.claude/.token-state" ]] && \
   grep -q '"cached_stage":"implementation"' "$PROJECT_PATH/.claude/.token-state"; then
    pass "cold start initializes tracking for active feature (JSON format)"
else
    fail "cold start initializes tracking for active feature (JSON format)"
fi

# ── Test 12: Cold start skips terminal features ──────────────────────────────

rm -f "$PROJECT_PATH/.claude/.token-state"
write_status "pr" "complete"

(cd "$PROJECT_PATH" && echo "" | bash .claude/scripts/token-stop-hook.sh)

if [[ ! -f "$PROJECT_PATH/.claude/.token-state" ]]; then
    pass "cold start skips terminal features"
else
    fail "cold start skips terminal features" \
        ".token-state created for pr/complete feature"
fi

# ── Test 13: Token log uses 8-column format ──────────────────────────────────

echo ""
echo "  testing: log format consistency"

write_status "testing" "writing-tests"
write_token_state "planning" "1"
rm -f "$PROJECT_PATH/.feature/test-feature/token-log.md"

(cd "$PROJECT_PATH" && echo "" | bash .claude/scripts/token-stop-hook.sh)

if [[ -f "$PROJECT_PATH/.feature/test-feature/token-log.md" ]]; then
    # Count pipe separators in the data row (should be 9 for 8 columns: |col1|col2|...|col8|)
    row=$(grep "| planning |" "$PROJECT_PATH/.feature/test-feature/token-log.md")
    pipe_count=$(echo "$row" | tr -cd '|' | wc -c)
    if [[ "$pipe_count" -eq 9 ]]; then
        pass "token log data rows have 8 columns"
    else
        fail "token log data rows have 8 columns" \
            "found $pipe_count pipe chars (expected 9): $row"
    fi
else
    fail "token log data rows have 8 columns" "no token-log.md"
fi

# ── Test 14: Backwards-compat: legacy shell variable .token-state ─────────────

echo ""
echo "  testing: backwards compatibility"

write_status "testing" "writing-tests"
write_token_state_legacy "planning" "1"
rm -f "$PROJECT_PATH/.feature/test-feature/token-log.md"

(cd "$PROJECT_PATH" && echo "" | bash .claude/scripts/token-stop-hook.sh)

if [[ -f "$PROJECT_PATH/.feature/test-feature/token-log.md" ]] && \
   grep -q "| planning |" "$PROJECT_PATH/.feature/test-feature/token-log.md"; then
    pass "stop hook reads legacy shell variable .token-state"
else
    fail "stop hook reads legacy shell variable .token-state" \
        "token-log.md missing or no planning entry"
fi

# After transition, state should be written in JSON format
if grep -q '"cached_stage":"testing"' "$PROJECT_PATH/.claude/.token-state" 2>/dev/null; then
    pass "stop hook rewrites legacy state as JSON on transition"
else
    fail "stop hook rewrites legacy state as JSON on transition"
fi

# ── Test 15: Backwards-compat: statusline reads legacy baseline ───────────────

# Write a legacy shell variable baseline
printf 'baseline_stage=testing\nbaseline_ctx_tokens=51000\nbaseline_timestamp=2026-03-18T14:00:00Z\n' \
    > "$PROJECT_PATH/.claude/.statusline-baseline"
write_token_state "testing" "1"
write_status "testing" "writing-tests"

statusline_input='{"context_window":{"used_percentage":30.0,"context_window_size":200000}}'
output=$(cd "$PROJECT_PATH" && echo "$statusline_input" | bash .claude/scripts/statusline.sh 2>/dev/null)

if [[ -n "$output" ]] && echo "$output" | grep -q "testing"; then
    pass "statusline reads legacy shell variable baseline"
else
    fail "statusline reads legacy shell variable baseline" \
        "output: $output"
fi

# ── Test 16: Subagent state — SubagentStart writes state ──────────────────────

echo ""
echo "  testing: subagent hooks"

rm -f "$PROJECT_PATH/.claude/.subagent-state"

subagent_start='{"hook_event_name":"SubagentStart","agent_id":"abc123","description":"test-writer"}'
(cd "$PROJECT_PATH" && echo "$subagent_start" | bash .claude/scripts/subagent-hook.sh)

if [[ -f "$PROJECT_PATH/.claude/.subagent-state" ]] && \
   grep -q '"active":true' "$PROJECT_PATH/.claude/.subagent-state" && \
   grep -q '"description":"test-writer"' "$PROJECT_PATH/.claude/.subagent-state"; then
    pass "SubagentStart writes .subagent-state with agent details"
else
    fail "SubagentStart writes .subagent-state with agent details"
fi

# ── Test 17: Subagent state — SubagentStop clears state ──────────────────────

subagent_stop='{"hook_event_name":"SubagentStop","agent_id":"abc123"}'
(cd "$PROJECT_PATH" && echo "$subagent_stop" | bash .claude/scripts/subagent-hook.sh)

if [[ ! -f "$PROJECT_PATH/.claude/.subagent-state" ]]; then
    pass "SubagentStop removes .subagent-state"
else
    fail "SubagentStop removes .subagent-state" \
        "file still exists"
fi

# ── Test 18: Statusline shows active subagent ────────────────────────────────

echo ""
echo "  testing: statusline subagent display"

write_status "testing" "writing-tests"
write_token_state "testing" "1"
printf '{"active":true,"agent_id":"abc123","description":"test-writer","started":"2026-03-18T14:00:00Z"}\n' \
    > "$PROJECT_PATH/.claude/.subagent-state"

statusline_input='{"context_window":{"used_percentage":25.5,"context_window_size":200000}}'
output=$(cd "$PROJECT_PATH" && echo "$statusline_input" | bash .claude/scripts/statusline.sh 2>/dev/null)

if echo "$output" | grep -q "agent: test-writer"; then
    pass "statusline shows active subagent description"
else
    fail "statusline shows active subagent description" \
        "output: $output"
fi

# Clean up subagent state
rm -f "$PROJECT_PATH/.claude/.subagent-state"

# ── Test 19: Wrapper delegates to bash when no Python/Node ────────────────────

echo ""
echo "  testing: wrapper scripts"

write_status "implementation" "implementing"
write_token_state "implementation" "1"

statusline_input='{"context_window":{"used_percentage":40.0,"context_window_size":200000}}'
wrapper_output=$(cd "$PROJECT_PATH" && echo "$statusline_input" | bash .claude/scripts/statusline-wrapper.sh 2>/dev/null)

if echo "$wrapper_output" | grep -q "implementing"; then
    pass "statusline wrapper produces output (delegates successfully)"
else
    fail "statusline wrapper produces output" \
        "output: $wrapper_output"
fi

# ── Test 20: Python statusline output parity ──────────────────────────────────

echo ""
echo "  testing: python implementations"

if command -v python3 &>/dev/null; then
    # Copy Python scripts
    cp "$REPO_ROOT/scripts/statusline.py" "$PROJECT_PATH/.claude/scripts/"
    cp "$REPO_ROOT/scripts/token-stop-hook.py" "$PROJECT_PATH/.claude/scripts/"
    cp "$REPO_ROOT/scripts/subagent-hook.py" "$PROJECT_PATH/.claude/scripts/"

    write_status "implementation" "implementing"
    write_token_state "implementation" "1"
    rm -f "$PROJECT_PATH/.claude/.statusline-baseline"
    rm -f "$PROJECT_PATH/.claude/.subagent-state"

    statusline_input='{"context_window":{"used_percentage":42.0,"context_window_size":200000}}'

    bash_output=$(cd "$PROJECT_PATH" && echo "$statusline_input" | bash .claude/scripts/statusline.sh 2>/dev/null)
    py_output=$(cd "$PROJECT_PATH" && echo "$statusline_input" | python3 .claude/scripts/statusline.py 2>/dev/null)

    # Both should contain the stage display and context %
    if echo "$py_output" | grep -q "implementing" && echo "$py_output" | grep -q "42.0%"; then
        pass "python statusline shows stage and context %"
    else
        fail "python statusline shows stage and context %" \
            "py_output: $py_output"
    fi

    # ── Test 21: Python subagent hook writes/clears state ─────────────────────

    rm -f "$PROJECT_PATH/.claude/.subagent-state"
    subagent_start='{"hook_event_name":"SubagentStart","agent_id":"py123","description":"py-test-writer"}'
    (cd "$PROJECT_PATH" && echo "$subagent_start" | python3 .claude/scripts/subagent-hook.py)

    if [[ -f "$PROJECT_PATH/.claude/.subagent-state" ]] && \
       grep -q '"description": "py-test-writer"' "$PROJECT_PATH/.claude/.subagent-state"; then
        pass "python SubagentStart writes .subagent-state"
    else
        # Python json.dump uses spaces after colons, check for that too
        if grep -q 'py-test-writer' "$PROJECT_PATH/.claude/.subagent-state" 2>/dev/null; then
            pass "python SubagentStart writes .subagent-state"
        else
            fail "python SubagentStart writes .subagent-state"
        fi
    fi

    subagent_stop='{"hook_event_name":"SubagentStop","agent_id":"py123"}'
    (cd "$PROJECT_PATH" && echo "$subagent_stop" | python3 .claude/scripts/subagent-hook.py)

    if [[ ! -f "$PROJECT_PATH/.claude/.subagent-state" ]]; then
        pass "python SubagentStop removes .subagent-state"
    else
        fail "python SubagentStop removes .subagent-state"
    fi

    # ── Test 22: Python stop hook stage transition ────────────────────────────

    write_status "domains" "resolving"
    write_token_state "scoping" "1"
    rm -f "$PROJECT_PATH/.feature/test-feature/token-log.md"

    (cd "$PROJECT_PATH" && echo "" | python3 .claude/scripts/token-stop-hook.py)

    if [[ -f "$PROJECT_PATH/.feature/test-feature/token-log.md" ]] && \
       grep -q "| scoping |" "$PROJECT_PATH/.feature/test-feature/token-log.md"; then
        pass "python stop hook logs tokens on stage transition"
    else
        fail "python stop hook logs tokens on stage transition"
    fi

    # Verify JSON state was written
    if grep -q '"cached_stage"' "$PROJECT_PATH/.claude/.token-state" 2>/dev/null; then
        pass "python stop hook writes JSON state"
    else
        fail "python stop hook writes JSON state"
    fi

    # ── Test 23: Python statusline reads subagent state ───────────────────────

    write_status "testing" "writing-tests"
    write_token_state "testing" "1"
    rm -f "$PROJECT_PATH/.claude/.statusline-baseline"
    printf '{"active":true,"agent_id":"py123","description":"py-agent","started":"2026-03-18T14:00:00Z"}\n' \
        > "$PROJECT_PATH/.claude/.subagent-state"

    py_agent_output=$(cd "$PROJECT_PATH" && echo "$statusline_input" | python3 .claude/scripts/statusline.py 2>/dev/null)

    if echo "$py_agent_output" | grep -q "agent: py-agent"; then
        pass "python statusline shows active subagent"
    else
        fail "python statusline shows active subagent" \
            "output: $py_agent_output"
    fi

    rm -f "$PROJECT_PATH/.claude/.subagent-state"
else
    echo "  SKIP  python3 not available — skipping python tests"
fi

# ── Test 24: Node.js implementations ─────────────────────────────────────────

echo ""
echo "  testing: node.js implementations"

if command -v node &>/dev/null; then
    # Copy JS scripts
    cp "$REPO_ROOT/scripts/statusline.js" "$PROJECT_PATH/.claude/scripts/"
    cp "$REPO_ROOT/scripts/token-stop-hook.js" "$PROJECT_PATH/.claude/scripts/"
    cp "$REPO_ROOT/scripts/subagent-hook.js" "$PROJECT_PATH/.claude/scripts/"

    write_status "implementation" "implementing"
    write_token_state "implementation" "1"
    rm -f "$PROJECT_PATH/.claude/.statusline-baseline"
    rm -f "$PROJECT_PATH/.claude/.subagent-state"

    statusline_input='{"context_window":{"used_percentage":42.0,"context_window_size":200000}}'

    js_output=$(cd "$PROJECT_PATH" && echo "$statusline_input" | node .claude/scripts/statusline.js 2>/dev/null)

    if echo "$js_output" | grep -q "implementing" && echo "$js_output" | grep -q "42%"; then
        pass "node statusline shows stage and context %"
    else
        fail "node statusline shows stage and context %" \
            "js_output: $js_output"
    fi

    # ── Test 25: Node subagent hook ───────────────────────────────────────────

    rm -f "$PROJECT_PATH/.claude/.subagent-state"
    subagent_start='{"hook_event_name":"SubagentStart","agent_id":"js123","description":"js-test-writer"}'
    (cd "$PROJECT_PATH" && echo "$subagent_start" | node .claude/scripts/subagent-hook.js)

    if grep -q 'js-test-writer' "$PROJECT_PATH/.claude/.subagent-state" 2>/dev/null; then
        pass "node SubagentStart writes .subagent-state"
    else
        fail "node SubagentStart writes .subagent-state"
    fi

    subagent_stop='{"hook_event_name":"SubagentStop","agent_id":"js123"}'
    (cd "$PROJECT_PATH" && echo "$subagent_stop" | node .claude/scripts/subagent-hook.js)

    if [[ ! -f "$PROJECT_PATH/.claude/.subagent-state" ]]; then
        pass "node SubagentStop removes .subagent-state"
    else
        fail "node SubagentStop removes .subagent-state"
    fi

    # ── Test 26: Node stop hook stage transition ──────────────────────────────

    write_status "domains" "resolving"
    write_token_state "scoping" "1"
    rm -f "$PROJECT_PATH/.feature/test-feature/token-log.md"

    (cd "$PROJECT_PATH" && echo "" | node .claude/scripts/token-stop-hook.js)

    if [[ -f "$PROJECT_PATH/.feature/test-feature/token-log.md" ]] && \
       grep -q "| scoping |" "$PROJECT_PATH/.feature/test-feature/token-log.md"; then
        pass "node stop hook logs tokens on stage transition"
    else
        fail "node stop hook logs tokens on stage transition"
    fi

    if grep -q '"cached_stage"' "$PROJECT_PATH/.claude/.token-state" 2>/dev/null; then
        pass "node stop hook writes JSON state"
    else
        fail "node stop hook writes JSON state"
    fi

    # ── Test 27: Node statusline reads subagent state ─────────────────────────

    write_status "testing" "writing-tests"
    write_token_state "testing" "1"
    rm -f "$PROJECT_PATH/.claude/.statusline-baseline"
    printf '{"active":true,"agent_id":"js123","description":"js-agent","started":"2026-03-18T14:00:00Z"}\n' \
        > "$PROJECT_PATH/.claude/.subagent-state"

    js_agent_output=$(cd "$PROJECT_PATH" && echo "$statusline_input" | node .claude/scripts/statusline.js 2>/dev/null)

    if echo "$js_agent_output" | grep -q "agent: js-agent"; then
        pass "node statusline shows active subagent"
    else
        fail "node statusline shows active subagent" \
            "output: $js_agent_output"
    fi

    rm -f "$PROJECT_PATH/.claude/.subagent-state"
else
    echo "  SKIP  node not available — skipping node tests"
fi

# ── Test 28: Malformed state files don't crash hooks ──────────────────────────

echo ""
echo "  testing: robustness"

# Write garbage to .token-state
echo "not json and not shell vars {{{" > "$PROJECT_PATH/.claude/.token-state"
write_status "testing" "writing-tests"

# Bash stop hook should not crash
(cd "$PROJECT_PATH" && echo "" | bash .claude/scripts/token-stop-hook.sh 2>/dev/null)
exit_code=$?
if [[ "$exit_code" -eq 0 ]]; then
    pass "bash stop hook survives malformed .token-state"
else
    fail "bash stop hook survives malformed .token-state" \
        "exit code: $exit_code"
fi

# Bash statusline should not crash
statusline_input='{"context_window":{"used_percentage":25.5,"context_window_size":200000}}'
(cd "$PROJECT_PATH" && echo "$statusline_input" | bash .claude/scripts/statusline.sh 2>/dev/null)
exit_code=$?
if [[ "$exit_code" -eq 0 ]]; then
    pass "bash statusline survives malformed .token-state"
else
    fail "bash statusline survives malformed .token-state" \
        "exit code: $exit_code"
fi

# Python implementations
if command -v python3 &>/dev/null; then
    echo "not json and not shell vars {{{" > "$PROJECT_PATH/.claude/.token-state"
    (cd "$PROJECT_PATH" && echo "" | python3 .claude/scripts/token-stop-hook.py 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        pass "python stop hook survives malformed .token-state"
    else
        fail "python stop hook survives malformed .token-state"
    fi
fi

# Node implementations
if command -v node &>/dev/null; then
    echo "not json and not shell vars {{{" > "$PROJECT_PATH/.claude/.token-state"
    (cd "$PROJECT_PATH" && echo "" | node .claude/scripts/token-stop-hook.js 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        pass "node stop hook survives malformed .token-state"
    else
        fail "node stop hook survives malformed .token-state"
    fi
fi

rm -f "$PROJECT_PATH/.claude/.token-state"

# ── Test 29: Node.js no-op when stage unchanged ──────────────────────────────

echo ""
echo "  testing: node.js edge cases"

if command -v node &>/dev/null; then
    cp "$REPO_ROOT/scripts/token-stop-hook.js" "$PROJECT_PATH/.claude/scripts/"

    # Setup: tracking domains, status.md says domains — no transition
    write_status "domains" "resolving"
    write_token_state "domains" "1"
    rm -f "$PROJECT_PATH/.feature/test-feature/token-log.md"

    (cd "$PROJECT_PATH" && echo "" | node .claude/scripts/token-stop-hook.js)

    if [[ ! -f "$PROJECT_PATH/.feature/test-feature/token-log.md" ]]; then
        pass "node stop hook is no-op when stage unchanged"
    else
        fail "node stop hook is no-op when stage unchanged"
    fi

    # ── Test 30: Node.js terminal state logs final stage then cleans up ────────

    write_status "pr" "created"
    write_token_state "refactor" "1"
    rm -f "$PROJECT_PATH/.feature/test-feature/token-log.md"

    (cd "$PROJECT_PATH" && echo "" | node .claude/scripts/token-stop-hook.js)

    if [[ -f "$PROJECT_PATH/.feature/test-feature/token-log.md" ]] && \
       grep -q "| refactor |" "$PROJECT_PATH/.feature/test-feature/token-log.md"; then
        pass "node stop hook logs final stage before terminal cleanup"
    else
        fail "node stop hook logs final stage before terminal cleanup"
    fi

    if [[ ! -f "$PROJECT_PATH/.claude/.token-state" ]]; then
        pass "node stop hook removes state file on terminal state"
    else
        fail "node stop hook removes state file on terminal state"
    fi
else
    echo "  SKIP  node not available — skipping node edge case tests"
fi

# ── Cleanup mock transcript ──────────────────────────────────────────────────

rm -rf "$TRANSCRIPT_DIR"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "  $passed passed, $failed failed (of $total)"

if [[ "$failed" -gt 0 ]]; then
    exit 1
fi
