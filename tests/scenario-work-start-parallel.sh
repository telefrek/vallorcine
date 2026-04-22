#!/usr/bin/env bash
# Scenario: /work-start --parallel mode is documented and integrates cleanly.
#
# /work-start's parallel mode dispatches multiple sub-agents, which cannot be
# exercised in a scenario test (sub-agent orchestration requires the Claude
# runtime). This test validates the contract: that the SKILL.md documents
# the flag in the header, describes the parallel flow, and wires into
# work-resolve.sh's existing output so a runtime implementation has an
# unambiguous spec to follow.
#
# Run from repo root: bash tests/scenario-work-start-parallel.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SKILL="$REPO_ROOT/skills/work-start/SKILL.md"
RESOLVE="$REPO_ROOT/scripts/work-resolve.sh"
TEST_BASE="/tmp/vallorcine/scenario-work-start-parallel"

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
echo "scenario: /work-start --parallel"
echo "────────────────────────────────────────────────"

# ── SKILL.md argument-hint and usage ────────────────────────────────────────

echo ""
echo "  Flag declared in skill header"
echo "  ─────────────────────────────"

if grep -qE '^argument-hint:.*--parallel' "$SKILL"; then
    pass "argument-hint lists --parallel"
else
    fail "argument-hint missing --parallel"
fi

if grep -qE '# /work-start.*--parallel' "$SKILL"; then
    pass "usage header lists --parallel"
else
    fail "usage header missing --parallel"
fi

# ── Dedicated 'Parallel mode' section ───────────────────────────────────────

echo ""
echo "  Parallel-mode section"
echo "  ─────────────────────"

if grep -q "^## Parallel mode" "$SKILL"; then
    pass "has ## Parallel mode section"
else
    fail "missing ## Parallel mode section"
fi

for topic in "When to use parallel mode" "When NOT to use parallel mode" "Parallel-mode flow" "Concurrency caveats"; do
    if grep -qF "$topic" "$SKILL"; then
        pass "Parallel mode covers '$topic'"
    else
        fail "missing topic: '$topic'"
    fi
done

# ── Flow sub-steps are present ──────────────────────────────────────────────

echo ""
echo "  Flow mechanics"
echo "  ──────────────"

for phrase in \
    "Enumerate startable WDs" \
    "Cap concurrency" \
    "Create feature directories (all WDs, sequential)" \
    "Dispatch sub-agents concurrently" \
    "Aggregate results"
do
    if grep -qF "$phrase" "$SKILL"; then
        pass "flow step: '$phrase'"
    else
        fail "missing flow step: '$phrase'"
    fi
done

# ── Early-exit contract: Step 3 shortcircuits for --parallel ────────────────

echo ""
echo "  Step 3 shortcircuit"
echo "  ───────────────────"

if grep -qF 'If `--parallel` flag is present' "$SKILL"; then
    pass "Step 3 shortcircuits when --parallel set"
else
    fail "Step 3 missing --parallel shortcircuit"
fi

# ── Dispatch contract: sub-agent prompt explicit ────────────────────────────

echo ""
echo "  Sub-agent prompt contract"
echo "  ─────────────────────────"

if grep -q "parallel pipeline runner" "$SKILL"; then
    pass "sub-agent prompt identifies role"
else
    fail "sub-agent prompt role missing"
fi

if grep -q "single message with multiple Agent tool calls" "$SKILL"; then
    pass "dispatch uses parallel Agent calls in one message"
else
    fail "parallel dispatch pattern undocumented"
fi

if grep -q "Return a single summary line" "$SKILL"; then
    pass "sub-agent return contract specified"
else
    fail "sub-agent return contract missing"
fi

# ── Concurrency caveats cover real hazards ──────────────────────────────────

echo ""
echo "  Concurrency caveats"
echo "  ───────────────────"

for hazard in "Shared KB" "Shared spec writes" "Test runner contention" "Token / cost budget"; do
    if grep -qF "$hazard" "$SKILL"; then
        pass "caveat: '$hazard'"
    else
        fail "missing caveat: '$hazard'"
    fi
done

# ── Parsing contract: work-resolve.sh output has SPECIFIED rows ─────────────

echo ""
echo "  work-resolve.sh contract"
echo "  ────────────────────────"

# The parallel flow parses SPECIFIED rows from work-resolve.sh output. That
# output format must still emit SPECIFIED status in the table. Confirm by
# running work-resolve on a synthetic group and checking the output shape.

cleanup
mkdir -p "$TEST_BASE/project/.work/parallel-group"
cd "$TEST_BASE/project"

cat > ".work/parallel-group/WD-01.md" << 'EOF'
---
id: WD-01
title: First parallel WD
group: parallel-group
status: SPECIFIED
domains: [auth]
---

## Summary
Test WD.

## Acceptance Criteria
Test.
EOF

cat > ".work/parallel-group/WD-02.md" << 'EOF'
---
id: WD-02
title: Second parallel WD
group: parallel-group
status: SPECIFIED
domains: [auth]
---

## Summary
Test WD.

## Acceptance Criteria
Test.
EOF

if output="$(bash "$RESOLVE" parallel-group 2>/dev/null)"; then
    specified_rows=$(echo "$output" | grep -cE '\| SPECIFIED \|' || true)
    if (( specified_rows == 2 )); then
        pass "work-resolve emits SPECIFIED rows that parallel mode can parse"
    else
        fail "expected 2 SPECIFIED rows from work-resolve" \
            "got $specified_rows — output: $output"
    fi
else
    fail "work-resolve.sh failed on synthetic group" "got: $output"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
if [[ $failed -eq 0 ]]; then
    echo "ALL PASSED  ($passed/$total)"
else
    echo "FAILED  $failed/$total  ($passed passed)"
fi
echo ""

exit $failed
