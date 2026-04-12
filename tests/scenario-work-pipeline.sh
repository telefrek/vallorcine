#!/usr/bin/env bash
# Scenario: work-start pipeline bridge creates correct feature structures
#
# Tests the file structures /work-start creates and the lifecycle updates
# that feature-retro and feature-complete would trigger.
#
# Tests:
# 1. Feature directory created with double-dash convention
# 2. status.md has work_group and work_definition fields
# 3. status.md starts at scoping/complete
# 4. WD status updated to IN_PROGRESS on start
# 5. WD status updated to COMPLETE triggers readiness cascade
# 6. Double-dash slug convention auto-detects group in work-context.sh
# 7. Manifest updated when WD status changes
# 8. Work group progress reported correctly
# 9. Next selection picks WD with most unblocking value
# 10. All-complete state detected
#
# Run from repo root: bash tests/scenario-work-pipeline.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-work-pipeline"

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
echo "scenario: work pipeline bridge"
echo "────────────────────────────────────────────────"

# ── Setup ────────────────────────────────────────────────────────────────────

cleanup
mkdir -p "$TEST_BASE/project/.work/auth-migration"
mkdir -p "$TEST_BASE/project/.claude/scripts"
mkdir -p "$TEST_BASE/project/.feature"
mkdir -p "$TEST_BASE/project/.spec/registry"
mkdir -p "$TEST_BASE/project/.spec/domains/auth"

# Copy scripts
cp "$REPO_ROOT/scripts/work-lib.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-resolve.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-validate.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-context.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$TEST_BASE/project/.claude/scripts/"

# Create work group with 3 WDs in a chain
cat > "$TEST_BASE/project/.work/auth-migration/work.md" << 'EOF'
---
group: auth-migration
goal: Replace session tokens with JWT
status: active
created: 2026-04-11
---

## Goal
Replace session tokens with JWT.
EOF

cat > "$TEST_BASE/project/.work/auth-migration/WD-01.md" << 'EOF'
---
id: WD-01
title: JWT token library
group: auth-migration
status: DRAFT
domains: [auth]
produces:
  - { type: spec, path: "auth/jwt-token-contract" }
---

## Summary
JWT token library.

## Acceptance Criteria
Tokens created and validated.
EOF

cat > "$TEST_BASE/project/.work/auth-migration/WD-02.md" << 'EOF'
---
id: WD-02
title: Auth middleware
group: auth-migration
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth/jwt-token-contract", required_state: APPROVED }
produces:
  - { type: spec, path: "auth/token-validator", kind: interface-contract }
---

## Summary
Auth middleware rewrite.

## Acceptance Criteria
JWT validation in middleware.
EOF

cat > "$TEST_BASE/project/.work/auth-migration/WD-03.md" << 'EOF'
---
id: WD-03
title: Session migration
group: auth-migration
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth/token-validator", kind: interface-contract, required_state: APPROVED }
---

## Summary
Migrate sessions to JWT.

## Acceptance Criteria
Sessions migrated.
EOF

cd "$TEST_BASE/project"

# ── Test 1: Feature directory with double-dash convention ────────────────────

echo ""
echo "── Test 1: Feature directory created with double-dash convention"

# Simulate what /work-start does
FEATURE_SLUG="auth-migration--wd-01"
mkdir -p ".feature/$FEATURE_SLUG"

if [[ -d ".feature/$FEATURE_SLUG" ]]; then
    pass "feature directory created with double-dash convention"
else
    fail "feature directory should exist"
fi

# ── Test 2: status.md has work group fields ──────────────────────────────────

echo ""
echo "── Test 2: status.md has work_group and work_definition fields"

cat > ".feature/$FEATURE_SLUG/status.md" << 'EOF'
---
work_group: auth-migration
work_definition: WD-01
---

## Current Position
- Stage: scoping
- Substage: complete
EOF

has_wg=$(grep -c '^work_group:' ".feature/$FEATURE_SLUG/status.md" || true)
has_wd=$(grep -c '^work_definition:' ".feature/$FEATURE_SLUG/status.md" || true)

if (( has_wg > 0 && has_wd > 0 )); then
    pass "status.md has work_group and work_definition fields"
else
    fail "status.md missing work group fields"
fi

# ── Test 3: status.md starts at scoping/complete ─────────────────────────────

echo ""
echo "── Test 3: status.md starts at scoping/complete"

if grep -q "Stage: scoping" ".feature/$FEATURE_SLUG/status.md" && \
   grep -q "Substage: complete" ".feature/$FEATURE_SLUG/status.md"; then
    pass "status.md starts at scoping/complete"
else
    fail "should start at scoping/complete"
fi

# ── Test 4: WD status updated to IN_PROGRESS ────────────────────────────────

echo ""
echo "── Test 4: WD status updated to IN_PROGRESS on start"

# Simulate: update WD-01 status to IN_PROGRESS
sed -i 's/^status: DRAFT/status: IN_PROGRESS/' .work/auth-migration/WD-01.md

status=$(grep '^status:' .work/auth-migration/WD-01.md | head -1 | sed 's/^status:[[:space:]]*//')
if [[ "$status" == "IN_PROGRESS" ]]; then
    pass "WD-01 status updated to IN_PROGRESS"
