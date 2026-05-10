#!/usr/bin/env bash
# Scenario: PostToolUse hook check-kb-ref.sh validates KB citations in code.
#
# Layered cover:
#
#   1. Auto-disable when .kb/ is absent.
#   2. Auto-disable when .kb/ only has _refs/ (no entries).
#   3. Skip files inside vallorcine internal dirs (.kb/, .spec/, etc.).
#   4. Skip non-source extensions (md, json, yaml, etc.).
#   5. Suggest matching KB entries when a source file has no citation
#      but applies_to globs cover its path.
#   6. Silent when there is no citation AND no entry's applies_to matches.
#   7. Warn when a citation points at a missing KB entry (rotted link).
#   8. Warn when a citation's applies_to does not include the file (wrong citation).
#   9. Accept comma-separated multi-citation on one line.
#  10. Accept // KB:, # KB:, and <!-- KB: ... --> comment forms.
#  11. Hook always exits 0 (advisory only, never blocks the tool use).
#  12. Empty applies_to in the cited entry passes validation (general research).
#
# Run from repo root: bash tests/scenario-check-kb-ref.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
HOOK="$REPO_ROOT/scripts/check-kb-ref.sh"

passed=0
failed=0
total=0

pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() {
  ((failed++)) || true; ((total++)) || true
  echo "  FAIL  $1"
  [[ -n "${2:-}" ]] && echo "        $2"
}

# Drives the hook with a synthetic PostToolUse JSON. Captures stdout (the
# systemMessage JSON or empty), stderr, and exit code.
#
#   run_hook <project-root> <file-path>  → echoes stdout
run_hook() {
  local proj="$1" path="$2"
  ( cd "$proj" && \
    printf '{"tool_input":{"file_path":"%s"}}' "$path" \
      | bash "$HOOK" 2>/dev/null )
}

echo ""
echo "scenario: check-kb-ref.sh hook"
echo "────────────────────────────────────────────────"

TMPDIR_TEST="$(mktemp -d /tmp/vallorcine/check-kb-ref.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── 1. Project with no .kb/ at all ───────────────────────────────────────────

P1="$TMPDIR_TEST/no-kb"
mkdir -p "$P1/src/main"
cat > "$P1/src/main/Foo.java" << 'EOF'
public class Foo {}
EOF

OUT="$(run_hook "$P1" "src/main/Foo.java")"
if [[ -z "$OUT" ]]; then
  pass "auto-disable when .kb/ is absent"
else
  fail "auto-disable when .kb/ is absent" "got: $OUT"
fi

# Always exit 0 — advisory only.
( cd "$P1" && printf '{"tool_input":{"file_path":"src/main/Foo.java"}}' | bash "$HOOK" >/dev/null 2>&1 )
if [[ "$?" -eq 0 ]]; then
  pass "hook exits 0 on no-kb project"
else
  fail "hook exits 0 on no-kb project"
fi

# ── 2. Project with only _refs/ (no entries) ────────────────────────────────

P2="$TMPDIR_TEST/refs-only"
mkdir -p "$P2/.kb/_refs" "$P2/src/main"
echo "stub" > "$P2/.kb/_refs/frontmatter.md"
cat > "$P2/.kb/CLAUDE.md" << 'EOF'
# KB
EOF
cat > "$P2/src/main/Bar.java" << 'EOF'
public class Bar {}
EOF

OUT="$(run_hook "$P2" "src/main/Bar.java")"
if [[ -z "$OUT" ]]; then
  pass "auto-disable when .kb/ only has _refs/"
else
  fail "auto-disable when .kb/ only has _refs/" "got: $OUT"
fi

# ── Build a richer fixture for the rest ─────────────────────────────────────

P3="$TMPDIR_TEST/proj"
mkdir -p "$P3/.kb/algorithms/encryption" \
         "$P3/.kb/patterns/validation" \
         "$P3/.kb/_refs" \
         "$P3/.spec" \
         "$P3/src/main/auth" \
         "$P3/src/main/billing" \
         "$P3/docs"

