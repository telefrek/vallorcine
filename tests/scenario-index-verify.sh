#!/usr/bin/env bash
# Scenario: Index verification script detects and repairs inconsistencies
#
# Validates that index-verify.sh correctly:
# - Stays silent when indexes are consistent
# - Detects missing topic rows in .kb/CLAUDE.md
# - Detects missing ADR rows in .decisions/CLAUDE.md
# - Repairs missing rows (adds them)
# - Handles empty indexes with existing directories
# - Handles non-existent directories gracefully
# - Respects --kb and --decisions flags
#
# Run from repo root: bash tests/scenario-index-verify.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-index-verify"

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
echo "scenario: index verification"
echo "────────────────────────────────────────────────"

# ── Setup ────────────────────────────────────────────────────────────────────

cleanup
mkdir -p "$TEST_BASE"

PROJECT="$TEST_BASE/project"
mkdir -p "$PROJECT/.claude/scripts"
cp "$REPO_ROOT/scripts/index-verify.sh" "$PROJECT/.claude/scripts/"

# Create KB structure with empty root index
mkdir -p "$PROJECT/.kb/algorithms/vector-indexing"
mkdir -p "$PROJECT/.kb/systems/caching"

# Create KB root index (empty topic map)
cat > "$PROJECT/.kb/CLAUDE.md" << 'EOF'
# Knowledge Base — Root Index

## Topic Map

| Topic | Path | Categories | Files | Last Updated |
|-------|------|------------|-------|--------------|

## Recently Added (last 10)
| Date | Topic | Category | Subject |
|------|-------|----------|---------|
EOF

# Create subject files
cat > "$PROJECT/.kb/algorithms/vector-indexing/hnsw.md" << 'EOF'
---
title: "HNSW"
last_researched: "2026-03-17"
---
# HNSW
## summary
A graph-based ANN algorithm.
EOF

cat > "$PROJECT/.kb/systems/caching/redis.md" << 'EOF'
---
title: "Redis"
last_researched: "2026-03-16"
---
# Redis
## summary
In-memory data store.
EOF

# Create category CLAUDE.md files
cat > "$PROJECT/.kb/algorithms/vector-indexing/CLAUDE.md" << 'EOF'
# Vector Indexing — Category Index
## Contents
| File | Subject |
|------|---------|
| hnsw.md | HNSW |
EOF

# Create decisions structure with empty index
mkdir -p "$PROJECT/.decisions/rate-limiting"

cat > "$PROJECT/.decisions/CLAUDE.md" << 'EOF'
# Architecture Decisions — Master Index

## Active Decisions

| Problem | Slug | Date | Status | Recommendation |
|---------|------|------|--------|----------------|

## Recently Accepted (last 5)

| Problem | Slug | Accepted | Recommendation |
|---------|------|----------|----------------|

## Deferred

| Problem | Slug | Deferred | Resume When |
|---------|------|----------|-------------|

## Closed

| Problem | Slug | Closed | Reason |
|---------|------|--------|--------|
EOF

cat > "$PROJECT/.decisions/rate-limiting/adr.md" << 'EOF'
---
problem: "rate-limiting"
date: "2026-03-15"
version: 1
status: "confirmed"
---

# ADR — Rate Limiting

## Decision
**Chosen approach: Token bucket with Redis**

## Conditions for Revision
- If request rate exceeds 10K RPS
EOF

pass "project with inconsistent indexes created"

# ── Test 1: Detects missing KB topic ─────────────────────────────────────────

echo ""
echo "── Test 1: Detects missing KB topic rows"

output="$(cd "$PROJECT" && bash .claude/scripts/index-verify.sh --kb 2>&1)"

if echo "$output" | grep -q "algorithms"; then
    pass "detects missing 'algorithms' topic"
else
    fail "should detect missing algorithms topic" "got: $output"
fi

if echo "$output" | grep -q "systems"; then
    pass "detects missing 'systems' topic"
else
    fail "should detect missing systems topic" "got: $output"
fi

# ── Test 2: Repairs KB index ─────────────────────────────────────────────────

echo ""
echo "── Test 2: Repairs KB index"

if grep -q "algorithms" "$PROJECT/.kb/CLAUDE.md"; then
    pass "algorithms row added to KB index"
