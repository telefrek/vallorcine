#!/usr/bin/env bash
# Scenario: decisions-scan.sh handles both YAML and markdown-style status
#
# Tests:
# 1. YAML frontmatter status: deferred is detected
# 2. Markdown-style **Status:** deferred is detected (fallback)
# 3. YAML status: accepted is detected
# 4. Mixed formats in same project all counted
# 5. Resume condition extraction works
#
# Run from repo root: bash tests/scenario-decisions-scan.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-decisions-scan"

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
echo "scenario: decisions-scan format handling"
echo "────────────────────────────────────────────────"

# ── Setup ────────────────────────────────────────────────────────────────────

cleanup
PROJ="$TEST_BASE/project"
mkdir -p "$PROJ/.decisions/yaml-deferred" "$PROJ/.decisions/markdown-deferred"
mkdir -p "$PROJ/.decisions/yaml-accepted" "$PROJ/.claude/scripts"

cp "$REPO_ROOT/scripts/decisions-scan.sh" "$PROJ/.claude/scripts/"

# Create YAML-style deferred ADR
cat > "$PROJ/.decisions/yaml-deferred/adr.md" << 'EOF'
---
problem: "yaml-deferred"
date: "2026-04-12"
version: 1
status: "deferred"
---

# YAML Deferred — Deferred

## Problem
Test YAML format.

## Resume When
When feature X is complete.
EOF

# Create markdown-style deferred ADR (the bug case)
cat > "$PROJ/.decisions/markdown-deferred/adr.md" << 'EOF'
# Markdown Deferred — Deferred

**Status:** deferred

## Problem
Test markdown format.

## Resume When
When feature Y ships.
EOF

# Create YAML-style accepted ADR
cat > "$PROJ/.decisions/yaml-accepted/adr.md" << 'EOF'
---
problem: "yaml-accepted"
date: "2026-04-12"
version: 1
status: "accepted"
---

# YAML Accepted

## Problem
Test accepted format.

## Decision
Use approach A.
EOF

# Create minimal CLAUDE.md index
cat > "$PROJ/.decisions/CLAUDE.md" << 'EOF'
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
| YAML format | yaml-deferred | 2026-04-12 | When feature X is complete |
| Markdown format | markdown-deferred | 2026-04-12 | When feature Y ships |
EOF

cd "$PROJ"

# ── Test 1: YAML status: deferred detected ──────────────────────────────────

echo ""
echo "── Test 1: YAML frontmatter status detected"

scan_output="$(bash .claude/scripts/decisions-scan.sh 2>&1)"
summary="$(cat .decisions/.roadmap-scan.md 2>/dev/null || true)"

if echo "$summary" | grep -q "yaml-deferred"; then
    pass "YAML frontmatter status: deferred detected"
else
    fail "YAML deferred should be in summary" "scan: $scan_output"
fi

# ── Test 2: Markdown-style **Status:** deferred detected ────────────────────

echo ""
echo "── Test 2: Markdown-style status detected (fallback)"

if echo "$summary" | grep -q "markdown-deferred"; then
    pass "markdown-style **Status:** deferred detected via fallback"
else
    fail "markdown-style deferred should be in summary" "summary: $(echo "$summary" | head -20)"
fi

# ── Test 3: Accepted status not counted as deferred ──────────────────────────

echo ""
echo "── Test 3: Accepted status not counted as deferred"

if ! echo "$summary" | grep "yaml-accepted" | grep -qi "deferred"; then
    pass "accepted ADR not counted as deferred"
else
    fail "accepted should not appear in deferred list"
fi

# ── Test 4: Total deferred count includes both formats ───────────────────────

echo ""
echo "── Test 4: Both formats counted in total"

if echo "$scan_output" | grep -qE "Deferred: 2"; then
    pass "both YAML and markdown deferred counted (2 total)"
else
    fail "should show Deferred: 2" "got: $scan_output"
fi

# ── Test 5: Resume condition tracking works ──────────────────────────────────

echo ""
echo "── Test 5: Resume condition tracking"

# The scan should report "Resume conditions met: 0 of 2" (neither is met)
if echo "$scan_output" | grep -q "Resume conditions met: 0"; then
    pass "resume conditions tracked (0 of 2 met)"
else
    fail "should track resume conditions" "got: $scan_output"
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
