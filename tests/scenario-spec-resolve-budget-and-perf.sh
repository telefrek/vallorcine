#!/usr/bin/env bash
# Scenario: spec-resolve.sh budget defaults and Step 7b conflict-scan perf.
#
# Empirical bugs surfaced during jlsm membership-domain feature planning
# (2026-05-03):
#   Bug 1 — Default 8000-token budget produces empty bundles for mature
#           spec corpora (individual specs ~9-12K tokens each).
#   Bug 2 — Step 7b conflict scan fanned out tens of thousands of grep/tr
#           subprocesses per requirement line; took 30s+ for a single
#           ~10K-token spec, hung the script entirely on multi-spec bundles.
#
# These tests fail on current main and pass after the fix.
#
# Run from repo root: bash tests/scenario-spec-resolve-budget-and-perf.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-spec-resolve-budget-and-perf"

passed=0
failed=0
total=0

pass() {
    ((passed++)) || true
    ((total++)) || true
    echo "  PASS  $1"
    return 0
}

fail() {
    ((failed++)) || true
    ((total++)) || true
    echo "  FAIL  $1"
    [[ -n "${2:-}" ]] && echo "        $2"
    return 0
}

cleanup() {
    rm -rf "$TEST_BASE" 2>/dev/null || true
}
trap cleanup EXIT

echo ""
echo "scenario: spec-resolve budget defaults + Step 7b perf"
echo "────────────────────────────────────────────────────────"

cleanup
mkdir -p "$TEST_BASE/project/.spec/registry/" \
         "$TEST_BASE/project/.spec/domains/membership/" \
         "$TEST_BASE/project/.claude/scripts/"

cp "$REPO_ROOT/scripts/spec-resolve.sh" "$TEST_BASE/project/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh" "$TEST_BASE/project/.claude/scripts/"

