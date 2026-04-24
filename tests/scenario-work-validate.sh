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
cp "$REPO_ROOT/scripts/spec-lib.sh" "$TEST_BASE/project/.claude/scripts/"

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

# ── Test 11: wd type in artifact_deps is valid ──────────────────────────────

echo ""
echo "── Test 11: wd type in artifact_deps is valid"

cat > "$TEST_BASE/wd-type-valid.md" << 'EOF'
---
id: WD-02
title: Depends on WD-01
group: test-group
status: SPECIFIED
domains: [auth]
artifact_deps:
  - { type: wd, ref: "WD-01", required_state: COMPLETE }
produces: []
---

## Summary
Depends on another WD completing.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-validate.sh "$TEST_BASE/wd-type-valid.md" 2>&1)"
if echo "$output" | grep -q "PASS"; then
    pass "wd type in artifact_deps is valid"
else
    fail "wd type should be accepted" "got: $output"
fi

# ── Test 12: Circular wd deps detected (group mode) ────────────────────────

echo ""
echo "── Test 12: Circular wd deps detected (group mode)"

mkdir -p "$TEST_BASE/project/.work/wd-circular"

cat > "$TEST_BASE/project/.work/wd-circular/WD-01.md" << 'EOF'
---
id: WD-01
title: First
group: wd-circular
status: SPECIFIED
domains: [auth]
artifact_deps:
  - { type: wd, ref: "WD-02", required_state: COMPLETE }
produces: []
---

## Summary
Depends on WD-02.

## Acceptance Criteria
Test.
EOF

cat > "$TEST_BASE/project/.work/wd-circular/WD-02.md" << 'EOF'
---
id: WD-02
title: Second
group: wd-circular
status: SPECIFIED
domains: [auth]
artifact_deps:
  - { type: wd, ref: "WD-01", required_state: COMPLETE }
produces: []
---

## Summary
Depends on WD-01.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-validate.sh --group wd-circular 2>&1)" || true
if echo "$output" | grep -q "CIRCULAR"; then
    pass "circular wd deps detected"
else
    fail "circular wd deps should be detected" "got: $output"
fi

rm -rf "$TEST_BASE/project/.work/wd-circular"

# ── Tests 13-17: artifact_dep resolution (state + existence checks) ─────────
# Regression coverage for Items 4 + 8 of the post-v0.14.0 bug fix sweep:
# work-validate.sh used to accept artifact_deps that pointed at non-existent
# specs/WDs or declared wrong required_state. Now it resolves each reference
# and errors on dead wiring or state mismatches.

echo ""
echo "── Test 13: spec artifact_dep with matching state passes"

mkdir -p "$TEST_BASE/project/.spec/domains/auth"
mkdir -p "$TEST_BASE/project/.spec/registry"

cat > "$TEST_BASE/project/.spec/domains/auth/jwt-contract.md" << 'EOF'
---
{
  "id": "auth.jwt-contract",
  "version": 1,
  "state": "APPROVED",
  "status": "ACTIVE",
  "domains": ["auth"]
}
---

# auth.jwt-contract — JWT Contract

## Requirements
R1. JWT tokens must verify via the published public key.
EOF

cat > "$TEST_BASE/project/.spec/registry/manifest.json" << 'EOF'
{
  "schema_version": 2,
  "specs": [
    {"id": "auth.jwt-contract", "path": ".spec/domains/auth/jwt-contract.md", "state": "APPROVED"}
  ]
}
EOF

mkdir -p "$TEST_BASE/project/.work/resolve-group"
cat > "$TEST_BASE/project/.work/resolve-group/WD-01.md" << 'EOF'
---
id: WD-01
title: Depends on real APPROVED spec
group: resolve-group
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth.jwt-contract", required_state: APPROVED }
---

## Summary
Test.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-validate.sh .work/resolve-group/WD-01.md 2>&1)"
if echo "$output" | grep -q "PASS" && ! echo "$output" | grep -q "FAIL"; then
    pass "spec artifact_dep with matching state passes"
else
    fail "spec dep with real APPROVED target should pass" "got: $output"
fi

echo ""
echo "── Test 14: spec artifact_dep with state mismatch fails"

