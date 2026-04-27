#!/usr/bin/env bash
# Scenario: /spec-author Pass 2/3 awareness of layered specs.
#
# Validates the PR 4 piece of the spec-layering plan: spec-author's prompt
# must instruct the LLM to (a) load the parent + siblings when amending a
# child spec (sibling-aware adversarial review), and (b) surface a
# just-in-time subdivision signal when a Pass 2 amendment tips the spec
# into "multiple distinct concerns at scale" territory.
#
# These are prose-level prompt invariants — the LLM does the actual work
# at runtime. Tests here are structural drift detection: the SKILL.md
# must contain the right instructions so an LLM following them produces
# the right behavior.
#
# Layered cover:
#
#   1. Pre-flight has a "Layered-spec family load" step that triggers on
#      `parent_spec` + sets `INCLUDE_SIBLINGS=true` on spec-resolve.
#   2. Pre-flight skips the family load when target is a top-level spec.
#   3. JIT subdivision signal step exists between Pass 2 arbitration and
#      Pass 3, with the same thresholds /curate uses (≥50 reqs OR ≥15K
#      tokens, ≥2 sections, largest <90% of total).
#   4. JIT signal explicitly marks itself as non-blocking — the user
#      should know this is informational.
#   5. JIT signal surfaces the concrete `/spec-split <spec-id>` command.
#
# Run from repo root: bash tests/scenario-spec-author-layered.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

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
echo "scenario: /spec-author awareness of layered specs"
echo "────────────────────────────────────────────────"

SA="$REPO_ROOT/skills/spec-author/SKILL.md"

if [[ ! -f "$SA" ]]; then
  fail "spec-author SKILL.md not found at $SA"
  exit 1
fi

# ── Layer 1: Pre-flight has a layered-spec family load step ─────────────────

echo ""
echo "── Layer 1: Pre-flight loads parent + siblings on child specs"

if grep -qF "Layered-spec family load" "$SA"; then
  pass "Pre-flight has 'Layered-spec family load' step"
else
  fail "Pre-flight missing 'Layered-spec family load' step"
fi

if grep -qF "INCLUDE_SIBLINGS=true" "$SA"; then
  pass "INCLUDE_SIBLINGS=true is referenced in pre-flight"
else
  fail "INCLUDE_SIBLINGS=true not referenced in pre-flight"
fi

if grep -qF "EXPLICIT_SPEC_IDS=" "$SA"; then
  pass "EXPLICIT_SPEC_IDS targeting the spec is in the resolver invocation"
else
  fail "EXPLICIT_SPEC_IDS not in the resolver invocation"
fi

# ── Layer 2: Top-level spec exits the family-load step early ────────────────

echo ""
echo "── Layer 2: top-level specs skip the family-load step"

if grep -qE "If the target is a top-level spec.*skip" "$SA"; then
  pass "skill instructs skipping family load for top-level specs"
else
  fail "no skip-instruction for top-level specs"
fi

# ── Layer 3: JIT subdivision signal step exists ─────────────────────────────

echo ""
echo "── Layer 3: JIT subdivision signal between Pass 2 arbitration and Pass 3"

if grep -qF "Just-in-time subdivision signal" "$SA"; then
  pass "JIT subdivision signal section is present"
else
  fail "JIT subdivision signal section missing"
fi

# Section ordering: the signal must come AFTER "Pass 2 — Adversarial
# falsification" and BEFORE "Pass 3 — Depth pass".
pass2_line=$(grep -n "^## Pass 2 — Adversarial falsification" "$SA" | head -1 | cut -d: -f1 || true)
jit_line=$(grep -n "Just-in-time subdivision signal" "$SA" | head -1 | cut -d: -f1 || true)
pass3_line=$(grep -n "^## Pass 3 — Depth pass" "$SA" | head -1 | cut -d: -f1 || true)

if [[ -n "$pass2_line" && -n "$jit_line" && -n "$pass3_line" ]] && \
   (( pass2_line < jit_line && jit_line < pass3_line )); then
  pass "JIT signal lives between Pass 2 and Pass 3 (lines $pass2_line < $jit_line < $pass3_line)"
else
  fail "JIT signal misplaced" \
       "Pass 2: $pass2_line, JIT: $jit_line, Pass 3: $pass3_line"
fi

# ── Layer 4: JIT thresholds match /curate's heuristic ───────────────────────

echo ""
echo "── Layer 4: thresholds match /curate's subdivision detector"

# The skill must reference the same thresholds /curate uses so that what
# /spec-author surfaces matches what /curate would flag.
jit_block=$(awk '
  /Just-in-time subdivision signal/ { in_block = 1 }
  in_block { print }
  in_block && /^## Pass 3/ { exit }
' "$SA")

for threshold_phrase in \
  "Reqs ≥ 50" \
  "≥ ~15K tokens" \
  "Section count ≥ 2" \
  "Largest section.*share < 90%" \
  "parent_spec.*set"; do
  if echo "$jit_block" | grep -qE "$threshold_phrase"; then
    pass "threshold mentioned: $threshold_phrase"
  else
    fail "threshold missing: $threshold_phrase"
  fi
done

# ── Layer 5: JIT signal is explicitly non-blocking ──────────────────────────

echo ""
echo "── Layer 5: JIT signal explicitly non-blocking"

if echo "$jit_block" | grep -qE "non-blocking|not a blocker|heads-up"; then
  pass "JIT signal explicitly marked non-blocking"
else
  fail "JIT signal not explicitly marked non-blocking" \
       "expected one of: 'non-blocking', 'not a blocker', 'heads-up'"
fi

if echo "$jit_block" | grep -qF "/spec-split <spec-id>"; then
  pass "JIT signal includes /spec-split <spec-id> as the suggested action"
else
  fail "JIT signal missing /spec-split command suggestion"
fi

# ── Layer 6: skill files still parse cleanly ───────────────────────────────

echo ""
echo "── Layer 6: skill prompts still pass basic structural checks"

# Check the skill still has the key markers — Pass 1, Pass 2, Pass 3 — so
# we didn't accidentally break the structure while adding the new sections.
for marker in "## Pre-flight" "## Pass 1" "## Pass 2" "## Pass 3" "## Hard constraints"; do
  if grep -qF "$marker" "$SA"; then
    pass "skill structure preserved: $marker"
  else
    fail "skill structure broken: $marker is missing"
  fi
done

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
if [[ $failed -eq 0 ]]; then
  echo "ALL PASSED  ($passed/$total)"
  exit 0
else
  echo "FAILED  $failed/$total  ($passed passed)"
  exit 1
fi
