#!/usr/bin/env bash
# Scenario: /curate subdivision-candidate detector.
#
# Validates the PR 3 piece of the spec-layering plan: curate-scan.sh's
# Analysis 20 should flag specs that have grown past one file's worth of
# behavior AND show multiple distinct concerns, but should NOT false-positive
# on specs that are large-but-singular or already part of a layered family.
#
# Layered cover:
#
#   1. Mature multi-concern spec triggers — synthetic spec with ≥50 reqs
#      and ≥2 section headers AND no dominant section is flagged.
#   2. Small spec does not trigger — even with multiple sections, if reqs
#      are below the size threshold it's not a candidate.
#   3. Single-section large spec does not trigger — large but tightly
#      coupled (one concern with many requirements) shouldn't be
#      surfaced as a subdivision candidate.
#   4. Dominant-section spec does not trigger — multi-section but one
#      section holds ≥90% of reqs (large-but-singular) shouldn't trigger.
#   5. Child spec (parent_spec set) does not trigger — already part of a
#      layered family.
#   6. Output table format — when a candidate is flagged, the markdown
#      summary contains a row with the right columns.
#
# Run from repo root: bash tests/scenario-curate-subdivision-candidates.sh

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
echo "scenario: /curate subdivision-candidate detector"
echo "────────────────────────────────────────────────"

# Synthetic project tree.
TMPDIR_TEST="$(mktemp -d /tmp/vallorcine-curate-subdiv.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PROJ="$TMPDIR_TEST/proj"
mkdir -p "$PROJ/.spec/registry" "$PROJ/.spec/domains/encryption" "$PROJ/.spec/domains/storage" "$PROJ/.spec/domains/util" "$PROJ/.curate"
cd "$PROJ"

# Initialize empty git repo so curate-scan's git operations don't crash.
git init -q
git config user.email test@example.com
git config user.name "Test"
git commit -q --allow-empty -m "initial"

# ── Build synthetic specs ────────────────────────────────────────────────────

# (a) Mature multi-concern spec — should trigger.
build_spec_mature() {
  local file="$1" id="$2"
  {
    cat <<EOF
---
{
  "id": "$id",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["encryption"],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": []
}
---

# $id

Cross-cutting overview.

R1. Cross-cutting wrap invariant.
R2. Cross-cutting audit invariant.
R3. Cross-cutting tenant boundary.

## Key Rotation

R10. Key rotation must run at most every 90 days.
R11. Rotation must use a fresh DEK.
R12. Rotation must publish the new key version to the audit log.
R13. Rotation must succeed atomically.
R14. Rotation must not block read traffic.
R15. Rotation must record metrics.
R16. Rotation must be idempotent.
R17. Rotation must verify pre-conditions.
R18. Rotation must log warnings on retry.
R19. Rotation must respect cooldown.
R20. Rotation must surface failures.
R21. Rotation must not regress in version.
R22. Rotation must allow opt-out.
R23. Rotation must export status.
R24. Rotation must integrate with KMS.
R25. Rotation must support dual-write window.

## DEK Management

R30. DEKs must be stored encrypted at rest.
R31. DEK access must be audited.
R32. DEKs must be disposed within 24h of last use.
R33. DEKs must be unique per object.
R34. DEKs must support cipher upgrade.
R35. DEKs must verify tenant binding.
R36. DEKs must reject reuse.
R37. DEKs must surface lookup failures.
R38. DEKs must support cache invalidation.
R39. DEKs must be observable.
R40. DEKs must record creation timestamp.
R41. DEKs must serialize predictably.
R42. DEKs must support sub-key derivation.
R43. DEKs must validate length.
R44. DEKs must reject zero values.
R45. DEKs must support recovery.
R46. DEKs must report TTL.
R47. DEKs must allow inspection.
R48. DEKs must error on corruption.

## Revocation

R55. Revocation must be effective immediately.
R56. Revocation must propagate to caches.
R57. Revocation must record reason.
R58. Revocation must support audit playback.
R59. Revocation must reject in-flight reads gracefully.
R60. Revocation must enable mass operations.
R61. Revocation must integrate with KMS.
R62. Revocation must record audit events.
R63. Revocation must support tenant batch.
R64. Revocation must guard against replay.
R65. Revocation must signal to consumers.
R66. Revocation must drain pending operations.
R67. Revocation must record the operator identity.
R68. Revocation must reject malformed requests.
R69. Revocation must surface partial failures.
R70. Revocation must reject when tenant is frozen.
R71. Revocation must integrate with audit pipeline.

---

## Notes
Original lifecycle spec covering rotation + DEK + revocation together.
EOF
  } > "$file"
}

