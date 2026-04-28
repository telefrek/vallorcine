#!/usr/bin/env bash
# Scenario: /curate --verify mode (structural).
#
# Validates that the curate SKILL.md prompt declares the --verify flag,
# describes the verify-mode branch (skips correlation, focuses on
# verification-shaped candidates), documents the dismissed-state file at
# .curate/verify-dismissed.txt, and routes both link-rot and
# falsification-staleness candidates to the right repair commands.
#
# Layered cover:
#
#   1. Frontmatter argument-hint advertises --verify.
#   2. The flags list documents --verify and --analysis.
#   3. A "Verify mode" section exists at the top of the skill.
#   4. The verify-mode branch (Step 1.5 or equivalent) describes the
#      filter to subsections 2p + 2q only.
#   5. The dismissed-state file path .curate/verify-dismissed.txt is
#      documented with a row format that includes analysis name + key.
#   6. Link-rot routing in verify mode includes a "Dismiss" option AND
#      writes to the dismissed file.
#   7. Falsification-stale routing in verify mode includes a "Dismiss"
#      option AND writes to the dismissed file.
#   8. The skill explicitly states that verify mode does NOT change the
#      scan invocation (the script still runs all analyses).
#   9. The --analysis filter values include link-rot, falsification-stale,
#      and all.
#
# Behavioral correctness — does the model actually filter the pick list
# and skip non-verify subsections in practice — is exercised manually,
# since it depends on the LLM's interpretation of the prompt.
#
# Run from repo root: bash tests/scenario-curate-verify-routing.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

SKILL="$REPO_ROOT/skills/curate/SKILL.md"

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
echo "scenario: /curate --verify mode (structural)"
echo "────────────────────────────────────────────────"

# ── Layer 1: argument-hint includes --verify ───────────────────────────────

echo ""
echo "── Layer 1: argument-hint advertises --verify"

argument_hint=$(grep -E '^argument-hint:' "$SKILL" | head -1)
if [[ -z "$argument_hint" ]]; then
  fail "no argument-hint in curate SKILL.md"
elif echo "$argument_hint" | grep -q '\-\-verify'; then
  pass "argument-hint includes --verify"
else
  fail "argument-hint missing --verify" "$argument_hint"
fi

# ── Layer 2: flags list documents --verify and --analysis ──────────────────

echo ""
echo "── Layer 2: flags list documents --verify and --analysis"

if grep -qE '^- `--verify`' "$SKILL"; then
  pass "flags list documents --verify"
else
  fail "flags list missing --verify entry"
fi

if grep -qE '^- `--analysis' "$SKILL"; then
  pass "flags list documents --analysis"
else
  fail "flags list missing --analysis entry"
fi

# ── Layer 3: Verify mode section exists ────────────────────────────────────

echo ""
echo "── Layer 3: 'Verify mode' section exists"

if grep -qE '^## Verify mode' "$SKILL"; then
  pass "## Verify mode section present"
else
  fail "## Verify mode section missing"
fi

# ── Layer 4: verify-mode branch filters to 2p and 2q ──────────────────────

echo ""
echo "── Layer 4: verify-mode branch filters Step 2 to 2p + 2q only"

