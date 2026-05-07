#!/usr/bin/env bash
# Scenario: feature-state-reconcile.sh detects + repairs Spec Authoring
# substage drift caused by sibling-WD spec authoring landing in a
# different feature's PR.
#
# Tests:
# 1. Drift detected when produced spec is APPROVED but status.md says in-progress
# 2. Apply mode rewrites the Stage Completion row to `complete` with today's date
# 3. --read-only mode reports drift but does not write
# 4. Re-running on already-reconciled state is a no-op (prints "current")
# 5. Plain (non-work-group) feature reports "no cross-session reconciliation needed"
# 6. WD with no produced specs reports "no durable check"
# 7. Partial — 1/2 produced specs APPROVED leaves status.md unchanged
# 8. Slash-form path normalizes to dot-form for manifest lookup
# 9. Archived feature directory is reconciled too
# 10. Missing manifest exits cleanly without writing
#
# Run from repo root: bash tests/scenario-feature-state-reconcile.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-feature-state-reconcile"
RECONCILE="$REPO_ROOT/scripts/feature-state-reconcile.sh"

passed=0; failed=0; total=0
pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }
cleanup() { rm -rf "$TEST_BASE" 2>/dev/null || true; }
trap cleanup EXIT

echo ""
echo "scenario: feature-state-reconcile spec-authoring drift detection"
echo "──────────────────────────────────────────────────────────────────"

cleanup

# ── Common fixture builder ──────────────────────────────────────────────────

setup_fixture() {
  local name="$1"
  local proj="$TEST_BASE/$name/project"
  local wd_status="${2:-SPECIFIED}"
  local spec_state="${3:-APPROVED}"
  local feature_substage="${4:-in-progress}"

  rm -rf "$TEST_BASE/$name"
  mkdir -p "$proj/.feature/add-compaction--wd-05" \
           "$proj/.work/add-compaction" \
           "$proj/.spec/registry" \
           "$proj/.spec/domains/engine" \
           "$proj/.claude/scripts"
  cp "$REPO_ROOT/scripts/feature-state-reconcile.sh" "$proj/.claude/scripts/"
  cp "$REPO_ROOT/scripts/spec-lib.sh"                "$proj/.claude/scripts/"
  cp "$REPO_ROOT/scripts/work-lib.sh"                "$proj/.claude/scripts/"

  cat > "$proj/.work/add-compaction/WD-05.md" << EOF
---
id: WD-05
title: Compaction orchestration
group: add-compaction
status: $wd_status
domains: [engine]
artifact_deps: []
produces:
  - { type: spec, path: "engine.compaction-orchestration" }
---

## Summary
Author the orchestration spec.
EOF

  cat > "$proj/.spec/registry/manifest.json" << EOF
{
  "schema_version": 2,
  "specs": [
    { "id": "engine.compaction-orchestration", "path": ".spec/domains/engine/compaction-orchestration.md", "state": "$spec_state", "version": 4, "domains": ["engine"] }
  ]
}
EOF
  echo '# engine.compaction-orchestration' > "$proj/.spec/domains/engine/compaction-orchestration.md"

  cat > "$proj/.feature/add-compaction--wd-05/status.md" << EOF
# Status — add-compaction--wd-05

## Current Position
**Stage:** spec-authoring
**Substage:** drafting

## Work Group
work_group: add-compaction
work_definition: WD-05

## Stage Completion

| Stage | Status | Completed | Est. Tokens | Actual Tokens | Notes |
|-------|--------|-----------|-------------|---------------|-------|
| Scoping | complete | 2026-04-30 | ~5K | 4.2K in / 3K out | |
| Domains | complete | 2026-05-01 | ~6K | 8.1K in / 2K out | |
| Spec Authoring | $feature_substage | — | — | — | drafting |
| Planning | not-started | — | — | — | |
EOF
  echo "$proj"
}

# ── Test 1: Drift detected ──────────────────────────────────────────────────

