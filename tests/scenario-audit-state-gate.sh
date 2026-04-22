#!/usr/bin/env bash
# Scenario: audit-state-gate.sh refuses /audit on non-APPROVED specs.
#
# Regression for Item 6 of the post-v0.14.0 bug fix sweep. /audit used to
# run against DRAFT specs and produce misleading findings — without an
# authoritative contract, Lens A (SPEC-REQ) findings have nothing to
# prove against. The gate refuses the entry point before the pipeline
# starts.
#
# Run from repo root: bash tests/scenario-audit-state-gate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-audit-state-gate"

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
echo "scenario: audit-state-gate refuses non-APPROVED specs"
echo "────────────────────────────────────────────────"

cleanup
PROJECT="$TEST_BASE/project"
mkdir -p "$PROJECT/.claude/scripts"
mkdir -p "$PROJECT/.spec/domains/schema"
mkdir -p "$PROJECT/.spec/registry"

cp "$REPO_ROOT/scripts/audit-state-gate.sh" "$PROJECT/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$PROJECT/.claude/scripts/"
chmod +x "$PROJECT/.claude/scripts/audit-state-gate.sh"

# ── Fixtures: one APPROVED spec, one DRAFT spec, one INVALIDATED spec ────

cat > "$PROJECT/.spec/domains/schema/approved-contract.md" << 'EOF'
---
{
  "id": "schema.approved-contract",
  "version": 1,
  "state": "APPROVED",
  "status": "ACTIVE",
  "domains": ["schema"]
}
---

# schema.approved-contract

## Requirements
R1. Schemas must serialize deterministically.
EOF

cat > "$PROJECT/.spec/domains/schema/draft-contract.md" << 'EOF'
---
{
  "id": "schema.draft-contract",
  "version": 1,
  "state": "DRAFT",
  "status": "ACTIVE",
  "domains": ["schema"]
}
---

# schema.draft-contract

## Requirements
R1. TBD.
EOF

cat > "$PROJECT/.spec/domains/schema/retired-contract.md" << 'EOF'
---
{
  "id": "schema.retired-contract",
  "version": 1,
  "state": "INVALIDATED",
  "status": "DEPRECATED",
  "domains": ["schema"]
}
---

# schema.retired-contract

## Requirements
R1. Was here once.
EOF

cat > "$PROJECT/.spec/registry/manifest.json" << 'EOF'
{
  "schema_version": 2,
  "specs": [
    {"id": "schema.approved-contract", "path": ".spec/domains/schema/approved-contract.md", "state": "APPROVED"},
    {"id": "schema.draft-contract", "path": ".spec/domains/schema/draft-contract.md", "state": "DRAFT"},
    {"id": "schema.retired-contract", "path": ".spec/domains/schema/retired-contract.md", "state": "INVALIDATED"}
  ]
}
EOF

cd "$PROJECT"

# ── Test 1: APPROVED spec passes the gate ────────────────────────────────

echo ""
echo "── Test 1: APPROVED spec passes"

if output="$(bash .claude/scripts/audit-state-gate.sh schema.approved-contract 2>&1)"; then
    if echo "$output" | grep -q "OK: spec 'schema.approved-contract' is APPROVED"; then
        pass "APPROVED spec passes with OK message"
    else
        fail "APPROVED spec output missing OK" "got: $output"
    fi
else
    fail "APPROVED spec should exit 0" "got: $output"
fi

# ── Test 2: DRAFT spec fails the gate with clear guidance ────────────────

echo ""
echo "── Test 2: DRAFT spec fails with next-step guidance"

if output="$(bash .claude/scripts/audit-state-gate.sh schema.draft-contract 2>&1)"; then
    fail "DRAFT spec should exit non-zero" "got: $output"
else
    if echo "$output" | grep -q "is DRAFT" \
        && echo "$output" | grep -q "/spec-verify schema.draft-contract"; then
        pass "DRAFT spec rejected with /spec-verify guidance"
    else
        fail "DRAFT rejection missing state and/or next step" "got: $output"
    fi
fi

# ── Test 3: INVALIDATED spec fails the gate ─────────────────────────────

echo ""
echo "── Test 3: INVALIDATED spec fails"

if output="$(bash .claude/scripts/audit-state-gate.sh schema.retired-contract 2>&1)"; then
    fail "INVALIDATED spec should exit non-zero" "got: $output"
else
    if echo "$output" | grep -q "is INVALIDATED" \
        && echo "$output" | grep -q "replacement spec"; then
        pass "INVALIDATED spec rejected with replacement-spec guidance"
    else
        fail "INVALIDATED rejection missing state and/or next step" "got: $output"
    fi
fi

# ── Test 4: Unknown spec ID fails with registry message ─────────────────

echo ""
echo "── Test 4: Unknown spec ID fails"

if output="$(bash .claude/scripts/audit-state-gate.sh schema.phantom-spec 2>&1)"; then
    fail "unknown spec should exit non-zero" "got: $output"
else
    if echo "$output" | grep -q "not found in registry"; then
        pass "unknown spec rejected with registry message"
    else
        fail "unknown spec rejection missing 'not found in registry'" "got: $output"
    fi
fi

# ── Test 5: No manifest fails with guidance ─────────────────────────────

echo ""
echo "── Test 5: Missing manifest fails"

NO_MANIFEST_PROJECT="$TEST_BASE/no-manifest"
mkdir -p "$NO_MANIFEST_PROJECT/.claude/scripts"
cp "$REPO_ROOT/scripts/audit-state-gate.sh" "$NO_MANIFEST_PROJECT/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$NO_MANIFEST_PROJECT/.claude/scripts/"
chmod +x "$NO_MANIFEST_PROJECT/.claude/scripts/audit-state-gate.sh"
mkdir -p "$NO_MANIFEST_PROJECT/.spec"    # exists but no registry inside
cd "$NO_MANIFEST_PROJECT"

if output="$(bash .claude/scripts/audit-state-gate.sh schema.anything 2>&1)"; then
    fail "missing manifest should exit non-zero" "got: $output"
else
    if echo "$output" | grep -q "no .spec/registry/manifest.json"; then
        pass "missing manifest rejected with clear message"
    else
        fail "missing-manifest rejection unclear" "got: $output"
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
if [[ $failed -eq 0 ]]; then
    echo "ALL PASSED  ($passed/$total)"
else
    echo "FAILED  $failed/$total  ($passed passed)"
fi
echo ""

exit $failed
