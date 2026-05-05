#!/usr/bin/env bash
# Scenario: /curate review-log persistence + full-window thresholds.
#
# Empirical bug surfaced during jlsm /curate run on 2026-05-04: the scan
# reported "0 actionable items" even though the user had skipped multiple
# items on the prior run. Diagnosis identified three coupled defects:
#
#   Bug 1 — Step 5's curation-state.md template was a full-file
#           replacement, wiping every prior Review Log row each run.
#   Bug 2 — Step 0 read "previously deferred items from the review log"
#           but no Step actually re-presented them in the pick list.
#   Bug 3 — Pressure / gravity / drift thresholds ran against the
#           incremental commit window only. Small windows diluted
#           signals below thresholds and reported them as "flat
#           artifact correlations" instead of actionable findings.
#
# This scenario locks in the fix:
#   - .curate/review-log.md is append-only and survives multiple scans.
#   - `curate-review-log.sh unresolved` returns rows where the latest
#     status is `deferred` or `suggested`.
#   - `curate-review-log.sh migrate` lifts any legacy Review Log rows
#     out of curation-state.md (idempotent).
#   - curate-scan.sh runs threshold analyses against the full configured
#     window regardless of LAST_SHA, and tags findings as "new since
#     last scan" vs "ongoing" rather than gating on incremental delta.
#
# Run from repo root: bash tests/scenario-curate-defer-and-thresholds.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-curate-defer-and-thresholds"

passed=0
failed=0
total=0

pass() {
    ((passed++)) || true
    ((total++)) || true
    echo "  PASS  $1"
    return 0
}

fail() {
    ((failed++)) || true
    ((total++)) || true
    echo "  FAIL  $1"
    [[ -n "${2:-}" ]] && echo "        $2"
    return 0
}

cleanup() { rm -rf "$TEST_BASE" 2>/dev/null || true; }
trap cleanup EXIT

echo ""
echo "scenario: /curate review-log persistence + full-window thresholds"
echo "──────────────────────────────────────────────────────────────────"

cleanup
mkdir -p "$TEST_BASE"

PROJECT="$TEST_BASE/project"
git init --initial-branch=main "$PROJECT" >/dev/null 2>&1
git -C "$PROJECT" config user.email "test@test.com"
git -C "$PROJECT" config user.name "Test"

mkdir -p "$PROJECT/.claude/scripts" "$PROJECT/.decisions/auth-session-storage" \
         "$PROJECT/src/auth"

cp "$REPO_ROOT/scripts/curate-scan.sh"        "$PROJECT/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh"           "$PROJECT/.claude/scripts/"
cp "$REPO_ROOT/scripts/curate-review-log.sh"  "$PROJECT/.claude/scripts/" 2>/dev/null \
    || echo "(curate-review-log.sh not yet present — fix-side test will fill in once script lands)"

cat > "$PROJECT/.decisions/auth-session-storage/adr.md" <<'ADR'
---
slug: auth-session-storage
status: accepted
files: ["src/auth/session.ts", "src/auth/middleware.ts", "src/auth/cookies.ts"]
---
# auth-session-storage

This ADR governs three files that together implement session storage.
ADR

# Seed three files covered by the ADR.
echo "// session" > "$PROJECT/src/auth/session.ts"
echo "// middleware" > "$PROJECT/src/auth/middleware.ts"
echo "// cookies" > "$PROJECT/src/auth/cookies.ts"
echo "# project" > "$PROJECT/README.md"

git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "initial" >/dev/null 2>&1
INITIAL_SHA=$(git -C "$PROJECT" rev-parse HEAD)

# Touch each ADR-constrained file in distinct commits across history.
# 5 separate single-file commits produces ADR pressure: 3 changed files /
# 3 listed → 100% pct, well above any reasonable threshold. This creates
# the "old, large window" signal for the full-window test below.
for i in 1 2 3 4 5; do
    target=$(( i % 3 ))
    case "$target" in
        0) f="$PROJECT/src/auth/session.ts" ;;
        1) f="$PROJECT/src/auth/middleware.ts" ;;
        2) f="$PROJECT/src/auth/cookies.ts" ;;
    esac
    echo "// edit $i" >> "$f"
    git -C "$PROJECT" add -A
    git -C "$PROJECT" commit -m "auth edit $i" >/dev/null 2>&1
done

PRE_RECENT_SHA=$(git -C "$PROJECT" rev-parse HEAD)

# Two more very recent commits that touch only ONE ADR-constrained file.
# This is the tiny incremental window — the cumulative window above still
# shows full pressure, but the incremental window alone would dilute below
# the >=2 threshold.
echo "// recent A" >> "$PROJECT/src/auth/session.ts"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "tiny recent A" >/dev/null 2>&1
echo "// recent B" >> "$PROJECT/src/auth/session.ts"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "tiny recent B" >/dev/null 2>&1

CURRENT_SHA=$(git -C "$PROJECT" rev-parse HEAD)

cd "$PROJECT"