else
    fail "WD-01 should be IN_PROGRESS" "got: $status"
fi

# ── Test 5: Completing WD triggers readiness cascade ─────────────────────────

echo ""
echo "── Test 5: WD completion triggers readiness cascade"

# Complete WD-01 and create the spec it produces
sed -i 's/^status: IN_PROGRESS/status: COMPLETE/' .work/auth-migration/WD-01.md

cat > .spec/domains/auth/F01-jwt-token-contract.md << 'EOF'
---
{
  "id": "F01",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["auth"],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": [],
  "open_obligations": []
}
---

# F01 — JWT Token Contract

## Requirements
R1. JWT tokens created with configurable claims.

---

## Design Narrative
Token format.
EOF

cat > .spec/registry/manifest.json << 'EOF'
{
  "domains": {
    "auth": { "description": "authentication", "feature_count": 1 }
  },
  "features": {
    "F01": {
      "latest_file": "domains/auth/F01-jwt-token-contract.md",
      "state": "APPROVED",
      "domains": ["auth"]
    }
  }
}
EOF

# Run resolver — WD-02 should now be READY (its dep is satisfied)
output="$(bash .claude/scripts/work-resolve.sh auth-migration 2>&1)"
if echo "$output" | grep "WD-02" | grep -q "READY"; then
    pass "WD-02 became READY after WD-01 completed and produced its spec"
else
    fail "WD-02 should be READY" "got: $(echo "$output" | grep WD-02)"
fi

# WD-03 should still be BLOCKED (needs token-validator interface contract)
if echo "$output" | grep "WD-03" | grep -q "BLOCKED"; then
    pass "WD-03 still BLOCKED (needs interface contract from WD-02)"
else
    fail "WD-03 should still be BLOCKED" "got: $(echo "$output" | grep WD-03)"
fi

# ── Test 6: Double-dash auto-detection in work-context.sh ────────────────────

echo ""
echo "── Test 6: Double-dash convention auto-detects in work-context"

output="$(bash .claude/scripts/work-context.sh --feature "auth-migration--wd-01" 2>&1)"
if echo "$output" | grep -q "auth-migration"; then
    pass "work-context.sh auto-detects group from double-dash slug"
else
    fail "should auto-detect group" "got: $output"
fi

# ── Test 7: Resolver shows correct summary counts ───────────────────────────

echo ""
echo "── Test 7: Resolver reports correct summary counts"

output="$(bash .claude/scripts/work-resolve.sh auth-migration 2>&1)"
# Should be: 1 READY (WD-02), 1 BLOCKED (WD-03), 0 IN_PROGRESS, 1 COMPLETE (WD-01)
if echo "$output" | grep -q "Ready: 1" && echo "$output" | grep -q "Complete: 1"; then
    pass "resolver shows correct counts (1 ready, 1 blocked, 1 complete)"
else
    fail "counts incorrect" "got: $(echo "$output" | head -4)"
fi

# ── Test 8: Unblocking value — WD-01 unblocked WD-02 ────────────────────────

echo ""
echo "── Test 8: Unblocking chain tracked correctly"

# WD-01 produced auth/jwt-token-contract, WD-02 depended on it
# The resolver should show WD-01 unblocks WD-02
output="$(bash .claude/scripts/work-resolve.sh auth-migration 2>&1)"
# WD-01 is COMPLETE now, but in the status table it should show it previously unblocked WD-02
# Actually check that WD-02 produces token-validator which unblocks WD-03
if echo "$output" | grep "WD-02" | grep -q "WD-03"; then
    pass "WD-02 shows it unblocks WD-03"
else
    fail "WD-02 should show unblocking WD-03" "got: $(echo "$output" | grep WD-02)"
fi

# ── Test 9: Full completion chain ────────────────────────────────────────────

echo ""
echo "── Test 9: All WDs complete → all reported as COMPLETE"

# Complete WD-02 and WD-03
sed -i 's/^status: DRAFT/status: COMPLETE/' .work/auth-migration/WD-02.md
sed -i 's/^status: DRAFT/status: COMPLETE/' .work/auth-migration/WD-03.md

output="$(bash .claude/scripts/work-resolve.sh auth-migration 2>&1)"
if echo "$output" | grep -q "Complete: 3" && echo "$output" | grep -q "Ready: 0"; then
    pass "all 3 WDs reported as COMPLETE"
else
    fail "should show 3 complete" "got: $(echo "$output" | head -4)"
fi

# ── Test 10: Validate all WDs still pass validation after status changes ─────

echo ""
echo "── Test 10: WDs valid after status lifecycle changes"

all_valid=true
for wd in .work/auth-migration/WD-*.md; do
    output="$(bash .claude/scripts/work-validate.sh "$wd" 2>&1)"
    if ! echo "$output" | grep -q "PASS"; then
        fail "validation failed for $(basename "$wd")" "got: $output"
        all_valid=false
    fi
done

if [[ "$all_valid" == "true" ]]; then
    pass "all WDs pass validation after lifecycle changes"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
if [[ $failed -eq 0 ]]; then
    echo "ALL PASSED  ($passed/$total)"
else
    echo "FAILED  $failed/$total  ($passed passed)"
fi
echo ""

exit $failed
