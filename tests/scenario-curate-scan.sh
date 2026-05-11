#!/usr/bin/env bash
# Scenario: Curation scan script produces correct output
#
# Validates that curate-scan.sh correctly:
# - Runs on a fresh repo (--init mode)
# - Identifies churn hotspots
# - Identifies co-change clusters
# - Correlates against ADR artifacts with file references
# - Correlates against KB artifacts with applies_to references
# - Identifies orphaned high-churn files
# - Detects stale KB entries
# - Detects ADRs with revisit conditions
# - Handles incremental scanning (skips when no new commits)
# - Handles incremental scanning (picks up new commits)
# - Respects --window flag
# - Handles non-git directories gracefully
# - Detects ADR pressure (2+ constrained files changed)
# - Detects ADR gravity (unconstrained files co-changing with ADR scope)
# - Excludes test files from gravity signals
# - Detects hub files (co-changing with 3+ ADRs)
# - Separates hub files from gravity signals
# - Calculates pressure percentage
#
# Run from repo root: bash tests/scenario-curate-scan.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-curate-scan"

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
echo "scenario: curation scan"
echo "────────────────────────────────────────────────"

# ── Setup: create a project with git history ─────────────────────────────────

cleanup
mkdir -p "$TEST_BASE"

PROJECT="$TEST_BASE/project"
git init --initial-branch=main "$PROJECT" >/dev/null 2>&1
git -C "$PROJECT" config user.email "test@test.com"
git -C "$PROJECT" config user.name "Test"

# Install the scan script
mkdir -p "$PROJECT/.claude/scripts"
cp "$REPO_ROOT/scripts/curate-scan.sh" "$PROJECT/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$PROJECT/.claude/scripts/"

# Create initial files
mkdir -p "$PROJECT/src/auth" "$PROJECT/src/billing" "$PROJECT/src/utils" "$PROJECT/lib"
echo "module.exports = {}" > "$PROJECT/src/auth/session.ts"
echo "module.exports = {}" > "$PROJECT/src/auth/middleware.ts"
echo "module.exports = {}" > "$PROJECT/src/billing/stripe.ts"
echo "module.exports = {}" > "$PROJECT/src/utils/helpers.ts"
echo "module.exports = {}" > "$PROJECT/lib/db.ts"
echo "# test" > "$PROJECT/README.md"

git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "initial commit" >/dev/null 2>&1

# Create churn: auth files change together frequently
for i in $(seq 1 5); do
    echo "// change $i" >> "$PROJECT/src/auth/session.ts"
    echo "// change $i" >> "$PROJECT/src/auth/middleware.ts"
    git -C "$PROJECT" add -A
    git -C "$PROJECT" commit -m "auth update $i" >/dev/null 2>&1
done

# Create some billing changes (less frequent)
for i in $(seq 1 3); do
    echo "// change $i" >> "$PROJECT/src/billing/stripe.ts"
    git -C "$PROJECT" add -A
    git -C "$PROJECT" commit -m "billing fix $i" >/dev/null 2>&1
done

# Create some co-changes between auth and db
for i in $(seq 1 4); do
    echo "// db change $i" >> "$PROJECT/lib/db.ts"
    echo "// session db $i" >> "$PROJECT/src/auth/session.ts"
    git -C "$PROJECT" add -A
    git -C "$PROJECT" commit -m "session + db update $i" >/dev/null 2>&1
done

pass "project with git history created (12 commits)"

# ── Test 1: Basic --init scan ────────────────────────────────────────────────

echo ""
echo "── Test 1: Basic --init scan"

output="$(cd "$PROJECT" && bash .claude/scripts/curate-scan.sh --init 2>&1)"
if echo "$output" | grep -q "Scan complete"; then
    pass "scan completes successfully"
else
    fail "scan should complete" "got: $output"
fi

if [[ -f "$PROJECT/.curate/scan-summary.md" ]]; then
    pass "scan-summary.md created"
else
    fail "scan-summary.md should exist"
fi

# ── Test 2: Churn hotspots detected ─────────────────────────────────────────

echo ""
echo "── Test 2: Churn hotspots"

if grep -q "src/auth/session.ts" "$PROJECT/.curate/scan-summary.md"; then
    pass "session.ts appears in churn hotspots"
else
    fail "session.ts should be a churn hotspot"
fi

if grep -q "src/auth/middleware.ts" "$PROJECT/.curate/scan-summary.md"; then
    pass "middleware.ts appears in churn hotspots"
else
    fail "middleware.ts should be a churn hotspot"
fi

# ── Test 3: Co-change clusters detected ──────────────────────────────────────

echo ""
echo "── Test 3: Co-change clusters"

if grep -q "Co-change Clusters" "$PROJECT/.curate/scan-summary.md"; then
    pass "co-change section present"
else
    fail "co-change section should be present"
fi

# auth/session.ts and auth/middleware.ts should co-change (5 commits together)
if grep -q "session.ts" "$PROJECT/.curate/scan-summary.md" && grep -q "middleware.ts" "$PROJECT/.curate/scan-summary.md"; then
    pass "auth files appear in co-change data"
else
    fail "auth session + middleware should co-change"
fi

# ── Test 4: Orphaned areas (no artifacts = everything is orphaned) ───────────

echo ""
echo "── Test 4: Orphaned areas on cold start"

if grep -q "Orphaned Areas" "$PROJECT/.curate/scan-summary.md"; then
    pass "orphaned areas section present"
else
    fail "orphaned areas should be present (no artifacts exist)"
fi

# ── Test 5: ADR artifact correlation ─────────────────────────────────────────

echo ""
echo "── Test 5: ADR artifact correlation"

# Create an ADR that references auth files
mkdir -p "$PROJECT/.decisions/session-storage"
cat > "$PROJECT/.decisions/session-storage/adr.md" << 'EOF'
---
problem: "session-storage"
date: "2026-03-01"
version: 1
status: "confirmed"
files:
  - "src/auth/session.ts"
  - "src/auth/middleware.ts"
---

# ADR — Session Storage

## Files Constrained by This Decision
- src/auth/session.ts
- src/auth/middleware.ts

## Problem
How to store session tokens.

## Decision
Use middleware-based session handling.

## Conditions for Revision
- If session volume exceeds 10K concurrent
EOF

git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "add session-storage ADR" >/dev/null 2>&1

# Add another auth change after the ADR
echo "// post-adr change" >> "$PROJECT/src/auth/session.ts"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "auth change after ADR" >/dev/null 2>&1

# Re-scan
cd "$PROJECT" && bash .claude/scripts/curate-scan.sh --init >/dev/null 2>&1

if grep -q "Artifact Correlations" "$PROJECT/.curate/scan-summary.md"; then
    pass "artifact correlations section present"
else
    fail "artifact correlations should appear"
fi

if grep -q "ADR" "$PROJECT/.curate/scan-summary.md" && grep -q "session-storage" "$PROJECT/.curate/scan-summary.md"; then
    pass "ADR session-storage correlated with changed files"
else
    fail "should correlate ADR with changed auth files"
fi

# ── Test 6: KB artifact correlation ──────────────────────────────────────────

echo ""
echo "── Test 6: KB artifact correlation"

# Create a KB entry that references billing files
mkdir -p "$PROJECT/.kb/systems/payments"
cat > "$PROJECT/.kb/systems/payments/stripe-integration.md" << 'EOF'
---
title: "Stripe Integration"
topic: "systems"
category: "payments"
applies_to:
  - "src/billing/stripe.ts"
research_status: "mature"
last_researched: "2025-06-01"
---

# Stripe Integration

## summary
How we integrate with Stripe.
EOF

git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "add stripe KB entry" >/dev/null 2>&1

# Re-scan
cd "$PROJECT" && bash .claude/scripts/curate-scan.sh --init >/dev/null 2>&1

if grep -q "KB" "$PROJECT/.curate/scan-summary.md" && grep -q "stripe" "$PROJECT/.curate/scan-summary.md"; then
    pass "KB stripe entry correlated with changed files"
else
    fail "should correlate KB entry with changed billing files"
fi

# ── Test 7: Stale KB detection ──────────────────────────────────────────────

echo ""
echo "── Test 7: Stale KB detection"

if grep -q "Stale KB Entries" "$PROJECT/.curate/scan-summary.md"; then
    pass "stale KB section present"
else
    fail "stripe entry (last_researched 2025-06-01) should be stale"
fi

if grep -q "stripe-integration" "$PROJECT/.curate/scan-summary.md" && grep -q "2025-06-01" "$PROJECT/.curate/scan-summary.md"; then
    pass "stripe entry identified as stale with correct date"
else
    fail "should identify stripe entry with last_researched date"
fi

# ── Test 8: ADR revisit conditions ───────────────────────────────────────────

echo ""
echo "── Test 8: ADR revisit conditions"

if grep -q "ADRs With Revisit Conditions" "$PROJECT/.curate/scan-summary.md"; then
    pass "ADR revisit section present"
else
    fail "session-storage ADR has revisit conditions"
fi

if grep -q "session-storage" "$PROJECT/.curate/scan-summary.md"; then
    pass "session-storage ADR flagged for revisit"