else
    fail "algorithms row should be in KB index after repair"
fi

if grep -q "systems" "$PROJECT/.kb/CLAUDE.md"; then
    pass "systems row added to KB index"
else
    fail "systems row should be in KB index after repair"
fi

# ── Test 3: Detects missing ADR ──────────────────────────────────────────────

echo ""
echo "── Test 3: Detects missing ADR rows"

output="$(cd "$PROJECT" && bash .claude/scripts/index-verify.sh --decisions 2>&1)"

if echo "$output" | grep -q "rate-limiting"; then
    pass "detects missing 'rate-limiting' ADR"
else
    fail "should detect missing rate-limiting ADR" "got: $output"
fi

# ── Test 4: Repairs decisions index ──────────────────────────────────────────

echo ""
echo "── Test 4: Repairs decisions index"

if grep -q "rate-limiting" "$PROJECT/.decisions/CLAUDE.md"; then
    pass "rate-limiting row added to decisions index"
else
    fail "rate-limiting row should be in decisions index after repair"
fi

# ── Test 5: Silent when consistent ───────────────────────────────────────────

echo ""
echo "── Test 5: Silent when indexes are consistent"

# Run again — should find nothing to repair
output="$(cd "$PROJECT" && bash .claude/scripts/index-verify.sh --both 2>&1)"

if [[ -z "$output" ]]; then
    pass "silent when indexes are already consistent"
else
    # May report "repair(s) made" if Recently Added was rebuilt
    if echo "$output" | grep -q "repair"; then
        pass "only rebuilds Recently Added (acceptable)"
    else
        fail "should be silent on consistent indexes" "got: $output"
    fi
fi

# ── Test 6: Handles missing directories ──────────────────────────────────────

echo ""
echo "── Test 6: Handles missing directories gracefully"

EMPTY="$TEST_BASE/empty"
mkdir -p "$EMPTY/.claude/scripts"
cp "$REPO_ROOT/scripts/index-verify.sh" "$EMPTY/.claude/scripts/"

output="$(cd "$EMPTY" && bash .claude/scripts/index-verify.sh --both 2>&1)"
if [[ -z "$output" ]]; then
    pass "silent when .kb/ and .decisions/ don't exist"
else
    fail "should be silent with no directories" "got: $output"
fi

# ── Test 7: --kb flag only checks KB ─────────────────────────────────────────

echo ""
echo "── Test 7: --kb flag scopes to KB only"

# Create a new project with only decisions issues
SCOPED="$TEST_BASE/scoped"
mkdir -p "$SCOPED/.claude/scripts" "$SCOPED/.decisions/test-decision"
cp "$REPO_ROOT/scripts/index-verify.sh" "$SCOPED/.claude/scripts/"

cat > "$SCOPED/.decisions/CLAUDE.md" << 'EOF'
# Architecture Decisions — Master Index
## Recently Accepted (last 5)
| Problem | Slug | Accepted | Recommendation |
|---------|------|----------|----------------|
EOF

cat > "$SCOPED/.decisions/test-decision/adr.md" << 'EOF'
---
problem: "test-decision"
date: "2026-03-15"
status: "confirmed"
---
# Test Decision
## Decision
**Chosen approach: Test**
EOF

output="$(cd "$SCOPED" && bash .claude/scripts/index-verify.sh --kb 2>&1)"
if [[ -z "$output" ]]; then
    pass "--kb flag doesn't check decisions"
else
    fail "--kb should only check KB" "got: $output"
fi

# ── Test 8: Deferred ADR gets correct section ───────────────────────────────

echo ""
echo "── Test 8: Deferred ADR added to correct section"

mkdir -p "$PROJECT/.decisions/cache-strategy"
cat > "$PROJECT/.decisions/cache-strategy/adr.md" << 'EOF'
---
problem: "cache-strategy"
date: "2026-03-16"
status: "deferred"
---
# Cache Strategy — Deferred
## Problem
How to cache API responses.
## Resume When
After v2 launch.
EOF

output="$(cd "$PROJECT" && bash .claude/scripts/index-verify.sh --decisions 2>&1)"

if grep -q "cache-strategy" "$PROJECT/.decisions/CLAUDE.md"; then
    pass "deferred ADR added to decisions index"