# Look for the branch block by name (Step 1.5 or any heading mentioning
# verify-mode branching).
branch_block=$(awk '
  /^## (Step 1\.5|.*[Vv]erify-mode branch)/ { capturing=1; print; next }
  capturing && /^## / { exit }
  capturing { print }
' "$SKILL")

if [[ -z "$branch_block" ]]; then
  fail "no Step 1.5 / verify-mode branch section found"
else
  if echo "$branch_block" | grep -qE '2p.*2q|2p.*falsification|link.rot.*falsification' ; then
    pass "branch section names the 2p/2q filter"
  else
    fail "branch section does not name 2p (link rot) and 2q (falsification staleness)"
  fi
fi

# ── Layer 5: dismissed-state file documented ───────────────────────────────

echo ""
echo "── Layer 5: dismissed-state file path and format documented"

if grep -q '\.curate/verify-dismissed\.txt' "$SKILL"; then
  pass ".curate/verify-dismissed.txt path is documented"
else
  fail ".curate/verify-dismissed.txt not referenced anywhere"
fi

# Format hint: should mention <analysis>|<key>|<date> shape (or similar
# pipe-delimited layout).
if grep -qE 'link-rot\|.*\|.*\||falsification-stale\|.*:' "$SKILL"; then
  pass "dismissed-state row format is documented"
else
  fail "dismissed-state row format not explicit"
fi

# ── Layer 6: link-rot dismiss option in verify mode ────────────────────────

echo ""
echo "── Layer 6: link-rot routing in verify mode includes Dismiss"

# Find the link-rot routing block in Step 4. It starts at "**Link rot in KB entry:**"
linkrot_block=$(awk '
  /\*\*Link rot in KB entry:\*\*/ { capturing=1; print; next }
  capturing && /^\*\*[A-Z]/ { exit }
  capturing { print }
' "$SKILL")

if [[ -z "$linkrot_block" ]]; then
  fail "no Link rot routing block found in Step 4"
else
  if echo "$linkrot_block" | grep -qE '"Dismiss"' ; then
    pass "link-rot routing includes Dismiss option"
  else
    fail "link-rot routing missing Dismiss option"
  fi

  if echo "$linkrot_block" | grep -qE 'verify-dismissed\.txt'; then
    pass "link-rot Dismiss writes to verify-dismissed.txt"
  else
    fail "link-rot Dismiss action does not reference verify-dismissed.txt"
  fi
fi

# ── Layer 7: falsification-stale dismiss option in verify mode ─────────────

echo ""
echo "── Layer 7: falsification-stale routing in verify mode includes Dismiss"

fals_block=$(awk '
  /\*\*Falsification-lens staleness candidate:\*\*/ { capturing=1; print; next }
  capturing && /^\*\*[A-Z]/ { exit }
  capturing && /^### / { exit }
  capturing { print }
' "$SKILL")

if [[ -z "$fals_block" ]]; then
  fail "no Falsification-lens staleness routing block found in Step 4"
else
  if echo "$fals_block" | grep -qE '"Dismiss"' ; then
    pass "falsification-stale routing includes Dismiss option"
  else
    fail "falsification-stale routing missing Dismiss option"
  fi

  if echo "$fals_block" | grep -qE 'verify-dismissed\.txt'; then
    pass "falsification-stale Dismiss writes to verify-dismissed.txt"
  else
    fail "falsification-stale Dismiss does not reference verify-dismissed.txt"
  fi
fi

# ── Layer 8: verify mode does NOT change scan invocation ───────────────────

echo ""
echo "── Layer 8: verify mode does NOT change scan invocation"

if grep -qE 'verify.*does NOT change the scan|--verify flag does NOT|verify does not change the scan' "$SKILL"; then
  pass "scan-invariance under --verify is documented"
else
  fail "no statement that --verify does not change the scan invocation"
fi

# ── Layer 9: --analysis filter values ──────────────────────────────────────

echo ""
echo "── Layer 9: --analysis filter values are explicit"

if grep -qE 'link-rot' "$SKILL" && grep -qE 'falsification-stale' "$SKILL"; then
  pass "--analysis values include link-rot and falsification-stale"
else
  fail "--analysis values not fully documented"
fi

# Look for 'all' in --analysis context (default value).
if grep -qE '\-\-analysis.*all|all \(default\)|default: `all`|or `all`' "$SKILL"; then
  pass "--analysis 'all' default is documented"
else
  fail "--analysis 'all' default not documented"
fi

# ── Summary ────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
if [[ $failed -eq 0 ]]; then
  echo "ALL PASSED  ($passed/$total)"
  exit 0
else
  echo "FAILED  $failed/$total  ($passed passed)"
  exit 1
fi
