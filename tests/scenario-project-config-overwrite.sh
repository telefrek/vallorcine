#!/usr/bin/env bash
# Scenario: concurrent project-config.md overwrites
#
# Validates that two developers running /feature-init with different answers
# on separate branches produces a visible merge conflict in
# .feature/project-config.md, forcing manual resolution.
#
# This test validates the PROBLEM exists — the fix is convention, not code.
#
# Run from repo root: bash tests/scenario-project-config-overwrite.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-project-config"

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
echo "scenario: project-config overwrite"
echo "────────────────────────────────────────────────"

# ── Setup: bare repo + two clones ────────────────────────────────────────────

cleanup  # clear any previous run
mkdir -p "$TEST_BASE"

REMOTE="$TEST_BASE/remote.git"
CLONE_A="$TEST_BASE/clone-a"
CLONE_B="$TEST_BASE/clone-b"

echo ""
echo "── Setup: bare repo with two clones"

git init --bare --initial-branch=main "$REMOTE" >/dev/null 2>&1

# Create initial commit directly so clone works
INIT_DIR="$TEST_BASE/init-tmp"
mkdir -p "$INIT_DIR"
git init --initial-branch=main "$INIT_DIR" >/dev/null 2>&1
git -C "$INIT_DIR" config user.email "test@test.com"
git -C "$INIT_DIR" config user.name "Test"
echo "# test project" > "$INIT_DIR/README.md"
mkdir -p "$INIT_DIR/.feature"
git -C "$INIT_DIR" add README.md
git -C "$INIT_DIR" commit -m "initial" >/dev/null 2>&1
git -C "$INIT_DIR" remote add origin "$REMOTE"
git -C "$INIT_DIR" push origin main >/dev/null 2>&1
rm -rf "$INIT_DIR"

git clone "$REMOTE" "$CLONE_A" >/dev/null 2>&1
git -C "$CLONE_A" config user.email "test@test.com"
git -C "$CLONE_A" config user.name "Test"

git clone "$REMOTE" "$CLONE_B" >/dev/null 2>&1
git -C "$CLONE_B" config user.email "test@test.com"
git -C "$CLONE_B" config user.name "Test"

pass "bare repo + two clones created"

# ── Action: /feature-init on both branches with different answers ────────────

echo ""
echo "── Action: simulate /feature-init on separate branches"

# Developer A: creates project-config on branch feature/widget
git -C "$CLONE_A" checkout -b feature/widget >/dev/null 2>&1
mkdir -p "$CLONE_A/.feature"
cat > "$CLONE_A/.feature/project-config.md" << 'EOF'
# Project Profile

Language: Java 25
Build: Gradle (Groovy DSL)
Test framework: JUnit 5
Style: Google Java Style
Modules: core, indexing, vector
EOF
git -C "$CLONE_A" add .feature/project-config.md
git -C "$CLONE_A" commit -m "feature-init: widget (Java project)" >/dev/null 2>&1
git -C "$CLONE_A" push origin feature/widget >/dev/null 2>&1

# Developer B: creates project-config on branch feature/dashboard
git -C "$CLONE_B" checkout -b feature/dashboard >/dev/null 2>&1
mkdir -p "$CLONE_B/.feature"
cat > "$CLONE_B/.feature/project-config.md" << 'EOF'
# Project Profile

Language: TypeScript
Build: npm
Test framework: Vitest
Style: Prettier + ESLint
Modules: api, ui, shared
EOF
git -C "$CLONE_B" add .feature/project-config.md
git -C "$CLONE_B" commit -m "feature-init: dashboard (TypeScript project)" >/dev/null 2>&1
git -C "$CLONE_B" push origin feature/dashboard >/dev/null 2>&1

pass "two branches with different project-config.md"

# ── Merge: first branch merges cleanly, second causes conflict ───────────────

echo ""
echo "── Merge: merge both branches to main"

# Merge feature/widget to main (should succeed)
git -C "$CLONE_A" checkout main >/dev/null 2>&1
git -C "$CLONE_A" merge feature/widget --no-edit >/dev/null 2>&1
git -C "$CLONE_A" push origin main >/dev/null 2>&1

pass "feature/widget merges to main cleanly"

# Merge feature/dashboard to main (should conflict)
git -C "$CLONE_B" checkout main >/dev/null 2>&1
git -C "$CLONE_B" pull origin main >/dev/null 2>&1
merge_exit=0
git -C "$CLONE_B" merge feature/dashboard --no-edit >"$TEST_BASE/merge-output.txt" 2>&1 || merge_exit=$?

# ── Assert: merge conflict in .feature/project-config.md ─────────────────────

echo ""
echo "── Assert: merge conflict produced"

if [[ "$merge_exit" != "0" ]] || grep -q "CONFLICT" "$TEST_BASE/merge-output.txt" 2>/dev/null; then
    pass "merge produces conflict (exit=$merge_exit)"
else
    fail "merge should produce conflict" "exit was $merge_exit, no CONFLICT in output"
fi

# Check conflict markers are in the file
if grep -q "<<<<<<" "$CLONE_B/.feature/project-config.md" 2>/dev/null; then
    pass "project-config.md contains conflict markers"
else
    fail "project-config.md should contain conflict markers"
fi

# Verify both contents are represented in the conflict
if grep -q "Java 25" "$CLONE_B/.feature/project-config.md" 2>/dev/null &&
   grep -q "TypeScript" "$CLONE_B/.feature/project-config.md" 2>/dev/null; then
    pass "conflict includes both project profiles"
else
    fail "conflict should include both profiles"
fi

# Clean up the merge conflict so the repo isn't left dirty
git -C "$CLONE_B" merge --abort 2>/dev/null || true

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "This test validates that concurrent /feature-init creates a visible"
echo "merge conflict. The fix is convention: treat /feature-init as one-time"
echo "setup on a shared branch, not per-developer."
echo ""
if [[ $failed -eq 0 ]]; then
    echo "ALL PASSED  ($passed/$total)"
else
    echo "FAILED  $failed/$total  ($passed passed)"
fi
echo ""

exit $failed
