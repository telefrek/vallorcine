#!/usr/bin/env bash
# Scenario: user-required escalation contract is documented in /work-start.
#
# Like scenario-work-start-parallel.sh, the actual sub-agent dispatch
# cannot be exercised in a scenario test — sub-agent orchestration
# requires the Claude runtime. This test validates the documented
# contract: that the SKILL.md has all the pieces a sub-agent and a
# parent need to implement and detect user-required escalations
# correctly. A future orchestrator (PR B) and /work-run skill (PR C)
# will be built against this contract.
#
# Run from repo root: bash tests/scenario-work-start-escalation.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SKILL="$REPO_ROOT/skills/work-start/SKILL.md"
TEST_BASE="/tmp/vallorcine/scenario-work-start-escalation"

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

cleanup
mkdir -p "$TEST_BASE"

echo ""
echo "scenario: /work-start user-required escalation contract"
echo "────────────────────────────────────────────────"

# ── Contract section exists ─────────────────────────────────────────────────

echo ""
echo "  Contract section in SKILL.md"
echo "  ────────────────────────────"

if grep -q "^## User-required escalation contract" "$SKILL"; then
    pass "has ## User-required escalation contract section"
else
    fail "missing ## User-required escalation contract section"
fi

# ── Categories enumerated ───────────────────────────────────────────────────

echo ""
echo "  Escalation categories"
echo "  ─────────────────────"

for cat in design-choice missing-context spec-conflict impossible other; do
    if grep -qF "\`$cat\`" "$SKILL"; then
        pass "category enumerated: $cat"
    else
        fail "category missing: $cat"
    fi
done

# ── escalation.json schema fields ───────────────────────────────────────────

echo ""
echo "  escalation.json schema fields"
echo "  ─────────────────────────────"

# Required fields the orchestrator + UI both depend on
for field in schema_version feature_slug wd_id group_slug raised_at \
             blocking_stage category question context; do
    if grep -qE "\"$field\"" "$SKILL"; then
        pass "schema field present: $field"
    else
        fail "schema field missing: $field"
    fi
done

# Optional but documented
for field in context_refs options; do
    if grep -qE "\"$field\"" "$SKILL"; then
        pass "optional schema field documented: $field"
    else
        fail "optional schema field missing: $field"
    fi
done

# ── Sub-agent obligations ───────────────────────────────────────────────────

echo ""
echo "  Sub-agent obligations on escalation"
echo "  ───────────────────────────────────"

if grep -qF "escalation.json" "$SKILL"; then
    pass "obligation: write escalation.json"
else
    fail "obligation missing: write escalation.json"
fi

if grep -qF "user-escalation" "$SKILL"; then
    pass "obligation: record user-escalation in cycle-log"
else
    fail "obligation missing: cycle-log entry"
fi

if grep -qF "awaiting-user-input" "$SKILL"; then
    pass "obligation: status.md substage awaiting-user-input"
else
    fail "obligation missing: substage transition"
fi

if grep -qE "ESCALATION_AT_<stage>" "$SKILL"; then
    pass "obligation: return ESCALATION_AT_<stage>"
else
    fail "obligation missing: return-line sentinel"
fi

# ── Both sub-agent prompts updated ──────────────────────────────────────────

echo ""
echo "  Sub-agent prompts carry escalation instructions"
echo "  ──────────────────────────────────────────────"

# Sequential mode prompt should mention USER-REQUIRED + escalation.json
seq_block=$(awk '/sequential pipeline runner/,/parses this string/' "$SKILL")
if echo "$seq_block" | grep -qF "USER-REQUIRED"; then
    pass "sequential prompt mentions USER-REQUIRED escalation"
else
    fail "sequential prompt missing USER-REQUIRED reference"
fi
if echo "$seq_block" | grep -qF "escalation.json"; then
    pass "sequential prompt instructs writing escalation.json"
else
    fail "sequential prompt missing escalation.json instruction"
fi
if echo "$seq_block" | grep -qF "ESCALATION_AT_<stage>"; then
    pass "sequential prompt documents ESCALATION_AT_<stage> return"
else
    fail "sequential prompt missing ESCALATION_AT return form"
fi

# Parallel mode prompt should likewise
par_block=$(awk '/parallel pipeline runner/,/^   \`\`\`$/' "$SKILL")
if echo "$par_block" | grep -qF "USER-REQUIRED"; then
    pass "parallel prompt mentions USER-REQUIRED escalation"
else
    fail "parallel prompt missing USER-REQUIRED reference"