else
    fail "cache-strategy should be added to decisions index"
fi

# Verify it's in the Deferred section, not Recently Accepted
deferred_section="$(sed -n '/## Deferred/,/^## /p' "$PROJECT/.decisions/CLAUDE.md")"
if echo "$deferred_section" | grep -q "cache-strategy"; then
    pass "deferred ADR in correct section"
else
    fail "cache-strategy should be in Deferred section, not elsewhere"
fi

# ── Test 9: Recently Accepted overflows to history.md when over cap ─────────
# Regression: prior to v0.16.x, when auto-repair stacked many "confirmed"
# ADRs into Recently Accepted, the file blew the 80-line cap and the script
# only warned. The cap exists because CLAUDE.md is loaded into context;
# silent growth burns tokens. Overflow keeps the newest rows in the index
# and archives the rest to history.md.

echo ""
echo "── Test 9: Recently Accepted overflows to history.md when over 80-line cap"

OVERFLOW_DIR="/tmp/vallorcine/scenario-overflow"
rm -rf "$OVERFLOW_DIR" 2>/dev/null || true
mkdir -p "$OVERFLOW_DIR/.claude/scripts" "$OVERFLOW_DIR/.decisions"
cp "$REPO_ROOT/scripts/index-verify.sh" "$OVERFLOW_DIR/.claude/scripts/"

# Build a CLAUDE.md with many Recently Accepted rows — enough to blow 80
# lines. 30 rows + headers + other sections ≈ 95 lines.
{
    cat << 'HEAD'
# Architecture Decisions — Master Index

## Active Decisions
| Problem | Slug | Date | Status | Recommendation |
|---------|------|------|--------|----------------|

## Recently Accepted (last 5)
| Problem | Slug | Accepted | Recommendation |
|---------|------|----------|----------------|
HEAD
    for n in $(seq 1 90); do
        d=$(printf "2026-01-%02d" $((n % 28 + 1)))
        echo "| Problem $n | adr-$n | $d | Choose option $n |"
    done
    cat << 'TAIL'

## Deferred
| Problem | Slug | Deferred | Resume When |
|---------|------|----------|-------------|

## Closed
| Problem | Slug | Closed | Reason |
|---------|------|--------|--------|
TAIL
} > "$OVERFLOW_DIR/.decisions/CLAUDE.md"

before_lines="$(wc -l < "$OVERFLOW_DIR/.decisions/CLAUDE.md")"
if (( before_lines <= 80 )); then
    fail "test setup wrong: file is only $before_lines lines, won't trigger cap"
fi

(cd "$OVERFLOW_DIR" && bash .claude/scripts/index-verify.sh --decisions 2>&1) >/tmp/index-verify-overflow.out

after_lines="$(wc -l < "$OVERFLOW_DIR/.decisions/CLAUDE.md")"
if (( after_lines <= 80 )); then
    pass "CLAUDE.md trimmed to $after_lines lines (under 80-line cap)"
else
    fail "CLAUDE.md still over cap after overflow ($after_lines lines)"
fi

if [[ -f "$OVERFLOW_DIR/.decisions/history.md" ]]; then
    pass "history.md created on first overflow"
else
    fail "history.md should have been created"
fi

# 90 rows started, default keep=5 → 85 rows should land in history.md.
# Match `Problem <digit>` to avoid catching the Active Decisions table
# header `| Problem | Slug | …`.
hist_rows="$(grep -cE '^\| Problem [0-9]' "$OVERFLOW_DIR/.decisions/history.md" 2>/dev/null || echo 0)"
if (( hist_rows == 85 )); then
    pass "history.md received 85 archived rows (kept 5, archived 85)"
else
    fail "expected 85 archived rows in history.md, got $hist_rows"
fi

# Newest 5 rows should remain in the index.
remaining_rows="$(grep -cE '^\| Problem [0-9]' "$OVERFLOW_DIR/.decisions/CLAUDE.md" 2>/dev/null || echo 0)"
if (( remaining_rows == 5 )); then
    pass "5 most recent rows remain in CLAUDE.md"
else
    fail "expected 5 remaining rows in CLAUDE.md, got $remaining_rows"
fi

