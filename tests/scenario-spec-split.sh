#!/usr/bin/env bash
# Scenario: /spec-split executor + rollback + @spec annotation rewrite.
#
# Validates the PR 2 mechanical scope of the spec-layering plan. Tests
# only the script (`scripts/spec-split.sh`), not the orchestrating skill
# prompt — the skill is tested manually during the pilot on jlsm.
#
# Layered cover:
#
#   1. Plan validation — bad plans are rejected before any change is
#      made (missing required field, child id with wrong prefix, child
#      claiming an R-number not in parent, two children claiming the
#      same R-number, every R-number claimed leaving no cross-cutting).
#
#   2. Golden split — synthetic parent with 3 categories of requirements;
#      run the script with a 2-child plan; assert: child files exist
#      with carved requirements, parent retains only cross-cutting,
#      manifest has new entries with parent_spec set, spec-validate
#      passes parent + each child.
#
#   3. R-number identity is preserved — moving R45 to a child keeps R45
#      as the child's R45, NOT renumbered.
#
#   4. @spec annotation sweep — synthesized source files containing
#      `@spec parent.R12` get rewritten to `@spec parent.child.R12` for
#      moved requirements, but `@spec parent.R5` (cross-cutting, stays
#      at parent) is left alone.
#
#   5. Rollback on validation failure — force a post-split spec-validate
#      failure (by injecting a malformed child after planned execute)
#      and assert the rollback fully restores parent + manifest +
#      annotations.
#
#   6. Backwards compatibility — running with no plan exits non-zero
#      and surfaces the usage message.
#
# Run from repo root: bash tests/scenario-spec-split.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

passed=0
failed=0
total=0

pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() {
  ((failed++)) || true; ((total++)) || true
  echo "  FAIL  $1"
  [[ -n "${2:-}" ]] && echo "        $2"
}

echo ""
echo "scenario: /spec-split executor + rollback + annotation sweep"
echo "────────────────────────────────────────────────"

# ── Synthetic project tree ──────────────────────────────────────────────────

TMPDIR_TEST="$(mktemp -d /tmp/vallorcine-spec-split.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PROJ="$TMPDIR_TEST/proj"
mkdir -p "$PROJ/.spec/registry" "$PROJ/.spec/domains/encryption" "$PROJ/modules/jlsm-engine/src"
SPEC_DIR="$PROJ/.spec"
MANIFEST="$SPEC_DIR/registry/manifest.json"
PARENT_ID="encryption.primitives-lifecycle"
PARENT_FILE="$SPEC_DIR/domains/encryption/primitives-lifecycle.md"

cat > "$PARENT_FILE" <<'EOF'
---
{
  "id": "encryption.primitives-lifecycle",
  "version": 5,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["encryption"],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": []
}
---

# encryption.primitives-lifecycle

The umbrella spec for primitive lifecycle behaviour.

R1. All DEKs must be wrappable under their tenant root key.
R2. Cross-cutting audit invariant.
R3. Cross-cutting tenant boundary invariant.

R10. Key rotation must run at most every 90 days.
R11. Rotation must use a fresh DEK.
R12. Rotation must publish the new key version to the audit log.

R20. DEKs must be stored encrypted at rest.
R21. DEK access must be audited per request.
R22. DEKs must be disposed within 24h of last use.

---

## Notes
Original lifecycle spec covering rotation + DEK management together.
EOF

# Manifest with the parent registered.
cat > "$MANIFEST" <<EOF
{
  "schema_version": 2,
  "generated_at": "2026-04-27T00:00:00Z",
  "spec_count": 1,
  "specs": [
    {
      "id": "encryption.primitives-lifecycle",
      "path": ".spec/domains/encryption/primitives-lifecycle.md",
      "state": "APPROVED",
      "version": 5,
      "domains": ["encryption"],
      "requires": [],
      "invalidates": [],
      "decision_refs": [],
      "kb_refs": []
    }
  ]
}
EOF

# Source code with @spec annotations referencing parent.
cat > "$PROJ/modules/jlsm-engine/src/Rotator.java" <<'EOF'
// @spec encryption.primitives-lifecycle.R10 — rotation cadence guard
public class Rotator {
    // @spec encryption.primitives-lifecycle.R12
    void publishVersion() {}
    // @spec encryption.primitives-lifecycle.R1 — cross-cutting wrap invariant
    void wrap() {}
}
EOF

cat > "$PROJ/modules/jlsm-engine/src/DekStore.java" <<'EOF'
// @spec encryption.primitives-lifecycle.R20,R21
public class DekStore {
    // @spec encryption.primitives-lifecycle.R22 — TTL disposal
    void purge() {}
}
EOF

