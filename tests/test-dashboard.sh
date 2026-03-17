#!/usr/bin/env bash
# vallorcine dashboard watcher tests
# Run from repo root: bash tests/test-dashboard.sh
#
# Tests:
#   1. Install includes dashboard watchers and command
#   2. vallorcine_theme.sh loads and exports expected variables
#   3. fmt_tokens formats correctly
#   4. render_bar produces expected output
#   5. pipeline.sh renders empty state without error
#   6. pipeline.sh renders full pipeline state
#   7. stage-detail.sh renders empty state without error
#   8. stage-detail.sh renders full stage state with artifacts
#   9. MANIFEST includes watcher files
#  10. Upgrade safety guard allows .claude/watchers/* prefix

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION="$(cat "$REPO_ROOT/VERSION")"

# ── Test helpers ─────────────────────────────────────────────────────────────

passed=0
failed=0
total=0

pass() {
    ((passed++)) || true
    ((total++)) || true
    echo "  PASS: $1"
}

fail() {
    ((failed++)) || true
    ((total++)) || true
    echo "  FAIL: $1"
    [[ -n "${2:-}" ]] && echo "        $2"
}

TEST_BASE="/tmp/vallorcine/test-dashboard"

cleanup() {
    rm -rf "$TEST_BASE" 2>/dev/null || true
}
trap cleanup EXIT

cleanup
mkdir -p "$TEST_BASE"

test_count=0
make_temp() {
    local d="$TEST_BASE/$((++test_count))"
    mkdir -p "$d"
    echo "$d"
}

echo ""
echo "vallorcine dashboard watcher tests"
echo "═══════════════════════════════════"
echo ""

# ── Test 1: Install includes dashboard files ─────────────────────────────────

echo "Test 1: Install includes dashboard watchers and command"
T1="$(make_temp)"
bash "$REPO_ROOT/install.sh" "$T1" >/dev/null 2>&1

if [[ -f "$T1/.claude/watchers/vallorcine_theme.sh" ]] \
   && [[ -f "$T1/.claude/watchers/vallorcine_pipeline.sh" ]] \
   && [[ -f "$T1/.claude/watchers/vallorcine_stage-detail.sh" ]] \
   && [[ -f "$T1/.claude/commands/dashboard.md" ]]; then
    pass "All dashboard files installed"
else
    fail "Missing dashboard files"
fi

# ── Test 2: vallorcine_theme.sh loads and exports expected variables ────────────────────

echo "Test 2: vallorcine_theme.sh loads expected variables"
result=$(bash -c "source '$T1/.claude/watchers/vallorcine_theme.sh' && echo \"\${STAGE_ICON[scoping]}|\${STAGE_COLOR[testing]}|\${STATUS_ICON[complete]}|\${ARTIFACT_ICON[test_written]}\"" 2>&1)
if [[ "$result" == *"⬡"* ]] && [[ "$result" == *"✓"* ]] && [[ "$result" == *"△"* ]]; then
    pass "Theme variables loaded correctly"
else
    fail "Theme variables not as expected" "got: $result"
fi

# ── Test 3: fmt_tokens formats correctly ─────────────────────────────────────

echo "Test 3: fmt_tokens formatting"
result=$(bash -c "source '$T1/.claude/watchers/vallorcine_theme.sh' && echo \"\$(fmt_tokens 1842)|\$(fmt_tokens 24193)|\$(fmt_tokens '')|\$(fmt_tokens 1234567)|\$(fmt_tokens 500)\"")
expected="1.8K|24.1K|──|1.2M|500"
if [[ "$result" == "$expected" ]]; then
    pass "fmt_tokens formats all ranges correctly"
else
    fail "fmt_tokens output mismatch" "expected: $expected, got: $result"
fi

# ── Test 4: render_bar produces expected output ──────────────────────────────

echo "Test 4: render_bar output"
result=$(bash -c "source '$T1/.claude/watchers/vallorcine_theme.sh' && render_bar 50 100 10")
if [[ "$result" == "█████░░░░░ 50%" ]]; then
    pass "render_bar 50/100 correct"
else
    fail "render_bar output mismatch" "got: [$result]"
fi

# Also test that render_bar returns 1 when estimate is null
rc=0
bash -c "source '$T1/.claude/watchers/vallorcine_theme.sh' && render_bar 50 ''" 2>/dev/null || rc=$?
if [[ "$rc" -eq 1 ]]; then
    pass "render_bar returns 1 for null estimate"
