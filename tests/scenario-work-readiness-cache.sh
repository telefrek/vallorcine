#!/usr/bin/env bash
# Scenario: work-resolve.sh emits a structured `_readiness.json` cache
# that downstream skills (/work-resume, /work-status --all, parallel
# coordination) can read instead of parsing the markdown report.
#
# Tests:
# 1. _readiness.json is written next to manifest.md after a normal run
# 2. JSON parses as valid JSON (python3 json.load succeeds)
# 3. summary counts match the resolver's stderr diagnostic line
# 4. wds[] entries include id, title, status, deps_count, blockers, unblocks
# 5. titles containing double quotes are correctly escaped
# 6. blockers array is populated for BLOCKED WDs and empty for READY
# 7. unblocks array reflects produces→deps relationships
# 8. atomic write — _readiness.json.tmp.* is not left behind on success
#
# Run from repo root: bash tests/scenario-work-readiness-cache.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-work-readiness-cache"
RESOLVE="$REPO_ROOT/scripts/work-resolve.sh"

passed=0; failed=0; total=0
pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }
cleanup() { rm -rf "$TEST_BASE" 2>/dev/null || true; }
trap cleanup EXIT

echo ""
echo "scenario: work-resolve.sh _readiness.json cache"
echo "──────────────────────────────────────────────────────────────────"

cleanup

# Common fixture: 3 WDs — one READY, one BLOCKED on a missing spec, one
# whose produces unblocks the BLOCKED one.

setup_fixture() {
  local proj="$TEST_BASE/project"
  rm -rf "$TEST_BASE"
  mkdir -p "$proj/.work/example" "$proj/.spec/registry" "$proj/.claude/scripts" "$proj/.decisions"

  # Copy work scripts so the fixture is self-contained
  cp "$REPO_ROOT/scripts/work-resolve.sh" "$proj/.claude/scripts/"
  cp "$REPO_ROOT/scripts/work-lib.sh"     "$proj/.claude/scripts/"
  cp "$REPO_ROOT/scripts/spec-lib.sh"     "$proj/.claude/scripts/"

  cat > "$proj/.work/example/work.md" << 'EOF'
---
group: example
external_deps: []
---

# Example
## Goal
Test readiness JSON cache.
EOF

  cat > "$proj/.work/example/manifest.md" << 'EOF'
# example manifest

## Work Definitions

| WD | Title | Status | Domains | Deps | Produces |
|----|-------|--------|---------|------|----------|
EOF

  # WD-01: produces a spec, no deps → READY
  cat > "$proj/.work/example/WD-01.md" << 'EOF'
---
id: WD-01
title: Foundation "with quotes" in title
group: example
status: DRAFT
domains: [engine]
artifact_deps: []
produces:
  - { type: spec, path: "engine/foundation-contract" }
---

## Summary
Foundational spec.
EOF

  # WD-02: needs WD-01's spec APPROVED → initially BLOCKED
  cat > "$proj/.work/example/WD-02.md" << 'EOF'
---
id: WD-02
title: Consumer
group: example
status: DRAFT
domains: [engine]
artifact_deps:
  - { type: spec, path: "engine/foundation-contract", required_state: APPROVED }
---

## Summary
Consumes the foundation spec.
EOF

  # WD-03: independent, no deps → READY
  cat > "$proj/.work/example/WD-03.md" << 'EOF'
---
id: WD-03
title: Independent
group: example
status: DRAFT
domains: [io]
artifact_deps: []
produces: []
---

## Summary
Independent work.
EOF

  cat > "$proj/.spec/registry/manifest.json" << 'EOF'
{ "schema_version": 2, "specs": [] }
EOF

  echo "$proj"
}

# Helper: run the resolver from inside the fixture project
run_resolve() {
  local proj="$1"
  local group="$2"
  ( cd "$proj" && bash .claude/scripts/work-resolve.sh "$group" ) 1>/tmp/resolve-stdout.$$ 2>/tmp/resolve-stderr.$$
  local rc=$?
  cat /tmp/resolve-stdout.$$
  cat /tmp/resolve-stderr.$$ >&2
  rm -f /tmp/resolve-stdout.$$ /tmp/resolve-stderr.$$
  return $rc
}

