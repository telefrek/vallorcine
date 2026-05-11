#!/usr/bin/env bash
# Scenario: /work-decompose + work-validate.sh HIGH fixes from 2026-05-11
# adversarial sweep.
#
# H1: orphan classifier scoped to Phase A's target WD slots via
#     phase_a_target_wds checkpoint field (no false positives on
#     "Add more" flows).
# H2/H3: post-write self-validation step after each checkpoint update
#        (atomicity + LLM-parsing fragility safety net).
# H4: "Defer all" no longer wedges Step 7 — work-validate.sh respects
#     phase_b_deferred: true in work.md frontmatter and skips the
#     cross-WD invariant.
#
# Run from repo root: bash tests/scenario-decompose-high-cluster.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SKILL="$REPO_ROOT/skills/work-decompose/SKILL.md"
VALIDATE="$REPO_ROOT/scripts/work-validate.sh"

passed=0; failed=0; total=0
pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }

echo ""
echo "scenario: /work-decompose HIGH cluster"
echo "────────────────────────────────────────────────"

# ── H1: phase_a_target_wds scoping ──────────────────────────────────────────

echo ""
echo "  H1 — orphan classifier scoped to phase_a_target_wds"
echo "  ───────────────────────────────────────────────"

orphan_section=$(awk '/Orphan-checkpoint signal/,/Use AskUserQuestion with options:/' "$SKILL")

if echo "$orphan_section" | grep -qE 'phase_a_target_wds'; then
    pass "SKILL references phase_a_target_wds checkpoint field"
else
    fail "SKILL missing phase_a_target_wds reference"
fi

if echo "$orphan_section" | grep -qE 'Add more'; then
    pass "SKILL acknowledges the 'Add more' flow"
else
    fail "SKILL doesn't mention 'Add more' flow"
fi

if echo "$orphan_section" | grep -qE 'absent.*legacy.*fall back|fall back to the global scan'; then
    pass "SKILL provides legacy fallback when field is absent"
else
    fail "SKILL missing legacy fallback"
fi

# ── H2/H3: post-write self-validation ──────────────────────────────────────

echo ""
echo "  H2/H3 — post-write self-validation after checkpoint update"
echo "  ────────────────────────────────────────────────────────"

self_check=$(awk '/Post-write self-validation/{p=1} p; /^---$/ && p {p=0}' "$SKILL")

if [[ -n "$self_check" ]]; then
    pass "SKILL has Post-write self-validation section"
else
    fail "SKILL missing self-validation section"
fi

# Three checks must be specified
if echo "$self_check" | grep -qE 'new row is present.*Phase B — Settled'; then
    pass "check 1: new row exists in Phase B — Settled"
else
    fail "check 1 missing"
fi

if echo "$self_check" | tr '\n' ' ' | tr -s ' ' | grep -qE 'Exactly ONE row.*seams table.*Settled: yes|exactly ONE'; then
    pass "check 2: exactly one row flipped in seams table"
else
    fail "check 2 missing"
fi

if echo "$self_check" | grep -qiE 'count.*equals.*settled|two sections must agree'; then
    pass "check 3: cross-section count agreement"
else
    fail "check 3 missing"
fi

if echo "$self_check" | tr '\n' ' ' | tr -s ' ' | grep -qE 'AskUserQuestion.*Retry'; then
    pass "self-validation failure routes via AskUserQuestion"
else
    fail "self-validation failure doesn't use AskUserQuestion"
fi

# Migration note acknowledges the JSON-checkpoint future direction
if echo "$self_check" | grep -qE 'JSON checkpoint|helper script.*settle'; then
    pass "Migration note documents the JSON-checkpoint future direction"
else
    fail "Migration note missing"
fi

# ── H4: work-validate.sh tolerates phase_b_deferred ────────────────────────

echo ""
echo "  H4 — work-validate.sh respects phase_b_deferred: true"
echo "  ───────────────────────────────────────────────────"

