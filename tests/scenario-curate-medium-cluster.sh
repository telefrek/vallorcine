#!/usr/bin/env bash
# Scenario: /curate + curate-scan.sh MEDIUM fixes from 2026-05-11
# adversarial sweep.
#
# M1: Step 5 no longer overwrites curation-state.md with a conflicting
#     schema; script remains the canonical writer.
# M2: link-rot cache prunes URLs no longer referenced by any KB entry
#     (cache no longer grows monotonically).
# M3: Stuck-marker prompt batches when N > 2 markers exist.
# M4: Analysis 28 tolerates both `.decisions/<slug>/adr.md` (grouped)
#     and `.decisions/<slug>.md` (flat) layouts.
#
# Run from repo root: bash tests/scenario-curate-medium-cluster.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SCAN="$REPO_ROOT/scripts/curate-scan.sh"
SKILL="$REPO_ROOT/skills/curate/SKILL.md"

passed=0; failed=0; total=0
pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }

TEST_DIR="/tmp/vallorcine/scenario-curate-medium"
cleanup() { rm -rf "$TEST_DIR" 2>/dev/null || true; }
trap cleanup EXIT

echo ""
echo "scenario: /curate MEDIUM cluster"
echo "────────────────────────────────────────────────"

# ── M1: Step 5 doesn't write curation-state.md ─────────────────────────────

echo ""
echo "  M1 — Step 5 is no-op for curation-state.md (script is canonical)"
echo "  ──────────────────────────────────────────────────────────"

step5=$(awk '/^## Step 5 — Update curation state/{p=1} p; /^## Step 6/{exit}' "$SKILL")

if echo "$step5" | tr '\n' ' ' | tr -s ' ' | grep -qE 'already wrote.*curation-state\.md|Step 5 is a no-op|canonical writer'; then
    pass "Step 5 documented as no-op for curation-state.md"
else
    fail "Step 5 still prescribes a SKILL-side write"
fi

# The format documented should match the script's actual output
if echo "$step5" | grep -qE 'Scan date:' && echo "$step5" | grep -qE '^Commits:'; then
    pass "Step 5 documents the canonical (script) format"
else
    fail "Step 5 format doesn't match script output"
fi

# The pre-fix conflicting field names should NOT be in the prescribed template
# (they may still appear as historical "do not re-introduce" note text)
if echo "$step5" | grep -qE 'Last scanned date: <YYYY-MM-DD>'; then
    fail "Step 5 still uses conflicting 'Last scanned date' field name"
else
    pass "Step 5 no longer prescribes 'Last scanned date' (script uses 'Scan date:')"
fi

# ── M2: link-rot cache prunes dead URLs ────────────────────────────────────

echo ""
echo "  M2 — link-rot cache prunes URLs not referenced in current scan"
echo "  ────────────────────────────────────────────────────────────"

# Find the cache-merge block
cache_merge=$(awk '/Atomic cache write/,/Stable output ordering/' "$SCAN")

if echo "$cache_merge" | grep -qE 'prune URLs no longer|LINK_ROT_SEEN.*URLs actually referenced|seen\[.+]'; then
    pass "cache-merge logic intersects with LINK_ROT_SEEN"
else
    fail "cache-merge still adds without pruning"
fi

if echo "$cache_merge" | grep -qE 'unbounded.*link-rot-cache|grow.*monotonically'; then
    pass "rationale documents the monotonic-growth bug"
else
    fail "rationale missing"
fi

# ── M3: Stuck-marker prompt batches when N > 2 ─────────────────────────────

echo ""
echo "  M3 — Stuck-marker prompt batches when N > 2 markers"
echo "  ─────────────────────────────────────────────────"

stuck_section=$(awk '/^\*\*Stuck-marker recovery/,/Display opening header/' "$SKILL")

if echo "$stuck_section" | grep -qE 'Batch the prompt when N > 2|batching path'; then
    pass "Stuck-marker section describes batching"
else
    fail "Stuck-marker section missing batching"