# VALLORCINE_DECISIONS_KEEP env var should change the cap.
rm -rf "$OVERFLOW_DIR/.decisions/history.md"
{
    cat << 'HEAD'
# Architecture Decisions — Master Index

## Active Decisions
| Problem | Slug | Date | Status | Recommendation |
|---------|------|------|--------|----------------|

## Recently Accepted (last 5)
| Problem | Slug | Accepted | Recommendation |
|---------|------|----------|----------------|
HEAD
    for n in $(seq 1 90); do
        echo "| P$n | adr-$n | 2026-01-01 | reco$n |"
    done
    echo ""
    echo "## Deferred"
    echo "| Problem | Slug | Deferred | Resume When |"
    echo "|---------|------|----------|-------------|"
} > "$OVERFLOW_DIR/.decisions/CLAUDE.md"

(cd "$OVERFLOW_DIR" && VALLORCINE_DECISIONS_KEEP=10 bash .claude/scripts/index-verify.sh --decisions 2>&1) >/dev/null

remaining="$(grep -cE '^\| P[0-9]+ ' "$OVERFLOW_DIR/.decisions/CLAUDE.md" 2>/dev/null || echo 0)"
if (( remaining == 10 )); then
    pass "VALLORCINE_DECISIONS_KEEP=10 retains 10 rows"
else
    fail "VALLORCINE_DECISIONS_KEEP override failed (kept $remaining instead of 10)"
fi

rm -rf "$OVERFLOW_DIR" 2>/dev/null || true

# ── Test 9b: overflow keeps the DATE-newest rows, not document-newest ───────
# Regression for the 2026-05-10 jlsm bug: /curate rotated newer ADRs
# (2026-04-26 et al.) out of "Recently Accepted" and pulled older ADRs
# (2026-03-19 et al.) in. Root cause: the overflow trimmed from the bottom
# assuming "newest is at the top," but auto-repair inserted missing rows
# on top in filesystem order regardless of their accepted_at date. The
# fix sorts the section by date desc before applying the cap.
# This test specifically arranges document-order ≠ date-order so a
# position-trimming implementation fails while a date-sorting one passes.

echo ""
echo "── Test 9b: Recently Accepted survivors selected by DATE, not document order"

ORDER_DIR="/tmp/vallorcine/scenario-overflow-order"
rm -rf "$ORDER_DIR" 2>/dev/null || true
mkdir -p "$ORDER_DIR/.claude/scripts" "$ORDER_DIR/.decisions"
cp "$REPO_ROOT/scripts/index-verify.sh" "$ORDER_DIR/.claude/scripts/"

# Build a CLAUDE.md where the OLDER rows appear at the TOP and NEWER rows
# at the BOTTOM — the opposite of the "newest first" assumption the old
# overflow logic baked in. With 90 rows + the other sections we'll hit
# the 80-line cap and trigger overflow.
{
    cat << 'HEAD'
# Architecture Decisions — Master Index

## Active Decisions
| Problem | Slug | Date | Status | Recommendation |
|---------|------|------|--------|----------------|

## Recently Accepted (last 5)
| Problem | Slug | Accepted | Recommendation |
|---------|------|----------|----------------|
HEAD
    # Rows 1..85 are OLD (2026-01-*). Rows 86..90 are the NEW ones that
    # SHOULD survive (2026-04-*). They live at the BOTTOM of the table.
    for n in $(seq 1 85); do
        d=$(printf "2026-01-%02d" $((n % 28 + 1)))
        echo "| Old $n | adr-old-$n | $d | reco old $n |"
    done
    for n in $(seq 1 5); do
        d=$(printf "2026-04-%02d" $((n * 5)))
        echo "| New $n | adr-new-$n | $d | reco new $n |"
    done
    cat << 'TAIL'

## Deferred
| Problem | Slug | Deferred | Resume When |
|---------|------|----------|-------------|

## Closed
| Problem | Slug | Closed | Reason |
|---------|------|--------|--------|
TAIL
} > "$ORDER_DIR/.decisions/CLAUDE.md"

(cd "$ORDER_DIR" && bash .claude/scripts/index-verify.sh --decisions 2>&1) >/tmp/index-verify-order.out

