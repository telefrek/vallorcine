#!/usr/bin/env bash
# Scenario: security lens is wired into the audit pipeline.
#
# Validates:
# - prompts/audit/lens-security.md exists in the kit
# - MANIFEST lists it
# - install.sh installs it (via existing prompts/audit/*.md glob)
# - assembly.md's Domain-specific analysis guidance references it
# - suspect.md tells the subagent to read it when security concerns apply
# - exploration.md's domain-signal table covers the new signals
#   (credential store, PII, auth middleware, deserialization/parser)
# - lens-security.md has the expected structure (testability taxonomy,
#   attack patterns grouped by concern number, output format)
#
# Run from repo root: bash tests/scenario-audit-lens-security.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-audit-lens-security"

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

echo ""
echo "scenario: audit security lens"
echo "────────────────────────────────────────────────"

# ── Existence + MANIFEST ────────────────────────────────────────────────────

echo ""
echo "  Existence and MANIFEST"
echo "  ──────────────────────"

lens_file="$REPO_ROOT/prompts/audit/lens-security.md"
if [[ -f "$lens_file" ]]; then
    pass "lens-security.md exists"
else
    fail "lens-security.md is missing"
fi

if grep -qF ".claude/prompts/audit/lens-security.md" "$REPO_ROOT/MANIFEST"; then
    pass "MANIFEST lists lens-security.md"
else
    fail "MANIFEST missing lens-security.md entry"
fi

# ── Structural sections of the lens file ────────────────────────────────────

echo ""
echo "  Lens file structure"
echo "  ───────────────────"

if grep -q "^## Testability taxonomy" "$lens_file"; then
    pass "has Testability taxonomy section"
else
    fail "missing Testability taxonomy section"
fi

if grep -q "TESTABLE" "$lens_file" && grep -q "ADVISORY" "$lens_file"; then
    pass "distinguishes TESTABLE vs ADVISORY findings"
else
    fail "missing TESTABLE/ADVISORY distinction"
fi

for concern in "Information flow" "Auth / authorization" "Injection" "Cryptographic misuse" "Configuration / environment"; do
    if grep -qF "$concern" "$lens_file"; then
        pass "attack patterns cover '$concern'"
    else
        fail "missing attack patterns for '$concern'"
    fi
done

# Specific security patterns that generic lenses miss
for pattern in "IV / nonce reuse" "Timing channel" "Key material not zeroed" "JWT without signature" "class whitelist"; do
    if grep -qF "$pattern" "$lens_file"; then
        pass "covers specific pattern: '$pattern'"
    else
        fail "missing pattern: '$pattern'"
    fi
done

# Output format guidance
if grep -q "security_concern" "$lens_file" \
   && grep -q "attack_surface" "$lens_file" \
   && grep -q "adversary_model" "$lens_file"; then
    pass "output format spec includes structured fields"
else
    fail "output format fields missing"
fi

# ── Integration: assembly.md references the lens ────────────────────────────

echo ""
echo "  Integration"
echo "  ───────────"

if grep -qF "lens-security.md" "$REPO_ROOT/prompts/audit/assembly.md"; then
    pass "assembly.md references lens-security.md"
else
    fail "assembly.md missing lens-security.md reference"
fi

if grep -q "\*\*Security:\*\*" "$REPO_ROOT/prompts/audit/assembly.md"; then
    pass "assembly.md has 'Security' domain-specific guidance"
else
    fail "assembly.md missing Security lens guidance block"
fi

if grep -qF "lens-security.md" "$REPO_ROOT/prompts/audit/suspect.md"; then
    pass "suspect.md references lens-security.md"
else
    fail "suspect.md missing lens-security.md reference"
fi

# ── Integration: exploration.md covers new signals ──────────────────────────

echo ""
echo "  New domain signals in exploration.md"
echo "  ────────────────────────────────────"

for signal in "Credential store" "PII handling" "Auth middleware" "Deserialization"; do
    if grep -qF "$signal" "$REPO_ROOT/prompts/audit/exploration.md"; then
        pass "exploration.md covers signal: '$signal'"
    else
        fail "exploration.md missing signal: '$signal'"
    fi
done

# ── Install-path coverage: fresh install includes the lens ──────────────────

echo ""
echo "  Install wiring"
echo "  ──────────────"

cleanup
mkdir -p "$TEST_BASE/project"
cd "$TEST_BASE/project"
git init -q 2>&1 >/dev/null

if bash "$REPO_ROOT/install.sh" "$TEST_BASE/project" >/dev/null 2>&1; then
    if [[ -f "$TEST_BASE/project/.claude/prompts/audit/lens-security.md" ]]; then
        pass "install.sh installs lens-security.md"
    else
        fail "install.sh did not install lens-security.md"
    fi
else
    fail "install.sh failed for test project"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
if [[ $failed -eq 0 ]]; then
    echo "ALL PASSED  ($passed/$total)"
else
    echo "FAILED  $failed/$total  ($passed passed)"
fi
echo ""

exit $failed
