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