# (b) Small spec — should NOT trigger.
build_spec_small() {
  local file="$1" id="$2"
  {
    cat <<EOF
---
{
  "id": "$id",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["util"],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": []
}
---

# $id

## A
R1. Small spec.
## B
R2. Still small.

---
## Notes
EOF
  } > "$file"
}

# (c) Single-section large spec — should NOT trigger.
build_spec_one_section() {
  local file="$1" id="$2"
  {
    cat <<EOF
---
{
  "id": "$id",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["storage"],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": []
}
---

# $id

Single tightly-coupled concern.

## Format Specification
EOF
    for i in $(seq 1 60); do
      printf "R%d. Format requirement %d describing layout invariant.\n" "$i" "$i"
    done
    cat <<'EOF'

---

## Notes
EOF
  } > "$file"
}

# (d) Dominant-section spec — should NOT trigger (one section holds ≥90% reqs).
build_spec_dominant() {
  local file="$1" id="$2"
  {
    cat <<EOF
---
{
  "id": "$id",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["storage"],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": []
}
---

# $id

## Main Concern
EOF
    for i in $(seq 1 55); do
      printf "R%d. Main concern requirement %d.\n" "$i" "$i"
    done
    cat <<EOF

## Side Note
R56. A small side note.
R57. Another small side note.

---

## Notes
EOF
  } > "$file"
}

# (e) Child spec (parent_spec set) — should NOT trigger.
build_spec_child() {
  local file="$1" id="$2" parent="$3"
  {
    cat <<EOF
---
{
  "id": "$id",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["encryption"],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": [],
  "parent_spec": "$parent"
}
---

# $id

## Child Section A
EOF
    for i in $(seq 1 25); do
      printf "R%d. Child section A requirement %d.\n" "$i" "$i"
    done
    cat <<'EOF'

## Child Section B
EOF
    for i in $(seq 26 55); do
      printf "R%d. Child section B requirement %d.\n" "$i" "$i"
    done
    cat <<EOF

---

## Notes
EOF
  } > "$file"
}

MATURE_FILE="$PROJ/.spec/domains/encryption/primitives-lifecycle.md"
SMALL_FILE="$PROJ/.spec/domains/util/small.md"
ONE_FILE="$PROJ/.spec/domains/storage/format-v3.md"
DOM_FILE="$PROJ/.spec/domains/storage/big-singular.md"
mkdir -p "$PROJ/.spec/domains/encryption/primitives-lifecycle"
CHILD_FILE="$PROJ/.spec/domains/encryption/primitives-lifecycle/child-already.md"

build_spec_mature       "$MATURE_FILE"  "encryption.primitives-lifecycle"
build_spec_small        "$SMALL_FILE"   "util.small"
build_spec_one_section  "$ONE_FILE"     "storage.format-v3"
build_spec_dominant     "$DOM_FILE"     "storage.big-singular"
build_spec_child        "$CHILD_FILE"   "encryption.primitives-lifecycle.child-already" \
                                         "encryption.primitives-lifecycle"

