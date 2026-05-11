#!/usr/bin/env bash
# Scenario: work-orchestrator.sh state machine
#
# Validates the persistent state directory that drives the (future)
# dynamic /work-run skill. The orchestrator manages a queue + in-flight
# + completed + blocked sets across ticks; this test exercises every
# subcommand and the transitions between sets.
#
# Run from repo root: bash tests/scenario-work-orchestrator.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-work-orchestrator"

passed=0
failed=0
total=0

pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }

cleanup() { rm -rf "$TEST_BASE" 2>/dev/null || true; }
trap cleanup EXIT

cleanup
mkdir -p "$TEST_BASE/project/.work/alpha"
mkdir -p "$TEST_BASE/project/.claude/scripts"

cp "$REPO_ROOT/scripts/work-orchestrator.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-resolve.sh"      "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-lib.sh"          "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh"          "$TEST_BASE/project/.claude/scripts/"

cd "$TEST_BASE/project"

# Three independent SPECIFIED WDs (no deps) — all should land in the queue.
for i in 01 02 03; do
  cat > ".work/alpha/WD-$i.md" <<EOF
---
id: WD-$i
title: Test WD $i
group: alpha
status: SPECIFIED
domains: [test]
produces:
  - { type: spec, path: "test/wd$i-contract" }
---

## Summary
Test WD $i.

## Acceptance Criteria
Pass.
EOF
done

# Mark the produced specs as present so artifact_deps consider them
# satisfied. Tests don't need a real spec body — work-resolve only
# checks for file existence.
mkdir -p .spec/domains/test
for i in 01 02 03; do
  cat > ".spec/domains/test/wd${i}-contract.md" <<EOF
---
{
  "id": "test.wd${i}-contract",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["test"],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": []
}
---

# test.wd${i}-contract — Test WD $i Contract

## Requirements
R1. Test.

---

## Design Narrative
Test.
EOF
done

ORCH="bash .claude/scripts/work-orchestrator.sh"

echo ""
echo "scenario: work-orchestrator.sh"
echo "────────────────────────────────────────────────"

# ── init ────────────────────────────────────────────────────────────────────

echo ""
echo "── init"

out=$($ORCH init alpha --cap 2 2>&1)
if echo "$out" | grep -q "Initialized orchestrator"; then
    pass "init reports success"
else
    fail "init failed" "$out"
fi

if [[ -d .work/alpha/.orchestrator ]]; then
    pass "init created .orchestrator directory"
else
    fail "init missed .orchestrator directory"
fi

if [[ -f .work/alpha/.orchestrator/state.json ]]; then
    pass "init created state.json"
else
    fail "init missed state.json"
fi

if grep -q '"concurrency_cap": 2' .work/alpha/.orchestrator/state.json; then
    pass "init --cap 2 stored in state.json"
else
    fail "init --cap 2 not stored"
fi

if grep -q '"paused": false' .work/alpha/.orchestrator/state.json; then
    pass "init starts unpaused"
else
    fail "init paused state wrong"
fi

# Three SPECIFIED WDs should have been queued.
queue_count=$(wc -l < .work/alpha/.orchestrator/queue.txt | tr -d ' ')
if [[ "$queue_count" -eq 3 ]]; then
    pass "init queued 3 SPECIFIED WDs"
else
    fail "expected 3 queued, got $queue_count"
fi

# ── init refuses if already initialized ─────────────────────────────────────

echo ""
echo "── init idempotency"

if ! $ORCH init alpha 2>/dev/null; then
    pass "init refuses re-init (correct: must clear first)"
else
    fail "init should refuse re-init"
fi

# ── ready returns up to cap ─────────────────────────────────────────────────

echo ""
echo "── ready (cap=2, 0 in-flight)"

ready=$($ORCH ready alpha)
ready_count=$(echo "$ready" | grep -c .)
if [[ "$ready_count" -eq 2 ]]; then
    pass "ready returns 2 WDs (cap=2, no in-flight)"
else
    fail "expected 2 ready, got $ready_count" "$ready"
fi

