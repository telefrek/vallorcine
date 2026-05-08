#!/usr/bin/env bash
# Scenario: spec-coverage.sh init / update / gate / waive lifecycle.
#
# Verifies the orchestrator that backs the spec-annotation enforcement
# protocol introduced 2026-05-04. Tests are written first (the regression
# rule) and must pass once spec-coverage.sh and the enforcement skills
# land together.
#
# Run from repo root: bash tests/scenario-spec-coverage.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-spec-coverage"

passed=0
failed=0
total=0

pass() {
    ((passed++)) || true
    ((total++)) || true
    echo "  PASS  $1"
    return 0
}

fail() {
    ((failed++)) || true
    ((total++)) || true
    echo "  FAIL  $1"
    [[ -n "${2:-}" ]] && echo "        $2"
    return 0
}

cleanup() { rm -rf "$TEST_BASE" 2>/dev/null || true; }
trap cleanup EXIT

echo ""
echo "scenario: spec-coverage.sh init / update / gate / waive lifecycle"
echo "──────────────────────────────────────────────────────────────────"

cleanup
mkdir -p "$TEST_BASE/project/.spec/registry/" \
         "$TEST_BASE/project/.spec/domains/auth/" \
         "$TEST_BASE/project/.feature/sample/" \
         "$TEST_BASE/project/.claude/scripts/" \
         "$TEST_BASE/project/src/auth/" \
         "$TEST_BASE/project/tests/"

cp "$REPO_ROOT/scripts/spec-coverage.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-trace.sh"    "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh"      "$TEST_BASE/project/.claude/scripts/"

# Synthetic spec-resolve bundle (the input to `init`).
cat > "$TEST_BASE/project/.feature/sample/spec-bundle.md" <<'BUNDLE'
# Resolved Context Bundle
Generated: 2026-05-04T00:00:00Z
Feature request: sample
Domains matched: auth
Token budget: 25000 | Tokens used: ~1200
Omitted (budget): none

## Open Obligations (must be addressed in this feature)
none

## Feature Requirements

# auth.token-validation

## Requirements
R1. The TokenValidator must reject tokens older than 24h.
R2. The TokenValidator must reject malformed tokens.
R3. The TokenValidator must accept tokens within the validity window.

---

# auth.session-lifecycle

## Requirements
R1. The SessionStore must invalidate the session on logout.
R2. The SessionStore must auto-expire sessions after the inactivity threshold.

## Cross-References
none
BUNDLE

cd "$TEST_BASE/project"
COV=".feature/sample/spec-coverage.md"

# ── Test 1: init produces a table with one row per requirement ───────────────

echo ""
echo "── Test 1: init writes one row per (spec, R) pair, all rows pending"

bash .claude/scripts/spec-coverage.sh init "$COV" .feature/sample/spec-bundle.md 2>/dev/null
row_count=$(grep -cE '^\| auth\.[a-z\-]+ \| R[0-9]+' "$COV" || true)
if [[ "$row_count" == "5" ]]; then
    pass "5 rows written for 3+2 requirements across two specs"
else
    fail "expected 5 rows, got $row_count" "head: $(head -10 "$COV")"
fi

if grep -q "^| auth.token-validation | R1 | pending | pending |" "$COV" \
   && grep -q "^| auth.session-lifecycle | R2 | pending | pending |" "$COV"; then
    pass "both Test and Impl default to pending"
else
    fail "rows do not have Test=pending Impl=pending"
fi

# ── Test 2: gate fails before any annotations ────────────────────────────────

echo ""
echo "── Test 2: gate exits nonzero with a list of pending requirements"

if bash .claude/scripts/spec-coverage.sh gate "$COV" >/tmp/vallorcine/gate-out.txt 2>/dev/null; then
    fail "gate returned 0 with all rows pending"
else
    if grep -q "auth.token-validation.R1" /tmp/vallorcine/gate-out.txt \
       && grep -q "auth.session-lifecycle.R2" /tmp/vallorcine/gate-out.txt; then
        pass "gate output enumerates the pending requirements"
    else
        fail "gate output does not list pending rows" "$(cat /tmp/vallorcine/gate-out.txt)"
    fi
fi

# ── Test 3: update reflects test-side @spec annotations ──────────────────────

echo ""
echo "── Test 3: update detects @spec annotations in test files"

cat > tests/test_token_validator.py <<'PY'
# @spec auth.token-validation.R1
def test_rejects_old_tokens():
    pass

# @spec auth.token-validation.R2
def test_rejects_malformed_tokens():
    pass
