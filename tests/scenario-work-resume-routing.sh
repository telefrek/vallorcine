#!/usr/bin/env bash
# Scenario: /work-resume Step 5 routing uses AskUserQuestion + documents
# source-of-truth precedence (2026-05-11 adversarial findings HIGH #3,
# #4, #5, #6, #7).
#
# Pre-fix, Step 5 had 9 routing branches with ZERO AskUserQuestion calls
# — auto-mode Claude would execute the recommended command without
# pausing for input. Same problem in Step 2c. Plus rule 1 was dead code
# (decompose checkpoint already handled in Step 2). Plus the staleness
# check at Step 2a used GNU-only `date -d`. Plus the precedence between
# three state sources (frontmatter / orchestrator / readiness cache)
# was undocumented.
#
# This test validates the contract surface: SKILL.md must mention
# AskUserQuestion in every routing decision, the dead rule is gone,
# date parsing has a GNU+BSD fallback, and the precedence section
# exists in Implementation Notes.
#
# Run from repo root: bash tests/scenario-work-resume-routing.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SKILL="$REPO_ROOT/skills/work-resume/SKILL.md"

passed=0; failed=0; total=0
pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }

echo ""
echo "scenario: /work-resume routing + precedence (HIGH cluster 1)"
echo "────────────────────────────────────────────────"

# ── H4: dead rule 1 removed ─────────────────────────────────────────────────

echo ""
echo "  H4 — dead rule 1 ('_decompose-progress.md already handled') removed"
echo "  ──────────────────────────────────────────────────────────────"

step5=$(awk '/^## Step 5 — Determine the next command/,/^## Implementation notes/' "$SKILL")

# The old "1. Any _decompose-progress.md exists → already handled in Step 2"
# string should be gone.
if echo "$step5" | grep -qE '_decompose-progress\.md exists.*already handled'; then
    fail "dead rule 1 still in Step 5"
else
    pass "dead rule 1 removed"
fi

# Rules should now be numbered 0, 1, 2, 3, 4, 5, 6, 7, 8 (no gap).
# After removing the old rule 1, the rest renumber down.
for n in 0 1 2 3 4 5 6 7 8; do
    if echo "$step5" | grep -qE "^${n}\. \*\*"; then
        pass "rule $n exists in Step 5"
    else
        fail "rule $n missing in Step 5"
    fi
done

# ── H3: Step 5 routing uses AskUserQuestion ────────────────────────────────

echo ""
echo "  H3 — Step 5 routing uses AskUserQuestion (no prose NEXT STEP blocks)"
echo "  ──────────────────────────────────────────────────────────────────"

# Step 5 introduction explicitly says every recommendation MUST use
# AskUserQuestion.
if echo "$step5" | grep -qE "MUST use .?AskUserQuestion.? to confirm"; then
    pass "Step 5 intro mandates AskUserQuestion for every recommendation"
else
    fail "Step 5 intro doesn't mandate AskUserQuestion"
fi

# Each rule should explicitly mention AskUserQuestion. Count rules and
# count AskUserQuestion mentions within Step 5.
au_count=$(echo "$step5" | grep -cE "AskUserQuestion" || true)
if (( au_count >= 9 )); then
    pass "Step 5 references AskUserQuestion at least once per rule ($au_count occurrences)"
else
    fail "Step 5 has only $au_count AskUserQuestion references (need >= 9)"
fi

# No "NEXT STEP" prose blocks should remain in Step 5 (the bad pattern).
# Allow the literal phrase in the intro paragraph that EXPLAINS the
# pattern was bad.
next_step_blocks=$(echo "$step5" | grep -cE '^\s*NEXT STEP\b' || true)
if (( next_step_blocks == 0 )); then
    pass "no prose 'NEXT STEP' blocks remain in Step 5"
else
    fail "$next_step_blocks prose 'NEXT STEP' block(s) still in Step 5"
fi