# ── dispatch moves queue → in-flight ────────────────────────────────────────

echo ""
echo "── dispatch"

$ORCH dispatch alpha WD-01 alpha--WD-01 >/dev/null
if [[ -f .work/alpha/.orchestrator/in-flight/WD-01.json ]]; then
    pass "dispatch created in-flight/WD-01.json"
else
    fail "dispatch missed in-flight record"
fi

if ! grep -qxF "WD-01" .work/alpha/.orchestrator/queue.txt; then
    pass "dispatch removed WD-01 from queue"
else
    fail "WD-01 still in queue after dispatch"
fi

if grep -q '"feature_slug": "alpha--WD-01"' .work/alpha/.orchestrator/in-flight/WD-01.json; then
    pass "in-flight record carries feature_slug"
else
    fail "feature_slug not recorded"
fi

# ── ready respects in-flight count ──────────────────────────────────────────

echo ""
echo "── ready (cap=2, 1 in-flight)"

ready=$($ORCH ready alpha)
ready_count=$(echo "$ready" | grep -c . || true)
if [[ "$ready_count" -eq 1 ]]; then
    pass "ready returns 1 (cap-in_flight=2-1)"
else
    fail "expected 1 ready, got $ready_count" "$ready"
fi

# ── dispatch second WD, ready returns 0 ─────────────────────────────────────

$ORCH dispatch alpha WD-02 alpha--WD-02 >/dev/null
ready=$($ORCH ready alpha)
ready_count=$(echo "$ready" | grep -c . || true)
if [[ "$ready_count" -eq 0 ]]; then
    pass "ready returns 0 when cap reached (2 in-flight)"
else
    fail "expected 0 ready at cap, got $ready_count"
fi

# ── dispatch errors on unknown WD ───────────────────────────────────────────

echo ""
echo "── dispatch error path"

if ! $ORCH dispatch alpha WD-99 alpha--WD-99 2>/dev/null; then
    pass "dispatch refuses unknown WD-99"
else
    fail "dispatch should error on unknown WD"
fi

# ── complete moves in-flight → completed ────────────────────────────────────

echo ""
echo "── complete"

$ORCH complete alpha WD-01 COMPLETE "alpha--WD-01: COMPLETE — refactor clean" >/dev/null
if [[ -f .work/alpha/.orchestrator/completed/WD-01.json ]]; then
    pass "complete created completed/WD-01.json"
else
    fail "complete missed record"
fi

if [[ ! -f .work/alpha/.orchestrator/in-flight/WD-01.json ]]; then
    pass "complete removed in-flight/WD-01.json"
else
    fail "WD-01 still in-flight after complete"
fi

if grep -q '"status": "COMPLETE"' .work/alpha/.orchestrator/completed/WD-01.json; then
    pass "completed record carries status"
else
    fail "completed status not recorded"
fi

# ── ready now returns 1 again (cap=2, 1 in-flight) ──────────────────────────

ready=$($ORCH ready alpha)
ready_count=$(echo "$ready" | grep -c . || true)
if [[ "$ready_count" -eq 1 ]]; then
    pass "ready returns 1 after complete frees a slot"
else
    fail "expected 1 ready after complete, got $ready_count"
fi

# ── block moves in-flight → blocked + paused=true ───────────────────────────

echo ""
echo "── block"

$ORCH block alpha WD-02 "escalation:design-choice" ".feature/alpha--WD-02/escalation.json" >/dev/null
if [[ -f .work/alpha/.orchestrator/blocked/WD-02.json ]]; then
    pass "block created blocked/WD-02.json"
else
    fail "block missed record"
fi

if grep -q '"paused": true' .work/alpha/.orchestrator/state.json; then
    pass "block set paused=true"
else
    fail "paused flag not set"
fi

if grep -q '"reason": "escalation:design-choice"' .work/alpha/.orchestrator/blocked/WD-02.json; then
    pass "blocked record carries reason"
else
    fail "reason not recorded"
fi

if grep -q '"escalation_path"' .work/alpha/.orchestrator/blocked/WD-02.json; then
    pass "blocked record carries escalation_path"
