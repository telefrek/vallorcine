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
    ".kb/_refs/adversarial-finding-template.md" \
    ".kb/_refs/feature-footprint-template.md" \
    ".kb/_refs/frontmatter.md" \
    ".kb/_refs/detail-companion.md" \
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

# ── Test 5c: FORCE_UPDATE never overwrites user-populated seed files ──────────

echo ""
echo "── Test 5c: FORCE_UPDATE preserves user-populated KB and decisions indexes"

SEED_TARGET="$(make_temp)"
bash "$REPO_ROOT/install.sh" "$SEED_TARGET" >/dev/null 2>&1

# Simulate user-populated indexes (research and architect added rows)
cat > "$SEED_TARGET/.kb/CLAUDE.md" << 'SEEDKB'
# Knowledge Base — Root Index

## Topic Map

| Topic | Path | Categories | Files | Last Updated |
|-------|------|------------|-------|--------------|
| algorithms | .kb/algorithms/ | 2 | 5 | 2026-03-17 |

## Recently Added (last 10)
| Date | Topic | Category | Subject |
|------|-------|----------|---------|
| 2026-03-17 | algorithms | vector-indexing | hnsw |
SEEDKB

cat > "$SEED_TARGET/.decisions/CLAUDE.md" << 'SEEDDEC'
# Architecture Decisions — Master Index

## Active Decisions

| Problem | Slug | Date | Status | Recommendation |
|---------|------|------|--------|----------------|

## Recently Accepted (last 5)

| Problem | Slug | Accepted | Recommendation |
|---------|------|----------|----------------|
| Vector search | vector-search | 2026-03-17 | HNSW |
SEEDDEC

# Force install — should NOT overwrite the populated indexes
FORCE_UPDATE=1 bash "$REPO_ROOT/install.sh" "$SEED_TARGET" >/dev/null 2>&1

if grep -q "algorithms" "$SEED_TARGET/.kb/CLAUDE.md" 2>/dev/null; then
    pass "FORCE_UPDATE preserves user-populated .kb/CLAUDE.md"
else
    fail "FORCE_UPDATE overwrote .kb/CLAUDE.md with empty seed template"
fi

if grep -q "vector-search" "$SEED_TARGET/.decisions/CLAUDE.md" 2>/dev/null; then
    pass "FORCE_UPDATE preserves user-populated .decisions/CLAUDE.md"
else
    fail "FORCE_UPDATE overwrote .decisions/CLAUDE.md with empty seed template"
fi

# Also test version mismatch path (triggers auto-force)
echo "0.0.1" > "$SEED_TARGET/.claude/.vallorcine-version"
bash "$REPO_ROOT/install.sh" "$SEED_TARGET" >/dev/null 2>&1

if grep -q "algorithms" "$SEED_TARGET/.kb/CLAUDE.md" 2>/dev/null; then
    pass "version mismatch auto-force preserves .kb/CLAUDE.md"
else
    fail "version mismatch auto-force overwrote .kb/CLAUDE.md"
fi

if grep -q "vector-search" "$SEED_TARGET/.decisions/CLAUDE.md" 2>/dev/null; then
    pass "version mismatch auto-force preserves .decisions/CLAUDE.md"
else
    fail "version mismatch auto-force overwrote .decisions/CLAUDE.md"
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
# Use bash regex (not grep|head) — the pipe SIGPIPEs grep under `set -euo pipefail`
# and kills the whole test script. BASH_REMATCH gives us the first match directly.
if [[ "$dev_output" =~ /tmp/[^[:space:]]+ ]]; then
    dev_target="${BASH_REMATCH[0]}"
else
    dev_target=""
fi

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

# ── Test 8b: Upgrade copies script subdirectories (#28) ─────────────

echo ""
echo "── Test 8b: Upgrade copies scripts/ subdirectories (narrative/)"

SUBDIR_TARGET="$(make_temp)"
bash "$REPO_ROOT/install.sh" "$SUBDIR_TARGET" >/dev/null 2>&1