else
    fail "should flag session-storage for revisit"
fi

# ── Test 9: Incremental scan — no new commits ───────────────────────────────

echo ""
echo "── Test 9: Incremental scan (no new commits)"

# Create curation-state.md with current HEAD
CURRENT_SHA="$(git -C "$PROJECT" rev-parse HEAD)"
mkdir -p "$PROJECT/.curate"
cat > "$PROJECT/.curate/curation-state.md" << EOF
# Curation State

## Scan State
Last scanned: $CURRENT_SHA
Last scanned date: 2026-03-18
EOF

output="$(cd "$PROJECT" && bash .claude/scripts/curate-scan.sh 2>&1)"
if echo "$output" | grep -q "No new commits"; then
    pass "skips when no new commits"
else
    fail "should skip when HEAD matches last scan" "got: $output"
fi

# ── Test 10: Incremental scan — picks up new commits ────────────────────────

echo ""
echo "── Test 10: Incremental scan (new commits)"

echo "// new change" >> "$PROJECT/src/utils/helpers.ts"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "utils update" >/dev/null 2>&1

output="$(cd "$PROJECT" && bash .claude/scripts/curate-scan.sh 2>&1)"
if echo "$output" | grep -q "Scan complete"; then
    pass "processes new commits incrementally"
else
    fail "should process new commits" "got: $output"
fi

if grep -q "src/utils/helpers.ts" "$PROJECT/.curate/scan-summary.md"; then
    pass "new change appears in summary"
else
    fail "helpers.ts should appear in incremental scan"
fi

# ── Test 11: --window flag ───────────────────────────────────────────────────

echo ""
echo "── Test 11: --window flag"

output="$(cd "$PROJECT" && bash .claude/scripts/curate-scan.sh --init --window 1 2>&1)"
if echo "$output" | grep -q "Scan complete"; then
    pass "--window 1 completes successfully"
else
    fail "--window flag should work" "got: $output"
fi

# ── Test 12: Non-git directory ───────────────────────────────────────────────

echo ""
echo "── Test 12: Non-git directory"

NO_GIT="$TEST_BASE/no-git"
mkdir -p "$NO_GIT/.claude/scripts"
cp "$REPO_ROOT/scripts/curate-scan.sh" "$NO_GIT/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$NO_GIT/.claude/scripts/"

output="$(cd "$NO_GIT" && bash .claude/scripts/curate-scan.sh --init 2>&1)" || true
if echo "$output" | grep -q "not a git repository"; then
    pass "errors on non-git directory"
else
    fail "should error on non-git directory" "got: $output"
fi

# ── Test 13: Orphaned vs covered files ───────────────────────────────────────

echo ""
echo "── Test 13: Covered files not in orphaned list"

# Re-scan with artifacts in place
cd "$PROJECT" && bash .claude/scripts/curate-scan.sh --init >/dev/null 2>&1

# session.ts is referenced by ADR — should NOT be in orphaned list
orphaned_section="$(sed -n '/## Orphaned Areas/,/^## /p' "$PROJECT/.curate/scan-summary.md")"
if echo "$orphaned_section" | grep -q "src/auth/session.ts"; then
    fail "session.ts should not be orphaned (covered by ADR)"
else
    pass "session.ts not in orphaned list (covered by ADR)"
fi

# helpers.ts has no coverage — should be in orphaned list
if echo "$orphaned_section" | grep -q "src/utils/helpers.ts"; then
    pass "helpers.ts correctly identified as orphaned"
else
    fail "helpers.ts should be orphaned (no coverage)"
fi

# ── Test 14: Large commit filtering ─────────────────────────────────────────

echo ""
echo "── Test 14: Large commits excluded from co-change"

# The initial commit touches many files but shouldn't poison co-change analysis
# (it has <50 files so it won't trigger, but we verify the mechanism works)
# Just verify the script doesn't crash with the filtering logic
output="$(cd "$PROJECT" && bash .claude/scripts/curate-scan.sh --init --max-commits 100 2>&1)"
if echo "$output" | grep -q "Scan complete"; then
    pass "large commit filter doesn't break scan"
else
    fail "scan should complete with large commit filter" "got: $output"
fi

# ── Test 15: ADR Pressure ────────────────────────────────────────────────────

echo ""
echo "── Test 15: ADR Pressure"

# session-storage ADR constrains session.ts and middleware.ts — both changed
cd "$PROJECT" && bash .claude/scripts/curate-scan.sh --init >/dev/null 2>&1

if grep -q "ADR Pressure" "$PROJECT/.curate/scan-summary.md"; then
    pass "ADR Pressure section present"
else
    fail "ADR Pressure section should appear (session-storage has 2+ changed files)"
fi

if grep -q "session-storage" "$PROJECT/.curate/scan-summary.md" | head -1 && \
   sed -n '/## ADR Pressure/,/^## /p' "$PROJECT/.curate/scan-summary.md" | grep -q "session-storage"; then
    pass "session-storage ADR appears in pressure table"
else
    fail "session-storage should be under pressure (both constrained files changed)"
fi

# ── Test 16: ADR Gravity ────────────────────────────────────────────────────

echo ""
echo "── Test 16: ADR Gravity"

# lib/db.ts co-changes with src/auth/session.ts (4 commits together)
# session.ts is constrained by session-storage ADR, db.ts is not
# → db.ts should be a gravity signal for session-storage

gravity_section="$(sed -n '/## ADR Gravity/,/^## /p' "$PROJECT/.curate/scan-summary.md")"
if [[ -n "$gravity_section" ]]; then
    pass "ADR Gravity section present"
else
    fail "ADR Gravity section should appear (db.ts co-changes with ADR-constrained session.ts)"
fi

if echo "$gravity_section" | grep -q "db.ts"; then
    pass "db.ts identified as gravity signal for session-storage"
else
    fail "db.ts should be gravitationally linked to session-storage ADR"
fi

# ── Test 17: Test files excluded from gravity ───────────────────────────────

echo ""
echo "── Test 17: Test files excluded from gravity"

# Create a test file that co-changes with auth files
mkdir -p "$PROJECT/tests"
for i in $(seq 1 4); do
    echo "// test change $i" >> "$PROJECT/tests/session.test.ts"
    echo "// paired $i" >> "$PROJECT/src/auth/session.ts"
    git -C "$PROJECT" add -A
    git -C "$PROJECT" commit -m "test + session $i" >/dev/null 2>&1
done

cd "$PROJECT" && bash .claude/scripts/curate-scan.sh --init >/dev/null 2>&1

gravity_section="$(sed -n '/## ADR Gravity/,/^## /p' "$PROJECT/.curate/scan-summary.md")"
if echo "$gravity_section" | grep -q "session.test.ts"; then
    fail "test files should be excluded from gravity (unconstrained side)"
else
    pass "test files correctly excluded from gravity signals"
fi

# ── Test 18: Hub file detection ─────────────────────────────────────────────

echo ""
echo "── Test 18: Hub file detection"

# Create two more ADRs constraining different files
mkdir -p "$PROJECT/.decisions/billing-model"
cat > "$PROJECT/.decisions/billing-model/adr.md" << 'EOF'
---
problem: "billing-model"
date: "2026-03-01"
status: "confirmed"
---

# ADR — Billing Model

## Files Constrained by This Decision
- src/billing/stripe.ts

## Decision
Use Stripe for payments.
EOF

mkdir -p "$PROJECT/.decisions/db-connection"
cat > "$PROJECT/.decisions/db-connection/adr.md" << 'EOF'
---
problem: "db-connection"
date: "2026-03-01"
status: "confirmed"
---

# ADR — DB Connection

## Files Constrained by This Decision
- lib/db.ts

## Decision
Use connection pooling.
EOF

git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "add billing and db ADRs" >/dev/null 2>&1

# Create a shared config file that co-changes with files from all 3 ADRs
echo "config = {}" > "$PROJECT/src/config.ts"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "add config" >/dev/null 2>&1

for i in $(seq 1 4); do
    echo "// config $i" >> "$PROJECT/src/config.ts"
    echo "// auth cfg $i" >> "$PROJECT/src/auth/session.ts"
    git -C "$PROJECT" add -A
    git -C "$PROJECT" commit -m "config + auth $i" >/dev/null 2>&1
done

for i in $(seq 1 4); do
    echo "// config billing $i" >> "$PROJECT/src/config.ts"
    echo "// billing cfg $i" >> "$PROJECT/src/billing/stripe.ts"
    git -C "$PROJECT" add -A
    git -C "$PROJECT" commit -m "config + billing $i" >/dev/null 2>&1
done

for i in $(seq 1 4); do
    echo "// config db $i" >> "$PROJECT/src/config.ts"
    echo "// db cfg $i" >> "$PROJECT/lib/db.ts"
    git -C "$PROJECT" add -A
    git -C "$PROJECT" commit -m "config + db $i" >/dev/null 2>&1
done

cd "$PROJECT" && bash .claude/scripts/curate-scan.sh --init >/dev/null 2>&1

if grep -q "Hub Files" "$PROJECT/.curate/scan-summary.md"; then
    pass "Hub Files section present"
