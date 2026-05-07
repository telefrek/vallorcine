#!/usr/bin/env bash
# Scenario: work-index.sh maintains .work/CLAUDE.md Active Work Groups
# table without hand-edits.
#
# Tests:
# 1. add appends a new row to Active Work Groups + Recently Added log
# 2. add is idempotent — second add for same slug falls through to update
# 3. update recomputes WDs / Ready / Complete from WD frontmatter
# 4. update preserves the existing Path and Goal columns
# 5. update bumps Last Updated to today
# 6. update-all iterates every group directory under .work/
# 7. remove drops the row from Active Work Groups
# 8. update on an unknown slug fails with a clear error
# 9. add rejects pipe characters in goal so the table cannot be split
# 10. update reflects status changes (READY → COMPLETE)
#
# Run from repo root: bash tests/scenario-work-index.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-work-index"
INDEX_SCRIPT="$REPO_ROOT/scripts/work-index.sh"

passed=0; failed=0; total=0
pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }
cleanup() { rm -rf "$TEST_BASE" 2>/dev/null || true; }
trap cleanup EXIT

echo ""
echo "scenario: work-index Active Work Groups maintenance"
echo "────────────────────────────────────────────────"

cleanup
mkdir -p "$TEST_BASE/project/.work/auth-migration" \
         "$TEST_BASE/project/.work/billing-overhaul" \
         "$TEST_BASE/project/.claude/scripts"

cp "$REPO_ROOT/scripts/work-index.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-lib.sh"   "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/work/CLAUDE.md"        "$TEST_BASE/project/.work/CLAUDE.md"

cd "$TEST_BASE/project"

# Two WD fixtures to drive the count math.
cat > .work/auth-migration/WD-01.md << 'EOF'
---
id: WD-01
title: JWT library
group: auth-migration
status: COMPLETE
domains: [auth]
---
EOF
cat > .work/auth-migration/WD-02.md << 'EOF'
---
id: WD-02
title: Auth middleware
group: auth-migration
status: READY
domains: [auth]
---
EOF
cat > .work/billing-overhaul/WD-01.md << 'EOF'
---
id: WD-01
title: Charge processor
group: billing-overhaul
status: DRAFT
domains: [billing]
---
EOF

# ── Test 1: add appends Active Work Groups + Recently Added rows ────────────

echo ""
echo "── Test 1: add appends Active Work Groups + Recently Added rows"

bash "$INDEX_SCRIPT" add auth-migration "Replace session auth with JWT" >/dev/null 2>&1
if grep -qF "| auth-migration | .work/auth-migration/ | Replace session auth with JWT |" .work/CLAUDE.md; then
    pass "Active Work Groups row appended for auth-migration"
else
    fail "Active Work Groups row missing" "got: $(grep auth-migration .work/CLAUDE.md)"
fi
if grep -qE '^\| 20[0-9]{2}-[0-9]{2}-[0-9]{2} \| auth-migration \| — \| — \| active \|' .work/CLAUDE.md; then
    pass "Recently Added log row appended"
else
    fail "Recently Added log row missing" "got: $(grep -A 5 'Recently Added' .work/CLAUDE.md)"
fi

# ── Test 2: add is idempotent on same slug ─────────────────────────────────

echo ""
echo "── Test 2: add is idempotent (second add falls through to update)"

bash "$INDEX_SCRIPT" add auth-migration "different goal" >/dev/null 2>&1
row_count=$(grep -cF "| auth-migration |" .work/CLAUDE.md)
if [[ "$row_count" -eq 2 ]]; then
    # 1 in Active Work Groups + 1 in Recently Added (the latter is a log
    # — even idempotent add re-falls to update, no extra log row should
    # appear)
    pass "second add for same slug does not duplicate Active Work Groups row"
else
    fail "expected 2 rows mentioning auth-migration (active + recent), got $row_count" \
         "$(grep -nF '| auth-migration |' .work/CLAUDE.md)"
fi

# ── Test 3: update recomputes WDs / Ready / Complete ───────────────────────

echo ""
echo "── Test 3: update recomputes WDs / Ready / Complete"

bash "$INDEX_SCRIPT" update auth-migration >/dev/null 2>&1
# auth-migration has 2 WDs: 1 COMPLETE, 1 READY. Expect 2 / 1 / 1.
if grep -qE '^\| auth-migration \| .work/auth-migration/ \| .* \| 2 \| 1 \| 1 \|' .work/CLAUDE.md; then
    pass "counts recomputed to 2 WDs / 1 ready / 1 complete"
