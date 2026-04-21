#!/usr/bin/env bash
# Scenario: curate-scan drift-detection analyses
#
# Exercises the two drift-detection analyses added to /curate:
#   Analysis 18 — Missing @spec annotation coverage
#   Analysis 19 — Aging open_obligations
#
# Run from repo root: bash tests/scenario-curate-drift.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-curate-drift"

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

if ! command -v jq >/dev/null 2>&1; then
    echo "scenario: curate-scan drift detection"
    echo "────────────────────────────────────────────────"
    echo "  SKIP  jq not available"
    exit 0
fi

echo ""
echo "scenario: curate-scan drift detection"
echo "────────────────────────────────────────────────"

# ── Analysis 18 setup ───────────────────────────────────────────────────────
# Create a project with an APPROVED spec and partial @spec annotations:
#   - Spec schema.field-access has R1, R2, R3
#   - R1 has BOTH impl and test annotations        → no gap
#   - R2 has ONLY impl annotation                  → TEST_GAP
#   - R3 has ONLY test annotation                  → IMPL_GAP

PROJECT="$TEST_BASE/project-annotations"
mkdir -p "$PROJECT/.claude/scripts" "$PROJECT/src/schema" "$PROJECT/tests/schema"
mkdir -p "$PROJECT/.spec/registry" "$PROJECT/.spec/domains/schema"

cp "$REPO_ROOT/scripts/curate-scan.sh" "$PROJECT/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-trace.sh" "$PROJECT/.claude/scripts/"
chmod +x "$PROJECT/.claude/scripts/spec-trace.sh"

# Registry manifest (v2 schema — specs[])
cat > "$PROJECT/.spec/registry/manifest.json" << 'REGEOF'
{
  "schema_version": 2,
  "generated_at": "2026-04-21",
  "spec_count": 2,
  "specs": [
    {
      "id": "schema.field-access",
      "path": ".spec/domains/schema/field-access.md",
      "state": "APPROVED",
      "domains": ["schema"]
    },
    {
      "id": "schema.unannotated",
      "path": ".spec/domains/schema/unannotated.md",
      "state": "APPROVED",
      "domains": ["schema"]
    }
  ]
}
REGEOF

cat > "$PROJECT/.spec/domains/schema/field-access.md" << 'SPECEOF'
---
{
  "id": "schema.field-access",
  "version": 1,
  "state": "APPROVED",
  "domains": ["schema"],
  "open_obligations": []
}
---

# schema.field-access — Field Access

## Requirements
R1. First requirement.
R2. Second requirement.
R3. Third requirement.
SPECEOF

cat > "$PROJECT/.spec/domains/schema/unannotated.md" << 'SPECEOF'
---
{
  "id": "schema.unannotated",
  "version": 1,
  "state": "APPROVED",
  "domains": ["schema"],
  "open_obligations": []
}
---

# schema.unannotated — No Annotations Anywhere

## Requirements
R1. A requirement with no code references.
SPECEOF

# Implementation: R1 and R2 annotated, R3 not.
cat > "$PROJECT/src/schema/Fields.java" << 'JAVA'
package com.example.schema;
public class Fields {
    // @spec schema.field-access.R1
    public void first() {}

    // @spec schema.field-access.R2
    public void second() {}

    // R3 intentionally unannotated on impl side
    public void third() {}
}
JAVA

# Tests: R1 and R3 annotated, R2 not.
cat > "$PROJECT/tests/schema/FieldsTest.java" << 'JAVA'
package com.example.schema;
public class FieldsTest {
    // @spec schema.field-access.R1
    public void testFirst() {}

    // R2 intentionally unannotated on test side

    // @spec schema.field-access.R3
    public void testThird() {}
}
JAVA

cd "$PROJECT"
git init -q --initial-branch=main .
git config user.email "test@test.com"
git config user.name "Test"
git add -A && git commit -q -m "init with partial annotations"

output="$(bash .claude/scripts/curate-scan.sh --init 2>&1)"

# ── Test: Annotation gaps section appears ────────────────────────────────────
if grep -q "Spec Annotation Coverage Gaps" .curate/scan-summary.md; then
    pass "annotation gaps section present"