PY

bash .claude/scripts/spec-coverage.sh update "$COV" --all 2>/dev/null

if grep -qE '^\| auth\.token-validation \| R1 \| tests/test_token_validator\.py:[0-9]+' "$COV"; then
    pass "R1 Test cell now points to tests/test_token_validator.py"
else
    fail "R1 Test cell did not update from annotation" \
         "$(grep token-validation "$COV")"
fi

if grep -qE '^\| auth\.token-validation \| R3 \| pending \| pending' "$COV"; then
    pass "R3 stays pending (no annotation written)"
else
    fail "R3 should still be pending" "$(grep R3 "$COV")"
fi

# ── Test 4: update detects @spec annotations in implementation files ─────────

echo ""
echo "── Test 4: update detects @spec annotations in impl files"

cat > src/auth/validator.py <<'PY'
# @spec auth.token-validation.R3
def accept_valid_token(token):
    return True
PY

bash .claude/scripts/spec-coverage.sh update "$COV" --all 2>/dev/null

if grep -qE '^\| auth\.token-validation \| R3 \| pending \| src/auth/validator\.py:[0-9]+' "$COV"; then
    pass "R3 Impl cell now points to src/auth/validator.py"
else
    fail "R3 Impl cell did not update" "$(grep token-validation "$COV")"
fi

# ── Test 5: gate still fails while session-lifecycle rows are pending ────────

echo ""
echo "── Test 5: gate still fails until every requirement is annotated or waived"

if bash .claude/scripts/spec-coverage.sh gate "$COV" >/tmp/vallorcine/gate-out2.txt 2>/dev/null; then
    fail "gate returned 0 with session-lifecycle rows still pending"
else
    if grep -q "auth.session-lifecycle.R1" /tmp/vallorcine/gate-out2.txt \
       && grep -q "auth.session-lifecycle.R2" /tmp/vallorcine/gate-out2.txt; then
        pass "gate enumerates only the still-pending session-lifecycle rows"
    else
        fail "gate did not list session-lifecycle pending rows" "$(cat /tmp/vallorcine/gate-out2.txt)"
    fi
fi

# ── Test 6: waive marks both Test and Impl cells with the reason ─────────────

echo ""
echo "── Test 6: waive records the reason on both Test and Impl cells"

bash .claude/scripts/spec-coverage.sh waive "$COV" auth.session-lifecycle.R1 \
    "covered via integration suite, see issue #99" 2>/dev/null

if grep -qE '^\| auth\.session-lifecycle \| R1 \| waived: covered via integration suite' "$COV"; then
    pass "waive applied to R1"
else
    fail "waive did not update R1 row" "$(grep session-lifecycle "$COV")"
fi

# ── Test 7: gate passes once everything is annotated or waived ───────────────

echo ""
echo "── Test 7: gate exits 0 when no rows are double-pending"

# Annotate the last remaining row (session-lifecycle.R2) in a test file.
cat > tests/test_session_lifecycle.py <<'PY'
# @spec auth.session-lifecycle.R2
def test_inactivity_expiry():
    pass
PY

bash .claude/scripts/spec-coverage.sh update "$COV" --all 2>/dev/null

if bash .claude/scripts/spec-coverage.sh gate "$COV" >/tmp/vallorcine/gate-out3.txt 2>/dev/null; then
    pass "gate exits 0 after every row is annotated or waived"
else
    fail "gate still failing despite full coverage" "$(cat /tmp/vallorcine/gate-out3.txt)"
fi

# ── Test 8: report counts match the table state ──────────────────────────────

echo ""
echo "── Test 8: report counts match the expected coverage state"

report_out=$(bash .claude/scripts/spec-coverage.sh report "$COV" 2>/dev/null)
if echo "$report_out" | grep -qE '5 loaded · 4 annotated · 1 waived · 0 pending'; then
    pass "report shows 5/4/1/0"
else
    fail "report counts wrong" "got: $report_out"
fi

# ── Test 9: init is idempotent and preserves prior cell values ───────────────

echo ""
echo "── Test 9: init preserves Test/Impl/Notes when re-run on existing coverage"

bash .claude/scripts/spec-coverage.sh init "$COV" .feature/sample/spec-bundle.md 2>/dev/null

# R1 was annotated by the test file in Test 3 — that should survive re-init.
if grep -qE '^\| auth\.token-validation \| R1 \| tests/test_token_validator\.py:[0-9]+' "$COV"; then
    pass "re-init preserved R1 Test cell"
