#!/usr/bin/env bash
# Scenario: work-context.sh produces correct context snippets
#
# Tests:
# 1. No .work/ directory → empty output
# 2. --group with valid slug → context for that group
# 3. --group with invalid slug → empty output
# 4. --domains matching a work group → context produced
# 5. --domains with no match → empty output
# 6. --feature with double-dash convention → auto-detects group
# 7. Interface contracts surfaced in context
# 8. ADR dependencies aggregated across WDs
# 9. Multiple groups with overlapping domains → both reported
# 10. Empty group (no WDs) → produces header but empty table
#
# Run from repo root: bash tests/scenario-work-context.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-work-context"

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
echo "scenario: work-context context builder"
echo "────────────────────────────────────────────────"

# ── Setup ────────────────────────────────────────────────────────────────────

cleanup
mkdir -p "$TEST_BASE/project/.claude/scripts"

# Copy scripts
cp "$REPO_ROOT/scripts/work-context.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-lib.sh" "$TEST_BASE/project/.claude/scripts/"

# ── Test 1: No .work/ directory → empty output ──────────────────────────────

echo ""
echo "── Test 1: No .work/ directory produces empty output"

output="$(cd "$TEST_BASE/project" && bash .claude/scripts/work-context.sh --domains "auth" 2>&1)"
if [[ -z "$output" ]]; then
    pass "no .work/ directory produces empty output"
else
    fail "should produce empty output without .work/" "got: $output"
fi

# ── Setup: create work group structure ───────────────────────────────────────

mkdir -p "$TEST_BASE/project/.work/auth-migration"

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
domains: [auth, crypto]
produces:
  - { type: spec, path: "auth/jwt-token-contract" }
---

## Summary
JWT token library.

## Acceptance Criteria
Test.
EOF

cat > "$TEST_BASE/project/.work/auth-migration/WD-02.md" << 'EOF'
---
id: WD-02
title: Auth middleware rewrite
group: auth-migration
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth/jwt-token-contract", required_state: APPROVED }
  - { type: adr, slug: "token-format", required_status: accepted }
produces:
  - { type: spec, path: "auth/token-validator", kind: interface-contract }
---

## Summary
Rewrite auth middleware.

## Acceptance Criteria
Test.
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
  - { type: adr, slug: "token-format", required_status: accepted }
---

## Summary
Session migration.

## Acceptance Criteria
Test.
EOF

cd "$TEST_BASE/project"

# ── Test 2: --group with valid slug → context produced ───────────────────────

echo ""
echo "── Test 2: --group with valid slug produces context"

output="$(bash .claude/scripts/work-context.sh --group auth-migration 2>&1)"
if echo "$output" | grep -q "Work Group Context" && echo "$output" | grep -q "auth-migration"; then
    pass "--group produces context for valid slug"
else
    fail "--group should produce context" "got: $output"
fi

# ── Test 3: --group with invalid slug → empty output ────────────────────────

echo ""
echo "── Test 3: --group with invalid slug produces empty output"

output="$(bash .claude/scripts/work-context.sh --group nonexistent 2>&1)"
if [[ -z "$output" ]]; then
    pass "--group with invalid slug produces empty output"
else
    fail "invalid slug should produce empty output" "got: $output"
fi

# ── Test 4: --domains matching → context produced ────────────────────────────

echo ""
echo "── Test 4: --domains matching produces context"

output="$(bash .claude/scripts/work-context.sh --domains "auth" 2>&1)"
if echo "$output" | grep -q "Work Group Context" && echo "$output" | grep -q "auth-migration"; then
    pass "--domains auth matches auth-migration group"
else
    fail "--domains auth should match" "got: $output"
fi

# ── Test 5: --domains with no match → empty output ──────────────────────────

echo ""
echo "── Test 5: --domains with no match produces empty output"

output="$(bash .claude/scripts/work-context.sh --domains "billing" 2>&1)"
if [[ -z "$output" ]]; then
    pass "--domains with no matching WDs produces empty output"
else
    fail "unmatched domain should produce empty output" "got: $output"
fi

# ── Test 6: --feature with double-dash convention ────────────────────────────

echo ""
echo "── Test 6: --feature with double-dash auto-detects group"

# Create a feature directory with the double-dash convention
mkdir -p .feature/auth-migration--jwt-token

output="$(bash .claude/scripts/work-context.sh --feature "auth-migration--jwt-token" 2>&1)"
if echo "$output" | grep -q "auth-migration"; then
    pass "--feature with double-dash detects work group"
else
    fail "--feature double-dash should detect group" "got: $output"
fi

rm -rf .feature

# ── Test 7: Interface contracts surfaced ─────────────────────────────────────

echo ""
echo "── Test 7: Interface contracts surfaced in context"

output="$(bash .claude/scripts/work-context.sh --group auth-migration 2>&1)"
if echo "$output" | grep -q "Shared interfaces" && echo "$output" | grep -q "token-validator"; then
    pass "interface contracts shown in context"
else
    fail "should show interface contracts" "got: $output"
fi

# ── Test 8: ADR dependencies aggregated ──────────────────────────────────────

echo ""
echo "── Test 8: ADR dependencies aggregated across WDs"

output="$(bash .claude/scripts/work-context.sh --group auth-migration 2>&1)"
if echo "$output" | grep -q "ADR dependencies" && echo "$output" | grep -q "token-format"; then
    pass "ADR dependencies aggregated"
else
    fail "should aggregate ADR deps" "got: $output"
fi

# Check that token-format shows both consumers
if echo "$output" | grep "token-format" | grep -q "WD-02" && echo "$output" | grep "token-format" | grep -q "WD-03"; then
    pass "token-format ADR shows both WD-02 and WD-03 as consumers"
else
    fail "token-format should show both consumers" "got: $(echo "$output" | grep token-format)"
fi

# ── Test 9: Multiple groups with overlapping domains ─────────────────────────

echo ""
echo "── Test 9: Multiple groups with overlapping domains"

mkdir -p .work/auth-audit
cat > .work/auth-audit/work.md << 'EOF'
---
group: auth-audit
goal: Audit authentication code
status: active
created: 2026-04-11
---

## Goal
Audit auth code.
EOF

cat > .work/auth-audit/WD-01.md << 'EOF'
---
id: WD-01
title: Auth code review
group: auth-audit
status: DRAFT
domains: [auth]
---

## Summary
Review auth code.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-context.sh --domains "auth" 2>&1)"
auth_migration_found=false
auth_audit_found=false
echo "$output" | grep -q "auth-migration" && auth_migration_found=true
echo "$output" | grep -q "auth-audit" && auth_audit_found=true

if [[ "$auth_migration_found" == "true" && "$auth_audit_found" == "true" ]]; then
    pass "both groups with auth domain reported"
else
    fail "should report both groups" "migration=$auth_migration_found audit=$auth_audit_found"
fi

# ── Test 10: Empty group → header but empty table ────────────────────────────

echo ""
echo "── Test 10: Empty group produces header with empty table"

mkdir -p .work/empty-group
cat > .work/empty-group/work.md << 'EOF'
---
group: empty-group
goal: Empty test
status: active
created: 2026-04-11
---

## Goal
Empty.
EOF

output="$(bash .claude/scripts/work-context.sh --group empty-group 2>&1)"
if echo "$output" | grep -q "empty-group" && echo "$output" | grep -q "Empty test"; then
    pass "empty group shows header with goal"
else
    fail "empty group should show header" "got: $output"
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