# ── Build a synthetic spec at a target token count ──────────────────────────
# Token estimator (spec-lib.sh): 1 token ≈ 4 chars.
# Each requirement line carries ~25 CamelCase / snake_case tokens so Step 7b's
# subject-token scan exercises the same hot path it would on a real spec.
build_spec() {
    local id="$1"
    local target_tokens="$2"
    local file="$TEST_BASE/project/.spec/domains/membership/${id}.md"
    local target_chars=$(( target_tokens * 4 ))

    {
        cat <<HDR
---
{
  "id": "membership.${id}",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["membership"],
  "amends": [],
  "amended_by": [],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": [],
  "open_obligations": []
}
---

# membership.${id}

## Requirements
HDR

        local i=0 body_chars=0
        local line='R%d. The MembershipCoordinator must validate the cluster_member entry against the EventContract schema and emit ClusterHealthEvent when the recovery_state transitions. The validate_partition routine must accept a NodeIdentifier within the partition_window and reject a stale heartbeat older than the configured threshold.'
        while (( body_chars < target_chars )); do
            i=$((i + 1))
            local rendered
            rendered=$(printf "$line" "$i")
            echo "$rendered"
            body_chars=$(( body_chars + ${#rendered} + 1 ))
        done

        cat <<'TRAILER'

---

## Design Narrative

### Intent
Synthetic spec for resolver budget + perf scenario tests.
TRAILER
    } > "$file"
}

# Build 2 specs that individually exceed the 8000-token default.
build_spec "cluster-health" 10000
build_spec "event-contract" 12000

# v2 manifest
cat > "$TEST_BASE/project/.spec/registry/manifest.json" <<'EOF'
{
  "schema_version": 2,
  "spec_count": 2,
  "specs": [
    { "id": "membership.cluster-health", "path": ".spec/domains/membership/cluster-health.md", "state": "APPROVED", "version": 1, "domains": ["membership"], "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": [] },
    { "id": "membership.event-contract", "path": ".spec/domains/membership/event-contract.md", "state": "APPROVED", "version": 1, "domains": ["membership"], "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": [] }
  ]
}
EOF

cd "$TEST_BASE/project"

# ── Test 1: Bundle MUST include at least one direct match even at low budget ─
# Bug 1 root cause: every individual candidate exceeded the 8000-token default,
# so Step 5 omitted them all and the bundle was empty (just headers).
# Contract: when the candidate set is non-empty, the bundle must include the
# largest-fitting spec or, if no spec fits, the smallest direct match,
# rather than emit an empty Feature Requirements section.

echo ""
echo "── Test 1: low budget never yields an empty bundle when candidates exist"

out_low="$(timeout 30 bash .claude/scripts/spec-resolve.sh "membership" 8000 2>/dev/null)" || true
# Feature Requirements section must contain at least one membership spec heading
# (`# membership.<id>`) — the script must force-include the smallest direct
# match rather than emit an empty Requirements section when every candidate
# exceeds the budget.
feature_section=$(echo "$out_low" | sed -n '/^## Feature Requirements/,/^## /p')
if echo "$out_low" | grep -q "^## Feature Requirements" \
    && echo "$feature_section" | grep -q "membership\."; then
    pass "low-budget bundle includes at least one membership spec"
else
    fail "bundle is empty when individual specs exceed budget" \
         "head: $(echo "$out_low" | head -10)"
fi

# ── Test 2: Realistic default budget loads multiple membership specs ─────────
# After the fix, the default budget bumps to 25000 — large enough to fit two
# typical mature specs.

echo ""
echo "── Test 2: 25000-budget bundle includes both specs"

out_default="$(timeout 30 bash .claude/scripts/spec-resolve.sh "membership" 25000 2>/dev/null)" || true
included=0
echo "$out_default" | grep -q "membership.cluster-health" && included=$((included + 1))
echo "$out_default" | grep -q "membership.event-contract" && included=$((included + 1))
if (( included == 2 )); then
    pass "both membership specs included in 25000-token bundle"
else
    fail "expected both specs in 25000-token bundle (got $included/2)"
fi

# ── Test 3: Resolver completes within wall-clock budget on real-sized specs ──
# Bug 2 root cause: per-requirement tr/grep/sort + per-token antonym grep
# fanout in Step 7b. A single ~10K spec with ~150 requirements took 30s+;
# multi-spec bundles hung indefinitely. Contract: the resolver must finish
# within 10s on the 2-spec, ~22K-token bundle this fixture builds.

echo ""
echo "── Test 3: resolver finishes within 10s on 2-spec membership bundle"

started=$(date +%s)
timeout 15 bash .claude/scripts/spec-resolve.sh "membership" 25000 \
    > /tmp/vallorcine/scenario-spec-resolve-budget-and-perf-out.txt 2>/dev/null \
    || true
elapsed=$(( $(date +%s) - started ))

if (( elapsed <= 10 )); then
    pass "resolver completed in ${elapsed}s (≤ 10s budget)"
else
    fail "resolver took ${elapsed}s on 2-spec bundle (budget: 10s)" \
         "Step 7b conflict scan likely still in bash subprocess loop"
fi

# ── Test 4: Conflict scan still detects real antonym-pair contradictions ─────
# Guards against the perf rewrite silently dropping conflict detection.
# Build two specs where one says "must accept YAML" and the other "must
# reject YAML" with a shared CamelCase subject. The bundle's ## Conflicts
# section must surface the pair.

build_spec_with_text() {
    local id="$1"
    local body="$2"
    local file="$TEST_BASE/project/.spec/domains/membership/${id}.md"
    cat > "$file" <<EOF
---
{
  "id": "membership.${id}",
  "version": 1,
  "status": "ACTIVE",
  "state": "APPROVED",
  "domains": ["membership"],
  "amends": [],
  "amended_by": [],
  "requires": [],
  "invalidates": [],
  "decision_refs": [],
  "kb_refs": [],
  "open_obligations": []
}
---

# membership.${id}

## Requirements
${body}

---

## Design Narrative

### Intent
Conflict-detection regression fixture.
EOF
}

build_spec_with_text "format-accept" "R1. The SerializerComponent must accept YamlDocument input and produce a parsed tree."
build_spec_with_text "format-reject" "R1. The SerializerComponent must reject YamlDocument input and surface a clear error."

cat > "$TEST_BASE/project/.spec/registry/manifest.json" <<'EOF'
{
  "schema_version": 2,
  "spec_count": 2,
  "specs": [
    { "id": "membership.format-accept", "path": ".spec/domains/membership/format-accept.md", "state": "APPROVED", "version": 1, "domains": ["membership"], "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": [] },
    { "id": "membership.format-reject", "path": ".spec/domains/membership/format-reject.md", "state": "APPROVED", "version": 1, "domains": ["membership"], "requires": [], "invalidates": [], "decision_refs": [], "kb_refs": [] }
  ]
}
EOF

echo ""
echo "── Test 4: conflict scan still detects accept-vs-reject antonym pair"

out_conflict="$(timeout 15 bash .claude/scripts/spec-resolve.sh "membership" 25000 2>/dev/null)" || true
if echo "$out_conflict" | grep -q "^## Conflicts" \
   && echo "$out_conflict" | grep -qE "CONFLICT:.*format-(accept|reject).*(accept|reject)"; then
    pass "antonym-pair conflict detected between accept and reject specs"
else
    fail "conflict detection regressed — accept/reject pair not surfaced" \
         "conflicts section: $(echo "$out_conflict" | sed -n '/## Conflicts/,$p')"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────────────"
if [[ $failed -eq 0 ]]; then
    echo "ALL PASSED  ($passed/$total)"
else
    echo "FAILED  $failed/$total  ($passed passed)"
fi
echo ""

exit $failed