else
    fail "re-init wiped R1 Test cell" "$(grep token-validation "$COV" | head -3)"
fi

if grep -qE '^\| auth\.session-lifecycle \| R1 \| waived:' "$COV"; then
    pass "re-init preserved waived row"
else
    fail "re-init wiped waiver" "$(grep session-lifecycle "$COV")"
fi

# ── Test 10: init on empty bundle writes the vacuous-coverage marker ─────────

echo ""
echo "── Test 10: empty bundle (no specs) produces a vacuous-coverage file"

cat > .feature/sample/empty-bundle.md <<'EMPTY'
# Resolved Context Bundle
Generated: 2026-05-04T00:00:00Z
Feature request: sample
Domains matched: nothing
Token budget: 25000 | Tokens used: ~0
Omitted (budget): none

## Feature Requirements

none
EMPTY

VACUOUS=".feature/sample/vacuous-coverage.md"
bash .claude/scripts/spec-coverage.sh init "$VACUOUS" .feature/sample/empty-bundle.md 2>/dev/null

if grep -q "^No specs loaded" "$VACUOUS"; then
    pass "vacuous coverage file written when bundle has no specs"
else
    fail "expected 'No specs loaded' marker" "$(cat "$VACUOUS")"
fi

if bash .claude/scripts/spec-coverage.sh gate "$VACUOUS" >/dev/null 2>&1; then
    pass "gate passes vacuously on empty coverage"
else
    fail "gate failed on vacuous coverage"
fi

# ── Test 11: init parses title-bearing spec section headers ─────────────────
# Regression: spec-coverage.sh init's awk regex was anchored as `^# <id>$`,
# but spec-resolve.sh's machine_section pass-through includes the spec
# file's own title line `# <id> — Title`. The anchored regex never
# matched, init emitted a vacuous-coverage file, and populated tables
# only appeared later when /spec-coverage update re-derived rows from
# spec-trace output. After this fix init must populate the table from a
# title-bearing bundle just like it does from the bare-id form.

echo ""
echo "── Test 11: init parses title-bearing `# <id> — Title` section headers"

mkdir -p .feature/title-bearing
cat > .feature/title-bearing/spec-bundle.md << 'BUNDLE'
# Resolved Context Bundle
Generated: 2026-05-07T00:00:00Z

## Feature Requirements

# auth.token-validation — JWT Token Validation Contract

## Requirements
R1. The TokenValidator must reject expired tokens.
R2. The TokenValidator must reject malformed tokens.

---

# auth.session-lifecycle — Session Lifecycle (revision 3)

## Requirements
R1. The SessionStore must invalidate on logout.
R2. The SessionStore must auto-expire on inactivity.

## Cross-References
none
BUNDLE

COV_TITLE=".feature/title-bearing/spec-coverage.md"
bash .claude/scripts/spec-coverage.sh init "$COV_TITLE" .feature/title-bearing/spec-bundle.md 2>/dev/null

# Should NOT fall into the vacuous-coverage branch
if grep -q '^No specs loaded' "$COV_TITLE"; then
    fail "title-bearing bundle was misclassified as empty (regex still anchored?)"
else
    pass "title-bearing bundle did NOT trigger vacuous-coverage path"
fi

# Should populate one row per (spec, R)
row_count=$(grep -cE '^\| auth\.[a-z\-]+ \| R[0-9]+' "$COV_TITLE" || true)
if [[ "$row_count" == "4" ]]; then
    pass "4 rows written from title-bearing bundle (2 specs × 2 reqs)"
else
    fail "expected 4 rows, got $row_count" "head: $(head -10 "$COV_TITLE")"
fi

# Spec ID column must be the bare ID, NOT the title-bearing form. If the
# extraction failed to truncate at the first whitespace, the ID column
# would contain the appended title.
if grep -q '— JWT' "$COV_TITLE" || grep -q '— Session' "$COV_TITLE"; then
    fail "spec ID column captured the title — extraction did not truncate at whitespace" \
         "got: $(grep '^|' "$COV_TITLE" | head -3)"
else
    pass "spec ID column is bare (title not leaked into the ID column)"
fi

# Bare-ID form must still work — backwards compatibility for older bundles.
mkdir -p .feature/bare-id
cat > .feature/bare-id/spec-bundle.md << 'BUNDLE'
# Resolved Context Bundle

## Feature Requirements

# auth.bare-token

## Requirements
R1. Just one requirement.
BUNDLE