fi
if echo "$par_block" | grep -qF "escalation.json"; then
    pass "parallel prompt instructs writing escalation.json"
else
    fail "parallel prompt missing escalation.json instruction"
fi
if echo "$par_block" | grep -qF "ESCALATION_AT_<stage>"; then
    pass "parallel prompt documents ESCALATION_AT_<stage> return"
else
    fail "parallel prompt missing ESCALATION_AT return form"
fi

# ── Classifier extended to 5-way in both modes ──────────────────────────────

echo ""
echo "  Classifier covers escalation in both modes"
echo "  ──────────────────────────────────────────"

# Sequential mode classifier (Step 3f)
seq_classifier=$(awk '/Classify the return and update the marker/,/Append to the aggregate. Display incrementally/' "$SKILL")
if echo "$seq_classifier" | grep -qF "Escalation return"; then
    pass "sequential classifier has Escalation return case"
else
    fail "sequential classifier missing Escalation return case"
fi
if echo "$seq_classifier" | tr '\n' ' ' | tr -s ' ' | grep -qF "Match \`ESCALATION_AT_\` before \`STOPPED_AT_\`"; then
    pass "sequential classifier documents match order"
else
    fail "sequential classifier missing match-order guidance"
fi
if echo "$seq_classifier" | grep -qF "escalation:<category>"; then
    pass "sequential classifier uses fail with escalation:<category>"
else
    fail "sequential classifier missing fail-with-category convention"
fi

# Parallel mode classifier (Step 6)
par_classifier=$(awk '/Aggregate results — classify each return/,/Concurrency caveats/' "$SKILL")
if echo "$par_classifier" | grep -qF "five-way classification"; then
    pass "parallel classifier upgraded to five-way"
else
    fail "parallel classifier still four-way"
fi
if echo "$par_classifier" | tr '\n' ' ' | tr -s ' ' | grep -qF "Match \`ESCALATION_AT_\` before \`STOPPED_AT_\`"; then
    pass "parallel classifier documents match order"
else
    fail "parallel classifier missing match-order guidance"
fi
if echo "$par_classifier" | grep -qF "escalation:<category>"; then
    pass "parallel classifier uses fail with escalation:<category>"
else
    fail "parallel classifier missing fail-with-category convention"
fi

# ── Summary block shows escalations distinctly ──────────────────────────────

echo ""
echo "  Summary block surfaces escalations distinctly"
echo "  ─────────────────────────────────────────────"

# The parallel summary block should include "Escalations awaiting user input"
if grep -qF "Escalations awaiting user input" "$SKILL"; then
    pass "summary line: Escalations awaiting user input"
else
    fail "summary missing: Escalations awaiting user input"
fi

# ── Sanity check: classifier match order is correct (sentinel test) ─────────

echo ""
echo "  Pattern-match sanity (real shell, not docs)"
echo "  ──────────────────────────────────────────"

# Pretend we got these return lines from sub-agents and verify the
# classifier order produces the right routing. This is a tiny shell
# version of what the LLM-driven classifier needs to do.

classify() {
    local line="$1"
    # Order matters: ESCALATION_AT_ must match before STOPPED_AT_ because
    # both contain `_AT_`. SKIPPED before ERROR is incidental.
    case "$line" in
        *": COMPLETE — "*)          echo "clean" ;;
        *": ESCALATION_AT_"*" — "*) echo "escalation" ;;
        *": SKIPPED — "*)           echo "clean" ;;
        *": STOPPED_AT_"*" — "*)    echo "clean" ;;
        *": ERROR — "*)             echo "clean" ;;
        *)                          echo "parse-failed" ;;
    esac
}

cases=(
  "alpha--WD-01: COMPLETE — refactor clean|clean"
  "alpha--WD-02: ESCALATION_AT_feature-plan — design-choice: codec interface?|escalation"
  "alpha--WD-03: STOPPED_AT_feature-test — fixture missing|clean"
  "alpha--WD-04: ERROR — feature dir already exists|clean"
  "alpha--WD-05: SKIPPED — claim conflict|clean"
  "garbage payload|parse-failed"
)

for tc in "${cases[@]}"; do
    line="${tc%|*}"
    expect="${tc##*|}"
    got=$(classify "$line")
    if [[ "$got" == "$expect" ]]; then
        pass "classify: $expect ← \"${line:0:50}...\""
    else
        fail "classify: expected $expect got $got" "for line: $line"
    fi
done

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "Total: $total | Passed: $passed | Failed: $failed"
echo ""

[[ $failed -eq 0 ]] && exit 0 || exit 1
