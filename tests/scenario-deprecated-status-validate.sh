#!/usr/bin/env bash
# Scenario: spec-validate.sh enforces the DEPRECATED-status contract
#
# Validates that scripts/spec-validate.sh correctly:
# - Refuses status:DEPRECATED without displaced_by
# - Refuses status:DEPRECATED without displacement_reason
# - Refuses status:DEPRECATED without removal_scheduled_in
# - Refuses status:DEPRECATED with malformed removal_scheduled_in
# - Refuses status:DEPRECATED with removal_scheduled_in <= current VERSION
# - Refuses status:DEPRECATED without deprecation_date
# - Refuses status:DEPRECATED with malformed deprecation_date
# - Refuses status:DEPRECATED on a state:DRAFT spec
# - Refuses status:DEPRECATED when displaced_by target is state:DRAFT
# - Refuses status:DEPRECATED when displaced_by target is itself status:DEPRECATED
# - Accepts a properly-formed status:DEPRECATED spec
# - Allows status:DEPRECATED on state:INVALIDATED (terminal phase, no required fields)
#
# Run from repo root: bash tests/scenario-deprecated-status-validate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-deprecated-status-validate"
VALIDATOR="$REPO_ROOT/scripts/spec-validate.sh"

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
    rm -rf "$TEST_BASE"
}
trap cleanup EXIT
mkdir -p "$TEST_BASE"

echo ""
echo "── Scenario: status:DEPRECATED validator contract ──────────────"
echo ""

# Set up a minimal project skeleton
setup_project() {
    local pdir="$1"
    rm -rf "$pdir"
    mkdir -p "$pdir/.spec/domains/example" "$pdir/.spec/registry"
    echo "0.21.0" > "$pdir/VERSION"

    # The displacing spec (alternative — must be APPROVED + not DEPRECATED)
    cat > "$pdir/.spec/domains/example/successor.md" <<'EOF'
---
{
  "id": "example.successor",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["example"]
}
---

# example.successor — The replacement

## Requirements
R1. The successor MUST do the thing.

---

## Design Narrative
This is the replacement spec.
EOF

    # Build a minimal registry that resolves IDs to files
    cat > "$pdir/.spec/registry/manifest.json" <<EOF
{
  "version": 1,
  "specs": {
    "example.successor": {
      "id": "example.successor",
      "path": ".spec/domains/example/successor.md",
      "state": "APPROVED",
      "status": "ACTIVE"
    }
  }
}
EOF
}

# Write a spec under test inside the project
write_spec() {
    local pdir="$1"
    local frontmatter="$2"
    cat > "$pdir/.spec/domains/example/under_test.md" <<EOF
---
$frontmatter
---

# example.under-test — Title

## Requirements
R1. The thing must happen.

---

## Design Narrative
Body content.
EOF
}

run_validate() {
    local pdir="$1"
    local file="$pdir/.spec/domains/example/under_test.md"
    (cd "$pdir" && bash "$VALIDATOR" "$file" 2>&1)
}

PROJECT="$TEST_BASE/project"

# ── Test 1: missing displaced_by → fail ─────────────────────────────────
setup_project "$PROJECT"
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "DEPRECATED",
  "state": "APPROVED",
  "domains": ["example"],
  "displacement_reason": "superseded",
  "removal_scheduled_in": "0.22.0",
  "deprecation_date": "2026-05-17"
}'
out=$(run_validate "$PROJECT" || true)
if echo "$out" | grep -q "requires non-empty displaced_by"; then
    pass "missing displaced_by is flagged"
else
    fail "missing displaced_by is flagged" "$out"
fi

# ── Test 2: missing displacement_reason → fail ─────────────────────────
setup_project "$PROJECT"
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "DEPRECATED",
  "state": "APPROVED",
  "domains": ["example"],
  "displaced_by": ["example.successor"],
  "removal_scheduled_in": "0.22.0",
  "deprecation_date": "2026-05-17"
}'
out=$(run_validate "$PROJECT" || true)
if echo "$out" | grep -q "requires displacement_reason"; then
    pass "missing displacement_reason is flagged"
