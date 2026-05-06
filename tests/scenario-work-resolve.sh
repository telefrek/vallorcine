#!/usr/bin/env bash
# Scenario: work-resolve.sh correctly computes readiness for work definitions
#
# Tests:
# 1. WD with no deps is READY
# 2. WD with unsatisfied spec dep is BLOCKED
# 3. WD with satisfied spec dep is READY
# 4. WD with unsatisfied ADR dep is BLOCKED
# 5. WD with satisfied ADR dep is READY
# 6. WD with status COMPLETE is reported as COMPLETE
# 7. WD with status IN_PROGRESS is reported as IN_PROGRESS
# 8. Scope signal shown for high-dep-count WDs
# 9. Dependency graph shows which WDs unblock others
# 10. Curate mode emits extra data tables
# 11-16. wd-type deps (basic + chained)
# 17-21. monotonic state-rank match for wd deps (regression for strict-equality bug)
#
# Run from repo root: bash tests/scenario-work-resolve.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-work-resolve"

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
echo "scenario: work-resolve readiness computation"
echo "────────────────────────────────────────────────"

# ── Setup: create project structure ──────────────────────────────────────────

cleanup
mkdir -p "$TEST_BASE/project/.work/auth-migration"
mkdir -p "$TEST_BASE/project/.claude/scripts"
mkdir -p "$TEST_BASE/project/.spec/registry"
mkdir -p "$TEST_BASE/project/.spec/domains/auth"
mkdir -p "$TEST_BASE/project/.decisions/token-format"
mkdir -p "$TEST_BASE/project/.kb/auth/jwt"

# Copy scripts
cp "$REPO_ROOT/scripts/work-resolve.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-lib.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$TEST_BASE/project/.claude/scripts/"

cd "$TEST_BASE/project"

# ── Test 1: WD with no deps is READY ────────────────────────────────────────

echo ""
echo "── Test 1: WD with no deps is READY"

cat > .work/auth-migration/WD-01.md << 'EOF'
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
Add JWT token creation and validation.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-resolve.sh auth-migration 2>&1)"
if echo "$output" | grep -q "WD-01" && echo "$output" | grep -q "READY"; then
    pass "WD with no deps is READY"
else
    fail "WD with no deps should be READY" "got: $output"
fi

# ── Test 2: WD with unsatisfied spec dep is BLOCKED ─────────────────────────

echo ""
echo "── Test 2: WD with unsatisfied spec dep is BLOCKED"

cat > .work/auth-migration/WD-02.md << 'EOF'
---
id: WD-02
title: Auth middleware rewrite
group: auth-migration
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth/jwt-token-contract", required_state: APPROVED }
---

## Summary
Replace session validation with JWT.

## Acceptance Criteria
Test.
EOF

# No spec exists yet — should be BLOCKED
output="$(bash .claude/scripts/work-resolve.sh auth-migration 2>&1)"
if echo "$output" | grep "WD-02" | grep -q "BLOCKED"; then
    pass "WD with unsatisfied spec dep is BLOCKED"
else
    fail "WD with unsatisfied spec dep should be BLOCKED" "got: $output"
fi

# ── Test 3: WD with satisfied spec dep is READY ─────────────────────────────

echo ""
echo "── Test 3: WD with satisfied spec dep is READY"

# Create the spec that WD-02 depends on
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
R1. The system must create valid JWT tokens with configurable claims.

---

## Design Narrative
Core token format.
EOF

