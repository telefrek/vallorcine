#!/usr/bin/env bash
# Scenario: generic dispatch-marker.sh primitive
#
# Validates the dispatch marker contract reused by /spec-backfill --all
# (and future /curate dispatch). The script is a generic counterpart to
# work-dispatch.sh — same begin / ack / fail / status / stuck / clear
# subcommands, but with a marker root passed in as the first argument so
# any skill can drop markers into its own state directory.
#
# Run from repo root: bash tests/scenario-dispatch-marker.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-dispatch-marker"
DM="$REPO_ROOT/scripts/dispatch-marker.sh"

passed=0
failed=0
total=0

pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }

cleanup() { rm -rf "$TEST_BASE" 2>/dev/null || true; }
trap cleanup EXIT

cleanup
mkdir -p "$TEST_BASE"
ROOT="$TEST_BASE/markers"

echo ""
echo "scenario: dispatch-marker.sh"
echo "────────────────────────────────────────────────"

# ── Test 1: begin creates a marker with ack=false ────────────────────────────

echo ""
echo "── Test 1: begin writes a fresh marker"

bash "$DM" begin "$ROOT" "spec-A" >/dev/null
marker="$ROOT/_dispatch-spec-A.json"
if [[ -f "$marker" ]]; then
    pass "marker file written at expected path"
else
    fail "marker not written"
fi

if grep -q '"ack":false' "$marker"; then
    pass "fresh marker has ack=false"
else
    fail "fresh marker missing ack=false"
fi

if grep -q '"id":"spec-A"' "$marker"; then
    pass "marker carries the id field"
else
    fail "marker missing id field"
fi

# ── Test 2: stuck reports unacked markers ────────────────────────────────────

echo ""
echo "── Test 2: stuck lists unacked markers, exits 0 with content"

out="$(bash "$DM" stuck "$ROOT")"
if [[ -n "$out" ]] && echo "$out" | grep -q "^spec-A|"; then
    pass "stuck shows the unacked spec-A row"
else
    fail "stuck did not surface spec-A" "got: $out"
fi

# ── Test 3: ack flips the marker + removes it from stuck ─────────────────────

echo ""
echo "── Test 3: ack updates marker and clears it from stuck list"

bash "$DM" ack "$ROOT" "spec-A" "COMPLETE spec-A annotated=3 skipped=0 waived=0 uncovered_after=0" >/dev/null

if grep -q '"ack":true' "$marker"; then
    pass "ack flipped marker to ack=true"
else
    fail "ack did not update ack flag"
fi

if grep -q 'annotated=3' "$marker"; then
    pass "ack preserved the result line in marker"
else
    fail "ack did not preserve result line"
fi

stuck_out="$(bash "$DM" stuck "$ROOT" || true)"
if [[ -z "$stuck_out" ]]; then
    pass "acked marker no longer appears in stuck"
else
    fail "acked marker still in stuck list" "got: $stuck_out"
fi

# ── Test 4: fail records failure_reason, still ack=true ──────────────────────

echo ""
echo "── Test 4: fail acks marker with failure_reason"

bash "$DM" begin "$ROOT" "spec-B" >/dev/null
bash "$DM" fail "$ROOT" "spec-B" "payload-lost" >/dev/null

marker_b="$ROOT/_dispatch-spec-B.json"
if grep -q '"ack":true' "$marker_b" && grep -q '"failure_reason":"payload-lost"' "$marker_b"; then
    pass "fail sets ack=true + records failure_reason"
else
    fail "fail did not set ack/failure_reason correctly"
fi

if ! bash "$DM" stuck "$ROOT" 2>/dev/null | grep -q "spec-B"; then
    pass "failed marker stays out of stuck list (ack flipped)"
else
    fail "failed marker incorrectly appears in stuck"
fi

# ── Test 5: clear removes the marker, idempotent ─────────────────────────────

echo ""
echo "── Test 5: clear removes marker, idempotent on repeat"

bash "$DM" clear "$ROOT" "spec-A" >/dev/null
if [[ ! -f "$marker" ]]; then
    pass "clear removes the marker file"
else
    fail "clear did not remove marker"
fi

if bash "$DM" clear "$ROOT" "spec-A" >/dev/null 2>&1; then
    pass "clear is idempotent on already-cleared id"
else
    fail "clear failed on already-cleared id"
fi

# ── Test 6: status returns marker JSON, exits 1 when absent ──────────────────

