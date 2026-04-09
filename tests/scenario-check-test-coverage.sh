#!/usr/bin/env bash
# Scenario: check-test-coverage.py matches findings against existing tests
#
# Validates that check-test-coverage.py correctly:
# - Matches findings to adversarial tests by construct + keyword overlap
# - Does NOT match same construct with different behavior
# - Writes prove-fix stubs for covered findings
# - Never overwrites existing prove-fix files
# - Handles no matching tests
# - Handles empty finding list
# - Writes coverage-check.md report
#
# Run from repo root: bash tests/scenario-check-test-coverage.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-check-test-coverage"
SCRIPT="$REPO_ROOT/prompts/audit/check-test-coverage.py"

passed=0
failed=0
total=0

pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }
cleanup() { rm -rf "$TEST_BASE" 2>/dev/null || true; }
trap cleanup EXIT

echo ""
echo "scenario: check-test-coverage"
echo "────────────────────────────────────────────────"

if ! command -v python3 &>/dev/null; then
    echo "  SKIP  python3 not available"
    exit 0
fi

# ── Setup: create synthetic project with adversarial tests ──────────────

setup_project() {
    local proj="$TEST_BASE/project"
    mkdir -p "$proj/src/test/java/com/example"

    cat > "$proj/src/test/java/com/example/ContractBoundariesAdversarialTest.java" << 'JAVA'
package com.example;

import org.junit.jupiter.api.Test;

class ContractBoundariesAdversarialTest {

    // Finding: F-R1.cb.1.1
    // Bug: register() does not call evictIfNeeded — limits not enforced on registration
    // Correct behavior: After register(), handle count should not exceed maxHandlesPerSourcePerTable
    // Fix location: HandleTracker.register()
    // Regression watch: eviction must invalidate oldest handle
    @Test
    void test_HandleTracker_register_doesNotEnforceLimits() {
        // test body
    }

    // Finding: F-R1.cb.1.2
    // Bug: close() is not idempotent — double-close calls cleanup twice
    // Correct behavior: Second close() should be a no-op
    // Fix location: LocalEngine.close()
    // Regression watch: first close must still work
    @Test
    void test_LocalEngine_close_notIdempotent() {
        // test body
    }

    // Finding: F-R1.cb.1.3
    // Bug: insert() uses assert-only guard for empty schema fields
    // Correct behavior: Should throw IllegalArgumentException at runtime
    // Fix location: LocalTable.insert()
    // Regression watch: valid schemas must still work
    @Test
    void test_LocalTable_insert_assertOnlyEmptySchema() {
        // test body
    }
}
JAVA

    echo "$proj"
}

# ── Test 1: Matching findings against tests ─────────────────────────────

echo ""
echo "  Basic matching"
echo "  ───────────────"

proj=$(setup_project)
run_dir="$TEST_BASE/run-match"
mkdir -p "$run_dir"

cat > "$run_dir/finding-list.txt" << 'EOF'
F-R2.cb.1.1|register() does not enforce limits — handles accumulate without bound|HandleTracker (HandleTracker.java:83)|contract_boundaries|1|suspect-cb-1.md
F-R2.rl.1.1|close() has no idempotency guard — double-close retries cleanup|LocalEngine (LocalEngine.java:182)|resource_lifecycle|1|suspect-rl-1.md
F-R2.ss.1.1|scan() returns stale results after concurrent insert|TableIterator (TableIterator.java:50)|shared_state|1|suspect-ss-1.md
EOF

output=$(python3 "$SCRIPT" "$run_dir" "$proj" 2>&1)

if echo "$output" | grep -q "2 covered"; then
    pass "matches 2 findings with existing tests"
else
    fail "match count" "got: $output"
fi

if echo "$output" | grep -q "1 uncovered"; then
    pass "1 finding uncovered (no matching test)"
else
    fail "uncovered count" "got: $output"
fi

# Check stubs written
if [[ -f "$run_dir/prove-fix-F-R2-cb-1-1.md" ]]; then
    pass "writes stub for covered finding"
else
    fail "no stub for covered finding"
fi

if grep -q "COVERED_BY_EXISTING_TEST" "$run_dir/prove-fix-F-R2-cb-1-1.md"; then
    pass "stub has correct result type"
else
    fail "wrong result type in stub"
fi

if grep -q "test_HandleTracker_register_doesNotEnforceLimits" "$run_dir/prove-fix-F-R2-cb-1-1.md"; then
    pass "stub references matching test method"