else
    fail "expected counts 2/1/1 for auth-migration" "got: $(grep -F '| auth-migration |' .work/CLAUDE.md | head -1)"
fi

# ── Test 4: update preserves existing Path and Goal columns ────────────────

echo ""
echo "── Test 4: update preserves Path and Goal"

if grep -qF "| auth-migration | .work/auth-migration/ | Replace session auth with JWT |" .work/CLAUDE.md; then
    pass "Path and Goal preserved across update"
else
    fail "Path or Goal got rewritten" "got: $(grep -F '| auth-migration |' .work/CLAUDE.md | head -1)"
fi

# ── Test 5: update bumps Last Updated to today ─────────────────────────────

echo ""
echo "── Test 5: update bumps Last Updated to today"

today=$(date +%F)
if grep -qE "^\| auth-migration \|.* \| $today \|" .work/CLAUDE.md; then
    pass "Last Updated bumped to today ($today)"
else
    fail "Last Updated not bumped to $today" "got: $(grep -F '| auth-migration |' .work/CLAUDE.md | head -1)"
fi

# ── Test 6: update-all iterates every group ────────────────────────────────

echo ""
echo "── Test 6: update-all iterates every group directory"

# Add billing-overhaul first so update-all has a row to refresh.
bash "$INDEX_SCRIPT" add billing-overhaul "Modernize charge handling" >/dev/null 2>&1
bash "$INDEX_SCRIPT" update-all >/dev/null 2>&1
# billing-overhaul has 1 DRAFT WD: 1 / 0 / 0
if grep -qE '^\| billing-overhaul \| .work/billing-overhaul/ \| .* \| 1 \| 0 \| 0 \|' .work/CLAUDE.md; then
    pass "update-all refreshed billing-overhaul to 1/0/0"
else
    fail "billing-overhaul not refreshed by update-all" "got: $(grep -F '| billing-overhaul |' .work/CLAUDE.md | head -1)"
fi

# ── Test 7: remove drops the row ───────────────────────────────────────────

echo ""
echo "── Test 7: remove drops the Active Work Groups row"

bash "$INDEX_SCRIPT" remove billing-overhaul >/dev/null 2>&1
if ! grep -qF "| billing-overhaul | .work/billing-overhaul/" .work/CLAUDE.md; then
    pass "Active Work Groups row dropped for billing-overhaul"
else
    fail "row not removed" "got: $(grep -F billing-overhaul .work/CLAUDE.md)"
fi

# ── Test 8: update on unknown slug fails with clear error ──────────────────

echo ""
echo "── Test 8: update on unknown slug fails with clear error"

set +e
out=$(bash "$INDEX_SCRIPT" update never-existed 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]] && echo "$out" | grep -q "group not found"; then
    pass "update on unknown slug returns nonzero with clear error"
else
    fail "update on unknown slug should error" "rc=$rc out: $out"
fi

# ── Test 9: pipe characters in goal sanitized ──────────────────────────────

echo ""
echo "── Test 9: pipe characters in goal are sanitized"

mkdir -p .work/piped
cat > .work/piped/WD-01.md << 'EOF'
---
id: WD-01
title: Piped
group: piped
status: DRAFT
---
EOF
bash "$INDEX_SCRIPT" add piped "goal|with|pipes" >/dev/null 2>&1
# Pipes should be replaced with slashes (preserves table column structure)
if grep -qF "| piped | .work/piped/ | goal/with/pipes |" .work/CLAUDE.md; then
    pass "pipes replaced with slashes (table integrity preserved)"
else
    fail "pipes not sanitized" "got: $(grep -F '| piped |' .work/CLAUDE.md | head -1)"
fi

# ── Test 10: update reflects status change (READY → COMPLETE) ──────────────

echo ""
echo "── Test 10: update reflects status changes on existing WDs"

# Flip WD-02 from READY to COMPLETE — auth-migration becomes 2/0/2
sed -i 's/^status: READY$/status: COMPLETE/' .work/auth-migration/WD-02.md
bash "$INDEX_SCRIPT" update auth-migration >/dev/null 2>&1
if grep -qE '^\| auth-migration \|.* \| 2 \| 0 \| 2 \|' .work/CLAUDE.md; then
    pass "update picked up READY → COMPLETE transition"
else
    fail "update didn't reflect status change" "got: $(grep -F '| auth-migration |' .work/CLAUDE.md | head -1)"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────"
if [[ $failed -eq 0 ]]; then
    echo "ALL PASSED  ($passed/$total)"
else
    echo "FAILED  $failed/$total  ($passed passed)"
fi
exit $failed
