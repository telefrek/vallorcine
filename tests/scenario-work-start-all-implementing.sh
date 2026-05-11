#!/usr/bin/env bash
# Scenario: /work-start <group> all picks up stranded IMPLEMENTING WDs
#
# Real bug hit on jlsm: WD-01 was claimed by an earlier /work-start that
# crashed mid-pipeline (the nested-dispatch bug). WD-01 was left at
# status: IMPLEMENTING with status.md reflecting partial progress. The
# user ran /work-start <group> all to retry — but the enumeration only
# picked SPECIFIED WDs, so WD-01 fell through and required a separate
# manual /feature-resume.
#
# Fix: the all flow enumerates BOTH SPECIFIED and stranded IMPLEMENTING
# WDs, routing IMPLEMENTING ones through /feature-resume (not another
# /work-start, which would reject the SPECIFIED→IMPLEMENTING transition
# via work-claim.sh). SPECIFYING WDs (mid-/spec-author Pass 2) are
# surfaced as informational ("needs /work-plan") since arbitration is
# /work-plan's concern.
#
# Run from repo root: bash tests/scenario-work-start-all-implementing.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SKILL="$REPO_ROOT/skills/work-start/SKILL.md"

passed=0
failed=0
total=0

pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }

echo ""
echo "scenario: /work-start all picks up stranded IMPLEMENTING WDs"
echo "────────────────────────────────────────────────"

# ── Sequential-all flow enumerates both SPECIFIED and IMPLEMENTING ──────────

echo ""
echo "  Step 1 enumeration covers SPECIFIED + IMPLEMENTING"
echo "  ────────────────────────────────────────────────"

step1=$(awk '/^### Sequential-all flow/,/^2\. \*\*Show the plan/' "$SKILL")

if echo "$step1" | grep -qE '`specified`.*SPECIFIED'; then
    pass 'Step 1 declares `specified` set'
else
    fail 'Step 1 missing `specified` set'
fi

if echo "$step1" | grep -qE '`stranded_implementing`'; then
    pass 'Step 1 declares `stranded_implementing` set'
else
    fail 'Step 1 missing `stranded_implementing` set'
fi

if echo "$step1" | grep -qE '`needs_planning`.*SPECIFYING'; then
    pass 'Step 1 declares `needs_planning` set (SPECIFYING WDs)'
else
    fail 'Step 1 missing `needs_planning` set'
fi

# ── Routing: IMPLEMENTING uses /feature-resume, not another /work-start ────

echo ""
echo "  IMPLEMENTING routing uses /feature-resume"
echo "  ───────────────────────────────────────"

if echo "$step1" | tr '\n' ' ' | tr -s ' ' | grep -qE "Route these via .?/feature-resume"; then
    pass "Step 1 routes IMPLEMENTING WDs through /feature-resume"
else
    fail "Step 1 doesn't route IMPLEMENTING through /feature-resume"
fi

if echo "$step1" | grep -qE 'NOT another.*work-start|would.*re-trigger.*work-claim'; then
    pass "Step 1 warns against re-invoking /work-start on IMPLEMENTING"
else
    fail "Step 1 missing warning about /work-start re-invocation"
fi

# ── Active vs stranded distinction documented ──────────────────────────────

echo ""
echo "  Active vs stranded marker distinction"
echo "  ────────────────────────────────────"

if echo "$step1" | tr '\n' ' ' | tr -s ' ' | grep -qE "Active vs stranded distinction"; then
    pass "Step 1 documents the active vs stranded distinction"
else
    fail "Step 1 missing active vs stranded section"
fi

if echo "$step1" | grep -qE "30 minutes|30 min"; then
    pass "Step 1 names the stuck-marker threshold (30 min)"
else
    fail "Step 1 missing stuck-marker threshold"
fi

if echo "$step1" | tr '\n' ' ' | tr -s ' ' | grep -qE 'state .?begin.? and.*dispatched_at'; then
    pass "Step 1 checks marker dispatched_at for staleness"
else
    fail "Step 1 missing dispatched_at staleness check"
fi

# ── Plan display surfaces all three sets ───────────────────────────────────

echo ""
echo "  Plan display in Step 2"
echo "  ────────────────────"

step2=$(awk '/^2\. \*\*Show the plan/,/^3\. \*\*Iterate/' "$SKILL")