cat > .spec/registry/manifest.json << 'EOF'
{
  "domains": {
    "auth": { "description": "authentication and authorization", "feature_count": 1 }
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

output="$(bash .claude/scripts/work-resolve.sh auth-migration 2>&1)"
if echo "$output" | grep "WD-02" | grep -q "READY"; then
    pass "WD with satisfied spec dep is READY"
else
    fail "WD with satisfied spec dep should be READY" "got: $output"
fi

# ── Test 4: WD with unsatisfied ADR dep is BLOCKED ──────────────────────────

echo ""
echo "── Test 4: WD with unsatisfied ADR dep is BLOCKED"

cat > .work/auth-migration/WD-03.md << 'EOF'
---
id: WD-03
title: Token format decision
group: auth-migration
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: adr, slug: "token-format", required_status: accepted }
---

## Summary
Needs the token format ADR to be accepted.

## Acceptance Criteria
Test.
EOF

# ADR directory exists but no adr.md — should be BLOCKED
output="$(bash .claude/scripts/work-resolve.sh auth-migration 2>&1)"
if echo "$output" | grep "WD-03" | grep -q "BLOCKED"; then
    pass "WD with missing ADR is BLOCKED"
else
    fail "WD with missing ADR should be BLOCKED" "got: $output"
fi

# ── Test 5: WD with satisfied ADR dep is READY ──────────────────────────────

echo ""
echo "── Test 5: WD with satisfied ADR dep is READY"

cat > .decisions/token-format/adr.md << 'EOF'
---
problem: token-format
date: 2026-04-11
version: 1
status: accepted
---

# Token Format

## Problem
Which token format to use.

## Decision
Use JWT with RS256.
EOF

output="$(bash .claude/scripts/work-resolve.sh auth-migration 2>&1)"
if echo "$output" | grep "WD-03" | grep -q "READY"; then
    pass "WD with satisfied ADR dep is READY"
else
    fail "WD with satisfied ADR dep should be READY" "got: $output"
fi

# ── Test 6: WD with status COMPLETE is reported as COMPLETE ──────────────────

echo ""
echo "── Test 6: COMPLETE status is respected"

cat > .work/auth-migration/WD-04.md << 'EOF'
---
id: WD-04
title: Already done
group: auth-migration
status: COMPLETE
domains: [auth]
---

## Summary
This was already completed.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-resolve.sh auth-migration 2>&1)"
if echo "$output" | grep "WD-04" | grep -q "COMPLETE"; then
    pass "COMPLETE status is respected"
else
    fail "COMPLETE status should be reported as-is" "got: $output"
fi

# ── Test 7: WD with status IN_PROGRESS is reported ──────────────────────────

echo ""
echo "── Test 7: IN_PROGRESS status is respected"

cat > .work/auth-migration/WD-05.md << 'EOF'
---
id: WD-05
title: In progress work
group: auth-migration
status: IN_PROGRESS
domains: [auth]
---

## Summary
Currently being implemented.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-resolve.sh auth-migration 2>&1)"
if echo "$output" | grep "WD-05" | grep -q "IMPLEMENTING"; then
    pass "IN_PROGRESS status is normalized to IMPLEMENTING"
else
    fail "IN_PROGRESS should be normalized to IMPLEMENTING" "got: $output"
fi

# ── Test 8: Scope signal for high-dep-count WDs ─────────────────────────────

echo ""
echo "── Test 8: Scope signal for high-dep-count WDs"

cat > .work/auth-migration/WD-06.md << 'EOF'
---
id: WD-06
title: Many dependencies
group: auth-migration
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth/a", required_state: APPROVED }
  - { type: spec, path: "auth/b", required_state: APPROVED }
  - { type: spec, path: "auth/c", required_state: APPROVED }
  - { type: adr, slug: "d", required_status: accepted }
  - { type: adr, slug: "e", required_status: accepted }
  - { type: kb, path: "auth/jwt/f" }
---

## Summary
Has more than 5 deps.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-resolve.sh auth-migration 2>&1)"
if echo "$output" | grep -q "Scope Signal" && echo "$output" | grep -q "WD-06"; then
    pass "scope signal shown for high-dep-count WD"
else
    fail "scope signal should appear for >5 deps" "got: $output"
fi

# ── Test 9: Dependency graph shows unblocking ────────────────────────────────

echo ""
echo "── Test 9: Dependency graph shows which WDs unblock others"

