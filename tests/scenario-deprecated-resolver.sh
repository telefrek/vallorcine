#!/usr/bin/env bash
# Scenario: work_check_spec_dep emits tiered deprecation messages
#
# Validates that the resolver helper correctly:
# - Emits [deprecation:ADVISORY] when removal version is far away
# - Emits [deprecation:WARNING] when displaced_by target is not APPROVED
# - Emits [deprecation:WARNING] when removal version is within one minor bump
# - Emits [deprecation:ERROR] when current VERSION >= removal_scheduled_in
# - Returns 0 (SATISFIED) for all DEPRECATED cases — dep doesn't fail
# - Emits nothing when the spec is APPROVED + ACTIVE (no deprecation)
# - Falls back gracefully when VERSION file is missing
#
# Run from repo root: bash tests/scenario-deprecated-resolver.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-deprecated-resolver"

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
echo "── Scenario: tiered deprecation messages from resolver ──────────"
echo ""

# Helper to invoke work_check_spec_dep in a subshell that sources work-lib.sh
run_check() {
    local pdir="$1"
    local spec_id="$2"
    local required_state="${3:-APPROVED}"
    (
        cd "$pdir"
        # shellcheck disable=SC1091
        source "$REPO_ROOT/scripts/work-lib.sh"
        work_check_spec_dep "$pdir" "$spec_id" "$required_state"
    )
}

# Project skeleton: VERSION + manifest with the two specs (deprecated + successor)
setup_project() {
    local pdir="$1"
    local version="$2"
    local removal_in="$3"
    local successor_state="$4"   # APPROVED | DRAFT
    local successor_status="$5"  # ACTIVE | DEPRECATED

    rm -rf "$pdir"
    mkdir -p "$pdir/.spec/domains/example" "$pdir/.spec/registry"
    echo "$version" > "$pdir/VERSION"

    # Successor spec
    cat > "$pdir/.spec/domains/example/successor.md" <<EOF
---
{
  "id": "example.successor",
  "version": 1,
  "status": "$successor_status",
  "state": "$successor_state",
  "domains": ["example"]
}
---

# example.successor — Replacement

## Requirements
R1. Successor does the thing.

---

## Design Narrative
Body.
EOF

    # The deprecated spec
    cat > "$pdir/.spec/domains/example/legacy.md" <<EOF
---
{
  "id": "example.legacy",
  "version": 1,
  "status": "DEPRECATED",
  "state": "APPROVED",
  "domains": ["example"],
  "displaced_by": ["example.successor"],
  "displacement_reason": "superseded by example.successor",
  "removal_scheduled_in": "$removal_in",
  "deprecation_date": "2026-05-17"
}
---

# example.legacy — Old way

## Requirements
R1. Legacy does the thing.

---

## Design Narrative
Body.
EOF

    cat > "$pdir/.spec/registry/manifest.json" <<EOF
{
  "version": 1,
  "specs": {
    "example.successor": {
      "id": "example.successor",
      "path": ".spec/domains/example/successor.md",
      "state": "$successor_state",
      "status": "$successor_status"
    },
    "example.legacy": {
      "id": "example.legacy",
      "path": ".spec/domains/example/legacy.md",
      "state": "APPROVED",
      "status": "DEPRECATED"
    }
  }
}
EOF
}

# ── Test 1: ADVISORY when removal is far away (0.10.0 → 1.0.0) ────────────
P1="$TEST_BASE/p1"
setup_project "$P1" "0.10.0" "1.0.0" "APPROVED" "ACTIVE"
rc=0
out=$(run_check "$P1" "example.legacy" APPROVED 2>&1) || rc=$?
if [[ $rc -eq 0 ]] && echo "$out" | grep -q '\[deprecation:ADVISORY\]'; then
    pass "Tier 1 ADVISORY when removal far away"
else
    fail "Tier 1 ADVISORY when removal far away" "rc=$rc; out=$out"
fi

# ── Test 2: WARNING when current minor is 1 below removal (0.21.0 → 0.22.0) ────
P2="$TEST_BASE/p2"
setup_project "$P2" "0.21.0" "0.22.0" "APPROVED" "ACTIVE"
rc=0
out=$(run_check "$P2" "example.legacy" APPROVED 2>&1) || rc=$?
if [[ $rc -eq 0 ]] && echo "$out" | grep -q '\[deprecation:WARNING\]'; then
    pass "Tier 2 WARNING when removal within one minor"
