#!/usr/bin/env bash
# Scenario: aggregate-results.py pre-aggregates prove-fix and suspect outputs
#
# Validates that aggregate-results.py correctly:
# - Aggregates prove-fix files into prove-fix-summary.md
# - Aggregates boundary observations into boundary-summary.md
# - Tallies results by type (CONFIRMED_AND_FIXED, IMPOSSIBLE, etc.)
# - Counts Phase 0 short-circuits
# - Groups findings by result type
# - Handles empty runs (no prove-fix files)
# - Handles malformed prove-fix files
# - Handles missing boundary section in suspect files
# - Uses atomic writes (tmp + rename)
# - Handles mixed results
#
# Run from repo root: bash tests/scenario-aggregate-results.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-aggregate-results"
SCRIPT="$REPO_ROOT/prompts/audit/aggregate-results.py"

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
echo "scenario: aggregate-results"
echo "────────────────────────────────────────────────"

# Check python3 available
if ! command -v python3 &>/dev/null; then
    echo "  SKIP  python3 not available"
    exit 0
fi

# ── Setup: create test run directory with prove-fix and suspect files ────────

setup_basic_run() {
    local run_dir="$TEST_BASE/run-basic"
    rm -rf "$run_dir"
    mkdir -p "$run_dir"

    # Confirmed finding (Phase 0 = STILL_VULNERABLE)
    cat > "$run_dir/prove-fix-F-R1-cb-1-1.md" << 'EOF'
# Prove-Fix — F-R1.cb.1.1

## Result: CONFIRMED_AND_FIXED

### Phase 0: Already-fixed check
- **Result:** STILL_VULNERABLE
- **Detail:** No limit enforcement on registration.

### Phase 1: Verify
- **Test method:** test_register_doesNotEnforceLimits
- **Test class:** src/test/ContractBoundariesTest.java
- **Result:** CONFIRMED
- **Detail:** Test confirms the bug.

### Phase 2: Fix
- **Change:** Add evictIfNeeded() call after registration
- **File:** src/main/HandleTracker.java:115
- **Result:** FIXED
- **Detail:** Limits now enforced on every registration.
EOF

    # Impossible finding (Phase 0 = ALREADY_FIXED)
    cat > "$run_dir/prove-fix-F-R1-cb-1-2.md" << 'EOF'
# Prove-Fix — F-R1.cb.1.2

## Result: IMPOSSIBLE

### Phase 0: Already-fixed check
- **Result:** ALREADY_FIXED
- **Detail:** Fixed by prior finding F-R1.cb.1.1.

### Phase 1: Verify (skipped if Phase 0 = ALREADY_FIXED)
- **Test method:** skipped
- **Test class:** src/test/ContractBoundariesTest.java
- **Result:** SKIPPED
- **Detail:** Skipped — vulnerability already fixed

### Phase 2: Fix (if Phase 1 confirmed)
- **Change:** N/A
- **File:** N/A
- **Result:** N/A
- **Detail:** N/A
EOF

    # Second confirmed finding
    cat > "$run_dir/prove-fix-F-R1-resource_lifecycle-1-1.md" << 'EOF'
# Prove-Fix — F-R1.resource_lifecycle.1.1

## Result: CONFIRMED_AND_FIXED

### Phase 0: Already-fixed check
- **Result:** STILL_VULNERABLE
- **Detail:** No close guard present.

### Phase 1: Verify
- **Test method:** test_useAfterClose
- **Test class:** src/test/ResourceLifecycleTest.java
- **Result:** CONFIRMED
- **Detail:** Operations succeed after close.

### Phase 2: Fix
- **Change:** Add isClosed flag with AtomicBoolean
- **File:** src/main/LocalTable.java:42
- **Result:** FIXED
- **Detail:** All public methods now check closed flag.
EOF

    # Impossible finding (not cascade — genuinely not a bug)
    cat > "$run_dir/prove-fix-F-R1-shared_state-1-1.md" << 'EOF'
# Prove-Fix — F-R1.shared_state.1.1

## Result: IMPOSSIBLE

### Phase 0: Already-fixed check
- **Result:** STILL_VULNERABLE
- **Detail:** Potential race condition identified.

### Phase 1: Verify
- **Test method:** test_concurrentAccess
- **Test class:** src/test/SharedStateTest.java
- **Result:** IMPOSSIBLE
- **Detail:** The synchronized block prevents this race.

### Phase 2: Fix (if Phase 1 confirmed)
- **Change:** N/A
- **File:** N/A
- **Result:** N/A
- **Detail:** N/A
EOF

    # Suspect file with boundary observations
    cat > "$run_dir/suspect-contract_boundaries-cluster-1.md" << 'EOF'
# Suspect Results — contract_boundaries / Cluster 1

## Findings

### F-R1.cb.1.1: register() does not enforce limits
- **Construct:** HandleTracker
- **Severity:** high

### F-R1.cb.1.2: checkValid passes hardcoded 0
- **Construct:** LocalTable
- **Severity:** medium

## Boundary Observations

### HandleTracker -> TableCatalog (external)
- **Data flowing:** tableName strings
- **This cluster guarantees:** tableName is non-null
- **Assumption about receiver:** TableCatalog uses same keys

### LocalEngine -> JlsmTable (external)
- **Data flowing:** key strings, documents
- **This cluster guarantees:** all params non-null
- **Assumption about receiver:** standard CRUD semantics

## Summary
- Constructs analyzed: 4
- Findings: 2
- Cleared: 3
- Boundary observations: 2
EOF

    # Suspect file without boundary observations
    cat > "$run_dir/suspect-shared_state-cluster-1.md" << 'EOF'
# Suspect Results — shared_state / Cluster 1

## Findings

### F-R1.shared_state.1.1: potential race in concurrent access
- **Construct:** HandleTracker
- **Severity:** low

## Summary
- Constructs analyzed: 2
- Findings: 1
- Cleared: 1
- Boundary observations: 0
EOF

    echo "$run_dir"
}