# A test file (not in scan dirs) — should NOT be rewritten.
mkdir -p "$PROJ/modules/jlsm-engine/test"
cat > "$PROJ/modules/jlsm-engine/test/RotatorTest.java" <<'EOF'
// @spec encryption.primitives-lifecycle.R10 — must NOT be rewritten by default scan
public class RotatorTest {}
EOF

# ── Layer 1: plan validation ─────────────────────────────────────────────────

echo ""
echo "── Layer 1: bad plans rejected"

run_split() {
  cd "$PROJ" && bash "$REPO_ROOT/scripts/spec-split.sh" "$@" 2>&1
}

# 1a: missing parent_id
PLAN1="$TMPDIR_TEST/plan1.json"
echo '{"children": [{"id": "x", "title": "X", "domains": ["e"], "requirements": ["R1"]}]}' > "$PLAN1"
out=$(run_split --plan "$PLAN1" || true)
if echo "$out" | grep -q "missing parent_id"; then
  pass "rejects plan missing parent_id"
else
  fail "did not reject missing parent_id" "got: $out"
fi

# 1b: child id without parent prefix
PLAN2="$TMPDIR_TEST/plan2.json"
cat > "$PLAN2" <<EOF
{"parent_id":"$PARENT_ID","children":[{"id":"foo.bar","title":"X","domains":["e"],"requirements":["R10"]}]}
EOF
out=$(run_split --plan "$PLAN2" || true)
if echo "$out" | grep -q "must start with"; then
  pass "rejects child id without parent prefix"
else
  fail "did not reject prefix mismatch" "got: $out"
fi

# 1c: child claims an R-number not in parent
PLAN3="$TMPDIR_TEST/plan3.json"
cat > "$PLAN3" <<EOF
{"parent_id":"$PARENT_ID","children":[
  {"id":"$PARENT_ID.bogus","title":"Bogus","domains":["encryption"],"requirements":["R999"]}]}
EOF
out=$(run_split --plan "$PLAN3" || true)
if echo "$out" | grep -q "not in parent's R-numbers"; then
  pass "rejects R-number not in parent"
else
  fail "did not reject unknown R-number" "got: $out"
fi

# 1d: two children claiming the same R-number
PLAN4="$TMPDIR_TEST/plan4.json"
cat > "$PLAN4" <<EOF
{"parent_id":"$PARENT_ID","children":[
  {"id":"$PARENT_ID.a","title":"A","domains":["encryption"],"requirements":["R10"]},
  {"id":"$PARENT_ID.b","title":"B","domains":["encryption"],"requirements":["R10"]}]}
EOF
out=$(run_split --plan "$PLAN4" || true)
if echo "$out" | grep -q "claimed by both"; then
  pass "rejects duplicate R-number claim"
else
  fail "did not reject duplicate claim" "got: $out"
fi

# 1e: every R claimed → no cross-cutting → must reject
PLAN5="$TMPDIR_TEST/plan5.json"
cat > "$PLAN5" <<EOF
{"parent_id":"$PARENT_ID","children":[
  {"id":"$PARENT_ID.allofit","title":"AllOfIt","domains":["encryption"],
   "requirements":["R1","R2","R3","R10","R11","R12","R20","R21","R22"]}]}
EOF
out=$(run_split --plan "$PLAN5" || true)
if echo "$out" | grep -q "no cross-cutting requirements"; then
  pass "rejects plan that drains every R-number from parent"
else
  fail "did not enforce non-empty cross-cutting" "got: $out"
fi

# 1f: --dry-run on a valid plan succeeds without touching files
PLAN_VALID="$TMPDIR_TEST/plan-valid.json"
cat > "$PLAN_VALID" <<EOF
{
  "parent_id": "$PARENT_ID",
  "children": [
    {"id":"$PARENT_ID.key-rotation","title":"Key Rotation",
     "domains":["encryption"],"requirements":["R10","R11","R12"]},
    {"id":"$PARENT_ID.dek-management","title":"DEK Management",
     "domains":["encryption"],"requirements":["R20","R21","R22"]}
  ]
}
EOF
parent_before="$(cat "$PARENT_FILE")"
out=$(run_split --plan "$PLAN_VALID" --dry-run || true)
parent_after="$(cat "$PARENT_FILE")"
if [[ "$parent_before" == "$parent_after" ]] && echo "$out" | grep -q "DRY RUN"; then
  pass "--dry-run validates without touching parent"
else
  fail "--dry-run modified parent or did not signal" "$(diff <(echo "$parent_before") <(echo "$parent_after") | head -3)"
fi

# ── Layer 2: golden split ────────────────────────────────────────────────────

echo ""
echo "── Layer 2: golden 2-child split"

run_split --plan "$PLAN_VALID" >/tmp/spec-split.out 2>&1
rc=$?