echo ""
echo "── Test 6: status emits JSON for present marker, exits 1 if absent"

if bash "$DM" status "$ROOT" "spec-B" 2>/dev/null | grep -q '"schema_version":1'; then
    pass "status prints marker JSON for present id"
else
    fail "status did not print JSON for spec-B"
fi

if ! bash "$DM" status "$ROOT" "nonexistent-id" >/dev/null 2>&1; then
    pass "status exits non-zero for absent marker"
else
    fail "status did not exit non-zero for absent marker"
fi

# ── Test 7: id slugification keeps dots/hyphens, replaces unsafe chars ───────

echo ""
echo "── Test 7: id with dots/hyphens preserved, unsafe chars slugified"

bash "$DM" begin "$ROOT" "engine.handle-lifecycle.state-machine" >/dev/null
if [[ -f "$ROOT/_dispatch-engine.handle-lifecycle.state-machine.json" ]]; then
    pass "dotted/hyphenated id preserved in marker filename"
else
    fail "dotted id was not preserved in filename"
fi

# id with slash should be slugified to underscore (slash would create
# subdirectory, breaking the marker layout)
bash "$DM" begin "$ROOT" "topic/category/subject" >/dev/null
if [[ -f "$ROOT/_dispatch-topic_category_subject.json" ]]; then
    pass "slashes in id slugified to underscores"
else
    fail "slash id was not slugified correctly"
fi

# ── Test 8: marker root auto-created if absent ───────────────────────────────

echo ""
echo "── Test 8: begin creates the marker root directory if missing"

DEEP_ROOT="$TEST_BASE/deeply/nested/markers"
bash "$DM" begin "$DEEP_ROOT" "spec-C" >/dev/null
if [[ -f "$DEEP_ROOT/_dispatch-spec-C.json" ]]; then
    pass "begin auto-creates deep marker root"
else
    fail "begin did not create marker root"
fi

# ── Test 9: stuck returns empty (exit 0) for an empty marker root ────────────

echo ""
echo "── Test 9: stuck handles empty marker root gracefully"

EMPTY_ROOT="$TEST_BASE/empty"
mkdir -p "$EMPTY_ROOT"
out="$(bash "$DM" stuck "$EMPTY_ROOT" 2>&1)"
if [[ -z "$out" ]]; then
    pass "stuck returns empty for an empty root"
else
    fail "stuck emitted output for empty root: $out"
fi

# Nonexistent root: still exits 0 with no output (the script's
# `[[ -d "$root" ]] || return 0` guard).
out="$(bash "$DM" stuck "$TEST_BASE/never-existed" 2>&1)"
if [[ -z "$out" ]]; then
    pass "stuck returns empty for nonexistent root"
else
    fail "stuck emitted output for missing root: $out"
fi

# ── Test 10: JSON escaping handles control chars + quotes safely ─────────────

echo ""
echo "── Test 10: ack with quotes + control bytes produces valid JSON"

bash "$DM" begin "$ROOT" "spec-X" >/dev/null
# Result line containing quotes, newline, and tab
bash "$DM" ack "$ROOT" "spec-X" $'COMPLETE spec-X "quoted"\nnewline\ttab' >/dev/null

marker_x="$ROOT/_dispatch-spec-X.json"
if command -v jq >/dev/null 2>&1; then
    if jq -e . "$marker_x" >/dev/null 2>&1; then
        pass "marker with quoted+newline result is valid JSON"
    else
        fail "marker JSON did not parse via jq"
    fi
    # The escaped result should round-trip back through jq
    val="$(jq -r '.result' "$marker_x")"
    if [[ "$val" == $'COMPLETE spec-X "quoted"\nnewline\ttab' ]]; then
        pass "round-trip preserves quotes/newline/tab in result"
    else
        fail "round-trip mangled result" "got: $val"
    fi
else
    echo "  SKIP  jq not available for round-trip check"
fi

# ── Test 11: status uses slugified path for lookup (consistency) ─────────────

echo ""
echo "── Test 11: status lookup uses same slug as begin"

# Same slash-containing id from Test 7 should resolve via status
if bash "$DM" status "$ROOT" "topic/category/subject" 2>/dev/null | grep -q '"id":"topic/category/subject"'; then
    pass "status resolves slugified id and preserves original id in JSON"
else
    fail "status could not resolve slugified id"
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