# Simulate old install missing the narrative/ subdirectory
rm -rf "$SUBDIR_TARGET/.claude/scripts/narrative"

echo "0.0.1" > "$SUBDIR_TARGET/.claude/.vallorcine-version"

bash "$REPO_ROOT/upgrade.sh" \
    --apply \
    --kit-root "$REPO_ROOT" \
    --project-root "$SUBDIR_TARGET" \
    --from-version "0.0.1" \
    --to-version "$VERSION" >/dev/null 2>&1

if [[ -f "$SUBDIR_TARGET/.claude/scripts/narrative/model.py" \
   && -f "$SUBDIR_TARGET/.claude/scripts/narrative/model.js" \
   && -f "$SUBDIR_TARGET/.claude/scripts/narrative/parse.py" \
   && -f "$SUBDIR_TARGET/.claude/scripts/narrative/generate.js" ]]; then
    pass "upgrade copies scripts/ subdirectories (narrative/)"
else
    fail "upgrade should copy scripts/ subdirectories" \
        "narrative/ files missing after upgrade"
fi

# Also verify top-level scripts still copied
if [[ -f "$SUBDIR_TARGET/.claude/scripts/statusline.sh" \
   && -f "$SUBDIR_TARGET/.claude/scripts/token-usage.sh" ]]; then
    pass "upgrade still copies top-level scripts"
else
    fail "upgrade should still copy top-level .sh scripts"
fi

# ── Test 8c: Upgrade patches settings.json hooks (#22) ──────────────

echo ""
echo "── Test 8c: Upgrade patches settings.json hooks"

HOOKS_TARGET="$(make_temp)"
cd "$HOOKS_TARGET" && git init -q && cd "$REPO_ROOT"

# Simulate old-style install with outdated hooks
mkdir -p "$HOOKS_TARGET/.claude/scripts"
cat > "$HOOKS_TARGET/.claude/settings.json" << 'OLDJSON'
{
  "permissions": { "allow": [] },
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/scripts/token-stop-hook.sh"
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/scripts/dashboard-stop-hook.sh"
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "bash .claude/scripts/statusline.sh"
  }
}
OLDJSON

echo "0.4.0" > "$HOOKS_TARGET/.claude/.vallorcine-version"
cp "$REPO_ROOT/MANIFEST" "$HOOKS_TARGET/.claude/.vallorcine-manifest"

bash "$REPO_ROOT/upgrade.sh" \
    --apply \
    --kit-root "$REPO_ROOT" \
    --project-root "$HOOKS_TARGET" \
    --from-version "0.4.0" \
    --to-version "$VERSION" >/dev/null 2>&1

# 8c-1: Old direct references migrated to wrappers
if assert_file_contains "$HOOKS_TARGET/.claude/settings.json" "token-hook-wrapper.sh"; then
    pass "upgrade migrates token-stop-hook.sh → wrapper"
else
    fail "upgrade should migrate token-stop-hook.sh to wrapper"
fi

if assert_file_contains "$HOOKS_TARGET/.claude/settings.json" "statusline-wrapper.sh"; then
    pass "upgrade migrates statusline.sh → wrapper"
else
    fail "upgrade should migrate statusline.sh to wrapper"
fi

# 8c-2: Stale dashboard hook removed
if ! grep -qF "dashboard-stop-hook" "$HOOKS_TARGET/.claude/settings.json" 2>/dev/null; then
    pass "upgrade removes stale dashboard-stop-hook"
else
    fail "upgrade should remove stale dashboard-stop-hook"
fi

# 8c-3: Missing SubagentStart/SubagentStop hooks added
if assert_file_contains "$HOOKS_TARGET/.claude/settings.json" "SubagentStart" && \
   assert_file_contains "$HOOKS_TARGET/.claude/settings.json" "SubagentStop"; then
    pass "upgrade adds missing SubagentStart/SubagentStop hooks"
