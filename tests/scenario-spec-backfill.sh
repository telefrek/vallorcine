#!/usr/bin/env bash
# Scenario: /spec-backfill primitives — candidate finder + append-only log
#
# Tests:
# - spec-backfill-candidates.sh ranks code locations by token overlap
# - candidate finder filters below min-score
# - candidate finder respects --top
# - spec-backfill-log.sh init + append + has-decision + list-decisions + report
# - has-decision distinguishes terminal (annotated/waived) from skipped
# - log is append-only and idempotent on identical rows
# - report counts each status correctly
#
# Run from repo root: bash tests/scenario-spec-backfill.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-spec-backfill"
CAND="$REPO_ROOT/scripts/spec-backfill-candidates.sh"
LOG="$REPO_ROOT/scripts/spec-backfill-log.sh"

passed=0; failed=0; total=0
pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }
cleanup() { rm -rf "$TEST_BASE" 2>/dev/null || true; }
trap cleanup EXIT

echo ""
echo "scenario: spec-backfill primitives"
echo "────────────────────────────────────────────────"

cleanup
mkdir -p "$TEST_BASE/project/.git"
mkdir -p "$TEST_BASE/project/.spec/registry"
mkdir -p "$TEST_BASE/project/.spec/domains/auth"
mkdir -p "$TEST_BASE/project/src/auth"
mkdir -p "$TEST_BASE/project/test/auth"

# ── Spec fixture ────────────────────────────────────────────────────────────
cat > "$TEST_BASE/project/.spec/domains/auth/F01-token-validation.md" << 'EOF'
---
{
  "id": "F01",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["auth"]
}
---

# F01 — Token Validation

## Requirements

R1. The TokenValidator must reject expired tokens by checking the expiry claim.
R2. The system must support multi-tenant claims with TenantContext propagation.
R3. The TokenValidator must handle malformed tokens by raising a parse error.

## Design Narrative
Notes.
EOF

cat > "$TEST_BASE/project/.spec/registry/manifest.json" << 'EOF'
{
  "schema_version": 2,
  "specs": [
    { "id": "F01", "path": ".spec/domains/auth/F01-token-validation.md", "state": "APPROVED", "domains": ["auth"] }
  ]
}
EOF

# ── Code fixture: realistic enforcement points ──────────────────────────────

cat > "$TEST_BASE/project/src/auth/TokenValidator.java" << 'EOF'
package com.example.auth;

public class TokenValidator {

    public boolean validateExpiry(Claims claims) {
        if (claims.getExpiry().isBefore(now())) {
            return false;
        }
        return true;
    }

    public TenantContext extractTenant(Claims claims) {
        return new TenantContext(claims.getTenantId());
    }

    public Claims parseToken(String raw) throws ParseException {
        // parsing logic
        return Claims.parse(raw);
    }
}
EOF

cat > "$TEST_BASE/project/test/auth/TokenValidatorTest.java" << 'EOF'
package com.example.auth;

@Test
void expiredTokensRejected() {
    TokenValidator v = new TokenValidator();
    assertFalse(v.validateExpiry(expiredClaims));
}
EOF

# Decoy: file mentioning Token but not the requirement subjects.
cat > "$TEST_BASE/project/src/auth/TokenLogger.java" << 'EOF'
package com.example.auth;
public class TokenLogger {
    public void log(String message) {
        System.out.println(message);
    }
}
EOF

# ── Test 1: candidate finder produces candidates with overlap scores ────────

echo ""
echo "── Test 1: candidate finder produces candidates ranked by score"

output=$(cd "$TEST_BASE/project" && bash "$CAND" F01 R1 2>/dev/null)
# Top candidate should reference TokenValidator (impl or test file are both
# valid annotation targets per spec-annotation-protocol). Score column must
# be present and numeric.
if [[ -n "$output" ]] && echo "$output" | head -1 | grep -qE '^[0-9]+\s+(src|test)/auth/TokenValidator(Test)?\.java:[0-9]+'; then
    pass "top candidate for R1 references TokenValidator (impl or test)"
else
    fail "expected TokenValidator file in top candidate" "got: $output"
fi

# ── Test 2: top candidate has higher score than tail ────────────────────────

echo ""
echo "── Test 2: candidates are sorted by score descending"

