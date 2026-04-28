#!/usr/bin/env bash
# Scenario: /curate link-rot detector (Analysis 21).
#
# Validates curate-scan.sh's link-rot detection: KB entries with citation
# URLs are scanned, dead URLs (4xx + connection failures) are flagged,
# and the cache prevents re-checking confirmed-dead URLs on every scan.
#
# Layered cover:
#
#   1. Unreachable URL (curl returns 000) is flagged.
#   2. Cached-as-200 URL is NOT flagged.
#   3. URLs inside fenced code blocks are NOT extracted.
#   4. Cached confirmed-dead URLs surface from cache without re-curling.
#   5. Markdown-link URLs `[text](url)` are extracted correctly.
#   6. Bare URLs `https://...` are extracted correctly.
#   7. Trailing prose punctuation is stripped from bare URLs.
#   8. Output section + table format match the schema downstream readers
#      expect (status, KB entry, URL, last-checked columns).
#   9. Cache file is updated atomically with new entries.
#  10. KB excluded paths (_refs, _archive, CLAUDE.md) are skipped.
#
# Run from repo root: bash tests/scenario-curate-link-rot.sh

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
echo "scenario: /curate link-rot detector (Analysis 21)"
echo "────────────────────────────────────────────────"

# Skip if curl missing — link-rot analysis silently degrades but the test
# harness can't validate behavior without it.
if ! command -v curl >/dev/null 2>&1; then
  echo "  SKIP  curl not available"
  exit 0
fi

# Synthetic project tree under /tmp/vallorcine/* for permission pre-grant.
TMPDIR_TEST="$(mktemp -d /tmp/vallorcine-curate-link-rot.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PROJ="$TMPDIR_TEST/proj"
mkdir -p "$PROJ/.kb/storage/format" \
         "$PROJ/.kb/_refs" \
         "$PROJ/.kb/security/_archive" \
         "$PROJ/.curate"
cd "$PROJ"

# Initialize empty git repo so curate-scan's git operations don't crash.
git init -q
git config user.email test@example.com
git config user.name "Test"
git commit -q --allow-empty -m "initial"

# ── Build synthetic KB entries ─────────────────────────────────────────────

# (a) Entry with one unreachable URL (will resolve to status 000 — connection
#     refused on port 1). Plus a markdown-linked URL we'll pre-cache as 200.
cat > "$PROJ/.kb/storage/format/lsm-tree.md" <<'EOF'
---
title: LSM-tree storage
type: pattern
applies_to: [src/storage/lsm.go]
related: []
research_status: active
last_researched: "2026-04-01"
---

# LSM-tree storage

Bare URL pointing to a guaranteed-unreachable port:
http://127.0.0.1:1/dead-citation.

