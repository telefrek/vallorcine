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

# Helper to create .token-state
write_token_state() {
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

# ── Test 3: Stop hook updates state file to new stage ────────────────────────

if grep -q 'cached_stage=domains' "$PROJECT_PATH/.claude/.token-state" 2>/dev/null; then
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
if [[ -f "$BASELINE_FILE" ]] && grep -q 'baseline_stage=testing' "$BASELINE_FILE"; then
    pass "statusline resets baseline to new stage"
else
    fail "statusline resets baseline to new stage" \
        "baseline not updated to testing"
fi

# ── Test 11: Cold start initializes tracking ─────────────────────────────────

echo ""
echo "  testing: cold start"

rm -f "$PROJECT_PATH/.claude/.token-state"
write_status "implementation" "implementing"

(cd "$PROJECT_PATH" && echo "" | bash .claude/scripts/token-stop-hook.sh)

if [[ -f "$PROJECT_PATH/.claude/.token-state" ]] && \
   grep -q 'cached_stage=implementation' "$PROJECT_PATH/.claude/.token-state"; then
    pass "cold start initializes tracking for active feature"
else
    fail "cold start initializes tracking for active feature"
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

# ── Cleanup mock transcript ──────────────────────────────────────────────────

rm -rf "$TRANSCRIPT_DIR"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "  $passed passed, $failed failed (of $total)"

if [[ "$failed" -gt 0 ]]; then
    exit 1
fi
