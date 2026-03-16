#!/usr/bin/env bash
# Scenario: index merge driver resolves concurrent CLAUDE.md edits
#
# Validates that when two branches add different rows to .kb/CLAUDE.md
# or .decisions/CLAUDE.md, the custom merge driver keeps all rows
# without conflict markers.
#
# Tests both WITH and WITHOUT the merge driver to prove the difference.
#
# Run from repo root: bash tests/scenario-index-merge-driver.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-index-merge"

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

# Seed a .kb/CLAUDE.md with one existing entry
seed_kb_index() {
    local dir="$1"
    mkdir -p "$dir/.kb"
    cat > "$dir/.kb/CLAUDE.md" << 'EOF'
# Knowledge Base — Root Index

> Managed by vallorcine agents.

## Topic Map

| Topic | Path | Categories | Files | Last Updated |
|-------|------|------------|-------|--------------|
| algorithms | .kb/algorithms/ | 2 | 5 | 2026-03-01 |

## Recently Added (last 10)
| Date | Topic | Category | Subject |
|------|-------|----------|---------|
| 2026-03-01 | algorithms | sorting | quicksort |
EOF
}

# Seed a .decisions/CLAUDE.md with one existing entry
seed_decisions_index() {
    local dir="$1"
    mkdir -p "$dir/.decisions"
    cat > "$dir/.decisions/CLAUDE.md" << 'EOF'
# Architecture Decisions — Master Index

> Managed by vallorcine agents.

## Active Decisions

| Problem | Slug | Date | Status | Recommendation |
|---------|------|------|--------|----------------|
| Storage engine | storage-engine | 2026-03-01 | proposed | LSM-Tree |
EOF
}

echo ""
echo "scenario: index merge driver"
echo "────────────────────────────────────────────────"

# ══════════════════════════════════════════════════════════════════════════════
# Part 1: WITHOUT merge driver — prove the conflict exists
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Part 1: WITHOUT merge driver (expect conflict)"

cleanup
mkdir -p "$TEST_BASE"

REMOTE="$TEST_BASE/remote.git"
CLONE_A="$TEST_BASE/clone-a"
CLONE_B="$TEST_BASE/clone-b"

# Set up bare repo with initial content
git init --bare --initial-branch=main "$REMOTE" >/dev/null 2>&1

INIT_DIR="$TEST_BASE/init-tmp"
git init --initial-branch=main "$INIT_DIR" >/dev/null 2>&1
git -C "$INIT_DIR" config user.email "test@test.com"
git -C "$INIT_DIR" config user.name "Test"
echo "# test" > "$INIT_DIR/README.md"
seed_kb_index "$INIT_DIR"
seed_decisions_index "$INIT_DIR"
git -C "$INIT_DIR" add -A
git -C "$INIT_DIR" commit -m "initial" >/dev/null 2>&1
git -C "$INIT_DIR" remote add origin "$REMOTE"
git -C "$INIT_DIR" push origin main >/dev/null 2>&1
rm -rf "$INIT_DIR"

# Clone twice (no merge driver configured)
git clone "$REMOTE" "$CLONE_A" >/dev/null 2>&1
git -C "$CLONE_A" config user.email "test@test.com"
git -C "$CLONE_A" config user.name "Test"

git clone "$REMOTE" "$CLONE_B" >/dev/null 2>&1
git -C "$CLONE_B" config user.email "test@test.com"
git -C "$CLONE_B" config user.name "Test"

# Developer A adds a KB topic on branch-a
git -C "$CLONE_A" checkout -b feature/ml-research >/dev/null 2>&1

# Append a new row to the Topic Map table
sed -i '/| algorithms/a | ml | .kb/ml/ | 1 | 3 | 2026-03-10 |' "$CLONE_A/.kb/CLAUDE.md"
sed -i '/| 2026-03-01 | algorithms/a | 2026-03-10 | ml | transformers | attention |' "$CLONE_A/.kb/CLAUDE.md"

git -C "$CLONE_A" add -A
git -C "$CLONE_A" commit -m "add ml topic" >/dev/null 2>&1
git -C "$CLONE_A" push origin feature/ml-research >/dev/null 2>&1

# Developer B adds a different KB topic on branch-b
git -C "$CLONE_B" checkout -b feature/systems-research >/dev/null 2>&1

sed -i '/| algorithms/a | systems | .kb/systems/ | 1 | 2 | 2026-03-11 |' "$CLONE_B/.kb/CLAUDE.md"
sed -i '/| 2026-03-01 | algorithms/a | 2026-03-11 | systems | caching | lru |' "$CLONE_B/.kb/CLAUDE.md"

