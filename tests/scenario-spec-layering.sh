#!/usr/bin/env bash
# Scenario: layered specs — parent + children with parent_spec field.
#
# Validates the PR 1 schema + read-path scope for the spec-layering
# initiative. Layered specs let a mature domain subdivide into a parent
# spec plus child sub-domain specs (recursive). Every node is a full
# spec; the parent retains cross-cutting R-requirements, children own
# concern-specific requirements.
#
# This test exercises:
#
#   1. ID grammar — multi-dot IDs (a.b.c.d) accepted by spec-trace and
#      spec-validate; bare names without a dot still rejected.
#   2. spec_file_for_id() — manifest lookup is preferred; ID-computed
#      path fallback resolves an unregistered child via deterministic
#      path computation (a.b.c → domains/a/b/c.md).
#   3. spec-validate.sh new checks — parent_spec resolves to an existing
#      spec; child ID is prefixed by parent ID + "." + one segment;
#      parent chain is acyclic.
#   4. spec-resolve.sh hierarchy-aware loading — when a child lands in
#      candidates, the parent chain is auto-included. INCLUDE_SIBLINGS=true
#      pulls in siblings.
#   5. Backwards compatibility — flat specs without parent_spec still
#      validate, resolve, and trace as before.
#
# Run from repo root: bash tests/scenario-spec-layering.sh

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
echo "scenario: layered specs (parent + children)"
echo "────────────────────────────────────────────────"

# ── Test fixture: synthetic project tree under /tmp/vallorcine/ ──────────────

TMPDIR_TEST="$(mktemp -d /tmp/vallorcine-spec-layering.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PROJ="$TMPDIR_TEST/proj"
mkdir -p "$PROJ/.spec/registry" "$PROJ/.spec/domains/encryption/primitives-lifecycle"
SPEC_DIR="$PROJ/.spec"
MANIFEST="$SPEC_DIR/registry/manifest.json"

# Spec template — minimal valid spec body.
write_spec() {
    local file="$1" id="$2" parent="$3" extra_reqs="${4:-}"
    local parent_field
    if [[ -n "$parent" ]]; then
        parent_field=$(printf ', "parent_spec": "%s"' "$parent")
    else
        parent_field=""
    fi
    cat > "$file" <<EOF
---
{
  "id": "$id",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["encryption"],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": []$parent_field
}
---

# $id

Human narrative.

R1. The $id spec must do its job.
R2. The spec must be parseable.
$extra_reqs

---

## Notes
EOF
}

# Build minimal manifest.
build_manifest() {
    local entries="$1"  # JSON array literal
    cat > "$MANIFEST" <<EOF
{
  "schema_version": 2,
  "generated_at": "2026-04-27T00:00:00Z",
  "spec_count": $(echo "$entries" | jq 'length'),
  "specs": $entries
}
EOF
}

# Build the parent spec.
PARENT_ID="encryption.primitives-lifecycle"
PARENT_FILE="$SPEC_DIR/domains/encryption/primitives-lifecycle.md"
write_spec "$PARENT_FILE" "$PARENT_ID" ""

# Build a child spec.
CHILD_ID="encryption.primitives-lifecycle.key-rotation"
CHILD_FILE="$SPEC_DIR/domains/encryption/primitives-lifecycle/key-rotation.md"
write_spec "$CHILD_FILE" "$CHILD_ID" "$PARENT_ID"

# Build a sibling.
SIBLING_ID="encryption.primitives-lifecycle.dek-management"
SIBLING_FILE="$SPEC_DIR/domains/encryption/primitives-lifecycle/dek-management.md"
write_spec "$SIBLING_FILE" "$SIBLING_ID" "$PARENT_ID"

# Manifest with parent + 2 children registered.
build_manifest '[
  {"id": "encryption.primitives-lifecycle",
   "path": ".spec/domains/encryption/primitives-lifecycle.md",
   "state": "APPROVED", "version": 1, "domains": ["encryption"],
   "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": []},
  {"id": "encryption.primitives-lifecycle.key-rotation",
   "path": ".spec/domains/encryption/primitives-lifecycle/key-rotation.md",
   "parent_spec": "encryption.primitives-lifecycle",
   "state": "APPROVED", "version": 1, "domains": ["encryption"],
   "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": []},
  {"id": "encryption.primitives-lifecycle.dek-management",
   "path": ".spec/domains/encryption/primitives-lifecycle/dek-management.md",
   "parent_spec": "encryption.primitives-lifecycle",
   "state": "APPROVED", "version": 1, "domains": ["encryption"],
   "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": []}
]'

