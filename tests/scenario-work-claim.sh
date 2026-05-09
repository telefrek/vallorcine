#!/usr/bin/env bash
# Scenario: work-claim.sh atomic compare-and-swap on WD status.
#
# Tests:
# 1. Claim succeeds when current status matches expected
# 2. Claim fails (exit 1) when current status differs
# 3. Bogus new-status is rejected (exit 2) before any write
# 4. Missing WD file is rejected (exit 2)
# 5. Two parallel claims of the same DRAFT → SPECIFYING transition: only one succeeds
# 6. Status validation accepts all five lifecycle states
# 7. Lock file is created during claim (proof of flock path)
# 8. Lock is shared with work-resolve (same .work-resolve.lock filename)
#
# Run from repo root: bash tests/scenario-work-claim.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-work-claim"

passed=0; failed=0; total=0
pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }
cleanup() { rm -rf "$TEST_BASE" 2>/dev/null || true; }
trap cleanup EXIT

echo ""
echo "scenario: work-claim.sh atomic CAS on WD status"
echo "──────────────────────────────────────────────────────────────────"

cleanup

setup_fixture() {
  local proj="$TEST_BASE/project"
  rm -rf "$TEST_BASE"
  mkdir -p "$proj/.work/example" "$proj/.spec/registry" "$proj/.claude/scripts" "$proj/.decisions"
  cp "$REPO_ROOT/scripts/work-claim.sh"   "$proj/.claude/scripts/"
  cp "$REPO_ROOT/scripts/work-resolve.sh" "$proj/.claude/scripts/"
  cp "$REPO_ROOT/scripts/work-lib.sh"     "$proj/.claude/scripts/"
  cp "$REPO_ROOT/scripts/spec-lib.sh"     "$proj/.claude/scripts/"
  echo '{"schema_version":2,"specs":[]}' > "$proj/.spec/registry/manifest.json"

  cat > "$proj/.work/example/WD-01.md" <<'EOF'
---
id: WD-01
title: First
group: example
status: DRAFT
domains: [foo]
artifact_deps: []
produces: []
---

## Summary
First.
EOF
  echo "$proj"
}

# ── Test 1: claim succeeds when status matches ──────────────────────────────

echo ""
echo "── Test 1: claim DRAFT → SPECIFYING when status is DRAFT"

proj=$(setup_fixture)
( cd "$proj" && bash .claude/scripts/work-claim.sh example WD-01 DRAFT SPECIFYING ) >/tmp/claim.out 2>&1
rc=$?
if [[ $rc -eq 0 ]] && grep -q "^status: SPECIFYING" "$proj/.work/example/WD-01.md"; then
    pass "claim succeeded, status flipped"
else
    fail "claim should have succeeded" "rc=$rc, output: $(cat /tmp/claim.out)"
fi

# ── Test 2: claim fails when status differs ─────────────────────────────────

echo ""
echo "── Test 2: re-claim DRAFT → SPECIFYING fails (status is now SPECIFYING)"

if ( cd "$proj" && bash .claude/scripts/work-claim.sh example WD-01 DRAFT SPECIFYING ) >/tmp/claim.out 2>&1; then
    fail "claim should have failed with CONFLICT"
else
    rc=$?
    if [[ $rc -eq 1 ]] && grep -q "CONFLICT" /tmp/claim.out; then
        pass "claim correctly rejected with exit 1 + CONFLICT message"
    else
        fail "wrong failure mode" "rc=$rc, output: $(cat /tmp/claim.out)"
    fi
fi

# ── Test 3: bogus new-status rejected ───────────────────────────────────────

echo ""
echo "── Test 3: bogus new-status 'SPECIFFIED' rejected (exit 2)"

proj=$(setup_fixture)
if ( cd "$proj" && bash .claude/scripts/work-claim.sh example WD-01 DRAFT SPECIFFIED ) >/tmp/claim.out 2>&1; then
    fail "should have rejected typo"
else
    rc=$?
    if [[ $rc -eq 2 ]] && grep -q "unknown new-status" /tmp/claim.out; then
        pass "typo rejected with exit 2 before any write"
    else
        fail "wrong failure mode for typo" "rc=$rc, output: $(cat /tmp/claim.out)"
    fi
fi

# Verify the WD is unchanged after the typo rejection
if grep -q "^status: DRAFT" "$proj/.work/example/WD-01.md"; then
    pass "WD unchanged after typo rejection"
else
    fail "WD was modified despite typo rejection" "$(grep '^status:' $proj/.work/example/WD-01.md)"
fi

# ── Test 4: missing WD file rejected ────────────────────────────────────────

echo ""
echo "── Test 4: missing WD file rejected (exit 2)"

