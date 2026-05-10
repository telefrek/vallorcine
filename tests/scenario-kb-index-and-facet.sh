#!/usr/bin/env bash
# Scenario: kb-index.sh rebuild + kb-search.sh --facet filter mode.
#
# Layered cover:
#
#  Index generation
#    1. Rebuild produces .kb/_index.json with the documented schema.
#    2. CLAUDE.md, _refs/, _archive* are excluded.
#    3. detail-companion entries are excluded (surfaced via parent @./).
#    4. Frontmatter without applies_to becomes [] in the entry.
#    5. Inline list YAML and block list YAML both parse.
#    6. Path drives derived topic + category fields.
#    7. Atomic write via .tmp + rename.
#
#  Facet query
#    8. Scalar field exact match (type=adversarial-finding).
#    9. List field membership (tags=encryption).
#   10. Multiple facets AND-combine.
#   11. Empty result for impossible filter (no FAIL, no error).
#   12. Auto-rebuild when index is missing.
#   13. Auto-rebuild when index is stale (any *.md newer than index).
#   14. Unknown facet key never matches (typo tolerance).
#   15. Facet mode skips files that have no frontmatter.
#
# Run from repo root: bash tests/scenario-kb-index-and-facet.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
KB_INDEX="$REPO_ROOT/scripts/kb-index.sh"
KB_SEARCH="$REPO_ROOT/scripts/kb-search.sh"

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
echo "scenario: kb-index.sh + kb-search.sh --facet"
echo "────────────────────────────────────────────────"

TMPDIR_TEST="$(mktemp -d /tmp/vallorcine/kb-index.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PROJ="$TMPDIR_TEST/proj"
mkdir -p "$PROJ/.kb/algorithms/encryption" \
         "$PROJ/.kb/patterns/validation" \
         "$PROJ/.kb/architecture/feature-footprints" \
         "$PROJ/.kb/_refs" \
         "$PROJ/.kb/_archive"
cd "$PROJ"

cat > .kb/CLAUDE.md << 'EOF'
# KB
EOF

# Excluded — _refs/
cat > .kb/_refs/frontmatter.md << 'EOF'
---
type: reference-fragment
title: schema
---
# refs
EOF

# Excluded — _archive
cat > .kb/_archive/old-entry.md << 'EOF'
---
title: "Old archived entry"
type: research
last_researched: "2025-01-01"
research_status: deprecated
applies_to: []
---
# entry
EOF

# Block-form applies_to.
cat > .kb/algorithms/encryption/three-level-keys.md << 'EOF'
---
title: "Three-level key hierarchy"
type: research
tags: ["encryption", "key-hierarchy"]
applies_to:
  - "src/main/auth/**"
  - "src/main/security/**"
last_researched: "2026-04-01"
research_status: stable
confidence: medium
---
# entry
EOF

# Inline-list applies_to + adversarial-finding.
cat > .kb/patterns/validation/silent-fallthrough.md << 'EOF'
---
title: "Silent fallthrough"
type: adversarial-finding
domain: validation
severity: confirmed
tags: ["adversarial-finding", "validation"]
applies_to: ["src/main/auth/**"]
last_researched: "2026-04-12"
research_status: stable
---
# entry
EOF

# feature-footprint with domains and constructs.
cat > .kb/architecture/feature-footprints/auth-rewrite.md << 'EOF'
---
title: "auth-rewrite"
type: feature-footprint
domains: ["auth", "security"]
constructs: ["LoginService", "KeyStore"]
applies_to:
  - "src/main/auth/**"
last_researched: "2026-04-15"
research_status: stable
---
# entry
EOF

# detail-companion — excluded from index.
cat > .kb/algorithms/encryption/three-level-keys-detail.md << 'EOF'
---
title: "Three-level keys — Detail"
type: detail-companion
companion_to: "algorithms/encryption/three-level-keys.md"
last_researched: "2026-04-01"
research_status: stable
applies_to: []
---
# detail
EOF

# Entry without frontmatter — should be silently skipped.
cat > .kb/algorithms/encryption/no-frontmatter.md << 'EOF'
# Just a markdown stub with no YAML.
EOF

# ── 1. Index rebuild ─────────────────────────────────────────────────────

bash "$KB_INDEX" >/dev/null 2>&1
INDEX=".kb/_index.json"

if [[ -f "$INDEX" ]]; then
  pass "index file created"
else
  fail "index file created" "$INDEX missing"
fi

if python3 -c 'import json; json.load(open(".kb/_index.json"))' 2>/dev/null; then
  pass "index is valid JSON"
else
  fail "index is valid JSON"
fi

# ── 2 & 3 & 15. Exclusions ───────────────────────────────────────────────

if ! grep -q '"path": ".kb/CLAUDE.md"' "$INDEX"; then
  pass "exclude: CLAUDE.md not indexed"
else
  fail "exclude: CLAUDE.md not indexed"
fi

if ! grep -q '_refs/frontmatter' "$INDEX"; then
  pass "exclude: _refs/ not indexed"
else
  fail "exclude: _refs/ not indexed"
fi

if ! grep -q '_archive/old-entry' "$INDEX"; then
  pass "exclude: _archive not indexed"
else
  fail "exclude: _archive not indexed"
fi

