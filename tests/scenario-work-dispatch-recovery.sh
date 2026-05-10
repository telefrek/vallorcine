#!/usr/bin/env bash
# Scenario: work-dispatch.sh marker lifecycle for crash-resilient sub-agent
# dispatch.
#
# Background: /work-start dispatches each WD as a sub-agent via Agent. When
# the Agent call returns "[Tool result missing due to internal error]" or
# "The user doesn't want to proceed with this tool use" the orchestrator
# loses the result payload. Without a disk-side record of the dispatch the
# task list says in_progress and recovery requires manual filesystem
# inspection. work-dispatch.sh writes a marker per dispatch so recovery
# can reason about the actual state.
#
# Layered cover:
#
#   1. begin writes a marker in dispatch-pending state.
#   2. ack writes a marker in acknowledged state with the result line.
#   3. fail records a payload-lost / user-stopped reason and acks.
#   4. stuck enumerates only unacknowledged markers (one row per stuck WD).
#   5. status returns the marker JSON; exit 1 when absent.
#   6. clear deletes the marker; clearing an absent marker is a no-op.
#   7. JSON output survives a result line containing newline / tab /
#      backslash / control bytes (same robustness work-resolve.sh has).
#   8. Re-dispatching the same WD overwrites the previous marker (the
#      coordinator is the sole writer).
#
# Run from repo root: bash tests/scenario-work-dispatch-recovery.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WORK_DISPATCH="$REPO_ROOT/scripts/work-dispatch.sh"

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
echo "scenario: work-dispatch.sh marker lifecycle"
echo "────────────────────────────────────────────────"

TMPDIR_TEST="$(mktemp -d /tmp/vallorcine/work-dispatch.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PROJ="$TMPDIR_TEST/proj"
mkdir -p "$PROJ/.work/auto-index/auto-index"   # extra dir for work_find_root
GROUP_DIR="$PROJ/.work/auto-index"
echo '---' > "$GROUP_DIR/WD-01.md"
echo '---' > "$GROUP_DIR/WD-02.md"
echo '---' > "$GROUP_DIR/WD-03.md"
cd "$PROJ"

# ── 1. begin writes a marker in dispatch-pending state ───────────────────

bash "$WORK_DISPATCH" begin auto-index WD-01 >/dev/null
MARKER_01="$GROUP_DIR/_dispatch-WD-01.json"

if [[ -f "$MARKER_01" ]]; then
  pass "begin: marker file created"
else
  fail "begin: marker file created" "$MARKER_01 missing"
fi

if grep -q '"ack":false' "$MARKER_01"; then
  pass "begin: ack flag is false"
else
  fail "begin: ack flag is false"
fi

if grep -q '"wd_id":"WD-01"' "$MARKER_01"; then
  pass "begin: wd_id recorded"
else
  fail "begin: wd_id recorded"
fi

if grep -qE '"dispatched_at":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z"' "$MARKER_01"; then
  pass "begin: dispatched_at is ISO-8601 UTC"
else
  fail "begin: dispatched_at is ISO-8601 UTC"
fi

# ── 2. ack writes the result line ────────────────────────────────────────

bash "$WORK_DISPATCH" ack auto-index WD-01 \
    "auto-index--WD-01: COMPLETE — feature merged" >/dev/null

if grep -q '"ack":true' "$MARKER_01"; then
  pass "ack: ack flag flipped to true"
else
  fail "ack: ack flag flipped to true"
fi

if grep -q "COMPLETE" "$MARKER_01"; then
  pass "ack: result line stored"
else
  fail "ack: result line stored"
fi

if grep -qE '"acknowledged_at":"[0-9]{4}-' "$MARKER_01"; then
  pass "ack: acknowledged_at populated"
else
  fail "ack: acknowledged_at populated"
fi

# ── 3. fail records a payload-lost reason and acks ───────────────────────

bash "$WORK_DISPATCH" begin auto-index WD-02 >/dev/null
bash "$WORK_DISPATCH" fail auto-index WD-02 "payload-lost" >/dev/null
MARKER_02="$GROUP_DIR/_dispatch-WD-02.json"