output=$(cd "$TEST_BASE/project" && bash "$CAND" F01 R1 --top 10 2>/dev/null)
first_score=$(echo "$output" | head -1 | cut -f1)
last_score=$(echo "$output" | tail -1 | cut -f1)
if [[ -n "$first_score" && -n "$last_score" && "$first_score" -ge "$last_score" ]]; then
    pass "candidate scores are non-increasing (top=$first_score, last=$last_score)"
else
    fail "expected non-increasing scores" "first=$first_score last=$last_score; got: $output"
fi

# ── Test 3: --top N caps the output length ──────────────────────────────────

echo ""
echo "── Test 3: --top caps the output length"

output_top1=$(cd "$TEST_BASE/project" && bash "$CAND" F01 R1 --top 1 2>/dev/null)
line_count=$(echo "$output_top1" | wc -l | tr -d ' ')
if [[ "$line_count" -eq 1 ]]; then
    pass "--top 1 emits exactly one row"
else
    fail "--top 1 should emit one row" "got $line_count rows: $output_top1"
fi

# ── Test 4: --min-score filters low-overlap noise ───────────────────────────

echo ""
echo "── Test 4: --min-score filters low-overlap candidates"

# TokenLogger has only "Token" overlap (1 token, below default min-score=2)
output=$(cd "$TEST_BASE/project" && bash "$CAND" F01 R1 --top 99 2>/dev/null)
if ! echo "$output" | grep -q "TokenLogger"; then
    pass "TokenLogger filtered out below min-score=2"
else
    fail "TokenLogger should be below min-score" "got: $output"
fi

# Lower the bar — at min-score=1, decoys may surface (informational; not asserted).

# ── Test 5: candidate finder resolves domain.slug ID via fallback ───────────

echo ""
echo "── Test 5: candidate finder resolves domain.slug ID"

# Add a domain.slug-styled spec at the path-derived location
mkdir -p "$TEST_BASE/project/.spec/domains/billing"
cat > "$TEST_BASE/project/.spec/domains/billing/charge.md" << 'EOF'
---
{
  "id": "billing.charge",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["billing"]
}
---

# billing.charge

## Requirements

R1. The ChargeProcessor must finalize charges via the SettlementGateway.
EOF

# Update manifest to include billing.charge
cat > "$TEST_BASE/project/.spec/registry/manifest.json" << 'EOF'
{
  "schema_version": 2,
  "specs": [
    { "id": "F01", "path": ".spec/domains/auth/F01-token-validation.md", "state": "APPROVED", "domains": ["auth"] },
    { "id": "billing.charge", "path": ".spec/domains/billing/charge.md", "state": "APPROVED", "domains": ["billing"] }
  ]
}
EOF

mkdir -p "$TEST_BASE/project/src/billing"
cat > "$TEST_BASE/project/src/billing/ChargeProcessor.java" << 'EOF'
package com.example.billing;
public class ChargeProcessor {
    private SettlementGateway gateway;
    public void finalize(Charge c) {
        gateway.settle(c);
    }
}
EOF

output=$(cd "$TEST_BASE/project" && bash "$CAND" billing.charge R1 2>/dev/null)
if echo "$output" | grep -q "src/billing/ChargeProcessor.java"; then
    pass "candidate finder resolves domain.slug spec ID"
else
    fail "should find ChargeProcessor.java for billing.charge.R1" "got: $output"
fi

# ── Test 6: missing requirement → error ─────────────────────────────────────

echo ""
echo "── Test 6: candidate finder errors clearly on missing R-id"

output=$(cd "$TEST_BASE/project" && bash "$CAND" F01 R99 2>&1 || true)
if echo "$output" | grep -q "Requirement 'R99' not found"; then
    pass "missing R-id produces clear error"
else
    fail "should error on missing R-id" "got: $output"
fi

# ── Test 7: log init creates header table ───────────────────────────────────

echo ""
echo "── Test 7: log init creates a header table"

bash "$LOG" init "$TEST_BASE/log.md" >/dev/null 2>&1
if grep -q "^| Date | Spec | R-id | Status |" "$TEST_BASE/log.md"; then
    pass "log init writes header table"
else
    fail "log init should write header" "got: $(cat "$TEST_BASE/log.md")"
fi

# ── Test 8: log init is idempotent ──────────────────────────────────────────

echo ""
echo "── Test 8: log init is idempotent"

cp "$TEST_BASE/log.md" "$TEST_BASE/log.md.bak"
bash "$LOG" init "$TEST_BASE/log.md" >/dev/null 2>&1
if cmp -s "$TEST_BASE/log.md" "$TEST_BASE/log.md.bak"; then
    pass "log init does not overwrite existing log"
