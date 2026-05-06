#!/usr/bin/env bash
# Scenario: spec-trace.sh finds @spec annotations across source and test files
#
# Tests:
# - Single requirement annotation (@spec F01.R1)
# - Multi-requirement same spec (@spec F01.R1,R3,R7)
# - Multi-spec annotation (@spec F01.R1 F02.R4)
# - Implementation vs test file classification
# - Feature ID isolation (F01 trace doesn't include F02-only annotations)
# - Invalid feature ID rejection (F1 not zero-padded)
# - No-match case exits cleanly
# - Summary, detail, and JSON output formats
# - SPEC_TRACE_DIRS override
# - --uncovered mode: emits R-ids defined in spec but absent from annotations
#
# Run from repo root: bash tests/scenario-spec-trace.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-spec-trace"
TRACE_SCRIPT="$REPO_ROOT/scripts/spec-trace.sh"

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
echo "scenario: spec-trace annotation discovery"
echo "────────────────────────────────────────────────"

# ── Setup: create a mock project with @spec annotations ─────────────────────

cleanup
mkdir -p "$TEST_BASE/project/src/auth" "$TEST_BASE/project/test/auth"
mkdir -p "$TEST_BASE/project/src/data" "$TEST_BASE/project/lib"
mkdir -p "$TEST_BASE/project/.git"  # so project root detection works

# Source file with single annotation
cat > "$TEST_BASE/project/src/auth/Auth.java" << 'JAVA'
package com.example.auth;

// @spec F01.R1 — rejects null keys
public void add(Key key, Value value) {
    if (key == null) throw new NullKeyException();
}
JAVA

# Source file with multi-req same spec
cat > "$TEST_BASE/project/src/auth/Validator.java" << 'JAVA'
package com.example.auth;

// @spec F01.R3,R7
public void validate(Token token) {
    // validation logic
}
JAVA

# Source file with cross-spec annotation
cat > "$TEST_BASE/project/src/data/Serializer.java" << 'JAVA'
package com.example.data;

// @spec F01.R1 F02.R4 — shared serialization constraint
public void serialize(Record record) {
    // serialization
}
JAVA

# Test file with annotations
cat > "$TEST_BASE/project/test/auth/AuthTest.java" << 'JAVA'
package com.example.auth;

// @spec F01.R1,R3
@Test void testNullKeyRejection() { }

// @spec F01.R7
@Test void testTokenValidation() { }
JAVA

# File with only F02 annotations (should NOT appear in F01 trace)
cat > "$TEST_BASE/project/src/data/Other.java" << 'JAVA'
package com.example.data;

// @spec F02.R1
public void otherThing() { }
JAVA

# Python file with annotation
cat > "$TEST_BASE/project/lib/helper.py" << 'PY'
# @spec F01.R12 — helper constraint
def helper():
    pass
PY

# ── Test 1: Invalid feature ID rejected ─────────────────────────────────────

output=$(cd "$TEST_BASE/project" && bash "$TRACE_SCRIPT" F1 2>&1 || true)
if echo "$output" | grep -q "Invalid spec ID"; then
    pass "rejects F1 (not zero-padded)"
else
    fail "should reject F1" "got: $output"
fi

# ── Test 1b: Accepts new domain.slug format ─────────────────────────────────

output=$(cd "$TEST_BASE/project" && bash "$TRACE_SCRIPT" schema.field-access 2>&1 || true)
if echo "$output" | grep -q "Invalid spec ID"; then
    fail "should accept domain.slug format" "got: $output"
else
    pass "accepts domain.slug format (schema.field-access)"
fi

# ── Test 1c: Rejects malformed mixed format ─────────────────────────────────

output=$(cd "$TEST_BASE/project" && bash "$TRACE_SCRIPT" "Schema.field" 2>&1 || true)
if echo "$output" | grep -q "Invalid spec ID"; then
    pass "rejects uppercase domain (Schema.field)"