if echo "$step2" | grep -qE "Stranded IMPLEMENTING WDs to resume"; then
    pass "plan display shows stranded IMPLEMENTING count"
else
    fail "plan display missing IMPLEMENTING count"
fi

if echo "$step2" | grep -qE "SPECIFIED WDs to start"; then
    pass "plan display shows SPECIFIED count"
else
    fail "plan display missing SPECIFIED count"
fi

if echo "$step2" | grep -qE "SPECIFYING WD.*need /work-plan"; then
    pass "plan display surfaces SPECIFYING note (informational)"
else
    fail "plan display missing SPECIFYING note"
fi

if echo "$step2" | tr '\n' ' ' | tr -s ' ' | grep -qE "IMPLEMENTING WDs sort BEFORE SPECIFIED|IMPLEMENTING first"; then
    pass "plan documents IMPLEMENTING-first ordering"
else
    fail "plan missing IMPLEMENTING-first ordering rule"
fi

# ── Dispatch loop has two prompts (Prompt A + Prompt B) ────────────────────

echo ""
echo "  Dispatch loop has separate prompts per state"
echo "  ──────────────────────────────────────────"

step3d=$(awk '/^   d\. \*\*Dispatch ONE sub-agent/,/^   e\.|^   \*\*Wait/' "$SKILL")

if echo "$step3d" | grep -qE 'Prompt A.*SPECIFIED'; then
    pass "Step 3d defines Prompt A for SPECIFIED WDs"
else
    fail "Step 3d missing Prompt A"
fi

if echo "$step3d" | grep -qE 'Prompt B.*IMPLEMENTING'; then
    pass "Step 3d defines Prompt B for IMPLEMENTING WDs"
else
    fail "Step 3d missing Prompt B"
fi

# Prompt B should invoke /feature-resume, NOT /work-start
prompt_b=$(awk '/Prompt B — IMPLEMENTING/,/Nothing else after/' "$SKILL")

if echo "$prompt_b" | grep -qE 'Invoke /feature-resume'; then
    pass "Prompt B invokes /feature-resume"
else
    fail "Prompt B missing /feature-resume invocation"
fi

if echo "$prompt_b" | grep -qE 'Do NOT re-invoke /work-start|would.*reject.*transition'; then
    pass "Prompt B explicitly warns against re-invoking /work-start"
else
    fail "Prompt B missing /work-start re-invocation warning"
fi

# Both prompts share the same return-line classifier (consistency)
if echo "$prompt_b" | grep -qE 'COMPLETE.*ESCALATION_AT_.*STOPPED_AT_.*ERROR' \
   || echo "$prompt_b" | tr '\n' ' ' | grep -qE 'COMPLETE.*ESCALATION_AT_'; then
    pass "Prompt B uses the 5-way classifier shape (consistent with Prompt A)"
else
    fail "Prompt B return shape inconsistent with Prompt A"
fi

# ── Iteration loop picks from combined set ─────────────────────────────────

echo ""
echo "  Iteration picks from combined set"
echo "  ────────────────────────────────"

step3b=$(awk '/^   b\. \*\*Pick the next/,/^   c\./' "$SKILL")

if echo "$step3b" | tr '\n' ' ' | grep -qE "stranded_implementing.*specified|combined .stranded_implementing. .* .specified."; then
    pass "Step 3b picks from combined stranded_implementing ∪ specified"
else
    fail "Step 3b doesn't unify both sets"
fi

if echo "$step3b" | tr '\n' ' ' | tr -s ' ' | grep -qiE "IMPLEMENTING WDs sort before SPECIFIED|IMPLEMENTING first"; then
    pass "Step 3b sorts IMPLEMENTING before SPECIFIED"
else
    fail "Step 3b missing IMPLEMENTING-first ordering"
fi

if echo "$step3b" | tr '\n' ' ' | tr -s ' ' | grep -qE 're-evaluate.*active vs stranded|markers can flip'; then
    pass "Step 3b re-evaluates active vs stranded each iteration"
else
    fail "Step 3b doesn't refresh active/stranded between iterations"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "Total: $total | Passed: $passed | Failed: $failed"
echo ""

[[ $failed -eq 0 ]] && exit 0 || exit 1