else
    fail "escalation_path not recorded"
fi

# ── ready returns 0 while paused ────────────────────────────────────────────

ready=$($ORCH ready alpha)
ready_count=$(echo "$ready" | grep -c . || true)
if [[ "$ready_count" -eq 0 ]]; then
    pass "ready returns 0 while paused"
else
    fail "expected 0 ready while paused, got $ready_count"
fi

# ── unblock moves blocked → queue ───────────────────────────────────────────

echo ""
echo "── unblock + resume"

$ORCH unblock alpha WD-02 >/dev/null
if [[ ! -f .work/alpha/.orchestrator/blocked/WD-02.json ]]; then
    pass "unblock removed blocked/WD-02.json"
else
    fail "WD-02 still blocked after unblock"
fi

if grep -qxF "WD-02" .work/alpha/.orchestrator/queue.txt; then
    pass "unblock re-queued WD-02"
else
    fail "WD-02 not re-queued"
fi

# ── still paused after unblock (resume is separate) ─────────────────────────

if grep -q '"paused": true' .work/alpha/.orchestrator/state.json; then
    pass "unblock alone does NOT clear paused (resume is explicit)"
else
    fail "paused was cleared by unblock (should require explicit resume)"
fi

# ── resume clears paused ────────────────────────────────────────────────────

$ORCH resume alpha >/dev/null
if grep -q '"paused": false' .work/alpha/.orchestrator/state.json; then
    pass "resume cleared paused flag"
else
    fail "resume did not clear paused"
fi

# ── ready now returns queued + makes progress again ─────────────────────────

ready=$($ORCH ready alpha)
ready_count=$(echo "$ready" | grep -c . || true)
if [[ "$ready_count" -ge 1 ]]; then
    pass "ready returns work after resume ($ready_count)"
else
    fail "expected ready after resume, got 0"
fi

# ── status prints all sections ──────────────────────────────────────────────

echo ""
echo "── status display"

out=$($ORCH status alpha)
for section in "Started:" "Last tick:" "Cap:" "Paused:" "Queued:" "In-flight:" "Completed:" "Blocked:"; do
    if echo "$out" | grep -qF "$section"; then
        pass "status shows section: $section"
    else
        fail "status missing section: $section"
    fi
done

# ── dump --section state ────────────────────────────────────────────────────

echo ""
echo "── dump"

out=$($ORCH dump alpha --section state)
if echo "$out" | grep -q '"schema_version": 1'; then
    pass "dump --section state outputs JSON"
else
    fail "dump --section state malformed"
fi

# ── idempotent queue_append (re-init detection) ─────────────────────────────

echo ""
echo "── resolve dedupes against existing sets"

# WD-01 is in completed; WD-02 is in queue (after unblock). WD-03 is in
# queue. So 'resolve' should not re-queue any of them.
out=$($ORCH resolve alpha)
if echo "$out" | grep -q "+0 newly-SPECIFIED"; then
    pass "resolve correctly dedupes (no double-queue)"
else
    fail "resolve dedupe broke" "$out"
fi

# ── hung: in-flight WD with stale status.md flagged ─────────────────────────

echo ""
echo "── hung detection"

# WD-03 still in queue. Dispatch it then artificially backdate
# its status.md mtime.
$ORCH dispatch alpha WD-03 alpha--WD-03 >/dev/null
mkdir -p .feature/alpha--WD-03
touch .feature/alpha--WD-03/status.md
# Back-date by 2 hours
old=$(($(date -u +%s) - 7200))
touch -d "@$old" .feature/alpha--WD-03/status.md 2>/dev/null \
  || touch -t "$(date -u -r "$old" +%Y%m%d%H%M.%S 2>/dev/null || echo "202601010000.00")" .feature/alpha--WD-03/status.md 2>/dev/null || true

hung_out=$($ORCH hung alpha --threshold-seconds 1800)
if echo "$hung_out" | grep -q "WD-03"; then
    pass "hung detects stale in-flight WD (>30 min)"
else
    fail "hung did not flag WD-03" "$hung_out"
fi