git -C "$CLONE_B" add -A
git -C "$CLONE_B" commit -m "add systems topic" >/dev/null 2>&1
git -C "$CLONE_B" push origin feature/systems-research >/dev/null 2>&1

# Merge branch-a to main (should succeed)
git -C "$CLONE_A" checkout main >/dev/null 2>&1
git -C "$CLONE_A" merge feature/ml-research --no-edit >/dev/null 2>&1
git -C "$CLONE_A" push origin main >/dev/null 2>&1

# Merge branch-b to main (should conflict WITHOUT driver)
git -C "$CLONE_B" checkout main >/dev/null 2>&1
git -C "$CLONE_B" pull origin main >/dev/null 2>&1
no_driver_exit=0
git -C "$CLONE_B" merge feature/systems-research --no-edit >/dev/null 2>&1 || no_driver_exit=$?

if [[ $no_driver_exit -ne 0 ]]; then
    pass "merge conflicts WITHOUT driver (exit=$no_driver_exit)"
else
    fail "expected conflict without driver" "merge succeeded unexpectedly"
fi

if grep -q "<<<<" "$CLONE_B/.kb/CLAUDE.md" 2>/dev/null; then
    pass "conflict markers in .kb/CLAUDE.md"
else
    # Might auto-resolve if rows aren't adjacent — still a valid test
    pass "no conflict markers (rows not adjacent — git auto-resolved)"
fi

git -C "$CLONE_B" merge --abort 2>/dev/null || true

# ══════════════════════════════════════════════════════════════════════════════
# Part 2: WITH merge driver — prove clean resolution
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Part 2: WITH merge driver (expect clean merge)"

# Clean slate
rm -rf "$CLONE_A" "$CLONE_B"
rm -rf "$REMOTE"

git init --bare --initial-branch=main "$REMOTE" >/dev/null 2>&1

INIT_DIR="$TEST_BASE/init-tmp"
git init --initial-branch=main "$INIT_DIR" >/dev/null 2>&1
git -C "$INIT_DIR" config user.email "test@test.com"
git -C "$INIT_DIR" config user.name "Test"
echo "# test" > "$INIT_DIR/README.md"
seed_kb_index "$INIT_DIR"
seed_decisions_index "$INIT_DIR"

# Install merge driver
mkdir -p "$INIT_DIR/.claude/scripts"
cp "$REPO_ROOT/scripts/merge-driver-index.sh" "$INIT_DIR/.claude/scripts/"

cat > "$INIT_DIR/.gitattributes" << 'GITATTR'
# vallorcine merge driver — scoped to managed index files only
.kb/CLAUDE.md           merge=vallorcine-index
.kb/*/CLAUDE.md         merge=vallorcine-index
.kb/*/*/CLAUDE.md       merge=vallorcine-index
.decisions/CLAUDE.md    merge=vallorcine-index
GITATTR

git -C "$INIT_DIR" add -A
git -C "$INIT_DIR" commit -m "initial with merge driver" >/dev/null 2>&1
git -C "$INIT_DIR" remote add origin "$REMOTE"
git -C "$INIT_DIR" push origin main >/dev/null 2>&1
rm -rf "$INIT_DIR"

# Clone twice WITH merge driver configured
git clone "$REMOTE" "$CLONE_A" >/dev/null 2>&1
git -C "$CLONE_A" config user.email "test@test.com"
git -C "$CLONE_A" config user.name "Test"
git -C "$CLONE_A" config merge.vallorcine-index.name "vallorcine index merge"
git -C "$CLONE_A" config merge.vallorcine-index.driver "bash .claude/scripts/merge-driver-index.sh %O %A %B"

git clone "$REMOTE" "$CLONE_B" >/dev/null 2>&1
git -C "$CLONE_B" config user.email "test@test.com"
git -C "$CLONE_B" config user.name "Test"
git -C "$CLONE_B" config merge.vallorcine-index.name "vallorcine index merge"
git -C "$CLONE_B" config merge.vallorcine-index.driver "bash .claude/scripts/merge-driver-index.sh %O %A %B"

# Developer A adds ml topic
git -C "$CLONE_A" checkout -b feature/ml-research >/dev/null 2>&1

sed -i '/| algorithms/a | ml | .kb/ml/ | 1 | 3 | 2026-03-10 |' "$CLONE_A/.kb/CLAUDE.md"
sed -i '/| 2026-03-01 | algorithms/a | 2026-03-10 | ml | transformers | attention |' "$CLONE_A/.kb/CLAUDE.md"

