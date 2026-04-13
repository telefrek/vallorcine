#!/usr/bin/env bash
# Scenario: work group and work definition creation flow
#
# Tests the file structures that /work and /work-decompose create,
# and verifies they integrate with work-validate.sh and work-resolve.sh.
#
# Tests:
# 1. Work group directory structure is valid
# 2. Work.md has required YAML fields
# 3. Manifest.md is well-formed
# 4. WD files pass work-validate.sh
# 5. work-resolve.sh works on the created group
# 6. CLAUDE.md index has correct table format
# 7. WD with interface contract produces entry is valid
# 8. Multiple WDs with dependency chain resolve correctly
# 9. Adding a WD to existing group preserves existing WDs
# 10. Empty group (no WDs) handled gracefully by resolve
#
# Run from repo root: bash tests/scenario-work-creation.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-work-creation"

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
echo "scenario: work group creation flow"
echo "────────────────────────────────────────────────"

# ── Setup ────────────────────────────────────────────────────────────────────

cleanup
mkdir -p "$TEST_BASE/project/.work"
mkdir -p "$TEST_BASE/project/.claude/scripts"
mkdir -p "$TEST_BASE/project/.spec/registry"
mkdir -p "$TEST_BASE/project/.spec/domains/auth"
mkdir -p "$TEST_BASE/project/.decisions/token-format"

# Copy scripts
cp "$REPO_ROOT/scripts/work-validate.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-resolve.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-lib.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$TEST_BASE/project/.claude/scripts/"

# Copy seed
cp "$REPO_ROOT/work/CLAUDE.md" "$TEST_BASE/project/.work/CLAUDE.md"

cd "$TEST_BASE/project"

# ── Test 1: Work group directory structure ───────────────────────────────────

echo ""
echo "── Test 1: Work group directory structure is valid"

mkdir -p .work/auth-migration

cat > .work/auth-migration/work.md << 'EOF'
---
group: auth-migration
goal: Replace session tokens with JWT across all services
status: active
created: 2026-04-11
---

## Goal
Replace session tokens with JWT across all services.

## Scope
### In scope
- JWT token library
- Auth middleware rewrite
- Session migration path

### Out of scope
- OAuth provider integration

## Ordering Constraints
- JWT library must be specified before middleware rewrite
- Migration depends on both library and middleware

## Shared Interfaces
- TokenValidator interface between library and middleware
- MigrationStrategy interface between middleware and migration

## Success Criteria
- All services authenticate via JWT
- No session tokens remain in production
EOF

if [[ -f .work/auth-migration/work.md ]]; then
    pass "work group directory structure is valid"
else
    fail "work.md should exist in group directory"
fi

# ── Test 2: Work.md has required YAML fields ─────────────────────────────────

echo ""
echo "── Test 2: Work.md has required YAML fields"

has_group=$(grep -c '^group:' .work/auth-migration/work.md || true)
has_goal=$(grep -c '^goal:' .work/auth-migration/work.md || true)
has_status=$(grep -c '^status:' .work/auth-migration/work.md || true)
has_created=$(grep -c '^created:' .work/auth-migration/work.md || true)

if (( has_group > 0 && has_goal > 0 && has_status > 0 && has_created > 0 )); then
    pass "work.md has all required YAML fields"
else
    fail "work.md missing required fields" "group=$has_group goal=$has_goal status=$has_status created=$has_created"
fi

# ── Test 3: Manifest.md is well-formed ───────────────────────────────────────

echo ""
echo "── Test 3: Manifest.md is well-formed"

cat > .work/auth-migration/manifest.md << 'EOF'
# Work Group Manifest: auth-migration

**Goal:** Replace session tokens with JWT across all services
**Status:** active
**Created:** 2026-04-11
**Work definitions:** 3

## Work Definitions

| WD | Title | Status | Domains | Deps | Produces |
|----|-------|--------|---------|------|----------|
| WD-01 | JWT token library | DRAFT | auth, crypto | 0 | spec:auth/jwt-token-contract |
| WD-02 | Auth middleware rewrite | DRAFT | auth | 1 | spec:auth/token-validator |
| WD-03 | Session migration | DRAFT | auth | 2 | — |

## Dependency Graph

WD-01 (no deps)
  └→ WD-02 (needs: auth/jwt-token-contract from WD-01)
       └→ WD-03 (needs: auth/token-validator from WD-02, auth/jwt-token-contract from WD-01)
EOF

if grep -q "Work Definitions" .work/auth-migration/manifest.md && \
   grep -q "Dependency Graph" .work/auth-migration/manifest.md; then
    pass "manifest.md has required sections"
else
    fail "manifest.md missing required sections"
fi

# ── Test 4: WD files pass work-validate.sh ───────────────────────────────────

echo ""
echo "── Test 4: WD files pass work-validate.sh"

cat > .work/auth-migration/WD-01.md << 'EOF'
---
id: WD-01
title: JWT token library
group: auth-migration
status: DRAFT
domains: [auth, crypto]
produces:
  - { type: spec, path: "auth/jwt-token-contract" }
---

## Summary
Add JWT token creation and validation library with configurable claims.

## Acceptance Criteria
- JWT tokens can be created with standard claims
- Token validation rejects expired and malformed tokens
- Signing algorithm is configurable

## Implementation Notes
No external dependencies — this is the foundation.
EOF

cat > .work/auth-migration/WD-02.md << 'EOF'
---
id: WD-02
title: Auth middleware rewrite
group: auth-migration
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth/jwt-token-contract", required_state: APPROVED }
produces:
  - { type: spec, path: "auth/token-validator", kind: interface-contract }
---