# ── Test 1: Basic aggregation produces correct tally ─────────────────────────

echo ""
echo "  Basic aggregation"
echo "  ─────────────────"

run_dir=$(setup_basic_run)
output=$(python3 "$SCRIPT" "$run_dir" 2>&1)

# Check output
if echo "$output" | grep -q "Aggregated 4 findings"; then
    pass "reports 4 findings"
else
    fail "finding count" "got: $output"
fi

if echo "$output" | grep -q "CONFIRMED_AND_FIXED: 2"; then
    pass "counts 2 confirmed+fixed"
else
    fail "confirmed count" "got: $output"
fi

if echo "$output" | grep -q "IMPOSSIBLE: 2"; then
    pass "counts 2 impossible"
else
    fail "impossible count" "got: $output"
fi

if echo "$output" | grep -q "Phase 0 short-circuits: 1"; then
    pass "counts 1 Phase 0 short-circuit"
else
    fail "phase 0 count" "got: $output"
fi

# Check prove-fix-summary.md exists and has content
if [[ -f "$run_dir/prove-fix-summary.md" ]]; then
    pass "prove-fix-summary.md created"
else
    fail "prove-fix-summary.md not created"
fi

# Check tally table in summary
if grep -q "CONFIRMED_AND_FIXED | 2" "$run_dir/prove-fix-summary.md"; then
    pass "summary contains correct confirmed tally"
else
    fail "summary tally wrong"
fi

# Check grouping
if grep -q "## Confirmed and Fixed (2)" "$run_dir/prove-fix-summary.md"; then
    pass "findings grouped by result"
else
    fail "finding grouping"
fi

# Check individual finding details preserved
if grep -q "test_register_doesNotEnforceLimits" "$run_dir/prove-fix-summary.md"; then
    pass "test method preserved in summary"
else
    fail "test method missing"
fi

if grep -q "Add evictIfNeeded" "$run_dir/prove-fix-summary.md"; then
    pass "fix description preserved in summary"
else
    fail "fix description missing"
fi

# Check cascade impossible has reason
if grep -q "Already fixed by prior finding" "$run_dir/prove-fix-summary.md"; then
    pass "cascade impossible shows reason"
else
    fail "cascade reason missing"
fi

# ── Test 2: Boundary aggregation ────────────────────────────────────────────

echo ""
echo "  Boundary aggregation"
echo "  ─────────────────────"

if [[ -f "$run_dir/boundary-summary.md" ]]; then
    pass "boundary-summary.md created"
else
    fail "boundary-summary.md not created"
fi

if grep -q "Total boundary observations: 2" "$run_dir/boundary-summary.md"; then
    pass "correct boundary count"
else
    fail "boundary count" "$(head -3 "$run_dir/boundary-summary.md")"
fi

if grep -q "HandleTracker -> TableCatalog" "$run_dir/boundary-summary.md"; then
    pass "boundary edge preserved"
else
    fail "boundary edge missing"
fi

if grep -q "tableName is non-null" "$run_dir/boundary-summary.md"; then
    pass "boundary guarantee preserved"
else
    fail "boundary guarantee missing"
fi

# Cluster without boundaries should not add entries
# Count boundary entries before the Cluster Summaries section
boundary_count=$(sed '/^## Cluster Summaries/,$d' "$run_dir/boundary-summary.md" | grep -c "^### " || true)
if [[ "$boundary_count" -eq 2 ]]; then
    pass "no phantom boundaries from cluster without observations"
else
    fail "phantom boundaries" "expected 2 boundary entries, got $boundary_count"
fi

# Cluster summaries
if grep -q "Constructs analyzed: 4" "$run_dir/boundary-summary.md"; then
    pass "cluster summary preserved"
else
    fail "cluster summary missing"
fi

# ── Test 3: Empty run (no prove-fix files) ──────────────────────────────────