# ── Test 1: Full-window thresholds fire even with LAST_SHA set ──────────────
# Bug 3 contract: pressure must be reported because the full window has
# changes across all three ADR-constrained files, even though the
# incremental delta from PRE_RECENT_SHA..HEAD only touches one file twice.

echo ""
echo "── Test 1: pressure reported on full window despite tiny LAST_SHA delta"

mkdir -p .curate
cat > .curate/curation-state.md <<EOF
# Curation State

## Scan State
Last scanned: $PRE_RECENT_SHA
Last scanned date: 2026-05-03
EOF

output=$(bash .claude/scripts/curate-scan.sh 2>&1 || true)

# Pressure section must include auth-session-storage.
if echo "$output" | grep -q "Scan complete"; then
    if grep -q "auth-session-storage" .curate/scan-summary.md 2>/dev/null \
       && sed -n '/^## ADR Pressure/,/^## /p' .curate/scan-summary.md \
            | grep -q "auth-session-storage"; then
        pass "ADR pressure on auth-session-storage reported on full-window analysis"
    else
        fail "auth-session-storage pressure missing despite full-window scan" \
             "scan-summary head:\n$(head -40 .curate/scan-summary.md 2>/dev/null)"
    fi
else
    fail "scan did not complete cleanly" "got: $output"
fi

# ── Test 2: Findings tagged "new" vs "ongoing" relative to LAST_SHA ─────────
# Bug 3 fix preserves the LAST_SHA semantic: an ADR whose changes occurred
# ONLY in the incremental window is "new"; one whose pressure was already
# present pre-LAST_SHA is "ongoing".

echo ""
echo "── Test 2: scan-summary tags pressure findings as new vs ongoing"

if grep -qE "^## ADR Pressure" .curate/scan-summary.md \
   && grep -qE "(new since last scan|ongoing since)" .curate/scan-summary.md; then
    pass "scan-summary annotates findings with new/ongoing tag"
else
    fail "no new/ongoing annotation in scan-summary" \
         "ADR Pressure section:\n$(sed -n '/## ADR Pressure/,/^## /p' .curate/scan-summary.md)"
fi

# ── Test 3: review-log.md migration from legacy curation-state.md ───────────
# Bug 1 fix: rows previously written to curation-state.md's Review Log
# section are migrated to .curate/review-log.md on first run. Migration
# is idempotent — re-running does not duplicate rows.

echo ""
echo "── Test 3: legacy review-log rows migrate to .curate/review-log.md"

cat > .curate/curation-state.md <<EOF
# Curation State

## Scan State
Last scanned: $PRE_RECENT_SHA
Last scanned date: 2026-05-03

## Review Log
| Date | Item | Status | Notes |
|------|------|--------|-------|
| 2026-05-01 | adr-pressure:auth-session-storage | deferred | wait for WD-03 |
| 2026-05-02 | spec-drift:foo                    | suggested | low priority |
EOF

bash .claude/scripts/curate-review-log.sh migrate \
    .curate/curation-state.md .curate/review-log.md 2>&1 >/dev/null || true

if [[ -f .curate/review-log.md ]] \
   && grep -q "adr-pressure:auth-session-storage" .curate/review-log.md \
   && grep -q "spec-drift:foo" .curate/review-log.md; then
    pass "two legacy rows migrated to review-log.md"
else
    fail "migration did not move rows" \
         "review-log: $(cat .curate/review-log.md 2>/dev/null || echo '(missing)')"
fi

# After migration, curation-state.md must NOT carry the Review Log section.
if grep -q "^## Review Log" .curate/curation-state.md; then
    fail "curation-state.md still has Review Log section after migrate"
else
    pass "curation-state.md cleaned of Review Log section"
fi

# Migration is idempotent — re-running adds no duplicate rows.
rows_before=$(grep -cE '^\|.*\|.*\|' .curate/review-log.md || true)
bash .claude/scripts/curate-review-log.sh migrate \
    .curate/curation-state.md .curate/review-log.md 2>&1 >/dev/null || true
rows_after=$(grep -cE '^\|.*\|.*\|' .curate/review-log.md || true)
if [[ "$rows_before" == "$rows_after" ]]; then
    pass "migrate is idempotent"
else
    fail "migrate duplicated rows on re-run" "before=$rows_before after=$rows_after"
fi

# ── Test 4: append preserves prior rows across simulated runs ───────────────
# Bug 1 contract: each run appends; nothing is rewritten.

echo ""
echo "── Test 4: append preserves prior rows across multiple runs"

bash .claude/scripts/curate-review-log.sh append \
    .curate/review-log.md 2026-05-04 \
    "adr-gravity:cache-strategy" \
    "ADR gravity on cache-strategy (3 unconstrained files)" \
    "deferred" "needs architect review" >/dev/null 2>&1

bash .claude/scripts/curate-review-log.sh append \
    .curate/review-log.md 2026-05-04 \
    "scan-bookkeeping:index-overflow" \
    "decisions index overflow repair" \
    "resolved" "archived 12 rows" >/dev/null 2>&1