cat > "$P3/.kb/CLAUDE.md" << 'EOF'
# KB
EOF
echo "stub" > "$P3/.kb/_refs/frontmatter.md"

cat > "$P3/.kb/algorithms/encryption/three-level-keys.md" << 'EOF'
---
title: "Three-level key hierarchy"
type: research
applies_to:
  - "src/main/auth/**"
  - "src/main/auth/KeyStore.java"
last_researched: "2026-05-09"
research_status: stable
---
# entry
EOF

cat > "$P3/.kb/patterns/validation/silent-fallthrough.md" << 'EOF'
---
title: "Silent fallthrough"
type: adversarial-finding
domain: validation
severity: confirmed
applies_to:
  - "src/main/auth/**"
last_researched: "2026-05-09"
research_status: stable
---
# entry
EOF

cat > "$P3/.kb/algorithms/encryption/no-applies.md" << 'EOF'
---
title: "General encryption research (no applies_to)"
type: research
applies_to: []
last_researched: "2026-05-09"
research_status: stable
---
# entry
EOF

# ── 3. Skip vallorcine internals ─────────────────────────────────────────────

OUT="$(run_hook "$P3" ".kb/algorithms/encryption/three-level-keys.md")"
if [[ -z "$OUT" ]]; then
  pass "skip files inside .kb/"
else
  fail "skip files inside .kb/" "got: $OUT"
fi

OUT="$(run_hook "$P3" ".spec/foo.md")"
if [[ -z "$OUT" ]]; then
  pass "skip files inside .spec/"
else
  fail "skip files inside .spec/" "got: $OUT"
fi

# ── 4. Skip non-source extensions ───────────────────────────────────────────

cat > "$P3/docs/notes.md" << 'EOF'
some markdown
EOF
OUT="$(run_hook "$P3" "docs/notes.md")"
if [[ -z "$OUT" ]]; then
  pass "skip .md files"
else
  fail "skip .md files" "got: $OUT"
fi

cat > "$P3/src/main/auth/config.yaml" << 'EOF'
key: value
EOF
OUT="$(run_hook "$P3" "src/main/auth/config.yaml")"
if [[ -z "$OUT" ]]; then
  pass "skip .yaml files"
else
  fail "skip .yaml files" "got: $OUT"
fi

# ── 5. Suggest matching entries when no citation ────────────────────────────

cat > "$P3/src/main/auth/KeyStore.java" << 'EOF'
public class KeyStore {
    // some implementation
}
EOF
OUT="$(run_hook "$P3" "src/main/auth/KeyStore.java")"
if echo "$OUT" | grep -q 'three-level-keys'; then
  pass "suggest: matching entry surfaced when no citation present"
else
  fail "suggest: matching entry surfaced when no citation present" "got: $OUT"
fi
if echo "$OUT" | grep -q 'silent-fallthrough'; then
  pass "suggest: second matching entry also surfaced"
else
  fail "suggest: second matching entry also surfaced" "got: $OUT"
fi

# ── 6. Silent when no citation AND no entry matches ─────────────────────────

cat > "$P3/src/main/billing/Invoice.java" << 'EOF'
public class Invoice {}
EOF
OUT="$(run_hook "$P3" "src/main/billing/Invoice.java")"
if [[ -z "$OUT" ]]; then
  pass "silent when no citation and no applies_to matches"
else
  fail "silent when no citation and no applies_to matches" "got: $OUT"
fi

# ── 7. Warn when citation points at missing entry ───────────────────────────

cat > "$P3/src/main/auth/Login.java" << 'EOF'
// KB: .kb/algorithms/encryption/this-was-renamed.md
public class Login {}
EOF
OUT="$(run_hook "$P3" "src/main/auth/Login.java")"
if echo "$OUT" | grep -q 'missing entry'; then
  pass "warn: citation points at missing entry"