echo ""
echo "── Test 1: Drift detected when spec is APPROVED but status.md says in-progress"

proj=$(setup_fixture t1)
cd "$proj"
output=$(bash "$RECONCILE" add-compaction--wd-05 --read-only 2>&1)
if echo "$output" | grep -q "drift — Spec Authoring 'in-progress'.*1/1 produced specs APPROVED"; then
    pass "drift detected with correct counts"
else
    fail "drift detection wrong" "got: $output"
fi
cd - >/dev/null

# ── Test 2: Apply mode rewrites the row ─────────────────────────────────────

echo ""
echo "── Test 2: Apply mode rewrites Spec Authoring row to complete"

proj=$(setup_fixture t2)
cd "$proj"
bash "$RECONCILE" add-compaction--wd-05 >/dev/null 2>&1
today=$(date +%F)
if grep -qE "^\| Spec Authoring \| complete \| $today \|" .feature/add-compaction--wd-05/status.md; then
    pass "Spec Authoring row → complete with today's date"
else
    fail "row not rewritten correctly" "got: $(grep '^| Spec Authoring' .feature/add-compaction--wd-05/status.md)"
fi
cd - >/dev/null

# ── Test 3: --read-only does not write ──────────────────────────────────────

echo ""
echo "── Test 3: --read-only reports drift but does not write"

proj=$(setup_fixture t3)
cd "$proj"
cp .feature/add-compaction--wd-05/status.md /tmp/before-readonly.md
bash "$RECONCILE" add-compaction--wd-05 --read-only >/dev/null 2>&1
if cmp -s .feature/add-compaction--wd-05/status.md /tmp/before-readonly.md; then
    pass "--read-only left status.md byte-identical"
else
    fail "--read-only wrote to status.md"
fi
cd - >/dev/null

# ── Test 4: Re-run is no-op on already-reconciled state ─────────────────────

echo ""
echo "── Test 4: Re-run on already-reconciled state is a no-op"

proj=$(setup_fixture t4)
cd "$proj"
bash "$RECONCILE" add-compaction--wd-05 >/dev/null 2>&1
cp .feature/add-compaction--wd-05/status.md /tmp/before-rerun.md
output=$(bash "$RECONCILE" add-compaction--wd-05 2>&1)
if echo "$output" | grep -q "already complete in status.md.*current" && \
   cmp -s .feature/add-compaction--wd-05/status.md /tmp/before-rerun.md; then
    pass "re-run reports current and writes nothing"
else
    fail "re-run mutated status.md or wrong message" "got: $output"
fi
cd - >/dev/null

# ── Test 5: Plain (non-work-group) feature ──────────────────────────────────

echo ""
echo "── Test 5: Plain feature reports no cross-session reconciliation needed"

proj=$(setup_fixture t5)
cd "$proj"
# Strip work_group + work_definition from status.md and rename feature dir
mv .feature/add-compaction--wd-05 .feature/plain-feature
sed -i '/^work_group:/d; /^work_definition:/d' .feature/plain-feature/status.md
output=$(bash "$RECONCILE" plain-feature 2>&1)
if echo "$output" | grep -q "not work-group-sourced"; then
    pass "plain feature short-circuits cleanly"
else
    fail "plain feature should report not work-group-sourced" "got: $output"
fi
cd - >/dev/null

# ── Test 6: WD with no produced specs ───────────────────────────────────────

echo ""
echo "── Test 6: WD with empty produces reports no durable check"

proj=$(setup_fixture t6)
cd "$proj"
# Drop the produces section
sed -i '/^produces:$/,/^---$/{ /^---$/!d }' .work/add-compaction/WD-05.md
output=$(bash "$RECONCILE" add-compaction--wd-05 2>&1)
if echo "$output" | grep -q "produces no specs"; then
    pass "WD without produced specs short-circuits"
else
    fail "should report produces no specs" "got: $output"
fi
cd - >/dev/null