else
    fail "should reject uppercase domain" "got: $output"
fi

# ── Test 2: Valid feature ID accepted ────────────────────────────────────────

output=$(cd "$TEST_BASE/project" && bash "$TRACE_SCRIPT" F01 2>/dev/null)
if echo "$output" | grep -q "F01 — Trace Report"; then
    pass "accepts F01 and produces report"
else
    fail "should produce trace report for F01" "got: $output"
fi

# ── Test 3: Finds all F01 requirements ───────────────────────────────────────

output=$(cd "$TEST_BASE/project" && bash "$TRACE_SCRIPT" F01 2>/dev/null)
if echo "$output" | grep -q "F01.R1" && \
   echo "$output" | grep -q "F01.R3" && \
   echo "$output" | grep -q "F01.R7" && \
   echo "$output" | grep -q "F01.R12"; then
    pass "finds all four F01 requirements (R1, R3, R7, R12)"
else
    fail "should find R1, R3, R7, R12" "got: $output"
fi

# ── Test 4: F01.R1 has 2 impl + 1 test ──────────────────────────────────────

output=$(cd "$TEST_BASE/project" && bash "$TRACE_SCRIPT" F01 2>/dev/null)
r1_line=$(echo "$output" | grep "F01.R1 " || true)
if echo "$r1_line" | grep -qE "\| 2 \| 1 \|"; then
    pass "F01.R1 has 2 implementation + 1 test annotations"
else
    fail "F01.R1 should have 2 impl + 1 test" "got: $r1_line"
fi

# ── Test 5: F01.R12 has 1 impl + 0 tests ────────────────────────────────────

r12_line=$(echo "$output" | grep "F01.R12" || true)
if echo "$r12_line" | grep -qE "\| 1 \| 0 \|"; then
    pass "F01.R12 has 1 implementation + 0 test annotations"
else
    fail "F01.R12 should have 1 impl + 0 test" "got: $r12_line"
fi

# ── Test 6: No-impl/no-test summary ─────────────────────────────────────────

if echo "$output" | grep -q "No test annotations.*F01.R12"; then
    pass "summary reports F01.R12 has no test annotations"
else
    fail "should report F01.R12 has no test annotations" "got last lines: $(echo "$output" | tail -3)"
fi

# ── Test 7: F02 trace only shows F02 annotations ────────────────────────────

output_f02=$(cd "$TEST_BASE/project" && bash "$TRACE_SCRIPT" F02 2>/dev/null)
if echo "$output_f02" | grep -q "F02.R4" && \
   echo "$output_f02" | grep -q "F02.R1" && \
   ! echo "$output_f02" | grep -q "F01"; then
    pass "F02 trace shows only F02 annotations (R1, R4), no F01 leakage"
else
    fail "F02 trace should only show F02 refs" "got: $output_f02"
fi

# ── Test 8: No-match feature exits cleanly ───────────────────────────────────

output_none=$(cd "$TEST_BASE/project" && bash "$TRACE_SCRIPT" F99 2>/dev/null)
if echo "$output_none" | grep -q "No annotations found"; then
    pass "F99 (no matches) reports no annotations found"
else
    fail "F99 should report no annotations" "got: $output_none"
fi

# ── Test 9: Detail format produces per-requirement sections ──────────────────

output_detail=$(cd "$TEST_BASE/project" && SPEC_TRACE_FORMAT=detail bash "$TRACE_SCRIPT" F01 2>/dev/null)
if echo "$output_detail" | grep -q "### F01.R1" && \
   echo "$output_detail" | grep -q "### F01.R3" && \
   echo "$output_detail" | grep -q "**Implementation**" && \
   echo "$output_detail" | grep -q "**Test**"; then
    pass "detail format produces per-requirement sections with impl/test grouping"
else
    fail "detail format should have ### headings and impl/test groups"
fi

# ── Test 10: JSON format produces valid structure ────────────────────────────

