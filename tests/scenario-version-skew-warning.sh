#!/usr/bin/env bash
# Scenario: version-check.sh warns on version skew
#
# Validates that the version-check script correctly:
# - Stays silent when versions match
# - Stays silent on the main branch
# - Warns when the current branch is behind main
# - Stays silent when main is behind (dev install ahead of release)
#
# Run from repo root: bash tests/scenario-version-skew-warning.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-version-check"

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
echo "scenario: version-check.sh warning behavior"
echo "────────────────────────────────────────────────"

# ── Setup: project repo with vallorcine installed ────────────────────────────

cleanup
mkdir -p "$TEST_BASE"

PROJECT="$TEST_BASE/project"

echo ""
echo "── Setup: install vallorcine into test project"

git init --initial-branch=main "$PROJECT" >/dev/null 2>&1
git -C "$PROJECT" config user.email "test@test.com"
git -C "$PROJECT" config user.name "Test"

bash "$REPO_ROOT/install.sh" "$PROJECT" >/dev/null 2>&1

echo "# test" > "$PROJECT/README.md"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "initial install" >/dev/null 2>&1

pass "project with vallorcine installed"

# ── Test 1: silent on main branch ────────────────────────────────────────────

echo ""
echo "── Test 1: silent on main branch"

output="$(cd "$PROJECT" && bash .claude/scripts/version-check.sh 2>&1)"
if [[ -z "$output" ]]; then
    pass "no output on main branch"
else
    fail "should be silent on main" "got: $output"
fi

# ── Test 2: silent when versions match ───────────────────────────────────────

echo ""
echo "── Test 2: silent when versions match on feature branch"

git -C "$PROJECT" checkout -b feature/test-match >/dev/null 2>&1

output="$(cd "$PROJECT" && bash .claude/scripts/version-check.sh 2>&1)"
if [[ -z "$output" ]]; then
    pass "no output when versions match"
else
    fail "should be silent when versions match" "got: $output"
fi

# ── Test 3: warns when branch is behind main ────────────────────────────────

echo ""
echo "── Test 3: warns when branch is behind main"

# Upgrade on main
git -C "$PROJECT" checkout main >/dev/null 2>&1
echo "2.0.0" > "$PROJECT/.claude/.vallorcine-version"
git -C "$PROJECT" add .claude/.vallorcine-version
git -C "$PROJECT" commit -m "upgrade to v2.0.0" >/dev/null 2>&1

# Switch to feature branch (still has old version)
git -C "$PROJECT" checkout feature/test-match >/dev/null 2>&1

output="$(cd "$PROJECT" && bash .claude/scripts/version-check.sh 2>&1)"
if echo "$output" | grep -q "version skew"; then
    pass "warns about version skew"
else
    fail "should warn about version skew" "got: $output"
fi

if echo "$output" | grep -q "v2.0.0"; then
    pass "warning mentions main version (v2.0.0)"
else
    fail "warning should mention main version" "got: $output"
fi

# ── Test 4: silent when branch is ahead of main ─────────────────────────────

echo ""
echo "── Test 4: silent when branch is ahead of main (dev install)"

# Set branch version higher than main
CURRENT_VERSION="$(cat "$PROJECT/.claude/.vallorcine-version")"
echo "99.0.0" > "$PROJECT/.claude/.vallorcine-version"

output="$(cd "$PROJECT" && bash .claude/scripts/version-check.sh 2>&1)"

# Restore
echo "$CURRENT_VERSION" > "$PROJECT/.claude/.vallorcine-version"

if [[ -z "$output" ]]; then
    pass "no output when branch is ahead"
else
    fail "should be silent when branch is ahead" "got: $output"
fi

# ── Test 5: silent outside a git repo ────────────────────────────────────────

echo ""
echo "── Test 5: silent outside a git repo"

NO_GIT="$TEST_BASE/no-git"
mkdir -p "$NO_GIT/.claude/scripts"
cp "$PROJECT/.claude/scripts/version-check.sh" "$NO_GIT/.claude/scripts/"
echo "1.0.0" > "$NO_GIT/.claude/.vallorcine-version"

output="$(cd "$NO_GIT" && bash .claude/scripts/version-check.sh 2>&1)"
if [[ -z "$output" ]]; then
    pass "no output outside git repo"
else
    fail "should be silent outside git repo" "got: $output"
fi

# ── Test 6: exit code is always 0 ───────────────────────────────────────────

echo ""
echo "── Test 6: exit code is always 0 (advisory only)"

# Run from the skewed branch (should warn but exit 0)
git -C "$PROJECT" checkout feature/test-match >/dev/null 2>&1
exit_code=0
(cd "$PROJECT" && bash .claude/scripts/version-check.sh >/dev/null 2>&1) || exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    pass "exit code 0 even with version skew"
else
    fail "exit code should always be 0" "got: $exit_code"
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