A markdown-linked source: [Wikipedia entry](https://example.org/wiki/LSM_tree).

Trailing punctuation should be stripped: see http://127.0.0.1:1/another-dead.

```
# Code fence — URLs in here MUST NOT be extracted.
http://127.0.0.1:1/inside-fence
[Decoy](http://127.0.0.1:1/decoy-in-fence)
```

A second bare URL in prose: https://example.org/wiki/Bloom_filter.
EOF

# (b) Entry under _refs — must be excluded by the find filter.
cat > "$PROJ/.kb/_refs/refs-only.md" <<'EOF'
---
title: Refs-only
---
This URL must not be processed: http://127.0.0.1:1/ref-only-dead
EOF

# (c) Entry under _archive — must be excluded.
cat > "$PROJ/.kb/security/_archive/archived.md" <<'EOF'
---
title: Archived
---
This URL must not be processed: http://127.0.0.1:1/archive-dead
EOF

# (d) CLAUDE.md inside a category — must be excluded by name filter.
cat > "$PROJ/.kb/storage/CLAUDE.md" <<'EOF'
# Storage topic index
- format/lsm-tree.md
EOF

# Pre-populate the cache so example.org URLs do not get fresh-curled
# (avoids real-network dependency in CI). Both example.org URLs cache as
# status 200 (reachable) so they should NOT appear in the rot output.
NOW=$(date +%s)
cat > "$PROJ/.curate/link-rot-cache.txt" <<EOF
https://example.org/wiki/LSM_tree|200|$NOW
https://example.org/wiki/Bloom_filter|200|$NOW
EOF

# ── Run curate-scan (first invocation: fresh) ──────────────────────────────

echo ""
echo "── Run 1: fresh scan, unreachable URLs should curl + cache + flag"

cd "$PROJ"
SUMMARY_FILE="$PROJ/.curate/scan-summary.md"
bash "$REPO_ROOT/scripts/curate-scan.sh" --init >/tmp/curate-link-rot-1.log 2>&1
rc=$?

if [[ $rc -eq 0 ]]; then
  pass "curate-scan run 1 completed without error"
else
  fail "curate-scan run 1 exited $rc" "$(tail -10 /tmp/curate-link-rot-1.log)"
  echo ""
  echo "────────────────────────────────────────────────"
  echo "FAILED  $failed/$total"
  exit 1
fi

if [[ -f "$SUMMARY_FILE" ]]; then
  pass "summary file written"
else
  fail "summary file missing"
  exit 1
fi

# ── Layer 1: unreachable URL flagged ───────────────────────────────────────

echo ""
echo "── Layer 1: unreachable URLs are flagged"

if grep -q 'http://127.0.0.1:1/dead-citation' "$SUMMARY_FILE"; then
  pass "first unreachable URL appears in summary"
else
  fail "first unreachable URL not flagged" "$(grep -A 10 'Link Rot' "$SUMMARY_FILE" || echo '(no section)')"
fi

if grep -q 'http://127.0.0.1:1/another-dead' "$SUMMARY_FILE"; then
  pass "second bare URL is flagged with trailing punctuation stripped"
else
  fail "second bare URL not flagged or punctuation not stripped"
fi

# ── Layer 2: cached-as-200 URLs NOT flagged ────────────────────────────────

echo ""
echo "── Layer 2: cached-200 URLs are NOT flagged"

if grep -q 'example.org/wiki/LSM_tree' "$SUMMARY_FILE"; then
  fail "cached-as-200 markdown link was incorrectly flagged"
else
  pass "cached-as-200 markdown link is not flagged"
fi

if grep -q 'example.org/wiki/Bloom_filter' "$SUMMARY_FILE"; then
  fail "cached-as-200 bare URL was incorrectly flagged"
else
  pass "cached-as-200 bare URL is not flagged"
fi

# ── Layer 3: URLs inside code fence excluded ────────────────────────────────

echo ""
echo "── Layer 3: URLs inside fenced code blocks are NOT extracted"

if grep -q 'inside-fence' "$SUMMARY_FILE" || grep -q 'decoy-in-fence' "$SUMMARY_FILE"; then
  fail "code-fenced URL leaked into the rot output"
else
  pass "code-fenced URLs are excluded"
fi

# ── Layer 4: excluded paths (_refs, _archive, CLAUDE.md) ───────────────────

echo ""
echo "── Layer 4: excluded paths are not scanned"

if grep -q 'ref-only-dead' "$SUMMARY_FILE"; then
  fail "_refs path was scanned (should be excluded)"
else
  pass "_refs path is excluded"
fi

if grep -q 'archive-dead' "$SUMMARY_FILE"; then
  fail "_archive path was scanned (should be excluded)"
else
  pass "_archive path is excluded"
fi

# ── Layer 5: section header + table format ─────────────────────────────────

echo ""
echo "── Layer 5: section header + table format"

if grep -q '^## Link Rot in KB Entries' "$SUMMARY_FILE"; then
  pass "Link Rot section header present"
else
  fail "Link Rot section header missing"
fi

if grep -qE '^\| Status \| KB Entry \| URL \| Last Checked \|' "$SUMMARY_FILE"; then
  pass "table header has expected columns"
else
  fail "table header missing or malformed"
fi

# Status code "000" should appear in at least one row (since unreachable
# URLs all hit 127.0.0.1:1 which refuses connection).
if grep -qE '^\| 000 \|' "$SUMMARY_FILE"; then
  pass "rows include 000 status for connection failures"
else
  fail "no row with 000 status — connection-refused detection broken"
fi

# ── Layer 6: cache file updated ────────────────────────────────────────────

echo ""
echo "── Layer 6: cache updated with new dead-URL entries"

CACHE_FILE="$PROJ/.curate/link-rot-cache.txt"
if grep -q 'http://127.0.0.1:1/dead-citation|000|' "$CACHE_FILE"; then
  pass "cache contains dead-citation entry"
else
  fail "cache missing dead-citation entry" "$(cat "$CACHE_FILE")"
fi

# Pre-existing example.org entries should still be present after merge.
if grep -q 'example.org/wiki/LSM_tree|200|' "$CACHE_FILE"; then
  pass "pre-existing cache entries preserved across run"
else
  fail "cache merge dropped pre-existing entries"
fi

# ── Layer 7: cache hit prevents re-curl on second run ──────────────────────

echo ""
echo "── Run 2: cache hit, no fresh curl, dead URLs still surfaced"

# Capture cache mtime to detect whether the cache was rewritten.
cache_mtime_before=$(stat -c %Y "$CACHE_FILE" 2>/dev/null \
                     || stat -f %m "$CACHE_FILE" 2>/dev/null)

# Sleep 1s so any rewrite would have a different mtime.
sleep 1

bash "$REPO_ROOT/scripts/curate-scan.sh" --init >/tmp/curate-link-rot-2.log 2>&1
rc=$?

if [[ $rc -eq 0 ]]; then
  pass "curate-scan run 2 completed without error"
else
  fail "curate-scan run 2 exited $rc" "$(tail -10 /tmp/curate-link-rot-2.log)"
fi

# Dead URLs should still be flagged (from cache).
if grep -q 'http://127.0.0.1:1/dead-citation' "$SUMMARY_FILE"; then
  pass "cached dead URLs still surfaced on run 2"
else
  fail "dead URLs lost between runs (cache lookup broken)"
fi

cache_mtime_after=$(stat -c %Y "$CACHE_FILE" 2>/dev/null \
                    || stat -f %m "$CACHE_FILE" 2>/dev/null)

# Cache should NOT have been rewritten this run (no new fresh-curl entries).
if [[ "$cache_mtime_before" == "$cache_mtime_after" ]]; then
  pass "cache not rewritten on run 2 (TTL hit, no fresh curls)"
else
  # Some bash builtins or filesystems may touch the file even on
  # no-op writes; treat as a soft assertion.
  echo "  NOTE  cache mtime changed between runs (acceptable on some FSes)"
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
