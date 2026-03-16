#!/usr/bin/env bash
# Scenario: ensure-merge-driver.sh auto-configures on first pipeline run
#
# Validates that a fresh clone (without running install.sh) gets the merge
# driver registered automatically when a pipeline command triggers the
# ensure script.
#
# Run from repo root: bash tests/scenario-ensure-merge-driver.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-ensure-driver"

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
echo "scenario: ensure-merge-driver auto-setup"
echo "────────────────────────────────────────────────"

cleanup
mkdir -p "$TEST_BASE"

# ── Setup: repo with vallorcine files but NO git config ──────────────────────

echo ""
echo "── Setup: repo with driver script but no git config"

PROJECT="$TEST_BASE/project"
git init --initial-branch=main "$PROJECT" >/dev/null 2>&1
git -C "$PROJECT" config user.email "test@test.com"
git -C "$PROJECT" config user.name "Test"

# Install vallorcine files manually (simulating a clone of a repo that
# had vallorcine installed — .gitattributes and scripts are in the tree
# but git config is per-clone and empty)
mkdir -p "$PROJECT/.claude/scripts"
cp "$REPO_ROOT/scripts/merge-driver-index.sh" "$PROJECT/.claude/scripts/"
cp "$REPO_ROOT/scripts/ensure-merge-driver.sh" "$PROJECT/.claude/scripts/"

echo "# test" > "$PROJECT/README.md"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "initial" >/dev/null 2>&1

pass "project created without merge driver config"

# ── Test 1: git config has no merge driver ───────────────────────────────────

echo ""
echo "── Test 1: no merge driver in git config before ensure"

config_before="$(git -C "$PROJECT" config --local merge.vallorcine-index.driver 2>/dev/null || echo "")"
if [[ -z "$config_before" ]]; then
    pass "merge driver not in git config"
else
    fail "should not have driver yet" "got: $config_before"
fi

# ── Test 2: ensure script registers the driver ───────────────────────────────

echo ""
echo "── Test 2: ensure script registers driver and .gitattributes"

output="$(cd "$PROJECT" && bash .claude/scripts/ensure-merge-driver.sh 2>&1)"

if echo "$output" | grep -q "registered"; then
    pass "script reports driver registered"
else
    fail "should report registration" "got: $output"
fi

if echo "$output" | grep -q "gitattributes"; then
    pass "script reports .gitattributes updated"
else
    fail "should report .gitattributes update" "got: $output"
fi

# Verify git config
config_after="$(git -C "$PROJECT" config --local merge.vallorcine-index.driver 2>/dev/null || echo "")"
if [[ -n "$config_after" ]]; then
    pass "merge driver now in git config"
else
    fail "git config should have merge driver"
fi

# Verify .gitattributes
if grep -q "vallorcine-index" "$PROJECT/.gitattributes" 2>/dev/null; then
    pass ".gitattributes has merge driver entries"
else
    fail ".gitattributes should have entries"
fi

# ── Test 3: idempotent — re-run is silent ────────────────────────────────────

echo ""
echo "── Test 3: re-run is silent (idempotent)"

output2="$(cd "$PROJECT" && bash .claude/scripts/ensure-merge-driver.sh 2>&1)"
if [[ -z "$output2" ]]; then
    pass "second run produces no output"
else
    fail "second run should be silent" "got: $output2"
fi

# ── Test 4: works end-to-end with actual merge ───────────────────────────────

echo ""
echo "── Test 4: driver works after ensure (end-to-end merge)"

# Set up KB index
mkdir -p "$PROJECT/.kb"
cat > "$PROJECT/.kb/CLAUDE.md" << 'EOF'
# Knowledge Base — Root Index

## Topic Map

| Topic | Path | Categories | Files | Last Updated |
|-------|------|------------|-------|--------------|
| base | .kb/base/ | 1 | 1 | 2026-03-01 |
EOF

git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "add kb index" >/dev/null 2>&1

# Branch A adds a row
git -C "$PROJECT" checkout -b branch-a >/dev/null 2>&1
sed -i '/| base |/a | topic-a | .kb/topic-a/ | 1 | 2 | 2026-03-10 |' "$PROJECT/.kb/CLAUDE.md"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "add topic-a" >/dev/null 2>&1

# Branch B adds a different row
git -C "$PROJECT" checkout main >/dev/null 2>&1
git -C "$PROJECT" checkout -b branch-b >/dev/null 2>&1
sed -i '/| base |/a | topic-b | .kb/topic-b/ | 1 | 3 | 2026-03-11 |' "$PROJECT/.kb/CLAUDE.md"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "add topic-b" >/dev/null 2>&1

# Merge A to main
git -C "$PROJECT" checkout main >/dev/null 2>&1
git -C "$PROJECT" merge branch-a --no-edit >/dev/null 2>&1

# Merge B to main (should use driver)
merge_exit=0
git -C "$PROJECT" merge branch-b --no-edit >/dev/null 2>&1 || merge_exit=$?

if [[ $merge_exit -eq 0 ]]; then
    pass "merge succeeds with auto-configured driver"
else
    fail "merge should succeed" "exit=$merge_exit"
fi

if grep -q "topic-a" "$PROJECT/.kb/CLAUDE.md" && grep -q "topic-b" "$PROJECT/.kb/CLAUDE.md"; then
    pass "both topics present after merge"
else
    fail "both topics should be present"
fi

if ! grep -q "<<<<" "$PROJECT/.kb/CLAUDE.md" 2>/dev/null; then
    pass "no conflict markers"
else
    fail "should have no conflict markers"
fi

# ── Test 5: silent outside a git repo ────────────────────────────────────────

echo ""
echo "── Test 5: silent outside a git repo"

NO_GIT="$TEST_BASE/no-git"
mkdir -p "$NO_GIT/.claude/scripts"
cp "$REPO_ROOT/scripts/ensure-merge-driver.sh" "$NO_GIT/.claude/scripts/"
cp "$REPO_ROOT/scripts/merge-driver-index.sh" "$NO_GIT/.claude/scripts/"

output3="$(cd "$NO_GIT" && bash .claude/scripts/ensure-merge-driver.sh 2>&1)"
if [[ -z "$output3" ]]; then
    pass "silent outside git repo"
else
    fail "should be silent outside git repo" "got: $output3"
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