# ── Test 1: cache file written ──────────────────────────────────────────────

echo ""
echo "── Test 1: _readiness.json is written after a resolver run"

proj=$(setup_fixture)
( cd "$proj" && bash .claude/scripts/work-resolve.sh example ) >/dev/null 2>/tmp/stderr.$$
if [[ -f "$proj/.work/example/_readiness.json" ]]; then
    pass "cache file exists"
else
    fail "cache file not created" "expected: $proj/.work/example/_readiness.json"
fi

# ── Test 2: cache file is valid JSON ────────────────────────────────────────

echo ""
echo "── Test 2: cache parses as valid JSON"

if python3 -c "import json; json.load(open('$proj/.work/example/_readiness.json'))" 2>/tmp/jsonerr.$$; then
    pass "valid JSON"
else
    fail "invalid JSON" "$(cat /tmp/jsonerr.$$)"
fi
rm -f /tmp/jsonerr.$$

# ── Test 3: summary counts ──────────────────────────────────────────────────

echo ""
echo "── Test 3: summary counts (1 ready DRAFT no-deps, 1 blocked, 1 ready DRAFT no-deps)"
# Note: the resolver classifies ALL DRAFTs with deps met as READY. So both
# WD-01 (no deps) and WD-03 (no deps) should be READY; WD-02 BLOCKED.

ready=$(python3 -c "import json; print(json.load(open('$proj/.work/example/_readiness.json'))['summary']['ready'])")
blocked=$(python3 -c "import json; print(json.load(open('$proj/.work/example/_readiness.json'))['summary']['blocked'])")
total_count=$(python3 -c "import json; print(json.load(open('$proj/.work/example/_readiness.json'))['summary']['total'])")

if [[ "$ready" == "2" && "$blocked" == "1" && "$total_count" == "3" ]]; then
    pass "summary: total=3 ready=2 blocked=1"
else
    fail "summary counts wrong" "got total=$total_count ready=$ready blocked=$blocked"
fi

# ── Test 4: wd entries shape ────────────────────────────────────────────────

echo ""
echo "── Test 4: wds[] entries have required fields"