# WD-01 produces auth/jwt-token-contract, WD-02 depends on it
# The unblocks column for WD-01 should mention WD-02
output="$(bash .claude/scripts/work-resolve.sh auth-migration 2>&1)"
if echo "$output" | grep "WD-01" | grep -q "WD-02"; then
    pass "dependency graph shows WD-01 unblocks WD-02"
else
    fail "WD-01 should show it unblocks WD-02" "got: $output"
fi

# ── Test 10: Curate mode emits extra data ────────────────────────────────────

echo ""
echo "── Test 10: Curate mode emits artifact dependency tables"

output="$(bash .claude/scripts/work-resolve.sh auth-migration --curate 2>&1)"
if echo "$output" | grep -q "Curate Data" && echo "$output" | grep -q "All Artifact Dependencies"; then
    pass "curate mode emits extra data tables"
else
    fail "curate mode should emit correlation data" "got: $output"
fi

# ── Test 11: SPECIFIED WD with unmet wd dep is BLOCKED ──────────────────────

echo ""
echo "── Test 11: SPECIFIED WD with unmet wd dep is BLOCKED"

# Create a fresh group for wd-dep tests
mkdir -p "$TEST_BASE/project/.work/wd-dep-test"

cat > .work/wd-dep-test/WD-01.md << 'EOF'
---
id: WD-01
title: Foundation work
group: wd-dep-test
status: SPECIFIED
domains: [auth]
artifact_deps: []
produces: []
---

## Summary
Foundation that must complete first.

## Acceptance Criteria
Test.
EOF

cat > .work/wd-dep-test/WD-02.md << 'EOF'
---
id: WD-02
title: Dependent work
group: wd-dep-test
status: SPECIFIED
domains: [auth]
artifact_deps:
  - { type: wd, ref: "WD-01", required_state: COMPLETE }
produces: []
---

## Summary
Depends on WD-01 completing.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-resolve.sh wd-dep-test 2>&1)"
if echo "$output" | grep "WD-02" | grep -q "BLOCKED"; then
    pass "SPECIFIED WD with unmet wd dep is BLOCKED"
else
    fail "SPECIFIED WD with unmet wd dep should be BLOCKED" "got: $output"
fi

# ── Test 12: SPECIFIED WD with met wd dep stays SPECIFIED ───────────────────

echo ""
echo "── Test 12: SPECIFIED WD with met wd dep stays SPECIFIED"

# Mark WD-01 as COMPLETE
sed -i 's/status: SPECIFIED/status: COMPLETE/' .work/wd-dep-test/WD-01.md

output="$(bash .claude/scripts/work-resolve.sh wd-dep-test 2>&1)"
if echo "$output" | grep "WD-02" | grep -q "SPECIFIED"; then
    pass "SPECIFIED WD with met wd dep stays SPECIFIED"
else
    fail "SPECIFIED WD with met wd dep should stay SPECIFIED" "got: $output"
fi

# ── Test 13: wd dep creates unblocks edge in graph ──────────────────────────

echo ""
echo "── Test 13: wd dep creates unblocks edge in graph"

# Reset WD-01 to SPECIFIED so WD-02 is blocked again
sed -i 's/status: COMPLETE/status: SPECIFIED/' .work/wd-dep-test/WD-01.md

output="$(bash .claude/scripts/work-resolve.sh wd-dep-test 2>&1)"
if echo "$output" | grep "WD-01" | grep -q "WD-02"; then
    pass "wd dep creates unblocks edge (WD-01 unblocks WD-02)"
else
    fail "WD-01 should show it unblocks WD-02" "got: $output"
fi

# ── Test 14: DRAFT WD with unmet wd dep is BLOCKED ─────────────────────────

echo ""
echo "── Test 14: DRAFT WD with unmet wd dep is BLOCKED"

cat > .work/wd-dep-test/WD-03.md << 'EOF'
---
id: WD-03
title: Draft with wd dep
group: wd-dep-test
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: wd, ref: "WD-01", required_state: COMPLETE }
produces: []
---

