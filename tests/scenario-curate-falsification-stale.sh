#!/usr/bin/env bash
# Scenario: /curate falsification-lens staleness detector (Analysis 22).
#
# Validates curate-scan.sh's falsification-staleness detection: APPROVED
# specs authored before a falsification lens shipped that match the lens's
# keyword pattern are surfaced as re-falsification candidates. Specs
# authored after the lens, or pre-lens specs without lens keywords, are
# NOT surfaced (no false positives).
#
# Layered cover:
#
#   1. Pre-lens spec WITH lens keywords IS flagged.
#   2. Post-lens spec is NOT flagged (no staleness signal).
#   3. Pre-lens spec WITHOUT lens keywords is NOT flagged.
#   4. DRAFT and INVALIDATED specs are NOT flagged (only APPROVED).
#   5. Output section + table format match the schema downstream readers
#      expect (Spec | Created | Missing Lens | Matched Keyword columns).
#   6. Lens registry comment lines and blank lines are skipped.
#   7. Multiple lenses can apply to the same spec (one row per lens).
#
# Run from repo root: bash tests/scenario-curate-falsification-stale.sh

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
echo "scenario: /curate falsification-lens staleness (Analysis 22)"
echo "────────────────────────────────────────────────"

TMPDIR_TEST="$(mktemp -d /tmp/vallorcine-curate-falsification.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PROJ="$TMPDIR_TEST/proj"
mkdir -p "$PROJ/.spec/registry" \
         "$PROJ/.spec/domains/auth" \
         "$PROJ/.spec/domains/storage" \
         "$PROJ/.spec/domains/util" \
         "$PROJ/.curate" \
         "$PROJ/scripts"
cd "$PROJ"

# Initialize git so the script's first-commit-date logic works.
git init -q
git config user.email test@example.com
git config user.name "Test"
git commit -q --allow-empty --date='2026-01-01T00:00:00Z' -m "initial"

# ── Build synthetic lens registry ──────────────────────────────────────────
#
# Two lenses with different introduction dates and keyword patterns.
# Comment + blank lines included to exercise the parser.

cat > "$PROJ/scripts/lens-registry.txt" <<'EOF'
# Test lens registry — comments must be skipped

security|2026-04-21|credential|password|encrypt|cipher|secret

concurrency|2026-02-01|deadlock|race|mutex|lock_order
EOF

# ── Build synthetic specs ──────────────────────────────────────────────────

build_spec() {
  local file="$1" id="$2" state="$3" body="$4"
  cat > "$file" <<EOF
---
{
  "id": "$id",
  "version": 1,
  "status": "ACTIVE",
  "state": "$state",
  "domains": ["auth"],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": []
}
---

# $id

$body
EOF
}

# (a) Pre-security-lens APPROVED spec with security keywords — should flag.
build_spec "$PROJ/.spec/domains/auth/credential-store.md" \
           "auth.credential-store" "APPROVED" \
           "R1. The credential vault must encrypt secrets at rest.
R2. Password rotation must run every 90 days.
R3. Cipher suites must be FIPS-approved."

# (b) Post-security-lens APPROVED spec with security keywords — should NOT
#     flag (added in a separate commit at a date AFTER the lens shipped,
#     so its git first-add date is post-lens).

# (c) Pre-security-lens APPROVED spec WITHOUT security keywords — should
#     NOT flag (no keyword match means no signal).
build_spec "$PROJ/.spec/domains/storage/format-v2.md" \
           "storage.format-v2" "APPROVED" \
           "R1. Records must be sorted by primary key on flush.
R2. Compaction must run when level size exceeds threshold.
R3. Page checksums must be verified on read."

# (d) Pre-security-lens DRAFT spec with security keywords — should NOT
#     flag (only APPROVED specs surface).
build_spec "$PROJ/.spec/domains/auth/oauth-flow.md" \
           "auth.oauth-flow" "DRAFT" \
           "R1. Encrypt all OAuth tokens at rest.
R2. Credentials must rotate hourly."

# (e) Pre-security-lens INVALIDATED spec with security keywords — should
#     NOT flag (INVALIDATED is historical, not a candidate).
build_spec "$PROJ/.spec/domains/auth/legacy-cipher.md" \
           "auth.legacy-cipher" "INVALIDATED" \
           "R1. Use legacy cipher for backwards compatibility."

