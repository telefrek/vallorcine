#!/usr/bin/env bash
# vallorcine install & upgrade smoke tests
# Run from repo root: bash tests/test-install.sh
#
# Tests:
#   1. Fresh install to temp directory
#   2. All expected files exist after install
#   3. Version stamp matches VERSION
#   4. Idempotent install (re-run skips existing files)
#   5. FORCE_UPDATE=1 overwrites existing files
#   5b. Version mismatch auto-forces update (bootstrapping fix)
#   6. Safety guard blocks install to repo root
#   7. --dev flag installs to temp directory (not repo)
#   8. Upgrade apply from "old" version to current

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
    echo "  PASS  $1"
}

fail() {
    ((failed++)) || true
    ((total++)) || true
    echo "  FAIL  $1"
    [[ -n "${2:-}" ]] && echo "        $2"
}

assert_file_exists() {
    local path="$1"
    local label="${2:-$path}"
    if [[ -f "$path" ]]; then
        return 0
    else
        return 1
    fi
}

assert_file_contains() {
    local path="$1"
    local pattern="$2"
    if grep -q "$pattern" "$path" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

TEST_BASE="/tmp/vallorcine/test-install"

cleanup() {
    rm -rf "$TEST_BASE" 2>/dev/null || true
}
trap cleanup EXIT

# Start clean
cleanup
mkdir -p "$TEST_BASE"

test_count=0
make_temp() {
    local d="$TEST_BASE/$((++test_count))"
    mkdir -p "$d"
    echo "$d"
}

echo ""
echo "vallorcine install & upgrade smoke tests"
echo "VERSION: $VERSION"
echo "────────────────────────────────────────────────"

# ── Test 1: Fresh install ────────────────────────────────────────────────────

echo ""
echo "── Test 1: Fresh install to temp directory"

TARGET="$(make_temp)"
output="$(bash "$REPO_ROOT/install.sh" "$TARGET" 2>&1)"

if [[ $? -eq 0 ]]; then
    pass "install.sh exits 0"
else
    fail "install.sh exits 0" "exit code was non-zero"
fi

# ── Test 2: All expected files exist ─────────────────────────────────────────

echo ""
echo "── Test 2: Expected files exist after install"

# Read MANIFEST and check each file
missing=0
while IFS= read -r rel_path; do
    [[ "$rel_path" =~ ^#.*$ || -z "$rel_path" ]] && continue
    if assert_file_exists "$TARGET/$rel_path"; then
        :
    else
        fail "file exists: $rel_path"
        ((missing++)) || true
    fi
done < "$REPO_ROOT/MANIFEST"

# Also check non-manifest files that install.sh creates
for extra in \
    ".claude/.vallorcine-version" \
    ".claude/.vallorcine-manifest" \
    ".kb/CLAUDE.md" \
    ".kb/_refs/complexity-notation.md" \
    ".kb/_refs/benchmarking-methodology.md" \
    ".decisions/CLAUDE.md"; do
    if assert_file_exists "$TARGET/$extra"; then
        :
    else
        fail "file exists: $extra"
        ((missing++)) || true
    fi
done

if [[ $missing -eq 0 ]]; then
    pass "all expected files present"
else
    fail "missing $missing expected files"
fi

# ── Test 3: Version stamp matches ───────────────────────────────────────────

echo ""
echo "── Test 3: Version stamp matches VERSION"

STAMP="$(cat "$TARGET/.claude/.vallorcine-version")"
if [[ "$STAMP" == "$VERSION" ]]; then
    pass "version stamp = $VERSION"
else
    fail "version stamp = $VERSION" "got: $STAMP"
fi

# ── Test 4: Idempotent install (skips existing) ─────────────────────────────

echo ""
echo "── Test 4: Idempotent install (re-run skips existing)"

output2="$(bash "$REPO_ROOT/install.sh" "$TARGET" 2>&1)"
skip_count="$(echo "$output2" | grep -c "skip" || true)"
write_count="$(echo "$output2" | grep -c "write" || true)"

# On re-run, manifest files should be skipped (they already exist)
# Only version stamp and manifest are always written
if [[ $skip_count -gt 0 ]]; then
    pass "re-run skips existing files ($skip_count skipped)"
else
    fail "re-run should skip existing files" "skip_count=$skip_count"
fi

# ── Test 5: FORCE_UPDATE overwrites ─────────────────────────────────────────

echo ""
echo "── Test 5: FORCE_UPDATE=1 overwrites existing"

# Modify a file to detect overwrite
echo "# modified" >> "$TARGET/.claude/skills/feature-quick/SKILL.md"
output3="$(FORCE_UPDATE=1 bash "$REPO_ROOT/install.sh" "$TARGET" 2>&1)"
write_count3="$(echo "$output3" | grep -c "write" || true)"

# Check the modified file was overwritten (no longer has our marker)
if ! grep -q "^# modified$" "$TARGET/.claude/skills/feature-quick/SKILL.md" 2>/dev/null; then
    pass "FORCE_UPDATE overwrites modified files"
else
    fail "FORCE_UPDATE should overwrite" "file still has modification marker"
fi

# ── Test 5b: Version mismatch auto-forces update ─────────────────────────

echo ""
echo "── Test 5b: Version mismatch auto-forces update without FORCE_UPDATE"

MISMATCH_TARGET="$(make_temp)"
bash "$REPO_ROOT/install.sh" "$MISMATCH_TARGET" >/dev/null 2>&1

# Plant a marker in a kit file to detect overwrite
echo "# old-version-marker" >> "$MISMATCH_TARGET/.claude/skills/feature-quick/SKILL.md"

# Fake an older version stamp so install.sh sees a mismatch
echo "0.0.1" > "$MISMATCH_TARGET/.claude/.vallorcine-version"

# Re-install WITHOUT FORCE_UPDATE — version mismatch should auto-force
mismatch_output="$(bash "$REPO_ROOT/install.sh" "$MISMATCH_TARGET" 2>&1)"

if ! grep -q "^# old-version-marker$" "$MISMATCH_TARGET/.claude/skills/feature-quick/SKILL.md" 2>/dev/null; then
    pass "version mismatch overwrites kit files without FORCE_UPDATE"
else
    fail "version mismatch should auto-force overwrite" "file still has old marker"
fi

# Verify upgrade.sh specifically gets overwritten (the bootstrapping fix)
# Plant a marker in upgrade.sh
echo "# old-upgrade-marker" >> "$MISMATCH_TARGET/.claude/upgrade.sh"
echo "0.0.1" > "$MISMATCH_TARGET/.claude/.vallorcine-version"

mismatch_output2="$(bash "$REPO_ROOT/install.sh" "$MISMATCH_TARGET" 2>&1)"

if ! grep -q "^# old-upgrade-marker$" "$MISMATCH_TARGET/.claude/upgrade.sh" 2>/dev/null; then
    pass "version mismatch overwrites upgrade.sh (bootstrapping fix)"
else
    fail "version mismatch should overwrite upgrade.sh" "upgrade.sh still has old marker"
fi

# Verify version stamp updated to current
MISMATCH_STAMP="$(cat "$MISMATCH_TARGET/.claude/.vallorcine-version")"
if [[ "$MISMATCH_STAMP" == "$VERSION" ]]; then
    pass "version stamp updated after mismatch install"
else
    fail "version stamp should match current" "got: $MISMATCH_STAMP"
fi

# ── Test 6: Safety guard blocks repo-root install ───────────────────────────

echo ""
echo "── Test 6: Safety guard blocks install to repo root"

guard_output="$(bash "$REPO_ROOT/install.sh" "$REPO_ROOT" 2>&1 || true)"
if echo "$guard_output" | grep -q "vallorcine repo itself"; then
    pass "safety guard blocks install to repo root"
else
    fail "safety guard should block repo-root install" "output: $guard_output"
fi

# ── Test 7: --dev installs to temp dir ──────────────────────────────────────

echo ""
echo "── Test 7: --dev installs to temp directory"

dev_output="$(bash "$REPO_ROOT/install.sh" --dev 2>&1)"
dev_target="$(echo "$dev_output" | grep -o '/tmp/[^ ]*' | head -1)"

if [[ -n "$dev_target" && -d "$dev_target" ]]; then
    if [[ -f "$dev_target/.claude/skills/feature-quick/SKILL.md" ]]; then
        pass "--dev installs to temp dir ($dev_target)"
    else
        fail "--dev should install files" "skills not found in $dev_target"
    fi
else
    fail "--dev should use temp dir" "could not find temp path in output"
fi

# ── Test 7b: --diff shows changes without writing ─────────────────────────

echo ""
echo "── Test 7b: --diff shows changes without writing"

DIFF_TARGET="$(make_temp)"
bash "$REPO_ROOT/install.sh" "$DIFF_TARGET" >/dev/null 2>&1

# Modify a file so diff has something to report
echo "# modified" >> "$DIFF_TARGET/.claude/skills/feature-quick/SKILL.md"

# Run diff mode
diff_output="$(bash "$REPO_ROOT/install.sh" --diff "$DIFF_TARGET" 2>&1)"

# Should show "changed" for the modified file
if echo "$diff_output" | grep -q "changed.*feature-quick/SKILL.md"; then
    pass "--diff detects changed files"
else
    fail "--diff should detect changed files" "output did not contain 'changed'"
fi

# Should NOT have written the file (still has our marker)
if grep -q "^# modified$" "$DIFF_TARGET/.claude/skills/feature-quick/SKILL.md" 2>/dev/null; then
    pass "--diff does not write files"
else
    fail "--diff should not modify files" "file was modified"
fi

# Should show "Diff complete" summary
if echo "$diff_output" | grep -q "Diff complete"; then
    pass "--diff shows summary"
else
    fail "--diff should show summary" "output did not contain 'Diff complete'"
fi

# ── Test 8: Upgrade apply ───────────────────────────────────────────────────

echo ""
echo "── Test 8: Upgrade --apply from old version"

# Set up a "previously installed" project with an older version
UPGRADE_TARGET="$(make_temp)"
bash "$REPO_ROOT/install.sh" "$UPGRADE_TARGET" >/dev/null 2>&1

# Fake an older version stamp
echo "0.0.1" > "$UPGRADE_TARGET/.claude/.vallorcine-version"

# Run upgrade --apply simulating the new kit being at REPO_ROOT
upgrade_output="$(bash "$REPO_ROOT/upgrade.sh" \
    --apply \
    --kit-root "$REPO_ROOT" \
    --project-root "$UPGRADE_TARGET" \
    --from-version "0.0.1" \
    --to-version "$VERSION" 2>&1)"

NEW_STAMP="$(cat "$UPGRADE_TARGET/.claude/.vallorcine-version")"
if [[ "$NEW_STAMP" == "$VERSION" ]]; then
    pass "upgrade updates version stamp to $VERSION"
else
    fail "upgrade should update version stamp" "got: $NEW_STAMP"
fi

# Verify upgraded files are present
if [[ -f "$UPGRADE_TARGET/.claude/skills/feature-quick/SKILL.md" ]]; then
    pass "upgrade preserves skill files"
else
    fail "upgrade should preserve skill files"
fi

# ── Test 9: Upgrade stale removal preserves user files ──────────────

echo ""
echo "── Test 9: Upgrade stale removal preserves user files"

STALE_TARGET="$(make_temp)"
bash "$REPO_ROOT/install.sh" "$STALE_TARGET" >/dev/null 2>&1

# 9a: User files in .claude/commands/ that are NOT in the manifest
# should never be touched (stale removal only reads the manifest)
echo "# my perf test skill" > "$STALE_TARGET/.claude/commands/perf-test.md"
echo "# my custom skill" > "$STALE_TARGET/.claude/commands/my-custom-tool.md"

stale_output="$(bash "$REPO_ROOT/upgrade.sh" \
    --apply \
    --kit-root "$REPO_ROOT" \
    --project-root "$STALE_TARGET" \
    --from-version "0.0.1" \
    --to-version "$VERSION" 2>&1)"

if [[ -f "$STALE_TARGET/.claude/commands/perf-test.md" ]]; then
    pass "user command perf-test.md preserved (not in manifest)"
else
    fail "user command perf-test.md was deleted by upgrade"
fi

if [[ -f "$STALE_TARGET/.claude/commands/my-custom-tool.md" ]]; then
    pass "user command my-custom-tool.md preserved (not in manifest)"
else
    fail "user command my-custom-tool.md was deleted by upgrade"
fi

# 9b: Non-kit paths in a corrupted manifest are refused by safety guard
# (protects against manifest corruption or malformed entries)
cat >> "$STALE_TARGET/.claude/.vallorcine-manifest" << 'MANIFEST'
src/main.py
README.md
docs/api.md
MANIFEST

mkdir -p "$STALE_TARGET/src" "$STALE_TARGET/docs"
echo "# source" > "$STALE_TARGET/src/main.py"
echo "# readme" > "$STALE_TARGET/README.md"
echo "# docs" > "$STALE_TARGET/docs/api.md"

stale_output2="$(bash "$REPO_ROOT/upgrade.sh" \
    --apply \
    --kit-root "$REPO_ROOT" \
    --project-root "$STALE_TARGET" \
    --from-version "0.0.1" \
    --to-version "$VERSION" 2>&1)"

if echo "$stale_output2" | grep -q "not a known kit path"; then
    pass "safety guard warns about non-kit paths in manifest"
else
    fail "safety guard should warn about non-kit paths" "no warning in output"
fi

if [[ -f "$STALE_TARGET/src/main.py" && -f "$STALE_TARGET/README.md" ]]; then
    pass "non-kit files preserved despite corrupted manifest"
else
    fail "non-kit files were deleted" "safety guard did not protect them"
fi

# 9c: Legitimate stale kit files ARE removed
# (old kit command no longer in the new kit → should be cleaned up)
echo ".claude/commands/old-removed-command.md" >> "$STALE_TARGET/.claude/.vallorcine-manifest"
echo "# this was removed from the kit" > "$STALE_TARGET/.claude/commands/old-removed-command.md"

stale_output3="$(bash "$REPO_ROOT/upgrade.sh" \
    --apply \
    --kit-root "$REPO_ROOT" \
    --project-root "$STALE_TARGET" \
    --from-version "0.0.1" \
    --to-version "$VERSION" 2>&1)"

if [[ ! -f "$STALE_TARGET/.claude/commands/old-removed-command.md" ]]; then
    pass "legitimate stale kit file removed during upgrade"
else
    fail "stale kit file should be removed" "old-removed-command.md still exists"
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