echo ""
echo "  Empty run"
echo "  ──────────"

empty_dir="$TEST_BASE/run-empty"
rm -rf "$empty_dir"
mkdir -p "$empty_dir"

output=$(python3 "$SCRIPT" "$empty_dir" 2>&1)

if echo "$output" | grep -q "Aggregated 0 findings"; then
    pass "handles empty run"
else
    fail "empty run" "got: $output"
fi

if [[ -f "$empty_dir/prove-fix-summary.md" ]]; then
    pass "creates summary even for empty run"
else
    fail "no summary for empty run"
fi

if grep -qF '**Total** | **0**' "$empty_dir/prove-fix-summary.md"; then
    pass "empty tally shows 0"
else
    fail "empty tally"
fi

# ── Test 4: Malformed prove-fix file ────────────────────────────────────────

echo ""
echo "  Malformed input"
echo "  ────────────────"

mal_dir="$TEST_BASE/run-malformed"
rm -rf "$mal_dir"
mkdir -p "$mal_dir"

# File with no Result header
echo "# Prove-Fix — F-R1.cb.1.1" > "$mal_dir/prove-fix-F-R1-cb-1-1.md"
echo "Some garbage content" >> "$mal_dir/prove-fix-F-R1-cb-1-1.md"

# Valid file alongside malformed one
cat > "$mal_dir/prove-fix-F-R1-cb-1-2.md" << 'EOF'
# Prove-Fix — F-R1.cb.1.2

## Result: CONFIRMED_AND_FIXED

### Phase 0: Already-fixed check
- **Result:** STILL_VULNERABLE
- **Detail:** Bug exists.

### Phase 1: Verify
- **Test method:** test_something
- **Test class:** SomeTest.java
- **Result:** CONFIRMED
- **Detail:** Confirmed.

### Phase 2: Fix
- **Change:** Fixed it
- **File:** SomeFile.java:10
- **Result:** FIXED
- **Detail:** Fixed.
EOF

output=$(python3 "$SCRIPT" "$mal_dir" 2>&1)
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    pass "does not crash on malformed input"
else
    fail "crashes on malformed input" "exit code: $exit_code"
fi

# Should still aggregate the valid file
if echo "$output" | grep -q "Aggregated 2 findings"; then
    pass "includes malformed file in count"
else
    fail "malformed file handling" "got: $output"
fi

# ── Test 5: Atomic writes ──────────────────────────────────────────────────

echo ""
echo "  Atomic writes"
echo "  ──────────────"

# No .tmp files should remain after successful run
if ls "$run_dir"/*.tmp 2>/dev/null | grep -q '.'; then
    fail "tmp files left behind"
else
    pass "no tmp files left behind"
fi

# ── Test 6: Invalid directory ───────────────────────────────────────────────

echo ""
echo "  Error handling"
echo "  ───────────────"

output=$(python3 "$SCRIPT" "/tmp/vallorcine/nonexistent-dir" 2>&1 || true)
if echo "$output" | grep -q "not a directory"; then
    pass "rejects nonexistent directory"
else
    fail "no error for nonexistent dir" "got: $output"
fi

output=$(python3 "$SCRIPT" 2>&1 || true)
if echo "$output" | grep -q "Usage"; then
    pass "shows usage with no args"
else
    fail "no usage message" "got: $output"
fi

# ── Test 7: Natural sort order ──────────────────────────────────────────────

echo ""
echo "  Sort order"
echo "  ───────────"

sort_dir="$TEST_BASE/run-sort"
rm -rf "$sort_dir"
mkdir -p "$sort_dir"

# Create files that would sort wrong with lexicographic order
for i in 1 2 10 11 3; do
    cat > "$sort_dir/prove-fix-F-R1-cb-1-$i.md" << EOF
# Prove-Fix — F-R1.cb.1.$i

## Result: CONFIRMED_AND_FIXED

### Phase 0: Already-fixed check
- **Result:** STILL_VULNERABLE
- **Detail:** Bug $i.

### Phase 1: Verify
- **Test method:** test_$i
- **Test class:** Test.java
- **Result:** CONFIRMED
- **Detail:** Confirmed.

### Phase 2: Fix
- **Change:** Fix $i
- **File:** File.java:$i
- **Result:** FIXED
- **Detail:** Fixed.
EOF
done

python3 "$SCRIPT" "$sort_dir" >/dev/null 2>&1

# Check that findings appear in natural order (1, 2, 3, 10, 11)
order=$(grep "^### F-R1" "$sort_dir/prove-fix-summary.md" | sed 's/.*cb\.1\.\([0-9]*\).*/\1/')
expected="1
2
3
10
11"

if [[ "$order" == "$expected" ]]; then
    pass "natural sort order (1, 2, 3, 10, 11)"
else
    fail "sort order wrong" "got: $order"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "  $passed passed, $failed failed (of $total)"
echo ""

if ((failed > 0)); then
    exit 1
fi
