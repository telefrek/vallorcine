#!/usr/bin/env bash
# Scenario: ADR contradiction detection
#
# Validates that adr-validate.sh detects duplicate accepted slugs in
# .decisions/CLAUDE.md and stays silent when no contradictions exist.
#
# Run from repo root: bash tests/scenario-adr-contradiction.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-adr-contradiction"

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
echo "scenario: ADR contradiction detection"
echo "────────────────────────────────────────────────"

# ── Setup ────────────────────────────────────────────────────────────────────

cleanup
mkdir -p "$TEST_BASE"

PROJECT="$TEST_BASE/project"
mkdir -p "$PROJECT/.decisions"

# Copy the script to the installed location
mkdir -p "$PROJECT/.claude/scripts"
cp "$REPO_ROOT/scripts/adr-validate.sh" "$PROJECT/.claude/scripts/adr-validate.sh"

# ── Test 1: no decisions index — silent ──────────────────────────────────────

echo ""
echo "── Test 1: no decisions index"

rm -f "$PROJECT/.decisions/CLAUDE.md"
output="$(cd "$PROJECT" && bash .claude/scripts/adr-validate.sh 2>&1)"
if [[ -z "$output" ]]; then
    pass "silent when no .decisions/CLAUDE.md"
else
    fail "should be silent without index" "got: $output"
fi

# ── Test 2: empty index — silent ─────────────────────────────────────────────

echo ""
echo "── Test 2: empty index"

cat > "$PROJECT/.decisions/CLAUDE.md" << 'EOF'
# Architecture Decisions — Master Index

## Active Decisions

| Problem | Slug | Date | Status | Recommendation |
|---------|------|------|--------|----------------|

## Recently Accepted (last 5)

| Problem | Slug | Accepted | Recommendation |
|---------|------|----------|----------------|
EOF

output="$(cd "$PROJECT" && bash .claude/scripts/adr-validate.sh 2>&1)"
if [[ -z "$output" ]]; then
    pass "silent with empty index"
else
    fail "should be silent with empty index" "got: $output"
fi

# ── Test 3: one accepted — silent ────────────────────────────────────────────

echo ""
echo "── Test 3: single accepted ADR"

cat > "$PROJECT/.decisions/CLAUDE.md" << 'EOF'
# Architecture Decisions — Master Index

## Active Decisions

| Problem | Slug | Date | Status | Recommendation |
|---------|------|------|--------|----------------|

## Recently Accepted (last 5)

| Problem | Slug | Accepted | Recommendation |
|---------|------|----------|----------------|
| Storage format | storage-format | 2026-03-01 | accepted | Use LSM-Tree |
EOF

output="$(cd "$PROJECT" && bash .claude/scripts/adr-validate.sh 2>&1)"
if [[ -z "$output" ]]; then
    pass "silent with one accepted ADR"
else
    fail "should be silent with single accepted" "got: $output"
fi

# ── Test 4: two different accepted — silent ──────────────────────────────────

echo ""
echo "── Test 4: two different accepted ADRs"

cat > "$PROJECT/.decisions/CLAUDE.md" << 'EOF'
# Architecture Decisions — Master Index

## Active Decisions

| Problem | Slug | Date | Status | Recommendation |
|---------|------|------|--------|----------------|
| Auth approach | auth-approach | 2026-03-10 | accepted | Use JWT |

## Recently Accepted (last 5)

| Problem | Slug | Accepted | Recommendation |
|---------|------|----------|----------------|
| Storage format | storage-format | 2026-03-01 | accepted | Use LSM-Tree |
EOF

output="$(cd "$PROJECT" && bash .claude/scripts/adr-validate.sh 2>&1)"
if [[ -z "$output" ]]; then
    pass "silent with two different accepted ADRs"
else
    fail "should be silent with different slugs" "got: $output"
fi

# ── Test 5: duplicate accepted slug — warns ──────────────────────────────────

echo ""
echo "── Test 5: duplicate accepted slug (contradiction)"

cat > "$PROJECT/.decisions/CLAUDE.md" << 'EOF'
# Architecture Decisions — Master Index

## Active Decisions

| Problem | Slug | Date | Status | Recommendation |
|---------|------|------|--------|----------------|
| Storage format v2 | storage-format | 2026-03-15 | accepted | Use B-Tree |

## Recently Accepted (last 5)

| Problem | Slug | Accepted | Recommendation |
|---------|------|----------|----------------|
| Storage format | storage-format | 2026-03-01 | accepted | Use LSM-Tree |
EOF

output="$(cd "$PROJECT" && bash .claude/scripts/adr-validate.sh 2>&1)"
if [[ -n "$output" ]]; then
    pass "warns on duplicate accepted slug"
else
    fail "should warn on contradiction" "got no output"
fi

if echo "$output" | grep -q "storage-format"; then
    pass "warning mentions the contradicting slug"
else
    fail "warning should mention slug" "got: $output"
fi

# ── Test 6: non-accepted duplicates — silent ─────────────────────────────────

echo ""
echo "── Test 6: duplicate slug but different statuses"

cat > "$PROJECT/.decisions/CLAUDE.md" << 'EOF'
# Architecture Decisions — Master Index

## Active Decisions

| Problem | Slug | Date | Status | Recommendation |
|---------|------|------|--------|----------------|
| Storage format v2 | storage-format | 2026-03-15 | proposed | Consider B-Tree |

## Recently Accepted (last 5)

| Problem | Slug | Accepted | Recommendation |
|---------|------|----------|----------------|
| Storage format | storage-format | 2026-03-01 | accepted | Use LSM-Tree |
EOF

output="$(cd "$PROJECT" && bash .claude/scripts/adr-validate.sh 2>&1)"
if [[ -z "$output" ]]; then
    pass "silent when duplicate slug has different status"
else
    fail "should be silent — only one is accepted" "got: $output"
fi

# ── Test 7: multiple contradictions — reports all ────────────────────────────

echo ""
echo "── Test 7: multiple contradictions"

cat > "$PROJECT/.decisions/CLAUDE.md" << 'EOF'
# Architecture Decisions — Master Index

## Active Decisions

| Problem | Slug | Date | Status | Recommendation |
|---------|------|------|--------|----------------|
| Storage format v2 | storage-format | 2026-03-15 | accepted | Use B-Tree |
| Auth v2 | auth-approach | 2026-03-15 | accepted | Use OAuth |

## Recently Accepted (last 5)

| Problem | Slug | Accepted | Recommendation |
|---------|------|----------|----------------|
| Storage format | storage-format | 2026-03-01 | accepted | Use LSM-Tree |
| Auth approach | auth-approach | 2026-03-05 | accepted | Use JWT |
EOF

output="$(cd "$PROJECT" && bash .claude/scripts/adr-validate.sh 2>&1)"
if echo "$output" | grep -q "storage-format"; then
    pass "reports storage-format contradiction"
else
    fail "should report storage-format" "got: $output"
fi

if echo "$output" | grep -q "auth-approach"; then
    pass "reports auth-approach contradiction"
else
    fail "should report auth-approach" "got: $output"
fi

if echo "$output" | grep -q "2 slug"; then
    pass "reports correct count of contradictions"
else
    fail "should report 2 contradictions" "got: $output"
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