else
    fail "Hub Files section should appear (config.ts co-changes with 3 ADRs' files)"
fi

hub_section="$(sed -n '/## Hub Files/,/^## /p' "$PROJECT/.curate/scan-summary.md")"
if echo "$hub_section" | grep -q "config.ts"; then
    pass "config.ts identified as hub file"
else
    fail "config.ts should be a hub file (co-changes with 3+ ADRs' constrained files)"
fi

# Hub file should NOT appear in gravity section
gravity_section="$(sed -n '/## ADR Gravity/,/^## /p' "$PROJECT/.curate/scan-summary.md")"
if echo "$gravity_section" | grep -q "config.ts"; then
    fail "hub files should not appear in gravity (they're separated)"
else
    pass "hub file correctly excluded from gravity signals"
fi

# ── Test 19: Pressure percentage ────────────────────────────────────────────

echo ""
echo "── Test 19: Pressure percentage calculation"

pressure_section="$(sed -n '/## ADR Pressure/,/^## /p' "$PROJECT/.curate/scan-summary.md")"
if echo "$pressure_section" | grep -q "%"; then
    pass "pressure percentage is calculated"
else
    fail "pressure table should include percentage"
fi

# ── Test 20: .curate directory auto-created ──────────────────────────────────

echo ""
echo "── Test 20: .curate directory auto-created"

FRESH="$TEST_BASE/fresh"
git init --initial-branch=main "$FRESH" >/dev/null 2>&1
git -C "$FRESH" config user.email "test@test.com"
git -C "$FRESH" config user.name "Test"
echo "test" > "$FRESH/README.md"
git -C "$FRESH" add -A
git -C "$FRESH" commit -m "init" >/dev/null 2>&1

mkdir -p "$FRESH/.claude/scripts"
cp "$REPO_ROOT/scripts/curate-scan.sh" "$FRESH/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$FRESH/.claude/scripts/"

cd "$FRESH" && bash .claude/scripts/curate-scan.sh --init >/dev/null 2>&1

if [[ -d "$FRESH/.curate" ]]; then
    pass ".curate/ directory auto-created"
else
    fail ".curate/ should be created automatically"
fi

# ── Test 21: Out-of-scope items from accepted ADRs ──────────────────────────

echo ""
echo "── Test 21: Out-of-scope extraction (Analysis 9)"

# Add a "What This Decision Does NOT Solve" section to an existing ADR
cat >> "$PROJECT/.decisions/session-storage/adr.md" << 'EOF'

## What This Decision Does NOT Solve
- Session replication across regions — separate decision needed
- Session encryption at rest — can layer on later
- Rate limiting per session — not needed at current scale

## Conditions for Revision
This ADR should be re-evaluated if sessions exceed 1M concurrent.
EOF

git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "add out-of-scope to session-storage ADR" >/dev/null 2>&1

cd "$PROJECT" && bash .claude/scripts/curate-scan.sh --init >/dev/null 2>&1

if grep -q "Out-of-Scope Items" "$PROJECT/.curate/scan-summary.md"; then
    pass "Out-of-Scope Items section present in summary"
else
    fail "Out-of-Scope Items section should appear"
fi

oos_section="$(sed -n '/## Out-of-Scope Items/,/^## /p' "$PROJECT/.curate/scan-summary.md")"
if echo "$oos_section" | grep -q "Session replication across regions"; then
    pass "out-of-scope item 1 extracted correctly"
else
    fail "should extract 'Session replication across regions'"
fi

if echo "$oos_section" | grep -q "Session encryption at rest"; then
    pass "out-of-scope item 2 extracted correctly"
else
    fail "should extract 'Session encryption at rest'"
fi

if echo "$oos_section" | grep -q "session-storage"; then
    pass "parent ADR slug present in output"
else
    fail "parent ADR slug should be in the output table"
fi

# ── Test 22: Out-of-scope deduplication ─────────────────────────────────────

echo ""
echo "── Test 22: Out-of-scope deduplication"

# Create a deferred stub for one of the items — it should not appear on next scan
mkdir -p "$PROJECT/.decisions/session-replication-across-regions"
cat > "$PROJECT/.decisions/session-replication-across-regions/adr.md" << 'EOF'
---
problem: "session-replication-across-regions"
date: "2026-03-20"
status: "deferred"
---
# Session Replication Across Regions — Deferred
## Problem
Session replication across regions
## Why Deferred
Scoped out during session-storage decision.
## Resume When
Not specified.
EOF

git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "add deferred stub for session replication" >/dev/null 2>&1

cd "$PROJECT" && bash .claude/scripts/curate-scan.sh --init >/dev/null 2>&1

oos_section="$(sed -n '/## Out-of-Scope Items/,/^## /p' "$PROJECT/.curate/scan-summary.md")"
if echo "$oos_section" | grep -q "Session replication across regions"; then
    fail "deduplication failed — stubbed item should not appear"
else
    pass "stubbed out-of-scope item correctly deduplicated"
fi

# The other two items should still appear
if echo "$oos_section" | grep -q "Session encryption at rest"; then
    pass "non-stubbed items still present after deduplication"
else
    fail "non-stubbed items should still appear"
fi

# ── Test 23: Template placeholders skipped ──────────────────────────────────

echo ""
echo "── Test 23: Template placeholders skipped"

mkdir -p "$PROJECT/.decisions/placeholder-test"
cat > "$PROJECT/.decisions/placeholder-test/adr.md" << 'EOF'
---
problem: "placeholder-test"
date: "2026-03-20"
status: "confirmed"
---
# Placeholder Test

## What This Decision Does NOT Solve
- <Limitation 1 — be explicit about scope>
- <Limitation 2>
- Real concern that should appear — genuine limitation

## Conditions for Revision
None.
EOF

git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "add ADR with template placeholders" >/dev/null 2>&1

cd "$PROJECT" && bash .claude/scripts/curate-scan.sh --init >/dev/null 2>&1

oos_section="$(sed -n '/## Out-of-Scope Items/,/^## /p' "$PROJECT/.curate/scan-summary.md")"
if echo "$oos_section" | grep -q "Limitation 1"; then
    fail "template placeholders should be skipped"
else
    pass "template placeholders correctly skipped"
fi

if echo "$oos_section" | grep -q "Real concern that should appear"; then
    pass "real items still extracted alongside placeholders"
else
    fail "real items should still be extracted"
fi

# ── Test 24: grep pipefail in ADR pressure (no file references) ─────────────

echo ""
echo "── Test 24: ADR with no file-path references doesn't crash pressure calc"

# Create an ADR with no file-path-like strings in its body
mkdir -p "$PROJECT/.decisions/no-file-refs"
cat > "$PROJECT/.decisions/no-file-refs/adr.md" << 'EOF'
---
problem: "no-file-refs"
date: "2026-03-01"
status: "confirmed"
---

# ADR — No File References

## Problem
How to handle something abstract with no file references at all.

## Decision
Use a conceptual approach with no specific files constrained.
EOF

git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "add ADR with no file references" >/dev/null 2>&1

output="$(cd "$PROJECT" && bash .claude/scripts/curate-scan.sh --init 2>&1)"
if echo "$output" | grep -q "Scan complete"; then
    pass "scan succeeds with ADR containing no file-path references"
else
    fail "grep pipefail: ADR with no file references crashes scan" "got: $output"
fi

# ── Test 25: test-drift grep -c doesn't break integer comparison ────────────

echo ""
echo "── Test 25: test-drift with source file not in churn.txt"

# Create a source file that changed but has zero churn entries
# (simulates grep -c returning 0 — the old || echo 0 bug)
mkdir -p "$PROJECT/src/new"
echo "new module" > "$PROJECT/src/new/fresh.ts"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "add fresh source file" >/dev/null 2>&1

# Incremental scan — fresh.ts appears as changed but has minimal churn
output="$(cd "$PROJECT" && bash .claude/scripts/curate-scan.sh --init 2>&1)"
if echo "$output" | grep -q "Scan complete"; then
    pass "scan succeeds when source files have zero churn matches"
else
    fail "grep -c newline bug: integer comparison fails on zero-match files" "got: $output"
fi

# ── Test 26: Orphaned spec detection (Analysis 14) ──────────────────────────

echo ""
echo "── Test 26: Orphaned spec detection (APPROVED spec with no matching source)"

# Use a fresh project to avoid interference with Analysis 10's spec parsing
ORPHAN_PROJECT="$TEST_BASE/orphan-project"
git init --initial-branch=main "$ORPHAN_PROJECT" >/dev/null 2>&1
git -C "$ORPHAN_PROJECT" config user.email "test@test.com"
git -C "$ORPHAN_PROJECT" config user.name "Test"

mkdir -p "$ORPHAN_PROJECT/.claude/scripts"
cp "$REPO_ROOT/scripts/curate-scan.sh" "$ORPHAN_PROJECT/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$ORPHAN_PROJECT/.claude/scripts/"

# Create source files first
mkdir -p "$ORPHAN_PROJECT/src/auth"
echo "class SessionManager { constructor() {} }" > "$ORPHAN_PROJECT/src/auth/session.ts"
echo "module.exports = {}" > "$ORPHAN_PROJECT/README.md"