# Specifically: the rule-0 stuck-marker actions previously prose'd
# "Recommend re-dispatch: /work-start..." — verify they use
# AskUserQuestion now too.
rule0=$(awk '/^0\. \*\*Any unacknowledged dispatch marker/,/^1\. \*\*/' "$SKILL")
if echo "$rule0" | grep -qE "AskUserQuestion"; then
    pass "rule 0 (stuck markers) uses AskUserQuestion per marker"
else
    fail "rule 0 still routes via prose"
fi

# ── H5: Step 2a 7-day staleness uses cross-platform date fallback ──────────

echo ""
echo "  H5 — Step 2a date parsing has GNU + BSD fallback"
echo "  ──────────────────────────────────────────────"

step2a=$(awk '/^### Step 2a — Detect orphan checkpoints/,/^For an \*\*orphan\*\*/' "$SKILL")

if echo "$step2a" | grep -qE 'date -u -d.*date -u -j -f|GNU.*BSD'; then
    pass "Step 2a documents GNU + BSD date fallback chain"
else
    fail "Step 2a date parsing not cross-platform"
fi

if echo "$step2a" | grep -qE 'phase_a_complete_at'; then
    pass "Step 2a names the timestamp field"
else
    fail "Step 2a missing timestamp field reference"
fi

if echo "$step2a" | grep -qE '604800'; then
    pass "Step 2a uses 7 days = 604800 seconds threshold"
else
    fail "Step 2a missing 7-day threshold constant"
fi

# ── H6: Step 2c routing uses AskUserQuestion ───────────────────────────────

echo ""
echo "  H6 — Step 2c orchestrator routing uses AskUserQuestion"
echo "  ─────────────────────────────────────────────────────"

step2c=$(awk '/^## Step 2c — Detect orchestrator state/,/^## Step 3/' "$SKILL")

if echo "$step2c" | grep -qE "AskUserQuestion"; then
    pass "Step 2c uses AskUserQuestion for routing"
else
    fail "Step 2c missing AskUserQuestion"
fi

# Should NOT have prose "Recommend..." routing
prose_rec=$(echo "$step2c" | grep -cE '^\s*-\s+(Run|Inspect)' || true)
# Allowed: bullet lists of options (under AskUserQuestion). The bad
# pattern is "Recommend X" as prose. Check the absence of that.
if echo "$step2c" | grep -qE "the user's next action is usually"; then
    fail "Step 2c still has prose 'next action' recommendation"
else
    pass "Step 2c removed prose 'next action' recommendation"
fi

# ── H7: source-of-truth precedence documented ─────────────────────────────

echo ""
echo "  H7 — source-of-truth precedence section in Implementation Notes"
echo "  ────────────────────────────────────────────────────────────"

impl_notes=$(awk '/^## Implementation notes/,/^$/' "$SKILL")
# Awk above won't match across multiple blank lines; widen.
impl_notes=$(awk '/^## Implementation notes/{p=1} p' "$SKILL")

if echo "$impl_notes" | grep -qE "Source-of-truth precedence"; then
    pass "Implementation Notes has 'Source-of-truth precedence' section"
else
    fail "missing precedence section in Implementation Notes"
fi

if echo "$impl_notes" | tr '\n' ' ' | tr -s ' ' | grep -qE "in-flight.*>.*frontmatter.*>.*cache|in-flight/.*frontmatter.*readiness"; then
    pass "precedence order documented (orchestrator > frontmatter > cache)"
else
    fail "precedence order not documented"
fi

# Suppression rule: Step 2c must mention suppressing Step 5 routing for
# WDs that appear in the orchestrator state.
if echo "$step2c" | grep -qE "[Ss]uppress.*Step 5"; then
    pass "Step 2c suppresses Step 5 routing for WDs in orchestrator state"
else
    fail "Step 2c doesn't suppress Step 5 for orchestrator WDs"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "Total: $total | Passed: $passed | Failed: $failed"
echo ""

[[ $failed -eq 0 ]] && exit 0 || exit 1
