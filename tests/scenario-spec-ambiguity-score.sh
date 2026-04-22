#!/usr/bin/env bash
# Scenario: spec-ambiguity-score.sh computes ambiguity score for specs.
#
# Validates:
# - Clean spec scores 0.00 and PASSes
# - Mixed spec (1 unverified / 5 reqs) scores 0.20 and PASSes (boundary)
# - Noisy spec (3 unverified / 5 reqs) scores 0.60 and FAILs
# - Machine section is the scoring scope (narrative text doesn't count)
# - --json output format is parseable
# - --threshold flag overrides default
# - Empty spec (no requirements) returns deterministic score
# - Missing file exits with clear error
#
# Run from repo root: bash tests/scenario-spec-ambiguity-score.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-spec-ambiguity-score"
SCRIPT="$REPO_ROOT/scripts/spec-ambiguity-score.sh"

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
echo "scenario: spec-ambiguity-score"
echo "────────────────────────────────────────────────"

cleanup
mkdir -p "$TEST_BASE"

# ── Fixtures ────────────────────────────────────────────────────────────────

write_clean_spec() {
    cat > "$TEST_BASE/clean.md" << 'EOF'
---
{"id": "domain.clean", "state": "APPROVED", "domains": ["domain"]}
---
# domain.clean

R1. Service must accept well-formed requests.
R2. Service must reject malformed input with 400.
R3. Service must return 500 on internal failure.
R4. Service must log every request.
R5. Service must time out after 30 seconds.

---

## Design Narrative

### Intent
Clean spec with no markers — every requirement resolvable.
EOF
}

write_boundary_spec() {
    # 1 UNVERIFIED out of 5 reqs = 0.20 — on the boundary of the 0.20 threshold
    cat > "$TEST_BASE/boundary.md" << 'EOF'
---
{"id": "domain.boundary", "state": "DRAFT", "domains": ["domain"]}
---
# domain.boundary

R1. Service must accept well-formed requests.
R2. Service must reject malformed input. [UNVERIFIED: assumes 400 is the canonical reject code — source needed]
R3. Service must return 500 on internal failure.
R4. Service must log every request.
R5. Service must time out after 30 seconds.

---

## Design Narrative

### Intent
One unverified claim; other five requirements clean.
EOF
}

write_noisy_spec() {
    # 3 markers out of 5 reqs = 0.60 — comfortably above threshold
    cat > "$TEST_BASE/noisy.md" << 'EOF'
---
{"id": "domain.noisy", "state": "DRAFT", "domains": ["domain"]}
---
# domain.noisy

R1. Service must accept well-formed requests. [UNVERIFIED: assumes HTTP/1.1]
R2. Service must reject malformed input. [UNRESOLVED: which codes count as malformed?]
R3. Service must return 500 on internal failure.
R4. Service must log every request. [CONFLICT: R4 vs F02.R7 on log format]
R5. Service must time out after 30 seconds.

---

## Design Narrative

### Intent
Deliberately noisy for test coverage.
EOF
}

write_empty_spec() {
    cat > "$TEST_BASE/empty.md" << 'EOF'
---
{"id": "domain.empty", "state": "DRAFT", "domains": ["domain"]}
---
# domain.empty

No requirements yet — placeholder.

---

## Design Narrative

### Intent
Stub.
EOF
}

write_narrative_noise_spec() {
    # Narrative contains markers but machine section is clean — must not count
    cat > "$TEST_BASE/narrative-noise.md" << 'EOF'
---
{"id": "domain.narrative-noise", "state": "APPROVED", "domains": ["domain"]}
---
# domain.narrative-noise

R1. Service must accept well-formed requests.
R2. Service must reject malformed input with 400.
R3. Service must return 500 on internal failure.

---

## Design Narrative

### Intent
Prior notes contained [UNRESOLVED] claims and a [CONFLICT] with F02
that were addressed during adversarial review. Those markers should
not count — they are natural English prose in the narrative section.
EOF
}

# ── Test 1: Clean spec scores 0.00 and PASSes ───────────────────────────────

echo ""
echo "  Clean spec"
echo "  ──────────"

write_clean_spec
if output="$(bash "$SCRIPT" "$TEST_BASE/clean.md" 2>&1)"; then
    if echo "$output" | grep -qE "Score[[:space:]]+:[[:space:]]+0\.00"; then
        pass "clean spec scores 0.00"
    else
        fail "clean spec score" "got: $output"
    fi
    if echo "$output" | grep -q "Verdict          : PASS"; then
        pass "clean spec verdict PASS"
    else
        fail "clean spec verdict" "got: $output"
    fi
else
    fail "clean spec should exit 0" "got: $output"
fi

# ── Test 2: Boundary spec (0.20) PASSes at default threshold ────────────────

echo ""
echo "  Boundary spec (1/5 = 0.20)"
echo "  ──────────────────────────"

write_boundary_spec
if output="$(bash "$SCRIPT" "$TEST_BASE/boundary.md" 2>&1)"; then
    if echo "$output" | grep -qE "Score[[:space:]]+:[[:space:]]+0\.20"; then
        pass "boundary spec scores 0.20"
    else
        fail "boundary spec score" "got: $output"
    fi
    if echo "$output" | grep -q "Verdict          : PASS"; then
        pass "boundary spec passes at default 0.20 threshold"
    else
        fail "boundary verdict" "got: $output"
    fi