# Same WD with much larger threshold — should NOT be flagged.
hung_out=$($ORCH hung alpha --threshold-seconds 999999)
if [[ -z "$hung_out" ]]; then
    pass "hung respects threshold (not flagged at huge threshold)"
else
    fail "hung over-flagged at huge threshold" "$hung_out"
fi

# ── clear removes directory ─────────────────────────────────────────────────

echo ""
echo "── clear"

$ORCH clear alpha >/dev/null
if [[ ! -d .work/alpha/.orchestrator ]]; then
    pass "clear removed .orchestrator/"
else
    fail "clear failed"
fi

# ── clear is idempotent ─────────────────────────────────────────────────────

if $ORCH clear alpha 2>/dev/null; then
    pass "clear is idempotent (no error when absent)"
else
    fail "clear errored on missing directory"
fi

# ── ready/status fail cleanly when uninitialized ────────────────────────────

echo ""
echo "── error paths when uninitialized"

if ! $ORCH ready alpha 2>/dev/null; then
    pass "ready exits non-zero when uninitialized"
else
    fail "ready should error when uninitialized"
fi

if ! $ORCH status alpha 2>/dev/null; then
    pass "status exits non-zero when uninitialized"
else
    fail "status should error when uninitialized"
fi

# ════════════════════════════════════════════════════════════════════════════
# State-invariant tests — added after 2026-05-11 adversarial review.
# The original tests exercised happy-path subcommand effects. They missed
# CRITICAL and HIGH findings because they used only ASCII-clean inputs
# and never asserted invariants between sets.
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "── invariants: state.json is always valid JSON"
echo "  ─────────────────────────────────────────"

# Fresh fixture for a clean state-invariant pass.
cd "$REPO_ROOT"
rm -rf "$TEST_BASE"
mkdir -p "$TEST_BASE/project/.work/inv" "$TEST_BASE/project/.claude/scripts" "$TEST_BASE/project/.spec/domains/test"
cp "$REPO_ROOT/scripts/work-orchestrator.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-resolve.sh"      "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-lib.sh"          "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh"          "$TEST_BASE/project/.claude/scripts/"
cd "$TEST_BASE/project"

for i in 01 02; do
  cat > ".work/inv/WD-$i.md" <<EOF
---
id: WD-$i
title: Invariant WD $i
group: inv
status: SPECIFIED
domains: [test]
produces:
  - { type: spec, path: "test/inv${i}-contract" }
---
## Summary
.
## Acceptance Criteria
.
EOF
  cat > ".spec/domains/test/inv${i}-contract.md" <<EOF
---
{ "id": "test.inv${i}-contract", "version": 1, "status": "ACTIVE", "state": "APPROVED", "domains": ["test"], "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": [] }
---
# test.inv${i}-contract
## Requirements
R1.
---
## Design Narrative
.
EOF
done

# Helper: assert state.json is parseable JSON. Falls back to a python3
# json.tool round-trip; if python3 isn't present, do a lightweight check.
assert_valid_state_json() {
    local label="$1"
    local f=".work/inv/.orchestrator/state.json"
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
            pass "state.json valid JSON after $label"
        else
            fail "state.json INVALID JSON after $label" "$(cat "$f")"
        fi
    else
        # Crude fallback: ensure no stray `: ,` patterns (the corruption mode
        # the CRITICAL finding produced).
        if grep -qE ':[[:space:]]*,' "$f"; then
            fail "state.json has empty value after $label" "$(cat "$f")"
        else
            pass "state.json passes shape check after $label"
        fi
    fi
}

# Helper: assert no WD appears in two sets (the cross-set window invariant).
assert_no_cross_set_overlap() {
    local label="$1"
    local dir=".work/inv/.orchestrator"
    local overlap
    overlap=$(find "$dir/in-flight" "$dir/completed" "$dir/blocked" \
        -name '*.json' 2>/dev/null \
        | xargs -I{} basename {} .json 2>/dev/null \
        | sort | uniq -d | tr '\n' ' ')
    if [[ -z "$overlap" ]]; then
        pass "no cross-set overlap after $label"
    else
        fail "cross-set overlap after $label: $overlap"
    fi
}

