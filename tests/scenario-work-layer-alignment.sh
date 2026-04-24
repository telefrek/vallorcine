#!/usr/bin/env bash
# Scenario: work-layer alignment — /work-decompose Phase A/B/C + /work-status
# routing by state + work-validate --decompose invariant.
#
# Defends two bug classes surfaced on jlsm (2026-04-24):
#
#   Gap 2 — /work-status suggested /work-start for READY WDs, which /work-start
#           then rejected, creating a wrong-command round-trip.
#
#   Gap 1 — /work-decompose did no research, no architect, no spec authoring —
#           it was LLM-only scope-splitting. Each WD's /work-plan then ran
#           /feature-domains independently and re-did architecture in isolation,
#           producing divergent interpretations across parallel WDs.
#
# Structural invariants checked here (grep-based) — full end-to-end behavior
# is LLM-driven and not mechanically testable. Functional invariants where
# possible use work-validate.sh --decompose against crafted fixtures.
#
# Run from repo root: bash tests/scenario-work-layer-alignment.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-work-layer-alignment"

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
echo "scenario: work-layer alignment"
echo "────────────────────────────────────────────────"

# ── Invariant 1: /work-status routes READY WDs to /work-plan only ───────────
#
# Before this fix, Step 4 "If READY WDs exist" listed both /work-plan and
# /work-start under the same header. /work-start rejects READY. This created
# the round-trip the user hit.

echo ""
echo "── Invariant 1: /work-status READY routing"

status_skill="$REPO_ROOT/skills/work-status/SKILL.md"

if [[ ! -f "$status_skill" ]]; then
    fail "/work-status skill missing" "$status_skill"