COV_BARE=".feature/bare-id/spec-coverage.md"
bash .claude/scripts/spec-coverage.sh init "$COV_BARE" .feature/bare-id/spec-bundle.md 2>/dev/null
if grep -qE '^\| auth\.bare-token \| R1 \| pending \| pending \|' "$COV_BARE"; then
    pass "bare-ID bundle (pre-title format) still parses (backwards-compatible)"
else
    fail "bare-ID bundle regressed" "got: $(cat "$COV_BARE" | tail -5)"
fi

# ── Tests 12-19: primary-vs-context scope distinction ──────────────────────
# Regression: spec-coverage previously gate-enforced every row in the
# bundle, which forced waiver-spam on transitively-pulled context specs
# (parent chain, requires:, sibling expansion). spec-resolve now emits
# `Primary specs:` and `Context specs:` preamble lines; init reads them
# to tag context rows; gate skips context-tagged rows by default with
# --include-context for strict mode.

# Bundle with explicit Primary/Context preamble lines.
mkdir -p .feature/scoped
cat > .feature/scoped/spec-bundle.md << 'BUNDLE'
# Resolved Context Bundle
Generated: 2026-05-07T00:00:00Z
Feature request: scoped
Domains matched: auth, billing
Token budget: 25000 | Tokens used: ~1500
Omitted (budget): none
Force-included (over budget, kept to avoid empty bundle): none
Omitted (DRAFT with unresolved conflicts): none
Primary specs: auth.token-validation
Context specs: auth.session-lifecycle, billing.charge-flow

## Open Obligations (must be addressed in this feature)
none

## Feature Requirements

# auth.token-validation — JWT Token Validation

## Requirements
R1. The TokenValidator must reject expired tokens.
R2. The TokenValidator must reject malformed tokens.

---

# auth.session-lifecycle — Session Lifecycle (transitively pulled)

## Requirements
R1. The SessionStore must invalidate on logout.

---

# billing.charge-flow — Charge Flow (transitively pulled)

## Requirements
R1. The ChargeProcessor must finalize via SettlementGateway.
R2. The ChargeProcessor must roll back on settlement failure.
BUNDLE

COV_SCOPED=".feature/scoped/spec-coverage.md"
bash .claude/scripts/spec-coverage.sh init "$COV_SCOPED" .feature/scoped/spec-bundle.md 2>/dev/null

# ── Test 12: init tags context-spec rows with `context` in Notes ───────────

echo ""
echo "── Test 12: init tags context-spec rows with 'context' in Notes column"

if grep -qE '^\| auth\.session-lifecycle \| R1 \| pending \| pending \| context \|' "$COV_SCOPED" \
   && grep -qE '^\| billing\.charge-flow \| R1 \| pending \| pending \| context \|' "$COV_SCOPED"; then
    pass "context-spec rows tagged"
else
    fail "context-spec rows not tagged" "got: $(grep '^|' $COV_SCOPED)"
fi

# ── Test 13: init does NOT tag primary-spec rows ───────────────────────────

echo ""
echo "── Test 13: primary-spec rows have empty Notes column"

if grep -qE '^\| auth\.token-validation \| R1 \| pending \| pending \|  \|' "$COV_SCOPED" \
   && grep -qE '^\| auth\.token-validation \| R2 \| pending \| pending \|  \|' "$COV_SCOPED"; then
    pass "primary-spec rows have empty Notes"
else
    fail "primary-spec rows incorrectly tagged" "got: $(grep token-validation $COV_SCOPED)"
fi

# ── Test 14: gate (default) skips context rows ─────────────────────────────

echo ""
echo "── Test 14: gate (default) fires only on primary-spec pending rows"

if bash .claude/scripts/spec-coverage.sh gate "$COV_SCOPED" >/tmp/vallorcine/gate-scoped.txt 2>/dev/null; then
    fail "gate returned 0 with primary-spec rows still pending"
else
    # Should list the 2 primary requirements, not the 3 context ones.
    if grep -q "auth.token-validation.R1" /tmp/vallorcine/gate-scoped.txt \
       && grep -q "auth.token-validation.R2" /tmp/vallorcine/gate-scoped.txt \
       && ! grep -q "auth.session-lifecycle" /tmp/vallorcine/gate-scoped.txt \
       && ! grep -q "billing.charge-flow" /tmp/vallorcine/gate-scoped.txt; then
        pass "gate enumerated 2 primary requirements; context rows excluded"
    else
        fail "gate output mis-scoped" "$(cat /tmp/vallorcine/gate-scoped.txt)"
    fi
fi

# ── Test 15: gate hint mentions --include-context for strict mode ──────────

