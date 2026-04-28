#!/usr/bin/env bash
# Scenario: /spec-author --depth-pass-only mode (structural).
#
# Validates that the spec-author skill prompt includes the depth-pass-only
# entry path with all the load-bearing instructions: argument-hint mentions
# the flag, a dedicated "Depth-pass-only mode" section exists, the spec
# state check is documented, lens validation is documented, the link to
# Pass 3 is present, and the kit's lens-registry references lens names
# that have corresponding lens-*.md prompt files (cross-kit consistency).
#
# Layered cover:
#
#   1. Frontmatter argument-hint declares --depth-pass-only.
#   2. SKILL.md has a "## Depth-pass-only mode" section.
#   3. The mode section requires APPROVED state (refuses DRAFT).
#   4. The mode section documents --lens validation against the registry.
#   5. The mode section explains the Pass 1 + Pass 2 skip.
#   6. The mode section explains Pass 3 input adaptation (full spec body,
#      empty prior-findings).
#   7. Pass 3 section cross-references the depth-pass-only entry path.
#   8. lens-registry.txt names match lens-*.md prompt files (no orphans
#      in either direction).
#   9. The decline routing back to /curate is documented.
#
# Behavioral correctness (does the model actually follow the prompt and
# skip Pass 1/2 correctly?) is exercised manually — it requires running
# /spec-author against a real APPROVED spec, which is outside the scope
# of a fast scenario test.
#
# Run from repo root: bash tests/scenario-spec-author-depth-pass-only.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

SKILL="$REPO_ROOT/skills/spec-author/SKILL.md"
LENS_REGISTRY="$REPO_ROOT/scripts/lens-registry.txt"
PROMPTS_DIR="$REPO_ROOT/prompts/audit"

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
echo "scenario: /spec-author --depth-pass-only mode"
echo "────────────────────────────────────────────────"

# ── Layer 1: argument-hint ──────────────────────────────────────────────────

echo ""
echo "── Layer 1: frontmatter argument-hint advertises the flag"

argument_hint=$(grep -E '^argument-hint:' "$SKILL" | head -1)
if [[ -z "$argument_hint" ]]; then
  fail "no argument-hint in spec-author SKILL.md"
elif echo "$argument_hint" | grep -q '\-\-depth-pass-only'; then
  pass "argument-hint includes --depth-pass-only"
else
  fail "argument-hint missing --depth-pass-only" "$argument_hint"
fi

if echo "$argument_hint" | grep -q '\-\-lens'; then
  pass "argument-hint includes --lens"
else
  fail "argument-hint missing --lens" "$argument_hint"
fi

# ── Layer 2: dedicated section exists ──────────────────────────────────────

echo ""
echo "── Layer 2: 'Depth-pass-only mode' section exists"

if grep -q '^## Depth-pass-only mode' "$SKILL"; then
  pass "## Depth-pass-only mode section present"
else
  fail "missing ## Depth-pass-only mode section"
fi

# ── Layer 3: APPROVED state requirement documented ─────────────────────────

echo ""
echo "── Layer 3: APPROVED state requirement documented"

if grep -qiE 'must be APPROVED|state.*APPROVED|state is not APPROVED|refuse.*DRAFT' "$SKILL"; then
  pass "APPROVED state precondition is documented"
else
  fail "no documentation that the target spec must be APPROVED"
fi

# ── Layer 4: lens validation against registry ──────────────────────────────

echo ""
echo "── Layer 4: lens validation references the registry"

if grep -q 'lens-registry.txt' "$SKILL"; then
  pass "SKILL.md references lens-registry.txt"
else
  fail "SKILL.md does not reference lens-registry.txt"
fi

if grep -qE 'prompts/audit/lens-' "$SKILL"; then
  pass "SKILL.md references lens prompt path layout"
else
  fail "SKILL.md does not document lens prompt path"
fi

# ── Layer 5: Pass 1 + Pass 2 skip is documented ───────────────────────────

echo ""
echo "── Layer 5: Pass 1 + Pass 2 skip is documented"

if grep -qE 'Skip Pass 1|skips Pass 1|skip.*Pass 2|Skip Pass 2' "$SKILL"; then
  pass "Pass 1 / Pass 2 skip is documented"
else
  fail "no documentation that Pass 1 + Pass 2 are skipped"
fi

# ── Layer 6: Pass 3 input adaptation ──────────────────────────────────────

echo ""
echo "── Layer 6: Pass 3 input adaptation documented"

if grep -qE 'empty prior-findings|empty prior findings|prior-findings set|prior findings set' "$SKILL"; then
  pass "empty prior-findings adaptation documented"
else
  fail "no documentation that prior-findings is empty for depth-pass-only"
fi

# ── Layer 7: Pass 3 section cross-references depth-pass-only ──────────────

echo ""
echo "── Layer 7: Pass 3 section cross-references depth-pass-only"

# Find the Pass 3 section body (between '## Pass 3' and the next sibling
# heading that isn't itself '## Pass 3'). Awk's `,` range matches both
# endpoints, so we filter explicitly.
pass3_block=$(awk '
  /^## Pass 3/ { capturing=1; print; next }
  capturing && /^## / { exit }
  capturing { print }
' "$SKILL")
if echo "$pass3_block" | grep -q 'depth-pass-only'; then
  pass "Pass 3 section cross-references the depth-pass-only entry"
else
  fail "Pass 3 section does not cross-reference depth-pass-only" \
       "first 5 lines: $(echo "$pass3_block" | head -5)"
fi

# ── Layer 8: lens-registry ↔ prompts cross-consistency ─────────────────────

echo ""
echo "── Layer 8: lens-registry lens names align with prompts/audit/lens-*.md"

if [[ ! -f "$LENS_REGISTRY" ]]; then
  fail "lens-registry.txt missing at $LENS_REGISTRY"
elif [[ ! -d "$PROMPTS_DIR" ]]; then
  fail "prompts/audit dir missing at $PROMPTS_DIR"
else
  registry_lenses=$(grep -vE '^[[:space:]]*(#|$)' "$LENS_REGISTRY" \
                    | cut -d'|' -f1 | sort -u)
  prompt_lenses=$(find "$PROMPTS_DIR" -maxdepth 1 -name 'lens-*.md' -type f \
                  -printf '%f\n' 2>/dev/null \
                  | sed -E 's/^lens-(.*)\.md$/\1/' | sort -u)

  missing_prompt=""
  while IFS= read -r lens; do
    [[ -z "$lens" ]] && continue
    if ! echo "$prompt_lenses" | grep -qx "$lens"; then
      missing_prompt="${missing_prompt}${lens} "
    fi
  done <<< "$registry_lenses"

  if [[ -z "$missing_prompt" ]]; then
    pass "every lens in registry has a corresponding prompts/audit/lens-*.md"
  else
    fail "registry lenses without matching prompt file: $missing_prompt"
  fi

  # Also flag prompt files with no registry entry — they're either
  # not-yet-shipped or dead. Soft assertion (not a fail; just a note).
  while IFS= read -r lens; do
    [[ -z "$lens" ]] && continue
    if ! echo "$registry_lenses" | grep -qx "$lens"; then
      echo "  NOTE  prompts/audit/lens-${lens}.md has no registry entry"
    fi
  done <<< "$prompt_lenses"
fi

# ── Layer 9: decline routing documented ────────────────────────────────────

echo ""
echo "── Layer 9: decline routing back to /curate documented"

if grep -qE 'falsification-decline|decline.*curate|curate.*decline' "$SKILL"; then
  pass "decline-back-to-curate routing documented"
else
  fail "no documentation of decline routing back to /curate"
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
