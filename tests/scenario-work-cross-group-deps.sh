#!/usr/bin/env bash
# Scenario: cross-group dependencies via work.md external_deps
#
# Tests:
# 1. external_deps{group=B,COMPLETE} with B in mixed state blocks group-A DRAFT
#    WDs with a clear external reason.
# 2. Same setup blocks group-A SPECIFIED WDs.
# 3. Once all group-B WDs are COMPLETE, group-A WDs unblock.
# 4. external_deps referencing a missing group is flagged as a blocker at
#    resolve-time and as an error at validate-time.
# 5. work-validate.sh --group flags malformed external_deps (wrong type,
#    unsupported required_state, self-reference, missing ref).
# 6. work-resolve.sh ignores IMPLEMENTING/COMPLETE WDs for the external_deps
#    gate (doesn't retroactively un-do in-flight or finished work).
# 7. work-validate.sh rejects a wd: artifact_dep that points at a WD in a
#    different group — cross-group coordination must use external_deps.
#
# Run from repo root: bash tests/scenario-work-cross-group-deps.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-work-cross-group-deps"

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
echo "scenario: cross-group dependencies (external_deps)"
echo "────────────────────────────────────────────────"

# ── Setup ────────────────────────────────────────────────────────────────────

cleanup
mkdir -p "$TEST_BASE/project/.work/group-a"
mkdir -p "$TEST_BASE/project/.work/group-b"
mkdir -p "$TEST_BASE/project/.claude/scripts"

cp "$REPO_ROOT/scripts/work-resolve.sh"  "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-validate.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-lib.sh"      "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh"      "$TEST_BASE/project/.claude/scripts/"

cd "$TEST_BASE/project"

write_wd() {
    local group="$1"
    local id="$2"
    local status="$3"
    cat > ".work/$group/$id.md" << EOF
---
id: $id
title: $id of $group
group: $group
status: $status
domains: [core]
---

## Summary
Test $id.

## Acceptance Criteria
Test.
EOF
}

write_group_a_work_md() {
    local external_deps_block="$1"
    cat > ".work/group-a/work.md" << EOF
---
group: group-a
goal: Exercise external_deps gate
status: active
$external_deps_block
---

## Goal

Test external_deps behavior.
EOF
}

# ── Test 1: DRAFT WD in group-a BLOCKED when group-b not COMPLETE ────────────

echo ""
echo "── Test 1: DRAFT WD in group-a BLOCKED when group-b not COMPLETE"

write_wd group-b WD-01 DRAFT
write_wd group-b WD-02 DRAFT
write_wd group-a WD-01 DRAFT
write_group_a_work_md 'external_deps:
  - { type: group, ref: "group-b", required_state: COMPLETE }'

output="$(bash .claude/scripts/work-resolve.sh group-a 2>&1 || true)"
if echo "$output" | grep -q "BLOCKED" && echo "$output" | grep -q "external group:group-b"; then
    pass "DRAFT WD blocked by unmet external group dep"
else
    fail "DRAFT WD should be BLOCKED with external group reason" "got: $output"
fi

# ── Test 2: SPECIFIED WD in group-a also BLOCKED by external_deps ────────────

echo ""
echo "── Test 2: SPECIFIED WD in group-a BLOCKED when group-b not COMPLETE"

write_wd group-a WD-02 SPECIFIED
output="$(bash .claude/scripts/work-resolve.sh group-a 2>&1 || true)"
# WD-02 line should be in BLOCKED row
if echo "$output" | grep -E '^\| WD-02 .* BLOCKED ' >/dev/null && echo "$output" | grep -q "external group:group-b"; then
    pass "SPECIFIED WD blocked by unmet external group dep"
else
    fail "SPECIFIED WD should be BLOCKED by external_deps" "got: $output"
fi

# ── Test 3: group-b COMPLETE → group-a unblocks ──────────────────────────────

echo ""
echo "── Test 3: group-a unblocks once all group-b WDs are COMPLETE"

write_wd group-b WD-01 COMPLETE
write_wd group-b WD-02 COMPLETE
output="$(bash .claude/scripts/work-resolve.sh group-a 2>&1 || true)"
if echo "$output" | grep -E '^\| WD-01 .* READY '     >/dev/null \
   && echo "$output" | grep -E '^\| WD-02 .* SPECIFIED ' >/dev/null \
   && ! echo "$output" | grep -q "external group:group-b"; then
    pass "group-a WDs unblock when group-b reaches COMPLETE"
else
    fail "group-a should unblock once group-b COMPLETE" "got: $output"
fi

# ── Test 4: missing referenced group → blocker at resolve, error at validate ─

echo ""
echo "── Test 4: external_deps pointing at missing group is flagged"

write_group_a_work_md 'external_deps:
  - { type: group, ref: "group-nonexistent", required_state: COMPLETE }'

output="$(bash .claude/scripts/work-resolve.sh group-a 2>&1 || true)"
if echo "$output" | grep -q "external group:group-nonexistent" \
   && echo "$output" | grep -q "not found"; then
    pass "resolver flags missing external group as a blocker"
else
    fail "resolver should report missing group as blocker" "got: $output"
fi