else
    fail "log init clobbered existing content"
fi

# ── Test 9: append annotated row ────────────────────────────────────────────

echo ""
echo "── Test 9: append annotated row records location"

bash "$LOG" append "$TEST_BASE/log.md" 2026-05-06 F01 R1 annotated "src/auth/TokenValidator.java:5" >/dev/null 2>&1
if grep -qE '^\| 2026-05-06 \| F01 \| R1 \| annotated \| src/auth/TokenValidator\.java:5 \|' "$TEST_BASE/log.md"; then
    pass "append wrote annotated row with location"
else
    fail "annotated row not written" "got: $(grep R1 "$TEST_BASE/log.md")"
fi

# ── Test 10: has-decision returns 0 for annotated ───────────────────────────

echo ""
echo "── Test 10: has-decision distinguishes terminal vs non-terminal"

# `set -e` in the harness would short-circuit on the rc=1 paths below;
# pause errexit while we capture exit codes, then restore.
set +e
bash "$LOG" has-decision "$TEST_BASE/log.md" F01 R1
ann_rc=$?
bash "$LOG" append "$TEST_BASE/log.md" 2026-05-06 F01 R2 skipped "" >/dev/null 2>&1
bash "$LOG" has-decision "$TEST_BASE/log.md" F01 R2
skp_rc=$?
bash "$LOG" has-decision "$TEST_BASE/log.md" F01 R99
unknown_rc=$?
set -e
if [[ "$ann_rc" -eq 0 && "$skp_rc" -eq 1 && "$unknown_rc" -eq 1 ]]; then
    pass "has-decision: annotated=0, skipped=1, unknown=1"
else
    fail "has-decision exit codes wrong" "ann=$ann_rc skp=$skp_rc unk=$unknown_rc"
fi

# ── Test 11: append is idempotent on identical rows ─────────────────────────

echo ""
echo "── Test 11: append is idempotent on identical rows"

before=$(wc -l < "$TEST_BASE/log.md")
bash "$LOG" append "$TEST_BASE/log.md" 2026-05-06 F01 R1 annotated "src/auth/TokenValidator.java:5" >/dev/null 2>&1
after=$(wc -l < "$TEST_BASE/log.md")
if [[ "$before" -eq "$after" ]]; then
    pass "duplicate append does not add a new row"
else
    fail "duplicate append wrote a new row" "before=$before after=$after"
fi

# ── Test 12: later row supersedes earlier (most-recent wins) ────────────────

echo ""
echo "── Test 12: later row supersedes earlier (most-recent wins)"

# R2 was skipped above. Annotate it later — has-decision should now return 0.
bash "$LOG" append "$TEST_BASE/log.md" 2026-05-07 F01 R2 annotated "src/auth/TokenValidator.java:11" >/dev/null 2>&1
set +e
bash "$LOG" has-decision "$TEST_BASE/log.md" F01 R2
later_rc=$?
set -e
if [[ "$later_rc" -eq 0 ]]; then
    pass "later annotated row supersedes earlier skipped"
else
    fail "later row should supersede" "rc=$later_rc"
fi

# ── Test 13: list-decisions emits per-R-id rows for the spec ────────────────

echo ""
echo "── Test 13: list-decisions emits one row per R-id for the spec"

bash "$LOG" append "$TEST_BASE/log.md" 2026-05-06 F01 R3 waived "" "aspirational" >/dev/null 2>&1
output=$(bash "$LOG" list-decisions "$TEST_BASE/log.md" F01 2>/dev/null)
expected=$'R1|annotated|src/auth/TokenValidator.java:5|2026-05-06\nR2|annotated|src/auth/TokenValidator.java:11|2026-05-07\nR3|waived||2026-05-06'
if [[ "$output" == "$expected" ]]; then
    pass "list-decisions emits R1/R2/R3 with latest status each"
else
    fail "list-decisions output mismatch" "got: $output"
fi

# ── Test 14: report counts each status ──────────────────────────────────────

echo ""
echo "── Test 14: report counts each status correctly"

# Log has: R1 annotated, R2 skipped+annotated, R3 waived → 4 rows total
output=$(bash "$LOG" report "$TEST_BASE/log.md" 2>/dev/null)
if echo "$output" | grep -qE 'rows: 4 +annotated: 2 +skipped: 1 +waived: 1'; then
    pass "report counts rows=4 / annotated=2 / skipped=1 / waived=1"
