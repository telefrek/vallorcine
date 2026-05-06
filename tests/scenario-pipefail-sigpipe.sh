#!/usr/bin/env bash
# Scenario: scripts that pipe potentially-large stdin into early-closing
# tools must use here-strings (`<<< "$var"`) instead of `echo "$var" |`,
# otherwise SIGPIPE under `set -o pipefail` flips the pipeline result on
# unusually large inputs.
#
# Triggered by a real failure on jlsm 2026-04-27: spec-validate.sh's
# `echo "$spec_body" | grep -qE '\[UNRESOLVED\]'` check exit-141'd on
# encryption.primitives-lifecycle once its machine section reached
# ~134 KB. `grep -q` closed stdin after determining no match was needed,
# `echo` got SIGPIPE, the pipeline exited 141, pipefail propagated it,
# and the negated check treated 141 as success — so APPROVED specs
# could silently pass even with [UNRESOLVED] markers present.
#
# Two layers of defence:
#
#   1. Structural — for the seven known-large-stdin sites in three
#      scripts, assert the script uses here-string form. Drift detection
#      so regressions cannot sneak back in via copy-paste.
#
#   2. Runtime — synthesize a spec whose machine section is well over the
#      pipe buffer (~880 KB), wire up a minimal `.spec/` so spec-validate
#      runs end-to-end, and confirm validation returns successfully. Under
#      the bug the script either crashes (rc=141) or returns a wrong
#      answer; under the fix it succeeds.
#
# Run from repo root: bash tests/scenario-pipefail-sigpipe.sh

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
echo "scenario: pipefail SIGPIPE on large stdin"
echo "────────────────────────────────────────────────"

# ── Layer 1: structural — patched lines must use here-strings ────────────────

echo ""
echo "── Layer 1: known-large-stdin sites use here-strings (drift detection)"

# For each known site, assert the post-fix shape is present (grep -F:
# the line is matched as a fixed substring) and the pre-fix shape is
# absent. The pre-fix shape is matched with grep -F too.
check_site() {
    local file="$1"; local desc="$2"; local required="$3"; local forbidden="$4"
    if ! [[ -f "$file" ]]; then
        fail "$desc" "file missing: $file"
        return
    fi
    if grep -qF "$forbidden" "$file" 2>/dev/null; then
        fail "$desc" "forbidden substring still present: $forbidden"
        return
    fi
    if ! grep -qF "$required" "$file" 2>/dev/null; then
        fail "$desc" "required substring missing: $required"
        return
    fi
    pass "$desc"
}

# spec-validate.sh — three known-dangerous sites
check_site "$REPO_ROOT/scripts/spec-validate.sh" \
    "spec-validate Check 9b uses <<< for [UNRESOLVED]" \
    'grep -qE '"'"'\[UNRESOLVED\]'"'"' <<< "$spec_body"' \
    'echo "$spec_body" | grep -qE '"'"'\[UNRESOLVED\]'"'"

check_site "$REPO_ROOT/scripts/spec-validate.sh" \
    "spec-validate Check 9b uses <<< for [CONFLICT]" \
    'grep -qE '"'"'\[CONFLICT\]'"'"' <<< "$spec_body"' \
    'echo "$spec_body" | grep -qE '"'"'\[CONFLICT\]'"'"

check_site "$REPO_ROOT/scripts/spec-validate.sh" \
    "spec-validate Check 11 uses <<< for ^R[0-9]+ requirements" \
    'grep -qE '"'"'^R[0-9]+[a-z]*(-[0-9]+[a-z]*)?\.'"'"' <<< "$machine"' \
    'echo "$machine" | grep -qE '"'"'^R[0-9]+'"'"

# kb-search.sh — content_lower (KB index content) is unbounded for big indexes
check_site "$REPO_ROOT/scripts/kb-search.sh" \
    "kb-search uses <<< for content_lower token check" \
    'grep -q "$token" <<< "$content_lower"' \
    'echo "$content_lower" | grep -q "$token"'

# curate-scan.sh — trace_out is unbounded for large /spec-trace output
check_site "$REPO_ROOT/scripts/curate-scan.sh" \
    "curate-scan uses <<< for No annotations check" \
    'grep -q '"'"'\*\*No annotations found\.\*\*'"'"' <<< "$trace_out"' \
    'echo "$trace_out" | grep -q '"'"'\*\*No annotations found'"'"