else
    fail "missing displacement_reason is flagged" "$out"
fi

# ── Test 3: missing removal_scheduled_in → fail ─────────────────────────
setup_project "$PROJECT"
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "DEPRECATED",
  "state": "APPROVED",
  "domains": ["example"],
  "displaced_by": ["example.successor"],
  "displacement_reason": "superseded",
  "deprecation_date": "2026-05-17"
}'
out=$(run_validate "$PROJECT" || true)
if echo "$out" | grep -q "requires removal_scheduled_in"; then
    pass "missing removal_scheduled_in is flagged"
else
    fail "missing removal_scheduled_in is flagged" "$out"
fi

# ── Test 4: malformed removal_scheduled_in → fail ───────────────────────
setup_project "$PROJECT"
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "DEPRECATED",
  "state": "APPROVED",
  "domains": ["example"],
  "displaced_by": ["example.successor"],
  "displacement_reason": "superseded",
  "removal_scheduled_in": "soon",
  "deprecation_date": "2026-05-17"
}'
out=$(run_validate "$PROJECT" || true)
if echo "$out" | grep -q "not a well-formed semver"; then
    pass "malformed removal_scheduled_in is flagged"
else
    fail "malformed removal_scheduled_in is flagged" "$out"
fi

# ── Test 5: removal_scheduled_in below current VERSION → fail ───────────
setup_project "$PROJECT"  # VERSION = 0.21.0
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "DEPRECATED",
  "state": "APPROVED",
  "domains": ["example"],
  "displaced_by": ["example.successor"],
  "displacement_reason": "superseded",
  "removal_scheduled_in": "0.10.0",
  "deprecation_date": "2026-05-17"
}'
out=$(run_validate "$PROJECT" || true)
if echo "$out" | grep -q "below current VERSION"; then
    pass "removal_scheduled_in below current VERSION is flagged"
else
    fail "removal_scheduled_in below current VERSION is flagged" "$out"
fi

# ── Test 6: removal_scheduled_in equals current VERSION → fail ──────────
setup_project "$PROJECT"  # VERSION = 0.21.0
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "DEPRECATED",
  "state": "APPROVED",
  "domains": ["example"],
  "displaced_by": ["example.successor"],
  "displacement_reason": "superseded",
  "removal_scheduled_in": "0.21.0",
  "deprecation_date": "2026-05-17"
}'
out=$(run_validate "$PROJECT" || true)
if echo "$out" | grep -q "equals current VERSION"; then
    pass "removal_scheduled_in equals current VERSION is flagged"
else
    fail "removal_scheduled_in equals current VERSION is flagged" "$out"
fi

# ── Test 7: missing deprecation_date → fail ─────────────────────────────
setup_project "$PROJECT"
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "DEPRECATED",
  "state": "APPROVED",
  "domains": ["example"],
  "displaced_by": ["example.successor"],
  "displacement_reason": "superseded",
  "removal_scheduled_in": "0.22.0"
}'
out=$(run_validate "$PROJECT" || true)
if echo "$out" | grep -q "requires deprecation_date"; then
    pass "missing deprecation_date is flagged"
else
    fail "missing deprecation_date is flagged" "$out"
fi

# ── Test 8: malformed deprecation_date → fail ───────────────────────────
setup_project "$PROJECT"
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "DEPRECATED",
  "state": "APPROVED",
  "domains": ["example"],
  "displaced_by": ["example.successor"],
  "displacement_reason": "superseded",
  "removal_scheduled_in": "0.22.0",
  "deprecation_date": "May 17 2026"
}'
out=$(run_validate "$PROJECT" || true)
if echo "$out" | grep -q "not a valid ISO date"; then
    pass "malformed deprecation_date is flagged"
else
    fail "malformed deprecation_date is flagged" "$out"
fi

# ── Test 9: status:DEPRECATED on state:DRAFT → fail ─────────────────────
setup_project "$PROJECT"
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "DEPRECATED",
  "state": "DRAFT",
  "domains": ["example"]
}'
out=$(run_validate "$PROJECT" || true)
if echo "$out" | grep -q "DEPRECATED on a state:DRAFT spec is not allowed"; then
    pass "status:DEPRECATED on state:DRAFT is refused"
