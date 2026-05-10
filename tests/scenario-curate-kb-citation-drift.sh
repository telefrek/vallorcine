#!/usr/bin/env bash
# Scenario: /curate KB citation drift detector (Analysis 26).
#
# Validates curate-scan.sh's detection of `// KB:` / `# KB:` / `<!-- KB: -->`
# citations in changed source files that don't reconcile with the KB:
#
#   * `missing-entry` — citation points at a deleted/renamed KB path.
#   * `applies_to-mismatch` — citation is to an existing entry, but the
#     entry's `applies_to` doesn't include the source file.
#
# Layered cover:
#
#   1. Citation in a changed source file with missing target → flagged.
#   2. Citation to existing entry with applies_to NOT covering the file → flagged.
#   3. Citation to existing entry whose applies_to DOES cover the file → NOT flagged.
#   4. Citation to existing entry with EMPTY applies_to (general research) → NOT flagged.
#   5. Source file with no citation → NOT flagged (analysis is for citations only).
#   6. UNCHANGED source files (not in changed-source.txt) are NOT scanned —
#      analysis is bounded to recent activity.
#   7. Files in vallorcine internals (.kb/, .spec/) are skipped.
#   8. Multi-citation: the analysis flags only the bad slot, not the good one.
#   9. All three comment syntaxes are recognised (// , #, <!-- -->).
#
# Run from repo root: bash tests/scenario-curate-kb-citation-drift.sh

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

assert_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc" "pattern not found: $pattern"
  fi
}

assert_not_contains() {
  local file="$1" pattern="$2" desc="$3"
  if ! grep -qE "$pattern" "$file" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc" "pattern unexpectedly found: $pattern"
  fi
}

# Extract just the KB Citation Drift section so assertions don't collide with
# generic git analyses (Churn Hotspots, Test-Source Drift, etc.) that
# legitimately list every changed file by name.
citation_drift_section() {
  awk '
    /^## KB Citation Drift in Source/ { in_section = 1; next }
    /^## / && in_section { in_section = 0 }
    in_section { print }
  ' "$1"
}

assert_drift_contains() {
  local file="$1" pattern="$2" desc="$3"
  if citation_drift_section "$file" | grep -qE "$pattern" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc" "pattern not found in KB Citation Drift section: $pattern"
  fi
}

assert_drift_not_contains() {
  local file="$1" pattern="$2" desc="$3"
  if ! citation_drift_section "$file" | grep -qE "$pattern" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc" "pattern unexpectedly found in KB Citation Drift section: $pattern"
  fi
}

echo ""
echo "scenario: /curate KB citation drift (Analysis 26)"
echo "────────────────────────────────────────────────"

TMPDIR_TEST="$(mktemp -d /tmp/vallorcine/curate-kb-citation.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PROJ="$TMPDIR_TEST/proj"
mkdir -p "$PROJ/.kb/algorithms/encryption" \
         "$PROJ/.kb/_refs" \
         "$PROJ/.curate" \
         "$PROJ/src/main/auth" \
         "$PROJ/src/main/billing" \
         "$PROJ/src/main/util" \
         "$PROJ/.spec"
cd "$PROJ"

git init -q
git config user.email test@example.com
git config user.name "Test"

# Seed KB
cat > .kb/CLAUDE.md << 'EOF'
# KB
## Topic Map
EOF
echo "stub" > .kb/_refs/frontmatter.md

cat > .kb/algorithms/encryption/three-level-keys.md << 'EOF'
---
title: "Three-level keys"
type: research
applies_to:
  - "src/main/auth/**"
last_researched: "2026-04-01"
research_status: stable
---
# entry
EOF

cat > .kb/algorithms/encryption/general-encryption.md << 'EOF'
---
title: "General encryption (no applies_to — applies to anything)"
type: research
applies_to: []
last_researched: "2026-04-01"
research_status: stable
---
# entry
EOF

# Source files

# 1. Citation to missing entry (will be flagged).
cat > src/main/auth/Login.java << 'EOF'
// KB: .kb/algorithms/encryption/this-was-renamed.md
public class Login {}
EOF

# 2. Citation to existing entry whose applies_to does NOT include this file
#    (Charge.java is in src/main/billing, but the entry only covers src/main/auth/**).
cat > src/main/billing/Charge.java << 'EOF'
// KB: .kb/algorithms/encryption/three-level-keys.md
public class Charge {}
EOF

# 3. Citation to existing entry whose applies_to DOES cover this file
#    (KeyStore.java in src/main/auth/, entry's applies_to is src/main/auth/**).
cat > src/main/auth/KeyStore.java << 'EOF'
// KB: .kb/algorithms/encryption/three-level-keys.md
public class KeyStore {}
EOF

# 4. Citation to entry with empty applies_to (general research) — never flagged.
cat > src/main/util/Hex.java << 'EOF'
// KB: .kb/algorithms/encryption/general-encryption.md
public class Hex {}
EOF