else
    fail "annotation gaps section should appear" "output: $output"
fi

# ── Test: R2 surfaces as TEST_GAP ────────────────────────────────────────────
gap_section="$(sed -n '/## Spec Annotation Coverage Gaps/,/^## /p' .curate/scan-summary.md)"
if echo "$gap_section" | grep -q "impl-only → missing test annotation"; then
    pass "TEST_GAP row present (impl-only → missing test)"
else
    fail "should show impl-only gap for R2" "section: $gap_section"
fi

if echo "$gap_section" | grep -q "schema.field-access" \
   && echo "$gap_section" | grep -q "R2"; then
    pass "R2 identified as test-side gap"
else
    fail "R2 should be reported as missing test annotation" "section: $gap_section"
fi

# ── Test: R3 surfaces as IMPL_GAP ────────────────────────────────────────────
if echo "$gap_section" | grep -q "test-only → missing impl annotation"; then
    pass "IMPL_GAP row present (test-only → missing impl)"
else
    fail "should show test-only gap for R3" "section: $gap_section"
fi

if echo "$gap_section" | grep -q "R3"; then
    pass "R3 identified as impl-side gap"
else
    fail "R3 should be reported as missing impl annotation" "section: $gap_section"
fi

# ── Test: Requirement count column is accurate ──────────────────────────────
# Each of the two rows should list count 1 (R2 for test gap; R3 for impl gap).
count_rows="$(echo "$gap_section" | grep -E '^\| schema\.field-access' || true)"
# Extract the 4th pipe-delimited column (count) — columns: | spec | gap | count | reqs |
count_ok=1
while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    col_count="$(echo "$row" | awk -F'|' '{gsub(/ /, "", $4); print $4}')"
    if [[ "$col_count" != "1" ]]; then
        count_ok=0
    fi
done <<< "$count_rows"
if (( count_ok == 1 )); then
    pass "requirement count column is 1 for each single-req gap"
else
    fail "gap rows should report count=1 for single-req gaps" "rows: $count_rows"
fi

# ── Test: R1 is NOT in any gap row ───────────────────────────────────────────
# R1 has both impl + test annotations, so it must not appear in either gap list.
# Grep for "R1\b" in the gap table rows — should be absent.
gap_rows="$(echo "$gap_section" | grep -E '^\| schema\.field-access' || true)"
if echo "$gap_rows" | grep -qE '\bR1\b'; then
    fail "R1 should not appear in any gap row (has both impl+test)" "rows: $gap_rows"
else
    pass "R1 correctly absent from gap rows"
fi

# ── Test: Unannotated-spec section appears ──────────────────────────────────
if echo "$gap_section" | grep -q "APPROVED specs with no annotations at all"; then
    pass "unannotated-spec subsection present"
else
    fail "should list schema.unannotated as fully unannotated" "section: $gap_section"
fi

if echo "$gap_section" | grep -q "schema.unannotated"; then
    pass "schema.unannotated flagged as having no annotations"
else
    fail "schema.unannotated should appear as fully unannotated" "section: $gap_section"
fi

# ── Test: Stats line includes annotation-gap count ──────────────────────────
if echo "$output" | grep -q "Spec annotation gaps:"; then
    pass "stats output includes annotation gaps count"
else
    fail "stats should report annotation gaps count" "output: $output"
fi

if echo "$output" | grep -q "Unannotated APPROVED specs:"; then
    pass "stats output includes unannotated-spec count"
else
    fail "stats should report unannotated specs count" "output: $output"
fi

# ── Test: --max-specs-traced flag honored ──────────────────────────────────
# With --max-specs-traced 1, only one spec is traced. The order depends on
# how jq iterates the specs array — either schema.field-access OR
# schema.unannotated is traced, but not both. We assert at least one section
# has fewer findings than the full run.
output_capped="$(bash .claude/scripts/curate-scan.sh --init --max-specs-traced 1 2>&1)"
capped_section="$(sed -n '/## Spec Annotation Coverage Gaps/,/^## /p' .curate/scan-summary.md)"

