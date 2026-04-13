#!/usr/bin/env bash
# Scenario: work-validate.sh correctly validates work definition files
#
# Tests:
# 1. Valid WD passes
# 2. Missing required field fails
# 3. Invalid status enum fails
# 4. Empty domains fails
# 5. Invalid artifact_deps type fails
# 6. Missing artifact_deps reference fails
# 7. Scope signal warning for >5 deps
# 8. Missing narrative sections fails
# 9. Circular dependency detection (group mode)
# 10. No circular deps passes (group mode)
#
# Run from repo root: bash tests/scenario-work-validate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-work-validate"

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
echo "scenario: work-validate structural validation"
echo "────────────────────────────────────────────────"

# ── Setup ────────────────────────────────────────────────────────────────────

cleanup
mkdir -p "$TEST_BASE/project/.work/test-group"
mkdir -p "$TEST_BASE/project/.claude/scripts"

# Copy scripts
cp "$REPO_ROOT/scripts/work-validate.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-lib.sh" "$TEST_BASE/project/.claude/scripts/"

cd "$TEST_BASE/project"

# ── Test 1: Valid WD passes ──────────────────────────────────────────────────

echo ""
echo "── Test 1: Valid WD passes"

cat > .work/test-group/WD-01.md << 'EOF'
---
id: WD-01
title: JWT token library
group: test-group
status: DRAFT
domains: [auth, crypto]
artifact_deps:
  - { type: spec, path: "auth/jwt-token-contract", required_state: APPROVED }
produces:
  - { type: spec, path: "auth/jwt-token-contract" }
---

## Summary
Add JWT token creation and validation library.

## Acceptance Criteria
JWT tokens can be created and validated.

## Implementation Notes
Use standard JWT library.
EOF

output="$(bash .claude/scripts/work-validate.sh .work/test-group/WD-01.md 2>&1)"
if echo "$output" | grep -q "PASS"; then
    pass "valid WD passes validation"
else
    fail "valid WD should pass" "got: $output"
fi

# ── Test 2: Missing required field fails ─────────────────────────────────────

echo ""
echo "── Test 2: Missing required field fails"

cat > .work/test-group/bad-missing-field.md << 'EOF'
---
id: WD-BAD
title: Missing group field
status: DRAFT
domains: [auth]
---

## Summary
Test.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-validate.sh .work/test-group/bad-missing-field.md 2>&1 || true)"
if echo "$output" | grep -q "FAIL" && echo "$output" | grep -q "Missing required field: group"; then
    pass "missing required field fails validation"
else
    fail "missing required field should fail" "got: $output"
fi

# ── Test 3: Invalid status enum fails ────────────────────────────────────────

echo ""
echo "── Test 3: Invalid status enum fails"

cat > .work/test-group/bad-status.md << 'EOF'
---
id: WD-BAD2
title: Bad status
group: test-group
status: INVALID_STATUS
domains: [auth]
---

## Summary
Test.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-validate.sh .work/test-group/bad-status.md 2>&1 || true)"
if echo "$output" | grep -q "FAIL" && echo "$output" | grep -q "Invalid status"; then
    pass "invalid status enum fails validation"
else
    fail "invalid status should fail" "got: $output"
fi

# ── Test 4: Empty domains fails ──────────────────────────────────────────────

echo ""
echo "── Test 4: Empty domains fails"

cat > .work/test-group/bad-domains.md << 'EOF'
---
id: WD-BAD3
title: Empty domains
group: test-group
status: DRAFT
domains: []
---

## Summary
Test.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-validate.sh .work/test-group/bad-domains.md 2>&1 || true)"
if echo "$output" | grep -q "FAIL" && echo "$output" | grep -q "domains is empty"; then
    pass "empty domains fails validation"
else
    fail "empty domains should fail" "got: $output"
fi

# ── Test 5: Invalid artifact_deps type fails ─────────────────────────────────

echo ""
echo "── Test 5: Invalid artifact_deps type fails"

cat > .work/test-group/bad-dep-type.md << 'EOF'
---
id: WD-BAD4
title: Bad dep type
group: test-group
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: invalid, path: "foo/bar", required_state: APPROVED }
---

## Summary
Test.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-validate.sh .work/test-group/bad-dep-type.md 2>&1 || true)"
if echo "$output" | grep -q "FAIL" && echo "$output" | grep -q "invalid type"; then
    pass "invalid artifact_deps type fails validation"
