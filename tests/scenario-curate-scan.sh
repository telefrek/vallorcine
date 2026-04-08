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