# Count gap-table rows (lines starting with | schema.)
full_rows=$(echo "$gap_section" | grep -cE '^\| schema\.' || true)
capped_rows=$(echo "$capped_section" | grep -cE '^\| schema\.' || true)

# Either the row count dropped, OR the unannotated-spec block is shorter.
full_unann=$(echo "$gap_section" | grep -cE '^- schema\.' || true)
capped_unann=$(echo "$capped_section" | grep -cE '^- schema\.' || true)

# With only 1 spec traced we must have at most 1 spec's findings total.
distinct_specs=$(echo "$capped_section" | grep -oE 'schema\.[a-z-]+' | sort -u | wc -l)
if (( distinct_specs <= 1 )); then
    pass "--max-specs-traced 1 limits trace to one spec"
else
    fail "--max-specs-traced 1 should cap at one spec" "distinct: $distinct_specs; full=$full_rows/$full_unann capped=$capped_rows/$capped_unann"
fi

cd "$REPO_ROOT"

# ── Analysis 19 setup ───────────────────────────────────────────────────────
# Create a project with three specs:
#   - spec-a has 2 open obligations AND was committed 60 days ago       → flagged
#   - spec-b has 1 open obligation AND was committed today               → not flagged
#   - spec-c has empty open_obligations                                  → not flagged

OB_PROJECT="$TEST_BASE/project-obligations"
mkdir -p "$OB_PROJECT/.claude/scripts"
mkdir -p "$OB_PROJECT/.spec/registry" "$OB_PROJECT/.spec/domains/widgets"

cp "$REPO_ROOT/scripts/curate-scan.sh" "$OB_PROJECT/.claude/scripts/"

cat > "$OB_PROJECT/.spec/registry/manifest.json" << 'REGEOF'
{
  "schema_version": 2,
  "generated_at": "2026-04-21",
  "spec_count": 3,
  "specs": [
    {"id": "widgets.spec-a", "path": ".spec/domains/widgets/spec-a.md", "state": "APPROVED", "domains": ["widgets"]},
    {"id": "widgets.spec-b", "path": ".spec/domains/widgets/spec-b.md", "state": "APPROVED", "domains": ["widgets"]},
    {"id": "widgets.spec-c", "path": ".spec/domains/widgets/spec-c.md", "state": "APPROVED", "domains": ["widgets"]}
  ]
}
REGEOF

# spec-a: two open obligations, one string-shaped, one object-shaped with a "text" field
cat > "$OB_PROJECT/.spec/domains/widgets/spec-a.md" << 'SPECEOF'
---
{
  "id": "widgets.spec-a",
  "version": 1,
  "state": "APPROVED",
  "domains": ["widgets"],
  "open_obligations": [
    "Need a decision on retention policy",
    {"id": "OBL-A2", "text": "Concurrent access strategy not specified"}
  ]
}
---

# widgets.spec-a — Widget A

## Requirements
R1. Widgets must exist.
SPECEOF

# spec-b: one open obligation, will be "fresh" (committed today)
cat > "$OB_PROJECT/.spec/domains/widgets/spec-b.md" << 'SPECEOF'
---
{
  "id": "widgets.spec-b",
  "version": 1,
  "state": "APPROVED",
  "domains": ["widgets"],
  "open_obligations": ["Recent obligation that is not stale"]
}
---

# widgets.spec-b — Widget B

## Requirements
R1. Widgets must support B behavior.
SPECEOF

# spec-c: empty obligations
cat > "$OB_PROJECT/.spec/domains/widgets/spec-c.md" << 'SPECEOF'
---
{
  "id": "widgets.spec-c",
  "version": 1,
  "state": "APPROVED",
  "domains": ["widgets"],
  "open_obligations": []
}
---

# widgets.spec-c — Widget C

## Requirements
R1. No obligations.
SPECEOF

cd "$OB_PROJECT"
git init -q --initial-branch=main .
git config user.email "test@test.com"
git config user.name "Test"

# Commit spec-a and spec-c with a 60-day-old timestamp to make spec-a "aged".
OLD_DATE="$(date -d '60 days ago' '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -v-60d '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)"
git add .spec/registry/manifest.json .spec/domains/widgets/spec-a.md .spec/domains/widgets/spec-c.md
GIT_AUTHOR_DATE="$OLD_DATE" GIT_COMMITTER_DATE="$OLD_DATE" git commit -q -m "add aged specs"