# Create spec infrastructure with two APPROVED specs:
# - F01 references "SessionManager" which exists in source
# - F02 references "YamlParser" which does NOT exist in any source file
mkdir -p "$ORPHAN_PROJECT/.spec/registry"
mkdir -p "$ORPHAN_PROJECT/.spec/domains/auth"
mkdir -p "$ORPHAN_PROJECT/.spec/domains/serialization"

cat > "$ORPHAN_PROJECT/.spec/registry/manifest.json" << 'SPECEOF'
{
  "domains": {
    "auth": { "description": "authentication", "feature_count": 1 },
    "serialization": { "description": "data format support", "feature_count": 1 }
  },
  "features": {
    "F01": { "latest_file": "domains/auth/F01-session-management.md", "state": "APPROVED", "domains": ["auth"] },
    "F02": { "latest_file": "domains/serialization/F02-yaml-support.md", "state": "APPROVED", "domains": ["serialization"] }
  }
}
SPECEOF

cat > "$ORPHAN_PROJECT/.spec/domains/auth/F01-session-management.md" << 'SPECEOF'
---
{
  "id": "F01",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["auth"],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": [],
  "open_obligations": []
}
---

# F01 — Session Management

## Requirements
R1. The SessionManager must create sessions with unique identifiers.

---

## Design Narrative

### Intent
Session management for auth.
SPECEOF

cat > "$ORPHAN_PROJECT/.spec/domains/serialization/F02-yaml-support.md" << 'SPECEOF'
---
{
  "id": "F02",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["serialization"],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": [],
  "open_obligations": []
}
---

# F02 — YAML Support

## Requirements
R1. The YamlParser must accept valid YAML input.

---

## Design Narrative

### Intent
YAML format support — but no code exists for it anymore.
SPECEOF

git -C "$ORPHAN_PROJECT" add -A
git -C "$ORPHAN_PROJECT" commit -m "initial with specs and source" >/dev/null 2>&1

# Add a few commits for churn (scan requires commits to analyze)
for i in $(seq 1 3); do
    echo "// change $i" >> "$ORPHAN_PROJECT/src/auth/session.ts"
    git -C "$ORPHAN_PROJECT" add -A
    git -C "$ORPHAN_PROJECT" commit -m "auth update $i" >/dev/null 2>&1
done

cd "$ORPHAN_PROJECT" && bash .claude/scripts/curate-scan.sh --init >/dev/null 2>&1

# F02 (YamlParser) should be flagged as orphaned
if grep -q "Orphaned specs" "$ORPHAN_PROJECT/.curate/scan-summary.md" 2>/dev/null; then
    pass "Orphaned specs section present in summary"
else
    fail "should detect orphaned specs section"
fi

orphaned_section="$(sed -n '/### Orphaned specs/,/^#/p' "$ORPHAN_PROJECT/.curate/scan-summary.md" 2>/dev/null || true)"
if echo "$orphaned_section" | grep -q "F02"; then
    pass "F02 (YamlParser) correctly identified as orphaned"
else
    fail "F02 should be orphaned (YamlParser not in source)" "section: $orphaned_section"
fi

# F01 (SessionManager) should NOT be orphaned
if echo "$orphaned_section" | grep -q "F01"; then
    fail "F01 should not be orphaned (SessionManager exists in source)"
else
    pass "F01 (SessionManager) correctly not orphaned"
fi

# Report line should show orphaned count
output="$(cd "$ORPHAN_PROJECT" && bash .claude/scripts/curate-scan.sh --init 2>&1)"
if echo "$output" | grep -q "Orphaned specs:"; then
    pass "orphaned spec count in report output"
else
    fail "should report orphaned spec count" "got: $output"
fi

# ── Test 27: grep -c pipefail regression (zero-match produces clean integer)
# Bug: grep -c with zero matches exits 1 and outputs "0". When combined with
# || echo 0 inside $(...), the fallback fires and produces "0\n0" which fails
# integer comparison. Fix: var="$(grep -c ...)" || var=0

echo ""
echo "── Test 27: grep -c pipefail regression"

GREP_TEST_DIR="/tmp/vallorcine/grep-c-test"
rm -rf "$GREP_TEST_DIR" 2>/dev/null || true
mkdir -p "$GREP_TEST_DIR"

# Create a file with no matching lines
echo "no hex hashes here" > "$GREP_TEST_DIR/empty-log.txt"

# Test the fixed pattern: should produce clean integer "0", not "0\n0"
RESULT="$(grep -cE '^[0-9a-f]{40}$' "$GREP_TEST_DIR/empty-log.txt" 2>/dev/null)" || RESULT=0
if [[ "$RESULT" == "0" ]] && (( RESULT == 0 )); then
    pass "grep -c zero-match produces clean integer (commit count pattern)"
else
    fail "grep -c zero-match should produce '0'" "got: '$RESULT'"
fi

# Test the churn pattern with no matches
echo "unrelated content" > "$GREP_TEST_DIR/churn.txt"
SRC_RESULT="$(grep -c "nonexistent-file.java" "$GREP_TEST_DIR/churn.txt" 2>/dev/null)" || SRC_RESULT=0
if [[ "$SRC_RESULT" == "0" ]] && (( SRC_RESULT == 0 )); then
    pass "grep -c zero-match produces clean integer (churn pattern)"
else
    fail "grep -c churn zero-match should produce '0'" "got: '$SRC_RESULT'"
fi

# Test the obligation count pattern with no matching lines
OB_RESULT="$(echo "" | tr ',' '\n' | grep -c '[a-z]' 2>/dev/null)" || OB_RESULT=1
if (( OB_RESULT >= 0 )); then
    pass "grep -c obligation pattern produces valid integer"
else
    fail "grep -c obligation pattern should produce valid integer" "got: '$OB_RESULT'"
fi

rm -rf "$GREP_TEST_DIR" 2>/dev/null || true

# ── Test 28: Obligation registry scanning ─────────────────────────────────────

echo ""
echo "── Test 28: Obligation registry scanning"

OB_TEST_DIR="/tmp/vallorcine/scenario-ob-registry"
rm -rf "$OB_TEST_DIR" 2>/dev/null || true
mkdir -p "$OB_TEST_DIR/.curate"
mkdir -p "$OB_TEST_DIR/.spec/registry"
mkdir -p "$OB_TEST_DIR/.spec/domains/engine"
mkdir -p "$OB_TEST_DIR/.claude/scripts"

cp "$REPO_ROOT/scripts/curate-scan.sh" "$OB_TEST_DIR/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$OB_TEST_DIR/.claude/scripts/"

cd "$OB_TEST_DIR"
git init -q .
git add -A && git commit -q -m "init" --allow-empty

# Create obligation registry with 2 open and 1 resolved obligation
cat > .spec/registry/_obligations.json << 'OBJEOF'
{
  "version": 1,
  "obligations": [
    {
      "id": "OBL-F04-R39",
      "spec": "F04",
      "domains": ["engine"],
      "description": "Async listeners not implemented",
      "blocked_by": "listener executor design",
      "affects": ["F04.R39"],
      "status": "open",
      "created": "2026-04-18"
    },
    {
      "id": "OBL-F04-R53",
      "spec": "F04",
      "domains": ["engine"],
      "description": "Monotonic clock not used",
      "blocked_by": "MonotonicClock design",
      "affects": ["F04.R53"],
      "status": "open",
      "created": "2026-04-18"
    },
    {
      "id": "OBL-F02-R33",
      "spec": "F02",
      "domains": ["serialization"],
      "description": "Already fixed",
      "affects": ["F02.R33"],
      "status": "resolved",
      "resolved_by": "spec-verify",
      "created": "2026-04-16"
    }
  ]
}
OBJEOF

git add -A && git commit -q -m "add obligations"

if command -v jq >/dev/null 2>&1; then
    output="$(bash .claude/scripts/curate-scan.sh --init 2>&1)"

    # Check that obligation registry section exists in summary
    if grep -q "Open Obligations Registry" .curate/scan-summary.md 2>/dev/null; then
        pass "obligation registry section present in summary"
    else
        fail "obligation registry section should be in scan-summary.md" "got: $(cat .curate/scan-summary.md 2>/dev/null)"
    fi

    # Check that only open obligations appear (not resolved)
    if grep -q "OBL-F04-R39" .curate/scan-summary.md 2>/dev/null && \
       grep -q "OBL-F04-R53" .curate/scan-summary.md 2>/dev/null; then
        pass "open obligations listed in summary"
    else
        fail "both open obligations should appear" "got: $(cat .curate/scan-summary.md 2>/dev/null)"
    fi

    if ! grep -q "OBL-F02-R33" .curate/scan-summary.md 2>/dev/null; then
        pass "resolved obligations excluded from summary"
    else
        fail "resolved obligations should not appear" "got: $(grep F02 .curate/scan-summary.md 2>/dev/null)"
    fi

    # Check stats output includes obligation registry count
    if echo "$output" | grep -q "Obligation registry: 2"; then
        pass "obligation registry count in stats output"
    else
        fail "stats should show 'Obligation registry: 2'" "got: $(echo "$output" | grep -i oblig)"
    fi