check_site "$REPO_ROOT/scripts/curate-scan.sh" \
    "curate-scan uses <<< for No implementation annotations" \
    'grep -m1 '"'"'^\*\*No implementation annotations:\*\*'"'"' <<< "$trace_out"' \
    'echo "$trace_out" | grep -m1 '"'"'^\*\*No implementation'"'"

check_site "$REPO_ROOT/scripts/curate-scan.sh" \
    "curate-scan uses <<< for No test annotations" \
    'grep -m1 '"'"'^\*\*No test annotations:\*\*'"'"' <<< "$trace_out"' \
    'echo "$trace_out" | grep -m1 '"'"'^\*\*No test annotations'"'"

# ── Layer 2: runtime — spec-validate must not SIGPIPE on a >1MB spec body ────

echo ""
echo "── Layer 2: spec-validate handles a 1 MB machine section without SIGPIPE"

TMPDIR_TEST="$(mktemp -d -t /tmp/vallorcine/pipefail-XXXXXX 2>/dev/null \
                || mktemp -d /tmp/vallorcine-pipefail.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Minimal .spec/ scaffolding — spec-validate.sh requires it to exist.
mkdir -p "$TMPDIR_TEST/.spec/registry" "$TMPDIR_TEST/.spec/domains/test"
cat > "$TMPDIR_TEST/.spec/registry/manifest.json" <<'EOF'
{ "schema_version": 2, "specs": [] }
EOF

LARGE_SPEC="$TMPDIR_TEST/.spec/domains/test/large-spec.md"

{
    cat <<'EOF'
---
{
  "id": "test.large-spec",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["test"],
  "requires": [],
  "invalidates": [],
  "amends": null,
  "amended_by": null,
  "decision_refs": [],
  "kb_refs": [],
  "related": [],
  "title": "synthetic large spec for SIGPIPE regression",
  "description": "synthetic large spec for SIGPIPE regression"
}
---

# Large spec — SIGPIPE regression

Human-readable narrative would normally go here. The requirements list
below this point lives in the machine section (between the 2nd and 3rd
`---` lines).

EOF
    # Generate ~1 MB of unique requirement lines, in the machine section.
    for i in $(seq 1 8000); do
        printf "R%d. The system MUST handle requirement number %d with %s\n" \
            "$i" "$i" "consistent and observable behavior across all states."
    done
    cat <<'EOF'

---

## Notes (post-machine narrative)
EOF
} > "$LARGE_SPEC"

spec_size=$(wc -c < "$LARGE_SPEC")
spec_size_kb=$(( spec_size / 1024 ))
echo "  → synthesized spec: ${spec_size_kb} KB"

if (( spec_size_kb < 256 )); then
    fail "synthetic spec too small for SIGPIPE check" \
         "spec is ${spec_size_kb} KB; need ≥256 KB to overflow pipe buffer"
else
    pass "synthetic spec exceeds pipe buffer (${spec_size_kb} KB)"
fi

# Run spec-validate against the synthetic spec from inside a working tree
# that contains the minimal .spec/ scaffolding.
val_out=""; val_rc=0
val_out="$(cd "$TMPDIR_TEST" && bash "$REPO_ROOT/scripts/spec-validate.sh" "$LARGE_SPEC" 2>&1)" || val_rc=$?

if [[ $val_rc -eq 0 ]]; then
    pass "spec-validate passes on ${spec_size_kb} KB spec (rc=0)"
elif [[ $val_rc -eq 141 ]]; then
    fail "spec-validate hit SIGPIPE (rc=141) — fix regressed" \
         "first lines: $(printf '%s' "$val_out" | head -3 | tr '\n' '|')"
else
    fail "spec-validate returned $val_rc — investigate" \
         "first lines: $(printf '%s' "$val_out" | head -5 | tr '\n' '|')"
fi

# Bonus assertion: confirm fixture has the requirement count we wrote.
expected_reqs=8000
actual_reqs=$(grep -cE '^R[0-9]+\.' "$LARGE_SPEC" || true)
if (( actual_reqs == expected_reqs )); then
    pass "synthetic spec has ${expected_reqs} requirements as expected"
else
    fail "synthetic spec requirement count mismatch" \
         "expected $expected_reqs, got $actual_reqs"
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