# Validator code path
val_section=$(awk '/check_decompose_invariant\(\)/,/Build the union of all produces/' "$VALIDATE")

if echo "$val_section" | grep -qF "phase_b_deferred"; then
    pass "validator code checks phase_b_deferred field"
else
    fail "validator doesn't check phase_b_deferred"
fi

if echo "$val_section" | grep -qE 'SKIP.*invariant|return 0'; then
    pass "validator skips invariant when flag is set"
else
    fail "validator doesn't short-circuit on deferred flag"
fi

# SKILL.md prescribes writing the flag when "Defer all" is chosen
defer_section=$(awk '/^If "Defer all"/,/^If "Adjust the seams"/' "$SKILL")

if echo "$defer_section" | grep -qE 'phase_b_deferred: true'; then
    pass "SKILL prescribes writing phase_b_deferred: true on Defer all"
else
    fail "SKILL doesn't prescribe writing the flag"
fi

if echo "$defer_section" | grep -qE 'BEFORE running Step 7'; then
    pass "SKILL orders write BEFORE validate runs"
else
    fail "SKILL ordering unclear"
fi

# ── H4 LIVE: validate a fixture with phase_b_deferred set ──────────────────

echo ""
echo "  H4 LIVE — validator actually skips when flag is set"
echo "  ──────────────────────────────────────────────────"

TEST_DIR="/tmp/vallorcine/scenario-decompose-defer"
rm -rf "$TEST_DIR" 2>/dev/null || true
mkdir -p "$TEST_DIR/.work/deferred-group" "$TEST_DIR/.claude/scripts" "$TEST_DIR/.spec/registry" "$TEST_DIR/.decisions"
cp "$VALIDATE" "$TEST_DIR/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-resolve.sh" "$TEST_DIR/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-lib.sh" "$TEST_DIR/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$TEST_DIR/.claude/scripts/" 2>/dev/null || true
echo '{"schema_version":2,"specs":[]}' > "$TEST_DIR/.spec/registry/manifest.json"

# work.md with phase_b_deferred: true
cat > "$TEST_DIR/.work/deferred-group/work.md" <<'EOF'
---
group: deferred-group
goal: Test deferral
status: DRAFT
phase_b_deferred: true
---

## Tentative WDs

| WD | Title |
|----|-------|
| WD-01 | Test |
EOF

# A WD with an artifact_dep that wouldn't resolve (the kind of thing
# the invariant would normally fail on).
cat > "$TEST_DIR/.work/deferred-group/WD-01.md" <<'EOF'
---
id: WD-01
title: Test WD
group: deferred-group
status: DRAFT
domains: [test]
artifact_deps:
  - { type: spec, ref: "nonexistent/contract", required_state: APPROVED }
produces: []
---

## Summary
Test.

## Acceptance Criteria
Test.
EOF

# Run validate --decompose. Without the H4 fix, this would FAIL on the
# unsettled cross-WD reference. With the fix, it SKIPs that check
# because phase_b_deferred is true.
cd "$TEST_DIR"
out=$(bash .claude/scripts/work-validate.sh --group deferred-group --decompose 2>&1 || true)
cd "$REPO_ROOT"

if echo "$out" | grep -qE "SKIP.*decompose invariant.*phase_b_deferred"; then
    pass "validator SKIPs invariant with explicit message on deferred group"
else
    fail "validator didn't skip on deferred flag" "got: $out"
fi

# It MUST NOT print FAIL for the cross-WD reference (the bug we're fixing).
if echo "$out" | grep -qE "unsettled cross-WD reference"; then
    fail "validator still fails on unsettled refs despite deferred flag"
else
    pass "no 'unsettled cross-WD reference' error when deferred"
fi

rm -rf "$TEST_DIR" 2>/dev/null || true

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "Total: $total | Passed: $passed | Failed: $failed"
echo ""

[[ $failed -eq 0 ]] && exit 0 || exit 1
