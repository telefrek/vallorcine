#!/usr/bin/env bash
# Scenario: pipeline skills must not hang in parallel-mode subagents.
#
# Two structural invariants defend against the 2026-04-23 WU-3 hang
# (subagent completed its work but never emitted its final summary, so
# the coordinator stayed blocked on the Agent tool call):
#
# 1. Every AskUserQuestion site in the skills a coordinator dispatches
#    (/feature-test, /feature-implement, /feature-refactor) must either
#    live under an `automation_mode: manual` branch (doesn't fire in
#    parallel mode — coordinator always sets autonomous), or be preceded
#    by a `balanced | speed` bypass that records to cycle-log + returns
#    ESCALATED instead of waiting for input.
#
# 2. /feature-refactor's parallel-mode exit block must contain an
#    explicit termination contract ("your next message MUST be the
#    summary — no more tools"), and /feature-coordinate must document
#    the subagent dispatch contract so coordinators embed it verbatim.
#
# This is a grep-based structural test: it doesn't exercise the runtime
# coordinator, it validates that the SKILL.md files still contain the
# mode-gating prose. If someone adds a new AskUserQuestion without
# gating, this test fails fast.
#
# Run from repo root: bash tests/scenario-parallel-subagent-hang-prevention.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

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

echo ""
echo "scenario: parallel subagent hang prevention"
echo "────────────────────────────────────────────────"

# ── Invariant 1: /feature-coordinate carries the dispatch contract ───────────

echo ""
echo "── Invariant 1: /feature-coordinate dispatch contract"

coord_skill="$REPO_ROOT/skills/feature-coordinate/SKILL.md"

if grep -q "Subagent dispatch contract" "$coord_skill" && \
   grep -q "Termination contract" "$coord_skill" && \
   grep -q "Return format" "$coord_skill"; then
    pass "/feature-coordinate documents Subagent dispatch + Termination + Return format"
else
    fail "/feature-coordinate missing dispatch contract sections" \
         "expected: 'Subagent dispatch contract' + 'Termination contract' + 'Return format'"
fi

if grep -q "2026-04-23" "$coord_skill"; then
    pass "/feature-coordinate references the 2026-04-23 hang root-cause"
else
    fail "/feature-coordinate should document the hang root-cause date"
fi

# ── Invariant 2: /feature-refactor parallel-mode exit is strict ──────────────

echo ""
echo "── Invariant 2: /feature-refactor parallel-mode termination contract"

refactor_skill="$REPO_ROOT/skills/feature-refactor/SKILL.md"

# The parallel-mode exit block must tell the subagent to emit the summary
# IMMEDIATELY after marking status.md complete — no more tools.
parallel_block="$(sed -n '/Subagent termination contract/,/Emit that block as your final message/p' "$refactor_skill")"

if [[ -n "$parallel_block" ]]; then
    pass "refactor parallel-mode exit has termination contract block"
else
    fail "refactor parallel-mode exit missing termination contract" \
         "expected 'Subagent termination contract' + 'Emit that block as your final message'"
fi

if echo "$parallel_block" | grep -q "no more Read, Bash, Grep, Edit"; then
    pass "termination contract explicitly lists forbidden post-completion tools"
else
    fail "termination contract should enumerate forbidden tools"
fi

if echo "$parallel_block" | grep -q "WU-3"; then
    pass "termination contract cites WU-3 hang evidence"
else
    fail "termination contract should cite the WU-3 concrete case"
fi

# ── Invariant 3: AskUserQuestion sites are mode-gated or manual-only ─────────

echo ""
echo "── Invariant 3: AskUserQuestion sites gated for parallel mode"

# For each AskUserQuestion line in the 3 pipeline skills, check that it is
# EITHER:
#   (a) preceded (within 30 lines above) by a `balanced | speed` bypass
#   (b) under an `automation_mode: manual` block (within 20 lines above)
# Otherwise it's a potential hang point in a parallel subagent.

check_aukq_gated() {
    local file="$1"
    local name="$2"
    local ungated=0
    local ungated_lines=""

    while IFS= read -r ln; do
        local above_start=$((ln - 30))
        (( above_start < 1 )) && above_start=1
        local context
        context="$(sed -n "${above_start},${ln}p" "$file")"

        # (a) parallel-mode bypass within 30 lines above
        if echo "$context" | grep -qE 'balanced.*speed|speed.*balanced|execution_strategy.*balanced'; then
            continue
        fi
        # (b) manual-mode-only branch within 20 lines above.
        #     Authoritative markers: explicit automation_mode text, a
        #     "Sequential/cost mode:" bypass header, or the prose
        #     "— Manual:" subheading used within already-mode-gated
        #     sections like "sequential/cost mode only".
        local manual_start=$((ln - 20))
        (( manual_start < 1 )) && manual_start=1
        local manual_ctx
        manual_ctx="$(sed -n "${manual_start},${ln}p" "$file")"
        if echo "$manual_ctx" | grep -qE 'automation_mode.*manual|Sequential/cost mode|`manual` \(or not set\)|^— Manual:|^\*\*If `automation_mode: manual`'; then
            continue
        fi

        ungated=$((ungated + 1))
        ungated_lines="${ungated_lines}${ln} "
    done < <(grep -n "^Use AskUserQuestion\|^[[:space:]]*Use AskUserQuestion" "$file" | cut -d: -f1)

    if (( ungated == 0 )); then
        pass "$name: all AskUserQuestion sites are mode-gated"
    else
        fail "$name: $ungated ungated AskUserQuestion site(s)" \
             "lines: $ungated_lines — each must be preceded by a parallel-mode bypass or live under a manual-only branch"
    fi
}

check_aukq_gated "$REPO_ROOT/skills/feature-test/SKILL.md" "/feature-test"
check_aukq_gated "$REPO_ROOT/skills/feature-implement/SKILL.md" "/feature-implement"
check_aukq_gated "$REPO_ROOT/skills/feature-refactor/SKILL.md" "/feature-refactor"

# ── Invariant 4: Mode-gate clauses include escalation semantics ──────────────

echo ""
echo "── Invariant 4: parallel-mode bypasses write to cycle-log + return ESCALATED"

# Each skill that has parallel-mode bypass blocks should consistently
# record an escalation entry and mark substage `escalated-*` before
# returning. Check that the pattern appears in each file that has a
# bypass.

check_escalation_pattern() {
    local file="$1"
    local name="$2"
    if ! grep -q "balanced.*speed\|speed.*balanced" "$file"; then
        pass "$name: no parallel-mode bypasses (skill not used via coordinator)"
        return
    fi
    if grep -q "escalated-" "$file" && grep -q "ESCALATED" "$file"; then
        pass "$name: parallel bypasses set substage 'escalated-*' and return ESCALATED"
    else
        fail "$name: parallel bypasses missing escalation markers" \
             "expected both 'escalated-<kind>' substage writes and 'ESCALATED' return text"
    fi
}

check_escalation_pattern "$REPO_ROOT/skills/feature-test/SKILL.md" "/feature-test"
check_escalation_pattern "$REPO_ROOT/skills/feature-refactor/SKILL.md" "/feature-refactor"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
if [[ $failed -eq 0 ]]; then
    echo "ALL PASSED  ($passed/$total)"
    exit 0
else
    echo "FAILED  $failed/$total  ($passed passed)"
    exit 1
fi