else
    fail "test method not in stub"
fi

# No stub for uncovered finding
if [[ ! -f "$run_dir/prove-fix-F-R2-ss-1-1.md" ]]; then
    pass "no stub for uncovered finding"
else
    fail "stub created for uncovered finding"
fi

# Coverage report
if [[ -f "$run_dir/coverage-check.md" ]]; then
    pass "writes coverage-check.md"
else
    fail "no coverage-check.md"
fi

# ── Test 2: Different behavior NOT matched ──────────────────────────────

echo ""
echo "  Different behavior not matched"
echo "  ───────────────────────────────"

run_dir="$TEST_BASE/run-different"
mkdir -p "$run_dir"

# Finding about register() but different behavior than existing test
cat > "$run_dir/finding-list.txt" << 'EOF'
F-R2.cb.1.1|register() does not check closed flag — use after close|HandleTracker (HandleTracker.java:83)|contract_boundaries|1|suspect-cb-1.md
EOF

output=$(python3 "$SCRIPT" "$run_dir" "$proj" 2>&1)

if echo "$output" | grep -q "0 covered"; then
    pass "different behavior not matched despite same construct"
else
    fail "false match on different behavior" "got: $output"
fi

# ── Test 3: Never overwrite existing prove-fix ──────────────────────────

echo ""
echo "  No overwrite of existing results"
echo "  ──────────────────────────────────"

run_dir="$TEST_BASE/run-nooverwrite"
mkdir -p "$run_dir"

# Pre-existing prove-fix file
cat > "$run_dir/prove-fix-F-R2-cb-1-1.md" << 'EOF'
# Prove-Fix — F-R2.cb.1.1

## Result: CONFIRMED_AND_FIXED

Real result that must not be overwritten.
EOF

cat > "$run_dir/finding-list.txt" << 'EOF'
F-R2.cb.1.1|register() does not enforce limits — handles accumulate|HandleTracker (HandleTracker.java:83)|contract_boundaries|1|suspect-cb-1.md
EOF

python3 "$SCRIPT" "$run_dir" "$proj" >/dev/null 2>&1

if grep -q "CONFIRMED_AND_FIXED" "$run_dir/prove-fix-F-R2-cb-1-1.md"; then
    pass "existing prove-fix file not overwritten"
else
    fail "existing file was overwritten"
fi

# ── Test 4: No tests in project ─────────────────────────────────────────

echo ""
echo "  No tests available"
echo "  ───────────────────"

empty_proj="$TEST_BASE/empty-project"
mkdir -p "$empty_proj"
run_dir="$TEST_BASE/run-notests"
mkdir -p "$run_dir"

cat > "$run_dir/finding-list.txt" << 'EOF'
F-R1.cb.1.1|some bug description|SomeClass (Some.java:1)|contract_boundaries|1|suspect-cb-1.md
EOF

output=$(python3 "$SCRIPT" "$run_dir" "$empty_proj" 2>&1)

if echo "$output" | grep -q "0 covered"; then
    pass "handles project with no tests"
else
    fail "no-test handling" "got: $output"
fi

# ── Test 5: Empty finding list ──────────────────────────────────────────

echo ""
echo "  Empty finding list"
echo "  ───────────────────"

run_dir="$TEST_BASE/run-empty"
mkdir -p "$run_dir"
touch "$run_dir/finding-list.txt"

output=$(python3 "$SCRIPT" "$run_dir" "$proj" 2>&1)

if echo "$output" | grep -q "0 findings"; then
    pass "handles empty finding list"
else
    fail "empty list handling" "got: $output"
fi

# ── Test 6: Error handling ──────────────────────────────────────────────

echo ""
echo "  Error handling"
echo "  ───────────────"

output=$(python3 "$SCRIPT" "/tmp/vallorcine/nonexistent" "$proj" 2>&1 || true)
if echo "$output" | grep -q "not a directory"; then
    pass "rejects nonexistent run dir"
else
    fail "no error for nonexistent dir"
fi

output=$(python3 "$SCRIPT" 2>&1 || true)
if echo "$output" | grep -q "Usage"; then
    pass "shows usage with no args"
else
    fail "no usage message"
fi

# ── Summary ─────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "  $passed passed, $failed failed (of $total)"
echo ""
if ((failed > 0)); then exit 1; fi