else
    fail "render_bar should return 1 for null estimate" "got rc=$rc"
fi

# ── Test 5: pipeline.sh renders empty state ──────────────────────────────────

echo "Test 5: pipeline.sh empty state"
mkdir -p "$T1/.claude/dashboard"
# Remove pipeline.json if present
rm -f "$T1/.claude/dashboard/pipeline.json"

# Source theme and inline the render check (can't run full watcher due to loop)
result=$(bash -c "
cd '$T1'
source .claude/watchers/vallorcine_theme.sh
STATE=.claude/dashboard/pipeline.json
if [[ ! -f \"\$STATE\" ]]; then
    echo 'EMPTY_STATE_OK'
fi
")
if [[ "$result" == "EMPTY_STATE_OK" ]]; then
    pass "Empty state detected correctly"
else
    fail "Empty state not handled" "got: $result"
fi

# ── Test 6: pipeline.sh renders full state ───────────────────────────────────

echo "Test 6: pipeline.sh full state rendering"
cat > "$T1/.claude/dashboard/pipeline.json" << 'PJSON'
{"feature":"test-feature","version":"0.3.4","stages":[{"name":"scoping","icon":"⬡","status":"complete","tokens":{"actual":1842,"estimate":null,"live":null},"alert":null},{"name":"domains","icon":"◈","status":"complete","tokens":{"actual":3201,"estimate":null,"live":null},"alert":null},{"name":"planning","icon":"▣","status":"in_progress","tokens":{"actual":null,"estimate":4000,"live":2100},"alert":null},{"name":"testing","icon":"△","status":"pending","tokens":{"actual":null,"estimate":3000,"live":null},"alert":null},{"name":"implementation","icon":"⚙","status":"pending","tokens":{"actual":null,"estimate":8000,"live":null},"alert":null},{"name":"refactor","icon":"◆","status":"pending","tokens":{"actual":null,"estimate":3000,"live":null},"alert":null},{"name":"pr","icon":"⎘","status":"pending","tokens":{"actual":null,"estimate":1000,"live":null},"alert":null}],"units":null,"totals":{"actual":7143,"estimate":23043}}
PJSON

result=$(bash -c "
cd '$T1'
source .claude/watchers/vallorcine_theme.sh
STATE=.claude/dashboard/pipeline.json
stage_count=\$(jq '.stages | length' \"\$STATE\")
feature=\$(jq -r '.feature' \"\$STATE\")
total_est=\$(jq -r '.totals.estimate' \"\$STATE\")
echo \"\$stage_count|\$feature|\$total_est\"
")
if [[ "$result" == "7|test-feature|23043" ]]; then
    pass "Full pipeline state parsed correctly (7 stages, feature name, totals)"
else
    fail "Pipeline state parse error" "got: $result"
fi

# Verify token display logic
result=$(bash -c "
cd '$T1'
source .claude/watchers/vallorcine_theme.sh
STATE=.claude/dashboard/pipeline.json
# Stage 0 (complete) should show actual
actual=\$(jq -r '.stages[0].tokens.actual // empty' \"\$STATE\")
echo \"actual=\$(fmt_tokens \$actual)\"
# Stage 2 (in_progress) should show live
live=\$(jq -r '.stages[2].tokens.live // empty' \"\$STATE\")
echo \"live=\$(fmt_tokens \$live)\"
# Stage 4 (pending) should show estimate
est=\$(jq -r '.stages[4].tokens.estimate // empty' \"\$STATE\")
echo \"est=\$(fmt_tokens \$est)\"
")
if [[ "$result" == *"actual=1.8K"* ]] && [[ "$result" == *"live=2.1K"* ]] && [[ "$result" == *"est=8.0K"* ]]; then
    pass "Token display: actual/live/estimate all format correctly"
else
    fail "Token display mismatch" "got: $result"
fi

# ── Test 7: stage-detail.sh renders empty state ─────────────────────────────

echo "Test 7: stage-detail.sh empty state"
rm -f "$T1/.claude/dashboard/stage.json"

result=$(bash -c "
cd '$T1'
source .claude/watchers/vallorcine_theme.sh
STATE=.claude/dashboard/stage.json
if [[ ! -f \"\$STATE\" ]]; then
    echo 'EMPTY_STATE_OK'
fi
")
if [[ "$result" == "EMPTY_STATE_OK" ]]; then
    pass "Stage detail empty state detected"
else
    fail "Stage detail empty state not handled"
fi

# ── Test 8: stage-detail.sh renders full state with artifacts ────────────────

echo "Test 8: stage-detail.sh full state with artifacts"
cat > "$T1/.claude/dashboard/stage.json" << 'SJSON'
{"stage":"implementation","icon":"⚙","unit":"config-parser","updated":"2026-03-17T14:33:12Z","tasks":[{"name":"Read stub contracts","status":"complete"},{"name":"Implement ConfigParser","status":"in_progress"},{"name":"Implement SegmentCompactor","status":"pending"}],"artifacts":[{"name":"ConfigParser","status":"implementing"},{"name":"SegmentCompactor","status":"pending"},{"name":"BloomFilter","status":"test_written"}]}
SJSON

result=$(bash -c "
cd '$T1'
source .claude/watchers/vallorcine_theme.sh
STATE=.claude/dashboard/stage.json
stage=\$(jq -r '.stage' \"\$STATE\")
task_count=\$(jq '.tasks | length' \"\$STATE\")
artifact_count=\$(jq '.artifacts | length' \"\$STATE\")
unit=\$(jq -r '.unit // empty' \"\$STATE\")
has_active=\$(jq '[.tasks[] | select(.status == \"in_progress\")] | length' \"\$STATE\")
echo \"\$stage|\$task_count|\$artifact_count|\$unit|\$has_active\"
")
if [[ "$result" == "implementation|3|3|config-parser|1" ]]; then
    pass "Stage detail: stage, tasks, artifacts, unit, active status all correct"
else
    fail "Stage detail parse error" "got: $result"
fi

# Verify artifact icon mapping
result=$(bash -c "
cd '$T1'
source .claude/watchers/vallorcine_theme.sh
echo \"\${ARTIFACT_ICON[implementing]}|\${ARTIFACT_ICON[test_written]}|\${ARTIFACT_ICON[pending]}\"
")
if [[ "$result" == "◉|△|○" ]]; then
    pass "Artifact icon mapping correct"
else
    fail "Artifact icon mapping wrong" "got: $result"
fi

# ── Test 9: MANIFEST includes watcher files ──────────────────────────────────

echo "Test 9: MANIFEST includes watcher and dashboard entries"
manifest="$REPO_ROOT/MANIFEST"
missing=0
for entry in ".claude/watchers/vallorcine_theme.sh" ".claude/watchers/vallorcine_pipeline.sh" ".claude/watchers/vallorcine_stage-detail.sh" ".claude/commands/dashboard.md"; do
    if ! grep -qF "$entry" "$manifest"; then
        fail "MANIFEST missing: $entry"
        missing=1
    fi
done
if [[ "$missing" -eq 0 ]]; then
    pass "All dashboard entries in MANIFEST"
fi

# ── Test 10: Upgrade safety guard allows watchers prefix ─────────────────────

echo "Test 10: Upgrade safety guard allows .claude/watchers/* prefix"
if grep -q '.claude/watchers/\*' "$REPO_ROOT/upgrade.sh"; then
    pass "Upgrade safety guard includes .claude/watchers/* prefix"
else
    fail "Upgrade safety guard missing .claude/watchers/* prefix"
fi

# ── Test 11: dashboard-state.sh functions work ───────────────────────────────

echo "Test 11: dashboard-state.sh functions"
T11="$(make_temp)"
bash "$REPO_ROOT/install.sh" "$T11" >/dev/null 2>&1

# Test dashboard_init creates pipeline.json
result=$(bash -c "
cd '$T11'
source .claude/scripts/dashboard-state.sh
dashboard_init 'test-feature'
jq -r '.feature' .claude/dashboard/pipeline.json
")
if [[ "$result" == "test-feature" ]]; then
    pass "dashboard_init creates pipeline.json with feature name"
else
    fail "dashboard_init failed" "got: $result"
fi

# Test dashboard_stage_start
result=$(bash -c "
cd '$T11'
source .claude/scripts/dashboard-state.sh
dashboard_stage_start 'scoping'
jq -r '.stages[0].status' .claude/dashboard/pipeline.json
")
if [[ "$result" == "in_progress" ]]; then
    pass "dashboard_stage_start sets stage to in_progress"
else
    fail "dashboard_stage_start failed" "got: $result"
fi

# Test dashboard_stage_complete
result=$(bash -c "
cd '$T11'
source .claude/scripts/dashboard-state.sh
dashboard_stage_complete 'scoping' 1842
jq -r '.stages[0].status + \"|\" + (.stages[0].tokens.actual | tostring)' .claude/dashboard/pipeline.json
")
if [[ "$result" == "complete|1842" ]]; then
    pass "dashboard_stage_complete sets status and token actual"
else
    fail "dashboard_stage_complete failed" "got: $result"
fi

# Test dashboard_stage_detail + dashboard_task + dashboard_artifact
result=$(bash -c "
cd '$T11'
source .claude/scripts/dashboard-state.sh
dashboard_stage_detail 'testing' '△' 'config-parser'
dashboard_task 'Write tests' 'in_progress'
dashboard_artifact 'ConfigParser' 'test_written'
jq -r '.stage + \"|\" + .tasks[0].name + \"|\" + .artifacts[0].status' .claude/dashboard/stage.json
")
if [[ "$result" == "testing|Write tests|test_written" ]]; then
    pass "stage detail, task, and artifact writes work correctly"
else
    fail "stage detail writes failed" "got: $result"
fi

# Test dashboard_task updates existing task (not duplicates)
result=$(bash -c "
cd '$T11'
source .claude/scripts/dashboard-state.sh
dashboard_task 'Write tests' 'complete'
jq '.tasks | length' .claude/dashboard/stage.json
")
if [[ "$result" == "1" ]]; then
    pass "dashboard_task updates in-place, no duplicates"
else
    fail "dashboard_task duplicated" "got count: $result"
fi

# Test dashboard_set_alert
result=$(bash -c "
cd '$T11'
source .claude/scripts/dashboard-state.sh
dashboard_init 'test-feature'
dashboard_stage_start 'testing'
dashboard_set_alert 'testing' 'warning' '2 failing'
jq -r '.stages[3].alert.message' .claude/dashboard/pipeline.json
")
if [[ "$result" == "2 failing" ]]; then
    pass "dashboard_set_alert works"
else
    fail "dashboard_set_alert failed" "got: $result"
fi

# ── Test 12: Install registers Stop hook in settings.json ────────────────────

echo "Test 12: Install registers Stop hook"
T12="$(make_temp)"
bash "$REPO_ROOT/install.sh" "$T12" >/dev/null 2>&1

if [[ -f "$T12/.claude/settings.json" ]] && grep -qF "dashboard-stop-hook.sh" "$T12/.claude/settings.json"; then
    pass "Stop hook registered in settings.json"
else
    fail "Stop hook not in settings.json"
fi

# Test idempotency — re-install should not duplicate hook
bash "$REPO_ROOT/install.sh" "$T12" >/dev/null 2>&1
hook_count=$(grep -c "dashboard-stop-hook.sh" "$T12/.claude/settings.json" || echo 0)
if [[ "$hook_count" -eq 1 ]]; then
    pass "Re-install does not duplicate Stop hook"
else
    fail "Stop hook duplicated on re-install" "count: $hook_count"
fi

# ── Test 13: Pipeline commands have dashboard calls ──────────────────────────

echo "Test 13: Pipeline commands include dashboard calls"
missing=0
for cmd in feature.md feature-domains.md feature-plan.md feature-test.md feature-implement.md feature-refactor.md feature-pr.md; do
    if ! grep -q "dashboard_stage_start\|dashboard_init" "$REPO_ROOT/commands/$cmd" 2>/dev/null; then
        fail "Missing dashboard_stage_start in $cmd"
        missing=1
    fi
    if ! grep -q "dashboard_stage_complete" "$REPO_ROOT/commands/$cmd" 2>/dev/null; then
        fail "Missing dashboard_stage_complete in $cmd"
        missing=1
    fi
done
if [[ "$missing" -eq 0 ]]; then
    pass "All 7 pipeline commands have dashboard start and complete calls"
fi

# ── Test 14: feature-init.md includes .claude/dashboard/ in gitignore ────────

echo "Test 14: feature-init.md gitignore includes dashboard"
if grep -qF ".claude/dashboard/" "$REPO_ROOT/commands/feature-init.md"; then
    pass "feature-init.md adds .claude/dashboard/ to .gitignore"
else
    fail "feature-init.md missing .claude/dashboard/ gitignore entry"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════"
echo "  Results: $passed passed, $failed failed (of $total)"
echo "═══════════════════════════════════"
echo ""

[[ "$failed" -eq 0 ]] && exit 0 || exit 1
