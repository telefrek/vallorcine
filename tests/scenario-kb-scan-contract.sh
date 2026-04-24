#!/usr/bin/env bash
# Scenario: KB tendency-scan contract must be present at every pipeline
# surface where a subagent consumes KB context.
#
# Empirical gap (2026-04-24): across a 4-WU jlsm parallel run, 0 of 4
# WU-TDD subagents called kb-search.sh. The /feature-implement Step 8
# instruction existed in the skill file, but the coordinator-composed
# dispatch prompt never surfaced it to the subagent. Separately, audit
# Suspect agents received KB context in their cluster packets but used
# it at most 2/95 times in findings because the per-construct protocol
# didn't iterate KB as attack patterns. Prove-fix never mentioned KB at
# all.
#
# Six structural invariants defend against regression:
#
# 1. /feature-coordinate Step 1a embeds a "KB tendency-scan contract"
#    fragment that subagent dispatch prompts must include, referencing
#    kb-search.sh and the tendency-scan-complete substage.
# 2. /feature-implement Step 8 requires a tendency-scan-complete
#    substage write AND a cycle-log append after every construct's scan
#    (including zero-result scans).
# 3. /feature-coordinate's coordinator-side verification checks for
#    tendency-scan cycle-log entries on COMPLETE units.
# 4. prompts/audit/suspect.md has a KB attack-pattern sweep step that
#    iterates packet KB entries as attack vectors, and its finding
#    schema includes a kb_refs field.
# 5. prompts/audit/prove-fix.md has a KB fix-pattern lookup step (Phase
#    1a1) and its output schema records consulted KB refs.
# 6. prompts/audit/prove-fix-orchestrator.md passes kb_refs from each
#    Suspect finding through to the prove-fix dispatch.
#
# This is a grep-based structural test — it validates the prose is
# present, not that the runtime subagent actually runs it. Pairs with
# the existing scenario-parallel-subagent-hang-prevention.sh which
# defends the termination-contract pattern this test mirrors.
#
# Run from repo root: bash tests/scenario-kb-scan-contract.sh

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
echo "scenario: KB tendency-scan contract"
echo "────────────────────────────────────────────────"

# ── Invariant 1: /feature-coordinate carries the KB scan contract ────────────

echo ""
echo "── Invariant 1: /feature-coordinate dispatch contract includes KB scan"

coord_skill="$REPO_ROOT/skills/feature-coordinate/SKILL.md"

if [[ ! -f "$coord_skill" ]]; then
    fail "/feature-coordinate skill file missing" "$coord_skill"
else
    if grep -q "KB tendency-scan contract" "$coord_skill"; then
        pass "coordinator has 'KB tendency-scan contract' section"
    else
        fail "coordinator missing 'KB tendency-scan contract' section" \
             "dispatch template must surface Step 8 to subagents"
    fi

    if grep -q "kb-search.sh" "$coord_skill"; then
        pass "coordinator dispatch references kb-search.sh verbatim"
    else
        fail "coordinator dispatch does not reference kb-search.sh" \
             "subagent prompt must include the command invocation"
    fi

    if grep -q "tendency-scan-complete" "$coord_skill"; then
        pass "coordinator references tendency-scan-complete substage"
    else
        fail "coordinator missing tendency-scan-complete substage reference" \
             "dispatch must instruct subagent to write the checkpoint"
    fi
fi

# ── Invariant 2: /feature-implement Step 8 writes substage + cycle-log ──────

echo ""
echo "── Invariant 2: /feature-implement Step 8 checkpoint writes"

impl_skill="$REPO_ROOT/skills/feature-implement/SKILL.md"

if [[ ! -f "$impl_skill" ]]; then
    fail "/feature-implement skill file missing" "$impl_skill"
