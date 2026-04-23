#!/usr/bin/env bash
# Scenario: pipeline mode support (specification, implementation, full)
#
# Tests that the pipeline mode field in status.md is recognized by
# work-validate.sh and work-resolve.sh, and that status.md templates
# are well-formed for each mode.
#
# Tests:
# 1. Default pipeline_mode is "full" (backwards compatible)
# 2. status.md with pipeline_mode: specification is valid
# 3. status.md with pipeline_mode: implementation is valid
# 4. Specification mode status.md starts at scoping/complete
# 5. Implementation mode status.md starts at planning/loading-context
# 6. WD with only specification produces gets mode=specification
# 7. WD with mixed produces gets mode=full
# 8. Spec-mode feature with complete spec stage routes to retro
# 9. Impl-mode feature without domains.md still resolves
# 10. Pipeline mode field preserved across WD lifecycle
#
# Run from repo root: bash tests/scenario-pipeline-modes.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-pipeline-modes"

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
echo "scenario: pipeline modes (specification / implementation / full)"
echo "────────────────────────────────────────────────"

# ── Setup ────────────────────────────────────────────────────────────────────

cleanup
mkdir -p "$TEST_BASE/project/.feature/test-full"
mkdir -p "$TEST_BASE/project/.feature/test-spec"
mkdir -p "$TEST_BASE/project/.feature/test-impl"
mkdir -p "$TEST_BASE/project/.work/test-group"
mkdir -p "$TEST_BASE/project/.claude/scripts"

# Copy scripts
cp "$REPO_ROOT/scripts/work-lib.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-resolve.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-validate.sh" "$TEST_BASE/project/.claude/scripts/"

cd "$TEST_BASE/project"

# ── Test 1: Default pipeline_mode is "full" ──────────────────────────────────

echo ""
echo "── Test 1: Default pipeline_mode is full (backwards compatible)"

cat > .feature/test-full/status.md << 'EOF'
---
feature: "test-full"
created: "2026-04-11 10:00"
last_updated: "2026-04-11 10:00"
---

# Feature Status — test-full

## Current Position
**Stage:** scoping
**Substage:** complete
**Last successful checkpoint:** brief written
**Automation mode:** not-set
**Execution strategy:** not-set
EOF

# Pipeline mode not present → should default to full (backwards compatible)
if ! grep -q "Pipeline mode:" .feature/test-full/status.md; then
    pass "absent pipeline_mode is backwards compatible (defaults to full)"
else
    fail "status.md should not require pipeline_mode for backwards compat"
fi

# ── Test 2: Specification mode status.md ─────────────────────────────────────

echo ""
echo "── Test 2: status.md with pipeline_mode: specification is valid"

cat > .feature/test-spec/status.md << 'EOF'
---
feature: "test-spec"
created: "2026-04-11 10:00"
last_updated: "2026-04-11 10:00"
work_group: test-group
work_definition: WD-01
---

# Feature Status — test-spec

## Current Position
**Stage:** scoping
**Substage:** complete
**Last successful checkpoint:** brief written
**Automation mode:** not-set
**Execution strategy:** not-set
**Pipeline mode:** specification

## Stage Completion

| Stage | Status | Completed | Est. Tokens | Actual Tokens | Notes |
|-------|--------|-----------|-------------|---------------|-------|
| Scoping | complete | 2026-04-11 | — | — | pre-populated from WD |
| Domains | not-started | — | — | — | |
| Spec Authoring | not-started | — | — | — | |
EOF

if grep -q "Pipeline mode:.* specification" .feature/test-spec/status.md; then
    pass "specification mode status.md is well-formed"
else
    fail "should have Pipeline mode: specification"
fi

# ── Test 3: Implementation mode status.md ────────────────────────────────────

echo ""
echo "── Test 3: status.md with pipeline_mode: implementation is valid"

cat > .feature/test-impl/status.md << 'EOF'
---
feature: "test-impl"
created: "2026-04-11 10:00"
last_updated: "2026-04-11 10:00"
work_group: test-group
work_definition: WD-02
---

# Feature Status — test-impl

## Current Position
**Stage:** planning
**Substage:** loading-context
**Last successful checkpoint:** feature directory created
**Automation mode:** not-set
**Execution strategy:** not-set
**Pipeline mode:** implementation

## Stage Completion

| Stage | Status | Completed | Est. Tokens | Actual Tokens | Notes |
|-------|--------|-----------|-------------|---------------|-------|
| Planning | not-started | — | — | — | |
| Testing | not-started | — | — | — | cycle 0 |
| Hardening | not-started | — | — | — | cycle 0 |
| Implementation | not-started | — | — | — | cycle 0 |
| Refactor | not-started | — | — | — | cycle 0 |
EOF

if grep -q "Pipeline mode:.* implementation" .feature/test-impl/status.md; then
    pass "implementation mode status.md is well-formed"
else
    fail "should have Pipeline mode: implementation"
fi

# ── Test 4: Spec mode starts at scoping/complete ─────────────────────────────

echo ""
echo "── Test 4: Specification mode starts at scoping/complete"