else
    fail "report counts mismatch" "got: $output"
fi

# ── Test 15: invalid status rejected ────────────────────────────────────────

echo ""
echo "── Test 15: append rejects invalid status"

output=$(bash "$LOG" append "$TEST_BASE/log.md" 2026-05-06 F01 R4 broken "" 2>&1 || true)
if echo "$output" | grep -q "status must be one of"; then
    pass "invalid status produces clear error"
else
    fail "should reject invalid status" "got: $output"
fi

# ── Test 16: pipe-bearing notes are sanitized ───────────────────────────────

echo ""
echo "── Test 16: pipe characters in notes are sanitized"

bash "$LOG" append "$TEST_BASE/log.md" 2026-05-06 F01 R5 waived "" "complex|pipe|value" >/dev/null 2>&1
if grep -q "complex/pipe/value" "$TEST_BASE/log.md" && \
   ! grep -qE '\| F01 \| R5 \| waived \| \| complex\|' "$TEST_BASE/log.md"; then
    pass "pipes in notes replaced with slashes (preserves table integrity)"
else
    fail "pipes not sanitized" "got: $(grep R5 "$TEST_BASE/log.md")"
fi

# ── Test 17: --all corpus enumeration on v2 manifest ────────────────────────

echo ""
echo "── Test 17: --all corpus enumeration emits APPROVED spec IDs (v2)"

# v2 manifest already in place (with F01 + billing.charge from earlier tests).
# Add a DRAFT spec that should NOT be enumerated.
cat > "$TEST_BASE/project/.spec/domains/auth/F09-draft.md" << 'EOF'
---
{
  "id": "F09",
  "version": 1,
  "status": "ACTIVE",
  "state": "DRAFT",
  "domains": ["auth"]
}
---

# F09 — Draft only

## Requirements
R1. Draft.
EOF
cat > "$TEST_BASE/project/.spec/registry/manifest.json" << 'EOF'
{
  "schema_version": 2,
  "specs": [
    { "id": "F01", "path": ".spec/domains/auth/F01-token-validation.md", "state": "APPROVED", "domains": ["auth"] },
    { "id": "billing.charge", "path": ".spec/domains/billing/charge.md", "state": "APPROVED", "domains": ["billing"] },
    { "id": "F09", "path": ".spec/domains/auth/F09-draft.md", "state": "DRAFT", "domains": ["auth"] }
  ]
}
EOF

# Mirror the SKILL's enumeration — must work without bespoke tooling.
output=$(jq -r '
  if .specs then
    .specs[] | select(.state == "APPROVED") | .id
  else
    (.features // {}) | to_entries[] | select(.value.state == "APPROVED") | .key
  end
' "$TEST_BASE/project/.spec/registry/manifest.json" | sort)
expected=$'F01\nbilling.charge'
if [[ "$output" == "$expected" ]]; then
    pass "--all enumeration filters APPROVED only (v2 schema)"
else
    fail "should emit F01 and billing.charge, exclude F09 (DRAFT)" "got: '$output'"
fi

# ── Test 18: --all corpus enumeration on v1 manifest ────────────────────────

echo ""
echo "── Test 18: --all corpus enumeration handles v1 manifest schema"

cat > "$TEST_BASE/v1-manifest.json" << 'EOF'
{
  "domains": { "auth": {} },
  "features": {
    "F01": { "latest_file": "domains/auth/F01.md", "state": "APPROVED" },
    "F02": { "latest_file": "domains/auth/F02.md", "state": "DRAFT" },
    "F03": { "latest_file": "domains/auth/F03.md", "state": "APPROVED" }
  }
}
EOF

output=$(jq -r '
  if .specs then
    .specs[] | select(.state == "APPROVED") | .id
  else
    (.features // {}) | to_entries[] | select(.value.state == "APPROVED") | .key
  end
' "$TEST_BASE/v1-manifest.json" | sort)
expected=$'F01\nF03'
if [[ "$output" == "$expected" ]]; then
    pass "--all enumeration handles v1 manifest schema"
else
    fail "should emit F01 and F03 from v1 manifest" "got: '$output'"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────"
if [[ $failed -eq 0 ]]; then
    echo "ALL PASSED  ($passed/$total)"
else
    echo "FAILED  $failed/$total  ($passed passed)"
fi

exit $failed