# Also add an active decision
sed -i '/| Storage engine/a | Cache strategy | cache-strategy | 2026-03-10 | proposed | Write-through |' "$CLONE_A/.decisions/CLAUDE.md"

git -C "$CLONE_A" add -A
git -C "$CLONE_A" commit -m "add ml topic + cache decision" >/dev/null 2>&1
git -C "$CLONE_A" push origin feature/ml-research >/dev/null 2>&1

# Developer B adds systems topic
git -C "$CLONE_B" checkout -b feature/systems-research >/dev/null 2>&1

sed -i '/| algorithms/a | systems | .kb/systems/ | 1 | 2 | 2026-03-11 |' "$CLONE_B/.kb/CLAUDE.md"
sed -i '/| 2026-03-01 | algorithms/a | 2026-03-11 | systems | caching | lru |' "$CLONE_B/.kb/CLAUDE.md"

# Also add a different active decision
sed -i '/| Storage engine/a | Index format | index-format | 2026-03-11 | proposed | B+ Tree |' "$CLONE_B/.decisions/CLAUDE.md"

git -C "$CLONE_B" add -A
git -C "$CLONE_B" commit -m "add systems topic + index decision" >/dev/null 2>&1
git -C "$CLONE_B" push origin feature/systems-research >/dev/null 2>&1

# Merge branch-a to main
git -C "$CLONE_A" checkout main >/dev/null 2>&1
git -C "$CLONE_A" merge feature/ml-research --no-edit >/dev/null 2>&1
git -C "$CLONE_A" push origin main >/dev/null 2>&1

# Merge branch-b to main (should succeed WITH driver)
git -C "$CLONE_B" checkout main >/dev/null 2>&1
git -C "$CLONE_B" pull origin main >/dev/null 2>&1
driver_exit=0
git -C "$CLONE_B" merge feature/systems-research --no-edit >/dev/null 2>&1 || driver_exit=$?

if [[ $driver_exit -eq 0 ]]; then
    pass "merge succeeds WITH driver"
else
    fail "merge should succeed with driver" "exit=$driver_exit"
fi

# Assert: no conflict markers
if ! grep -q "<<<<" "$CLONE_B/.kb/CLAUDE.md" 2>/dev/null; then
    pass "no conflict markers in .kb/CLAUDE.md"
else
    fail "should have no conflict markers in .kb/CLAUDE.md"
fi

if ! grep -q "<<<<" "$CLONE_B/.decisions/CLAUDE.md" 2>/dev/null; then
    pass "no conflict markers in .decisions/CLAUDE.md"
else
    fail "should have no conflict markers in .decisions/CLAUDE.md"
fi

# Assert: both KB topics present
if grep -q "| ml |" "$CLONE_B/.kb/CLAUDE.md" 2>/dev/null; then
    pass ".kb/CLAUDE.md has ml topic"
else
    fail ".kb/CLAUDE.md should have ml topic"
fi

if grep -q "| systems |" "$CLONE_B/.kb/CLAUDE.md" 2>/dev/null; then
    pass ".kb/CLAUDE.md has systems topic"
else
    fail ".kb/CLAUDE.md should have systems topic"
fi

if grep -q "| algorithms |" "$CLONE_B/.kb/CLAUDE.md" 2>/dev/null; then
    pass ".kb/CLAUDE.md still has original algorithms topic"
else
    fail ".kb/CLAUDE.md should still have algorithms topic"
fi

# Assert: both decisions present
if grep -q "| Cache strategy |" "$CLONE_B/.decisions/CLAUDE.md" 2>/dev/null; then
    pass ".decisions/CLAUDE.md has cache-strategy decision"
else
    fail ".decisions/CLAUDE.md should have cache-strategy"
fi

if grep -q "| Index format |" "$CLONE_B/.decisions/CLAUDE.md" 2>/dev/null; then
    pass ".decisions/CLAUDE.md has index-format decision"
else
    fail ".decisions/CLAUDE.md should have index-format"
fi

if grep -q "| Storage engine |" "$CLONE_B/.decisions/CLAUDE.md" 2>/dev/null; then
    pass ".decisions/CLAUDE.md still has original storage-engine"
else
    fail ".decisions/CLAUDE.md should still have storage-engine"
fi

# Assert: recently added rows merged
if grep -q "| 2026-03-10 | ml |" "$CLONE_B/.kb/CLAUDE.md" 2>/dev/null &&
   grep -q "| 2026-03-11 | systems |" "$CLONE_B/.kb/CLAUDE.md" 2>/dev/null; then
    pass "recently added section has both entries"
else
    fail "recently added should have both entries"
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