## Summary
DRAFT that depends on WD-01.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-resolve.sh wd-dep-test 2>&1)"
if echo "$output" | grep "WD-03" | grep -q "BLOCKED"; then
    pass "DRAFT WD with unmet wd dep is BLOCKED"
else
    fail "DRAFT WD with unmet wd dep should be BLOCKED" "got: $output"
fi

# ── Test 15: Blocker detail shows wd dep reason ────────────────────────────

echo ""
echo "── Test 15: Blocker detail shows wd dep reason"

output="$(bash .claude/scripts/work-resolve.sh wd-dep-test 2>&1)"
if echo "$output" | grep -q "wd:WD-01 — need COMPLETE"; then
    pass "blocker detail shows wd dep reason"
else
    fail "blocker should mention wd:WD-01 and required state" "got: $output"
fi

# ── Test 16: Chained wd deps compute transitively ──────────────────────────

echo ""
echo "── Test 16: Chained wd deps block transitively"

cat > .work/wd-dep-test/WD-04.md << 'EOF'
---
id: WD-04
title: End of chain
group: wd-dep-test
status: SPECIFIED
domains: [auth]
artifact_deps:
  - { type: wd, ref: "WD-02", required_state: COMPLETE }
produces: []
---

## Summary
Depends on WD-02 which depends on WD-01.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-resolve.sh wd-dep-test 2>&1)"
if echo "$output" | grep "WD-04" | grep -q "BLOCKED"; then
    pass "chained wd deps block transitively"
else
    fail "WD-04 should be BLOCKED (WD-02 is BLOCKED)" "got: $output"
fi

# ── Cleanup wd-dep-test group ───────────────────────────────────────────────
rm -rf .work/wd-dep-test

# ── Tests 17-21: monotonic state-rank match for wd deps ─────────────────────
#
# Regression for strict-equality bug surfaced from jlsm: a dep declared as
# `required_state: SPECIFIED` was reported BLOCKED when the predecessor had
# advanced to COMPLETE (a higher-ranked state on the lifecycle). The dep
# should be satisfied by any state at-or-past the required rank.
#
# Lifecycle: DRAFT (0) → SPECIFYING (1) → SPECIFIED (2) → IMPLEMENTING (3)
# → COMPLETE (4). IN_PROGRESS is a legacy alias for IMPLEMENTING.

mkdir -p "$TEST_BASE/project/.work/state-rank-test"

# Predecessor we'll mutate across tests
cat > .work/state-rank-test/WD-01.md << 'EOF'
---
id: WD-01
title: Predecessor
group: state-rank-test
status: COMPLETE
domains: [auth]
artifact_deps: []
produces: []
---

## Summary
Predecessor whose state will vary across the test cases below.

## Acceptance Criteria
Test.
EOF

# Dependent declares need-SPECIFIED — the bug case
cat > .work/state-rank-test/WD-02.md << 'EOF'
---
id: WD-02
title: Needs WD-01 SPECIFIED
group: state-rank-test
status: SPECIFIED
domains: [auth]
artifact_deps:
  - { type: wd, ref: "WD-01", required_state: SPECIFIED }
produces: []
---

## Summary
This WD only needs WD-01 to have reached SPECIFIED — any state past
SPECIFIED (IMPLEMENTING, COMPLETE) should also satisfy.

## Acceptance Criteria
Test.
EOF

# ── Test 17: COMPLETE predecessor satisfies need-SPECIFIED (SPECIFIED branch)

echo ""
echo "── Test 17: COMPLETE predecessor satisfies need-SPECIFIED dep (SPECIFIED branch)"

output="$(bash .claude/scripts/work-resolve.sh state-rank-test 2>&1)"
if echo "$output" | grep "WD-02" | grep -q "SPECIFIED" && \
   ! echo "$output" | grep "WD-02" | grep -q "BLOCKED"; then
    pass "COMPLETE predecessor satisfies need-SPECIFIED on a SPECIFIED dependent"