# (f) Pre-both-lenses APPROVED spec matching BOTH lenses (security +
#     concurrency) — should flag once per matching lens.
build_spec "$PROJ/.spec/domains/util/multi-lens.md" \
           "util.multi-lens" "APPROVED" \
           "R1. Encrypt session keys before sharing across threads.
R2. Avoid deadlock by enforcing lock_order on shared mutex."

# Manifest with all 6 specs (token-issuer added later in a separate commit).
cat > "$PROJ/.spec/registry/manifest.json" <<'EOF'
{
  "schema_version": 2,
  "generated_at": "2026-01-15T00:00:00Z",
  "spec_count": 6,
  "specs": [
    {"id":"auth.credential-store",
     "path":".spec/domains/auth/credential-store.md",
     "state":"APPROVED","version":1,"domains":["auth"],
     "requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]},
    {"id":"auth.token-issuer",
     "path":".spec/domains/auth/token-issuer.md",
     "state":"APPROVED","version":1,"domains":["auth"],
     "requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]},
    {"id":"storage.format-v2",
     "path":".spec/domains/storage/format-v2.md",
     "state":"APPROVED","version":1,"domains":["storage"],
     "requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]},
    {"id":"auth.oauth-flow",
     "path":".spec/domains/auth/oauth-flow.md",
     "state":"DRAFT","version":1,"domains":["auth"],
     "requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]},
    {"id":"auth.legacy-cipher",
     "path":".spec/domains/auth/legacy-cipher.md",
     "state":"INVALIDATED","version":1,"domains":["auth"],
     "requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]},
    {"id":"util.multi-lens",
     "path":".spec/domains/util/multi-lens.md",
     "state":"APPROVED","version":1,"domains":["util"],
     "requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]}
  ]
}
EOF

# Empty obligations registry (curate-scan reads it).
echo '{"obligations": []}' > "$PROJ/.spec/registry/_obligations.json"

# Set spec creation dates via git commits at specific dates. Pre-lens
# specs (2026-01-15): credential-store, format-v2, oauth-flow,
# legacy-cipher, multi-lens. The manifest is also committed here.
git add .spec
git commit -q --date='2026-01-15T00:00:00Z' -m "pre-lens specs" \
           --author='Test <test@example.com>' \
           >/dev/null

# Post-security-lens (2026-04-25): token-issuer added in a separate
# commit at a later date. Its git first-add date is what the script
# uses to determine staleness.
build_spec "$PROJ/.spec/domains/auth/token-issuer.md" \
           "auth.token-issuer" "APPROVED" \
           "R1. Tokens must be encrypted in transit.
R2. Cipher choice must follow current NIST guidance."
git add .spec/domains/auth/token-issuer.md
git commit -q --date='2026-04-25T00:00:00Z' -m "post-lens token-issuer added" \
           --author='Test <test@example.com>' \
           >/dev/null

# Empty curate state.
echo "Last scanned: " > "$PROJ/.curate/curation-state.md"

# ── Run curate-scan ────────────────────────────────────────────────────────

echo ""
echo "── Running curate-scan against synthetic project"

cd "$PROJ"
SUMMARY_FILE="$PROJ/.curate/scan-summary.md"
bash "$REPO_ROOT/scripts/curate-scan.sh" --init >/tmp/curate-fals-out.log 2>&1
rc=$?

if [[ $rc -eq 0 ]]; then
  pass "curate-scan completed without error"
else
  fail "curate-scan exited $rc" "$(tail -10 /tmp/curate-fals-out.log)"
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

# ── Layer 1: pre-lens spec with keywords IS flagged ────────────────────────

echo ""
echo "── Layer 1: pre-lens spec with security keywords IS flagged"

if grep -q '^| auth.credential-store ' "$SUMMARY_FILE"; then
  pass "auth.credential-store appears in Falsification Lens Staleness"
else
  fail "pre-lens spec with keywords NOT flagged" \
       "$(grep -A 10 'Falsification Lens Staleness' "$SUMMARY_FILE" || echo '(no section)')"
fi

# ── Layer 2: post-lens spec is NOT flagged ─────────────────────────────────

echo ""
echo "── Layer 2: post-lens spec is NOT flagged"

# auth.token-issuer was first-committed at 2026-04-25, after security lens
# (2026-04-21) shipped — it should NOT appear.
if grep -qE '\| auth.token-issuer \|.*\| security \|' "$SUMMARY_FILE"; then
  fail "post-lens spec was incorrectly flagged for security lens"
else
  pass "post-lens spec is not flagged"
fi

# ── Layer 3: pre-lens spec without keywords is NOT flagged ─────────────────

echo ""
echo "── Layer 3: pre-lens spec without keywords is NOT flagged"

if grep -qE '\| storage.format-v2 \|.*\| security \|' "$SUMMARY_FILE"; then
  fail "pre-lens spec without security keywords was incorrectly flagged"
else
  pass "pre-lens spec without keywords is not flagged"
fi

# ── Layer 4: DRAFT and INVALIDATED specs are NOT flagged ───────────────────

echo ""
echo "── Layer 4: DRAFT and INVALIDATED specs are NOT flagged"

if grep -q '^| auth.oauth-flow ' "$SUMMARY_FILE"; then
  fail "DRAFT spec was incorrectly flagged"
else
  pass "DRAFT spec is not flagged"
fi

if grep -q '^| auth.legacy-cipher ' "$SUMMARY_FILE"; then
  fail "INVALIDATED spec was incorrectly flagged"
else
  pass "INVALIDATED spec is not flagged"
fi

# ── Layer 5: section header + table format ─────────────────────────────────

echo ""
echo "── Layer 5: section header + table format"

if grep -q '^## Falsification Lens Staleness' "$SUMMARY_FILE"; then
  pass "Falsification Lens Staleness section present"
else
  fail "section header missing"
fi

if grep -qE '^\| Spec \| Created \| Missing Lens \| Matched Keyword \|' "$SUMMARY_FILE"; then
  pass "table header has expected columns"
else
  fail "table header missing or malformed"
fi

# Sample row sanity: should have a date column with YYYY-MM-DD format.
if grep -qE '\| auth.credential-store \| [0-9]{4}-[0-9]{2}-[0-9]{2} \| security \|' "$SUMMARY_FILE"; then
  pass "row format has spec | YYYY-MM-DD date | lens"
else
  fail "row format malformed" \
       "$(grep '^| auth.credential-store' "$SUMMARY_FILE" || echo '(no row)')"
fi

# ── Layer 6: multi-lens spec flagged for both lenses ───────────────────────

echo ""
echo "── Layer 6: multi-lens spec flagged for each matching lens"

# util.multi-lens has both security and concurrency keywords; it was
# committed at 2026-01-15 (pre both 2026-02-01 concurrency and 2026-04-21
# security lenses). Both rows should appear.
sec_rows=$(grep -cE '\| util.multi-lens \|.*\| security \|' "$SUMMARY_FILE" || true)
con_rows=$(grep -cE '\| util.multi-lens \|.*\| concurrency \|' "$SUMMARY_FILE" || true)

if [[ "$sec_rows" -ge 1 ]]; then
  pass "multi-lens spec flagged for security lens"
else
  fail "multi-lens spec missing security row"
fi

if [[ "$con_rows" -ge 1 ]]; then
  pass "multi-lens spec flagged for concurrency lens"
else
  fail "multi-lens spec missing concurrency row" \
       "$(grep '^| util.multi-lens' "$SUMMARY_FILE" || echo '(no rows)')"
fi

# ── Layer 7: lens-registry comments and blanks are skipped ─────────────────

echo ""
echo "── Layer 7: lens-registry parser tolerates comments + blank lines"

# We injected comment + blank lines in the registry. If the parser misread
# them, a malformed lens row would either crash the script or appear in
# the summary as garbled output. Check both: no crash (already verified),
# and no garbled lens names in the rendered table.
malformed=$(grep -E '^\| [A-Za-z0-9_.-]+ \| [^|]+ \| (#|$| ) \|' "$SUMMARY_FILE" || true)
if [[ -z "$malformed" ]]; then
  pass "no malformed lens rows from comment/blank-line parsing"
else
  fail "malformed lens row" "$malformed"
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
