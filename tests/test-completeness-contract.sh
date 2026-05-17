#!/usr/bin/env bash
# Test: every dispatching skill has the completeness-contract preamble
#
# Validates that every skill that dispatches subagents includes the
# load-bearing preamble citing rules/completeness-contract.md. This is
# the grep-detectable enforcement test from the subagent rigor PR.
#
# Run from repo root: bash tests/test-completeness-contract.sh

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
echo "── Test: completeness-contract preamble across dispatching skills ──"
echo ""

# Skills that dispatch subagents — they MUST include the preamble.
# work-resume is intentionally excluded: it diagnoses stuck dispatches
# from other skills but never dispatches subagents itself.
DISPATCHING_SKILLS=(
    "skills/architect/SKILL.md"
    "skills/audit/SKILL.md"
    "skills/curate/SKILL.md"
    "skills/feature-coordinate/SKILL.md"
    "skills/feature-plan/SKILL.md"
    "skills/spec-author/SKILL.md"
    "skills/spec-backfill/SKILL.md"
    "skills/work-plan/SKILL.md"
    "skills/work-run/SKILL.md"
    "skills/work-start/SKILL.md"
)

# ── Test 1: every dispatching skill mentions completeness-contract.md ──
for skill in "${DISPATCHING_SKILLS[@]}"; do
    skill_path="$REPO_ROOT/$skill"
    if [[ ! -f "$skill_path" ]]; then
        fail "$skill exists" "file not found"
        continue
    fi
    if grep -q "rules/completeness-contract.md" "$skill_path"; then
        pass "$skill references rules/completeness-contract.md"
    else
        fail "$skill references rules/completeness-contract.md" "missing"
    fi
done

# ── Test 2: every dispatching skill uses the "load-bearing" marker ─────
# This guards against the rule being mentioned in passing without the
# load-bearing preamble. The phrase "load-bearing" must appear near
# the contract citation.
for skill in "${DISPATCHING_SKILLS[@]}"; do
    skill_path="$REPO_ROOT/$skill"
    [[ ! -f "$skill_path" ]] && continue
    if grep -q "load-bearing" "$skill_path"; then
        pass "$skill marks the contract as load-bearing"
    else
        fail "$skill marks the contract as load-bearing" "missing 'load-bearing'"
    fi
done

# ── Test 3: the rule file itself exists ───────────────────────────────
rule_path="$REPO_ROOT/rules/completeness-contract.md"
if [[ -f "$rule_path" ]]; then
    pass "rules/completeness-contract.md exists"
else
    fail "rules/completeness-contract.md exists" "file not found"
fi

# ── Test 4: rule file contains the six contracts ──────────────────────
if [[ -f "$rule_path" ]]; then
    for contract in "Verification contract" "Production-path contract" "Measurement contract" "Annotation contract" "Quality-bar contract" "Scope-reconciliation contract"; do
        if grep -q "$contract" "$rule_path"; then
            pass "rule file contains '$contract'"
        else
            fail "rule file contains '$contract'" "missing"
        fi
    done
fi

# ── Test 5: rule listed in MANIFEST ───────────────────────────────────
manifest="$REPO_ROOT/MANIFEST"
if grep -q "rules/completeness-contract.md" "$manifest"; then
    pass "MANIFEST includes rules/completeness-contract.md"
else
    fail "MANIFEST includes rules/completeness-contract.md" "missing entry"
fi

# ── Test 6: validator script in MANIFEST + install.sh ─────────────────
if grep -q "scripts/validate-subagent-return.sh" "$manifest"; then
    pass "MANIFEST includes validate-subagent-return.sh"
else
    fail "MANIFEST includes validate-subagent-return.sh" "missing entry"
fi

install_sh="$REPO_ROOT/install.sh"
if grep -q "validate-subagent-return.sh" "$install_sh"; then
    pass "install.sh installs validate-subagent-return.sh"
else
    fail "install.sh installs validate-subagent-return.sh" "missing"
fi

# ── Test 7: WD orchestrators pass --require-ac-coverage ──────────────
WD_ORCHESTRATORS=(
    "skills/work-run/SKILL.md"
    "skills/work-start/SKILL.md"
    "skills/work-plan/SKILL.md"
    "skills/feature-coordinate/SKILL.md"
)
for skill in "${WD_ORCHESTRATORS[@]}"; do
    skill_path="$REPO_ROOT/$skill"
    [[ ! -f "$skill_path" ]] && continue
    if grep -q "validate-subagent-return.sh.*--require-ac-coverage" "$skill_path"; then
        pass "$skill passes --require-ac-coverage to validator"
    else
        fail "$skill passes --require-ac-coverage to validator" "flag not found"
    fi
done

# ── Test 8: non-WD orchestrators DO NOT pass --require-ac-coverage ───
NON_WD_ORCHESTRATORS=(
    "skills/audit/SKILL.md"
    "skills/spec-backfill/SKILL.md"
    "skills/curate/SKILL.md"
)
for skill in "${NON_WD_ORCHESTRATORS[@]}"; do
    skill_path="$REPO_ROOT/$skill"
    [[ ! -f "$skill_path" ]] && continue
    if grep -q "validate-subagent-return.sh" "$skill_path"; then
        # Has validator call — make sure it does NOT pass --require-ac-coverage
        if grep -q "validate-subagent-return.sh.*--require-ac-coverage" "$skill_path"; then
            fail "$skill omits --require-ac-coverage" "flag found but shouldn't be"
        else
            pass "$skill omits --require-ac-coverage (correct for non-WD dispatch)"
        fi
    fi
done

# ── Test 9: feature-pr quality-bar gate present ───────────────────────
pr_skill="$REPO_ROOT/skills/feature-pr/SKILL.md"
if [[ -f "$pr_skill" ]]; then
    if grep -q "Quality-bar gate" "$pr_skill"; then
        pass "feature-pr has Quality-bar gate section"
    else
        fail "feature-pr has Quality-bar gate section" "section not found"
    fi
    if grep -q ".flake-allowlist.md" "$pr_skill"; then
        pass "feature-pr references .flake-allowlist.md"
    else
        fail "feature-pr references .flake-allowlist.md" "not referenced"
    fi
fi

# ── Test 10: spec-verify enforcement check present ───────────────────
sv_skill="$REPO_ROOT/skills/spec-verify/SKILL.md"
if [[ -f "$sv_skill" ]]; then
    if grep -q "Enforcement check" "$sv_skill"; then
        pass "spec-verify has Enforcement check section"
    else
        fail "spec-verify has Enforcement check section" "section not found"
    fi
    if grep -q "RETIRE / REMOVE-style" "$sv_skill"; then
        pass "spec-verify has RETIRE/REMOVE enforcement guidance"
    else
        fail "spec-verify has RETIRE/REMOVE enforcement guidance" "not found"
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "── Test summary ──────────────────────────────────────────────"
echo "  Passed: $passed / $total"
if [[ $failed -gt 0 ]]; then
    echo "  Failed: $failed"
    exit 1
fi
echo ""
exit 0