# Commit spec-b now (fresh).
git add .spec/domains/widgets/spec-b.md
git commit -q -m "add fresh spec-b"

output="$(bash .claude/scripts/curate-scan.sh --init 2>&1)"

# ── Test: Aging Open Obligations section appears ───────────────────────────
if grep -q "Aging Open Obligations" .curate/scan-summary.md; then
    pass "aging obligations section present"
else
    fail "aging obligations section should appear" "output: $output"
fi

aging_section="$(sed -n '/## Aging Open Obligations/,/^## /p' .curate/scan-summary.md)"

# ── Test: spec-a's obligations both surface ────────────────────────────────
if echo "$aging_section" | grep -q "widgets.spec-a"; then
    pass "aged spec-a obligation surfaced"
else
    fail "widgets.spec-a obligations should be aged" "section: $aging_section"
fi

# Both obligations emitted — string-shaped AND object-shaped
if echo "$aging_section" | grep -q "retention policy"; then
    pass "string-shaped obligation text extracted"
else
    fail "string obligation 'retention policy' should appear" "section: $aging_section"
fi

if echo "$aging_section" | grep -q "Concurrent access strategy"; then
    pass "object-shaped obligation .text field extracted"
else
    fail "object obligation text should appear" "section: $aging_section"
fi

# ── Test: spec-b (fresh) does NOT appear ────────────────────────────────────
if echo "$aging_section" | grep -q "widgets.spec-b"; then
    fail "fresh spec-b should not be flagged as aging"
else
    pass "fresh spec-b correctly excluded"
fi

# ── Test: spec-c (empty obligations) does NOT appear ───────────────────────
if echo "$aging_section" | grep -q "widgets.spec-c"; then
    fail "spec-c has no obligations and should not appear"
else
    pass "spec-c with empty obligations correctly excluded"
fi

# ── Test: --obligation-age-days 90 drops spec-a ────────────────────────────
# With threshold 90, 60-day-old spec-a should NOT be flagged.
bash .claude/scripts/curate-scan.sh --init --obligation-age-days 90 >/dev/null 2>&1
aging_section_90="$(sed -n '/## Aging Open Obligations/,/^## /p' .curate/scan-summary.md 2>/dev/null || true)"
if [[ -z "$aging_section_90" ]] || ! echo "$aging_section_90" | grep -q "widgets.spec-a"; then
    pass "--obligation-age-days 90 drops 60-day-old spec-a"
else
    fail "threshold 90 should exclude 60-day-old obligations" "section: $aging_section_90"
fi

# ── Test: --obligation-age-days 10 keeps spec-a AND spec-b  ─────────────────
# With threshold 10, spec-b is still fresh (0 days old) — not included.
# But spec-a (60 days) is definitely included.
bash .claude/scripts/curate-scan.sh --init --obligation-age-days 10 >/dev/null 2>&1
aging_section_10="$(sed -n '/## Aging Open Obligations/,/^## /p' .curate/scan-summary.md)"
if echo "$aging_section_10" | grep -q "widgets.spec-a"; then
    pass "--obligation-age-days 10 includes spec-a"
else
    fail "threshold 10 should include spec-a" "section: $aging_section_10"
fi

# ── Test: Age column is numeric ─────────────────────────────────────────────
bash .claude/scripts/curate-scan.sh --init >/dev/null 2>&1
aging_section="$(sed -n '/## Aging Open Obligations/,/^## /p' .curate/scan-summary.md)"
# The table has 3 columns: | spec | age | obligation |
# Extract the age column (col 3 when split by |) from spec-a's row.
age_col="$(echo "$aging_section" | grep 'widgets.spec-a' | head -1 | awk -F'|' '{print $3}' | tr -d ' ')"
if [[ "$age_col" =~ ^[0-9]+$ ]] && (( age_col >= 59 )) && (( age_col <= 61 )); then
    pass "age column reports ~60 days (got: $age_col)"