echo ""
echo "── Test 15: gate failure message hints at --include-context"

if grep -q -- "--include-context" /tmp/vallorcine/gate-scoped.txt; then
    pass "gate failure mentions --include-context for strict mode"
else
    fail "gate failure should mention --include-context" "$(cat /tmp/vallorcine/gate-scoped.txt)"
fi

# ── Test 16: gate --include-context fires on every pending row ─────────────

echo ""
echo "── Test 16: gate --include-context flips to whole-bundle strict mode"

if bash .claude/scripts/spec-coverage.sh gate "$COV_SCOPED" --include-context >/tmp/vallorcine/gate-strict.txt 2>/dev/null; then
    fail "strict gate returned 0 with rows still pending"
else
    pending_count=$(grep -cE '^- ' /tmp/vallorcine/gate-strict.txt || echo 0)
    if [[ "$pending_count" -eq 5 ]]; then
        pass "strict gate enumerated all 5 rows (2 primary + 3 context)"
    else
        fail "strict gate count wrong" "got $pending_count: $(cat /tmp/vallorcine/gate-strict.txt)"
    fi
fi

# ── Test 17: report breaks down primary vs context counts ──────────────────

echo ""
echo "── Test 17: report distinguishes primary vs context in counts"

output=$(bash .claude/scripts/spec-coverage.sh report "$COV_SCOPED" 2>/dev/null)
if echo "$output" | grep -qE '5 loaded · 0 annotated · 0 waived · 2 pending \(\+ 3 context not gate-enforced; 3 of those still pending\)'; then
    pass "report shows primary + context breakdown"
else
    fail "report breakdown wrong" "got: $output"
fi

# ── Test 18: legacy bundle (no Primary specs preamble) treats all as primary ─

echo ""
echo "── Test 18: legacy bundle without Primary specs line — all rows primary"

mkdir -p .feature/legacy
cat > .feature/legacy/spec-bundle.md << 'BUNDLE'
# Resolved Context Bundle
Generated: 2026-04-01T00:00:00Z

## Feature Requirements

# auth.legacy-spec — Legacy

## Requirements
R1. Legacy req.
BUNDLE

COV_LEGACY=".feature/legacy/spec-coverage.md"
bash .claude/scripts/spec-coverage.sh init "$COV_LEGACY" .feature/legacy/spec-bundle.md 2>/dev/null
# No row should carry the `context` tag — legacy bundles default to primary
if ! grep -qE '\| context \|' "$COV_LEGACY" \
   && grep -qE '^\| auth\.legacy-spec \| R1 \| pending \| pending \|  \|' "$COV_LEGACY"; then
    pass "legacy bundle: every row treated as primary (Notes empty)"
else
    fail "legacy bundle should not produce context-tagged rows" "got: $(grep '^|' $COV_LEGACY)"
fi
# And the gate should fire on it (default mode, not skipped as context)
if bash .claude/scripts/spec-coverage.sh gate "$COV_LEGACY" >/dev/null 2>&1; then
    fail "legacy gate should fail on the lone primary row"
else
    pass "legacy gate fires on primary row (no scope filter applied)"
fi

# ── Test 19: re-init preserves context tag idempotently ─────────────────────

echo ""
echo "── Test 19: re-init preserves context tag without overwriting waiver notes"

# Apply a waiver on a context row; re-init should not clobber the waiver.
bash .claude/scripts/spec-coverage.sh waive "$COV_SCOPED" auth.session-lifecycle.R1 \
    "covered by integration suite" 2>/dev/null
bash .claude/scripts/spec-coverage.sh init "$COV_SCOPED" .feature/scoped/spec-bundle.md 2>/dev/null
if grep -qE '^\| auth\.session-lifecycle \| R1 \| waived: covered by integration suite' "$COV_SCOPED"; then
    pass "re-init preserved waiver on context row"
else
    fail "re-init clobbered waiver" "got: $(grep session-lifecycle $COV_SCOPED)"
fi
# Other context rows should still carry the `context` tag.
if grep -qE '^\| billing\.charge-flow \| R1 \| pending \| pending \| context \|' "$COV_SCOPED"; then
    pass "re-init preserved context tag on un-waived context rows"
else
    fail "re-init lost context tag" "got: $(grep charge-flow $COV_SCOPED)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "──────────────────────────────────────────────────────────────────"
if [[ $failed -eq 0 ]]; then
    echo "ALL PASSED  ($passed/$total)"
else
    echo "FAILED  $failed/$total  ($passed passed)"
fi
echo ""

exit $failed