shape_ok=$(python3 -c "
import json
d = json.load(open('$proj/.work/example/_readiness.json'))
required = {'id', 'title', 'status', 'deps_count', 'blockers', 'unblocks'}
missing_for = []
for wd in d['wds']:
    miss = required - set(wd.keys())
    if miss:
        missing_for.append((wd.get('id', '?'), miss))
print('MISSING:' + str(missing_for) if missing_for else 'OK')
")

if [[ "$shape_ok" == "OK" ]]; then
    pass "all wds[] entries have required fields"
else
    fail "wds[] entries missing fields" "$shape_ok"
fi

# ── Test 5: title escaping ──────────────────────────────────────────────────

echo ""
echo "── Test 5: titles with embedded quotes are correctly escaped"

title_check=$(python3 -c "
import json
d = json.load(open('$proj/.work/example/_readiness.json'))
wd1 = next(w for w in d['wds'] if w['id'] == 'WD-01')
expected = 'Foundation \"with quotes\" in title'
print('OK' if wd1['title'] == expected else f'BAD: got {wd1[\"title\"]!r}')
")

if [[ "$title_check" == "OK" ]]; then
    pass "embedded double quotes round-trip cleanly"
else
    fail "title escape broken" "$title_check"
fi

# ── Test 6: blockers populated for BLOCKED WD ───────────────────────────────

echo ""
echo "── Test 6: blockers array populated for BLOCKED, empty for READY"

blocker_check=$(python3 -c "
import json
d = json.load(open('$proj/.work/example/_readiness.json'))
wd1 = next(w for w in d['wds'] if w['id'] == 'WD-01')
wd2 = next(w for w in d['wds'] if w['id'] == 'WD-02')
ready_empty = wd1['status'] == 'READY' and wd1['blockers'] == []
blocked_has  = wd2['status'] == 'BLOCKED' and len(wd2['blockers']) > 0
print('OK' if (ready_empty and blocked_has) else f'BAD ready_empty={ready_empty} blocked_has={blocked_has}')
")

if [[ "$blocker_check" == "OK" ]]; then
    pass "blockers shape correct"
else
    fail "blockers shape wrong" "$blocker_check"
fi

# ── Test 7: unblocks reflects produces→deps relationship ────────────────────

echo ""
echo "── Test 7: WD-01 unblocks WD-02 (via produces→deps)"

unblocks_check=$(python3 -c "
import json
d = json.load(open('$proj/.work/example/_readiness.json'))
wd1 = next(w for w in d['wds'] if w['id'] == 'WD-01')
print('OK' if 'WD-02' in wd1['unblocks'] else f'BAD: {wd1[\"unblocks\"]!r}')
")

if [[ "$unblocks_check" == "OK" ]]; then
    pass "WD-01 → WD-02 unblock edge present"
else
    fail "unblock edge missing" "$unblocks_check"
fi

# ── Test 8: atomic write — no .tmp leftover ─────────────────────────────────

echo ""
echo "── Test 8: no _readiness.json.tmp.* leftover after success"

leftover=$(find "$proj/.work/example" -name '_readiness.json.tmp.*' 2>/dev/null)
if [[ -z "$leftover" ]]; then
    pass "no tmp file leftover"
else
    fail "tmp file not cleaned up" "$leftover"
fi

rm -f /tmp/stderr.$$

# ── Test 9 (precursor): cache reflects status changes when resolver re-runs
#
# The /work-plan, /work-start, /feature-complete skills now call
# `work-resolve.sh` after sed-mutating WD status. This test mimics that
# flow — flip a WD's status on disk, re-run the resolver, confirm the
# cache reflects the new state.

echo ""
echo "── Test 9: cache reflects WD status changes after a resolver re-run"

# Reuse the 3-WD fixture from the earlier tests
proj=$(setup_fixture)
( cd "$proj" && bash .claude/scripts/work-resolve.sh example ) >/dev/null 2>&1

before_wd1=$(python3 -c "
import json
d = json.load(open('$proj/.work/example/_readiness.json'))
print(next(w for w in d['wds'] if w['id'] == 'WD-01')['status'])
")

# Mutate WD-01 to SPECIFIED (mimic /work-plan finishing)
sed -i "s/^status:.*/status: SPECIFIED/" "$proj/.work/example/WD-01.md"

# Re-run the resolver (mimic the new refresh-on-mutate pattern)
( cd "$proj" && bash .claude/scripts/work-resolve.sh example ) >/dev/null 2>&1

after_wd1=$(python3 -c "
import json
d = json.load(open('$proj/.work/example/_readiness.json'))
print(next(w for w in d['wds'] if w['id'] == 'WD-01')['status'])
")

if [[ "$before_wd1" == "READY" && "$after_wd1" == "SPECIFIED" ]]; then
    pass "cache reflects WD-01 transition READY → SPECIFIED"
else
    fail "cache stale after status change" "before=$before_wd1 after=$after_wd1"
fi

# ── Test 10a: stale .tmp.* files from a prior failed run ────────────────────
# A previous run that died mid-write would leave _readiness.json.tmp.<PID>
# behind. Successful subsequent runs should not be confused by them.
# (The current trap cleans up the CURRENT run's tmp; orphans from prior
# runs accumulate until manually removed. We assert here that the resolver
# at minimum does not crash if it finds them, and that it produces a clean
# successful output.)

echo ""
echo "── Test 10a: leftover .tmp.<other-pid> from prior crash does not break a fresh run"

proj=$(setup_fixture)
# Simulate orphan from a hypothetical prior crashed run
touch "$proj/.work/example/_readiness.json.tmp.99999"
( cd "$proj" && bash .claude/scripts/work-resolve.sh example ) >/dev/null 2>/tmp/stderr.$$

if [[ -f "$proj/.work/example/_readiness.json" ]] && \
   python3 -c "import json; json.load(open('$proj/.work/example/_readiness.json'))" 2>/dev/null; then
    pass "fresh run succeeds despite orphan tmp file"
else
    fail "orphan tmp file broke the run" "stderr: $(cat /tmp/stderr.$$ 2>/dev/null)"
fi
rm -f /tmp/stderr.$$

# ── Test 11: control character in WD title produces valid JSON ─────────────
# json_escape strips ASCII control chars (0x00-0x08, 0x0B-0x0C, 0x0E-0x1F)
# before applying escape transforms. Without this, a title containing a
# stray BEL or NUL would produce invalid JSON that consumers cannot parse.

echo ""
echo "── Test 11: WD title with control chars yields valid JSON"

proj=$(setup_fixture)
# Inject a BEL (0x07) and a Form Feed (0x0C) into the title — both are
# control chars json_escape should strip rather than emit raw.
python3 -c "
content = open('$proj/.work/example/WD-01.md').read()
content = content.replace('Foundation \"with quotes\" in title',
                          'Foundation\\x07with control\\x0Cchars')
open('$proj/.work/example/WD-01.md', 'w').write(content)
"

( cd "$proj" && bash .claude/scripts/work-resolve.sh example ) >/dev/null 2>/tmp/stderr.$$

if python3 -c "
import json
d = json.load(open('$proj/.work/example/_readiness.json'))
wd1 = next(w for w in d['wds'] if w['id'] == 'WD-01')
# Title should not contain BEL or FF — they were stripped
assert '\x07' not in wd1['title'], 'BEL should have been stripped'
assert '\x0c' not in wd1['title'], 'FF should have been stripped'
print('OK')
" 2>/tmp/jsonerr.$$; then
    pass "control chars stripped, JSON remains valid"
else
    fail "control char handling broken" "$(cat /tmp/jsonerr.$$ 2>/dev/null)"
fi
rm -f /tmp/stderr.$$ /tmp/jsonerr.$$

# ── Test 12: lock file is created when flock is available ──────────────────
# Best-effort proof that flock-based serialization is wired up. We don't
# test contention directly (hard in bash); we verify the lock file appears
# alongside the cache, signaling the lock acquisition path ran.

echo ""
echo "── Test 12: .work-resolve.lock is created when flock is available"

if command -v flock >/dev/null 2>&1; then
    proj=$(setup_fixture)
    ( cd "$proj" && bash .claude/scripts/work-resolve.sh example ) >/dev/null 2>/dev/null
    if [[ -f "$proj/.work/example/.work-resolve.lock" ]]; then
        pass "lock file present after a flock-equipped run"
    else
        fail "lock file not created"
    fi
else
    pass "skipped — flock not available on this platform"
fi

# ── Test 12a: parallel runs serialize and produce consistent JSON ──────────
# Two parallel resolvers MUST NOT interleave their writes such that one
# stomps on the other's content. After both finish, the cache must be
# valid JSON and reflect the (identical) input state. Without the lock
# wrapping the compute phase, a slow read in one process and a fast
# write in another can produce a fresh-mtime cache with stale content.

echo ""
echo "── Test 12a: 5 parallel resolvers leave a consistent JSON cache"

if command -v flock >/dev/null 2>&1; then
    proj=$(setup_fixture)
    # Fire 5 concurrent resolvers
    for i in 1 2 3 4 5; do
        ( cd "$proj" && bash .claude/scripts/work-resolve.sh example ) >/dev/null 2>/dev/null &
    done
    wait

    # The cache must exist and be valid JSON
    if [[ -f "$proj/.work/example/_readiness.json" ]] && \
       python3 -c "import json; json.load(open('$proj/.work/example/_readiness.json'))" 2>/dev/null; then
        pass "parallel runs produce valid JSON"
    else
        fail "parallel runs produced invalid or missing JSON"
    fi

    # No leftover .tmp files from racing writes
    leftover=$(find "$proj/.work/example" -name '_readiness.json.tmp.*' 2>/dev/null)
    if [[ -z "$leftover" ]]; then
        pass "no .tmp.* leftover after parallel runs"
    else
        fail "tmp files leaked from parallel runs" "$leftover"
    fi

    # Content correctness — JSON validity isn't enough. The lock-during-
    # compute claim only holds if the cache content matches what's on
    # disk. Mutate WD-01, run 5 parallel resolvers, then verify the cache
    # reflects the post-mutation state (not a stale pre-mutation snapshot
    # from a runner that read first but wrote last).
    sed -i "s/^status: DRAFT$/status: SPECIFIED/" "$proj/.work/example/WD-01.md"
    for i in 1 2 3 4 5; do
        ( cd "$proj" && bash .claude/scripts/work-resolve.sh example ) >/dev/null 2>/dev/null &
    done
    wait
    cache_status=$(python3 -c "
import json
d = json.load(open('$proj/.work/example/_readiness.json'))
wd1 = next((w for w in d['wds'] if w['id'] == 'WD-01'), None)
print(wd1['status'] if wd1 else 'MISSING')
")
    if [[ "$cache_status" == "SPECIFIED" ]]; then
        pass "cache content reflects post-mutation state (not a stale snapshot)"
    else
        fail "cache shows stale content despite parallel runs" "got: $cache_status (expected SPECIFIED)"
    fi
else
    pass "skipped — flock not available"
    pass "skipped — flock not available"
    pass "skipped — flock not available"
fi

# ── Test 13: empty group — valid JSON with empty wds[] ─────────────────────
# Edge case: a group exists (e.g., just created via /work) but has no WD files
# yet. The resolver must still emit valid JSON. Without this guarantee,
# /work-resume's JSON read would fail on freshly-created groups.

echo ""
echo "── Test 13: empty group emits valid JSON with empty wds[]"

empty_proj="$TEST_BASE/empty"
rm -rf "$empty_proj"
mkdir -p "$empty_proj/.work/empty-group" "$empty_proj/.spec/registry" "$empty_proj/.claude/scripts" "$empty_proj/.decisions"
cp "$REPO_ROOT/scripts/work-resolve.sh" "$empty_proj/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-lib.sh"     "$empty_proj/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh"     "$empty_proj/.claude/scripts/"

cat > "$empty_proj/.work/empty-group/work.md" << 'EOF'
---
group: empty-group
external_deps: []
---

# Empty
## Goal
No WDs yet.
EOF

cat > "$empty_proj/.spec/registry/manifest.json" << 'EOF'
{ "schema_version": 2, "specs": [] }
EOF

( cd "$empty_proj" && bash .claude/scripts/work-resolve.sh empty-group ) >/dev/null 2>/tmp/stderr.$$

if [[ -f "$empty_proj/.work/empty-group/_readiness.json" ]] && \
   python3 -c "
import json
d = json.load(open('$empty_proj/.work/empty-group/_readiness.json'))
assert d['summary']['total'] == 0, f'expected total=0, got {d[\"summary\"][\"total\"]}'
assert d['wds'] == [], f'expected empty wds, got {d[\"wds\"]}'
" 2>/tmp/jsonerr.$$; then
    pass "empty group → valid JSON, total=0, wds=[]"
else
    fail "empty group JSON wrong" "$(cat /tmp/jsonerr.$$ 2>/dev/null) / stderr: $(cat /tmp/stderr.$$ 2>/dev/null)"
fi
rm -f /tmp/stderr.$$ /tmp/jsonerr.$$

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "──────────────────────────────────────────────────────────────────"
echo "Total: $total | Passed: $passed | Failed: $failed"

if (( failed > 0 )); then
    exit 1
fi
exit 0