if ! grep -q 'three-level-keys-detail' "$INDEX"; then
  pass "exclude: detail-companion not indexed"
else
  fail "exclude: detail-companion not indexed"
fi

if ! grep -q 'no-frontmatter' "$INDEX"; then
  pass "skip: file without frontmatter"
else
  fail "skip: file without frontmatter"
fi

# ── 4. Empty applies_to becomes [] ──────────────────────────────────────

if python3 -c '
import json, sys
d = json.load(open(".kb/_index.json"))
for e in d["entries"]:
    if e["title"] == "Three-level key hierarchy":
        sys.exit(0 if e["applies_to"] == ["src/main/auth/**", "src/main/security/**"] else 1)
sys.exit(1)
' 2>/dev/null; then
  pass "applies_to: block-form parses to list of patterns"
else
  fail "applies_to: block-form parses to list of patterns"
fi

if python3 -c '
import json, sys
d = json.load(open(".kb/_index.json"))
for e in d["entries"]:
    if e["title"] == "Silent fallthrough":
        sys.exit(0 if e["applies_to"] == ["src/main/auth/**"] else 1)
sys.exit(1)
' 2>/dev/null; then
  pass "applies_to: inline-list parses to list of patterns"
else
  fail "applies_to: inline-list parses to list of patterns"
fi

# ── 6. Topic + category derived from path ───────────────────────────────

if python3 -c '
import json, sys
d = json.load(open(".kb/_index.json"))
for e in d["entries"]:
    if e["title"] == "Three-level key hierarchy":
        sys.exit(0 if e["topic"] == "algorithms" and e["category"] == "encryption" else 1)
sys.exit(1)
' 2>/dev/null; then
  pass "topic + category derived from path"
else
  fail "topic + category derived from path"
fi

# ── Facet queries ───────────────────────────────────────────────────────

# 8. Scalar exact match.
RESULT=$(bash "$KB_SEARCH" --facet 'type=adversarial-finding')
if echo "$RESULT" | grep -q 'silent-fallthrough'; then
  pass "facet: type=adversarial-finding matches"
else
  fail "facet: type=adversarial-finding matches" "got: $RESULT"
fi
if ! echo "$RESULT" | grep -q 'three-level-keys'; then
  pass "facet: type=adversarial-finding excludes research entries"
else
  fail "facet: type=adversarial-finding excludes research entries"
fi

# 9. List field membership.
RESULT=$(bash "$KB_SEARCH" --facet 'tags=encryption')
if echo "$RESULT" | grep -q 'three-level-keys.md'; then
  pass "facet: tags=encryption matches (list membership)"
else
  fail "facet: tags=encryption matches" "got: $RESULT"
fi

# 10. AND-combined facets.
RESULT=$(bash "$KB_SEARCH" --facet 'type=adversarial-finding,domain=validation')
LINES=$(echo "$RESULT" | grep -c . || true)
if [[ "$LINES" -eq 1 ]] && echo "$RESULT" | grep -q 'silent-fallthrough'; then
  pass "facet: AND-combine type+domain matches one entry"
else
  fail "facet: AND-combine type+domain matches one entry" "got $LINES lines: $RESULT"
fi

# 11. Empty result for impossible filter.
RESULT=$(bash "$KB_SEARCH" --facet 'type=does-not-exist')
if [[ -z "$RESULT" ]]; then
  pass "facet: empty result for impossible filter"
else
  fail "facet: empty result for impossible filter" "got: $RESULT"
fi

# 12. Auto-rebuild when index is missing.
rm -f "$INDEX"
RESULT=$(bash "$KB_SEARCH" --facet 'type=research')
if [[ -f "$INDEX" ]] && echo "$RESULT" | grep -q 'three-level-keys.md'; then
  pass "facet: auto-rebuilds index when missing"
else
  fail "facet: auto-rebuilds index when missing" "got: $RESULT"
fi

# 13. Auto-rebuild when index is stale.
sleep 1   # filesystem mtime resolution
cat > .kb/algorithms/encryption/new-entry.md << 'EOF'
---
title: "Newly added"
type: research
tags: []
applies_to: []
last_researched: "2026-05-09"
research_status: stable
---
# entry
EOF
RESULT=$(bash "$KB_SEARCH" --facet 'type=research')
if echo "$RESULT" | grep -q 'new-entry.md'; then
  pass "facet: auto-rebuilds index when stale"
else
  fail "facet: auto-rebuilds index when stale" "got: $RESULT"
fi

# 14. Unknown facet key never matches.
RESULT=$(bash "$KB_SEARCH" --facet 'nosuchkey=anything')
if [[ -z "$RESULT" ]]; then
  pass "facet: unknown key never matches"
else
  fail "facet: unknown key never matches" "got: $RESULT"
fi

# ── 7. Atomic write — no .tmp file lying around after success ───────────

if ! ls "$INDEX".tmp.* >/dev/null 2>&1; then
  pass "atomic write: no leftover .tmp files"
else
  fail "atomic write: no leftover .tmp files"
fi

# ── Final report ────────────────────────────────────────────────────────

echo ""
echo "── Summary ──"
echo "  Passed: $passed/$total"
echo "  Failed: $failed/$total"

[[ $failed -eq 0 ]] && exit 0 || exit 1