validate_out="$(bash .claude/scripts/work-validate.sh --group group-a 2>&1 || true)"
if echo "$validate_out" | grep -q "FAILED" \
   && echo "$validate_out" | grep -q "group-nonexistent"; then
    pass "validator flags missing referenced group"
else
    fail "validator should fail on missing referenced group" "got: $validate_out"
fi

# ── Test 5: malformed external_deps caught by validator ──────────────────────

echo ""
echo "── Test 5: validator rejects malformed external_deps"

# 5a: wrong type
write_group_a_work_md 'external_deps:
  - { type: spec, ref: "group-b", required_state: COMPLETE }'
validate_out="$(bash .claude/scripts/work-validate.sh --group group-a 2>&1 || true)"
if echo "$validate_out" | grep -q "invalid type 'spec'"; then
    pass "validator rejects wrong external_deps type"
else
    fail "validator should reject type=spec in external_deps" "got: $validate_out"
fi

# 5b: unsupported required_state
write_group_a_work_md 'external_deps:
  - { type: group, ref: "group-b", required_state: SPECIFIED }'
validate_out="$(bash .claude/scripts/work-validate.sh --group group-a 2>&1 || true)"
if echo "$validate_out" | grep -q "required_state 'SPECIFIED' unsupported"; then
    pass "validator rejects unsupported required_state"
else
    fail "validator should reject required_state=SPECIFIED" "got: $validate_out"
fi

# 5c: self-reference
write_group_a_work_md 'external_deps:
  - { type: group, ref: "group-a", required_state: COMPLETE }'
validate_out="$(bash .claude/scripts/work-validate.sh --group group-a 2>&1 || true)"
if echo "$validate_out" | grep -q "references itself"; then
    pass "validator rejects self-reference"
else
    fail "validator should reject self-reference" "got: $validate_out"
fi

# 5d: missing ref
write_group_a_work_md 'external_deps:
  - { type: group, ref: "", required_state: COMPLETE }'
validate_out="$(bash .claude/scripts/work-validate.sh --group group-a 2>&1 || true)"
if echo "$validate_out" | grep -q "missing ref"; then
    pass "validator rejects missing ref"
else
    fail "validator should reject missing ref" "got: $validate_out"
fi

# ── Test 6: IMPLEMENTING and COMPLETE WDs ignore the external gate ───────────

echo ""
echo "── Test 6: IMPLEMENTING and COMPLETE WDs are not retroactively blocked"

write_wd group-b WD-01 DRAFT
write_wd group-b WD-02 DRAFT
write_group_a_work_md 'external_deps:
  - { type: group, ref: "group-b", required_state: COMPLETE }'
write_wd group-a WD-01 DRAFT
write_wd group-a WD-02 IMPLEMENTING
write_wd group-a WD-03 COMPLETE

output="$(bash .claude/scripts/work-resolve.sh group-a 2>&1 || true)"
# WD-01 BLOCKED (DRAFT + unmet external), WD-02 IMPLEMENTING, WD-03 COMPLETE
if echo "$output" | grep -E '^\| WD-01 .* BLOCKED '      >/dev/null \
   && echo "$output" | grep -E '^\| WD-02 .* IMPLEMENTING ' >/dev/null \
   && echo "$output" | grep -E '^\| WD-03 .* COMPLETE '     >/dev/null; then
    pass "IMPLEMENTING and COMPLETE WDs bypass external gate"
else
    fail "IMPLEMENTING/COMPLETE should bypass external gate" "got: $output"
fi

# ── Test 7: wd: artifact_dep across groups rejected by validator ─────────────

echo ""
echo "── Test 7: cross-group wd: artifact_dep rejected by validator"

rm -f .work/group-a/WD-*.md .work/group-b/WD-*.md
write_group_a_work_md ''
write_wd group-b WD-01 DRAFT
cat > ".work/group-a/WD-01.md" << 'EOF'
---
id: WD-01
title: Cross-group wd ref
group: group-a
status: DRAFT
domains: [core]
artifact_deps:
  - { type: wd, ref: "WD-01", required_state: COMPLETE }
---

## Summary
Test.

## Acceptance Criteria
Test.
EOF

# In this setup group-a/WD-01 refers to WD-01 which exists in both groups,
# but within group-a's own scope. Replace with one that truly crosses groups.
cat > ".work/group-a/WD-01.md" << 'EOF'
---
id: WD-A-01
title: Cross-group wd ref
group: group-a
status: DRAFT
domains: [core]
artifact_deps:
  - { type: wd, ref: "WD-01", required_state: COMPLETE }
---

## Summary
Test.

## Acceptance Criteria
Test.
EOF

# Re-read: group-a has WD-A-01 with a dep on WD-01. Only group-b has a WD-01.
validate_out="$(bash .claude/scripts/work-validate.sh --group group-a 2>&1 || true)"
if echo "$validate_out" | grep -q "different group"; then
    pass "cross-group wd: artifact_dep rejected with guidance"
else
    fail "validator should reject cross-group wd: dep" "got: $validate_out"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
if (( failed > 0 )); then
    echo "FAILED  $failed/$total"
    exit 1
else
    echo "ALL PASSED  ($passed/$total)"
fi
