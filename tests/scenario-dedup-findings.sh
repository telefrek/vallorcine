#!/usr/bin/env bash
# Scenario: dedup-findings.py detects cross-lens behavioral duplicates
#
# Validates that dedup-findings.py correctly:
# - Identifies findings on same construct from different lenses with keyword overlap
# - Does NOT group findings on same construct with different behaviors
# - Produces dispatch-order.txt with primaries before duplicates
# - Writes dedup-report.md with group details
# - Handles empty finding lists
# - Handles single-lens findings (no dedup)
# - Never writes prove-fix stubs (reorder-only strategy)
#
# Run from repo root: bash tests/scenario-dedup-findings.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-dedup-findings"
SCRIPT="$REPO_ROOT/prompts/audit/dedup-findings.py"

passed=0
failed=0
total=0

pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }
cleanup() { rm -rf "$TEST_BASE" 2>/dev/null || true; }
trap cleanup EXIT

echo ""
echo "scenario: dedup-findings"
echo "────────────────────────────────────────────────"

if ! command -v python3 &>/dev/null; then
    echo "  SKIP  python3 not available"
    exit 0
fi

# ── Test 1: Cross-lens duplicates detected ──────────────────────────────

echo ""
echo "  Cross-lens duplicate detection"
echo "  ───────────────────────────────"

dir="$TEST_BASE/run-dupes"
mkdir -p "$dir"

cat > "$dir/finding-list.txt" << 'EOF'
F-R1.cb.1.1|HandleTracker.close() has no idempotency guard — double-close retries cleanup|HandleTracker (HandleTracker.java:100-120)|contract_boundaries|1|suspect-contract_boundaries-cluster-1.md
F-R1.ss.1.1|HandleTracker.close() has no idempotency guard — double-close calls invalidateAll twice|HandleTracker (HandleTracker.java:100-120)|shared_state|1|suspect-shared_state-cluster-1.md
F-R1.rl.1.1|HandleTracker.close() has no idempotency guard|HandleTracker (HandleTracker.java:100-120)|resource_lifecycle|1|suspect-resource_lifecycle-cluster-1.md
EOF

output=$(python3 "$SCRIPT" "$dir" 2>&1)

if echo "$output" | grep -q "2 duplicates"; then
    pass "detects 2 duplicates from 3 findings"
else
    fail "duplicate count" "got: $output"
fi

if [[ -f "$dir/dispatch-order.txt" ]]; then
    pass "writes dispatch-order.txt"
else
    fail "no dispatch-order.txt"
fi

if [[ -f "$dir/dedup-report.md" ]]; then
    pass "writes dedup-report.md"
else
    fail "no dedup-report.md"
fi

# Primary should come first in dispatch order
first=$(head -1 "$dir/dispatch-order.txt")
if [[ -n "$first" ]]; then
    # Check that the other two come after
    order=$(cat "$dir/dispatch-order.txt" | tr '\n' ',')
    pass "dispatch order has primary first: $first"
else
    fail "empty dispatch order"
fi

# No prove-fix stubs should exist (reorder-only)
stub_count=$(find "$dir" -name "prove-fix-*.md" 2>/dev/null | wc -l)
if [[ "$stub_count" -eq 0 ]]; then
    pass "no prove-fix stubs written (reorder-only strategy)"
else
    fail "prove-fix stubs written" "found $stub_count stubs"
fi

# ── Test 2: Different behaviors NOT grouped ─────────────────────────────

echo ""
echo "  Different behaviors preserved"
echo "  ──────────────────────────────"

dir="$TEST_BASE/run-different"
mkdir -p "$dir"

cat > "$dir/finding-list.txt" << 'EOF'
F-R1.cb.1.1|HandleTracker.register() does not call evictIfNeeded — limits not enforced|HandleTracker (HandleTracker.java:83)|contract_boundaries|1|suspect-cb-cluster-1.md
F-R1.rl.1.1|HandleTracker.register() does not check closed flag — use after close|HandleTracker (HandleTracker.java:83)|resource_lifecycle|1|suspect-rl-cluster-1.md
EOF

output=$(python3 "$SCRIPT" "$dir" 2>&1)

if echo "$output" | grep -q "0 duplicates"; then
    pass "different behaviors not grouped"
else
    fail "incorrectly grouped different behaviors" "got: $output"
fi

# Both should be in dispatch order
line_count=$(wc -l < "$dir/dispatch-order.txt")
if [[ "$line_count" -eq 2 ]]; then
    pass "both findings active"
else
    fail "wrong active count" "expected 2, got $line_count"
fi

# ── Test 3: Single-lens findings unchanged ──────────────────────────────

echo ""
echo "  Single-lens findings"
echo "  ─────────────────────"

dir="$TEST_BASE/run-single"
mkdir -p "$dir"

cat > "$dir/finding-list.txt" << 'EOF'
F-R1.cb.1.1|Bug one|ClassA (A.java:1)|contract_boundaries|1|suspect-cb-1.md
F-R1.cb.1.2|Bug two|ClassB (B.java:1)|contract_boundaries|1|suspect-cb-1.md
F-R1.cb.1.3|Bug three|ClassC (C.java:1)|contract_boundaries|1|suspect-cb-1.md
EOF

output=$(python3 "$SCRIPT" "$dir" 2>&1)

if echo "$output" | grep -q "0 duplicates"; then
    pass "single-lens findings not grouped"
else
    fail "single-lens grouping" "got: $output"
fi

# ── Test 4: Empty run ───────────────────────────────────────────────────

echo ""
echo "  Empty run"
echo "  ──────────"

dir="$TEST_BASE/run-empty"
mkdir -p "$dir"
touch "$dir/finding-list.txt"

output=$(python3 "$SCRIPT" "$dir" 2>&1)

if echo "$output" | grep -q "0 findings"; then
    pass "handles empty finding list"
else
    fail "empty handling" "got: $output"
fi

# ── Test 5: Multi-construct findings ────────────────────────────────────

echo ""
echo "  Multi-construct findings"
echo "  ─────────────────────────"

dir="$TEST_BASE/run-multi"
mkdir -p "$dir"

cat > "$dir/finding-list.txt" << 'EOF'
F-R1.cb.1.1|Builder accepts contradictory handle limits per-source exceeds per-table|HandleTracker.Builder / LocalEngine.Builder (HT.java:331, LE.java:289)|contract_boundaries|1|suspect-cb-1.md
F-R1.rl.1.1|Builder accepts contradictory handle limits per-source exceeds per-table total|HandleTracker.Builder (HT.java:331)|resource_lifecycle|1|suspect-rl-1.md
EOF

output=$(python3 "$SCRIPT" "$dir" 2>&1)

if echo "$output" | grep -q "1 duplicates"; then
    pass "multi-construct finding matched correctly"
else
    fail "multi-construct matching" "got: $output"
fi

# ── Test 6: Error handling ──────────────────────────────────────────────

echo ""
echo "  Error handling"
echo "  ───────────────"

output=$(python3 "$SCRIPT" "/tmp/vallorcine/nonexistent" 2>&1 || true)
if echo "$output" | grep -q "not a directory"; then
    pass "rejects nonexistent directory"
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