output_json=$(cd "$TEST_BASE/project" && SPEC_TRACE_FORMAT=json bash "$TRACE_SCRIPT" F01 2>/dev/null)
if echo "$output_json" | grep -q '"spec": "F01"' && \
   echo "$output_json" | grep -q '"F01.R1"' && \
   echo "$output_json" | grep -q '"implementation"' && \
   echo "$output_json" | grep -q '"test"'; then
    pass "JSON format produces structured output with spec, requirements, impl/test arrays"
else
    fail "JSON format should have spec, requirements, impl/test" "got: $output_json"
fi

# ── Test 11: SPEC_TRACE_DIRS limits scan scope ──────────────────────────────

output_limited=$(cd "$TEST_BASE/project" && SPEC_TRACE_DIRS="src" bash "$TRACE_SCRIPT" F01 2>/dev/null)
# With only src/, we should not see test annotations
r1_limited=$(echo "$output_limited" | grep "F01.R1 " || true)
if echo "$r1_limited" | grep -qE "\| 0 \|"; then
    pass "SPEC_TRACE_DIRS=src excludes test directory from scan"
else
    fail "limiting to src/ should show 0 test annotations" "got: $r1_limited"
fi

# ── Test 12: Cross-spec annotation parsed correctly ──────────────────────────

# F01.R1 should appear in Serializer.java (cross-spec line: @spec F01.R1 F02.R4)
if echo "$output_detail" | grep "F01.R1" | grep -q "Serializer"; then
    pass "cross-spec annotation correctly parsed (F01.R1 from @spec F01.R1 F02.R4 line)"
else
    # Check if Serializer appears anywhere in R1 section
    r1_section=$(echo "$output_detail" | sed -n '/### F01.R1/,/### F01.R3/p')
    if echo "$r1_section" | grep -q "Serializer"; then
        pass "cross-spec annotation correctly parsed (F01.R1 from @spec F01.R1 F02.R4 line)"
    else
        fail "cross-spec annotation should include Serializer.java for F01.R1" "R1 section: $r1_section"
    fi
fi

# ── Test 13: Description text after -- doesn't interfere ────────────────────

# The "— rejects null keys" text should not be parsed as a requirement reference
req_count=$(echo "$output" | grep -oP 'Requirements traced:\*\*\s+\K[0-9]+' || echo "0")
if [[ "$req_count" -eq 4 ]]; then
    pass "description text after — separator does not create false requirement matches"
else
    fail "should have exactly 4 requirements (R1, R3, R7, R12)" "got: $req_count"
fi

# ── --uncovered mode setup ───────────────────────────────────────────────────
# Add a .spec/ directory with a manifest and two spec files. F01 defines R1,
# R3, R5, R7, R12 — only R5 has no annotation in the fixture above. F02
# defines R1, R4, R8 — only R8 has no annotation.

mkdir -p "$TEST_BASE/project/.spec/registry"
mkdir -p "$TEST_BASE/project/.spec/domains/auth"
mkdir -p "$TEST_BASE/project/.spec/domains/data"

cat > "$TEST_BASE/project/.spec/domains/auth/F01-jwt-token.md" << 'EOF'
---
{
  "id": "F01",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["auth"]
}
---

# F01 — JWT Token Contract

## Requirements

R1. The system must reject null keys.
R3. The system must validate token signatures.
R5. The system must enforce token expiry. (uncovered — no @spec annotation)
R7. The system must support multi-tenant claims.
R12. The system must produce a helper constraint.

## Design Narrative
Notes here.
EOF

cat > "$TEST_BASE/project/.spec/domains/data/F02-serializer.md" << 'EOF'
---
{
  "id": "F02",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["data"]
}
---

# F02 — Serializer Contract

## Requirements

R1. The system must serialize records.
R4. The system must enforce shared serialization constraint.
R8. The system must compress records over 4KB. (uncovered)
EOF

