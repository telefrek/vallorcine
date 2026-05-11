#!/usr/bin/env bash
# Scenario: /curate + curate-scan.sh HIGH fixes from 2026-05-11
# adversarial sweep.
#
# H1: Step 4 no longer duplicates Step 0's stuck-marker recovery.
# H2: Analysis 29 drops -maxdepth 2 (handles nested ADR layouts).
# H3: MAX_SPECS_TRACED=0 writes an explicit "skipped" section so the
#     omission is a positive signal, not a silent gap.
# H4: has_bare_annotations uses a one-time index file (no per-spec
#     recursive grep over the whole source tree).
#
# Run from repo root: bash tests/scenario-curate-high-cluster.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SCAN="$REPO_ROOT/scripts/curate-scan.sh"
SKILL="$REPO_ROOT/skills/curate/SKILL.md"

passed=0; failed=0; total=0
pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }

echo ""
echo "scenario: /curate + curate-scan.sh HIGH cluster"
echo "────────────────────────────────────────────────"

# ── H1: Step 4 doesn't duplicate stuck-marker recovery ─────────────────────

echo ""
echo "  H1 — Step 4 no longer duplicates Step 0 stuck-marker recovery"
echo "  ─────────────────────────────────────────────────────────"

step4=$(awk '/^### Step 4 dispatch protocol/,/^## Step 5/' "$SKILL")

if echo "$step4" | grep -qE 'Stuck-marker recovery already happened in Step 0'; then
    pass "Step 4 explicitly references Step 0's single recovery point"
else
    fail "Step 4 doesn't acknowledge Step 0 handles stuck markers"
fi

# Step 4 must NOT call `dispatch-marker.sh stuck` again (that was the duplicate).
if echo "$step4" | grep -qE 'dispatch-marker\.sh stuck \.curate/_dispatches'; then
    fail "Step 4 still re-runs dispatch-marker.sh stuck (duplicates Step 0)"
else
    pass "Step 4 doesn't re-run dispatch-marker.sh stuck"
fi

# Step 0 still has the stuck-marker pre-flight (the canonical recovery point).
step0=$(awk '/^## Step 0 — Pre-flight/,/^## Step 0\.5/' "$SKILL")
if echo "$step0" | grep -qE 'dispatch-marker\.sh stuck'; then
    pass "Step 0 retains the canonical stuck-marker recovery"
else
    fail "Step 0 missing stuck-marker recovery (would lose feature entirely)"
fi

# ── H2: Analysis 29 walks nested ADR layouts ───────────────────────────────

echo ""
echo "  H2 — Analysis 29 drops -maxdepth 2 (handles nested ADRs)"
echo "  ──────────────────────────────────────────────────────"

# Find the Analysis 29 find invocation
a29=$(awk '/^# ── Analysis 29:/,/rm -f.*_adr-referenced\.txt/' "$SCAN")

if echo "$a29" | grep -qE 'find \.decisions -mindepth 2 -type f -name .adr\.md'; then
    pass "Analysis 29 uses -mindepth 2 with no -maxdepth (handles nested)"
else
    fail "Analysis 29 not using the corrected find invocation"
fi

if echo "$a29" | grep -qE '\-mindepth 2 -maxdepth 2'; then
    fail "Analysis 29 still has the -maxdepth 2 restriction"
else
    pass "Analysis 29 no longer has -maxdepth 2 restriction"
fi

# The slug derivation must use the relative path (not just basename),
# so `.decisions/area/slug/adr.md` → `area/slug`.
if echo "$a29" | grep -qE 'slug.*\.decisions/'; then
    pass "Analysis 29 derives slug from path-relative location"
else
    fail "Analysis 29 still uses basename-only slug"
fi

# ── H3: MAX_SPECS_TRACED=0 writes explicit "skipped" section ───────────────

echo ""
echo "  H3 — MAX_SPECS_TRACED=0 writes explicit Skipped rollup section"
echo "  ─────────────────────────────────────────────────────────────"

