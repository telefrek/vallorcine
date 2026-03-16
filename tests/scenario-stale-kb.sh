#!/usr/bin/env bash
# Scenario: KB freshness check warns on stale indexes
#
# Validates that kb-freshness-check.sh correctly:
# - Stays silent when indexes match main
# - Warns when main has newer KB entries
# - Warns when main has newer decisions entries
# - Stays silent on the main branch
# - Stays silent outside a git repo
#
# Run from repo root: bash tests/scenario-stale-kb.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-stale-kb"

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
echo "scenario: KB freshness check"
echo "────────────────────────────────────────────────"

# ── Setup ────────────────────────────────────────────────────────────────────

cleanup
mkdir -p "$TEST_BASE"

PROJECT="$TEST_BASE/project"
git init --initial-branch=main "$PROJECT" >/dev/null 2>&1
git -C "$PROJECT" config user.email "test@test.com"
git -C "$PROJECT" config user.name "Test"

# Install scripts
mkdir -p "$PROJECT/.claude/scripts"
cp "$REPO_ROOT/scripts/kb-freshness-check.sh" "$PROJECT/.claude/scripts/"

# Create KB and decisions indexes
mkdir -p "$PROJECT/.kb" "$PROJECT/.decisions"

cat > "$PROJECT/.kb/CLAUDE.md" << 'EOF'
# Knowledge Base — Root Index

## Topic Map

| Topic | Path | Categories | Files | Last Updated |
|-------|------|------------|-------|--------------|
| algorithms | .kb/algorithms/ | 2 | 5 | 2026-03-01 |
EOF

cat > "$PROJECT/.decisions/CLAUDE.md" << 'EOF'
# Architecture Decisions — Master Index

## Active Decisions

| Problem | Slug | Date | Status | Recommendation |
|---------|------|------|--------|----------------|
| Storage engine | storage-engine | 2026-03-01 | proposed | LSM-Tree |
EOF

echo "# test" > "$PROJECT/README.md"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "initial" >/dev/null 2>&1

pass "project with KB and decisions indexes"

# ── Test 1: silent on main branch ────────────────────────────────────────────

echo ""
echo "── Test 1: silent on main branch"

output="$(cd "$PROJECT" && bash .claude/scripts/kb-freshness-check.sh 2>&1)"
if [[ -z "$output" ]]; then
    pass "no output on main"
else
    fail "should be silent on main" "got: $output"
fi

# ── Test 2: silent when indexes match ────────────────────────────────────────

echo ""
echo "── Test 2: silent when feature branch matches main"

git -C "$PROJECT" checkout -b feature/test >/dev/null 2>&1

output="$(cd "$PROJECT" && bash .claude/scripts/kb-freshness-check.sh 2>&1)"
if [[ -z "$output" ]]; then
    pass "no output when indexes match"
else
    fail "should be silent when matching" "got: $output"
fi

# ── Test 3: warns when main has new KB entries ───────────────────────────────

echo ""
echo "── Test 3: warns when main has newer KB entries"

# Add a new topic on main
git -C "$PROJECT" checkout main >/dev/null 2>&1
sed -i '/| algorithms |/a | ml | .kb/ml/ | 1 | 3 | 2026-03-10 |' "$PROJECT/.kb/CLAUDE.md"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "add ml topic" >/dev/null 2>&1

# Switch to feature branch (stale KB)
git -C "$PROJECT" checkout feature/test >/dev/null 2>&1

output="$(cd "$PROJECT" && bash .claude/scripts/kb-freshness-check.sh 2>&1)"
if echo "$output" | grep -q "behind"; then
    pass "warns about stale KB"
else
    fail "should warn about stale KB" "got: $output"
fi

if echo "$output" | grep -q ".kb/CLAUDE.md"; then
    pass "identifies .kb/CLAUDE.md as stale"
else
    fail "should identify .kb/CLAUDE.md" "got: $output"
fi

# ── Test 4: warns when main has new decisions ────────────────────────────────

echo ""
echo "── Test 4: warns when main has newer decisions"

# Add a new decision on main
git -C "$PROJECT" checkout main >/dev/null 2>&1
sed -i '/| Storage engine |/a | Cache layer | cache-layer | 2026-03-10 | proposed | Redis |' "$PROJECT/.decisions/CLAUDE.md"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "add cache decision" >/dev/null 2>&1

# Switch to feature branch
git -C "$PROJECT" checkout feature/test >/dev/null 2>&1

output="$(cd "$PROJECT" && bash .claude/scripts/kb-freshness-check.sh 2>&1)"
if echo "$output" | grep -q ".decisions/CLAUDE.md"; then
    pass "identifies .decisions/CLAUDE.md as stale"
else
    fail "should identify .decisions/CLAUDE.md" "got: $output"
fi

# Both should be flagged
if echo "$output" | grep -q ".kb/CLAUDE.md" && echo "$output" | grep -q ".decisions/CLAUDE.md"; then
    pass "warns about both stale indexes"
else
    fail "should warn about both" "got: $output"
fi

# ── Test 5: suggests merge command ───────────────────────────────────────────

echo ""
echo "── Test 5: suggests resolution"

if echo "$output" | grep -q "git merge"; then
    pass "suggests git merge to resolve"
else
    fail "should suggest resolution" "got: $output"
fi

# ── Test 6: silent outside a git repo ────────────────────────────────────────

echo ""
echo "── Test 6: silent outside a git repo"

NO_GIT="$TEST_BASE/no-git"
mkdir -p "$NO_GIT/.claude/scripts"
cp "$REPO_ROOT/scripts/kb-freshness-check.sh" "$NO_GIT/.claude/scripts/"

output="$(cd "$NO_GIT" && bash .claude/scripts/kb-freshness-check.sh 2>&1)"
if [[ -z "$output" ]]; then
    pass "silent outside git repo"
else
    fail "should be silent outside git repo" "got: $output"
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