else
    fail "Tier 2 WARNING when removal within one minor" "rc=$rc; out=$out"
fi

# ── Test 3: WARNING when displaced_by target is DRAFT (0.10.0 → 1.0.0) ─────
P3="$TEST_BASE/p3"
setup_project "$P3" "0.10.0" "1.0.0" "DRAFT" "DRAFT"
rc=0
out=$(run_check "$P3" "example.legacy" APPROVED 2>&1) || rc=$?
if [[ $rc -eq 0 ]] && echo "$out" | grep -q '\[deprecation:WARNING\].*not state:APPROVED'; then
    pass "Tier 2 WARNING when displaced_by target not APPROVED"
else
    fail "Tier 2 WARNING when displaced_by target not APPROVED" "rc=$rc; out=$out"
fi

# ── Test 4: ERROR when current VERSION equals removal version (0.22.0 == 0.22.0) ─
P4="$TEST_BASE/p4"
setup_project "$P4" "0.22.0" "0.22.0" "APPROVED" "ACTIVE"
rc=0
out=$(run_check "$P4" "example.legacy" APPROVED 2>&1) || rc=$?
if [[ $rc -eq 0 ]] && echo "$out" | grep -q '\[deprecation:ERROR\].*has been reached'; then
    pass "Tier 3 ERROR when current VERSION equals removal"
else
    fail "Tier 3 ERROR when current VERSION equals removal" "rc=$rc; out=$out"
fi

# ── Test 5: ERROR when current VERSION exceeds removal (0.23.0 > 0.22.0) ────
P5="$TEST_BASE/p5"
setup_project "$P5" "0.23.0" "0.22.0" "APPROVED" "ACTIVE"
rc=0
out=$(run_check "$P5" "example.legacy" APPROVED 2>&1) || rc=$?
if [[ $rc -eq 0 ]] && echo "$out" | grep -q '\[deprecation:ERROR\].*has been passed'; then
    pass "Tier 3 ERROR when current VERSION exceeds removal"
else
    fail "Tier 3 ERROR when current VERSION exceeds removal" "rc=$rc; out=$out"
fi

# ── Test 6: SILENT when checking the successor itself (not DEPRECATED) ──────
P6="$TEST_BASE/p6"
setup_project "$P6" "0.10.0" "1.0.0" "APPROVED" "ACTIVE"
rc=0
out=$(run_check "$P6" "example.successor" APPROVED 2>&1) || rc=$?
if [[ $rc -eq 0 ]] && ! echo "$out" | grep -q '\[deprecation:'; then
    pass "no message when spec is APPROVED + ACTIVE"
else
    fail "no message when spec is APPROVED + ACTIVE" "rc=$rc; out=$out"
fi

# ── Test 7: dep stays SATISFIED (rc=0) for all DEPRECATED cases ─────────────
# Already verified in tests 1-5 (rc check is part of each PASS), but explicit:
P7="$TEST_BASE/p7"
setup_project "$P7" "0.21.0" "0.22.0" "APPROVED" "ACTIVE"
rc=0
run_check "$P7" "example.legacy" APPROVED >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 0 ]]; then
    pass "DEPRECATED spec still SATISFIES dep (rc=0)"
else
    fail "DEPRECATED spec still SATISFIES dep (rc=0)" "rc=$rc"
fi

# ── Test 8: graceful fallback when VERSION file is missing ──────────────────
P8="$TEST_BASE/p8"
setup_project "$P8" "0.10.0" "1.0.0" "APPROVED" "ACTIVE"
rm "$P8/VERSION"
rc=0
out=$(run_check "$P8" "example.legacy" APPROVED 2>&1) || rc=$?
if [[ $rc -eq 0 ]] && echo "$out" | grep -q '\[deprecation:'; then
    pass "graceful fallback when VERSION file missing (still emits a tier)"
else
    fail "graceful fallback when VERSION file missing (still emits a tier)" "rc=$rc; out=$out"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "── Scenario summary ───────────────────────────────────────────"
echo "  Passed: $passed / $total"
if [[ $failed -gt 0 ]]; then
    echo "  Failed: $failed"
    exit 1
fi
echo ""
exit 0