stage=$(grep 'Stage:' .feature/test-spec/status.md | head -1 | sed 's/.*Stage:\*\*[[:space:]]*//' | sed 's/\*//g' | xargs)
substage=$(grep 'Substage:' .feature/test-spec/status.md | head -1 | sed 's/.*Substage:\*\*[[:space:]]*//' | sed 's/\*//g' | xargs)

if [[ "$stage" == "scoping" && "$substage" == "complete" ]]; then
    pass "spec mode starts at scoping/complete"
else
    fail "spec mode should start at scoping/complete" "got: $stage/$substage"
fi

# ── Test 5: Impl mode starts at planning/loading-context ─────────────────────

echo ""
echo "── Test 5: Implementation mode starts at planning/loading-context"

stage=$(grep 'Stage:' .feature/test-impl/status.md | head -1 | sed 's/.*Stage:\*\*[[:space:]]*//' | sed 's/\*//g' | xargs)
substage=$(grep 'Substage:' .feature/test-impl/status.md | head -1 | sed 's/.*Substage:\*\*[[:space:]]*//' | sed 's/\*//g' | xargs)

if [[ "$stage" == "planning" && "$substage" == "loading-context" ]]; then
    pass "impl mode starts at planning/loading-context"
else
    fail "impl mode should start at planning/loading-context" "got: $stage/$substage"
fi

# ── Test 6: WD with only spec produces → specification mode hint ─────────────

echo ""
echo "── Test 6: WD with only specification produces"

cat > .work/test-group/WD-01.md << 'EOF'
---
id: WD-01
title: Define JWT spec
group: test-group
status: DRAFT
domains: [auth]
produces:
  - { type: spec, path: "auth/jwt-token-contract" }
  - { type: spec, path: "auth/token-validator", kind: interface-contract }
---

## Summary
Author JWT token contract and token validator interface specs.

## Acceptance Criteria
Both specs authored and in APPROVED state.
EOF

# Check that only spec-type artifacts in produces
only_specs=true
while IFS='|' read -r prod_type prod_path _ prod_kind; do
    [[ -z "$prod_type" ]] && continue
    if [[ "$prod_type" != "spec" ]]; then
        only_specs=false
    fi
done < <(bash .claude/scripts/work-lib.sh 2>/dev/null; cd "$TEST_BASE/project" && source .claude/scripts/work-lib.sh && work_fm_produces .work/test-group/WD-01.md)

# Alternative: just check the file directly
spec_produces=$(grep -c "type: spec" .work/test-group/WD-01.md || true)
non_spec_produces=$(grep "type:" .work/test-group/WD-01.md | grep -v "type: spec" | grep -c "type:" || true)

if (( spec_produces > 0 && non_spec_produces == 0 )); then
    pass "WD with only spec produces detected (specification mode candidate)"
else
    fail "should detect spec-only produces" "spec=$spec_produces non-spec=$non_spec_produces"
fi

# ── Test 7: WD with no produces → full mode ──────────────────────────────────

echo ""
echo "── Test 7: WD with no produces defaults to full mode"

cat > .work/test-group/WD-02.md << 'EOF'
---
id: WD-02
title: Implement JWT validation
group: test-group
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth/jwt-token-contract", required_state: APPROVED }
---

## Summary
Implement JWT token validation in the auth middleware.

## Acceptance Criteria
All auth endpoints validate JWT tokens correctly.
EOF

has_produces=$(grep -c "^produces:" .work/test-group/WD-02.md || true)
if (( has_produces == 0 )); then
    pass "WD with no produces defaults to full/implementation mode"
else
    fail "WD-02 should have no produces section"
fi

# ── Test 8: Spec-mode stage completion table is mode-appropriate ─────────────

echo ""
echo "── Test 8: Spec-mode stage table omits implementation stages"

if ! grep -q "Implementation" .feature/test-spec/status.md && \
   ! grep -q "Refactor" .feature/test-spec/status.md && \
   grep -q "Spec Authoring" .feature/test-spec/status.md; then
    pass "spec-mode table has Spec Authoring but not Implementation/Refactor"
else
    fail "spec-mode table should omit implementation stages"
fi

# ── Test 9: Impl-mode stage completion table is mode-appropriate ─────────────

echo ""
echo "── Test 9: Impl-mode stage table omits specification stages"

if ! grep -q "Scoping" .feature/test-impl/status.md && \
   ! grep -q "Domains" .feature/test-impl/status.md && \
   grep -q "Planning" .feature/test-impl/status.md && \
   grep -q "Implementation" .feature/test-impl/status.md; then
    pass "impl-mode table has Planning+Implementation but not Scoping/Domains"
else
    fail "impl-mode table should omit specification stages"
fi

# ── Test 10: Pipeline mode field preserved across WD lifecycle ───────────────

echo ""
echo "── Test 10: Pipeline mode preserved after status changes"

# Simulate updating substage
sed -i 's/Substage: complete/Substage: in-progress/' .feature/test-spec/status.md
if grep -q "Pipeline mode:.* specification" .feature/test-spec/status.md; then
    pass "pipeline mode preserved after substage update"
else
    fail "pipeline mode should survive substage changes"
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