if grep -q '"failure_reason":"payload-lost"' "$MARKER_02"; then
  pass "fail: failure_reason stored"
else
  fail "fail: failure_reason stored"
fi

if grep -q '"ack":true' "$MARKER_02"; then
  pass "fail: ack flag flipped to true (so it stops appearing in stuck)"
else
  fail "fail: ack flag flipped to true (so it stops appearing in stuck)"
fi

if grep -q '"result":null' "$MARKER_02"; then
  pass "fail: result remains null (no result was received)"
else
  fail "fail: result remains null (no result was received)"
fi

# ── 4. stuck enumerates only unacknowledged markers ──────────────────────

# Create one more in begin state to verify stuck picks it up.
bash "$WORK_DISPATCH" begin auto-index WD-03 >/dev/null

stuck_out="$(bash "$WORK_DISPATCH" stuck auto-index)"

if echo "$stuck_out" | grep -q '^WD-03|'; then
  pass "stuck: unacknowledged WD-03 listed"
else
  fail "stuck: unacknowledged WD-03 listed" "got: $stuck_out"
fi

if echo "$stuck_out" | grep -q '^WD-01|'; then
  fail "stuck: acknowledged WD-01 NOT listed" "WD-01 should be filtered out"
else
  pass "stuck: acknowledged WD-01 NOT listed"
fi

if echo "$stuck_out" | grep -q '^WD-02|'; then
  fail "stuck: ack-failed WD-02 NOT listed" "WD-02 should be filtered out (ack=true)"
else
  pass "stuck: ack-failed WD-02 NOT listed"
fi

# ── 5. status returns marker JSON; exit 1 when absent ────────────────────

if bash "$WORK_DISPATCH" status auto-index WD-01 | grep -q '"wd_id":"WD-01"'; then
  pass "status: returns JSON for present marker"
else
  fail "status: returns JSON for present marker"
fi

if ! bash "$WORK_DISPATCH" status auto-index WD-99 >/dev/null 2>&1; then
  pass "status: exits non-zero for absent marker"
else
  fail "status: exits non-zero for absent marker"
fi

# ── 6. clear deletes the marker; absent clear is a no-op ─────────────────

bash "$WORK_DISPATCH" clear auto-index WD-03 >/dev/null
if [[ ! -f "$GROUP_DIR/_dispatch-WD-03.json" ]]; then
  pass "clear: marker file removed"
else
  fail "clear: marker file removed"
fi

if bash "$WORK_DISPATCH" clear auto-index WD-99 >/dev/null 2>&1; then
  pass "clear: idempotent on absent marker"
else
  fail "clear: idempotent on absent marker"
fi

# ── 7. JSON output survives newline / tab / control bytes in result ──────

bash "$WORK_DISPATCH" begin auto-index WD-03 >/dev/null
bash "$WORK_DISPATCH" ack auto-index WD-03 \
    $'auto-index--WD-03: STOPPED_AT_test\nstray newline\ttab\\backslash"quote' \
    >/dev/null

# The marker should still be one valid JSON line — no raw newlines, no
# raw quotes, no raw control bytes in the body.
if python3 -c "import json,sys; json.load(open('$GROUP_DIR/_dispatch-WD-03.json'))" 2>/dev/null; then
  pass "ack: result containing newline / tab / backslash / quote stays valid JSON"
else
  fail "ack: result containing newline / tab / backslash / quote stays valid JSON" \
       "$(cat "$GROUP_DIR/_dispatch-WD-03.json")"
fi

# ── 8. re-dispatch overwrites prior marker ───────────────────────────────

bash "$WORK_DISPATCH" begin auto-index WD-01 >/dev/null
if grep -q '"ack":false' "$MARKER_01"; then
  pass "begin: re-dispatch resets ack to false"
else
  fail "begin: re-dispatch resets ack to false"
fi

# ── Final report ─────────────────────────────────────────────────────────

echo ""
echo "── Summary ──"
echo "  Passed: $passed/$total"
echo "  Failed: $failed/$total"

[[ $failed -eq 0 ]] && exit 0 || exit 1