# Set up a tiny project and run with --max-specs-traced 0.
TEST_DIR="/tmp/vallorcine/scenario-curate-max0"
rm -rf "$TEST_DIR" 2>/dev/null || true
mkdir -p "$TEST_DIR/.claude/scripts" "$TEST_DIR/.spec/registry" "$TEST_DIR/.spec/domains" "$TEST_DIR/.curate"
cp "$SCAN" "$TEST_DIR/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$TEST_DIR/.claude/scripts/" 2>/dev/null || true

# Minimal git fixture so the scan doesn't bail.
cd "$TEST_DIR"
git init -q
git config user.email t@t.t
git config user.name t
echo "hello" > foo.txt
git add -A
git commit -q -m "init"

# Manifest with one APPROVED spec (so the analysis WOULD have something to skip).
cat > .spec/registry/manifest.json <<'EOF'
{
  "schema_version": 2,
  "specs": [
    {"id": "test.example", "state": "APPROVED"}
  ]
}
EOF

# Run with --max-specs-traced 0
bash .claude/scripts/curate-scan.sh --init --max-specs-traced 0 >/dev/null 2>&1

if [[ -f .curate/scan-summary.md ]]; then
    if grep -q "^## Spec Annotation Coverage Rollup" .curate/scan-summary.md \
       && grep -qE "Skipped this run.*max-specs-traced 0" .curate/scan-summary.md; then
        pass "MAX_SPECS_TRACED=0 writes explicit Skipped rollup section"
    else
        fail "no 'Skipped this run' marker for max-specs-traced=0" \
             "$(grep -A2 'Annotation Coverage Rollup' .curate/scan-summary.md || echo '<missing>')"
    fi
else
    fail "scan-summary.md not created"
fi

cd "$REPO_ROOT"
rm -rf "$TEST_DIR" 2>/dev/null || true

# ── H4: has_bare_annotations uses one-time index ───────────────────────────

echo ""
echo "  H4 — has_bare_annotations uses one-time index (no per-spec walk)"
echo "  ──────────────────────────────────────────────────────────────"

# The script must define SPEC_REFS_INDEX and pre-build it once.
if grep -qE 'SPEC_REFS_INDEX=' "$SCAN"; then
    pass "SPEC_REFS_INDEX variable declared (one-time index path)"
else
    fail "SPEC_REFS_INDEX variable missing — per-spec walks still in place"
fi

# The pre-built grep MUST be outside the spec loop (one call before
# the `while IFS= read -r sid` enumeration).
# Verify by checking the line ordering.
index_build_line=$(grep -nE 'grep -rhoE .@spec ' "$SCAN" | head -1 | cut -d: -f1)
spec_loop_line=$(grep -nE 'while IFS= read -r sid; do' "$SCAN" | head -1 | cut -d: -f1)
if [[ -n "$index_build_line" && -n "$spec_loop_line" && "$index_build_line" -lt "$spec_loop_line" ]]; then
    pass "index pre-built BEFORE the per-spec loop (line $index_build_line < $spec_loop_line)"
else
    fail "index build / loop ordering wrong (or grep pattern not found)"
fi

# has_bare_annotations should NOT do a recursive grep itself.
hba_body=$(awk '/^has_bare_annotations\(\)/,/^}$/' "$SCAN")
if echo "$hba_body" | grep -qE 'grep -rqE.*@spec'; then
    fail "has_bare_annotations still does recursive grep per call"
else
    pass "has_bare_annotations no longer does recursive grep per call"
fi

# has_bare_annotations should reference the SPEC_REFS_INDEX file
if echo "$hba_body" | grep -qE 'SPEC_REFS_INDEX'; then
    pass "has_bare_annotations checks against SPEC_REFS_INDEX"
else
    fail "has_bare_annotations doesn't reference the index file"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "Total: $total | Passed: $passed | Failed: $failed"
echo ""

[[ $failed -eq 0 ]] && exit 0 || exit 1