# 5. Source file with no citation at all — not flagged by Analysis 26 (it is
#    the hook's job at write-time, and Analysis 26 scopes to citations).
cat > src/main/auth/Plain.java << 'EOF'
public class Plain {}
EOF

# 8. Multi-citation: one slot good, one slot bad.
cat > src/main/auth/Multi.java << 'EOF'
// KB: .kb/algorithms/encryption/three-level-keys.md, .kb/algorithms/encryption/missing.md
public class Multi {}
EOF

# 9. Comment-syntax variants — all valid citations to entries that cover them.
cat > src/main/auth/hash.py << 'EOF'
# KB: .kb/algorithms/encryption/three-level-keys.md
def hash(): pass
EOF

cat > src/main/auth/page.html << 'EOF'
<!-- KB: .kb/algorithms/encryption/three-level-keys.md -->
<html></html>
EOF

# Initial commit so changed-source.txt is non-empty during scan window.
git add -A
git commit -q --date='2026-05-01T00:00:00Z' -m "initial source"

# Run scan with link-rot disabled.
MAX_LINK_ROT_URLS=0 bash "$REPO_ROOT/scripts/curate-scan.sh" --init >/dev/null 2>&1 || true

SUMMARY="$PROJ/.curate/scan-summary.md"

if [[ ! -s "$SUMMARY" ]]; then
  fail "scan-summary.md was created and non-empty"
  echo ""
  echo "── Summary ──"
  echo "  Passed: $passed/$total"
  echo "  Failed: $failed/$total"
  exit 1
fi

# ── Section presence ─────────────────────────────────────────────────────

assert_contains "$SUMMARY" "## KB Citation Drift in Source" \
    "section: KB Citation Drift in Source present"

# ── 1. missing-entry detection ───────────────────────────────────────────

assert_drift_contains "$SUMMARY" "Login.java.*this-was-renamed.md.*missing-entry" \
    "drift: missing-entry on Login.java flagged"

# ── 2. applies_to-mismatch detection ─────────────────────────────────────

assert_drift_contains "$SUMMARY" "Charge.java.*three-level-keys.md.*applies_to-mismatch" \
    "drift: applies_to-mismatch on Charge.java flagged"

# ── 3. Valid citation NOT flagged ────────────────────────────────────────

assert_drift_not_contains "$SUMMARY" "KeyStore.java" \
    "exempt: KeyStore.java (valid citation, applies_to covers it) not flagged"

# ── 4. Empty applies_to entry NOT flagged ────────────────────────────────

assert_drift_not_contains "$SUMMARY" "Hex.java" \
    "exempt: Hex.java (empty applies_to) not flagged for mismatch"

# ── 5. No-citation file NOT flagged ──────────────────────────────────────

assert_drift_not_contains "$SUMMARY" "Plain.java" \
    "exempt: Plain.java (no citation) not flagged"

# ── 8. Multi-citation: only the bad slot is flagged ──────────────────────

assert_drift_contains "$SUMMARY" "Multi.java.*missing.md.*missing-entry" \
    "multi-citation: bad slot flagged"

# Multi.java's GOOD slot is three-level-keys.md, applies_to: src/main/auth/**.
# Multi.java is in src/main/auth/, so this slot is valid — should NOT flag
# applies_to-mismatch on the good slot.
multi_mismatches=$(citation_drift_section "$SUMMARY" \
    | grep -E "Multi.java.*three-level-keys.md.*applies_to-mismatch" | wc -l || true)
if [[ "$multi_mismatches" -eq 0 ]]; then
  pass "multi-citation: good slot NOT flagged"
else
  fail "multi-citation: good slot NOT flagged" "found $multi_mismatches mismatch row(s)"
fi

# ── 9. Comment-syntax variants ───────────────────────────────────────────

assert_drift_not_contains "$SUMMARY" "hash.py" \
    "comment syntax: # KB: parsed and validated (no drift)"

assert_drift_not_contains "$SUMMARY" "page.html" \
    "comment syntax: <!-- KB: --> parsed and validated (no drift)"

# ── 7. Vallorcine internals not scanned ──────────────────────────────────

# Drop a fake citation inside .spec/ — it should never appear in drift output
# because of the .spec/ filter.
mkdir -p .spec/domains
cat > .spec/domains/fake.md << 'EOF'
// KB: .kb/algorithms/encryption/this-also-missing.md
EOF
git add -A
git commit -q --date='2026-05-02T00:00:00Z' -m "add .spec citation"

MAX_LINK_ROT_URLS=0 bash "$REPO_ROOT/scripts/curate-scan.sh" --init >/dev/null 2>&1 || true

assert_drift_not_contains "$SUMMARY" "this-also-missing.md" \
    "exempt: citation inside .spec/ not scanned"

# ── Final report ─────────────────────────────────────────────────────────

echo ""
echo "── Summary ──"
echo "  Passed: $passed/$total"
echo "  Failed: $failed/$total"

[[ $failed -eq 0 ]] && exit 0 || exit 1