else
    fail "upgrade should add SubagentStart/SubagentStop hooks"
fi

# 8c-4: Missing script permissions added
if assert_file_contains "$HOOKS_TARGET/.claude/settings.json" "curate-scan.sh"; then
    pass "upgrade adds missing script permissions"
else
    fail "upgrade should add script permissions"
fi

# 8c-5: Idempotent — running again changes nothing
settings_before="$(cat "$HOOKS_TARGET/.claude/settings.json")"
bash "$REPO_ROOT/upgrade.sh" \
    --apply \
    --kit-root "$REPO_ROOT" \
    --project-root "$HOOKS_TARGET" \
    --from-version "$VERSION" \
    --to-version "$VERSION" >/dev/null 2>&1
settings_after="$(cat "$HOOKS_TARGET/.claude/settings.json")"

if [[ "$settings_before" == "$settings_after" ]]; then
    pass "upgrade hook patching is idempotent"
else
    fail "upgrade hook patching should be idempotent"
fi

# 8c-6: User hooks preserved
USERHOOK_TARGET="$(make_temp)"
cd "$USERHOOK_TARGET" && git init -q && cd "$REPO_ROOT"
bash "$REPO_ROOT/install.sh" "$USERHOOK_TARGET" >/dev/null 2>&1

# Add a user hook
if command -v jq &>/dev/null; then
    jq '.hooks.Stop = (.hooks.Stop + [{
        "hooks": [{
            "type": "command",
            "command": "bash my-custom-hook.sh"
        }]
    }])' "$USERHOOK_TARGET/.claude/settings.json" > "$USERHOOK_TARGET/.claude/settings.json.tmp" \
    && mv "$USERHOOK_TARGET/.claude/settings.json.tmp" "$USERHOOK_TARGET/.claude/settings.json"

    bash "$REPO_ROOT/upgrade.sh" \
        --apply \
        --kit-root "$REPO_ROOT" \
        --project-root "$USERHOOK_TARGET" \
        --from-version "0.4.0" \
        --to-version "$VERSION" >/dev/null 2>&1

    if assert_file_contains "$USERHOOK_TARGET/.claude/settings.json" "my-custom-hook.sh"; then
        pass "upgrade preserves user hooks in settings.json"
    else
        fail "upgrade should preserve user hooks"
    fi
else
    echo "  SKIP  user hook preservation test (jq not available)"
fi

# ── Test 9: Upgrade stale removal preserves user files ──────────────

echo ""
echo "── Test 9: Upgrade stale removal preserves user files"

STALE_TARGET="$(make_temp)"
bash "$REPO_ROOT/install.sh" "$STALE_TARGET" >/dev/null 2>&1

# 9a: User files in .claude/commands/ that are NOT in the manifest
# should never be touched (stale removal only reads the manifest)
mkdir -p "$STALE_TARGET/.claude/commands"
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

# ── Test 9e: Upgrade does not emit false skip for kept kit files (#45) ───────
# Regression: .claude/prompts/* entries fell through the safety whitelist and
# printed "skip … refusing to remove" even though the files were in both the
# old and new manifests (no removal was actually going to happen).

echo ""
echo "── Test 9e: upgrade does not emit false skip for kept kit files (#45)"

PROMPTS_TARGET="$(make_temp)"
bash "$REPO_ROOT/install.sh" "$PROMPTS_TARGET" >/dev/null 2>&1

if grep -q "^\.claude/prompts/" "$PROMPTS_TARGET/.claude/.vallorcine-manifest" \
   && [[ -f "$PROMPTS_TARGET/.claude/prompts/audit/assembly.md" ]]; then
    pass "setup: kit prompts installed and listed in manifest"
else
    fail "setup: kit prompts should be installed and listed" \
        "manifest or prompt files missing"
fi