# ── Test 7: Partial coverage (some specs not yet APPROVED) ──────────────────

echo ""
echo "── Test 7: Partial — only 1/2 produced specs APPROVED leaves status.md unchanged"

proj=$(setup_fixture t7)
cd "$proj"
# Add a second produces entry pointing at a DRAFT spec
cat > .work/add-compaction/WD-05.md << 'EOF'
---
id: WD-05
title: Compaction orchestration
group: add-compaction
status: SPECIFIED
domains: [engine]
artifact_deps: []
produces:
  - { type: spec, path: "engine.compaction-orchestration" }
  - { type: spec, path: "engine.compaction-budget" }
---
EOF
# Add the budget spec to manifest as DRAFT
cat > .spec/registry/manifest.json << 'EOF'
{
  "schema_version": 2,
  "specs": [
    { "id": "engine.compaction-orchestration", "path": ".spec/domains/engine/compaction-orchestration.md", "state": "APPROVED", "version": 4, "domains": ["engine"] },
    { "id": "engine.compaction-budget", "path": ".spec/domains/engine/compaction-budget.md", "state": "DRAFT", "version": 1, "domains": ["engine"] }
  ]
}
EOF
cp .feature/add-compaction--wd-05/status.md /tmp/before-partial.md
output=$(bash "$RECONCILE" add-compaction--wd-05 2>&1)
if echo "$output" | grep -q "1/2 produced specs APPROVED" && \
   echo "$output" | grep -q "engine.compaction-budget" && \
   cmp -s .feature/add-compaction--wd-05/status.md /tmp/before-partial.md; then
    pass "partial coverage reports gap and leaves status.md unchanged"
else
    fail "partial reconciliation incorrect" "got: $output"
fi
cd - >/dev/null

# ── Test 8: Slash-form path normalizes to dot-form ──────────────────────────

echo ""
echo "── Test 8: Slash-form path in produces resolves to dot-form ID"

proj=$(setup_fixture t8)
cd "$proj"
sed -i 's|engine.compaction-orchestration|engine/compaction-orchestration|' .work/add-compaction/WD-05.md
output=$(bash "$RECONCILE" add-compaction--wd-05 --read-only 2>&1)
if echo "$output" | grep -q "1/1 produced specs APPROVED"; then
    pass "slash-form path normalized to dot-form for manifest lookup"
else
    fail "slash-form not normalized" "got: $output"
fi
cd - >/dev/null

# ── Test 9: Archived feature directory ──────────────────────────────────────

echo ""
echo "── Test 9: Archived feature directory is reconciled too"

proj=$(setup_fixture t9)
cd "$proj"
mkdir -p .feature/_archive
mv .feature/add-compaction--wd-05 .feature/_archive/
output=$(bash "$RECONCILE" add-compaction--wd-05 2>&1)
if echo "$output" | grep -q "1/1 produced specs APPROVED"; then
    pass "archived feature is found + reconciled"
else
    fail "archived feature not reconciled" "got: $output"
fi
cd - >/dev/null

# ── Test 10: Missing manifest exits cleanly ─────────────────────────────────

echo ""
echo "── Test 10: Missing manifest exits cleanly without writing"

proj=$(setup_fixture t10)
cd "$proj"
rm -f .spec/registry/manifest.json
cp .feature/add-compaction--wd-05/status.md /tmp/before-no-manifest.md
output=$(bash "$RECONCILE" add-compaction--wd-05 2>&1)
if echo "$output" | grep -q "no spec manifest" && \
   cmp -s .feature/add-compaction--wd-05/status.md /tmp/before-no-manifest.md; then
    pass "missing manifest reports + leaves status.md untouched"
else
    fail "missing manifest path wrong" "got: $output"
fi
cd - >/dev/null

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────"
if [[ $failed -eq 0 ]]; then
    echo "ALL PASSED  ($passed/$total)"
else
    echo "FAILED  $failed/$total  ($passed passed)"
fi
exit $failed