else
    # Extract Step 8 region (from "Tendency scan" header to next top-level step
    # or Escalation protocol)
    step8=$(awk '/\*\*Tendency scan/,/^## Escalation protocol|^If a test fails unexpectedly/' "$impl_skill")

    if echo "$step8" | grep -q "MANDATORY"; then
        pass "Step 8 is labelled MANDATORY"
    else
        fail "Step 8 not labelled MANDATORY" \
             "optional phrasing lets subagents skip the scan"
    fi

    if echo "$step8" | grep -q "tendency-scan-complete"; then
        pass "Step 8 requires tendency-scan-complete substage write"
    else
        fail "Step 8 missing tendency-scan-complete substage write" \
             "absence of checkpoint is how skipped scans stay invisible"
    fi

    if echo "$step8" | grep -q "cycle-log.md"; then
        pass "Step 8 requires cycle-log.md append after scan"
    else
        fail "Step 8 missing cycle-log.md append" \
             "needed for coordinator-side verification in Invariant 3"
    fi

    if echo "$step8" | grep -qi "zero-result\|0 / 0 / 0\|even if.*empty\|even if.*produces zero"; then
        pass "Step 8 enforces checkpoint even on zero-result scans"
    else
        fail "Step 8 does not require checkpoint on zero-result scans" \
             "absence-is-signal requires the scan always write a checkpoint"
    fi
fi

# ── Invariant 3: coordinator verifies tendency-scan cycle-log entries ───────

echo ""
echo "── Invariant 3: coordinator checks tendency-scan evidence post-return"

if [[ -f "$coord_skill" ]]; then
    verify_block=$(awk '/### Coordinator-side verification/,/^## /' "$coord_skill")
    if echo "$verify_block" | grep -q "tendency-scan"; then
        pass "coordinator verification block greps for tendency-scan entries"
    else
        fail "coordinator verification does not check tendency-scan entries" \
             "skipped scans will not be surfaced without this check"
    fi
fi

# ── Invariant 4: suspect.md KB attack-pattern sweep + kb_refs field ─────────

echo ""
echo "── Invariant 4: suspect.md KB attack-pattern sweep"

suspect_prompt="$REPO_ROOT/prompts/audit/suspect.md"

if [[ ! -f "$suspect_prompt" ]]; then
    fail "suspect.md missing" "$suspect_prompt"
else
    if grep -q "KB attack-pattern sweep" "$suspect_prompt"; then
        pass "suspect.md has 'KB attack-pattern sweep' step"
    else
        fail "suspect.md missing KB attack-pattern sweep" \
             "per-construct protocol must iterate packet KB as attack vectors"
    fi

    if grep -q "MANDATORY when packet lists KB entries" "$suspect_prompt"; then
        pass "KB sweep is marked MANDATORY when packet carries KB"
    else
        fail "KB sweep not explicitly mandatory" \
             "optional phrasing leaves KB as passive reference material"
    fi

    if grep -q -E "^\s*-\s+\*\*KB refs:\*\*" "$suspect_prompt"; then
        pass "suspect.md finding schema includes KB refs field"
    else
        fail "suspect.md finding schema missing KB refs field" \
             "KB-informed findings have nowhere to record provenance"
    fi

    if grep -q "KB-driven" "$suspect_prompt"; then
        pass "suspect.md summary line reports KB-driven count"
    else
        fail "suspect.md summary line missing KB-driven count" \
             "Report needs the KB-leverage signal to surface it in audit-report.md"
    fi
fi

# ── Invariant 5: prove-fix.md KB fix-pattern lookup ─────────────────────────

echo ""
echo "── Invariant 5: prove-fix.md KB fix-pattern lookup"

provefix_prompt="$REPO_ROOT/prompts/audit/prove-fix.md"

if [[ ! -f "$provefix_prompt" ]]; then
    fail "prove-fix.md missing" "$provefix_prompt"