# All 5 "New" rows (2026-04-*) should survive in CLAUDE.md.
new_survivors="$(grep -cE '^\| New [0-9]+ \|' "$ORDER_DIR/.decisions/CLAUDE.md" 2>/dev/null; true)"
new_survivors="${new_survivors:-0}"
if (( new_survivors == 5 )); then
    pass "all 5 date-newest rows survive in CLAUDE.md (sort-by-date works)"
else
    fail "expected 5 'New' rows surviving, got $new_survivors" \
         "(this is the 2026-05-10 jlsm bug shape)"
fi

# All 85 "Old" rows (2026-01-*) should be in history.md.
old_archived="$(grep -cE '^\| Old [0-9]+ \|' "$ORDER_DIR/.decisions/history.md" 2>/dev/null; true)"
old_archived="${old_archived:-0}"
if (( old_archived == 85 )); then
    pass "all 85 date-older rows archived to history.md"
else
    fail "expected 85 'Old' rows archived, got $old_archived"
fi

# Zero "New" rows in history.md (would mean we archived newer rows — the bug).
new_archived="$(grep -cE '^\| New [0-9]+ \|' "$ORDER_DIR/.decisions/history.md" 2>/dev/null; true)"
new_archived="${new_archived:-0}"
if (( new_archived == 0 )); then
    pass "zero 'New' rows leaked into history (no inversion bug)"
else
    fail "$new_archived 'New' rows got archived (date-newer should never be archived)"
fi

# Sanity: the surviving 5 rows should be ordered date-desc (newest at top).
# The fixture has New 1..5 with dates 2026-04-05, -10, -15, -20, -25.
# After sort desc: New 5 (-25), New 4 (-20), New 3 (-15), New 2 (-10), New 1 (-05).
first_remaining="$(grep -m1 -E '^\| New [0-9]+ \|' "$ORDER_DIR/.decisions/CLAUDE.md")"
if echo "$first_remaining" | grep -qF "New 5"; then
    pass "first surviving row is the date-newest (New 5, 2026-04-25)"
else
    fail "expected 'New 5' first, got: $first_remaining"
fi

rm -rf "$ORDER_DIR" 2>/dev/null || true

# ── Test 10: under-cap files unchanged ──────────────────────────────────────

echo ""
echo "── Test 10: under-cap CLAUDE.md left untouched"

UNDERCAP_DIR="/tmp/vallorcine/scenario-undercap"
rm -rf "$UNDERCAP_DIR" 2>/dev/null || true
mkdir -p "$UNDERCAP_DIR/.claude/scripts" "$UNDERCAP_DIR/.decisions"
cp "$REPO_ROOT/scripts/index-verify.sh" "$UNDERCAP_DIR/.claude/scripts/"

cat > "$UNDERCAP_DIR/.decisions/CLAUDE.md" << 'EOF'
# Architecture Decisions — Master Index

## Active Decisions
| Problem | Slug | Date | Status | Recommendation |
|---------|------|------|--------|----------------|

## Recently Accepted (last 5)
| Problem | Slug | Accepted | Recommendation |
|---------|------|----------|----------------|
| One thing | adr-1 | 2026-01-01 | reco-1 |
| Two thing | adr-2 | 2026-01-02 | reco-2 |

## Deferred
| Problem | Slug | Deferred | Resume When |
|---------|------|----------|-------------|

## Closed
| Problem | Slug | Closed | Reason |
|---------|------|--------|--------|
EOF

before_md5="$(md5sum "$UNDERCAP_DIR/.decisions/CLAUDE.md" | cut -d' ' -f1)"
(cd "$UNDERCAP_DIR" && bash .claude/scripts/index-verify.sh --decisions 2>&1) >/dev/null
after_md5="$(md5sum "$UNDERCAP_DIR/.decisions/CLAUDE.md" | cut -d' ' -f1)"

if [[ "$before_md5" == "$after_md5" ]]; then
    pass "under-cap CLAUDE.md left untouched"
else
    fail "under-cap file was modified unnecessarily"
fi

if [[ ! -f "$UNDERCAP_DIR/.decisions/history.md" ]]; then
    pass "history.md not created when under cap"
else
    fail "history.md should not be created when under cap"
fi

rm -rf "$UNDERCAP_DIR" 2>/dev/null || true

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