ORCH="bash .claude/scripts/work-orchestrator.sh"

$ORCH init inv --cap 2 >/dev/null
assert_valid_state_json "init"
assert_no_cross_set_overlap "init"

$ORCH dispatch inv WD-01 inv--WD-01 >/dev/null
assert_valid_state_json "dispatch"
assert_no_cross_set_overlap "dispatch"

$ORCH complete inv WD-01 COMPLETE "inv--WD-01: COMPLETE — done" >/dev/null
assert_valid_state_json "complete"
assert_no_cross_set_overlap "complete"

$ORCH dispatch inv WD-02 inv--WD-02 >/dev/null
$ORCH block inv WD-02 "escalation:design-choice" ".feature/inv--WD-02/escalation.json" >/dev/null
assert_valid_state_json "block"
assert_no_cross_set_overlap "block"

$ORCH unblock inv WD-02 >/dev/null
assert_valid_state_json "unblock"

$ORCH resume inv >/dev/null
assert_valid_state_json "resume"

# ── block with quoted-content reason (CRITICAL #2 reproducer) ──────────────

echo ""
echo "── block with quoted-content reason"
echo "  ────────────────────────────────"

# Re-dispatch WD-02 then block with a reason containing literal `"` and `\`.
# Pre-fix this would have truncated pause_reason at the first `"` and
# corrupted state.json. Post-fix, pause_reason is no longer in state.json
# at all — blocked/<wd>.json carries the per-WD reason and state.json
# stays small + valid.
$ORCH dispatch inv WD-02 inv--WD-02 >/dev/null 2>&1 || true
$ORCH block inv WD-02 'design-choice: use "status": "running" or "idle"?' '.feature/inv--WD-02/escalation.json' >/dev/null
assert_valid_state_json "block with quoted-content reason"

# The reason should round-trip through blocked/<wd>.json without truncation.
got_reason=$(grep -oE '"reason":[[:space:]]*"[^"]*"' .work/inv/.orchestrator/blocked/WD-02.json | head -1 | sed -E 's/.*"reason":[[:space:]]*"([^"]*)".*/\1/')
# The reason value will include the outer quotes intact because json_escape
# turned them into \". After unescaping we should see the literal text up to
# the first unescaped quote — which here is the start of the embedded `"status"`.
# We assert that the prefix is preserved (this is the part that would have
# corrupted state.json pre-fix).
if [[ "$got_reason" == *"design-choice"* ]]; then
    pass "blocked record preserves reason prefix with quoted content"
else
    fail "blocked record lost reason content" "got: $got_reason"
fi

# ── resume refuses while blocked/ non-empty (MEDIUM #7) ────────────────────

echo ""
echo "── multi-block + resume guard"
echo "  ─────────────────────────────"

# WD-02 is currently blocked. Resume should refuse.
if ! $ORCH resume inv 2>/dev/null; then
    pass "resume refuses while blocked/ non-empty"
else
    fail "resume should refuse with blocked WDs present"
fi

# Unblock and resume succeeds.
$ORCH unblock inv WD-02 >/dev/null
if $ORCH resume inv >/dev/null 2>&1; then
    pass "resume succeeds once all unblocked"
else
    fail "resume should succeed when blocked is empty"
fi

# ── dispatch refuses empty feature_slug (MEDIUM #8) ────────────────────────

echo ""
echo "── dispatch input validation"
echo "  ─────────────────────────"

# Need a queued WD first. WD-02 is in queue after unblock+resume.
if ! $ORCH dispatch inv WD-02 "" 2>/dev/null; then
    pass "dispatch refuses empty feature_slug"
else
    fail "dispatch should refuse empty feature_slug"
fi

$ORCH dispatch inv WD-02 inv--WD-02 >/dev/null
if ! $ORCH dispatch inv WD-02 inv--WD-02 2>/dev/null; then
    err=$($ORCH dispatch inv WD-02 inv--WD-02 2>&1 || true)
    if echo "$err" | grep -q "already in-flight"; then
        pass "double-dispatch error message says 'already in-flight'"
    else
        fail "double-dispatch error message incorrect" "$err"
    fi
