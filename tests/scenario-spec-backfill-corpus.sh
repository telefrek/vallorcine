#!/usr/bin/env bash
# Scenario: /spec-backfill corpus mode (--all) — HIGH cluster fixes
# from 2026-05-11 adversarial sweep.
#
# H1: spec-backfill-log.sh report uses latest-status semantics (covered
#     in scenario-spec-backfill.sh Test 14 — verifies the fix here too).
# H2: C0 stuck-marker recovery groups by spec-id (strip --propose /
#     --apply suffix) so the user sees one prompt per spec, not two.
# H3: C2f forward-progress re-loop for specs with >12 uncovered R-ids.
# H4: Skip Phase B dispatch when decision-set is empty no-op.
#
# This is contract validation against the SKILL.md text — runtime
# AskUserQuestion behavior can't be exercised in scenario tests.
#
# Run from repo root: bash tests/scenario-spec-backfill-corpus.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SKILL="$REPO_ROOT/skills/spec-backfill/SKILL.md"

passed=0; failed=0; total=0
pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }

echo ""
echo "scenario: /spec-backfill corpus mode (HIGH cluster 2)"
echo "────────────────────────────────────────────────"

# ── H2: C0 stuck-marker grouping by spec-id ────────────────────────────────

echo ""
echo "  H2 — C0 groups stuck markers by spec-id (strip --propose/--apply)"
echo "  ───────────────────────────────────────────────────────────────"

c0=$(awk '/^### C0\. Pre-flight: surface stuck dispatches/,/^### C1/' "$SKILL")

if echo "$c0" | grep -qE 'suffixed|--propose|--apply'; then
    pass "C0 acknowledges marker suffix convention"
else
    fail "C0 missing marker suffix convention"
fi

if echo "$c0" | grep -qE 'Group stuck markers by spec-id|group.*by spec-id'; then
    pass "C0 prescribes grouping by spec-id"
else
    fail "C0 doesn't prescribe grouping by spec-id"
fi

if echo "$c0" | grep -qE '\$\{id%--\*\}|strip.*suffix'; then
    pass "C0 names the suffix-strip pattern"
else
    fail "C0 missing suffix-strip pattern reference"
fi

# Per-marker routing table should distinguish three cases
for marker_case in "propose. only" "apply. only" "Both"; do
    if echo "$c0" | grep -qE "$marker_case"; then
        pass "C0 routing covers: $marker_case"
    else
        fail "C0 routing missing case: $marker_case"
    fi
done

if echo "$c0" | grep -qE 'AskUserQuestion'; then
    pass "C0 uses AskUserQuestion (no prose recommendations)"
else
    fail "C0 missing AskUserQuestion"
fi

# ── H3: C2f forward-progress re-loop ───────────────────────────────────────

echo ""
echo "  H3 — C2f forward-progress re-loop for >12 uncovered R-ids"
echo "  ─────────────────────────────────────────────────────────"

c2f=$(awk '/^\*\*C2f\. Forward-progress re-loop/,/^\*\*C2g\. Honor the cap/' "$SKILL")

if [[ -n "$c2f" ]]; then
    pass "C2f section exists"
else
    fail "C2f section missing"
fi

if echo "$c2f" | grep -qE 'more_remain'; then
    pass "C2f references more_remain flag"
else
    fail "C2f doesn't reference more_remain"
fi

if echo "$c2f" | grep -qE 'forward progress.*zero|zero forward progress'; then
    pass "C2f handles zero-forward-progress case (stop iterating)"
else
    fail "C2f missing zero-forward-progress termination"
fi

if echo "$c2f" | grep -qE '3 iterations|cap.*iterations'; then
    pass "C2f caps re-loop iterations (anti-pathology)"
else
    fail "C2f missing iteration cap"
fi

if echo "$c2f" | grep -qE 'annotate.*waive|terminal in the log'; then
    pass "C2f counts annotate/waive as forward progress"
else
    fail "C2f forward-progress definition unclear"
fi

# ── H4: Skip empty Phase B dispatch ────────────────────────────────────────

echo ""
echo "  H4 — Skip Phase B dispatch when decision-set is no-op"
echo "  ───────────────────────────────────────────────────"

# The guard lives between C2c (build decision-set) and C2d (dispatch
# Phase B). Look in the C2c–C2d transition area.
c2_guard=$(awk '/^The decision-set lives in coordinator/,/^\*\*C2d/' "$SKILL")

if echo "$c2_guard" | grep -qE 'Skip Phase B|decision-set is no-op'; then
    pass "guard exists between C2c and C2d"
else
    fail "skip-empty guard missing"
fi

if echo "$c2_guard" | grep -qE 'all uncovered R-ids already terminal|already_decided'; then
    pass "guard recognizes already_decided-only case"
else
    fail "guard doesn't recognize re-run-after-completion"
fi

if echo "$c2_guard" | grep -qE 'ack the propose marker|ack.*propose'; then
    pass "guard still acks the propose marker on skip"
else
    fail "guard would leave propose marker stuck"
fi

if echo "$c2_guard" | grep -qE 'ONLY .skip. actions|only.*skip.*actions'; then
    pass "guard distinguishes skip-only (still dispatch) from all-terminal (skip)"
else
    fail "guard doesn't distinguish skip-only from no-op cases"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "Total: $total | Passed: $passed | Failed: $failed"
echo ""

[[ $failed -eq 0 ]] && exit 0 || exit 1