prompts_output="$(bash "$REPO_ROOT/upgrade.sh" \
    --apply \
    --kit-root "$REPO_ROOT" \
    --project-root "$PROMPTS_TARGET" \
    --from-version "$VERSION" \
    --to-version "$VERSION" 2>&1)"

if echo "$prompts_output" | grep "refusing to remove" | grep -q "\.claude/prompts/"; then
    fail "upgrade emits false skip for kit prompt paths" \
        "$(echo "$prompts_output" | grep 'refusing to remove' | grep '\.claude/prompts/' | head -3)"
else
    pass "no false skip messages for kept kit prompts"
fi

if [[ -f "$PROMPTS_TARGET/.claude/prompts/audit/assembly.md" ]]; then
    pass "kit prompts preserved after upgrade"
else
    fail "kit prompts should be preserved after upgrade"
fi

# ── Test 9d: Install migrates stale commands/ to skills/ ──────────────────────

echo ""
echo "── Test 9d: Install migrates stale commands/ to skills/"

MIGRATE_TARGET="$(make_temp)"
cd "$MIGRATE_TARGET" && git init -q && cd "$REPO_ROOT"

# Simulate a pre-migration install with commands/ files
mkdir -p "$MIGRATE_TARGET/.claude/commands"
echo "# old research" > "$MIGRATE_TARGET/.claude/commands/research.md"
echo "# old feature-quick" > "$MIGRATE_TARGET/.claude/commands/feature-quick.md"
echo "# old architect" > "$MIGRATE_TARGET/.claude/commands/architect.md"
echo "# user custom tool" > "$MIGRATE_TARGET/.claude/commands/my-custom-tool.md"

bash "$REPO_ROOT/install.sh" "$MIGRATE_TARGET" >/dev/null 2>&1

# Kit commands that now have skills should be removed
if [[ ! -f "$MIGRATE_TARGET/.claude/commands/research.md" \
   && ! -f "$MIGRATE_TARGET/.claude/commands/feature-quick.md" \
   && ! -f "$MIGRATE_TARGET/.claude/commands/architect.md" ]]; then
    pass "install removes stale pre-migration command files"
else
    fail "install should remove stale command files that are now skills"
fi

# User commands that don't match a skill should be preserved
if [[ -f "$MIGRATE_TARGET/.claude/commands/my-custom-tool.md" ]]; then
    pass "install preserves user command files not matching skills"
else
    fail "install should preserve user commands that don't match skills"
fi

# ── Test 10: Uninstall removes kit files ──────────────────────────────────────

echo ""
echo "── Test 10: Uninstall removes kit files"

UNINSTALL_TARGET="$(make_temp)"
cd "$UNINSTALL_TARGET" && git init -q && cd "$REPO_ROOT"
bash "$REPO_ROOT/install.sh" "$UNINSTALL_TARGET" >/dev/null 2>&1

# Verify files exist before uninstall
if [[ -f "$UNINSTALL_TARGET/.claude/skills/feature-quick/SKILL.md" ]]; then
    :
else
    fail "pre-uninstall: kit files should exist"
fi

# Run uninstall
uninstall_output="$(bash "$UNINSTALL_TARGET/.claude/scripts/uninstall.sh" --yes 2>&1)"

# Check manifest files are gone
if [[ ! -f "$UNINSTALL_TARGET/.claude/skills/feature-quick/SKILL.md" \
   && ! -f "$UNINSTALL_TARGET/.claude/agents/architect-agent.md" \
   && ! -f "$UNINSTALL_TARGET/.claude/rules/kb-protocol.md" \
   && ! -f "$UNINSTALL_TARGET/.claude/scripts/token-usage.sh" \
   && ! -f "$UNINSTALL_TARGET/.claude/upgrade.sh" ]]; then
    pass "uninstall removes kit files"
else
    fail "uninstall should remove all kit files"
fi

# Check metadata is gone
if [[ ! -f "$UNINSTALL_TARGET/.claude/.vallorcine-version" \
   && ! -f "$UNINSTALL_TARGET/.claude/.vallorcine-manifest" \
   && ! -f "$UNINSTALL_TARGET/.claude/.vallorcine-source" ]]; then
    pass "uninstall removes metadata files"