cat > "$TEST_BASE/project/.work/resolve-group/WD-02.md" << 'EOF'
---
id: WD-02
title: Declares wrong state
group: resolve-group
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth.jwt-contract", required_state: DRAFT }
---

## Summary
Test.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-validate.sh .work/resolve-group/WD-02.md 2>&1 || true)"
if echo "$output" | grep -q "FAIL" && echo "$output" | grep -q "has state 'APPROVED', required_state is 'DRAFT'"; then
    pass "spec artifact_dep with state mismatch fails"
else
    fail "state mismatch should fail with clear message" "got: $output"
fi

echo ""
echo "── Test 15: spec artifact_dep with dead reference fails"

cat > "$TEST_BASE/project/.work/resolve-group/WD-03.md" << 'EOF'
---
id: WD-03
title: References a spec that does not exist
group: resolve-group
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth.phantom-spec", required_state: APPROVED }
---

## Summary
Test.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-validate.sh .work/resolve-group/WD-03.md 2>&1 || true)"
if echo "$output" | grep -q "FAIL" && echo "$output" | grep -q "not found in registry"; then
    pass "spec artifact_dep with dead reference fails"
else
    fail "dead spec reference should fail with 'not found in registry'" "got: $output"
fi

echo ""
echo "── Test 16: wd artifact_dep with nonexistent WD fails"

cat > "$TEST_BASE/project/.work/resolve-group/WD-04.md" << 'EOF'
---
id: WD-04
title: References nonexistent WD
group: resolve-group
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: wd, ref: "WD-99", required_state: COMPLETE }
---

## Summary
Test.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-validate.sh .work/resolve-group/WD-04.md 2>&1 || true)"
if echo "$output" | grep -q "FAIL" && echo "$output" | grep -q "wd 'WD-99' not found in group"; then
    pass "wd artifact_dep with nonexistent WD fails"
else
    fail "nonexistent wd reference should fail" "got: $output"
fi

echo ""
echo "── Test 17: wd artifact_dep with status mismatch fails"

cat > "$TEST_BASE/project/.work/resolve-group/WD-05.md" << 'EOF'
---
id: WD-05
title: Wants WD-01 COMPLETE but WD-01 is DRAFT
group: resolve-group
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: wd, ref: "WD-01", required_state: COMPLETE }
---

## Summary
Test.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-validate.sh .work/resolve-group/WD-05.md 2>&1 || true)"
if echo "$output" | grep -q "FAIL" && echo "$output" | grep -q "wd 'WD-01' has status 'DRAFT', required_status is 'COMPLETE'"; then
    pass "wd artifact_dep with status mismatch fails"
else
    fail "wd status mismatch should fail with clear message" "got: $output"
fi

rm -rf "$TEST_BASE/project/.work/resolve-group"
rm -rf "$TEST_BASE/project/.spec"

# ── Test 18: produces: accepts slug: for ADR artifacts ──────────────────────
#
# jlsm dry-run (2026-04-24) surfaced a parser asymmetry: work_fm_artifact_deps
# accepts { type: adr, slug: "..." } / { ref: "..." } / { path: "..." } but
# work_fm_produces only accepted path:. Real-world ADR produces entries use
# slug: (matches .decisions/<slug>/adr.md layout), so 78 false-alarm
# "missing path for adr artifact" errors were raised across jlsm's
# decisions-backlog group. Both parsers must agree on identifier shape.

echo ""
echo "── Test 18: produces: slug: accepted for ADR artifacts"

mkdir -p "$TEST_BASE/project/.work/produces-group"
cat > "$TEST_BASE/project/.work/produces-group/WD-01.md" << 'EOF'
---
id: WD-01
title: ADR-producing WD using slug identifier
group: produces-group
status: DRAFT
domains: [decisions]
produces:
  - { type: adr, slug: "token-format" }
  - { type: adr, ref: "session-storage" }
  - { type: spec, path: "auth/jwt-token-contract" }
---

## Summary
Test.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-validate.sh .work/produces-group/WD-01.md 2>&1 || true)"
if echo "$output" | grep -q "PASS" \
   && ! echo "$output" | grep -q "missing path"; then
    pass "produces: accepts slug: and ref: for ADR entries"
else
    fail "produces: with slug: / ref: must validate clean" "got: $output"
fi

rm -rf "$TEST_BASE/project/.work/produces-group"

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
