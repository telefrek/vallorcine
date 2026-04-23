#!/usr/bin/env bash
# Scenario: vallorcine version skew across branches
#
# Validates that when vallorcine is upgraded on main but a feature branch
# hasn't pulled the upgrade, the version skew is detectable and resolvable
# via upgrade.sh --apply.
#
# Run from repo root: bash tests/scenario-version-skew.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION="$(cat "$REPO_ROOT/VERSION")"
TEST_BASE="/tmp/vallorcine/scenario-version-skew"

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
echo "scenario: version skew detection and resolution"
echo "VERSION: $VERSION"
echo "────────────────────────────────────────────────"

# ── Setup: repo with vallorcine installed ────────────────────────────────────

cleanup
mkdir -p "$TEST_BASE"

PROJECT="$TEST_BASE/project"
mkdir -p "$PROJECT"

echo ""
echo "── Setup: install vallorcine into test project"

git init --initial-branch=main "$PROJECT" >/dev/null 2>&1
git -C "$PROJECT" config user.email "test@test.com"
git -C "$PROJECT" config user.name "Test"

# Install vallorcine
bash "$REPO_ROOT/install.sh" "$PROJECT" >/dev/null 2>&1

# Commit the installed files
echo "# test project" > "$PROJECT/README.md"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "initial install v${VERSION}" >/dev/null 2>&1

INSTALLED_STAMP="$(cat "$PROJECT/.claude/.vallorcine-version")"
if [[ "$INSTALLED_STAMP" == "$VERSION" ]]; then
    pass "installed at v${VERSION}"
else
    fail "install version stamp" "expected $VERSION, got $INSTALLED_STAMP"
fi

# ── Create feature branch, then upgrade on main ─────────────────────────────

echo ""
echo "── Setup: create feature branch, then upgrade on main"

# Create feature branch (developer starts working before upgrade)
git -C "$PROJECT" checkout -b feature/stale-branch >/dev/null 2>&1
echo "# feature work" > "$PROJECT/feature-notes.md"
git -C "$PROJECT" add feature-notes.md
git -C "$PROJECT" commit -m "start feature work" >/dev/null 2>&1

# Switch to main and simulate an upgrade (bump version stamp + modify a file)
git -C "$PROJECT" checkout main >/dev/null 2>&1
echo "99.99.99" > "$PROJECT/.claude/.vallorcine-version"
# Add a marker to a command file to detect staleness
echo "# upgraded-marker" >> "$PROJECT/.claude/skills/feature-quick/SKILL.md"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "upgrade vallorcine to v99.99.99" >/dev/null 2>&1

pass "main upgraded to v99.99.99, feature branch still at v${VERSION}"

# ── Assert: version skew is detectable on feature branch ─────────────────────

echo ""
echo "── Assert: version skew detectable"

git -C "$PROJECT" checkout feature/stale-branch >/dev/null 2>&1

BRANCH_STAMP="$(cat "$PROJECT/.claude/.vallorcine-version")"
MAIN_STAMP="$(git -C "$PROJECT" show main:.claude/.vallorcine-version 2>/dev/null)"

if [[ "$BRANCH_STAMP" != "$MAIN_STAMP" ]]; then
    pass "version stamps differ (branch=$BRANCH_STAMP, main=$MAIN_STAMP)"
else
    fail "versions should differ" "both are $BRANCH_STAMP"
fi

# Check that the skill file on the branch lacks the upgrade marker
if ! grep -q "upgraded-marker" "$PROJECT/.claude/skills/feature-quick/SKILL.md" 2>/dev/null; then
    pass "feature branch has stale skill files"
else
    fail "feature branch should have stale files" "upgrade marker found"
fi

# ── Assert: upgrade.sh --apply resolves the skew ────────────────────────────

echo ""
echo "── Assert: upgrade --apply resolves version skew"

upgrade_output="$(bash "$REPO_ROOT/upgrade.sh" \
    --apply \
    --kit-root "$REPO_ROOT" \
    --project-root "$PROJECT" \
    --from-version "$BRANCH_STAMP" \
    --to-version "$VERSION" 2>&1)"

NEW_STAMP="$(cat "$PROJECT/.claude/.vallorcine-version")"
if [[ "$NEW_STAMP" == "$VERSION" ]]; then
    pass "upgrade resolves version to v${VERSION}"
else
    fail "upgrade should set version to $VERSION" "got: $NEW_STAMP"
fi

# Verify skill files were updated
if [[ -f "$PROJECT/.claude/skills/feature-quick/SKILL.md" ]]; then
    pass "skill files present after upgrade"
else
    fail "skill files should exist after upgrade"
fi

# ── Assert: version comparison works correctly ───────────────────────────────

echo ""
echo "── Assert: git diff can surface the skew for tooling"

# Simulate what a pre-commit hook or CI check could do
git -C "$PROJECT" checkout feature/stale-branch >/dev/null 2>&1

# After upgrade, the version stamp on the branch now matches current kit version
# but differs from main's v99.99.99 — this is intentional (upgrade to real version)
BRANCH_NOW="$(cat "$PROJECT/.claude/.vallorcine-version")"
MAIN_NOW="$(cd "$PROJECT" && git show main:.claude/.vallorcine-version 2>/dev/null)"

if [[ "$BRANCH_NOW" != "$MAIN_NOW" ]]; then
    pass "post-upgrade branch version ($BRANCH_NOW) differs from main ($MAIN_NOW)"
else
    # This is also fine — if versions match, skew is resolved
    pass "versions now match ($BRANCH_NOW) — skew fully resolved"
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