fi

# Three explicit branches: N==1, N==2, N>2
for branch in "N == 1" "N == 2" "N > 2"; do
    if echo "$stuck_section" | grep -qF -- "$branch"; then
        pass "branch $branch documented"
    else
        fail "branch $branch missing"
    fi
done

# N>2 path must offer "Re-dispatch all" / "Skip all" / "Walk one at a time"
if echo "$stuck_section" | grep -qE 'Re-dispatch all'; then
    pass "N>2 path offers 'Re-dispatch all'"
else
    fail "N>2 path missing 'Re-dispatch all'"
fi
if echo "$stuck_section" | grep -qE 'Skip all'; then
    pass "N>2 path offers 'Skip all'"
else
    fail "N>2 path missing 'Skip all'"
fi
if echo "$stuck_section" | grep -qE 'Walk one at a time'; then
    pass "N>2 path offers 'Walk one at a time' (per-marker fallback)"
else
    fail "N>2 path missing 'Walk one at a time'"
fi

# ── M4: Analysis 28 tolerates flat .decisions/<slug>.md layout ────────────

echo ""
echo "  M4 — Analysis 28 accepts flat .decisions/<slug>.md layout"
echo "  ──────────────────────────────────────────────────────"

# Find Analysis 28 decision_refs check
a28_decision=$(awk '/decision_refs → \.decisions/,/done < <\(fm "\$sfile".*decision_refs/' "$SCAN")

if echo "$a28_decision" | grep -qE '\.decisions/\$dref\.md'; then
    pass "Analysis 28 also checks .decisions/<slug>.md (flat layout)"
else
    fail "Analysis 28 still hardcodes grouped layout only"
fi

# LIVE test: build a fixture with flat-layout ADR and assert Analysis 28
# does NOT mark it as broken when referenced by a spec.
cleanup
mkdir -p "$TEST_DIR/.claude/scripts" "$TEST_DIR/.spec/registry" "$TEST_DIR/.spec/domains/test" "$TEST_DIR/.decisions" "$TEST_DIR/.curate"
cp "$SCAN" "$TEST_DIR/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$TEST_DIR/.claude/scripts/" 2>/dev/null || true

# Flat-layout ADR
cat > "$TEST_DIR/.decisions/flat-adr.md" <<'EOF'
---
status: accepted
date: 2026-05-11
---
# Flat layout ADR
EOF

# Spec referencing the flat ADR
cat > "$TEST_DIR/.spec/domains/test/foo.md" <<'EOF'
---
{"id":"test.foo","version":1,"state":"APPROVED","status":"ACTIVE","domains":["test"],"decision_refs":["flat-adr"],"kb_refs":[]}
---

# test.foo

## Requirements
R1. Test.

---

## Design Narrative
.
EOF

# Manifest
cat > "$TEST_DIR/.spec/registry/manifest.json" <<EOF
{
  "schema_version": 2,
  "specs": [
    {"id": "test.foo", "path": ".spec/domains/test/foo.md", "state": "APPROVED",
     "domains": ["test"], "decision_refs": ["flat-adr"], "kb_refs": []}
  ]
}
EOF

# Git fixture
cd "$TEST_DIR"
git init -q
git config user.email t@t.t
git config user.name t
git add -A
git commit -q -m "init"

# Run scan
bash .claude/scripts/curate-scan.sh --init >/dev/null 2>&1

# Check: Analysis 28 output should NOT list test.foo|decision_ref|flat-adr
# (it would, pre-fix, because the script only looked for flat-adr/adr.md).
if grep -q "SPEC_XREF.*flat-adr" .curate/scan-summary.md 2>/dev/null; then
    fail "Analysis 28 false-positives on flat-layout ADR"
else
    pass "Analysis 28 accepts flat-layout ADR (no false positive)"
fi

cd "$REPO_ROOT"

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "Total: $total | Passed: $passed | Failed: $failed"
echo ""

[[ $failed -eq 0 ]] && exit 0 || exit 1