else
    if grep -q "KB fix-pattern lookup" "$provefix_prompt"; then
        pass "prove-fix.md has KB fix-pattern lookup step"
    else
        fail "prove-fix.md missing KB fix-pattern lookup" \
             "fix construction cannot benefit from KB guidance otherwise"
    fi

    if grep -q "kb_refs" "$provefix_prompt"; then
        pass "prove-fix.md consumes kb_refs from the finding"
    else
        fail "prove-fix.md does not reference kb_refs" \
             "no channel to carry KB paths from Suspect through to fix construction"
    fi

    if grep -q "KB refs consulted" "$provefix_prompt"; then
        pass "prove-fix.md output records consulted KB refs"
    else
        fail "prove-fix.md output schema missing 'KB refs consulted'" \
             "Report cannot attribute fixes back to KB entries"
    fi

    # The hard-rules block used to forbid reading outside construct paths —
    # confirm the carve-out for kb_refs is present so prove-fix isn't
    # contradicting its own Phase 1a1 instruction.
    if grep -q "kb_refs.*allowed\|allowed.*kb_refs\|listed in .kb_refs\|listed in \`kb_refs\`" "$provefix_prompt"; then
        pass "prove-fix.md hard rules carve out kb_refs for reading"
    else
        fail "prove-fix.md hard rules still forbid all .kb/ reads" \
             "Phase 1a1 cannot fire without a carve-out in the Cannot-read rule"
    fi
fi

# ── Invariant 6: prove-fix-orchestrator passes kb_refs to each dispatch ─────

echo ""
echo "── Invariant 6: prove-fix-orchestrator forwards kb_refs"

orch_prompt="$REPO_ROOT/prompts/audit/prove-fix-orchestrator.md"

if [[ ! -f "$orch_prompt" ]]; then
    fail "prove-fix-orchestrator.md missing" "$orch_prompt"
else
    if grep -q "kb_refs" "$orch_prompt"; then
        pass "orchestrator dispatch template includes kb_refs line"
    else
        fail "orchestrator does not forward kb_refs" \
             "each prove-fix agent will see kb_refs unset regardless of Suspect output"
    fi
fi

# ── Invariant 7: Phase 0 upstream-mitigation short-circuit ──────────────────
#
# 16 of 36 IMPOSSIBLE returns on jlsm were "already-fixed-proxy" — findings
# whose attack path was blocked by an upstream fix from an earlier prove-fix
# in the same run, but the agent went through full Phase 1 anyway because
# Phase 0 only checked the local construct. Phase 0c must check prior
# prove-fix outputs for upstream mitigation before falling through.

echo ""
echo "── Invariant 7: prove-fix Phase 0 upstream-mitigation short-circuit"

if [[ -f "$provefix_prompt" ]]; then
    if grep -q "UPSTREAM_MITIGATED" "$provefix_prompt"; then
        pass "prove-fix.md recognises UPSTREAM_MITIGATED Phase 0 result"
    else
        fail "prove-fix.md missing UPSTREAM_MITIGATED result code" \
             "Phase 0 short-circuit for upstream-fixed findings has no output shape"
    fi

    if grep -qE "0c\.|upstream mitigation|upstream.*prior prove-fix|prior prove-fix.*upstream" "$provefix_prompt"; then
        pass "prove-fix.md Phase 0 has upstream-mitigation check step"
    else
        fail "prove-fix.md Phase 0 does not describe the upstream-mitigation check" \
             "the 0c step must instruct scanning prior prove-fix-*.md outputs"
    fi

    if grep -qE "2-file cap|max 2|at most 2|2 prior outputs|2 prior prove-fix" "$provefix_prompt"; then
        pass "prove-fix.md Phase 0 caps prior-output reads to 2 files"
    else
        fail "prove-fix.md Phase 0 does not cap prior-output reads" \
             "uncapped prior-output scan risks bigger waste than it saves"
    fi

    # Hard rules must carve out prove-fix-*.md reads for Phase 0
    if grep -qE "prove-fix-\*\.md|sibling .prove-fix|prove-fix.*sibling" "$provefix_prompt"; then
        pass "prove-fix.md hard rules carve out prove-fix-*.md reads"
    else
        fail "prove-fix.md hard rules still forbid sibling prove-fix output reads" \
             "Phase 0c cannot fire without a carve-out in the Cannot-read rule"
    fi

    # Output schema should allow recording consulted prior outputs
    if grep -q "Prior prove-fix consulted" "$provefix_prompt"; then
        pass "prove-fix.md output schema records consulted prior outputs"
    else
        fail "prove-fix.md output schema missing 'Prior prove-fix consulted'" \
             "Report cannot attribute upstream-mitigation short-circuits otherwise"
    fi
fi

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