else
    fail "invalid dep type should fail" "got: $output"
fi

# ── Test 6: Missing artifact_deps required_state fails ───────────────────────

echo ""
echo "── Test 6: Missing artifact_deps required_state fails"

cat > .work/test-group/bad-dep-state.md << 'EOF'
---
id: WD-BAD5
title: Missing required state
group: test-group
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "foo/bar" }
---

## Summary
Test.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-validate.sh .work/test-group/bad-dep-state.md 2>&1 || true)"
if echo "$output" | grep -q "FAIL" && echo "$output" | grep -q "missing required_state"; then
    pass "missing required_state fails validation"
else
    fail "missing required_state should fail" "got: $output"
fi

# ── Test 7: Scope signal warning for >5 deps ────────────────────────────────

echo ""
echo "── Test 7: Scope signal warning for >5 deps"

cat > .work/test-group/many-deps.md << 'EOF'
---
id: WD-MANY
title: Many deps
group: test-group
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "a/b", required_state: APPROVED }
  - { type: spec, path: "c/d", required_state: APPROVED }
  - { type: spec, path: "e/f", required_state: APPROVED }
  - { type: adr, slug: "g", required_status: accepted }
  - { type: adr, slug: "h", required_status: accepted }
  - { type: kb, path: "i/j/k" }
---

## Summary
Test.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-validate.sh .work/test-group/many-deps.md 2>&1)"
if echo "$output" | grep -q "PASS" && echo "$output" | grep -q "WARN.*consider decomposing"; then
    pass "scope signal warning shown for >5 deps"
else
    fail "should warn about >5 deps but pass" "got: $output"
fi

# ── Test 8: Missing narrative sections fails ─────────────────────────────────

echo ""
echo "── Test 8: Missing narrative sections fails"

cat > .work/test-group/bad-narrative.md << 'EOF'
---
id: WD-BAD6
title: Missing sections
group: test-group
status: DRAFT
domains: [auth]
---

No proper sections here.
EOF

output="$(bash .claude/scripts/work-validate.sh .work/test-group/bad-narrative.md 2>&1 || true)"
if echo "$output" | grep -q "FAIL" && echo "$output" | grep -q "Missing.*Summary"; then
    pass "missing narrative sections fails validation"
else
    fail "missing sections should fail" "got: $output"
fi

# ── Test 9: Circular dependency detection (group mode) ───────────────────────

echo ""
echo "── Test 9: Circular dependency detection (group mode)"

# Set up a clean group with circular deps: WD-A produces X, WD-B consumes X and produces Y, WD-A consumes Y
mkdir -p .work/circular-group

cat > .work/circular-group/WD-01.md << 'EOF'
---
id: WD-01
title: Circular A
group: circular-group
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth/from-b", required_state: APPROVED }
produces:
  - { type: spec, path: "auth/from-a" }
---

## Summary
Test circular dep A.

## Acceptance Criteria
Test.
EOF

cat > .work/circular-group/WD-02.md << 'EOF'
---
id: WD-02
title: Circular B
group: circular-group
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth/from-a", required_state: APPROVED }
produces:
  - { type: spec, path: "auth/from-b" }
---

## Summary
Test circular dep B.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-validate.sh --group circular-group 2>&1 || true)"
if echo "$output" | grep -q "CIRCULAR"; then
    pass "circular dependencies detected"
else
    fail "circular deps should be detected" "got: $output"
fi

# ── Test 10: No circular deps passes (group mode) ───────────────────────────

echo ""
echo "── Test 10: No circular deps passes (group mode)"

mkdir -p .work/acyclic-group

cat > .work/acyclic-group/WD-01.md << 'EOF'
---
id: WD-01
title: First
group: acyclic-group
status: DRAFT
domains: [auth]
produces:
  - { type: spec, path: "auth/token-format" }
---

## Summary
First WD, no deps.

## Acceptance Criteria
Test.
EOF

cat > .work/acyclic-group/WD-02.md << 'EOF'
---
id: WD-02
title: Second
group: acyclic-group
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth/token-format", required_state: APPROVED }
---

## Summary
Depends on WD-01's output.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-validate.sh --group acyclic-group 2>&1)"
if echo "$output" | grep -q "ALL PASSED" && echo "$output" | grep -q "No circular"; then
    pass "acyclic group passes validation"
else
    fail "acyclic group should pass" "got: $output"
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
