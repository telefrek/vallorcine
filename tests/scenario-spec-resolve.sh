#!/usr/bin/env bash
# Scenario: spec-resolve.sh displacement detection and INCLUDE_INVALIDATED
#
# Tests:
# - Backwards compatibility: no NEW_SPEC_FILES → no displacement section
# - Displacement detection via antonym pairs (must reject vs must accept)
# - Displacement detection via signal keywords (only support, remove, etc.)
# - No false positives: non-overlapping subjects produce no displacement
# - INCLUDE_INVALIDATED=true emits INVALIDATED specs section
# - INCLUDE_INVALIDATED absent → no INVALIDATED section
#
# Run from repo root: bash tests/scenario-spec-resolve.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-spec-resolve"

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
echo "scenario: spec-resolve displacement detection"
echo "────────────────────────────────────────────────"

# ── Setup: create a project with spec infrastructure ─────────────────────────

cleanup
mkdir -p "$TEST_BASE/project/.spec/registry" "$TEST_BASE/project/.spec/domains/serialization"
mkdir -p "$TEST_BASE/project/.claude/scripts"

# Copy scripts
cp "$REPO_ROOT/scripts/spec-resolve.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$TEST_BASE/project/.claude/scripts/"

# Create manifest with two features: F01 (APPROVED, YAML) and F02 (APPROVED, JSON)
cat > "$TEST_BASE/project/.spec/registry/manifest.json" << 'EOF'
{
  "domains": {
    "serialization": {
      "description": "data format serialization parsing",
      "feature_count": 3
    }
  },
  "features": {
    "F01": {
      "latest_file": "domains/serialization/F01-yaml-support.md",
      "state": "APPROVED",
      "domains": ["serialization"]
    },
    "F02": {
      "latest_file": "domains/serialization/F02-json-parsing.md",
      "state": "APPROVED",
      "domains": ["serialization"]
    },
    "F03": {
      "latest_file": "domains/serialization/F03-xml-support.md",
      "state": "INVALIDATED",
      "domains": ["serialization"]
    }
  }
}
EOF

# F01 — APPROVED YAML spec
cat > "$TEST_BASE/project/.spec/domains/serialization/F01-yaml-support.md" << 'EOF'
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

# F01 — YAML Support

## Requirements
R1. The serialization layer must accept YAML input and produce a valid document.
R2. YAML parsing errors must return a descriptive error message.

---

## Design Narrative

### Intent
Support YAML as an input format.
EOF

