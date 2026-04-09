#!/usr/bin/env bash
# Scenario: spec-validate.sh correctly validates displacement fields
#
# Tests the new Checks 7b-7e:
# - displaced_by: array of FXX IDs that resolve via registry
# - revives: array of FXX IDs that must be INVALIDATED
# - revived_by: array of FXX IDs that resolve via registry
# - displacement_reason: string, warns when displaced_by is non-empty but reason missing
#
# Run from repo root: bash tests/scenario-spec-validate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-spec-validate"

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

cleanup() {
    rm -rf "$TEST_BASE" 2>/dev/null || true
}
trap cleanup EXIT

echo ""
echo "scenario: spec-validate displacement fields"
echo "────────────────────────────────────────────────"

# ── Setup: create a minimal .spec/ structure ─────────────────────────────────

cleanup
mkdir -p "$TEST_BASE/project/.spec/registry" "$TEST_BASE/project/.spec/domains/serialization"
mkdir -p "$TEST_BASE/project/.claude/scripts"

# Copy scripts
cp "$REPO_ROOT/scripts/spec-validate.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$TEST_BASE/project/.claude/scripts/"

# Create manifest with two features: F01 (APPROVED) and F02 (INVALIDATED)
cat > "$TEST_BASE/project/.spec/registry/manifest.json" << 'EOF'
{
  "domains": {
    "serialization": {
      "description": "data format support",
      "feature_count": 2
    }
  },
  "features": {
    "F01": {
      "latest_file": "domains/serialization/F01-json-support.md",
      "state": "APPROVED",
      "domains": ["serialization"]
    },
    "F02": {
      "latest_file": "domains/serialization/F02-yaml-support.md",
      "state": "INVALIDATED",
      "domains": ["serialization"]
    }
  }
}
EOF

# Create F01 — APPROVED spec
cat > "$TEST_BASE/project/.spec/domains/serialization/F01-json-support.md" << 'EOF'
---
{
  "id": "F01",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["serialization"],
  "amends": [],
  "amended_by": [],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": [],
  "open_obligations": []
}
---

# F01 — JSON Support

## Requirements
R1. The system must parse valid JSON input and produce structured output.
R2. Invalid JSON input must be rejected with a descriptive error message.

---

## Design Narrative

### Intent
Core serialization format.
EOF

# Create F02 — INVALIDATED spec
cat > "$TEST_BASE/project/.spec/domains/serialization/F02-yaml-support.md" << 'EOF'
---
{
  "id": "F02",
  "version": 1,
  "status": "DEPRECATED",
  "state": "INVALIDATED",
  "domains": ["serialization"],
  "amends": [],
  "amended_by": [],
  "requires": [],
  "invalidates": [],
  "displaced_by": ["F01"],
  "revives": [],
  "revived_by": [],
  "displacement_reason": "YAML removed in favor of JSON-only with SIMD",
  "decision_refs": [],
  "kb_refs": [],
  "open_obligations": []
}
---

# F02 — YAML Support

## Requirements
R1. The system must parse valid YAML input.

---

## Design Narrative

### Intent
Alternative format support — now displaced.
EOF

cd "$TEST_BASE/project"

# ── Test 1: Spec with no displacement fields passes ────────────────────────

echo ""
echo "── Test 1: Spec with no displacement fields passes (backwards compatible)"

output="$(bash .claude/scripts/spec-validate.sh .spec/domains/serialization/F01-json-support.md 2>&1)"
if echo "$output" | grep -q "PASS"; then
    pass "spec without displacement fields passes validation"
else
    fail "spec without displacement fields should pass" "got: $output"
fi

# ── Test 2: Spec with valid displacement fields passes ─────────────────────

echo ""
echo "── Test 2: Spec with valid displacement fields passes"

output="$(bash .claude/scripts/spec-validate.sh .spec/domains/serialization/F02-yaml-support.md 2>&1)"
if echo "$output" | grep -q "PASS"; then
    pass "spec with valid displacement fields passes"
else
    fail "spec with valid displacement fields should pass" "got: $output"
fi

# ── Test 3: displaced_by with invalid format fails ─────────────────────────

echo ""
echo "── Test 3: displaced_by with invalid format fails"

cat > "$TEST_BASE/project/.spec/domains/serialization/bad-displaced-by.md" << 'EOF'
---
{
  "id": "F99",
  "version": 1,
  "status": "ACTIVE",
  "state": "DRAFT",
  "domains": ["serialization"],
  "amends": [],
  "amended_by": [],
  "requires": [],
  "invalidates": [],
  "displaced_by": ["not-a-valid-id"],
  "decision_refs": [],
  "kb_refs": [],
  "open_obligations": []
}
---

# F99 — Bad displaced_by

## Requirements
R1. Test requirement.

---

## Design Narrative

### Intent
Test.
EOF

output="$(bash .claude/scripts/spec-validate.sh .spec/domains/serialization/bad-displaced-by.md 2>&1 || true)"
if echo "$output" | grep -q "FAIL"; then
    pass "invalid displaced_by format fails validation"
else
    fail "invalid displaced_by format should fail" "got: $output"
fi

# ── Test 4: displaced_by with unresolvable ID fails ────────────────────────

echo ""
echo "── Test 4: displaced_by with unresolvable ID fails"