# Manifest with all 5 specs.
cat > "$PROJ/.spec/registry/manifest.json" <<'EOF'
{
  "schema_version": 2,
  "generated_at": "2026-04-27T00:00:00Z",
  "spec_count": 5,
  "specs": [
    {"id":"encryption.primitives-lifecycle",
     "path":".spec/domains/encryption/primitives-lifecycle.md",
     "state":"APPROVED","version":1,"domains":["encryption"],
     "requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]},
    {"id":"util.small",
     "path":".spec/domains/util/small.md",
     "state":"APPROVED","version":1,"domains":["util"],
     "requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]},
    {"id":"storage.format-v3",
     "path":".spec/domains/storage/format-v3.md",
     "state":"APPROVED","version":1,"domains":["storage"],
     "requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]},
    {"id":"storage.big-singular",
     "path":".spec/domains/storage/big-singular.md",
     "state":"APPROVED","version":1,"domains":["storage"],
     "requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]},
    {"id":"encryption.primitives-lifecycle.child-already",
     "path":".spec/domains/encryption/primitives-lifecycle/child-already.md",
     "parent_spec":"encryption.primitives-lifecycle",
     "state":"APPROVED","version":1,"domains":["encryption"],
     "requires":[],"invalidates":[],"decision_refs":[],"kb_refs":[]}
  ]
}
EOF

# Empty obligations registry (curate-scan reads it).
echo '{"obligations": []}' > "$PROJ/.spec/registry/_obligations.json"

# Empty curate state.
echo "Last scanned: " > "$PROJ/.curate/curation-state.md"

# ── Run curate-scan ──────────────────────────────────────────────────────────

echo ""
echo "── Running curate-scan against synthetic project"

cd "$PROJ"
SUMMARY_FILE="$PROJ/.curate/scan-summary.md"
bash "$REPO_ROOT/scripts/curate-scan.sh" >/tmp/curate-out.log 2>&1
rc=$?

if [[ $rc -eq 0 ]]; then
  pass "curate-scan completed without error"
else
  fail "curate-scan exited $rc" "$(tail -10 /tmp/curate-out.log)"
fi

if [[ -f "$SUMMARY_FILE" ]]; then
  pass "summary file written"
else
  fail "summary file missing: $SUMMARY_FILE"
  echo ""
  echo "────────────────────────────────────────────────"
  echo "FAILED  $failed/$total"
  exit 1
fi

# ── Layer 1: mature multi-concern spec triggered ─────────────────────────────

echo ""
echo "── Layer 1: mature spec is flagged"
if grep -q '^| encryption.primitives-lifecycle ' "$SUMMARY_FILE"; then
  pass "encryption.primitives-lifecycle appears in Subdivision Candidates"
else
  fail "mature spec NOT flagged" "$(grep -A 5 'Subdivision Candidates' "$SUMMARY_FILE" || echo '(no section)')"
fi

# Section header present.
if grep -q '^## Subdivision Candidates' "$SUMMARY_FILE"; then
  pass "Subdivision Candidates section exists in summary"
else
  fail "Subdivision Candidates section missing"
fi

# ── Layer 2: small spec NOT triggered ────────────────────────────────────────

echo ""
echo "── Layer 2: small spec is NOT flagged"
if grep -q '^| util.small ' "$SUMMARY_FILE"; then
  fail "small spec was incorrectly flagged"
else
  pass "small spec is not in Subdivision Candidates"
fi

# ── Layer 3: single-section large spec NOT triggered ─────────────────────────

echo ""
echo "── Layer 3: single-section large spec is NOT flagged"
if grep -q '^| storage.format-v3 ' "$SUMMARY_FILE"; then
  fail "single-section large spec was incorrectly flagged"
else
  pass "single-section spec is not flagged"
fi

# ── Layer 4: dominant-section spec NOT triggered ─────────────────────────────

echo ""
echo "── Layer 4: dominant-section spec is NOT flagged (one section ≥90%)"
if grep -q '^| storage.big-singular ' "$SUMMARY_FILE"; then
  fail "dominant-section spec was incorrectly flagged"
else
  pass "dominant-section spec is not flagged"
fi

# ── Layer 5: child spec NOT triggered ────────────────────────────────────────

echo ""
echo "── Layer 5: child spec (parent_spec set) is NOT flagged"
if grep -q '^| encryption.primitives-lifecycle.child-already ' "$SUMMARY_FILE"; then
  fail "child spec was incorrectly flagged" "child specs already part of layered family"
else
  pass "child spec is not flagged"
fi

# ── Layer 6: table format ────────────────────────────────────────────────────

echo ""
echo "── Layer 6: table includes expected columns"
header_line=$(grep -E '^\| Spec \| Domain \| Reqs' "$SUMMARY_FILE" | head -1)
if [[ -n "$header_line" ]]; then
  if echo "$header_line" | grep -q "Suggested"; then
    pass "table header includes Suggested column"
  else
    fail "table header missing 'Suggested'" "got: $header_line"
  fi
else
  fail "subdivision table header not found"
fi

# Suggested cell should contain `/spec-split <id>` for the mature spec.
if grep -q '`/spec-split encryption.primitives-lifecycle`' "$SUMMARY_FILE"; then
  pass "suggested command includes /spec-split <id>"
else
  fail "suggested /spec-split command missing or malformed"
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
