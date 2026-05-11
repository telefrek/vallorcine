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

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "Total: $total | Passed: $passed | Failed: $failed"
echo ""

[[ $failed -eq 0 ]] && exit 0 || exit 1