## Summary
Replace session-token validation with JWT validation in auth middleware.

## Acceptance Criteria
- All API endpoints validate JWT tokens
- Invalid tokens return 401 with descriptive error
- Token refresh flow works

## Implementation Notes
Depends on WD-01's JWT token contract being specified and approved.
EOF

cat > .work/auth-migration/WD-03.md << 'EOF'
---
id: WD-03
title: Session migration
group: auth-migration
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth/jwt-token-contract", required_state: APPROVED }
  - { type: spec, path: "auth/token-validator", kind: interface-contract, required_state: APPROVED }
---

## Summary
Write migration path for existing sessions to JWT tokens.

## Acceptance Criteria
- Existing sessions converted to JWT without user re-login
- Migration is reversible for rollback
- Migration progress is observable

## Implementation Notes
Depends on both WD-01 (token format) and WD-02 (middleware interface).
EOF

validate_ok=true
for wd in .work/auth-migration/WD-*.md; do
    output="$(bash .claude/scripts/work-validate.sh "$wd" 2>&1)"
    if ! echo "$output" | grep -q "PASS"; then
        fail "WD validation failed for $(basename "$wd")" "got: $output"
        validate_ok=false
    fi
done

if [[ "$validate_ok" == "true" ]]; then
    pass "all 3 WD files pass validation"
fi

# ── Test 5: work-resolve.sh works on created group ──────────────────────────

echo ""
echo "── Test 5: work-resolve.sh works on created group"

output="$(bash .claude/scripts/work-resolve.sh auth-migration 2>&1)"
if echo "$output" | grep -q "Work Group Readiness" && echo "$output" | grep -q "auth-migration"; then
    pass "work-resolve.sh produces readiness report"
else
    fail "work-resolve.sh should produce report" "got: $output"
fi

# ── Test 6: CLAUDE.md index has correct table format ─────────────────────────

echo ""
echo "── Test 6: CLAUDE.md index table format"

# Verify the seed CLAUDE.md has the expected table headers
if grep -q "Active Work Groups" .work/CLAUDE.md && \
   grep -q "Recently Added" .work/CLAUDE.md && \
   grep -q "Group.*Path.*Goal.*WDs.*Ready.*Complete" .work/CLAUDE.md; then
    pass "CLAUDE.md index has correct table format"
else
    fail "CLAUDE.md missing expected table headers"
fi

# ── Test 7: WD with interface contract produces entry ────────────────────────

echo ""
echo "── Test 7: WD with interface contract produces is valid"

# WD-02 produces an interface-contract — validate it passes
output="$(bash .claude/scripts/work-validate.sh .work/auth-migration/WD-02.md 2>&1)"
if echo "$output" | grep -q "PASS"; then
    pass "WD with interface-contract produces passes validation"
else
    fail "WD with interface-contract should pass" "got: $output"
fi

# ── Test 8: Dependency chain resolves correctly ──────────────────────────────

echo ""
echo "── Test 8: Dependency chain resolves correctly"

output="$(bash .claude/scripts/work-resolve.sh auth-migration 2>&1)"

# WD-01 should be READY (no deps)
# WD-02 should be BLOCKED (needs jwt-token-contract)
# WD-03 should be BLOCKED (needs jwt-token-contract + token-validator)
wd01_ready=false
wd02_blocked=false
wd03_blocked=false

echo "$output" | grep "WD-01" | grep -q "READY" && wd01_ready=true
echo "$output" | grep "WD-02" | grep -q "BLOCKED" && wd02_blocked=true
echo "$output" | grep "WD-03" | grep -q "BLOCKED" && wd03_blocked=true

if [[ "$wd01_ready" == "true" && "$wd02_blocked" == "true" && "$wd03_blocked" == "true" ]]; then
    pass "dependency chain: WD-01 ready, WD-02/03 blocked"
else
    fail "dependency chain incorrect" "WD-01=$wd01_ready WD-02=$wd02_blocked WD-03=$wd03_blocked"
fi

# ── Test 9: Adding WD preserves existing WDs ─────────────────────────────────

echo ""
echo "── Test 9: Adding a WD preserves existing WDs"

cat > .work/auth-migration/WD-04.md << 'EOF'
---
id: WD-04
title: Cleanup old session code
group: auth-migration
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth/token-validator", kind: interface-contract, required_state: APPROVED }
---

## Summary
Remove old session token code after migration is complete.

## Acceptance Criteria
- No session token references remain in codebase
- All session-related tests removed or converted

## Implementation Notes
Must run after WD-03 (migration) is verified in production.
EOF

output="$(bash .claude/scripts/work-resolve.sh auth-migration 2>&1)"
wd_count=$(echo "$output" | grep -c "| WD-0" || true)
if (( wd_count == 4 )); then
    pass "adding WD-04 preserved WD-01 through WD-03 (4 total)"
else
    fail "should have 4 WDs after adding WD-04" "found: $wd_count"
fi

# ── Test 10: Empty group handled gracefully ──────────────────────────────────

echo ""
echo "── Test 10: Empty group (no WDs) handled gracefully"

mkdir -p .work/empty-group
cat > .work/empty-group/work.md << 'EOF'
---
group: empty-group
goal: Test empty group handling
status: active
created: 2026-04-11
---

## Goal
Empty group for testing.

## Scope
### In scope
- Nothing yet

### Out of scope
- Nothing

## Success Criteria
- Test passes
EOF

output="$(bash .claude/scripts/work-resolve.sh empty-group 2>&1)"
if echo "$output" | grep -q "Total: 0"; then
    pass "empty group reports 0 WDs gracefully"
else
    fail "empty group should report 0 WDs" "got: $output"
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