# ── Layer 1: ID grammar — multi-dot IDs accepted ─────────────────────────────

echo ""
echo "── Layer 1: ID grammar accepts multi-dot IDs"

cd "$PROJ"

# spec-trace accepts a multi-dot ID (no need to find any matches; just no
# format error).
trace_out=$(bash "$REPO_ROOT/scripts/spec-trace.sh" "$CHILD_ID" "$PROJ" 2>&1 || true)
if echo "$trace_out" | grep -q "Invalid spec ID"; then
    fail "spec-trace rejects multi-dot ID $CHILD_ID" "output: $trace_out"
else
    pass "spec-trace accepts multi-dot ID $CHILD_ID"
fi

# spec-trace still rejects a bare bareword
trace_bad=$(bash "$REPO_ROOT/scripts/spec-trace.sh" "barenodot" "$PROJ" 2>&1 || true)
if echo "$trace_bad" | grep -q "Invalid spec ID"; then
    pass "spec-trace rejects bareword IDs (no dot)"
else
    fail "spec-trace incorrectly accepts bareword 'barenodot'" "output: $trace_bad"
fi

# spec-trace still accepts FXX
trace_fxx=$(bash "$REPO_ROOT/scripts/spec-trace.sh" "F01" "$PROJ" 2>&1 || true)
if echo "$trace_fxx" | grep -q "Invalid spec ID"; then
    fail "spec-trace rejects legacy F01" "output: $trace_fxx"
else
    pass "spec-trace accepts legacy FXX (F01)"
fi

# spec-trace still accepts single-dot domain.slug
trace_slug=$(bash "$REPO_ROOT/scripts/spec-trace.sh" "$PARENT_ID" "$PROJ" 2>&1 || true)
if echo "$trace_slug" | grep -q "Invalid spec ID"; then
    fail "spec-trace rejects single-dot $PARENT_ID" "output: $trace_slug"
else
    pass "spec-trace accepts single-dot domain.slug"
fi

# ── Layer 2: spec_file_for_id() — manifest + computed-path fallback ──────────

echo ""
echo "── Layer 2: spec_file_for_id() resolves registered + computed paths"

# We invoke through a shell that sources spec-lib.sh.
resolve_id() {
    local fid="$1"
    bash -c "source '$REPO_ROOT/scripts/spec-lib.sh'; spec_file_for_id '$MANIFEST' '$fid'"
}

# Registered child resolves via manifest.
child_path=$(resolve_id "$CHILD_ID")
if [[ "$child_path" == "$CHILD_FILE" ]]; then
    pass "spec_file_for_id resolves registered child via manifest"
else
    fail "spec_file_for_id failed for registered child" \
         "expected: $CHILD_FILE, got: $child_path"
fi

# Unregistered grandchild (no manifest entry) resolves via ID-computed path.
GRANDCHILD_ID="encryption.primitives-lifecycle.key-rotation.scheduled"
GRANDCHILD_FILE="$SPEC_DIR/domains/encryption/primitives-lifecycle/key-rotation/scheduled.md"
mkdir -p "$(dirname "$GRANDCHILD_FILE")"
write_spec "$GRANDCHILD_FILE" "$GRANDCHILD_ID" "$CHILD_ID"
gc_path=$(resolve_id "$GRANDCHILD_ID")
if [[ "$gc_path" == "$GRANDCHILD_FILE" ]]; then
    pass "spec_file_for_id falls back to ID-computed path for unregistered grandchild"
else
    fail "spec_file_for_id ID-computed fallback broken" \
         "expected: $GRANDCHILD_FILE, got: $gc_path"
fi

# Truly missing ID (not in manifest, no file at computed path) returns empty.
miss_path=$(resolve_id "encryption.does-not-exist")
if [[ -z "$miss_path" ]]; then
    pass "spec_file_for_id returns empty for unknown ID"
else
    fail "spec_file_for_id returned non-empty for missing ID" "got: $miss_path"
fi