else
    fail "uninstall should remove metadata files"
fi

# Self-delete: uninstall.sh should be gone too
if [[ ! -f "$UNINSTALL_TARGET/.claude/scripts/uninstall.sh" ]]; then
    pass "uninstall script self-deletes"
else
    fail "uninstall script should self-delete"
fi

# ── Test 11: Uninstall preserves user data ────────────────────────────────────

echo ""
echo "── Test 11: Uninstall preserves user data"

PRESERVE_TARGET="$(make_temp)"
cd "$PRESERVE_TARGET" && git init -q && cd "$REPO_ROOT"
bash "$REPO_ROOT/install.sh" "$PRESERVE_TARGET" >/dev/null 2>&1

# Create user data
mkdir -p "$PRESERVE_TARGET/.kb/apis/rest"
echo "# REST API" > "$PRESERVE_TARGET/.kb/apis/rest/endpoints.md"
mkdir -p "$PRESERVE_TARGET/.decisions/use-postgres"
echo "# Use Postgres" > "$PRESERVE_TARGET/.decisions/use-postgres/adr.md"
mkdir -p "$PRESERVE_TARGET/.feature/add-auth"
echo "# Auth feature" > "$PRESERVE_TARGET/.feature/add-auth/plan.md"
echo "# Project Context" > "$PRESERVE_TARGET/PROJECT-CONTEXT.md"

bash "$PRESERVE_TARGET/.claude/scripts/uninstall.sh" --yes >/dev/null 2>&1

if [[ -f "$PRESERVE_TARGET/.kb/apis/rest/endpoints.md" ]]; then
    pass "uninstall preserves .kb/ user data"
else
    fail "uninstall should preserve .kb/"
fi

if [[ -f "$PRESERVE_TARGET/.decisions/use-postgres/adr.md" ]]; then
    pass "uninstall preserves .decisions/ user data"
else
    fail "uninstall should preserve .decisions/"
fi

if [[ -f "$PRESERVE_TARGET/.feature/add-auth/plan.md" ]]; then
    pass "uninstall preserves .feature/ user data"
else
    fail "uninstall should preserve .feature/"
fi

if [[ -f "$PRESERVE_TARGET/PROJECT-CONTEXT.md" ]]; then
    pass "uninstall preserves PROJECT-CONTEXT.md"
else
    fail "uninstall should preserve PROJECT-CONTEXT.md"
fi

# ── Test 12: --dry-run makes no changes ───────────────────────────────────────

echo ""
echo "── Test 12: Uninstall --dry-run makes no changes"

DRYRUN_TARGET="$(make_temp)"
cd "$DRYRUN_TARGET" && git init -q && cd "$REPO_ROOT"
bash "$REPO_ROOT/install.sh" "$DRYRUN_TARGET" >/dev/null 2>&1

# Run dry-run
bash "$DRYRUN_TARGET/.claude/scripts/uninstall.sh" --dry-run >/dev/null 2>&1

# All files should still exist
if [[ -f "$DRYRUN_TARGET/.claude/skills/feature-quick/SKILL.md" \
   && -f "$DRYRUN_TARGET/.claude/agents/architect-agent.md" \
   && -f "$DRYRUN_TARGET/.claude/.vallorcine-version" \
   && -f "$DRYRUN_TARGET/.claude/scripts/uninstall.sh" ]]; then
    pass "--dry-run makes no changes"
else
    fail "--dry-run should not remove any files"
fi

# ── Test 13: Uninstall safety guard blocks repo root ──────────────────────────

echo ""
echo "── Test 13: Uninstall safety guard blocks repo root"