cat > "$TEST_BASE/project/.spec/domains/serialization/bad-displaced-by2.md" << 'EOF'
---
{
  "id": "F98",
  "version": 1,
  "status": "ACTIVE",
  "state": "DRAFT",
  "domains": ["serialization"],
  "amends": [],
  "amended_by": [],
  "requires": [],
  "invalidates": [],
  "displaced_by": ["F77"],
  "decision_refs": [],
  "kb_refs": [],
  "open_obligations": []
}
---

# F98 — Bad displaced_by unresolvable

## Requirements
R1. Test requirement.

---

## Design Narrative

### Intent
Test.
EOF

output="$(bash .claude/scripts/spec-validate.sh .spec/domains/serialization/bad-displaced-by2.md 2>&1 || true)"
if echo "$output" | grep -q "Unresolvable displaced_by"; then
    pass "unresolvable displaced_by ID fails validation"
else
    fail "unresolvable displaced_by ID should fail" "got: $output"
fi

# ── Test 5: revives pointing to non-INVALIDATED spec fails ────────────────

echo ""
echo "── Test 5: revives pointing to non-INVALIDATED spec fails"

cat > "$TEST_BASE/project/.spec/domains/serialization/bad-revives.md" << 'EOF'
---
{
  "id": "F97",
  "version": 1,
  "status": "ACTIVE",
  "state": "DRAFT",
  "domains": ["serialization"],
  "amends": [],
  "amended_by": [],
  "requires": [],
  "invalidates": [],
  "revives": ["F01"],
  "decision_refs": [],
  "kb_refs": [],
  "open_obligations": []
}
---

# F97 — Bad revives (target is APPROVED, not INVALIDATED)

## Requirements
R1. Test requirement.

---

## Design Narrative

### Intent
Test.
EOF

output="$(bash .claude/scripts/spec-validate.sh .spec/domains/serialization/bad-revives.md 2>&1 || true)"
if echo "$output" | grep -q "must be INVALIDATED"; then
    pass "revives pointing to non-INVALIDATED spec fails"
else
    fail "revives should fail when target is not INVALIDATED" "got: $output"
fi

# ── Test 6: revives pointing to INVALIDATED spec passes ───────────────────

echo ""
echo "── Test 6: revives pointing to INVALIDATED spec passes"

cat > "$TEST_BASE/project/.spec/domains/serialization/good-revives.md" << 'EOF'
---
{
  "id": "F96",
  "version": 1,
  "status": "ACTIVE",
  "state": "DRAFT",
  "domains": ["serialization"],
  "amends": [],
  "amended_by": [],
  "requires": [],
  "invalidates": [],
  "revives": ["F02"],
  "decision_refs": [],
  "kb_refs": [],
  "open_obligations": []
}
---

# F96 — Good revives (target is INVALIDATED)

## Requirements
R1. Test requirement.

---

## Design Narrative

### Intent
Test.
EOF

output="$(bash .claude/scripts/spec-validate.sh .spec/domains/serialization/good-revives.md 2>&1)"
if echo "$output" | grep -q "PASS"; then
    pass "revives pointing to INVALIDATED spec passes"
else
    fail "revives should pass when target is INVALIDATED" "got: $output"
fi

# ── Test 7: displacement_reason warning when displaced_by non-empty ────────

echo ""
echo "── Test 7: displacement_reason warning when displaced_by non-empty but reason missing"

cat > "$TEST_BASE/project/.spec/domains/serialization/warn-no-reason.md" << 'EOF'
---
{
  "id": "F95",
  "version": 1,
  "status": "DEPRECATED",
  "state": "INVALIDATED",
  "domains": ["serialization"],
  "amends": [],
  "amended_by": [],
  "requires": [],
  "invalidates": [],
  "displaced_by": ["F01"],
  "decision_refs": [],
  "kb_refs": [],
  "open_obligations": []
}
---

# F95 — Missing displacement_reason

## Requirements
R1. Test requirement.

---

## Design Narrative

### Intent
Test.
EOF

output="$(bash .claude/scripts/spec-validate.sh .spec/domains/serialization/warn-no-reason.md 2>&1)"
if echo "$output" | grep -q "PASS" && echo "$output" | grep -q "WARN.*displacement_reason"; then
    pass "warns about missing displacement_reason but still passes"
else
    fail "should warn about missing reason but pass validation" "got: $output"
fi

# ── Test 8: revived_by with invalid format fails ──────────────────────────

echo ""
echo "── Test 8: revived_by with invalid format fails"

cat > "$TEST_BASE/project/.spec/domains/serialization/bad-revived-by.md" << 'EOF'
---
{
  "id": "F94",
  "version": 1,
  "status": "ACTIVE",
  "state": "DRAFT",
  "domains": ["serialization"],
  "amends": [],
  "amended_by": [],
  "requires": [],
  "invalidates": [],
  "revived_by": ["bad-format"],
  "decision_refs": [],
  "kb_refs": [],
  "open_obligations": []
}
---

# F94 — Bad revived_by

## Requirements
R1. Test requirement.

---

## Design Narrative

### Intent
Test.
EOF

output="$(bash .claude/scripts/spec-validate.sh .spec/domains/serialization/bad-revived-by.md 2>&1 || true)"
if echo "$output" | grep -q "FAIL"; then
    pass "invalid revived_by format fails validation"
else
    fail "invalid revived_by format should fail" "got: $output"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
if [[ $failed -eq 0 ]]; then
    echo "ALL PASSED  ($passed/$total)"
else
    echo "FAILED  $failed/$total  ($passed passed)"
fi
echo ""

exit $failed
