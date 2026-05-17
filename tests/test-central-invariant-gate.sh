#!/usr/bin/env bash
# Test: /feature-pr Step 1c central-invariant gate is wired correctly
#
# Validates that the v0.22.0 central-invariant gate has the structural
# pieces in place: skill step, falsifier prompt, install plumbing, MANIFEST
# entry.
#
# Run from repo root: bash tests/test-central-invariant-gate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

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
echo "── Test: /feature-pr Step 1c central-invariant gate ─────────────"
echo ""

# ── Test 1: design doc exists ─────────────────────────────────────────
design_path="$REPO_ROOT/designs/central-invariant-gate.md"
if [[ -f "$design_path" ]]; then
    pass "designs/central-invariant-gate.md exists"
else
    fail "designs/central-invariant-gate.md exists" "file not found"
fi

# ── Test 2: falsifier prompt exists ───────────────────────────────────
prompt_path="$REPO_ROOT/prompts/feature-pr/central-invariant-falsify.md"
if [[ -f "$prompt_path" ]]; then
    pass "prompts/feature-pr/central-invariant-falsify.md exists"
else
    fail "prompts/feature-pr/central-invariant-falsify.md exists" "file not found"
fi

# ── Test 3: prompt opens with subagent contract preamble ──────────────
if [[ -f "$prompt_path" ]]; then
    if head -10 "$prompt_path" | grep -q "Subagent contract"; then
        pass "falsifier prompt opens with Subagent contract preamble"
    else
        fail "falsifier prompt opens with Subagent contract preamble" "preamble missing in top 10 lines"
    fi
    if grep -q "rules/completeness-contract.md" "$prompt_path"; then
        pass "falsifier prompt cites rules/completeness-contract.md"
    else
        fail "falsifier prompt cites rules/completeness-contract.md" "citation missing"
    fi
fi

# ── Test 4: prompt enumerates required output format ─────────────────
if [[ -f "$prompt_path" ]]; then
    for marker in "VERDICT:" "INVARIANT:" "EVIDENCE:"; do
        if grep -q "$marker" "$prompt_path"; then
            pass "falsifier prompt requires '$marker' output"
        else
            fail "falsifier prompt requires '$marker' output" "marker missing"
        fi
    done
fi

# ── Test 5: prompt covers all 5 falsifier patterns ───────────────────
if [[ -f "$prompt_path" ]]; then
    for pattern in "Vacuous equivalence" "Mocked-vs-live" "End-to-end vs unit" "Verbal argument" "Phantom annotation"; do
        if grep -q "$pattern" "$prompt_path"; then
            pass "falsifier prompt covers '$pattern' pattern"
        else
            fail "falsifier prompt covers '$pattern' pattern" "missing"
        fi
    done
fi

# ── Test 6: feature-pr SKILL.md has Step 1c section ──────────────────
skill_path="$REPO_ROOT/skills/feature-pr/SKILL.md"
if [[ -f "$skill_path" ]]; then
    if grep -q "Step 1c — Central-invariant gate" "$skill_path"; then
        pass "feature-pr SKILL.md has Step 1c section"
    else
        fail "feature-pr SKILL.md has Step 1c section" "section header missing"
    fi
fi

# ── Test 7: Step 1c references the falsifier prompt path ─────────────
if [[ -f "$skill_path" ]]; then
    if grep -q "prompts/feature-pr/central-invariant-falsify.md" "$skill_path"; then
        pass "Step 1c references the falsifier prompt path"
    else
        fail "Step 1c references the falsifier prompt path" "path not referenced"
    fi
fi

# ── Test 8: Step 1c branches on verdict (HOLDS, FAILS, UNCLEAR) ──────
if [[ -f "$skill_path" ]]; then
    for verdict in "HOLDS" "FAILS" "UNCLEAR"; do
        if grep -q "$verdict" "$skill_path"; then
            pass "Step 1c handles '$verdict' verdict"
        else
            fail "Step 1c handles '$verdict' verdict" "verdict not referenced"
        fi
    done
fi

# ── Test 9: Step 1c has skip detection ────────────────────────────────
if [[ -f "$skill_path" ]]; then
    if grep -q "central_invariant_gate: skip" "$skill_path"; then
        pass "Step 1c supports central_invariant_gate: skip"
    else
        fail "Step 1c supports central_invariant_gate: skip" "skip marker missing"
    fi
fi

# ── Test 10: Step 1c has empty-diff detection ────────────────────────
if [[ -f "$skill_path" ]]; then
    if grep -q "empty diff\|empty-diff\|git diff --quiet" "$skill_path"; then
        pass "Step 1c handles empty-diff case"
    else
        fail "Step 1c handles empty-diff case" "empty-diff handling missing"
    fi
fi

# ── Test 11: Step 1c validates the falsifier's own return ────────────
if [[ -f "$skill_path" ]]; then
    # The step should run validate-subagent-return.sh on the falsifier's return
    if grep -A 5 "Step 1c" "$skill_path" 2>/dev/null | head -200 > /tmp/step1c.txt && \
       grep -B 200 "## Step 2" "$skill_path" > /tmp/before-step2.txt && \
       grep -A 100 "Step 1c" /tmp/before-step2.txt | grep -q "validate-subagent-return.sh"; then
        pass "Step 1c validates the falsifier's own return"
    else
        fail "Step 1c validates the falsifier's own return" "validator call missing in Step 1c"
    fi
    rm -f /tmp/step1c.txt /tmp/before-step2.txt
fi

# ── Test 12: install.sh installs the falsifier prompt ────────────────
install_sh="$REPO_ROOT/install.sh"
if grep -q "prompts/feature-pr" "$install_sh"; then
    pass "install.sh installs prompts/feature-pr/"
else
    fail "install.sh installs prompts/feature-pr/" "not installed"
fi

# ── Test 13: MANIFEST includes the falsifier prompt ──────────────────
manifest="$REPO_ROOT/MANIFEST"
if grep -q "prompts/feature-pr/central-invariant-falsify.md" "$manifest"; then
    pass "MANIFEST includes central-invariant-falsify.md"
else
    fail "MANIFEST includes central-invariant-falsify.md" "missing entry"
fi

# ── Test 14: design doc enumerates rejected alternatives ─────────────
if [[ -f "$design_path" ]]; then
    if grep -q "Rejected alternatives" "$design_path"; then
        pass "design doc enumerates rejected alternatives"
    else
        fail "design doc enumerates rejected alternatives" "section missing"
    fi
fi

# ── Test 15: design doc enumerates open questions ────────────────────
if [[ -f "$design_path" ]]; then
    if grep -q "Open questions" "$design_path"; then
        pass "design doc enumerates open questions"
    else
        fail "design doc enumerates open questions" "section missing"
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "── Test summary ────────────────────────────────────────────────"
echo "  Passed: $passed / $total"
if [[ $failed -gt 0 ]]; then
    echo "  Failed: $failed"
    exit 1
fi
echo ""
exit 0
