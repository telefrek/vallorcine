#!/usr/bin/env bash
# Scenario: audit wontfix obligations resurface via /curate analysis 19
#
# The audit skill's option-2 ("Accept as wontfix") handler logs a
# `wontfix: <finding-id> — <rationale>` obligation on the most-relevant
# spec. This scenario pins the contract with curate-scan.sh:
# - the wontfix: prefix must survive the aging-obligations pipeline
#   verbatim so /curate output distinguishes accepted-risk entries
#   from deferred work.
# - the spec's state stays APPROVED (wontfix is a landed design
#   decision, not a gap — unlike option-4 defer).
#
# Run from repo root: bash tests/scenario-audit-wontfix-obligation.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-audit-wontfix-obligation"

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

cleanup() {
    rm -rf "$TEST_BASE" 2>/dev/null || true
}
trap cleanup EXIT

if ! command -v jq >/dev/null 2>&1; then
    echo "scenario: audit wontfix obligation"
    echo "────────────────────────────────────────────────"
    echo "  SKIP  jq not available"
    exit 0
fi

echo ""
echo "scenario: audit wontfix obligation"
echo "────────────────────────────────────────────────"

# ── Setup: project with an APPROVED spec carrying an aged wontfix obligation ─
PROJECT="$TEST_BASE/project"
mkdir -p "$PROJECT/.claude/scripts"
mkdir -p "$PROJECT/.spec/registry" "$PROJECT/.spec/domains/widgets"

cp "$REPO_ROOT/scripts/curate-scan.sh" "$PROJECT/.claude/scripts/"

cat > "$PROJECT/.spec/registry/manifest.json" << 'REGEOF'
{
  "schema_version": 2,
  "generated_at": "2026-04-22",
  "spec_count": 1,
  "specs": [
    {"id": "widgets.spec-wontfix", "path": ".spec/domains/widgets/spec-wontfix.md", "state": "APPROVED", "domains": ["widgets"]}
  ]
}
REGEOF

# Spec stays APPROVED. The wontfix: obligation is non-blocking — a resurface hook,
# not a gap. Exactly what the audit skill's option-2 handler is documented to write.
cat > "$PROJECT/.spec/domains/widgets/spec-wontfix.md" << 'SPECEOF'
---
{
  "id": "widgets.spec-wontfix",
  "version": 1,
  "state": "APPROVED",
  "domains": ["widgets"],
  "open_obligations": [
    "wontfix: F-42 — external API contract pins this behavior; revisit on v2 migration"
  ]
}
---

# widgets.spec-wontfix — Widget with accepted-risk finding

## Requirements
R1. Widgets must exist.
SPECEOF

cd "$PROJECT"
git init -q --initial-branch=main .
git config user.email "test@test.com"
git config user.name "Test"

# Commit with an aged timestamp so analysis 19 flags the obligation.
OLD_DATE="$(date -d '60 days ago' '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -v-60d '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)"
git add .spec/registry/manifest.json .spec/domains/widgets/spec-wontfix.md
GIT_AUTHOR_DATE="$OLD_DATE" GIT_COMMITTER_DATE="$OLD_DATE" git commit -q -m "aged wontfix obligation"

output="$(bash .claude/scripts/curate-scan.sh --init 2>&1)"

# ── Test: Aging Open Obligations section appears ───────────────────────────
if grep -q "Aging Open Obligations" .curate/scan-summary.md; then
    pass "aging obligations section present"
else
    fail "aging obligations section should appear" "output: $output"
fi

aging_section="$(sed -n '/## Aging Open Obligations/,/^## /p' .curate/scan-summary.md)"

# ── Test: wontfix prefix preserved verbatim ────────────────────────────────
if echo "$aging_section" | grep -qF "wontfix: F-42"; then
    pass "wontfix: prefix and finding ID preserved verbatim"
else
    fail "scanner must not strip the wontfix: prefix" "section: $aging_section"
fi

# ── Test: rationale text preserved ─────────────────────────────────────────
if echo "$aging_section" | grep -qF "external API contract pins this behavior"; then
    pass "rationale text preserved"
else
    fail "rationale text must pass through untouched" "section: $aging_section"
fi

# ── Test: aged spec surfaces ───────────────────────────────────────────────
if echo "$aging_section" | grep -q "widgets.spec-wontfix"; then
    pass "aged spec ID surfaced"
else
    fail "widgets.spec-wontfix should appear in aging obligations" "section: $aging_section"
fi

# ── Test: spec stays APPROVED (not forced to DRAFT by wontfix) ─────────────
# Unlike option-4 "Defer to obligation", option-2 wontfix must NOT degrade
# spec state — the wontfix is a landed design decision, not a gap. The spec
# file's declared state must still read APPROVED.
spec_state="$(jq -r '.state' < <(awk '/^---$/{n++; next} n==1 && /^[[:space:]]*\{/{inj=1} n==1 && inj{print} n>=2{exit}' .spec/domains/widgets/spec-wontfix.md) 2>/dev/null || echo "?")"
if [[ "$spec_state" == "APPROVED" ]]; then
    pass "spec state remains APPROVED for wontfix (not forced to DRAFT)"
else
    fail "wontfix must not force spec to DRAFT" "state was: $spec_state"
fi

# ── Summary ────────────────────────────────────────────────────────────────
cd "$REPO_ROOT"
echo ""
echo "Passed: $passed / $total"
if [[ "$failed" -gt 0 ]]; then
    exit 1
fi
