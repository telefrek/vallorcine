#!/usr/bin/env bash
# Scenario: work-decompose + work-resume MEDIUM fixes from 2026-05-11
# adversarial sweep.
#
# decompose M1: Step 7 ordering — validate BEFORE populating cache.
# decompose M2: orphan-detection regex tolerates YAML-indented status.
# work-resume M1: orchestrator acquires state lock on mutating cmds.
# work-resume M2: Step 3 mtime check has a same-mtime stage-2 path.
# work-resume M3: Step 2a detects corrupted/partially-deleted state.
#
# Run from repo root: bash tests/scenario-work-medium-cluster.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DECOMP_SKILL="$REPO_ROOT/skills/work-decompose/SKILL.md"
RESUME_SKILL="$REPO_ROOT/skills/work-resume/SKILL.md"
ORCH="$REPO_ROOT/scripts/work-orchestrator.sh"

passed=0; failed=0; total=0
pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }

echo ""
echo "scenario: work-decompose + work-resume MEDIUM cluster"
echo "────────────────────────────────────────────────"

# ── decompose M1: validate BEFORE cache populate ───────────────────────────

echo ""
echo "  decompose M1 — Step 7 runs validate BEFORE populating cache"
echo "  ──────────────────────────────────────────────────────"

# The validate section must appear in Step 7 BEFORE the cache populate section.
val_line=$(grep -n "Run invariant check" "$DECOMP_SKILL" | grep -v "fails" | head -1 | cut -d: -f1)
cache_line=$(grep -n "Populate the readiness cache" "$DECOMP_SKILL" | head -1 | cut -d: -f1)

if [[ -n "$val_line" && -n "$cache_line" && "$val_line" -lt "$cache_line" ]]; then
    pass "validate (line $val_line) runs BEFORE cache populate (line $cache_line)"
else
    fail "ordering wrong" "val=$val_line cache=$cache_line"
fi

if grep -qF "Order matters here" "$DECOMP_SKILL"; then
    pass "SKILL documents why ordering matters"
else
    fail "ordering rationale missing"
fi

# ── decompose M2 + resume regex anchoring ─────────────────────────────────

echo ""
echo "  decompose M2 / resume — orphan regex tolerates YAML indentation"
echo "  ───────────────────────────────────────────────────────────────"

# All three sites should now use ^[[:space:]]*status: anchoring
sites=0
expected=3
for line in $(grep -nE '^[[:space:]]+-exec grep -lE|^[[:space:]]+&& grep -qE' "$DECOMP_SKILL" "$RESUME_SKILL" 2>/dev/null | grep -oE '^[^:]+:[0-9]+' || true); do
    sites=$((sites + 1))
done

# Simpler check: count the corrected pattern across both files
corrected_count=$(grep -cE 'status:\[\[:space:\]\]\*\(SPECIFYING' "$DECOMP_SKILL" "$RESUME_SKILL" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
if (( corrected_count >= 3 )); then
    pass "all 3 grep sites use tolerant anchoring ($corrected_count matches)"
else
    fail "expected >= 3 corrected grep sites, found $corrected_count"
fi

# No site should still have the brittle `^status:` anchor
brittle_count=$( { grep -cE "'\^status: \(SPECIFYING" "$DECOMP_SKILL" "$RESUME_SKILL" 2>/dev/null || true; } | awk -F: '{s+=$2} END{print s+0}')
if (( brittle_count == 0 )); then
    pass "no brittle '^status: (...)' patterns remain"
else
    fail "$brittle_count brittle anchors remain"
fi

# ── work-resume M1: orchestrator acquires state lock ──────────────────────

echo ""
echo "  work-resume M1 — orchestrator state lock on mutators"
echo "  ──────────────────────────────────────────────────"

if grep -qE 'acquire_state_lock\(\)' "$ORCH"; then
    pass "acquire_state_lock helper defined"
else
    fail "acquire_state_lock helper missing"
fi

# Each mutating command should call it
for cmd in cmd_complete cmd_block cmd_skip; do
    body=$(awk "/^${cmd}\\(\\)/,/^}/" "$ORCH")
    if echo "$body" | grep -qE 'acquire_state_lock'; then
        pass "$cmd acquires state lock"
    else
        fail "$cmd doesn't acquire state lock"
    fi
done

# Lock helper should degrade gracefully when flock is missing
helper_body=$(awk '/^acquire_state_lock\(\)/,/^}/' "$ORCH")
if echo "$helper_body" | grep -qE 'command -v flock'; then
    pass "lock helper degrades gracefully without flock"
else
    fail "lock helper hard-requires flock"
fi

# ── work-resume M2: same-mtime stage-2 ────────────────────────────────────

echo ""
echo "  work-resume M2 — Step 3 mtime check handles 1-sec granularity"
echo "  ────────────────────────────────────────────────────────"

step3=$(awk '/^## Step 3 — Refresh readiness cache/,/^---$/' "$RESUME_SKILL")

if echo "$step3" | grep -qE '1-second mtime granularity|HFS\+|same-second'; then
    pass "Step 3 acknowledges 1-second mtime granularity"
else
    fail "Step 3 missing mtime-granularity rationale"
fi

if echo "$step3" | grep -qE 'src_mtime.*-eq.*cache_mtime|same mtime'; then
    pass "Step 3 forces refresh on same-mtime source files"
else
    fail "Step 3 missing same-mtime equality check"
fi

if echo "$step3" | grep -qE 'stat -c %Y.*stat -f %m'; then
    pass "Step 3 uses portable GNU/BSD stat fallback"
else
    fail "Step 3 stat invocation not cross-platform"
fi

# ── work-resume M3: corrupted/partially-deleted detection ─────────────────

echo ""
echo "  work-resume M3 — Step 2a detects corrupted/partial state"
echo "  ──────────────────────────────────────────────────────"

step2a=$(awk '/Corrupted \/ partially-deleted/,/^Otherwise, classify/' "$RESUME_SKILL")

if [[ -n "$step2a" ]]; then
    pass "Step 2a has corrupted/partially-deleted case"
else
    fail "corrupted case missing"
fi

if echo "$step2a" | grep -qE 'manifest_count.*-gt 0.*fs_count'; then
    pass "Step 2a compares manifest count vs filesystem count"
else
    fail "Step 2a missing manifest-vs-fs count check"
fi

if echo "$step2a" | grep -qE 'Restore from git'; then
    pass "Step 2a offers 'Restore from git' option"
else
    fail "Step 2a missing restore option"
fi

# ── Summary ────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "Total: $total | Passed: $passed | Failed: $failed"
echo ""

[[ $failed -eq 0 ]] && exit 0 || exit 1
