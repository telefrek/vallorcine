#!/usr/bin/env bash
# Scenario: curate-scan.sh work group analyses (15, 16, 17)
#
# Tests the work group health analyses in curate-scan.sh by running
# the full scan on prepared project structures with git history.
#
# Tests:
# 1. No .work/ → no work findings in summary
# 2. Displaced dep detected when WD depends on INVALIDATED spec
# 3. No false positive when spec is not invalidated
# 4. Stalled group detected (STALE_DAYS=0)
# 5. Non-stalled group not flagged (STALE_DAYS=9999)
# 6. Summary includes work sections when findings exist
#
# Run from repo root: bash tests/scenario-work-curate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-work-curate"

# ── Test helpers ────────────────────────────────────────────────────────��────

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
echo "scenario: work group curate analyses"
echo "────────────────────────────────────────────────"

# ── Helper: create a test project with git ───────────────────────────────────

create_project() {
    local proj="$1"
    rm -rf "$proj"
    mkdir -p "$proj"
    (
        cd "$proj"
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        mkdir -p .claude/scripts .curate src
        cp "$REPO_ROOT/scripts/curate-scan.sh" .claude/scripts/
        cp "$REPO_ROOT/scripts/spec-lib.sh" .claude/scripts/
        echo "class Main {}" > src/Main.java
        git add -A
        git commit -q -m "initial"
    )
}

run_scan() {
    local proj="$1"
    shift
    (cd "$proj" && bash .claude/scripts/curate-scan.sh --init "$@" 2>&1)
}

# ── Test 1: No .work/ → no work findings ─────────────────────────────────────

echo ""
echo "── Test 1: No .work/ produces no work findings"

PROJ1="$TEST_BASE/proj1"
create_project "$PROJ1"
run_scan "$PROJ1" >/dev/null 2>&1

if [[ -f "$PROJ1/.curate/scan-summary.md" ]] && ! grep -q "Work Group:" "$PROJ1/.curate/scan-summary.md" 2>/dev/null; then
    pass "no .work/ produces no work findings"
else
    fail "should have no work findings without .work/"
fi

# ── Test 2: Displaced dep detected ───────────────────────────────────────────

echo ""
echo "── Test 2: Displaced dep detected when WD depends on INVALIDATED spec"

PROJ2="$TEST_BASE/proj2"
create_project "$PROJ2"
(
    cd "$PROJ2"
    mkdir -p .spec/registry .spec/domains/auth .work/grp

    cat > .spec/registry/manifest.json << 'EOF'
{"domains":{"auth":{"description":"auth","feature_count":1}},"features":{"F01":{"latest_file":"domains/auth/F01-jwt.md","state":"INVALIDATED","domains":["auth"]}}}
EOF

    cat > .spec/domains/auth/F01-jwt.md << 'EOF'
---
{"id":"F01","version":1,"status":"DEPRECATED","state":"INVALIDATED","domains":["auth"],"requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[],"open_obligations":[]}
---
# F01
## Requirements
R1. Token format.
---
## DN
Done.
EOF

    cat > .work/grp/work.md << 'EOF'
---
group: grp
goal: test
status: active
created: 2026-04-01
---
## Goal
Test.
EOF

    cat > .work/grp/WD-01.md << 'EOF'
---
id: WD-01
title: Auth work
group: grp
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth/jwt", required_state: APPROVED }
---
## Summary
Auth work.
## Acceptance Criteria
Test.
EOF

    git add -A
    git commit -q -m "add work + invalidated spec"
)

run_scan "$PROJ2" >/dev/null 2>&1

if grep -q "Displaced Dependencies" "$PROJ2/.curate/scan-summary.md" 2>/dev/null; then
    pass "displaced dependency detected in summary"
else
    fail "should detect displaced dependency" "$(grep -A3 'Work' "$PROJ2/.curate/scan-summary.md" 2>/dev/null || echo 'no work section')"
fi

# ── Test 3: No false positive when spec is APPROVED ──────────────────────────

echo ""
echo "── Test 3: No false positive when spec is not invalidated"

PROJ3="$TEST_BASE/proj3"
create_project "$PROJ3"
(
    cd "$PROJ3"
    mkdir -p .spec/registry .spec/domains/auth .work/grp

    cat > .spec/registry/manifest.json << 'EOF'
{"domains":{"auth":{"description":"auth","feature_count":1}},"features":{"F01":{"latest_file":"domains/auth/F01-jwt.md","state":"APPROVED","domains":["auth"]}}}
EOF

    cat > .spec/domains/auth/F01-jwt.md << 'EOF'
---
{"id":"F01","version":1,"status":"ACTIVE","state":"APPROVED","domains":["auth"],"requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[],"open_obligations":[]}
---
# F01
## Requirements
R1. Token format.
---
## DN
Done.
EOF

    cat > .work/grp/work.md << 'EOF'
---
group: grp
goal: test
status: active
created: 2026-04-01
---
## Goal
Test.
EOF

    cat > .work/grp/WD-01.md << 'EOF'
---
id: WD-01
title: Auth work
group: grp
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: spec, path: "auth/jwt", required_state: APPROVED }
---
## Summary
Auth work.
## Acceptance Criteria
Test.
EOF

    git add -A
    git commit -q -m "add work + approved spec"
)

run_scan "$PROJ3" >/dev/null 2>&1

if ! grep -q "Displaced Dependencies" "$PROJ3/.curate/scan-summary.md" 2>/dev/null; then
    pass "no displacement when spec is APPROVED"
else
    fail "should not flag displacement for APPROVED spec"
fi

# ── Test 4: Stalled group detected (STALE_DAYS=0) ────────────────────────────

echo ""
echo "── Test 4: Stalled group detected with STALE_DAYS=0"

# Use PROJ2 which already has a work group
(cd "$PROJ2" && WORK_STALE_DAYS=0 bash .claude/scripts/curate-scan.sh --init 2>&1) >/dev/null

if grep -q "Work Group: Stalled" "$PROJ2/.curate/scan-summary.md" 2>/dev/null; then
    pass "stalled group detected with STALE_DAYS=0"
else
    fail "should detect stalled group" "$(grep -A3 'Stalled' "$PROJ2/.curate/scan-summary.md" 2>/dev/null || echo 'no stalled section')"
fi

# ── Test 5: Non-stalled group not flagged (STALE_DAYS=9999) ──────────────────

echo ""
echo "── Test 5: Non-stalled group not flagged with high threshold"

(cd "$PROJ2" && WORK_STALE_DAYS=9999 bash .claude/scripts/curate-scan.sh --init 2>&1) >/dev/null

if ! grep -q "Work Group: Stalled" "$PROJ2/.curate/scan-summary.md" 2>/dev/null; then
    pass "non-stalled group not flagged with high threshold"
else
    fail "should not flag with STALE_DAYS=9999"
fi

# ── Test 6: Summary includes work sections ───────────────────────────────────

echo ""
echo "── Test 6: Summary includes work sections when findings exist"

# PROJ2 should have displacement findings
(cd "$PROJ2" && WORK_STALE_DAYS=0 bash .claude/scripts/curate-scan.sh --init 2>&1) >/dev/null

work_sections=$(grep -c "Work Group:" "$PROJ2/.curate/scan-summary.md" 2>/dev/null || true)
if (( work_sections >= 1 )); then
    pass "summary includes $work_sections work group section(s)"
else
    fail "should include at least one work group section"
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