else
    echo "  SKIP  jq not available"
fi

rm -rf "$OB_TEST_DIR" 2>/dev/null || true
cd "$REPO_ROOT"

# ── Test 29: Empty open_obligations frontmatter is NOT flagged ───────────────
# Regression: prior shell-based stripper false-positived on every spec whose
# frontmatter contained `open_obligations: []` (the array's punctuation
# survived `tr -d '[]"'` and registered as content). Real-world impact:
# "specs with open obligations" reported ~all specs, drowning the real signal.

echo ""
echo "── Test 29: Empty open_obligations frontmatter must not be flagged"

EMPTY_OB_DIR="/tmp/vallorcine/scenario-empty-ob"
rm -rf "$EMPTY_OB_DIR" 2>/dev/null || true
mkdir -p "$EMPTY_OB_DIR/.spec/domains/engine" "$EMPTY_OB_DIR/.spec/registry" \
         "$EMPTY_OB_DIR/.curate" "$EMPTY_OB_DIR/.claude/scripts"
cp "$REPO_ROOT/scripts/curate-scan.sh" "$EMPTY_OB_DIR/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$EMPTY_OB_DIR/.claude/scripts/"

cd "$EMPTY_OB_DIR"
git init -q .
git config user.email t@t.com && git config user.name t

# Spec with explicit `open_obligations: []` in frontmatter — must NOT be
# flagged. This is the exact convention that caused the false-positive.
cat > .spec/domains/engine/empty-ob.md << 'SPECEOF'
---
{
  "id": "engine.empty-ob",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["engine"],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": [],
  "open_obligations": []
}
---

# engine.empty-ob

R1. A normal requirement.
SPECEOF

# Spec with a populated open_obligations array — MUST be flagged.
cat > .spec/domains/engine/real-ob.md << 'SPECEOF'
---
{
  "id": "engine.real-ob",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["engine"],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": [],
  "open_obligations": ["needs ADR on retry budget"]
}
---

# engine.real-ob

R1. Requires retry budget decision.
SPECEOF