# Create a fake "vallorcine repo" with install.sh, VERSION, MANIFEST at root
# and place the uninstall script at .claude/scripts/ so PROJECT_ROOT resolves to root
GUARD_DIR="/tmp/vallorcine/test-guard-$$"
mkdir -p "$GUARD_DIR/.claude/scripts"
cp "$REPO_ROOT/scripts/uninstall.sh" "$GUARD_DIR/.claude/scripts/uninstall.sh"
touch "$GUARD_DIR/install.sh" "$GUARD_DIR/VERSION" "$GUARD_DIR/MANIFEST"

guard_output="$(bash "$GUARD_DIR/.claude/scripts/uninstall.sh" 2>&1 || true)"
rm -rf "$GUARD_DIR"

if echo "$guard_output" | grep -q "vallorcine source repository"; then
    pass "uninstall safety guard blocks repo root"
else
    fail "uninstall safety guard should block repo root" "output: $guard_output"
fi

# ── Test 14a: New wrapper scripts and enhanced implementations installed ──────

echo ""
echo "── Test 14a: Enhanced status line + token tracking files"

ENHANCED_TARGET="$(make_temp)"
cd "$ENHANCED_TARGET" && git init -q && cd "$REPO_ROOT"
bash "$REPO_ROOT/install.sh" "$ENHANCED_TARGET" >/dev/null 2>&1

# Check wrapper scripts exist
for f in statusline-wrapper.sh token-hook-wrapper.sh subagent-hook-wrapper.sh \
         subagent-hook.sh statusline.py statusline.js \
         token-stop-hook.py token-stop-hook.js \
         subagent-hook.py subagent-hook.js; do
    if [[ -f "$ENHANCED_TARGET/.claude/scripts/$f" ]]; then
        :
    else
        fail "enhanced script installed: $f"
    fi
done
pass "all enhanced scripts installed"

# Check settings.json uses wrapper commands
if assert_file_contains "$ENHANCED_TARGET/.claude/settings.json" "token-hook-wrapper.sh"; then
    pass "settings.json uses token-hook-wrapper.sh"
else
    fail "settings.json should reference token-hook-wrapper.sh"
fi

if assert_file_contains "$ENHANCED_TARGET/.claude/settings.json" "statusline-wrapper.sh"; then
    pass "settings.json uses statusline-wrapper.sh"
else
    fail "settings.json should reference statusline-wrapper.sh"
fi

# Check SubagentStart/SubagentStop hooks registered
if assert_file_contains "$ENHANCED_TARGET/.claude/settings.json" "SubagentStart"; then
    pass "SubagentStart hook registered in settings.json"
else
    fail "SubagentStart hook should be in settings.json"
fi

if assert_file_contains "$ENHANCED_TARGET/.claude/settings.json" "SubagentStop"; then
    pass "SubagentStop hook registered in settings.json"
else
    fail "SubagentStop hook should be in settings.json"
fi

if assert_file_contains "$ENHANCED_TARGET/.claude/settings.json" "subagent-hook-wrapper.sh"; then
    pass "subagent hooks use wrapper script"
else
    fail "subagent hooks should reference subagent-hook-wrapper.sh"
fi

# Check .subagent-state in gitignore
if assert_file_contains "$ENHANCED_TARGET/.gitignore" ".subagent-state"; then
    pass ".subagent-state in .gitignore"
else
    fail ".subagent-state should be in .gitignore"
fi

# Check __pycache__/ in gitignore (narrative scripts generate bytecache)
if assert_file_contains "$ENHANCED_TARGET/.gitignore" "__pycache__/"; then
    pass "__pycache__/ in .gitignore"
else
    fail "__pycache__/ should be in .gitignore"
fi

# spec-split runtime artifacts must be in the installer's gitignore template.
# Otherwise users commit per-machine rollback logs and transient plan JSON.
if assert_file_contains "$ENHANCED_TARGET/.gitignore" ".spec/.split-log/"; then
    pass ".spec/.split-log/ in .gitignore"
else
    fail ".spec/.split-log/ should be in .gitignore"