# F02 — APPROVED JSON spec
cat > "$TEST_BASE/project/.spec/domains/serialization/F02-json-parsing.md" << 'EOF'
---
{
  "id": "F02",
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

# F02 — JSON Parsing

## Requirements
R1. The serialization layer must accept JSON input and produce a valid document.
R2. JSON parsing errors must return a descriptive error message.

---

## Design Narrative

### Intent
Core JSON support.
EOF

# F03 — INVALIDATED XML spec (for revival testing)
cat > "$TEST_BASE/project/.spec/domains/serialization/F03-xml-support.md" << 'EOF'
---
{
  "id": "F03",
  "version": 1,
  "status": "DEPRECATED",
  "state": "INVALIDATED",
  "domains": ["serialization"],
  "amends": [],
  "amended_by": [],
  "requires": [],
  "invalidates": [],
  "displaced_by": ["F02"],
  "revives": [],
  "revived_by": [],
  "displacement_reason": "XML removed in favor of JSON",
  "decision_refs": [],
  "kb_refs": [],
  "open_obligations": []
}
---

# F03 — XML Support

## Requirements
R1. The serialization layer must accept XML input.

---

## Design Narrative

### Intent
Legacy format — now displaced.
EOF

# Create a new draft spec that says "only JSON"
mkdir -p "$TEST_BASE/drafts"
cat > "$TEST_BASE/drafts/F04-json-only.md" << 'EOF'
---
{
  "id": "F04",
  "version": 1,
  "status": "ACTIVE",
  "state": "DRAFT",
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

# F04 — JSON-Only Serialization

## Requirements
R1. The serialization layer must only support JSON as an input format.
R2. The serialization layer must reject YAML input with a clear error.

---

## Design Narrative

### Intent
Remove all non-JSON formats for SIMD optimization.
EOF

# Create a draft spec with no subject overlap (should NOT trigger displacement)
cat > "$TEST_BASE/drafts/F05-compression.md" << 'EOF'
---
{
  "id": "F05",
  "version": 1,
  "status": "ACTIVE",
  "state": "DRAFT",
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

# F05 — Compression Support

## Requirements
R1. The compression engine must support gzip encoding.
R2. The compression engine must support zstd encoding.

---

## Design Narrative

### Intent
Add compression support — unrelated to format parsing.
EOF

cd "$TEST_BASE/project"

# ── Test 1: No NEW_SPEC_FILES → no displacement section (backwards compat) ─

echo ""
echo "── Test 1: No NEW_SPEC_FILES → no displacement section"

output="$(OVERRIDE_DOMAINS="serialization" bash .claude/scripts/spec-resolve.sh "JSON serialization" 8000 2>/dev/null)"
if echo "$output" | grep -q "## Displacement"; then
    fail "displacement section should not appear without NEW_SPEC_FILES"
else
    pass "no displacement section when NEW_SPEC_FILES is absent"
fi

# ── Test 2: Displacement detected via keyword ("only support") ─────────────

echo ""
echo "── Test 2: Displacement detected via keyword signal"

output="$(NEW_SPEC_FILES="$TEST_BASE/drafts/F04-json-only.md" OVERRIDE_DOMAINS="serialization" \
  bash .claude/scripts/spec-resolve.sh "JSON only serialization" 8000 2>/dev/null)"
if echo "$output" | grep -q "## Displacement"; then
    pass "displacement section present"
else
    fail "displacement section should appear" "got: $output"
fi

# Check that YAML spec (F01) is detected as displaced
if echo "$output" | grep -q "F01"; then
    pass "F01 (YAML) detected in displacement"
else
    fail "F01 (YAML) should be displaced by the JSON-only spec" "got: $output"
fi

# ── Test 3: Displacement detected via antonym pair (must reject vs must accept)

echo ""
echo "── Test 3: Displacement detected via antonym pair"

# F04.R2 says "must reject YAML" — F01 has YAML as subject token
# The keyword "reject" in F04.R2 should trigger displacement signal
if echo "$output" | grep -q "DISPLACED.*F04.*F01"; then
    pass "antonym/keyword displacement detected between F04 and F01"
else
    fail "should detect displacement between F04 (reject YAML) and F01 (accept YAML)" "got displacement lines: $(echo "$output" | grep DISPLACED || echo 'none')"
fi

# ── Test 4: No false positive — unrelated subjects don't trigger ───────────

echo ""
echo "── Test 4: No false positive for unrelated subjects"

output_no_overlap="$(NEW_SPEC_FILES="$TEST_BASE/drafts/F05-compression.md" OVERRIDE_DOMAINS="serialization" \
  bash .claude/scripts/spec-resolve.sh "compression support" 8000 2>/dev/null)"
if echo "$output_no_overlap" | grep -q "## Displacement"; then
    fail "displacement should not appear for unrelated spec (compression vs serialization)"
else
    pass "no false positive for unrelated subjects"
fi

# ── Test 5: INCLUDE_INVALIDATED shows INVALIDATED specs section ────────────

echo ""
echo "── Test 5: INCLUDE_INVALIDATED=true shows INVALIDATED specs"

output_inv="$(INCLUDE_INVALIDATED=true OVERRIDE_DOMAINS="serialization" \
  bash .claude/scripts/spec-resolve.sh "serialization format" 8000 2>/dev/null)"
if echo "$output_inv" | grep -q "## INVALIDATED Specs"; then
    pass "INVALIDATED specs section present"
else
    fail "should show INVALIDATED Specs section when INCLUDE_INVALIDATED=true" "got: $output_inv"
fi

if echo "$output_inv" | grep -q "F03"; then
    pass "F03 (XML) appears in INVALIDATED section"
else
    fail "F03 should appear in INVALIDATED section" "got: $output_inv"
fi

# ── Test 6: Without INCLUDE_INVALIDATED → no INVALIDATED section ──────────

echo ""
echo "── Test 6: Without INCLUDE_INVALIDATED → no INVALIDATED section"

output_no_inv="$(OVERRIDE_DOMAINS="serialization" \
  bash .claude/scripts/spec-resolve.sh "serialization format" 8000 2>/dev/null)"
if echo "$output_no_inv" | grep -q "## INVALIDATED Specs"; then
    fail "should not show INVALIDATED section without INCLUDE_INVALIDATED"
else
    pass "no INVALIDATED section when INCLUDE_INVALIDATED is absent"
fi

# ── Test 7: Displacement reports signal type ──────────────────────────────

echo ""
echo "── Test 7: Displacement reports signal type"

output_signal="$(NEW_SPEC_FILES="$TEST_BASE/drafts/F04-json-only.md" OVERRIDE_DOMAINS="serialization" \
  bash .claude/scripts/spec-resolve.sh "JSON only" 8000 2>/dev/null)"
if echo "$output_signal" | grep -q "signal:"; then
    pass "displacement line includes signal type"
else
    fail "displacement should report signal type (keyword or antonym)" "got: $(echo "$output_signal" | grep DISPLACED || echo 'none')"
fi

# ── Test 8: Displacement reports subject token ─────────────────────────────

echo ""
echo "── Test 8: Displacement reports subject token"

if echo "$output_signal" | grep -q "subject:"; then
    pass "displacement line includes subject token"
else
    fail "displacement should report shared subject token" "got: $(echo "$output_signal" | grep DISPLACED || echo 'none')"
fi

# ── Test 9: NEW_SPEC_FILES with missing file doesn't crash ────────────────

echo ""
echo "── Test 9: NEW_SPEC_FILES with missing file doesn't crash"

output_missing="$(NEW_SPEC_FILES="/nonexistent/file.md" OVERRIDE_DOMAINS="serialization" \
  bash .claude/scripts/spec-resolve.sh "test" 8000 2>/dev/null)"
if [[ $? -eq 0 ]] || echo "$output_missing" | grep -q "Resolved Context Bundle"; then
    pass "missing NEW_SPEC_FILES file doesn't crash"
else
    fail "should handle missing file gracefully" "got: $output_missing"
fi

# ── Test 10: EXPLICIT_SPEC_IDS bypasses fuzzy match ─────────────────────────
# Regression for Item 1 of the post-v0.14.0 bug fix sweep: /feature-test's
# fuzzy match could miss specs that don't share vocabulary with the brief
# title. EXPLICIT_SPEC_IDS lets callers pass IDs directly.

echo ""
echo "── Test 10: EXPLICIT_SPEC_IDS bypasses fuzzy match"

# Feature description does NOT mention serialization/yaml/json — fuzzy match
# would miss F01 and F02. Explicit IDs must still load them.
output_explicit="$(EXPLICIT_SPEC_IDS="F01,F02" \
  bash .claude/scripts/spec-resolve.sh "completely unrelated description" 8000 2>/dev/null)"

if echo "$output_explicit" | grep -q "F01" && echo "$output_explicit" | grep -q "F02"; then
    pass "EXPLICIT_SPEC_IDS loads both requested specs"
else
    fail "explicit IDs should load F01 and F02" "got: $output_explicit"
fi

# Should not mention F03 (INVALIDATED, not in explicit list)
if echo "$output_explicit" | grep -q "## INVALIDATED"; then
    fail "INVALIDATED section should not appear when not explicitly requested"
else
    pass "INVALIDATED section absent without INCLUDE_INVALIDATED"
fi

# ── Test 11: EXPLICIT_SPEC_IDS with unknown ID emits warning ────────────────

echo ""
echo "── Test 11: EXPLICIT_SPEC_IDS with unknown ID emits warning (doesn't crash)"

stderr_output="$(EXPLICIT_SPEC_IDS="F01,F99-phantom" \
  bash .claude/scripts/spec-resolve.sh "any" 8000 2>&1 >/dev/null)"

if echo "$stderr_output" | grep -q "explicit spec 'F99-phantom' not in registry"; then
    pass "unknown explicit ID surfaces clear warning"
else
    fail "unknown ID should warn" "stderr: $stderr_output"
fi

# The known ID must still load despite the unknown one
output_mixed="$(EXPLICIT_SPEC_IDS="F01,F99-phantom" \
  bash .claude/scripts/spec-resolve.sh "any" 8000 2>/dev/null)"
if echo "$output_mixed" | grep -q "F01"; then
    pass "known explicit ID loads despite unknown sibling"
else
    fail "F01 should load even when F99 is unknown" "got: $output_mixed"
fi

# ── Test 12-16: v2 manifest schema compatibility ────────────────────────────
# Regression for the v2 migration gap (post-2026-04-20): spec-resolve.sh
# previously used `.features | keys[]` and `.domains | keys[]` jq queries
# that return null on a v2 manifest, causing `set -euo pipefail` failures
# and spurious NEEDS_DOMAIN_INFERENCE emissions.

echo ""
echo "── v2 manifest compatibility ────────────────────"

V2_ROOT="$TEST_BASE/project-v2"
mkdir -p "$V2_ROOT/.spec/registry" "$V2_ROOT/.spec/domains/serialization"
mkdir -p "$V2_ROOT/.claude/scripts"
cp "$REPO_ROOT/scripts/spec-resolve.sh" "$V2_ROOT/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$V2_ROOT/.claude/scripts/"

# v2 manifest: .specs[] array, .path instead of .latest_file, no .domains map.
cat > "$V2_ROOT/.spec/registry/manifest.json" << 'EOF'
{
  "schema_version": 2,
  "generated_at": "2026-04-23T00:00:00Z",
  "spec_count": 2,
  "specs": [
    {
      "id": "serialization.yaml-support",
      "path": ".spec/domains/serialization/yaml-support.md",
      "state": "APPROVED",
      "version": 1,
      "domains": ["serialization"],
      "requires": [],
      "invalidates": [],
      "decision_refs": [],
      "kb_refs": []
    },
    {
      "id": "serialization.json-parsing",
      "path": ".spec/domains/serialization/json-parsing.md",
      "state": "APPROVED",
      "version": 1,
      "domains": ["serialization"],
      "requires": [],
      "invalidates": [],
      "decision_refs": [],
      "kb_refs": []
    }
  ]
}
EOF

cat > "$V2_ROOT/.spec/domains/serialization/yaml-support.md" << 'EOF'
---
{
  "id": "serialization.yaml-support",
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

# serialization.yaml-support — YAML Support

## Requirements
R1. The serialization layer must accept YAML input.
EOF

cat > "$V2_ROOT/.spec/domains/serialization/json-parsing.md" << 'EOF'
---
{
  "id": "serialization.json-parsing",
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

# serialization.json-parsing — JSON Parsing

## Requirements
R1. The serialization layer must accept JSON input.
EOF

cd "$V2_ROOT"

# ── Test 12: v2 manifest — no jq error under set -euo pipefail ──────────────

echo ""
echo "── Test 12: v2 manifest produces no jq null-has-no-keys error"

v2_stderr="$(bash .claude/scripts/spec-resolve.sh "serialization format" 8000 2>&1 >/dev/null)"
if echo "$v2_stderr" | grep -q "null (null) has no keys"; then
    fail "v2 manifest must not trigger jq null-traversal error" "stderr: $v2_stderr"
else
    pass "v2 manifest does not emit jq schema-mismatch error"
fi

# ── Test 13: v2 manifest — domain name matching works ──────────────────────

echo ""
echo "── Test 13: v2 fuzzy match finds specs by domain name"

v2_output="$(bash .claude/scripts/spec-resolve.sh "serialization format" 8000 2>/dev/null)"
if echo "$v2_output" | grep -q "serialization.yaml-support" \
    && echo "$v2_output" | grep -q "serialization.json-parsing"; then
    pass "v2 fuzzy match loads both specs by domain name"
else
    fail "v2 fuzzy match should surface both specs" "got: $v2_output"
fi

# ── Test 14: v2 manifest — NEEDS_DOMAIN_INFERENCE graceful fallback ────────
# Feature description with no domain-name hits should cleanly fall through
# to the inference-needed path (not die with a jq error).

echo ""
echo "── Test 14: v2 NEEDS_DOMAIN_INFERENCE fallback is graceful"

v2_nomatch_stderr="$(bash .claude/scripts/spec-resolve.sh "completely unrelated thing" 8000 2>&1 >/dev/null)"
v2_nomatch_stdout="$(bash .claude/scripts/spec-resolve.sh "completely unrelated thing" 8000 2>/dev/null)"
if echo "$v2_nomatch_stderr" | grep -q "NEEDS_DOMAIN_INFERENCE=true"; then
    pass "NEEDS_DOMAIN_INFERENCE=true signal emitted"
else
    fail "should emit NEEDS_DOMAIN_INFERENCE on no match" "stderr: $v2_nomatch_stderr"
fi

if echo "$v2_nomatch_stdout" | grep -q "serialization"; then
    pass "available-domains list includes v2 domain"
else
    fail "partial bundle should list v2 domains" "stdout: $v2_nomatch_stdout"
fi

# ── Test 15: v2 manifest — EXPLICIT_SPEC_IDS with domain.slug format ───────

echo ""
echo "── Test 15: EXPLICIT_SPEC_IDS works with v2 domain.slug IDs"

v2_explicit="$(EXPLICIT_SPEC_IDS="serialization.yaml-support" \
    bash .claude/scripts/spec-resolve.sh "anything" 8000 2>/dev/null)"
if echo "$v2_explicit" | grep -q "serialization.yaml-support"; then
    pass "explicit domain.slug ID resolves in v2 manifest"
else
    fail "explicit ID should load in v2" "got: $v2_explicit"
fi

# ── Test 16: v2 manifest — OVERRIDE_DOMAINS selects from v2 specs ──────────

echo ""
echo "── Test 16: OVERRIDE_DOMAINS filters v2 specs correctly"

v2_override="$(OVERRIDE_DOMAINS="serialization" \
    bash .claude/scripts/spec-resolve.sh "x" 8000 2>/dev/null)"
if echo "$v2_override" | grep -q "serialization.yaml-support" \
    && echo "$v2_override" | grep -q "serialization.json-parsing"; then
    pass "OVERRIDE_DOMAINS loads both v2 specs"
else
    fail "OVERRIDE_DOMAINS should load serialization specs" "got: $v2_override"
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