else
    fail "age column should be ~60 (got: '$age_col')"
fi

# ── Test: Stats line includes aging-obligations count ──────────────────────
if echo "$output" | grep -q "Aging obligations:"; then
    pass "stats output includes aging obligations count"
else
    fail "stats should report aging obligations count" "output: $output"
fi

cd "$REPO_ROOT"

# ── v1 manifest schema backwards compatibility ─────────────────────────────
# Analysis 18 must also work with the legacy v1 (features: {}) manifest.

V1_PROJECT="$TEST_BASE/project-v1-manifest"
mkdir -p "$V1_PROJECT/.claude/scripts" "$V1_PROJECT/src"
mkdir -p "$V1_PROJECT/.spec/registry" "$V1_PROJECT/.spec/domains/legacy"

cp "$REPO_ROOT/scripts/curate-scan.sh" "$V1_PROJECT/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-trace.sh" "$V1_PROJECT/.claude/scripts/"
chmod +x "$V1_PROJECT/.claude/scripts/spec-trace.sh"

cat > "$V1_PROJECT/.spec/registry/manifest.json" << 'REGEOF'
{
  "features": {
    "F01": {"latest_file": "domains/legacy/F01-legacy.md", "state": "APPROVED", "domains": ["legacy"]}
  }
}
REGEOF

cat > "$V1_PROJECT/.spec/domains/legacy/F01-legacy.md" << 'SPECEOF'
---
{
  "id": "F01",
  "state": "APPROVED",
  "open_obligations": []
}
---

# F01 — Legacy

## Requirements
R1. Legacy requirement.
R2. Another requirement.
SPECEOF

# Implementation annotates R1 only → R2 is impl-only? No — it's neither.
# Actually: annotate R1 on impl only → R1 is a TEST_GAP.
# Annotate R2 nowhere → R2 does not appear in trace (no annotations to key off of).
cat > "$V1_PROJECT/src/Legacy.java" << 'JAVA'
// @spec F01.R1
public class Legacy {}
JAVA

cd "$V1_PROJECT"
git init -q --initial-branch=main .
git config user.email "test@test.com"
git config user.name "Test"
git add -A && git commit -q -m "v1 manifest spec"

output="$(bash .claude/scripts/curate-scan.sh --init 2>&1)"

if grep -q "Spec Annotation Coverage Gaps" .curate/scan-summary.md; then
    pass "v1 manifest: annotation section present"
else
    fail "v1 manifest: annotation section should appear" "output: $output"
fi

gap_section="$(sed -n '/## Spec Annotation Coverage Gaps/,/^## /p' .curate/scan-summary.md)"
if echo "$gap_section" | grep -q "F01"; then
    pass "v1 manifest: FXX-style IDs work"
else
    fail "v1 manifest: F01 should be traced" "section: $gap_section"
fi

cd "$REPO_ROOT"

# ── No-op conditions: no spec registry ─────────────────────────────────────
# Analysis 18/19 must skip silently when .spec/ doesn't exist.

NO_SPEC="$TEST_BASE/project-no-spec"
mkdir -p "$NO_SPEC/.claude/scripts"
cp "$REPO_ROOT/scripts/curate-scan.sh" "$NO_SPEC/.claude/scripts/"

cd "$NO_SPEC"
git init -q --initial-branch=main .
git config user.email "test@test.com"
git config user.name "Test"
echo "hello" > README.md
git add -A && git commit -q -m "init"

output="$(bash .claude/scripts/curate-scan.sh --init 2>&1)"
if echo "$output" | grep -q "Scan complete"; then
    pass "scan completes when .spec/ is absent"
else
    fail "scan should complete without .spec/" "output: $output"
fi

if grep -q "Spec Annotation Coverage Gaps" .curate/scan-summary.md; then
    fail "annotation section should NOT appear without .spec/"
else
    pass "annotation section correctly absent without .spec/"
fi

if grep -q "Aging Open Obligations" .curate/scan-summary.md; then
    fail "aging obligations section should NOT appear without .spec/"
else
    pass "aging obligations section correctly absent without .spec/"
fi

cd "$REPO_ROOT"

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