else
    # Extract only the FIRST fenced code block inside the "If READY WDs exist"
    # section (the suggested-commands block). Explanatory prose after the block
    # may mention /work-start in a "do NOT" context, which is fine.
    ready_suggestions=$(awk '
        /^### If READY WDs exist/{in_section=1; next}
        in_section && /^### /{exit}
        in_section && /^```/{in_code=!in_code; if(!in_code){exit}; next}
        in_section && in_code{print}
    ' "$status_skill")

    if echo "$ready_suggestions" | grep -q "/work-plan"; then
        pass "/work-status READY suggestions offer /work-plan"
    else
        fail "/work-status READY suggestions do not offer /work-plan" \
             "READY WDs must be routed to /work-plan first"
    fi

    if echo "$ready_suggestions" | grep -q "/work-start"; then
        fail "/work-status READY suggestions still offer /work-start" \
             "/work-start rejects READY WDs — suggestion creates a round-trip"
    else
        pass "/work-status READY suggestions do NOT offer /work-start (correct)"
    fi

    # The --all mode block must also route correctly.
    all_block=$(awk '/^## Step 0 — List mode/,/^---$/' "$status_skill")
    if echo "$all_block" | grep -q "Route suggestions strictly by state\|must route by state"; then
        pass "/work-status --all mode has explicit state-routing discipline"
    else
        fail "/work-status --all mode lacks explicit state-routing discipline" \
             "must tell the LLM not to jumble /work-plan and /work-start"
    fi
fi

# ── Invariant 2: /work-decompose has explicit scope discipline ──────────────
#
# The skill must distinguish inter-WD coordination (decompose's job) from
# WD-internal detailing (/work-plan's job). Without this, decompose over-scopes
# and creates artifacts that should have been deferred.

echo ""
echo "── Invariant 2: /work-decompose scope discipline"

decompose_skill="$REPO_ROOT/skills/work-decompose/SKILL.md"

if [[ ! -f "$decompose_skill" ]]; then
    fail "/work-decompose skill missing" "$decompose_skill"
else
    if grep -q "shapes the relationships between chunks" "$decompose_skill"; then
        pass "/work-decompose declares scope discipline (relationships, not internals)"
    else
        fail "/work-decompose missing scope-discipline prose" \
             "must state it shapes relationships, not full scoping of each chunk"
    fi

    if grep -q "Zero new artifacts is a valid decompose outcome" "$decompose_skill"; then
        pass "/work-decompose explicitly allows zero-artifact outcomes"
    else
        fail "/work-decompose does not allow zero-artifact outcomes" \
             "atomic problems should not force research/architect passes"
    fi
fi

# ── Invariant 3: /work-decompose has Phase A/B/C structure ──────────────────

echo ""
echo "── Invariant 3: /work-decompose Phase A/B/C structure"

if [[ -f "$decompose_skill" ]]; then
    if grep -q "Phase A: Seam-finding" "$decompose_skill"; then
        pass "Phase A (seam-finding) is defined"
    else
        fail "Phase A (seam-finding) missing" \
             "decompose must have a seam-finding phase"
    fi

    if grep -q "Phase B: Architect and shared-spec authoring" "$decompose_skill"; then
        pass "Phase B (architect + spec authoring) is defined"
    else
        fail "Phase B (architect + spec authoring) missing" \
             "decompose must have a group-level architectural pass"
    fi

    if grep -q "Phase C: Finalize decomposition" "$decompose_skill"; then
        pass "Phase C (finalize) is defined"
    else
        fail "Phase C (finalize) missing" \
             "decompose must have a re-carving step after Phase B"
    fi
fi

# ── Invariant 4: Phase A dispatches /research for unknowns ──────────────────

echo ""
echo "── Invariant 4: Phase A dispatches /research subagents"

if [[ -f "$decompose_skill" ]]; then
    phase_a=$(awk '/^## Step 2 — Phase A/,/^## Step 3 — Present Phase A/' "$decompose_skill")

    if echo "$phase_a" | grep -qF 'Invoke `/research'; then
        pass "Phase A invokes /research as a subagent"
    else
        fail "Phase A does not invoke /research" \
             "seam-finding must dispatch research when unknowns block analysis"
    fi

    if echo "$phase_a" | grep -qE "Do NOT target a WD count|number falls out of the composition"; then
        pass "Phase A rejects target-count framing"
    else
        fail "Phase A still uses target-count framing" \
             "WD count must follow natural composition, not a target"
    fi
fi

# ── Invariant 5: Phase B dispatches /architect + /spec-author serially ──────

echo ""
echo "── Invariant 5: Phase B architect + spec authoring dispatches"

if [[ -f "$decompose_skill" ]]; then
    phase_b=$(awk '/^## Step 4 — Phase B/,/^## Step 5 — Phase C/' "$decompose_skill")

    if echo "$phase_b" | grep -qF 'Invoke `/architect'; then
        pass "Phase B invokes /architect for cross-WD decisions"
    else
        fail "Phase B does not invoke /architect" \
             "cross-WD decisions must go through architect deliberation"
    fi

    if echo "$phase_b" | grep -qF 'Invoke `/spec-author'; then
        pass "Phase B invokes /spec-author for shared specs"
    else
        fail "Phase B does not invoke /spec-author" \
             "shared requirements must be authored as specs (the enforcement layer)"
    fi

    if echo "$phase_b" | grep -q "Breakdown ADR"; then
        pass "Phase B documents the breakdown-ADR pattern"
    else
        fail "Phase B missing breakdown-ADR pattern" \
             "when seams are unclear, a breakdown ADR should carve the space"
    fi

    if echo "$phase_b" | grep -qE "one at a time|user-serial|serially"; then
        pass "Phase B specifies serial (user-interactive) architect passes"
    else
        fail "Phase B does not specify serial architect passes" \
             "/architect requires user deliberation; parallel dispatch is wrong"
    fi
fi

# ── Invariant 6: Phase C runs the invariant check ───────────────────────────

echo ""
echo "── Invariant 6: Phase C invariant check"

if [[ -f "$decompose_skill" ]]; then
    if grep -q "work-validate.sh --group .*--decompose" "$decompose_skill"; then
        pass "Phase C invokes work-validate.sh --decompose"
    else
        fail "Phase C does not invoke --decompose invariant" \
             "every cross-WD reference must be mechanically verified"
    fi
fi

# ── Invariant 7: produces: field is now optional ────────────────────────────

echo ""
echo "── Invariant 7: produces: field is optional in WD frontmatter"

if [[ -f "$decompose_skill" ]]; then
    # Locate the produces: rules block specifically (the one after artifact_deps rules)
    if grep -qE "Optional.*Leave empty.*produces: \[\]|produces:.*Optional" "$decompose_skill"; then
        pass "produces: field is documented as optional"
    else
        fail "produces: field is still mandatory/prediction-based" \
             "honest empty is better than LLM guesses at decompose time"
    fi
fi

# ── Invariant 8: /work-plan no-op path documented ───────────────────────────
#
# When decompose settled everything, /work-plan may have genuinely no WD-local
# work. The transition DRAFT → SPECIFIED still happens because /work-plan ran,
# but the skill must be explicit that no-op is legitimate.

echo ""
echo "── Invariant 8: /work-plan mandatory even when no-op"

# This currently lives in /work-decompose Step 8 summary — mentioning that
# /work-plan MUST run even when Phase B settled everything.
if [[ -f "$decompose_skill" ]]; then
    if grep -qE "/work-plan MUST run on every WD|Skipping /work-plan is not supported" "$decompose_skill"; then
        pass "decompose summary tells user /work-plan is mandatory for every WD"
    else
        fail "decompose summary does not enforce /work-plan-on-every-WD" \
             "without this, users skip /work-plan and bypass WD-local discipline"
    fi
fi

# ── Invariant 9: work-validate.sh --decompose mode works ────────────────────

echo ""
echo "── Invariant 9: work-validate.sh --decompose invariant (functional)"

# Fresh workspace
rm -rf "$TEST_BASE"
mkdir -p "$TEST_BASE/.work/demo-group"
mkdir -p "$TEST_BASE/.spec"
mkdir -p "$TEST_BASE/.decisions"
cd "$TEST_BASE"

# Seed a minimal work group with one WD that references a non-existent spec.
cat > .work/demo-group/work.md <<'EOF'
---
group: demo-group
goal: Test group for decompose invariant
status: active
created: 2026-04-24
---

## Goal
Test group.

## Scope
### In scope
- test

### Out of scope
- none

## Ordering Constraints
None.

## Shared Interfaces
None.

## Success Criteria
- test passes
EOF

cat > .work/demo-group/manifest.md <<'EOF'
# Manifest
EOF

# WD-01 references a spec that doesn't exist and isn't produced by anyone.
cat > .work/demo-group/WD-01.md <<'EOF'
---
id: WD-01
title: Test WD one
group: demo-group
status: DRAFT
domains: [test]
artifact_deps:
  - { type: spec, path: "test/nonexistent", required_state: APPROVED }
produces: []
---

## Summary
Test.

## Acceptance Criteria
- test passes

## Implementation Notes
None.
EOF

# Run --decompose and expect FAIL (the spec is unsettled).
if bash "$REPO_ROOT/scripts/work-validate.sh" --group demo-group --decompose >/tmp/vallorcine/decompose-out-1.txt 2>&1; then
    fail "decompose invariant passed when it should have failed (unsettled spec)" \
         "$(tail -5 /tmp/vallorcine/decompose-out-1.txt)"
else
    if grep -q "unsettled cross-WD reference" /tmp/vallorcine/decompose-out-1.txt; then
        pass "decompose invariant correctly flags unsettled spec reference"
    else
        fail "decompose invariant failed but with wrong message" \
             "$(tail -5 /tmp/vallorcine/decompose-out-1.txt)"
    fi
fi

# Now add out_of_scope to work.md and expect PASS.
cat > .work/demo-group/work.md <<'EOF'
---
group: demo-group
goal: Test group for decompose invariant
status: active
created: 2026-04-24
out_of_scope:
  - "spec:test/nonexistent"
---

## Goal
Test.

## Scope
### In scope
- test

### Out of scope
- test/nonexistent — declared out of scope for this group

## Ordering Constraints
None.

## Shared Interfaces
None.

## Success Criteria
- test passes
EOF

if bash "$REPO_ROOT/scripts/work-validate.sh" --group demo-group --decompose >/tmp/vallorcine/decompose-out-2.txt 2>&1; then
    pass "decompose invariant passes when reference is declared out_of_scope"
else
    fail "decompose invariant fails even with out_of_scope declaration" \
         "$(tail -10 /tmp/vallorcine/decompose-out-2.txt)"
fi

# Now replace out_of_scope with another WD's produces: and expect PASS.
cat > .work/demo-group/work.md <<'EOF'
---
group: demo-group
goal: Test group
status: active
created: 2026-04-24
---

## Goal
Test.

## Scope
### In scope
- test

### Out of scope
- none

## Ordering Constraints
None.

## Shared Interfaces
None.

## Success Criteria
- test passes
EOF

cat > .work/demo-group/WD-02.md <<'EOF'
---
id: WD-02
title: Test WD two — produces the spec WD-01 needs
group: demo-group
status: DRAFT
domains: [test]
artifact_deps: []
produces:
  - { type: spec, path: "test/nonexistent" }
---

## Summary
Produces the spec WD-01 consumes.

## Acceptance Criteria
- spec authored

## Implementation Notes
None.
EOF

if bash "$REPO_ROOT/scripts/work-validate.sh" --group demo-group --decompose >/tmp/vallorcine/decompose-out-3.txt 2>&1; then
    pass "decompose invariant passes when reference is satisfied by another WD's produces:"
else
    fail "decompose invariant fails when produces: lists the reference" \
         "$(tail -10 /tmp/vallorcine/decompose-out-3.txt)"
fi

# Go back to repo root for cleanup
cd "$REPO_ROOT"

# ── Invariant 10: /work-plan brief.md names the group envelope ──────────────
#
# Gap 3 — /work-plan's Step 4a brief template must declare the group envelope
# as AUTHORITATIVE so /feature-domains can defer to it instead of re-deciding.

echo ""
echo "── Invariant 10: /work-plan brief.md names Group Envelope"

plan_skill="$REPO_ROOT/skills/work-plan/SKILL.md"
if grep -q "Group Envelope" "$plan_skill" \
   && grep -q "AUTHORITATIVE" "$plan_skill" \
   && grep -qi "phase b" "$plan_skill"; then
    pass "/work-plan brief template declares Group Envelope (AUTHORITATIVE)"
else
    fail "/work-plan must document a Group Envelope section in brief.md" \
         "expected 'Group Envelope' + 'AUTHORITATIVE' + 'Phase B' in $plan_skill"
fi

# ── Invariant 11: /feature-domains reads the group envelope ──────────────────
#
# Gap 3 — /feature-domains Step 2 must consult the brief.md Group Envelope and
# classify domains covered by it as `resolved` with source annotation.

echo ""
echo "── Invariant 11: /feature-domains consumes brief's Group Envelope"

domains_skill="$REPO_ROOT/skills/feature-domains/SKILL.md"
if grep -q "Group envelope" "$domains_skill" \
   && grep -q "AUTHORITATIVE" "$domains_skill" \
   && grep -q "group envelope: <ref>" "$domains_skill"; then
    pass "/feature-domains Step 2 reads brief Group Envelope as authoritative"
else
    fail "/feature-domains must consult Group Envelope in Step 2" \
         "expected 'Group envelope' + 'AUTHORITATIVE' + source annotation in $domains_skill"
fi

# ── Invariant 12: /feature-domains escalates envelope contradictions ─────────
#
# Gap 3 — when WD-local analysis contradicts a group envelope item, the scout
# must classify `escalate-decompose` and halt rather than self-resolve.

echo ""
echo "── Invariant 12: /feature-domains flags envelope contradictions"

if grep -q "escalate-decompose" "$domains_skill" \
   && grep -q "ESCALATE to /work-decompose" "$domains_skill"; then
    pass "/feature-domains has escalate-decompose classification + halt path"
else
    fail "/feature-domains must handle envelope contradictions via escalate-decompose" \
         "expected 'escalate-decompose' state + 'ESCALATE to /work-decompose' prompt"
fi

# ── Invariant 13: Step 3 runs the escalation check before resolution ────────
#
# Gap 3 — the escalation halt must fire BEFORE Step 3's per-domain resolution
# loop, otherwise the scout would commission work against contradicted
# envelope assumptions.

echo ""
echo "── Invariant 13: /feature-domains Step 3 checks escalation first"

# Extract lines between "## Step 3" and the next "## Step" heading; the
# escalation header must appear before the per-domain resolution content.
step3_block="$(awk '/^## Step 3/,/^## Step [4-9]/' "$domains_skill")"
if echo "$step3_block" | grep -q "Escalation check (always first)" \
   && echo "$step3_block" | grep -q "domains-escalated-decompose"; then
    pass "/feature-domains Step 3 fires escalation check before resolution"
else
    fail "/feature-domains Step 3 must start with escalation check" \
         "expected 'Escalation check (always first)' in Step 3 block"
fi

# ── Invariant 14: /work-plan Step 5b dedupes against the envelope ───────────
#
# Gap 3 — /work-plan must NOT re-author group-level specs already listed in
# the WD's artifact_deps. This is what keeps group and WD specs from forking.

echo ""
echo "── Invariant 14: /work-plan Step 5b skips envelope-covered specs"

step5b_block="$(awk '/^## Step 5b/,/^## Step 6/' "$plan_skill")"
if echo "$step5b_block" | grep -qi "dedupe against the group envelope" \
   && echo "$step5b_block" | grep -q "artifact_deps" \
   && echo "$step5b_block" | grep -q "deferred to group-level spec"; then
    pass "/work-plan Step 5b dedupes spec authoring against artifact_deps"
else
    fail "/work-plan Step 5b must skip specs already covered by group envelope" \
         "expected 'dedupe against the group envelope' + 'artifact_deps' + 'deferred to group-level spec'"
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