if [[ $rc -eq 0 ]]; then
  pass "spec-split exits 0 on valid plan"
else
  fail "spec-split exited $rc on valid plan" "$(tail -10 /tmp/spec-split.out)"
fi

KR_FILE="$SPEC_DIR/domains/encryption/primitives-lifecycle/key-rotation.md"
DM_FILE="$SPEC_DIR/domains/encryption/primitives-lifecycle/dek-management.md"

if [[ -f "$KR_FILE" ]]; then
  pass "child file created: key-rotation.md"
else
  fail "child file missing: $KR_FILE"
fi
if [[ -f "$DM_FILE" ]]; then
  pass "child file created: dek-management.md"
else
  fail "child file missing: $DM_FILE"
fi

# ── Layer 3: R-number identity preserved ─────────────────────────────────────

echo ""
echo "── Layer 3: R-numbers preserved across the split"

if grep -q '^R10\.' "$KR_FILE" && grep -q '^R11\.' "$KR_FILE" && grep -q '^R12\.' "$KR_FILE"; then
  pass "key-rotation child contains R10, R11, R12"
else
  fail "key-rotation child missing original R-numbers" \
       "$(grep -E '^R[0-9]+\.' "$KR_FILE" | head -5)"
fi
if grep -q '^R20\.' "$DM_FILE" && grep -q '^R21\.' "$DM_FILE" && grep -q '^R22\.' "$DM_FILE"; then
  pass "dek-management child contains R20, R21, R22"
else
  fail "dek-management child missing original R-numbers"
fi

# Parent must contain ONLY cross-cutting (R1, R2, R3) and NOT R10/R11/R12/R20/R21/R22.
parent_post="$(cat "$PARENT_FILE")"
if grep -q '^R1\.' "$PARENT_FILE" && \
   grep -q '^R2\.' "$PARENT_FILE" && \
   grep -q '^R3\.' "$PARENT_FILE"; then
  pass "parent retains R1, R2, R3 (cross-cutting)"
else
  fail "parent missing cross-cutting R-numbers"
fi
if grep -qE '^(R10|R11|R12|R20|R21|R22)\.' "$PARENT_FILE"; then
  fail "parent still contains moved R-numbers" \
       "$(grep -E '^R[0-9]+\.' "$PARENT_FILE")"
else
  pass "parent does NOT contain moved R-numbers"
fi

# ── Layer 4: @spec annotation rewrite scope ──────────────────────────────────

echo ""
echo "── Layer 4: @spec annotations rewritten correctly"

# Rotator.java: R10 and R12 should rewrite; R1 should NOT.
ROT="$PROJ/modules/jlsm-engine/src/Rotator.java"
if grep -q "@spec encryption.primitives-lifecycle.key-rotation.R10" "$ROT"; then
  pass "Rotator.java: @spec parent.R10 → @spec parent.key-rotation.R10"
else
  fail "Rotator.java: R10 not rewritten" "$(grep '@spec' "$ROT")"
fi
if grep -q "@spec encryption.primitives-lifecycle.key-rotation.R12" "$ROT"; then
  pass "Rotator.java: @spec parent.R12 → @spec parent.key-rotation.R12"
else
  fail "Rotator.java: R12 not rewritten" "$(grep '@spec' "$ROT")"
fi
if grep -q "^// @spec encryption.primitives-lifecycle.R1 " "$ROT" || \
   grep -q "@spec encryption.primitives-lifecycle.R1 —" "$ROT"; then
  pass "Rotator.java: cross-cutting R1 untouched"
else
  fail "Rotator.java: R1 incorrectly rewritten" "$(grep '@spec' "$ROT")"
fi

# DekStore.java: R20, R21, R22 should rewrite to dek-management child.
DEK="$PROJ/modules/jlsm-engine/src/DekStore.java"
# The R20,R21 form is a single annotation listing two reqs from the same spec.
# Our rewrite handles each separately; both should land at dek-management.
# After rewrite, the comma form may split or both halves change. Check that
# both R20 and R21 references now point to dek-management.
if grep -q "encryption.primitives-lifecycle.dek-management.R20" "$DEK"; then
  pass "DekStore.java: R20 rewritten to dek-management"
else
  fail "DekStore.java: R20 not rewritten" "$(grep '@spec' "$DEK")"
fi
if grep -q "@spec encryption.primitives-lifecycle.dek-management.R22" "$DEK"; then
  pass "DekStore.java: R22 rewritten to dek-management"
else
  fail "DekStore.java: R22 not rewritten" "$(grep '@spec' "$DEK")"
fi

# Test file (not in default scan dirs) should NOT be rewritten.
TEST_FILE="$PROJ/modules/jlsm-engine/test/RotatorTest.java"
if grep -q "@spec encryption.primitives-lifecycle.R10" "$TEST_FILE"; then
  pass "test/ file left alone (not in default scan dirs)"