else
    fail "status:DEPRECATED on state:DRAFT is refused" "$out"
fi

# ── Test 10: displaced_by target is state:DRAFT → fail ──────────────────
setup_project "$PROJECT"
# Mutate the successor to be DRAFT
sed -i.bak 's/"state": "APPROVED"/"state": "DRAFT"/' "$PROJECT/.spec/domains/example/successor.md"
sed -i.bak 's/"state": "APPROVED"/"state": "DRAFT"/' "$PROJECT/.spec/registry/manifest.json"
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "DEPRECATED",
  "state": "APPROVED",
  "domains": ["example"],
  "displaced_by": ["example.successor"],
  "displacement_reason": "superseded",
  "removal_scheduled_in": "0.22.0",
  "deprecation_date": "2026-05-17"
}'
out=$(run_validate "$PROJECT" || true)
if echo "$out" | grep -q "must be state:APPROVED to displace"; then
    pass "displaced_by target state:DRAFT is flagged"
else
    fail "displaced_by target state:DRAFT is flagged" "$out"
fi

# ── Test 11: displaced_by target itself status:DEPRECATED → fail ────────
setup_project "$PROJECT"
sed -i.bak 's/"status": "ACTIVE"/"status": "DEPRECATED"/' "$PROJECT/.spec/domains/example/successor.md"
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "DEPRECATED",
  "state": "APPROVED",
  "domains": ["example"],
  "displaced_by": ["example.successor"],
  "displacement_reason": "superseded",
  "removal_scheduled_in": "0.22.0",
  "deprecation_date": "2026-05-17"
}'
out=$(run_validate "$PROJECT" || true)
if echo "$out" | grep -q "chain deprecations create confusion"; then
    pass "displaced_by target status:DEPRECATED is flagged"
else
    fail "displaced_by target status:DEPRECATED is flagged" "$out"
fi

# ── Test 12: properly-formed status:DEPRECATED → pass ───────────────────
setup_project "$PROJECT"
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "DEPRECATED",
  "state": "APPROVED",
  "domains": ["example"],
  "displaced_by": ["example.successor"],
  "displacement_reason": "superseded by example.successor",
  "removal_scheduled_in": "0.22.0",
  "deprecation_date": "2026-05-17"
}'
rc=0
out=$(run_validate "$PROJECT" 2>&1) || rc=$?
if [[ $rc -eq 0 ]]; then
    pass "well-formed status:DEPRECATED spec validates clean"
else
    fail "well-formed status:DEPRECATED spec validates clean" "rc=$rc; out=$out"
fi

# ── Test 13: state:INVALIDATED + displaced_by WITHOUT audit-trail → fail
# (audit-trail-before-deletion contract: reproducer + KB article required
#  when invalidating a spec that had a successor)
setup_project "$PROJECT"
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "DEPRECATED",
  "state": "INVALIDATED",
  "domains": ["example"],
  "displaced_by": ["example.successor"],
  "displacement_reason": "retired after migration"
}'
out=$(run_validate "$PROJECT" || true)
if echo "$out" | grep -q "reproducer frontmatter"; then
    pass "INVALIDATED+displaced_by without reproducer is flagged"
else
    fail "INVALIDATED+displaced_by without reproducer is flagged" "$out"
fi
if echo "$out" | grep -q "missing KB archaeology article"; then
    pass "INVALIDATED+displaced_by without KB article is flagged"
else
    fail "INVALIDATED+displaced_by without KB article is flagged" "$out"
fi

# ── Test 14: state:INVALIDATED + displaced_by WITH audit-trail → pass
setup_project "$PROJECT"
# Create the reproducer file + KB article
mkdir -p "$PROJECT/src/legacy"
echo "// reproducer for legacy v5 format" > "$PROJECT/src/legacy/V5Synthesizer.java"
mkdir -p "$PROJECT/.kb/_legacy"
cat > "$PROJECT/.kb/_legacy/example.under-test.md" <<'EOF'
---
{
  "type": "legacy-archaeology",
  "spec_ref": "example.under-test",
  "removed_in": "0.22.0",
  "removed_at": "2026-05-17"
}
---