fi
if assert_file_contains "$ENHANCED_TARGET/.gitignore" ".spec/.split-plan.json"; then
    pass ".spec/.split-plan.json in .gitignore"
else
    fail ".spec/.split-plan.json should be in .gitignore"
fi

# Work-layer runtime artifacts: per-machine readiness cache and ephemeral
# decompose checkpoint must be gitignored. Otherwise readiness recomputed
# on each machine fights with itself in merge conflicts. Use grep -qxF
# because the entries contain literal `*` glob chars that assert_file_contains
# would interpret as regex quantifiers.
if grep -qxF ".work/*/_readiness.json" "$ENHANCED_TARGET/.gitignore"; then
    pass ".work/*/_readiness.json in .gitignore"
else
    fail ".work/*/_readiness.json should be in .gitignore"
fi
if grep -qxF ".work/*/_decompose-progress.md" "$ENHANCED_TARGET/.gitignore"; then
    pass ".work/*/_decompose-progress.md in .gitignore"
else
    fail ".work/*/_decompose-progress.md should be in .gitignore"
fi
if grep -qxF ".work/*/.work-resolve.lock" "$ENHANCED_TARGET/.gitignore"; then
    pass ".work/*/.work-resolve.lock in .gitignore"
else
    fail ".work/*/.work-resolve.lock should be in .gitignore"
fi
if grep -qxF ".work/*/_dispatch-*.json" "$ENHANCED_TARGET/.gitignore"; then
    pass ".work/*/_dispatch-*.json in .gitignore"
else
    fail ".work/*/_dispatch-*.json should be in .gitignore"
fi
if grep -qxF ".kb/_index.json" "$ENHANCED_TARGET/.gitignore"; then
    pass ".kb/_index.json in .gitignore"
else
    fail ".kb/_index.json should be in .gitignore"
fi

# Upgrade path: an existing install that already has the runtime block but
# was made before v0.16.x should pick up the new entries on re-install.
UPGRADE_GI_TARGET="$(make_temp)"
mkdir -p "$UPGRADE_GI_TARGET"
cat > "$UPGRADE_GI_TARGET/.gitignore" << 'PRELEGACY'
# vallorcine runtime files — generated at runtime, not committed
.claude/.statusline-baseline
.claude/.token-state
.claude/.token-checkpoint
.claude/.subagent-state
.feature/
.curate/
__pycache__/
PRELEGACY

bash "$REPO_ROOT/install.sh" "$UPGRADE_GI_TARGET" >/dev/null 2>&1 || true

if grep -qxF ".spec/.split-log/" "$UPGRADE_GI_TARGET/.gitignore"; then
    pass "upgrade path adds .spec/.split-log/ to existing .gitignore"
else
    fail "upgrade should add .spec/.split-log/ to existing .gitignore"
fi
if grep -qxF ".spec/.split-plan.json" "$UPGRADE_GI_TARGET/.gitignore"; then
    pass "upgrade path adds .spec/.split-plan.json to existing .gitignore"
else
    fail "upgrade should add .spec/.split-plan.json to existing .gitignore"
fi
if grep -qxF ".work/*/_readiness.json" "$UPGRADE_GI_TARGET/.gitignore"; then
    pass "upgrade path adds .work/*/_readiness.json to existing .gitignore"
else
    fail "upgrade should add .work/*/_readiness.json to existing .gitignore"
fi
if grep -qxF ".work/*/_decompose-progress.md" "$UPGRADE_GI_TARGET/.gitignore"; then
    pass "upgrade path adds .work/*/_decompose-progress.md to existing .gitignore"
else
    fail "upgrade should add .work/*/_decompose-progress.md to existing .gitignore"
fi
if grep -qxF ".work/*/.work-resolve.lock" "$UPGRADE_GI_TARGET/.gitignore"; then
    pass "upgrade path adds .work/*/.work-resolve.lock to existing .gitignore"
else
    fail "upgrade should add .work/*/.work-resolve.lock to existing .gitignore"