cat > "$TEST_BASE/project/.spec/registry/manifest.json" << 'EOF'
{
  "schema_version": 2,
  "specs": [
    { "id": "F01", "path": ".spec/domains/auth/F01-jwt-token.md", "state": "APPROVED", "domains": ["auth"] },
    { "id": "F02", "path": ".spec/domains/data/F02-serializer.md", "state": "APPROVED", "domains": ["data"] }
  ]
}
EOF

# ── Test 14: --uncovered emits only R-ids absent from annotations ───────────

output_uncov=$(cd "$TEST_BASE/project" && bash "$TRACE_SCRIPT" --uncovered F01 2>/dev/null)
if [[ "$output_uncov" == "F01.R5" ]]; then
    pass "--uncovered F01 emits exactly the unannotated R-id (F01.R5)"
else
    fail "--uncovered should emit only F01.R5" "got: '$output_uncov'"
fi

# ── Test 15: --uncovered emits stderr summary with counts ───────────────────

stderr_uncov=$(cd "$TEST_BASE/project" && bash "$TRACE_SCRIPT" --uncovered F01 2>&1 >/dev/null)
if echo "$stderr_uncov" | grep -qE 'F01:.*5 requirement.*defined.*4 annotated.*1 uncovered'; then
    pass "--uncovered stderr summary reports defined/annotated/uncovered counts"
else
    fail "stderr summary should report 5 defined / 4 annotated / 1 uncovered" "got: $stderr_uncov"
fi

# ── Test 16: --uncovered handles a spec with multiple uncovered R-ids ───────

# Annotate only F02.R1 and F02.R4 in the fixture (R8 left uncovered) and verify.
output_uncov_f02=$(cd "$TEST_BASE/project" && bash "$TRACE_SCRIPT" --uncovered F02 2>/dev/null)
if [[ "$output_uncov_f02" == "F02.R8" ]]; then
    pass "--uncovered F02 emits only F02.R8 (R1 and R4 are annotated)"
else
    fail "--uncovered F02 should emit F02.R8" "got: '$output_uncov_f02'"
fi

# ── Test 17: --uncovered with no annotations emits all defined R-ids ────────

# Add a spec with NO annotations anywhere.
cat > "$TEST_BASE/project/.spec/domains/auth/F03-orphan.md" << 'EOF'
---
{
  "id": "F03",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["auth"]
}
---

# F03 — Orphan spec

## Requirements

R1. First.
R2. Second.
R3. Third.
EOF

# Update manifest
cat > "$TEST_BASE/project/.spec/registry/manifest.json" << 'EOF'
{
  "schema_version": 2,
  "specs": [
    { "id": "F01", "path": ".spec/domains/auth/F01-jwt-token.md", "state": "APPROVED", "domains": ["auth"] },
    { "id": "F02", "path": ".spec/domains/data/F02-serializer.md", "state": "APPROVED", "domains": ["data"] },
    { "id": "F03", "path": ".spec/domains/auth/F03-orphan.md", "state": "APPROVED", "domains": ["auth"] }
  ]
}
EOF

output_orphan=$(cd "$TEST_BASE/project" && bash "$TRACE_SCRIPT" --uncovered F03 2>/dev/null | sort)
expected_orphan=$'F03.R1\nF03.R2\nF03.R3'
if [[ "$output_orphan" == "$expected_orphan" ]]; then
    pass "--uncovered emits all R-ids when none are annotated"
else
    fail "--uncovered F03 should emit all three R-ids" "got: '$output_orphan'"
fi

# ── Test 18: --uncovered for domain.slug spec resolves via manifest ─────────

mkdir -p "$TEST_BASE/project/.spec/domains/auth/token"
cat > "$TEST_BASE/project/.spec/domains/auth/token/validation.md" << 'EOF'
---
{
  "id": "auth.token.validation",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["auth"]
}
---

# auth.token.validation

## Requirements

R1. Validate signature.
R2. Reject expired tokens.
EOF