# ── Layer 3: spec-validate — parent_spec checks ──────────────────────────────

echo ""
echo "── Layer 3: spec-validate enforces parent_spec invariants"

# Happy path: registered child with valid parent_spec passes.
val_out=$(bash "$REPO_ROOT/scripts/spec-validate.sh" "$CHILD_FILE" 2>&1)
val_rc=$?
if (( val_rc == 0 )); then
    pass "spec-validate passes on valid child with parent_spec"
else
    fail "spec-validate failed on valid child" "output: $val_out"
fi

# Parent (no parent_spec) still validates as today.
val_par=$(bash "$REPO_ROOT/scripts/spec-validate.sh" "$PARENT_FILE" 2>&1)
val_par_rc=$?
if (( val_par_rc == 0 )); then
    pass "spec-validate passes on parent (no parent_spec)"
else
    fail "spec-validate failed on parent" "output: $val_par"
fi

# Bad: parent_spec points to a missing spec.
BAD1="$SPEC_DIR/domains/encryption/primitives-lifecycle/bad-missing-parent.md"
write_spec "$BAD1" "encryption.primitives-lifecycle.bad-missing-parent" \
           "encryption.does-not-exist"
val_bad1=$(bash "$REPO_ROOT/scripts/spec-validate.sh" "$BAD1" 2>&1 || true)
if echo "$val_bad1" | grep -q "Unresolvable parent_spec"; then
    pass "spec-validate rejects parent_spec pointing at missing spec"
else
    fail "spec-validate accepted missing parent_spec" "output: $val_bad1"
fi

# Bad: child ID does not have parent's prefix.
BAD2="$SPEC_DIR/domains/encryption/wrong-prefix.md"
mkdir -p "$(dirname "$BAD2")"
write_spec "$BAD2" "encryption.wrong-prefix" "encryption.primitives-lifecycle"
val_bad2=$(bash "$REPO_ROOT/scripts/spec-validate.sh" "$BAD2" 2>&1 || true)
if echo "$val_bad2" | grep -q "ID prefix mismatch"; then
    pass "spec-validate rejects ID-prefix mismatch with parent_spec"
else
    fail "spec-validate accepted ID-prefix mismatch" "output: $val_bad2"
fi

# Bad: child ID has more than one segment beyond parent_spec (parent_spec
# must point at the IMMEDIATE parent).
BAD3="$SPEC_DIR/domains/encryption/primitives-lifecycle/key-rotation/skip-a-level.md"
mkdir -p "$(dirname "$BAD3")"
write_spec "$BAD3" "encryption.primitives-lifecycle.key-rotation.skip-a-level" \
           "encryption.primitives-lifecycle"  # NOTE: should be .key-rotation
val_bad3=$(bash "$REPO_ROOT/scripts/spec-validate.sh" "$BAD3" 2>&1 || true)
if echo "$val_bad3" | grep -q "ID-segment mismatch"; then
    pass "spec-validate rejects parent_spec skipping a level"
else
    fail "spec-validate accepted parent_spec skipping a level" "output: $val_bad3"
fi

# ── Layer 4: spec-resolve hierarchy-aware loading ────────────────────────────

echo ""
echo "── Layer 4: spec-resolve auto-includes parent chain + INCLUDE_SIBLINGS"

# Resolve targeting just the child via EXPLICIT_SPEC_IDS. Parent must be
# included automatically. Sibling must NOT (default INCLUDE_SIBLINGS=false).
resolve_out=$(cd "$PROJ" && \
    EXPLICIT_SPEC_IDS="$CHILD_ID" \
    bash "$REPO_ROOT/scripts/spec-resolve.sh" "key rotation" 8000 2>&1 || true)

if echo "$resolve_out" | grep -q "encryption.primitives-lifecycle.key-rotation"; then
    pass "spec-resolve includes the explicitly-requested child"
else
    fail "spec-resolve missed the explicit child" \
         "first lines: $(printf '%s' "$resolve_out" | head -10 | tr '\n' '|')"
fi

# Parent must be in the bundle (auto-included via parent chain).
if echo "$resolve_out" | grep -qE '^# encryption\.primitives-lifecycle$|"id":\s*"encryption\.primitives-lifecycle"'; then
    pass "spec-resolve auto-includes parent when child is selected"