fi
if grep -qxF ".work/*/_dispatch-*.json" "$UPGRADE_GI_TARGET/.gitignore"; then
    pass "upgrade path adds .work/*/_dispatch-*.json to existing .gitignore"
else
    fail "upgrade should add .work/*/_dispatch-*.json to existing .gitignore"
fi
if grep -qxF ".kb/_index.json" "$UPGRADE_GI_TARGET/.gitignore"; then
    pass "upgrade path adds .kb/_index.json to existing .gitignore"
else
    fail "upgrade should add .kb/_index.json to existing .gitignore"
fi
# Idempotent: running install twice must not duplicate entries.
bash "$REPO_ROOT/install.sh" "$UPGRADE_GI_TARGET" >/dev/null 2>&1 || true
splitlog_count="$(grep -cxF '.spec/.split-log/' "$UPGRADE_GI_TARGET/.gitignore")"
if (( splitlog_count == 1 )); then
    pass "re-running install does not duplicate .spec/.split-log/ entry"
else
    fail "expected 1 .spec/.split-log/ entry after second install, got $splitlog_count"
fi

# ── Test 14b: Migration from old direct references to wrappers ────────────────

echo ""
echo "── Test 14b: Migration from direct scripts to wrappers"

MIGRATE_HOOKS_TARGET="$(make_temp)"
cd "$MIGRATE_HOOKS_TARGET" && git init -q && cd "$REPO_ROOT"

# Simulate an old-style install with direct script references
mkdir -p "$MIGRATE_HOOKS_TARGET/.claude/scripts"
cat > "$MIGRATE_HOOKS_TARGET/.claude/settings.json" << 'OLDJSON'
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/scripts/token-stop-hook.sh"
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "bash .claude/scripts/statusline.sh"
  }
}
OLDJSON

bash "$REPO_ROOT/install.sh" "$MIGRATE_HOOKS_TARGET" >/dev/null 2>&1

if assert_file_contains "$MIGRATE_HOOKS_TARGET/.claude/settings.json" "token-hook-wrapper.sh"; then
    pass "migration: Stop hook updated to wrapper"
else
    fail "migration: Stop hook should be updated to wrapper"
fi

if assert_file_contains "$MIGRATE_HOOKS_TARGET/.claude/settings.json" "statusline-wrapper.sh"; then
    pass "migration: statusline updated to wrapper"
else
    fail "migration: statusline should be updated to wrapper"
fi

# ── Test 14: Uninstall cleans git config + .gitattributes ─────────────────────

echo ""
echo "── Test 14: Uninstall cleans git config + .gitattributes"

GITCLEAN_TARGET="$(make_temp)"
cd "$GITCLEAN_TARGET" && git init -q && cd "$REPO_ROOT"
bash "$REPO_ROOT/install.sh" "$GITCLEAN_TARGET" >/dev/null 2>&1

# Verify git config was set by install
if git -C "$GITCLEAN_TARGET" config --get merge.vallorcine-index.name >/dev/null 2>&1; then
    :
else
    fail "pre-uninstall: merge driver should be configured"
fi

bash "$GITCLEAN_TARGET/.claude/scripts/uninstall.sh" --yes >/dev/null 2>&1

# Check git config is cleaned
if ! git -C "$GITCLEAN_TARGET" config --get merge.vallorcine-index.name >/dev/null 2>&1; then
    pass "uninstall removes git merge driver config"
else
    fail "uninstall should remove merge driver config"
fi

# Check .gitattributes is cleaned
if [[ -f "$GITCLEAN_TARGET/.gitattributes" ]]; then
    if ! grep -qF "vallorcine" "$GITCLEAN_TARGET/.gitattributes" 2>/dev/null; then
        pass "uninstall cleans .gitattributes"
    else
        fail "uninstall should remove vallorcine entries from .gitattributes"
    fi
else
    pass "uninstall cleans .gitattributes (file removed — was empty)"
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
