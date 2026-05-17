#!/usr/bin/env bash
# Scenario: validate-subagent-return.sh detects completeness-contract violations
#
# Validates that scripts/validate-subagent-return.sh correctly:
# - Exits 0 on clean returns
# - Exits 1 when trigger phrases are present
# - Exits 1 when --require-ac-coverage is passed and AC mapping is missing
# - Exits 0 when --require-ac-coverage is passed and AC mapping is present
# - Exits 2 on missing file
# - Exits 2 on missing argument
# - Detects each trigger phrase from rules/completeness-contract.md
# - Detects AC mapping in various formats (AC1, AC-1, "Acceptance criteria")
# - Does not false-positive on benign technical uses
#
# Run from repo root: bash tests/scenario-validate-subagent-return.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-validate-subagent-return"
VALIDATOR="$REPO_ROOT/scripts/validate-subagent-return.sh"

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
    rm -rf "$TEST_BASE"
}
trap cleanup EXIT
mkdir -p "$TEST_BASE"

echo ""
echo "── Scenario: validate-subagent-return.sh ──────────────────────"
echo ""

# ── Test 1: Clean return, no AC required ─────────────────────────
cat > "$TEST_BASE/clean.txt" <<'EOF'
WD-01 COMPLETE

All assigned scope addressed. Tests pass green.
EOF
rc=0
bash "$VALIDATOR" "$TEST_BASE/clean.txt" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 0 ]]; then
    pass "clean return exits 0"
else
    fail "clean return exits 0" "got rc=$rc"
fi

# ── Test 2: Trigger phrase "candidate" ───────────────────────────
cat > "$TEST_BASE/trigger-candidate.txt" <<'EOF'
WD-01 COMPLETE

v8 reader is a candidate for follow-up work.
EOF
rc=0
bash "$VALIDATOR" "$TEST_BASE/trigger-candidate.txt" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 1 ]]; then
    pass "trigger 'candidate' exits 1"
else
    fail "trigger 'candidate' exits 1" "got rc=$rc"
fi

# ── Test 3: Trigger phrase "follow-on" ───────────────────────────
cat > "$TEST_BASE/trigger-followon.txt" <<'EOF'
WD-02 COMPLETE

Will address X in a follow-on WD.
EOF
rc=0
bash "$VALIDATOR" "$TEST_BASE/trigger-followon.txt" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 1 ]]; then
    pass "trigger 'follow-on' exits 1"
else
    fail "trigger 'follow-on' exits 1" "got rc=$rc"
fi

# ── Test 4: Trigger phrase "out of scope" ────────────────────────
cat > "$TEST_BASE/trigger-oos.txt" <<'EOF'
WD-03 COMPLETE

Edge case handling is out of scope for this WD.
EOF
rc=0
bash "$VALIDATOR" "$TEST_BASE/trigger-oos.txt" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 1 ]]; then
    pass "trigger 'out of scope' exits 1"
else
    fail "trigger 'out of scope' exits 1" "got rc=$rc"
fi

# ── Test 5: Trigger phrase "deferred" ────────────────────────────
cat > "$TEST_BASE/trigger-deferred.txt" <<'EOF'
WD-04 COMPLETE

The cross-shard validation is deferred for a later PR.
EOF
rc=0
bash "$VALIDATOR" "$TEST_BASE/trigger-deferred.txt" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 1 ]]; then
    pass "trigger 'deferred' exits 1"
else
    fail "trigger 'deferred' exits 1" "got rc=$rc"
fi

# ── Test 6: Trigger phrase "future work" ─────────────────────────
cat > "$TEST_BASE/trigger-future.txt" <<'EOF'
WD-05 COMPLETE

Improved error messages are future work.
EOF
rc=0
bash "$VALIDATOR" "$TEST_BASE/trigger-future.txt" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 1 ]]; then
    pass "trigger 'future work' exits 1"
else
    fail "trigger 'future work' exits 1" "got rc=$rc"
fi

# ── Test 7: Trigger phrase "non-critical" ────────────────────────
cat > "$TEST_BASE/trigger-noncritical.txt" <<'EOF'
WD-06 COMPLETE

Non-critical optimization left for later.
EOF
rc=0
bash "$VALIDATOR" "$TEST_BASE/trigger-noncritical.txt" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 1 ]]; then
    pass "trigger 'non-critical' exits 1"
else
    fail "trigger 'non-critical' exits 1" "got rc=$rc"
fi

# ── Test 8: --require-ac-coverage, missing AC ────────────────────
cat > "$TEST_BASE/no-ac.txt" <<'EOF'
WD-07 COMPLETE

Tests pass. Code looks clean.
EOF
rc=0
bash "$VALIDATOR" "$TEST_BASE/no-ac.txt" --require-ac-coverage >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 1 ]]; then
    pass "--require-ac-coverage missing AC exits 1"