else
    # The bundle emits `# <id>` headers as the spec body. Loosen check: parent
    # body must appear somewhere in stdout.
    if echo "$resolve_out" | grep -q "encryption.primitives-lifecycle"; then
        # Not enough — that string would also appear in child IDs.
        # Look for parent's R1 specifically.
        if echo "$resolve_out" | grep -q "The encryption.primitives-lifecycle spec must do its job"; then
            pass "spec-resolve auto-includes parent (parent's R1 present)"
        else
            fail "spec-resolve did not auto-include parent body" \
                 "parent body not in output"
        fi
    else
        fail "spec-resolve did not auto-include parent" \
             "parent ID not in output"
    fi
fi

# Sibling must NOT be in default mode.
if echo "$resolve_out" | grep -q "The encryption.primitives-lifecycle.dek-management spec must do its job"; then
    fail "spec-resolve included sibling without INCLUDE_SIBLINGS" \
         "sibling body should not appear in default mode"
else
    pass "spec-resolve omits siblings by default"
fi

# Now with INCLUDE_SIBLINGS=true, sibling MUST be in the bundle.
resolve_sib=$(cd "$PROJ" && \
    EXPLICIT_SPEC_IDS="$CHILD_ID" INCLUDE_SIBLINGS=true \
    bash "$REPO_ROOT/scripts/spec-resolve.sh" "key rotation" 8000 2>&1 || true)
if echo "$resolve_sib" | grep -q "The encryption.primitives-lifecycle.dek-management spec must do its job"; then
    pass "spec-resolve includes sibling when INCLUDE_SIBLINGS=true"
else
    fail "spec-resolve missed sibling under INCLUDE_SIBLINGS" \
         "first lines: $(printf '%s' "$resolve_sib" | head -10 | tr '\n' '|')"
fi

# ── Layer 5: backwards compatibility — flat specs still work ─────────────────

echo ""
echo "── Layer 5: flat specs (no parent_spec) keep working"

# Build a flat (unrelated) spec in another domain.
mkdir -p "$SPEC_DIR/domains/storage"
FLAT_FILE="$SPEC_DIR/domains/storage/format.md"
write_spec "$FLAT_FILE" "storage.format" ""

# Add to manifest by rebuilding.
build_manifest '[
  {"id": "encryption.primitives-lifecycle",
   "path": ".spec/domains/encryption/primitives-lifecycle.md",
   "state": "APPROVED", "version": 1, "domains": ["encryption"],
   "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": []},
  {"id": "encryption.primitives-lifecycle.key-rotation",
   "path": ".spec/domains/encryption/primitives-lifecycle/key-rotation.md",
   "parent_spec": "encryption.primitives-lifecycle",
   "state": "APPROVED", "version": 1, "domains": ["encryption"],
   "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": []},
  {"id": "encryption.primitives-lifecycle.dek-management",
   "path": ".spec/domains/encryption/primitives-lifecycle/dek-management.md",
   "parent_spec": "encryption.primitives-lifecycle",
   "state": "APPROVED", "version": 1, "domains": ["encryption"],
   "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": []},
  {"id": "storage.format",
   "path": ".spec/domains/storage/format.md",
   "state": "APPROVED", "version": 1, "domains": ["storage"],
   "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": []}
]'

# Validate the flat spec.
val_flat=$(bash "$REPO_ROOT/scripts/spec-validate.sh" "$FLAT_FILE" 2>&1)
val_flat_rc=$?
if (( val_flat_rc == 0 )); then
    pass "spec-validate passes on flat spec without parent_spec"
else
    fail "spec-validate broke on flat spec" "output: $val_flat"
fi

# Resolve the flat spec by itself. No parent should be added (storage.format
# has no parent_spec).
resolve_flat=$(cd "$PROJ" && \
    EXPLICIT_SPEC_IDS="storage.format" \
    bash "$REPO_ROOT/scripts/spec-resolve.sh" "storage format" 8000 2>&1 || true)
if echo "$resolve_flat" | grep -q "The storage.format spec must do its job"; then
    pass "spec-resolve handles flat spec normally"
else
    fail "spec-resolve broke on flat spec" \
         "first lines: $(printf '%s' "$resolve_flat" | head -10 | tr '\n' '|')"
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