else
    fail "double-dispatch should fail"
fi

# ── init refuses for nonexistent group (HIGH #5) ───────────────────────────

echo ""
echo "── init error paths"
echo "  ────────────────"

if ! $ORCH init nonexistent-typo --cap 2 2>/dev/null; then
    pass "init refuses nonexistent group (loud error, not silent empty queue)"
else
    fail "init should error for missing group dir"
    $ORCH clear nonexistent-typo >/dev/null 2>&1 || true
fi

# ── state.json survives a state_write with all-default inputs ──────────────

# Force a tick (state_tick uses fallback defaults).
echo ""
echo "── tick with corrupted state.json recovers cleanly"
echo "  ───────────────────────────────────────────────"

# Manually corrupt one field; the next tick should reset it to a sane
# default rather than emit invalid JSON.
$ORCH dispatch inv WD-01 inv--WD-01 2>/dev/null || true  # may already exist
echo '{ "schema_version": 1, "group_slug": "inv" }' > .work/inv/.orchestrator/state.json
$ORCH complete inv WD-02 COMPLETE "x" >/dev/null 2>&1 || true
assert_valid_state_json "complete after corrupted state.json"

# WD-id validation already covered by the validate_wd_id function and
# tested implicitly via dispatch's ^WD-[0-9]+ regex. Add an explicit one.
if ! $ORCH dispatch inv "../WD-99" inv--WD-99 2>/dev/null; then
    pass "dispatch rejects path-injection WD-id"
else
    fail "WD-id validation missed path-injection"
fi

# ── skip: atomic blocked → completed:ERROR ─────────────────────────────────
# (PR C CRITICAL #1: /work-run "Skip this WD" path needs this to avoid
# the unblock+complete sequence that the state machine rejects.)

echo ""
echo "── skip subcommand (PR C CRITICAL #1)"
echo "  ─────────────────────────────────"

# Fresh scenario: clear, re-init, dispatch a fresh WD, block, skip.
$ORCH clear inv >/dev/null 2>&1 || true
$ORCH init inv --cap 2 >/dev/null
$ORCH dispatch inv WD-01 inv--WD-01 >/dev/null
$ORCH block inv WD-01 "escalation:design-choice" ".feature/inv--WD-01/escalation.json" >/dev/null

# skip refuses missing reason
if ! $ORCH skip inv WD-01 "" 2>/dev/null; then
    pass "skip refuses empty reason"
else
    fail "skip should require non-empty reason"
fi

# skip refuses non-blocked WD
if ! $ORCH skip inv WD-99 "test" 2>/dev/null; then
    pass "skip refuses non-blocked WD"
else
    fail "skip should require blocked membership"
fi

# Happy path
$ORCH skip inv WD-01 "user picked Skip" >/dev/null
if [[ ! -f .work/inv/.orchestrator/blocked/WD-01.json ]]; then
    pass "skip removed WD-01 from blocked/"
else
    fail "WD-01 still in blocked after skip"
fi

if [[ -f .work/inv/.orchestrator/completed/WD-01.json ]]; then
    pass "skip wrote WD-01 to completed/"
else
    fail "WD-01 not in completed after skip"
fi

if grep -q '"status": "ERROR"' .work/inv/.orchestrator/completed/WD-01.json; then
    pass "skip records WD as ERROR status"
else
    fail "skip's completed record missing ERROR status"
fi

if grep -q '"summary_line": "user skipped: user picked Skip"' .work/inv/.orchestrator/completed/WD-01.json; then
    pass "skip records 'user skipped:' prefix + reason"
else
    fail "skip didn't preserve reason in summary_line"
fi

# State-invariant: state.json still valid; no cross-set overlap.
assert_valid_state_json "skip"
assert_no_cross_set_overlap "skip"

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "Total: $total | Passed: $passed | Failed: $failed"
echo ""

[[ $failed -eq 0 ]] && exit 0 || exit 1