if grep -q "adr-pressure:auth-session-storage" .curate/review-log.md \
   && grep -q "adr-gravity:cache-strategy" .curate/review-log.md \
   && grep -q "scan-bookkeeping:index-overflow" .curate/review-log.md; then
    pass "all four rows present (2 migrated + 2 newly appended)"
else
    fail "rows lost between writes" \
         "review-log: $(cat .curate/review-log.md)"
fi

# ── Test 5: append is duplicate-safe within the same run ────────────────────
# Re-appending the exact same (date, key, status, notes) row no-ops.

echo ""
echo "── Test 5: append is duplicate-safe"

before=$(grep -cE '^\|.*\|.*\|' .curate/review-log.md || true)
bash .claude/scripts/curate-review-log.sh append \
    .curate/review-log.md 2026-05-04 \
    "adr-gravity:cache-strategy" \
    "ADR gravity on cache-strategy (3 unconstrained files)" \
    "deferred" "needs architect review" >/dev/null 2>&1
after=$(grep -cE '^\|.*\|.*\|' .curate/review-log.md || true)
if [[ "$before" == "$after" ]]; then
    pass "append no-ops on identical row"
else
    fail "append duplicated identical row" "before=$before after=$after"
fi

# ── Test 6: unresolved query returns deferred/suggested rows ────────────────
# Bug 2 contract: items with most-recent status `deferred` or `suggested`
# (and no later resolved/dismissed for the same key) are emitted by the
# unresolved query so the SKILL can re-present them.

echo ""
echo "── Test 6: unresolved query returns deferred + suggested rows"

unresolved_out=$(bash .claude/scripts/curate-review-log.sh unresolved \
    .curate/review-log.md 2>&1)

# adr-pressure (deferred), spec-drift (suggested), adr-gravity (deferred) — 3 rows.
# scan-bookkeeping (resolved) — must NOT appear.
if echo "$unresolved_out" | grep -q "adr-pressure:auth-session-storage" \
   && echo "$unresolved_out" | grep -q "spec-drift:foo" \
   && echo "$unresolved_out" | grep -q "adr-gravity:cache-strategy"; then
    pass "all three deferred/suggested rows surface"
else
    fail "unresolved query missed rows" "got: $unresolved_out"
fi

if echo "$unresolved_out" | grep -q "scan-bookkeeping:index-overflow"; then
    fail "unresolved query incorrectly returned a resolved row"
else
    pass "resolved row correctly excluded"
fi

# ── Test 7: later resolved/dismissed supersedes earlier deferred ────────────
# When a row appears with status `resolved` AFTER a deferred row for the
# same key, the unresolved query must NOT return that key.

echo ""
echo "── Test 7: later resolution supersedes earlier deferral"

bash .claude/scripts/curate-review-log.sh append \
    .curate/review-log.md 2026-05-05 \
    "adr-gravity:cache-strategy" \
    "ADR gravity on cache-strategy" \
    "resolved" "addressed via /architect" >/dev/null 2>&1

unresolved_out=$(bash .claude/scripts/curate-review-log.sh unresolved \
    .curate/review-log.md 2>&1)
if echo "$unresolved_out" | grep -q "adr-gravity:cache-strategy"; then
    fail "later-resolved row still appearing in unresolved set"
else
    pass "later-resolved supersedes earlier deferred"
fi

# ── Test 8: scan after re-scan still emits the same pressure finding ────────
# Bug 3 contract: running /curate twice in close succession (the
# user-reported symptom) does not cause pressure to vanish. The signal
# stays visible until either resolved or pre-recent activity ages out.

echo ""
echo "── Test 8: pressure persists across consecutive scans"

# Touch one more ADR-constrained file to advance HEAD.
echo "// edit 6" >> "$PROJECT/src/auth/middleware.ts"
git -C "$PROJECT" add -A
git -C "$PROJECT" commit -m "another edit" >/dev/null 2>&1

# Update LAST_SHA to current HEAD-1 (so we have a 1-commit incremental window).
NEW_LAST=$(git -C "$PROJECT" rev-parse HEAD~1)
cat > .curate/curation-state.md <<EOF
# Curation State

## Scan State
Last scanned: $NEW_LAST
Last scanned date: 2026-05-04
EOF

bash .claude/scripts/curate-scan.sh >/dev/null 2>&1 || true

if sed -n '/^## ADR Pressure/,/^## /p' .curate/scan-summary.md \
        | grep -q "auth-session-storage"; then
    pass "pressure on auth-session-storage still reported on consecutive scan"
else
    fail "pressure vanished on consecutive small-delta scan" \
         "scan-summary: $(cat .curate/scan-summary.md | head -30)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "──────────────────────────────────────────────────────────────────"
if [[ $failed -eq 0 ]]; then
    echo "ALL PASSED  ($passed/$total)"
else
    echo "FAILED  $failed/$total  ($passed passed)"
fi
echo ""

exit $failed