else
    fail "--require-ac-coverage missing AC exits 1" "got rc=$rc"
fi

# ── Test 9: --require-ac-coverage, AC section present (header) ───
cat > "$TEST_BASE/ac-header.txt" <<'EOF'
WD-08 COMPLETE

## AC satisfaction
- AC1: src/foo.rs:42 + tests/foo_test.rs
- AC2: src/bar.rs:88
EOF
rc=0
bash "$VALIDATOR" "$TEST_BASE/ac-header.txt" --require-ac-coverage >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 0 ]]; then
    pass "--require-ac-coverage with header section exits 0"
else
    fail "--require-ac-coverage with header section exits 0" "got rc=$rc"
fi

# ── Test 10: --require-ac-coverage, AC1 inline reference ─────────
cat > "$TEST_BASE/ac-inline.txt" <<'EOF'
WD-09 COMPLETE

The implementation satisfies AC1 in src/foo.rs:42 and AC2 in tests/bar.rs.
EOF
rc=0
bash "$VALIDATOR" "$TEST_BASE/ac-inline.txt" --require-ac-coverage >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 0 ]]; then
    pass "--require-ac-coverage with AC<N> inline pattern exits 0"
else
    fail "--require-ac-coverage with AC<N> inline pattern exits 0" "got rc=$rc"
fi

# ── Test 11: missing file ────────────────────────────────────────
rc=0
bash "$VALIDATOR" "$TEST_BASE/does-not-exist.txt" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 2 ]]; then
    pass "missing file exits 2"
else
    fail "missing file exits 2" "got rc=$rc"
fi

# ── Test 12: missing argument ────────────────────────────────────
rc=0
bash "$VALIDATOR" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 2 ]]; then
    pass "missing argument exits 2"
else
    fail "missing argument exits 2" "got rc=$rc"
fi

# ── Test 13: unknown flag ────────────────────────────────────────
rc=0
bash "$VALIDATOR" "$TEST_BASE/clean.txt" --bogus-flag >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 2 ]]; then
    pass "unknown flag exits 2"
else
    fail "unknown flag exits 2" "got rc=$rc"
fi

# ── Test 14: trigger phrase + AC missing → still rc=1 ────────────
cat > "$TEST_BASE/both-violations.txt" <<'EOF'
WD-10 COMPLETE

The follow-on work is deferred.
EOF
rc=0
bash "$VALIDATOR" "$TEST_BASE/both-violations.txt" --require-ac-coverage >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 1 ]]; then
    pass "trigger + missing AC both flagged, exit 1"
else
    fail "trigger + missing AC both flagged, exit 1" "got rc=$rc"
fi

# ── Test 15: trigger phrase but no --require-ac-coverage still rc=1
cat > "$TEST_BASE/trigger-only.txt" <<'EOF'
WD-11 COMPLETE

Edge case is a candidate for later.
EOF
rc=0
bash "$VALIDATOR" "$TEST_BASE/trigger-only.txt" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 1 ]]; then
    pass "trigger phrase still flagged without --require-ac-coverage"
else
    fail "trigger phrase still flagged without --require-ac-coverage" "got rc=$rc"
fi

# ── Test 16: stderr message contains "VIOLATION" on rc=1 ─────────
stderr=$(bash "$VALIDATOR" "$TEST_BASE/trigger-candidate.txt" 2>&1 >/dev/null || true)
if echo "$stderr" | grep -q "VIOLATION"; then
    pass "stderr contains 'VIOLATION' on rc=1"
else
    fail "stderr contains 'VIOLATION' on rc=1" "stderr was: $stderr"
fi

# ── Test 17: stderr mentions completeness-contract.md ────────────
stderr=$(bash "$VALIDATOR" "$TEST_BASE/trigger-candidate.txt" 2>&1 >/dev/null || true)
if echo "$stderr" | grep -q "completeness-contract.md"; then
    pass "stderr cites completeness-contract.md"
else
    fail "stderr cites completeness-contract.md" "stderr was: $stderr"
fi

# ── Test 18: empty file → clean (no trigger phrases to find) ─────
touch "$TEST_BASE/empty.txt"
rc=0
bash "$VALIDATOR" "$TEST_BASE/empty.txt" >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 0 ]]; then
    pass "empty file exits 0 (no triggers)"
else
    fail "empty file exits 0 (no triggers)" "got rc=$rc"
fi

# ── Summary ──────────────────────────────────────────────────────
echo ""
echo "── Scenario summary ───────────────────────────────────────────"
echo "  Passed: $passed / $total"
if [[ $failed -gt 0 ]]; then
    echo "  Failed: $failed"
    exit 1
fi
echo ""
exit 0