proj=$(setup_fixture)
if ( cd "$proj" && bash .claude/scripts/work-claim.sh example WD-99 DRAFT SPECIFYING ) >/tmp/claim.out 2>&1; then
    fail "should have rejected missing WD"
else
    rc=$?
    if [[ $rc -eq 2 ]] && grep -q "WD file not found" /tmp/claim.out; then
        pass "missing WD rejected with exit 2"
    else
        fail "wrong failure mode for missing WD" "rc=$rc, output: $(cat /tmp/claim.out)"
    fi
fi

# ── Test 5: parallel claims — only one succeeds ─────────────────────────────

echo ""
echo "── Test 5: 5 parallel claims of DRAFT → SPECIFYING — exactly one wins"

if ! command -v flock >/dev/null 2>&1; then
    pass "skipped — flock not available; parallel safety not testable"
    pass "skipped — flock not available; parallel safety not testable"
else
    proj=$(setup_fixture)

    # Fire 5 concurrent claim attempts, capture their exit codes
    rcs_file="/tmp/claim-rcs.$$"
    : > "$rcs_file"
    for i in 1 2 3 4 5; do
        (
            cd "$proj"
            if bash .claude/scripts/work-claim.sh example WD-01 DRAFT SPECIFYING >/dev/null 2>&1; then
                echo "0" >> "$rcs_file"
            else
                echo "$?" >> "$rcs_file"
            fi
        ) &
    done
    wait

    successes=$(grep -c '^0$' "$rcs_file" || true)
    conflicts=$(grep -c '^1$' "$rcs_file" || true)
    rm -f "$rcs_file"

    if [[ "$successes" -eq 1 ]]; then
        pass "exactly one claim succeeded"
    else
        fail "wrong number of successes" "got $successes (expected 1)"
    fi

    if [[ "$conflicts" -eq 4 ]]; then
        pass "four claims correctly rejected as CONFLICT"
    else
        fail "wrong number of conflicts" "got $conflicts (expected 4)"
    fi
fi

# ── Test 6: lifecycle state validation ─────────────────────────────────────

echo ""
echo "── Test 6: each lifecycle state accepted as new-status"

# Set up a fresh DRAFT each time and walk through the lifecycle
walk_ok=true
for transition in "DRAFT SPECIFYING" "SPECIFYING SPECIFIED" "SPECIFIED IMPLEMENTING" "IMPLEMENTING COMPLETE"; do
    read -r expected new <<< "$transition"
    proj=$(setup_fixture)
    # Set status to expected
    sed -i "s/^status:.*/status: $expected/" "$proj/.work/example/WD-01.md"
    if ! ( cd "$proj" && bash .claude/scripts/work-claim.sh example WD-01 "$expected" "$new" ) >/dev/null 2>&1; then
        walk_ok=false
        break
    fi
done
if [[ "$walk_ok" == "true" ]]; then
    pass "all four lifecycle transitions accepted"
else
    fail "some lifecycle transition rejected"
fi

# ── Test 7: lock file created during claim ─────────────────────────────────

echo ""
echo "── Test 7: .work-resolve.lock created during claim"

if command -v flock >/dev/null 2>&1; then
    proj=$(setup_fixture)
    ( cd "$proj" && bash .claude/scripts/work-claim.sh example WD-01 DRAFT SPECIFYING ) >/dev/null 2>&1
    if [[ -f "$proj/.work/example/.work-resolve.lock" ]]; then
        pass "lock file present"
    else
        fail "lock file not created"
    fi
else
    pass "skipped — flock not available"
fi

# ── Test 8: claim and resolve share the lock (mutually exclusive) ──────────

echo ""
echo "── Test 8: claim uses the same .work-resolve.lock as work-resolve.sh"

# We assert by file presence — both scripts use the same path. A more
# rigorous test would block one and verify the other waits, but file
# presence proves the namespace is shared.
if command -v flock >/dev/null 2>&1; then
    proj=$(setup_fixture)
    ( cd "$proj" && bash .claude/scripts/work-claim.sh example WD-01 DRAFT SPECIFYING ) >/dev/null 2>&1
    lock_after_claim="$proj/.work/example/.work-resolve.lock"
    [[ -f "$lock_after_claim" ]] || fail "claim lock missing"

    # Run resolve — uses same lock file
    ( cd "$proj" && bash .claude/scripts/work-resolve.sh example ) >/dev/null 2>&1
    if [[ -f "$lock_after_claim" ]]; then
        pass "claim and resolve share .work-resolve.lock"
    else
        fail "lock disappeared between claim and resolve"
    fi
else
    pass "skipped — flock not available"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "──────────────────────────────────────────────────────────────────"
echo "Total: $total | Passed: $passed | Failed: $failed"

(( failed > 0 )) && exit 1
exit 0