cat > "$TEST_BASE/project/.spec/registry/manifest.json" << 'EOF'
{
  "schema_version": 2,
  "specs": [
    { "id": "F01", "path": ".spec/domains/auth/F01-jwt-token.md", "state": "APPROVED", "domains": ["auth"] },
    { "id": "F02", "path": ".spec/domains/data/F02-serializer.md", "state": "APPROVED", "domains": ["data"] },
    { "id": "F03", "path": ".spec/domains/auth/F03-orphan.md", "state": "APPROVED", "domains": ["auth"] },
    { "id": "auth.token.validation", "path": ".spec/domains/auth/token/validation.md", "state": "APPROVED", "domains": ["auth"] }
  ]
}
EOF

output_dom=$(cd "$TEST_BASE/project" && bash "$TRACE_SCRIPT" --uncovered auth.token.validation 2>/dev/null | sort)
expected_dom=$'auth.token.validation.R1\nauth.token.validation.R2'
if [[ "$output_dom" == "$expected_dom" ]]; then
    pass "--uncovered resolves domain.slug spec via manifest"
else
    fail "--uncovered auth.token.validation should emit R1 and R2" "got: '$output_dom'"
fi

# ── Test 19: --uncovered with letter-suffixed and sub-numbered R-ids ────────

cat > "$TEST_BASE/project/.spec/domains/auth/F04-suffixed.md" << 'EOF'
---
{
  "id": "F04",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["auth"]
}
---

# F04 — Suffixed requirements

## Requirements

R1. Plain.
R2a. Letter-suffixed.
R2b. Letter-suffixed.
R5-1. Sub-numbered.
R5-1a. Sub-numbered with letter.
EOF

cat > "$TEST_BASE/project/.spec/registry/manifest.json" << 'EOF'
{
  "schema_version": 2,
  "specs": [
    { "id": "F01", "path": ".spec/domains/auth/F01-jwt-token.md", "state": "APPROVED", "domains": ["auth"] },
    { "id": "F02", "path": ".spec/domains/data/F02-serializer.md", "state": "APPROVED", "domains": ["data"] },
    { "id": "F03", "path": ".spec/domains/auth/F03-orphan.md", "state": "APPROVED", "domains": ["auth"] },
    { "id": "auth.token.validation", "path": ".spec/domains/auth/token/validation.md", "state": "APPROVED", "domains": ["auth"] },
    { "id": "F04", "path": ".spec/domains/auth/F04-suffixed.md", "state": "APPROVED", "domains": ["auth"] }
  ]
}
EOF

output_sfx=$(cd "$TEST_BASE/project" && bash "$TRACE_SCRIPT" --uncovered F04 2>/dev/null | sort)
expected_sfx=$'F04.R1\nF04.R2a\nF04.R2b\nF04.R5-1\nF04.R5-1a'
if [[ "$output_sfx" == "$expected_sfx" ]]; then
    pass "--uncovered handles letter-suffixed and sub-numbered R-ids"
else
    fail "--uncovered should emit all suffixed R-ids" "got: '$output_sfx'"
fi

# ── Test 20: --uncovered with no manifest fails cleanly ─────────────────────

# Need a src/ dir so spec-trace passes the auto-detect dir check before
# reaching the manifest resolution step we're testing here.
mkdir -p "$TEST_BASE/no-manifest/.git"
mkdir -p "$TEST_BASE/no-manifest/src"
echo '// noop' > "$TEST_BASE/no-manifest/src/dummy.java"
cd "$TEST_BASE/no-manifest"
output_nm=$(bash "$TRACE_SCRIPT" --uncovered F01 2>&1 || true)
cd "$TEST_BASE/project"
if echo "$output_nm" | grep -q "Could not resolve spec file"; then
    pass "--uncovered without manifest fails with clear error"
else
    fail "--uncovered should error when manifest is missing" "got: $output_nm"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "Results: $passed passed, $failed failed, $total total"

if [[ $failed -gt 0 ]]; then
    exit 1
fi