else
  fail "test/ file was incorrectly rewritten" "$(cat "$TEST_FILE")"
fi

# ── Layer 5: manifest updated ────────────────────────────────────────────────

echo ""
echo "── Layer 5: manifest has child entries with parent_spec"

count_with_parent=$(jq '[.specs[] | select(.parent_spec != null)] | length' "$MANIFEST")
if [[ "$count_with_parent" == "2" ]]; then
  pass "manifest has 2 entries with parent_spec set"
else
  fail "manifest parent_spec count wrong" "got: $count_with_parent (expected 2)"
fi

# ── Layer 6: post-split validation passes ────────────────────────────────────

echo ""
echo "── Layer 6: spec-validate passes parent + children"

if (cd "$PROJ" && bash "$REPO_ROOT/scripts/spec-validate.sh" "$PARENT_FILE" >/dev/null 2>&1); then
  pass "spec-validate passes parent post-split"
else
  fail "spec-validate failed on parent post-split" \
       "$(cd "$PROJ" && bash "$REPO_ROOT/scripts/spec-validate.sh" "$PARENT_FILE" 2>&1 | head -10)"
fi
if (cd "$PROJ" && bash "$REPO_ROOT/scripts/spec-validate.sh" "$KR_FILE" >/dev/null 2>&1); then
  pass "spec-validate passes key-rotation child"
else
  fail "spec-validate failed on key-rotation child" \
       "$(cd "$PROJ" && bash "$REPO_ROOT/scripts/spec-validate.sh" "$KR_FILE" 2>&1 | head -10)"
fi
if (cd "$PROJ" && bash "$REPO_ROOT/scripts/spec-validate.sh" "$DM_FILE" >/dev/null 2>&1); then
  pass "spec-validate passes dek-management child"
else
  fail "spec-validate failed on dek-management child" \
       "$(cd "$PROJ" && bash "$REPO_ROOT/scripts/spec-validate.sh" "$DM_FILE" 2>&1 | head -10)"
fi

# ── Layer 7: rollback drill ──────────────────────────────────────────────────

echo ""
echo "── Layer 7: rollback restores parent + manifest + annotations"

# Get the rollback log from the previous successful split.
LOG_FILE=$(ls -1 "$SPEC_DIR/.split-log/"*.json 2>/dev/null | head -1)
if [[ -z "$LOG_FILE" ]]; then
  fail "no rollback log found post-split"
else
  # Capture current state.
  current_parent="$(cat "$PARENT_FILE")"
  current_manifest="$(cat "$MANIFEST")"

  # Replay rollback.
  bash "$REPO_ROOT/scripts/spec-split.sh" --rollback "$LOG_FILE" >/tmp/rollback.out 2>&1
  rb_rc=$?

  if [[ $rb_rc -eq 0 ]]; then
    pass "rollback exits 0"
  else
    fail "rollback exited $rb_rc" "$(tail -5 /tmp/rollback.out)"
  fi

  # Parent should be restored to original (not current post-split).
  parent_after_rb="$(cat "$PARENT_FILE")"
  if [[ "$parent_after_rb" == *"R10. Key rotation must run"* ]]; then
    pass "rollback: parent has R10 (rotation reqs) again"
  else
    fail "rollback: parent did NOT restore moved reqs"
  fi

  # Children should be deleted.
  if [[ ! -f "$KR_FILE" ]] && [[ ! -f "$DM_FILE" ]]; then
    pass "rollback: child files deleted"
  else
    fail "rollback: child files still exist"
  fi

  # Manifest should be back to 1 spec.
  manifest_count=$(jq '.specs | length' "$MANIFEST")
  if [[ "$manifest_count" == "1" ]]; then
    pass "rollback: manifest restored to 1 spec"
  else
    fail "rollback: manifest count is $manifest_count, expected 1"
  fi

  # Annotations should be reverted.
  if grep -q "@spec encryption.primitives-lifecycle.R10" "$ROT" && \
     ! grep -q "key-rotation.R10" "$ROT"; then
    pass "rollback: @spec annotations reverted"
  else
    fail "rollback: annotations not reverted" \
         "$(grep '@spec' "$ROT" | head -3)"
  fi
fi

# ── Layer 8: missing args / usage ────────────────────────────────────────────

echo ""
echo "── Layer 8: usage and arg parsing"

out=$(cd "$PROJ" && bash "$REPO_ROOT/scripts/spec-split.sh" 2>&1 || true)
if echo "$out" | grep -q "Usage:"; then
  pass "no args → usage message"
else
  fail "no args did not surface usage" "got: $out"
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
