#!/usr/bin/env bash
# Scenario: WD status updates must use `sed -i`, not `Edit`.
#
# The Edit tool requires the target file to be Read in the same session
# first. /work-plan and /work-start update WD status without otherwise
# needing the file's content, so an Edit instruction yields predictable
# "File has not been read yet" errors. The kit already uses
# `sed -i "s/^status:.*$/status: X/" <wd-file>` in
# `scripts/work-finalize.sh:80` for the equivalent operation; the skill
# prompts must mirror that pattern.
#
# Surfaced from the 2026-04-23 → 2026-04-27 jlsm session sweep —
# multiple edit-before-read errors traced to the three Edit-status
# instructions in /work-start and /work-plan.
#
# Run from repo root: bash tests/scenario-wd-status-update-no-edit.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

passed=0
failed=0
total=0

pass() {
    ((passed++)) || true
    ((total++)) || true
    echo "  PASS  $1"
}

fail() {
    ((failed++)) || true
    ((total++)) || true
    echo "  FAIL  $1"
    [[ -n "${2:-}" ]] && echo "        $2"
}

echo ""
echo "scenario: WD status updates must use sed -i (not Edit)"
echo "────────────────────────────────────────────────"

# ── Invariant 1: prohibited Edit-instruction pattern is absent ───────────────

echo ""
echo "── Invariant 1: no 'Edit .work/<group>/WD-<nn>.md — set status:' instructions"

# This is a literal pattern the bug PR removed. If reintroduced (typically
# via copy-paste from older docs), the prompt will fail at runtime when the
# assistant follows the instruction without first reading the file.
check_no_edit_status() {
    local file="$1"
    local name="$2"
    # Match the prose form: `Edit \`.work/...WD...\` — set \`status:`
    # (curly em-dash and ASCII hyphens both, defensively).
    if grep -nE 'Edit \`\.work/.*WD-.*\.md\`.*[—-].*set \`status:' "$file" >/dev/null 2>&1; then
        local hits
        hits="$(grep -nE 'Edit \`\.work/.*WD-.*\.md\`.*[—-].*set \`status:' "$file" | cut -d: -f1 | tr '\n' ' ')"
        fail "$name: contains Edit-status instruction" \
             "lines: $hits — replace with: sed -i \"s/^status:.*\\\$/status: <NEW>/\" <wd-file>"
    else
        pass "$name: no Edit-status instructions"
    fi
}

check_no_edit_status "$REPO_ROOT/skills/work-start/SKILL.md" "/work-start"
check_no_edit_status "$REPO_ROOT/skills/work-plan/SKILL.md" "/work-plan"

# ── Invariant 2: required sed-i pattern is present in each file ──────────────

echo ""
echo "── Invariant 2: sed -i status-update pattern is present"

# The replacement form. Each skill that updates WD status must use the
# `sed -i "s/^status:.*$/status: X/"` shape so it matches what
# scripts/work-finalize.sh:80 already does.
check_has_sed_status() {
    local file="$1"
    local name="$2"
    local expected_state="$3"
    if grep -qE "sed -i \"s/\^status:.\*\\\$/status: ${expected_state}/\"" "$file"; then
        pass "$name: uses sed -i for status: $expected_state"
    else
        fail "$name: missing sed -i status update for $expected_state" \
             "expected: sed -i \"s/^status:.*\\\$/status: ${expected_state}/\" .work/<group-slug>/WD-<nn>.md"
    fi
}

check_has_sed_status "$REPO_ROOT/skills/work-start/SKILL.md"  "/work-start" "IMPLEMENTING"
check_has_sed_status "$REPO_ROOT/skills/work-plan/SKILL.md"   "/work-plan"  "SPECIFYING"
check_has_sed_status "$REPO_ROOT/skills/work-plan/SKILL.md"   "/work-plan"  "SPECIFIED"

# ── Invariant 3: precedent script still uses the same pattern ────────────────

echo ""
echo "── Invariant 3: scripts/work-finalize.sh precedent unchanged"

# If the precedent moves, the skill prompts should too — flagging here
# means the skill prompts may have drifted from the script's actual pattern.
finalize="$REPO_ROOT/scripts/work-finalize.sh"
if grep -qF 'sed -i "s/^status:.*$/status: COMPLETE/"' "$finalize"; then
    pass "scripts/work-finalize.sh still sets status via sed -i (precedent)"
else
    fail "scripts/work-finalize.sh precedent missing or changed" \
         "if the script's pattern moved, update both the script and the skill prompts together"
fi

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