# Legacy: example.under-test

## What it was
A test artifact.

## Why it existed
For testing the audit trail.

## Why it was removed
Superseded by example.successor.

## How to reproduce
Use src/legacy/V5Synthesizer.java.
EOF
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "DEPRECATED",
  "state": "INVALIDATED",
  "domains": ["example"],
  "displaced_by": ["example.successor"],
  "displacement_reason": "retired after migration",
  "reproducer": {
    "type": "synthesizer",
    "path": "src/legacy/V5Synthesizer.java",
    "description": "v5 byte-stream synthesizer for forensic tests"
  }
}'
rc=0
out=$(run_validate "$PROJECT" 2>&1) || rc=$?
if [[ $rc -eq 0 ]]; then
    pass "INVALIDATED+displaced_by with full audit-trail validates clean"
else
    fail "INVALIDATED+displaced_by with full audit-trail validates clean" "rc=$rc; out=$out"
fi

# ── Test 15: state:INVALIDATED WITHOUT displaced_by → no audit-trail required
# (direct retirement of an unused contract)
setup_project "$PROJECT"
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "ACTIVE",
  "state": "INVALIDATED",
  "domains": ["example"]
}'
rc=0
out=$(run_validate "$PROJECT" 2>&1) || rc=$?
if [[ $rc -eq 0 ]]; then
    pass "INVALIDATED without displaced_by (direct retire) bypasses audit-trail gate"
else
    fail "INVALIDATED without displaced_by (direct retire) bypasses audit-trail gate" "rc=$rc; out=$out"
fi

# ── Test 16: reproducer path doesn't exist → fail
setup_project "$PROJECT"
mkdir -p "$PROJECT/.kb/_legacy"
cat > "$PROJECT/.kb/_legacy/example.under-test.md" <<'EOF'
---
{
  "type": "legacy-archaeology",
  "spec_ref": "example.under-test",
  "removed_in": "0.22.0",
  "removed_at": "2026-05-17"
}
---

# Legacy
Body.
EOF
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "DEPRECATED",
  "state": "INVALIDATED",
  "domains": ["example"],
  "displaced_by": ["example.successor"],
  "displacement_reason": "retired",
  "reproducer": {
    "type": "synthesizer",
    "path": "src/legacy/DoesNotExist.java"
  }
}'
out=$(run_validate "$PROJECT" || true)
if echo "$out" | grep -q "reproducer path does not exist"; then
    pass "missing reproducer file is flagged"
else
    fail "missing reproducer file is flagged" "$out"
fi

# ── Test 17: KB article has wrong spec_ref → fail
setup_project "$PROJECT"
mkdir -p "$PROJECT/src/legacy" "$PROJECT/.kb/_legacy"
echo "// reproducer" > "$PROJECT/src/legacy/V5.java"
cat > "$PROJECT/.kb/_legacy/example.under-test.md" <<'EOF'
---
{
  "type": "legacy-archaeology",
  "spec_ref": "different.spec",
  "removed_in": "0.22.0",
  "removed_at": "2026-05-17"
}
---

# Legacy
Body.
EOF
write_spec "$PROJECT" '{
  "id": "example.under-test",
  "version": 1,
  "status": "DEPRECATED",
  "state": "INVALIDATED",
  "domains": ["example"],
  "displaced_by": ["example.successor"],
  "displacement_reason": "retired",
  "reproducer": {"type": "synthesizer", "path": "src/legacy/V5.java"}
}'
out=$(run_validate "$PROJECT" || true)
if echo "$out" | grep -q "spec_ref.*does not match"; then
    pass "KB article wrong spec_ref is flagged"
else
    fail "KB article wrong spec_ref is flagged" "$out"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "── Scenario summary ────────────────────────────────────────────"
echo "  Passed: $passed / $total"
if [[ $failed -gt 0 ]]; then
    echo "  Failed: $failed"
    exit 1
fi
echo ""
exit 0