cat > .spec/registry/manifest.json << 'MFEOF'
{"schema_version": 2, "spec_count": 2,
 "specs": [
   {"id":"engine.empty-ob","path":".spec/domains/engine/empty-ob.md","state":"APPROVED","version":1,"domains":["engine"],"requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]},
   {"id":"engine.real-ob","path":".spec/domains/engine/real-ob.md","state":"APPROVED","version":1,"domains":["engine"],"requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]}
 ]}
MFEOF

git add -A && git commit -q -m "init"

if command -v jq >/dev/null 2>&1; then
    bash .claude/scripts/curate-scan.sh --init >/tmp/curate-empty-ob.out 2>&1 || true

    # Note: the obligations report uses the spec file basename (not the
    # full id), so empty-ob / real-ob are the table keys.
    if grep -qE '^\| empty-ob \|' .curate/scan-summary.md 2>/dev/null; then
        fail "empty open_obligations:[] flagged as having obligations" \
             "$(grep 'open obligation' -A 5 .curate/scan-summary.md | head -10)"
    else
        pass "empty open_obligations:[] not flagged"
    fi

    if grep -qE '^\| real-ob \|' .curate/scan-summary.md 2>/dev/null; then
        pass "populated open_obligations correctly flagged"
    else
        fail "real obligation should be flagged" \
             "$(grep 'open obligation' -A 5 .curate/scan-summary.md | head -10)"
    fi
else
    echo "  SKIP  jq not available"
fi

rm -rf "$EMPTY_OB_DIR" 2>/dev/null || true
cd "$REPO_ROOT"

# ── Test 30: JDK types blocklisted from unspecified-shared-types ─────────────
# Regression: IllegalArgumentException, NullPointerException, etc. dominated
# the "unspecified shared types" report on real codebases (JDK exceptions are
# referenced in nearly every spec). The blocklist drops them so genuine
# project value-types surface above the noise.

echo ""
echo "── Test 30: JDK types blocklisted from unspecified shared types"

JDK_DIR="/tmp/vallorcine/scenario-jdk-blocklist"
rm -rf "$JDK_DIR" 2>/dev/null || true
mkdir -p "$JDK_DIR/.spec/domains/engine" "$JDK_DIR/.curate" "$JDK_DIR/.claude/scripts"
cp "$REPO_ROOT/scripts/curate-scan.sh" "$JDK_DIR/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$JDK_DIR/.claude/scripts/"

cd "$JDK_DIR"
git init -q .
git config user.email t@t.com && git config user.name t

# Three specs each referencing the same JDK exception types AND a real
# project value type. The JDK types should be filtered out; VectorType
# should surface as an unspecified shared type.
for n in 1 2 3 4; do
  cat > ".spec/domains/engine/spec$n.md" <<SPECEOF
---
{
  "id": "engine.spec$n",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["engine"],
  "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": []
}
---

# engine.spec$n

R1. Throws IllegalArgumentException on bad input.
R2. Returns NullPointerException for missing data.
R3. Validates IllegalStateException on guard.
R4. Operates on VectorType payload.
R5. Manages BoundedString reference.
SPECEOF
done

git add -A && git commit -q -m "init"

bash .claude/scripts/curate-scan.sh --init >/tmp/curate-jdk.out 2>&1 || true

# JDK types should NOT appear under "Unspecified shared types"
if grep -A 50 "### Unspecified shared types" .curate/scan-summary.md 2>/dev/null \
   | grep -E '^\| (IllegalArgumentException|NullPointerException|IllegalStateException) '; then
    fail "JDK exceptions leaked into unspecified shared types" \
         "$(grep -A 30 'Unspecified shared types' .curate/scan-summary.md | head -20)"
else
    pass "JDK exception types blocklisted from unspecified shared types"
fi

# Real project type SHOULD appear (referenced by all 4 specs ≥ 3 threshold)
if grep -A 50 "### Unspecified shared types" .curate/scan-summary.md 2>/dev/null \
   | grep -qE '^\| VectorType '; then
    pass "real shared type (VectorType) still surfaces above blocklist filter"
else
    fail "VectorType should appear in unspecified shared types" \
         "$(grep -A 30 'Unspecified shared types' .curate/scan-summary.md | head -20)"
fi

rm -rf "$JDK_DIR" 2>/dev/null || true
cd "$REPO_ROOT"

# ── Test 31: Bare-only @spec annotations classified separately ───────────────
# Regression: previously, specs with only bare `@spec engine.foo` annotations
# (no R-suffix) were lumped into "no @spec annotations at all". The
# remediation differs (refine vs. add) so they need their own gap class.

echo ""
echo "── Test 31: Bare-only annotations distinct from no-annotations"

BARE_DIR="/tmp/vallorcine/scenario-bare-only"
rm -rf "$BARE_DIR" 2>/dev/null || true
mkdir -p "$BARE_DIR/.spec/domains/engine" "$BARE_DIR/.spec/registry" \
         "$BARE_DIR/.curate" "$BARE_DIR/.claude/scripts" "$BARE_DIR/src"
cp "$REPO_ROOT/scripts/curate-scan.sh" "$BARE_DIR/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$BARE_DIR/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-trace.sh" "$BARE_DIR/.claude/scripts/"

cd "$BARE_DIR"
git init -q .
git config user.email t@t.com && git config user.name t

# Spec A: source has bare @spec engine.bare-anno (no R-suffix)
cat > .spec/domains/engine/bare-anno.md << 'SPECEOF'
---
{
  "id": "engine.bare-anno",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["engine"],
  "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": []
}
---

# engine.bare-anno

R1. Some requirement.
SPECEOF

# Spec B: source has nothing referencing it at all.
cat > .spec/domains/engine/nothing.md << 'SPECEOF'
---
{
  "id": "engine.nothing",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["engine"],
  "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": []
}
---

# engine.nothing

R1. Some requirement.
SPECEOF

cat > src/Bare.java << 'JEOF'
// @spec engine.bare-anno — bare reference, no R suffix
public class Bare {}
JEOF

cat > .spec/registry/manifest.json << 'MFEOF'
{"schema_version": 2, "spec_count": 2,
 "specs": [
   {"id":"engine.bare-anno","path":".spec/domains/engine/bare-anno.md","state":"APPROVED","version":1,"domains":["engine"],"requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]},
   {"id":"engine.nothing","path":".spec/domains/engine/nothing.md","state":"APPROVED","version":1,"domains":["engine"],"requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]}
 ]}
MFEOF

git add -A && git commit -q -m "init"

if command -v jq >/dev/null 2>&1; then
    bash .claude/scripts/curate-scan.sh --init >/tmp/curate-bare.out 2>&1 || true

    # bare-anno should appear in BARE_ONLY section
    if grep -A 10 "specs with bare-only @spec annotations" .curate/scan-summary.md 2>/dev/null \
       | grep -q "engine.bare-anno"; then
        pass "spec with bare @spec anno classified as BARE_ONLY"
    else
        fail "bare-anno should appear in bare-only section" \
             "$(grep -A 5 -E 'bare|annotations' .curate/scan-summary.md | head -30)"
    fi

    # nothing should appear in UNANNOTATED section
    if grep -A 10 "no @spec annotations of any kind" .curate/scan-summary.md 2>/dev/null \
       | grep -q "engine.nothing"; then
        pass "spec with no annotations classified as UNANNOTATED"
    else
        fail "engine.nothing should appear in no-annotations section" \
             "$(grep -A 5 -E 'no.*annotations|of any kind' .curate/scan-summary.md | head -30)"
    fi

    # nothing should NOT appear in BARE_ONLY
    if grep -A 10 "specs with bare-only @spec annotations" .curate/scan-summary.md 2>/dev/null \
       | grep -q "engine.nothing"; then
        fail "engine.nothing leaked into BARE_ONLY (false positive)"
    else
        pass "no-annotations spec stays out of BARE_ONLY"
    fi
else
    echo "  SKIP  jq not available"
fi

rm -rf "$BARE_DIR" 2>/dev/null || true
cd "$REPO_ROOT"

# ── Test 32: Annotation drift — partial coverage below 50% surfaces ────────
# An APPROVED spec with > 50% of requirements uncovered (but at least one
# annotation) should appear in the new "Annotation drift" subsection of
# the scan summary, distinct from UNANNOTATED. Sorted by uncovered-pct.

echo ""
echo "── Test 32: Annotation drift — partial coverage below 50% surfaces"

DRIFT_DIR="/tmp/vallorcine/scenario-annotation-drift"
rm -rf "$DRIFT_DIR" 2>/dev/null || true
mkdir -p "$DRIFT_DIR/.spec/domains/auth" "$DRIFT_DIR/.spec/registry" \
         "$DRIFT_DIR/.curate" "$DRIFT_DIR/.claude/scripts" "$DRIFT_DIR/src/auth"
cp "$REPO_ROOT/scripts/curate-scan.sh" "$DRIFT_DIR/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$DRIFT_DIR/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-trace.sh" "$DRIFT_DIR/.claude/scripts/"

cd "$DRIFT_DIR"
git init -q .
git config user.email t@t.com && git config user.name t

# Spec with 5 R-ids; only R1 will be annotated → 4/5 uncovered = 80% drift.
cat > .spec/domains/auth/token.md << 'SPECEOF'
---
{
  "id": "auth.token",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["auth"],
  "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": []
}
---

# auth.token

## Requirements

R1. Validate token signatures.
R2. Reject expired tokens.
R3. Support multi-tenant claims.
R4. Handle malformed tokens with parse errors.
R5. Issue tokens with configurable TTL.
SPECEOF

cat > src/auth/Token.java << 'JEOF'
// @spec auth.token.R1 — signature validation
public class Token {
    public boolean validate() { return true; }
}
JEOF

cat > .spec/registry/manifest.json << 'MFEOF'
{"schema_version": 2, "spec_count": 1,
 "specs": [
   {"id":"auth.token","path":".spec/domains/auth/token.md","state":"APPROVED","version":1,"domains":["auth"],"requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]}
 ]}
MFEOF

git add -A && git commit -q -m "init"

if command -v jq >/dev/null 2>&1; then
    bash .claude/scripts/curate-scan.sh --init >/tmp/curate-drift.out 2>&1 || true

    # auth.token should appear in the drift subsection (4/5 uncovered = 80%)
    if grep -B 2 -A 15 'Annotation drift' .curate/scan-summary.md 2>/dev/null \
       | grep -qE '^\| auth\.token \| 4 \| 5 \| 80% \|'; then
        pass "auth.token surfaces in annotation-drift with 4/5 uncovered"
    else
        fail "auth.token should appear with 4 uncov, 5 total, 80%" \
             "$(grep -B 2 -A 15 'Annotation drift' .curate/scan-summary.md 2>/dev/null | head -25)"
    fi

    # auth.token should NOT appear in UNANNOTATED (it has at least one annotation)
    if grep -A 10 "no @spec annotations of any kind" .curate/scan-summary.md 2>/dev/null \
       | grep -q "auth.token"; then
        fail "auth.token leaked into UNANNOTATED (it has @spec auth.token.R1)"
    else
        pass "drifted spec stays out of UNANNOTATED bucket"
    fi

    # Drift subsection routes to /spec-backfill
    if grep -A 5 'Annotation drift' .curate/scan-summary.md 2>/dev/null \
       | grep -q '/spec-backfill'; then
        pass "drift subsection routes to /spec-backfill"
    else
        fail "drift subsection should mention /spec-backfill"
    fi
else
    echo "  SKIP  jq not available"
fi

rm -rf "$DRIFT_DIR" 2>/dev/null || true
cd "$REPO_ROOT"

# ── Test 33: Annotation drift — fully-covered spec does NOT surface ────────
# Spec with all R-ids annotated must NOT appear in the drift subsection.

echo ""
echo "── Test 33: Annotation drift — fully covered spec does not surface"

COV_DIR="/tmp/vallorcine/scenario-fully-covered"
rm -rf "$COV_DIR" 2>/dev/null || true
mkdir -p "$COV_DIR/.spec/domains/auth" "$COV_DIR/.spec/registry" \
         "$COV_DIR/.curate" "$COV_DIR/.claude/scripts" "$COV_DIR/src/auth"
cp "$REPO_ROOT/scripts/curate-scan.sh" "$COV_DIR/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$COV_DIR/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-trace.sh" "$COV_DIR/.claude/scripts/"

cd "$COV_DIR"
git init -q .
git config user.email t@t.com && git config user.name t

cat > .spec/domains/auth/cov.md << 'SPECEOF'
---
{
  "id": "auth.cov",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["auth"],
  "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": []
}
---

# auth.cov

## Requirements

R1. First.
R2. Second.
SPECEOF

cat > src/auth/Cov.java << 'JEOF'
// @spec auth.cov.R1
public class CovOne {}
// @spec auth.cov.R2
public class CovTwo {}
JEOF

cat > .spec/registry/manifest.json << 'MFEOF'
{"schema_version": 2, "spec_count": 1,
 "specs": [
   {"id":"auth.cov","path":".spec/domains/auth/cov.md","state":"APPROVED","version":1,"domains":["auth"],"requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]}
 ]}
MFEOF

git add -A && git commit -q -m "init"

if command -v jq >/dev/null 2>&1; then
    bash .claude/scripts/curate-scan.sh --init >/tmp/curate-cov.out 2>&1 || true

    if grep -A 15 'Annotation drift' .curate/scan-summary.md 2>/dev/null \
       | grep -q "auth.cov"; then
        fail "fully-covered auth.cov leaked into drift subsection"
    else
        pass "fully-covered spec does not appear in annotation-drift"
    fi
else
    echo "  SKIP  jq not available"
fi

rm -rf "$COV_DIR" 2>/dev/null || true
cd "$REPO_ROOT"

# ── Test 34: Spec graduation candidates (Analysis 27) ────────────────────────

echo ""
echo "── Test 34: Spec graduation candidates (DEPRECATED + APPROVED)"

if command -v jq >/dev/null 2>&1; then
    GRAD_DIR="$TEST_BASE/grad-project"
    rm -rf "$GRAD_DIR"; mkdir -p "$GRAD_DIR"
    cd "$GRAD_DIR"
    git init --initial-branch=main . >/dev/null 2>&1
    git config user.email t@t.com; git config user.name t
    mkdir -p .claude/scripts
    cp "$REPO_ROOT/scripts/curate-scan.sh" .claude/scripts/
    cp "$REPO_ROOT/scripts/spec-lib.sh" .claude/scripts/
    mkdir -p .spec/registry .spec/domains/storage

    # Three specs: one DEPRECATED+APPROVED (the gap), one DEPRECATED+INVALIDATED
    # (correctly graduated, should NOT surface), one ACTIVE+APPROVED (clean).
    cat > .spec/registry/manifest.json <<'JSON'
{
  "schema_version": 2,
  "specs": [
    { "id": "storage.v1-format", "path": ".spec/domains/storage/v1.md",
      "state": "APPROVED", "version": 1, "domains": ["storage"], "requires": [],
      "invalidates": [], "decision_refs": [], "kb_refs": [] },
    { "id": "storage.v2-format", "path": ".spec/domains/storage/v2.md",
      "state": "INVALIDATED", "version": 1, "domains": ["storage"], "requires": [],
      "invalidates": [], "decision_refs": [], "kb_refs": [] },
    { "id": "storage.v3-format", "path": ".spec/domains/storage/v3.md",
      "state": "APPROVED", "version": 1, "domains": ["storage"], "requires": [],
      "invalidates": [], "decision_refs": [], "kb_refs": [] }
  ]
}
JSON
    # storage.v1-format → DEPRECATED but still APPROVED — should surface.
    cat > .spec/domains/storage/v1.md <<'SPEC'
---
{
  "id": "storage.v1-format", "version": 1, "status": "DEPRECATED",
  "state": "APPROVED", "domains": ["storage"], "requires": [],
  "invalidates": [], "amends": null, "amended_by": null,
  "decision_refs": [], "kb_refs": []
}
---

# storage.v1-format

## Requirements
R1. Storage uses v1 binary layout.

---

## Design
v1 format reference.
SPEC
    # storage.v2-format → DEPRECATED + INVALIDATED — already graduated,
    # should NOT surface (Analysis 27 only flags the gap).
    cat > .spec/domains/storage/v2.md <<'SPEC'
---
{
  "id": "storage.v2-format", "version": 1, "status": "DEPRECATED",
  "state": "INVALIDATED", "domains": ["storage"], "requires": [],
  "invalidates": [], "displaced_by": ["storage.v3-format"],
  "displacement_reason": "v3 supersedes",
  "decision_refs": [], "kb_refs": []
}
---

# storage.v2-format

## Requirements
R1. Storage uses v2 binary layout.

---

## Design
v2 format reference (invalidated).
SPEC
    # storage.v3-format → ACTIVE + APPROVED — the clean current spec.
    cat > .spec/domains/storage/v3.md <<'SPEC'
---
{
  "id": "storage.v3-format", "version": 1, "status": "ACTIVE",
  "state": "APPROVED", "domains": ["storage"], "requires": [],
  "invalidates": [], "amends": null, "amended_by": null,
  "decision_refs": [], "kb_refs": []
}
---

# storage.v3-format

## Requirements
R1. Storage uses v3 binary layout.

---

## Design
v3 format reference.
SPEC
    git add -A && git commit -q -m "init"

    bash .claude/scripts/curate-scan.sh --init >/tmp/curate-grad.out 2>&1 || true

    if grep -q "storage.v1-format" .curate/scan-summary.md 2>/dev/null \
       && grep -A 20 "Spec Graduation Candidates" .curate/scan-summary.md \
            | grep -q "storage.v1-format"; then
        pass "storage.v1-format (DEPRECATED + APPROVED) surfaces in graduation candidates"
    else
        fail "storage.v1-format graduation candidate did not surface"
    fi

    if grep -A 20 "Spec Graduation Candidates" .curate/scan-summary.md 2>/dev/null \
         | grep -q "storage.v2-format"; then
        fail "storage.v2-format (already INVALIDATED) leaked into graduation candidates"
    else
        pass "already-INVALIDATED specs do not surface as graduation candidates"
    fi

    if grep -A 20 "Spec Graduation Candidates" .curate/scan-summary.md 2>/dev/null \
         | grep -q "storage.v3-format"; then
        fail "storage.v3-format (ACTIVE + APPROVED) leaked into graduation candidates"
    else
        pass "ACTIVE+APPROVED specs do not surface as graduation candidates"
    fi
else
    echo "  SKIP  jq not available"
fi

cd "$REPO_ROOT"

# ── Test 35: Spec corpus xref drift (Analysis 28) ────────────────────────────

echo ""
echo "── Test 35: Spec corpus xref drift (broken kb_refs / decision_refs)"

if command -v jq >/dev/null 2>&1; then
    XREF_DIR="$TEST_BASE/xref-project"
    rm -rf "$XREF_DIR"; mkdir -p "$XREF_DIR"
    cd "$XREF_DIR"
    git init --initial-branch=main . >/dev/null 2>&1
    git config user.email t@t.com; git config user.name t
    mkdir -p .claude/scripts
    cp "$REPO_ROOT/scripts/curate-scan.sh" .claude/scripts/
    cp "$REPO_ROOT/scripts/spec-lib.sh" .claude/scripts/
    mkdir -p .spec/registry .spec/domains/api .decisions/real-decision .kb/topic/cat
    echo "# real adr" > .decisions/real-decision/adr.md
    echo "# real kb"  > .kb/topic/cat/real-entry.md

    cat > .spec/registry/manifest.json <<'JSON'
{
  "schema_version": 2,
  "specs": [
    { "id": "api.endpoint", "path": ".spec/domains/api/endpoint.md",
      "state": "APPROVED", "version": 1, "domains": ["api"], "requires": [],
      "invalidates": [], "decision_refs": ["real-decision","missing-decision"],
      "kb_refs": ["topic/cat/real-entry","topic/cat/missing-entry"] }
  ]
}
JSON
    cat > .spec/domains/api/endpoint.md <<'SPEC'
---
{
  "id": "api.endpoint", "version": 1, "status": "ACTIVE", "state": "APPROVED",
  "domains": ["api"], "requires": [], "invalidates": [],
  "amends": null, "amended_by": null,
  "decision_refs": ["real-decision","missing-decision"],
  "kb_refs": ["topic/cat/real-entry","topic/cat/missing-entry"]
}
---

# api.endpoint

## Requirements
R1. The API exposes a versioned endpoint.

---

## Design
Endpoint contract.
SPEC
    git add -A && git commit -q -m "init"

    bash .claude/scripts/curate-scan.sh --init >/tmp/curate-xref.out 2>&1 || true

    if grep -A 20 "Spec Corpus Cross-Reference Drift" .curate/scan-summary.md 2>/dev/null \
        | grep -q "missing-decision"; then
        pass "broken decision_ref surfaces in xref drift"
    else
        fail "broken decision_ref did not surface"
    fi

    if grep -A 20 "Spec Corpus Cross-Reference Drift" .curate/scan-summary.md 2>/dev/null \
        | grep -q "topic/cat/missing-entry"; then
        pass "broken kb_ref surfaces in xref drift"
    else
        fail "broken kb_ref did not surface"
    fi

    if grep -A 20 "Spec Corpus Cross-Reference Drift" .curate/scan-summary.md 2>/dev/null \
        | grep -q "real-decision"; then
        fail "real-decision (resolves) leaked into xref drift"
    else
        pass "resolving decision_ref does not appear in xref drift"
    fi

    if grep -A 20 "Spec Corpus Cross-Reference Drift" .curate/scan-summary.md 2>/dev/null \
        | grep -q "topic/cat/real-entry"; then
        fail "real kb_ref (resolves) leaked into xref drift"
    else
        pass "resolving kb_ref does not appear in xref drift"
    fi
else
    echo "  SKIP  jq not available"
fi

cd "$REPO_ROOT"

# ── Test 36: Spec annotation coverage rollup (Analysis 18b — F5) ─────────────

echo ""
echo "── Test 36: Spec annotation coverage rollup (corpus framing)"

if command -v jq >/dev/null 2>&1; then
    ROLL_DIR="$TEST_BASE/rollup-project"
    rm -rf "$ROLL_DIR"; mkdir -p "$ROLL_DIR"
    cd "$ROLL_DIR"
    git init --initial-branch=main . >/dev/null 2>&1
    git config user.email t@t.com; git config user.name t
    mkdir -p .claude/scripts
    cp "$REPO_ROOT/scripts/curate-scan.sh"  .claude/scripts/
    cp "$REPO_ROOT/scripts/spec-lib.sh"     .claude/scripts/
    cp "$REPO_ROOT/scripts/spec-trace.sh"   .claude/scripts/ 2>/dev/null || true
    mkdir -p .spec/registry .spec/domains/auth src

    # Two APPROVED specs: one annotated, one not. Rollup should show
    # 50% covered / 50% unannotated.
    cat > .spec/registry/manifest.json <<'JSON'
{
  "schema_version": 2,
  "specs": [
    { "id": "auth.session", "path": ".spec/domains/auth/session.md",
      "state": "APPROVED", "version": 1, "domains": ["auth"], "requires": [],
      "invalidates": [], "decision_refs": [], "kb_refs": [] },
    { "id": "auth.token", "path": ".spec/domains/auth/token.md",
      "state": "APPROVED", "version": 1, "domains": ["auth"], "requires": [],
      "invalidates": [], "decision_refs": [], "kb_refs": [] }
  ]
}
JSON
    for sid in auth.session auth.token; do
      cat > ".spec/domains/auth/${sid#auth.}.md" <<SPEC
---
{
  "id": "$sid", "version": 1, "status": "ACTIVE", "state": "APPROVED",
  "domains": ["auth"], "requires": [], "invalidates": [],
  "amends": null, "amended_by": null,
  "decision_refs": [], "kb_refs": []
}
---

# $sid

## Requirements
R1. Requirement one.
R2. Requirement two.

---

## Design
Notes.
SPEC
    done

    # Annotate auth.session fully (R1 + R2 in source). Leave auth.token bare.
    cat > src/Session.java <<'JAVA'
// @spec auth.session.R1
// @spec auth.session.R2
public class Session {}
JAVA
    git add -A && git commit -q -m "init"

    bash .claude/scripts/curate-scan.sh --init >/tmp/curate-rollup.out 2>&1 || true

    if grep -q "## Spec Annotation Coverage Rollup" .curate/scan-summary.md 2>/dev/null; then
        pass "rollup section appears in summary"
    else
        fail "rollup section missing"
    fi

    if grep -A 12 "Spec Annotation Coverage Rollup" .curate/scan-summary.md 2>/dev/null \
        | grep -E "Unannotated.*\| 1 \|" >/dev/null; then
        pass "unannotated count = 1 surfaces in rollup"
    else
        fail "rollup unannotated count incorrect (expected 1)"
    fi

    if grep -A 12 "Spec Annotation Coverage Rollup" .curate/scan-summary.md 2>/dev/null \
        | grep -E "Fully covered.*\| 1 \|" >/dev/null; then
        pass "fully-covered count = 1 surfaces in rollup"
    else
        fail "rollup fully-covered count incorrect (expected 1)"
    fi
else
    echo "  SKIP  jq not available"
fi

cd "$REPO_ROOT"

# ── Test 37: ADRs without spec coverage (Analysis 29 — F6) ───────────────────

echo ""
echo "── Test 37: ADRs without spec coverage"

if command -v jq >/dev/null 2>&1; then
    ADR_DIR="$TEST_BASE/adr-no-spec-project"
    rm -rf "$ADR_DIR"; mkdir -p "$ADR_DIR"
    cd "$ADR_DIR"
    git init --initial-branch=main . >/dev/null 2>&1
    git config user.email t@t.com; git config user.name t
    mkdir -p .claude/scripts
    cp "$REPO_ROOT/scripts/curate-scan.sh"  .claude/scripts/
    cp "$REPO_ROOT/scripts/spec-lib.sh"     .claude/scripts/
    mkdir -p .spec/registry .spec/domains/auth
    mkdir -p .decisions/referenced-decision .decisions/orphan-decision \
             .decisions/rejected-decision

    cat > .decisions/referenced-decision/adr.md <<'ADR'
---
status: accepted
---

# Referenced Decision
ADR
    cat > .decisions/orphan-decision/adr.md <<'ADR'
---
status: accepted
---

# Orphan Decision
ADR
    cat > .decisions/rejected-decision/adr.md <<'ADR'
---
status: rejected
---

# Rejected Decision (filtered out)
ADR

    cat > .spec/registry/manifest.json <<'JSON'
{
  "schema_version": 2,
  "specs": [
    { "id": "auth.session", "path": ".spec/domains/auth/session.md",
      "state": "APPROVED", "version": 1, "domains": ["auth"], "requires": [],
      "invalidates": [], "decision_refs": ["referenced-decision"], "kb_refs": [] }
  ]
}
JSON
    cat > .spec/domains/auth/session.md <<'SPEC'
---
{
  "id": "auth.session", "version": 1, "status": "ACTIVE", "state": "APPROVED",
  "domains": ["auth"], "requires": [], "invalidates": [],
  "amends": null, "amended_by": null,
  "decision_refs": ["referenced-decision"], "kb_refs": []
}
---

# auth.session

## Requirements
R1. Sessions exist.

---

## Design
Notes.
SPEC
    git add -A && git commit -q -m "init"

    bash .claude/scripts/curate-scan.sh --init >/tmp/curate-adr.out 2>&1 || true

    if grep -A 25 "ADRs Without Spec Coverage" .curate/scan-summary.md 2>/dev/null \
        | grep -q "orphan-decision"; then
        pass "orphan-decision (accepted, no spec) surfaces"
    else
        fail "orphan-decision did not surface"
    fi

    if grep -A 25 "ADRs Without Spec Coverage" .curate/scan-summary.md 2>/dev/null \
        | grep -q "referenced-decision"; then
        fail "referenced-decision (has spec) leaked into ADR-no-spec"
    else
        pass "referenced ADR does not appear in ADR-no-spec"
    fi

    if grep -A 25 "ADRs Without Spec Coverage" .curate/scan-summary.md 2>/dev/null \
        | grep -q "rejected-decision"; then
        fail "rejected-decision (status filter) leaked into ADR-no-spec"
    else
        pass "rejected ADR is filtered out by status"
    fi
else
    echo "  SKIP  jq not available"
fi

cd "$REPO_ROOT"

# ── Test 38: Scan-complete sentinel written when scan finishes cleanly ───────

echo ""
echo "── Test 38: scan-complete sentinel marks the summary as authoritative"

if command -v jq >/dev/null 2>&1; then
    SENT_DIR="$TEST_BASE/sentinel-project"
    rm -rf "$SENT_DIR"; mkdir -p "$SENT_DIR"
    cd "$SENT_DIR"
    git init --initial-branch=main . >/dev/null 2>&1
    git config user.email t@t.com; git config user.name t
    mkdir -p .claude/scripts
    cp "$REPO_ROOT/scripts/curate-scan.sh"  .claude/scripts/
    cp "$REPO_ROOT/scripts/spec-lib.sh"     .claude/scripts/
    echo "x" > a.md
    git add -A && git commit -q -m "init"

    bash .claude/scripts/curate-scan.sh --init >/dev/null 2>&1 || true

    if tail -1 .curate/scan-summary.md | grep -q "^✓ Scan complete:"; then
        pass "sentinel line present at end of summary"
    else
        fail "sentinel line missing"
    fi

    if tail -1 .curate/scan-summary.md | grep -q "max_specs_traced=50"; then
        pass "sentinel records max_specs_traced setting"
    else
        fail "sentinel missing max_specs_traced field"
    fi

    if tail -1 .curate/scan-summary.md | grep -q "scan_mode=full"; then
        pass "sentinel records scan_mode (full on --init)"
    else
        fail "sentinel missing scan_mode field"
    fi
else
    echo "  SKIP  jq not available"
fi

cd "$REPO_ROOT"

# ── Test 39: Sentinel records specs_traced=0 with --max-specs-traced 0 ───────

echo ""
echo "── Test 39: --max-specs-traced 0 sentinel marks the trace as skipped"

if command -v jq >/dev/null 2>&1; then
    FAST_DIR="$TEST_BASE/sentinel-fast-project"
    rm -rf "$FAST_DIR"; mkdir -p "$FAST_DIR"
    cd "$FAST_DIR"
    git init --initial-branch=main . >/dev/null 2>&1
    git config user.email t@t.com; git config user.name t
    mkdir -p .claude/scripts
    cp "$REPO_ROOT/scripts/curate-scan.sh"  .claude/scripts/
    cp "$REPO_ROOT/scripts/spec-lib.sh"     .claude/scripts/
    cp "$REPO_ROOT/scripts/spec-trace.sh"   .claude/scripts/ 2>/dev/null || true
    mkdir -p .spec/registry .spec/domains/auth

    cat > .spec/registry/manifest.json <<'JSON'
{
  "schema_version": 2,
  "specs": [
    { "id": "auth.session", "path": ".spec/domains/auth/session.md",
      "state": "APPROVED", "version": 1, "domains": ["auth"], "requires": [],
      "invalidates": [], "decision_refs": [], "kb_refs": [] }
  ]
}
JSON
    cat > .spec/domains/auth/session.md <<'SPEC'
---
{
  "id": "auth.session", "version": 1, "status": "ACTIVE", "state": "APPROVED",
  "domains": ["auth"], "requires": [], "invalidates": [],
  "amends": null, "amended_by": null,
  "decision_refs": [], "kb_refs": []
}
---

# auth.session

## Requirements
R1. Sessions exist.

---

## Design
Notes.
SPEC
    git add -A && git commit -q -m "init"

    bash .claude/scripts/curate-scan.sh --init --max-specs-traced 0 >/dev/null 2>&1 || true

    if tail -1 .curate/scan-summary.md | grep -q "specs_traced=0"; then
        pass "fast scan records specs_traced=0"
    else
        fail "fast scan did not record specs_traced=0" "got: $(tail -1 .curate/scan-summary.md)"
    fi

    if tail -1 .curate/scan-summary.md | grep -q "max_specs_traced=0"; then
        pass "fast scan records max_specs_traced=0 setting"
    else
        fail "fast scan did not record max_specs_traced=0"
    fi
else
    echo "  SKIP  jq not available"
fi

cd "$REPO_ROOT"

# ── Test 40: Truncated summary (simulates killed scan) lacks the sentinel ────

echo ""
echo "── Test 40: truncated summary fails the sentinel check"

if command -v jq >/dev/null 2>&1; then
    TRUNC_DIR="$TEST_BASE/sentinel-trunc-project"
    rm -rf "$TRUNC_DIR"; mkdir -p "$TRUNC_DIR"
    cd "$TRUNC_DIR"
    git init --initial-branch=main . >/dev/null 2>&1
    git config user.email t@t.com; git config user.name t
    mkdir -p .claude/scripts .curate
    cp "$REPO_ROOT/scripts/curate-scan.sh"  .claude/scripts/
    cp "$REPO_ROOT/scripts/spec-lib.sh"     .claude/scripts/
    echo "x" > a.md
    git add -A && git commit -q -m "init"

    bash .claude/scripts/curate-scan.sh --init >/dev/null 2>&1 || true

    # Now simulate a killed scan: chop off the trailing sentinel block.
    # Real-world equivalent: the script's final write block (sentinel +
    # state update) never ran because the process was SIGTERM'd between
    # the body of the last analysis and the sentinel append.
    head -n -3 .curate/scan-summary.md > .curate/.tmp && mv .curate/.tmp .curate/scan-summary.md

    if tail -1 .curate/scan-summary.md | grep -q "^✓ Scan complete:"; then
        fail "sentinel present after truncation (test setup wrong)"
    else
        pass "truncated summary correctly fails sentinel check"
    fi
else
    echo "  SKIP  jq not available"
fi

cd "$REPO_ROOT"

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
