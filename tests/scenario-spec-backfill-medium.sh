#!/usr/bin/env bash
# Scenario: /spec-backfill MEDIUM fixes from 2026-05-11 adversarial sweep.
#
# M1: C2b parse-failure references C2e (not the typo C2d).
# M2: User-aborts-mid-AskUserQuestion-loop dispatches Phase B with
#     partial decision-set instead of losing all answered decisions.
# M3: dispatch-marker.sh read_field handles escaped quotes inside
#     result/failure_reason values.
# M4: spec-backfill-candidates.sh exits 3 (loud) when SCAN_DIRS is empty.
#
# Run from repo root: bash tests/scenario-spec-backfill-medium.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SKILL="$REPO_ROOT/skills/spec-backfill/SKILL.md"
DM="$REPO_ROOT/scripts/dispatch-marker.sh"
CAND="$REPO_ROOT/scripts/spec-backfill-candidates.sh"

passed=0; failed=0; total=0
pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }

TEST_DIR="/tmp/vallorcine/scenario-spec-backfill-medium"
cleanup() { rm -rf "$TEST_DIR" 2>/dev/null || true; }
trap cleanup EXIT

echo ""
echo "scenario: /spec-backfill MEDIUM cluster"
echo "────────────────────────────────────────────────"

# ── M1: C2b parse-failure references C2e ───────────────────────────────────

echo ""
echo "  M1 — C2b parse-failure cross-references C2e (not the typo C2d)"
echo "  ──────────────────────────────────────────────────────────"

if grep -qE 'parse failure.*marker.*failed.*continue.*C2e|surfacing logic is in C2e' "$SKILL"; then
    pass "C2b parse-failure path references C2e"
else
    fail "C2b parse-failure still references wrong section"
fi

# The fail-marker invocation should be named explicitly
if tr '\n' ' ' < "$SKILL" | tr -s ' ' | grep -qE 'dispatch-marker\.sh fail .spec/_backfill-dispatches <spec-id>--propose'; then
    pass "C2b spells out the dispatch-marker.sh fail invocation"
else
    fail "C2b doesn't spell out fail-marker invocation"
fi

# ── M2: user-abort mid-loop dispatches Phase B with partial set ───────────

echo ""
echo "  M2 — mid-AskUserQuestion abort dispatches Phase B with partial set"
echo "  ────────────────────────────────────────────────────────────"

fmodes=$(awk '/User aborts mid-AskUserQuestion/,/Exit the corpus loop/' "$SKILL")

if [[ -n "$fmodes" ]]; then
    pass "Failure modes section covers mid-loop abort"
else
    fail "mid-loop abort case missing"
fi

if echo "$fmodes" | grep -qE 'PARTIAL decision-set|partial decision-set'; then
    pass "mid-loop abort dispatches Phase B with partial decisions"
else
    fail "mid-loop abort doesn't dispatch Phase B"
fi

if echo "$fmodes" | grep -qE 'Phase B is idempotent'; then
    pass "rationale references Phase B idempotency"
else
    fail "missing idempotency rationale"
fi

if echo "$fmodes" | tr '\n' ' ' | tr -s ' ' | grep -qE 'will resurface on the next'; then
    pass "user told remaining R-ids will resurface"
else
    fail "missing resume guidance"
fi

# ── M3: dispatch-marker read_field handles escaped quotes ─────────────────

echo ""
echo "  M3 — dispatch-marker read_field handles escaped quotes"
echo "  ───────────────────────────────────────────────────"

cleanup
mkdir -p "$TEST_DIR"

# Build an UN-ACK'd marker with an escaped-quote failure_reason —
# `stuck` iterates unack'd markers and runs read_field on each field.
cat > "$TEST_DIR/_dispatch-test.json" <<'EOF'
{
  "schema_version": 1,
  "id": "test",
  "dispatched_at": "2026-05-11T00:00:00Z",
  "ack": false,
  "result": null,
  "failure_reason": "spec-backfill failed: \"foo\" then \"bar\" terminated",
  "acknowledged_at": null
}
EOF

# Use the dispatch-marker.sh stuck (which iterates + reads via read_field)
stuck_out=$(bash "$DM" stuck "$TEST_DIR" 2>/dev/null || true)

# Pre-fix: failure_reason would be truncated at first `\"`, so the
# stuck output would NOT contain "bar".
# Post-fix: should contain "bar" (full string preserved through the
# jq path or the perl regex fallback).
if [[ "$stuck_out" == *"bar"* ]]; then
    pass "read_field preserves content past escaped quotes in failure_reason"
else
    fail "read_field still truncates at escaped quote" "got: $stuck_out"
fi

# ── M4: spec-backfill-candidates.sh exits 3 on empty SCAN_DIRS ────────────

echo ""
echo "  M4 — spec-backfill-candidates.sh exits 3 (loud) on empty SCAN_DIRS"
echo "  ──────────────────────────────────────────────────────────────"

cleanup
mkdir -p "$TEST_DIR/empty-proj/.spec/registry"
echo '{"schema_version":2,"specs":[{"id":"test.foo","state":"APPROVED"}]}' > "$TEST_DIR/empty-proj/.spec/registry/manifest.json"
mkdir -p "$TEST_DIR/empty-proj/.spec/domains/test"
cat > "$TEST_DIR/empty-proj/.spec/domains/test/foo.md" <<'EOF'
---
{"id":"test.foo","version":1,"state":"APPROVED","status":"ACTIVE","domains":["test"]}
---

# test.foo

## Requirements

R1. The system must validate input tokens.

---

## Design Narrative
.
EOF

cd "$TEST_DIR/empty-proj"
# No src/lib/app/test dirs exist — scan dirs should be empty.
# Capture exit code without tripping set -e.
out=$(bash "$CAND" "test.foo" "R1" 2>&1) && rc=0 || rc=$?
cd "$REPO_ROOT"

if [[ $rc -eq 3 ]]; then
    pass "spec-backfill-candidates exits 3 on empty SCAN_DIRS"
else
    fail "expected exit 3, got $rc"
fi

if echo "$out" | grep -qE "ERROR.*no source directories|ERROR.*none of those directories"; then
    pass "error message names the problem"
else
    fail "error message doesn't explain the failure" "got: $out"
fi

# With SPEC_TRACE_DIRS set but nonexistent, same failure mode + different msg
cd "$TEST_DIR/empty-proj"
out=$(SPEC_TRACE_DIRS=nope bash "$CAND" "test.foo" "R1" 2>&1) && rc=0 || rc=$?
cd "$REPO_ROOT"
if [[ $rc -eq 3 ]] && echo "$out" | grep -qE "SPEC_TRACE_DIRS"; then
    pass "SPEC_TRACE_DIRS-with-no-existing-dir path exits 3 + names env var"
else
    fail "SPEC_TRACE_DIRS path didn't fail as expected" "rc=$rc, got: $out"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "Total: $total | Passed: $passed | Failed: $failed"
echo ""

[[ $failed -eq 0 ]] && exit 0 || exit 1