else
  fail "warn: citation points at missing entry" "got: $OUT"
fi

# ── 8. Warn when applies_to does not include the file ───────────────────────

cat > "$P3/src/main/billing/Charge.java" << 'EOF'
// KB: .kb/algorithms/encryption/three-level-keys.md
public class Charge {}
EOF
OUT="$(run_hook "$P3" "src/main/billing/Charge.java")"
if echo "$OUT" | grep -q 'applies_to does not include'; then
  pass "warn: applies_to mismatch flagged"
else
  fail "warn: applies_to mismatch flagged" "got: $OUT"
fi

# ── 9. Multi-citation parsing (comma-separated) ─────────────────────────────

cat > "$P3/src/main/auth/Multi.java" << 'EOF'
// KB: .kb/algorithms/encryption/three-level-keys.md, .kb/algorithms/encryption/missing.md
public class Multi {}
EOF
OUT="$(run_hook "$P3" "src/main/auth/Multi.java")"
if echo "$OUT" | grep -q 'missing.md'; then
  pass "multi-citation: missing entry in second slot is flagged"
else
  fail "multi-citation: missing entry in second slot is flagged" "got: $OUT"
fi
# The valid first citation should not be flagged.
if ! echo "$OUT" | grep -q 'three-level-keys.md.*missing entry'; then
  pass "multi-citation: valid entry in first slot is NOT flagged"
else
  fail "multi-citation: valid entry in first slot is NOT flagged" "got: $OUT"
fi

# ── 10. All comment syntaxes recognised ─────────────────────────────────────

cat > "$P3/src/main/auth/hash.py" << 'EOF'
# KB: .kb/algorithms/encryption/three-level-keys.md
def hash_key(): pass
EOF
OUT="$(run_hook "$P3" "src/main/auth/hash.py")"
# No suggestion message because citation is present and valid.
if [[ -z "$OUT" ]] || ! echo "$OUT" | grep -q 'no KB citation'; then
  pass "comment syntax: # KB: recognised (no suggestion fired)"
else
  fail "comment syntax: # KB: recognised (no suggestion fired)" "got: $OUT"
fi

cat > "$P3/src/main/auth/page.html" << 'EOF'
<!-- KB: .kb/algorithms/encryption/three-level-keys.md -->
<html></html>
EOF
OUT="$(run_hook "$P3" "src/main/auth/page.html")"
if [[ -z "$OUT" ]] || ! echo "$OUT" | grep -q 'no KB citation'; then
  pass "comment syntax: <!-- KB: --> recognised"
else
  fail "comment syntax: <!-- KB: --> recognised" "got: $OUT"
fi

# ── 11. Hook always exits 0 ─────────────────────────────────────────────────

EXIT_CODE=0
( cd "$P3" && printf '{"tool_input":{"file_path":"src/main/auth/Login.java"}}' \
    | bash "$HOOK" >/dev/null 2>&1 ) || EXIT_CODE=$?
if [[ "$EXIT_CODE" -eq 0 ]]; then
  pass "exit 0 even when warnings are emitted"
else
  fail "exit 0 even when warnings are emitted" "exit=$EXIT_CODE"
fi

# ── 12. Empty applies_to entry passes validation (general research) ─────────

cat > "$P3/src/main/auth/General.java" << 'EOF'
// KB: .kb/algorithms/encryption/no-applies.md
public class General {}
EOF
OUT="$(run_hook "$P3" "src/main/auth/General.java")"
if ! echo "$OUT" | grep -q 'applies_to does not include'; then
  pass "empty applies_to entry passes validation (general research)"
else
  fail "empty applies_to entry passes validation (general research)" "got: $OUT"
fi

# ── Final report ────────────────────────────────────────────────────────────

echo ""
echo "── Summary ──"
echo "  Passed: $passed/$total"
echo "  Failed: $failed/$total"

[[ $failed -eq 0 ]] && exit 0 || exit 1