else
    fail "boundary spec should exit 0 at default threshold" "got: $output"
fi

# ── Test 3: Noisy spec FAILs ────────────────────────────────────────────────

echo ""
echo "  Noisy spec (3/5 = 0.60)"
echo "  ───────────────────────"

write_noisy_spec
if output="$(bash "$SCRIPT" "$TEST_BASE/noisy.md" 2>&1 || true)"; then
    :  # ran (exit 0 or 1 captured by || true)
fi

# Exit code check requires a separate invocation
if bash "$SCRIPT" "$TEST_BASE/noisy.md" >/dev/null 2>&1; then
    fail "noisy spec should exit non-zero"
else
    pass "noisy spec exits non-zero"
fi

if echo "$output" | grep -qE "Score[[:space:]]+:[[:space:]]+0\.60"; then
    pass "noisy spec scores 0.60"
else
    fail "noisy spec score" "got: $output"
fi

if echo "$output" | grep -q "Verdict          : FAIL"; then
    pass "noisy spec verdict FAIL"
else
    fail "noisy verdict" "got: $output"
fi

if echo "$output" | grep -q "Unverified       : 1" \
   && echo "$output" | grep -q "Unresolved       : 1" \
   && echo "$output" | grep -q "Conflict         : 1"; then
    pass "noisy spec counts all three marker types correctly"
else
    fail "marker breakdown" "got: $output"
fi

# ── Test 4: Narrative section doesn't contaminate score ─────────────────────

echo ""
echo "  Narrative noise is scored-out"
echo "  ─────────────────────────────"

write_narrative_noise_spec
if output="$(bash "$SCRIPT" "$TEST_BASE/narrative-noise.md" 2>&1)"; then
    if echo "$output" | grep -qE "Score[[:space:]]+:[[:space:]]+0\.00"; then
        pass "narrative markers ignored (score stays 0.00)"
    else
        fail "narrative contamination" "got: $output"
    fi
else
    fail "narrative-noise spec should pass" "got: $output"
fi

# ── Test 5: --threshold flag overrides default ─────────────────────────────

echo ""
echo "  Threshold override"
echo "  ──────────────────"

# Boundary spec (0.20) should FAIL with stricter threshold 0.10
if bash "$SCRIPT" --threshold 0.10 "$TEST_BASE/boundary.md" >/dev/null 2>&1; then
    fail "boundary spec should fail at threshold 0.10"
else
    pass "threshold 0.10 fails boundary spec"
fi

# Noisy spec (0.60) should PASS with lax threshold 0.75
if bash "$SCRIPT" --threshold 0.75 "$TEST_BASE/noisy.md" >/dev/null 2>&1; then
    pass "threshold 0.75 passes noisy spec"
else
    fail "threshold 0.75 should pass noisy spec"
fi

# ── Test 6: --json output is valid JSON ─────────────────────────────────────

echo ""
echo "  JSON output"
echo "  ───────────"

if command -v jq >/dev/null 2>&1; then
    json_output="$(bash "$SCRIPT" --json "$TEST_BASE/noisy.md" 2>/dev/null || true)"
    if echo "$json_output" | jq empty 2>/dev/null; then
        pass "--json produces valid JSON"
    else
        fail "JSON invalid" "got: $json_output"
    fi

    # jq drops trailing zeros ("0.60" -> "0.6") so numeric-compare, not string-compare.
    score=$(echo "$json_output" | jq -r .score)
    if awk -v s="$score" 'BEGIN { exit !(s + 0 == 0.60) }'; then
        pass "JSON score field matches text output"
    else
        fail "JSON score field" "got: $score"
    fi

    pass_field=$(echo "$json_output" | jq -r .pass)
    if [[ "$pass_field" == "false" ]]; then
        pass "JSON pass field reports false for noisy spec"
    else
        fail "JSON pass field" "got: $pass_field"
    fi
else
    echo "  SKIP  jq not available — JSON validation skipped"
fi

# ── Test 7: Empty spec (no requirements) deterministic ──────────────────────

echo ""
echo "  Empty spec"
echo "  ──────────"

write_empty_spec
if output="$(bash "$SCRIPT" "$TEST_BASE/empty.md" 2>&1)"; then
    # No requirements + no markers = score 0.00 + PASS. Avoids crash on
    # divide-by-zero.
    if echo "$output" | grep -qE "Score[[:space:]]+:[[:space:]]+0\.00"; then
        pass "empty spec scores 0.00 (no divide-by-zero)"
    else
        fail "empty spec score" "got: $output"
    fi
else
    fail "empty spec should pass (no reqs, no markers)" "got: $output"
fi

# ── Test 8: Missing file exits with clear error ─────────────────────────────

echo ""
echo "  Missing file"
echo "  ────────────"

if err="$(bash "$SCRIPT" "$TEST_BASE/does-not-exist.md" 2>&1)"; then
    fail "missing file should exit non-zero"
else
    if echo "$err" | grep -q "file not found"; then
        pass "missing file reports 'file not found'"
    else
        fail "missing file error text" "got: $err"
    fi
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