else
    fail "WD-02 should be SPECIFIED (WD-01 COMPLETE >= SPECIFIED)" "got: $output"
fi

# ── Test 18: IMPLEMENTING predecessor satisfies need-SPECIFIED ──────────────

echo ""
echo "── Test 18: IMPLEMENTING predecessor satisfies need-SPECIFIED dep"

sed -i 's/^status: COMPLETE$/status: IMPLEMENTING/' .work/state-rank-test/WD-01.md

output="$(bash .claude/scripts/work-resolve.sh state-rank-test 2>&1)"
if echo "$output" | grep "WD-02" | grep -q "SPECIFIED" && \
   ! echo "$output" | grep "WD-02" | grep -q "BLOCKED"; then
    pass "IMPLEMENTING predecessor satisfies need-SPECIFIED"
else
    fail "WD-02 should be SPECIFIED (WD-01 IMPLEMENTING >= SPECIFIED)" "got: $output"
fi

# ── Test 19: SPECIFYING predecessor does NOT satisfy need-SPECIFIED ─────────

echo ""
echo "── Test 19: SPECIFYING predecessor does NOT satisfy need-SPECIFIED dep"

sed -i 's/^status: IMPLEMENTING$/status: SPECIFYING/' .work/state-rank-test/WD-01.md

output="$(bash .claude/scripts/work-resolve.sh state-rank-test 2>&1)"
if echo "$output" | grep "WD-02" | grep -q "BLOCKED"; then
    pass "SPECIFYING predecessor does not satisfy need-SPECIFIED (below required rank)"
else
    fail "WD-02 should be BLOCKED (WD-01 SPECIFYING < SPECIFIED)" "got: $output"
fi

# ── Test 20: COMPLETE predecessor satisfies need-SPECIFIED (DRAFT branch) ───

echo ""
echo "── Test 20: COMPLETE predecessor satisfies need-SPECIFIED dep (DRAFT branch)"

sed -i 's/^status: SPECIFYING$/status: COMPLETE/' .work/state-rank-test/WD-01.md

# DRAFT dependent that needs WD-01 SPECIFIED
cat > .work/state-rank-test/WD-03.md << 'EOF'
---
id: WD-03
title: Draft needs WD-01 SPECIFIED
group: state-rank-test
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: wd, ref: "WD-01", required_state: SPECIFIED }
produces: []
---

## Summary
DRAFT WD that wants WD-01 SPECIFIED to plan against.

## Acceptance Criteria
Test.
EOF

output="$(bash .claude/scripts/work-resolve.sh state-rank-test 2>&1)"
if echo "$output" | grep "WD-03" | grep -q "READY" && \
   ! echo "$output" | grep "WD-03" | grep -q "BLOCKED"; then
    pass "DRAFT WD with COMPLETE predecessor is READY (need-SPECIFIED satisfied)"
else
    fail "WD-03 should be READY (WD-01 COMPLETE >= SPECIFIED)" "got: $output"
fi

# ── Test 21: IN_PROGRESS legacy alias satisfies need-SPECIFIED ──────────────

echo ""
echo "── Test 21: IN_PROGRESS legacy alias satisfies need-SPECIFIED"

sed -i 's/^status: COMPLETE$/status: IN_PROGRESS/' .work/state-rank-test/WD-01.md

output="$(bash .claude/scripts/work-resolve.sh state-rank-test 2>&1)"
if echo "$output" | grep "WD-02" | grep -q "SPECIFIED" && \
   ! echo "$output" | grep "WD-02" | grep -q "BLOCKED"; then
    pass "IN_PROGRESS (legacy IMPLEMENTING alias) satisfies need-SPECIFIED"
else
    fail "WD-02 should be SPECIFIED (WD-01 IN_PROGRESS == IMPLEMENTING >= SPECIFIED)" "got: $output"
fi

# ── Cleanup state-rank-test group ───────────────────────────────────────────
rm -rf .work/state-rank-test

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
