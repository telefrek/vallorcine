#!/usr/bin/env bash
# Scenario: two unrelated kit defects fixed in one PR.
#
#   Bug A — work_check_adr_dep had asymmetric quote handling. The WD-side
#           parser stripped surrounding single/double quotes from values
#           (work_fm_artifact_deps, scripts/work-lib.sh:151) but the ADR-side
#           extractor did not (scripts/work-lib.sh:378). An ADR with quoted
#           YAML status (`status: "accepted"`) compared against an unquoted
#           WD `required_status: accepted` would never match — every
#           ADR-status check silently failed, blocking dependent WDs.
#
#   Bug B — Narrative parser dropped phases for work-driven feature slugs.
#           For feature_slug like "<group>--wd-NN", the slug filter at
#           scripts/narrative/parse.py:462-491 rejected /work-start and
#           /work-plan invocations whose args were "<group> <N>", because
#           the slug variants ("<group>--wd-NN", "<group>  wd NN") were
#           not substrings of "<group> <N>". With every parent phase
#           filtered out, all subagent activity (the actual /feature-*
#           dispatch) went with it, producing an empty phases list and
#           "narrative: no phases parsed for slug" at runtime.
#
# Both fixes ship together because both are user-reported bug surfaces in
# the same kit-internal layer (work-* skills). Tests written first, both
# fail on current main.
#
# Run from repo root: bash tests/scenario-work-adr-quote-and-narrative-wd.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_BASE="/tmp/vallorcine/scenario-work-adr-quote-and-narrative-wd"
NARRATIVE_DIR="$REPO_ROOT/scripts/narrative"

passed=0
failed=0
total=0
skipped=0

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
skip() {
    ((skipped++)) || true
    echo "  SKIP  $1"
    return 0
}

cleanup() { rm -rf "$TEST_BASE" 2>/dev/null || true; }
trap cleanup EXIT

echo ""
echo "scenario: work_check_adr_dep quote handling + narrative WD-slug filter"
echo "──────────────────────────────────────────────────────────────────────────"

cleanup
mkdir -p "$TEST_BASE"

# ── Bug A: ADR quote handling ───────────────────────────────────────────────

PROJECT="$TEST_BASE/project"
git init --initial-branch=main "$PROJECT" >/dev/null 2>&1
git -C "$PROJECT" config user.email "test@test.com"
git -C "$PROJECT" config user.name "Test"
mkdir -p "$PROJECT/.claude/scripts" \
         "$PROJECT/.work/auth-migration" \
         "$PROJECT/.decisions/token-format" \
         "$PROJECT/.spec/registry"

cp "$REPO_ROOT/scripts/work-lib.sh"      "$PROJECT/.claude/scripts/"
cp "$REPO_ROOT/scripts/work-resolve.sh"  "$PROJECT/.claude/scripts/"
cp "$REPO_ROOT/scripts/spec-lib.sh"      "$PROJECT/.claude/scripts/"

# Empty spec manifest (work-resolve looks for it; not needed for this test).
echo '{"schema_version": 2, "spec_count": 0, "specs": []}' \
    > "$PROJECT/.spec/registry/manifest.json"

# Group manifest.
cat > "$PROJECT/.work/auth-migration/work.md" <<'EOF'
---
group: auth-migration
status: ACTIVE
---

# Auth Migration

## Summary
Group manifest.
EOF

# WD-01 declares an ADR dep with UNQUOTED required_status (the WD-parser side
# strips quotes anyway, so this is the cleaner half of the comparison).
cat > "$PROJECT/.work/auth-migration/WD-01.md" <<'EOF'
---
id: WD-01
title: Implement token validator
group: auth-migration
status: DRAFT
domains: [auth]
artifact_deps:
  - { type: adr, slug: "token-format", required_status: accepted }
---

## Summary
Build the token validator against the accepted ADR.

## Acceptance Criteria
- The validator rejects malformed tokens.
EOF

# ── Test 1: ADR with QUOTED status matches unquoted WD required_status ──────
# This is the user-reported defect: ADR has `status: "accepted"` (quoted) and
# the WD requires `required_status: accepted`. Pre-fix, work_check_adr_dep's
# awk extracted the literal `"accepted"` (with quotes) and the comparison
# `"accepted" != accepted` always failed, BLOCKING the WD.

echo ""
echo "── Test 1: ADR with quoted YAML status matches unquoted WD required_status"

cat > "$PROJECT/.decisions/token-format/adr.md" <<'EOF'
---
problem: token-format
date: 2026-04-11
version: 1
status: "accepted"
---

# Token Format

## Decision
Use JWT with RS256.
EOF

output=$(cd "$PROJECT" && bash .claude/scripts/work-resolve.sh auth-migration 2>&1)
if echo "$output" | grep "WD-01" | grep -q "READY"; then
    pass "WD-01 with quoted ADR status resolves to READY"
else
    fail "WD-01 should be READY when ADR status is 'accepted' (quoted)" \
         "got: $(echo "$output" | grep WD-01)"
fi

# ── Test 2: Mismatched status still BLOCKS (no false positives) ─────────────
# Negative test — the fix must not make every ADR check pass. A genuinely
# mismatched status (ADR=draft, WD wants accepted) must still BLOCK.

echo ""
echo "── Test 2: ADR status mismatch (draft vs accepted) still BLOCKS"

cat > "$PROJECT/.decisions/token-format/adr.md" <<'EOF'
---
problem: token-format
date: 2026-04-11
version: 1
status: "draft"
---

# Token Format

## Decision
Use JWT with RS256.
EOF

output=$(cd "$PROJECT" && bash .claude/scripts/work-resolve.sh auth-migration 2>&1)
if echo "$output" | grep "WD-01" | grep -q "BLOCKED"; then
    pass "WD-01 BLOCKED when ADR status is genuinely wrong (no false-positive resolution)"
else
    fail "WD-01 should be BLOCKED on draft ADR" \
         "got: $(echo "$output" | grep WD-01)"
fi

# ── Test 3: Single-quoted ADR status also matches ───────────────────────────
# YAML allows both `status: "accepted"` and `status: 'accepted'`. The WD-side
# parser strips both quote styles, so the ADR-side fix must too.

echo ""
echo "── Test 3: ADR with single-quoted status matches"

cat > "$PROJECT/.decisions/token-format/adr.md" <<EOF
---
problem: token-format
date: 2026-04-11
version: 1
status: 'accepted'
---

# Token Format

## Decision
Use JWT with RS256.
EOF

output=$(cd "$PROJECT" && bash .claude/scripts/work-resolve.sh auth-migration 2>&1)
if echo "$output" | grep "WD-01" | grep -q "READY"; then
    pass "WD-01 resolves with single-quoted ADR status"
else
    fail "WD-01 should be READY when ADR status is 'accepted' (single-quoted)" \
         "got: $(echo "$output" | grep WD-01)"
fi

# ── Test 4: Unquoted ADR status keeps working (backwards compat) ────────────

echo ""
echo "── Test 4: unquoted ADR status keeps working"

cat > "$PROJECT/.decisions/token-format/adr.md" <<'EOF'
---
problem: token-format
date: 2026-04-11
version: 1
status: accepted
---

# Token Format

## Decision
Use JWT with RS256.
EOF

output=$(cd "$PROJECT" && bash .claude/scripts/work-resolve.sh auth-migration 2>&1)
if echo "$output" | grep "WD-01" | grep -q "READY"; then
    pass "unquoted ADR status still resolves WD to READY"
else
    fail "unquoted ADR should still work after fix" \
         "got: $(echo "$output" | grep WD-01)"
fi

# ── Bug B: Narrative parse drops phases for WD-suffixed slugs ───────────────
# Synthetic TokenStream → parse_story → expect non-empty phases when
# feature_slug is "<group>--wd-NN" and the JSONL contains a /work-start or
# /work-plan invocation for "<group> <N>".

if ! command -v python3 &>/dev/null; then
    skip "Bug B narrative tests (python3 not available)"
else
    # ── Test 5: parse_story finds a phase for /work-start with WD slug ──────
    echo ""
    echo "── Test 5: parse_story finds phases for '<group>--wd-NN' against /work-start <group> <N>"

    py_out=$(python3 - <<PY 2>&1 || true
import sys
sys.path.insert(0, "$NARRATIVE_DIR")
from model import Token, TokenStream
from parse import parse_story

# Build a minimal synthetic stream containing a /work-start command and an
# inline tool call so the phase has at least one child.
stream = TokenStream(sessions=["s1"], project="p")
stream.tokens.append(Token(
    type="command",
    timestamp="2026-05-05T00:00:00Z",
    content="/work-start \"add-compaction-scheduling\" 1",
    metadata={"name": "/work-start", "args": "add-compaction-scheduling 1"},
))
stream.tokens.append(Token(
    type="agent_prose",
    timestamp="2026-05-05T00:00:01Z",
    content="working on add-compaction-scheduling--wd-01",
    metadata={},
))
stream.tokens.append(Token(
    type="tool_call",
    timestamp="2026-05-05T00:00:02Z",
    content="",
    metadata={"tool": "Bash", "input_summary": "ls", "target": ""},
))
stream.tokens.append(Token(
    type="session_end",
    timestamp="2026-05-05T00:00:30Z",
    content="",
    metadata={"session_id": "s1", "reason": "stop"},
))

story = parse_story(stream, feature_slug="add-compaction-scheduling--wd-01")
if not story.phases:
    print(f"FAIL: phases empty for WD-suffixed slug")
    sys.exit(1)
print(f"OK: parsed {len(story.phases)} phase(s)")
PY
)
    if echo "$py_out" | grep -q "^OK:"; then
        pass "parse_story produces phases for '<group>--wd-NN' against /work-start"
    else
        fail "parse_story dropped phases for WD-suffixed slug" "$py_out"
    fi

    # ── Test 6: /work-plan invocation also matches WD-suffixed slug ─────────
    echo ""
    echo "── Test 6: /work-plan <group> <N> also matches '<group>--wd-NN'"

    py_out=$(python3 - <<PY 2>&1 || true
import sys
sys.path.insert(0, "$NARRATIVE_DIR")
from model import Token, TokenStream
from parse import parse_story

stream = TokenStream(sessions=["s1"], project="p")
stream.tokens.append(Token(
    type="command",
    timestamp="2026-05-05T00:00:00Z",
    content="/work-plan \"add-compaction-scheduling\" 2",
    metadata={"name": "/work-plan", "args": "add-compaction-scheduling 2"},
))
stream.tokens.append(Token(
    type="agent_prose",
    timestamp="2026-05-05T00:00:05Z",
    content="planning",
    metadata={},
))
stream.tokens.append(Token(
    type="session_end",
    timestamp="2026-05-05T00:00:10Z",
    content="",
    metadata={"session_id": "s1", "reason": "stop"},
))

story = parse_story(stream, feature_slug="add-compaction-scheduling--wd-02")
if not story.phases:
    print("FAIL: phases empty for /work-plan match")
    sys.exit(1)
print(f"OK: parsed {len(story.phases)} phase(s)")
PY
)
    if echo "$py_out" | grep -q "^OK:"; then
        pass "/work-plan <group> <N> matches WD-suffixed feature_slug"
    else
        fail "/work-plan invocation should match '<group>--wd-NN'" "$py_out"
    fi

    # ── Test 7: WD number mismatch still rejects (no false positives) ───────
    echo ""
    echo "── Test 7: /work-start with wrong WD number does NOT match"

    py_out=$(python3 - <<PY 2>&1 || true
import sys
sys.path.insert(0, "$NARRATIVE_DIR")
from model import Token, TokenStream
from parse import parse_story

# /work-start dispatched WD-99 but feature_slug asks for WD-01 → must reject.
stream = TokenStream(sessions=["s1"], project="p")
stream.tokens.append(Token(
    type="command",
    timestamp="2026-05-05T00:00:00Z",
    content="/work-start \"add-compaction-scheduling\" 99",
    metadata={"name": "/work-start", "args": "add-compaction-scheduling 99"},
))
stream.tokens.append(Token(
    type="agent_prose",
    timestamp="2026-05-05T00:00:01Z",
    content="working on WD-99",
    metadata={},
))
stream.tokens.append(Token(
    type="session_end",
    timestamp="2026-05-05T00:00:10Z",
    content="",
    metadata={"session_id": "s1", "reason": "stop"},
))

story = parse_story(stream, feature_slug="add-compaction-scheduling--wd-01")
if story.phases:
    print(f"FAIL: WD-99 phase leaked into WD-01 narrative ({len(story.phases)} phases)")
    sys.exit(1)
print("OK: WD-99 phase correctly rejected")
PY
)
    if echo "$py_out" | grep -q "^OK:"; then
        pass "WD number mismatch correctly rejects (no false positives)"
    else
        fail "WD-99 should not match feature_slug ending in --wd-01" "$py_out"
    fi

    # ── Test 8: Group prefix mismatch still rejects ─────────────────────────
    echo ""
    echo "── Test 8: different group prefix does NOT match"

    py_out=$(python3 - <<PY 2>&1 || true
import sys
sys.path.insert(0, "$NARRATIVE_DIR")
from model import Token, TokenStream
from parse import parse_story

stream = TokenStream(sessions=["s1"], project="p")
stream.tokens.append(Token(
    type="command",
    timestamp="2026-05-05T00:00:00Z",
    content="/work-start \"different-group\" 1",
    metadata={"name": "/work-start", "args": "different-group 1"},
))
stream.tokens.append(Token(
    type="session_end",
    timestamp="2026-05-05T00:00:05Z",
    content="",
    metadata={"session_id": "s1", "reason": "stop"},
))

story = parse_story(stream, feature_slug="add-compaction-scheduling--wd-01")
if story.phases:
    print(f"FAIL: different-group phase leaked into add-compaction-scheduling narrative ({len(story.phases)} phases)")
    sys.exit(1)
print("OK: different-group phase correctly rejected")
PY
)
    if echo "$py_out" | grep -q "^OK:"; then
        pass "different group prefix correctly rejects"
    else
        fail "different group should not match feature_slug" "$py_out"
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "──────────────────────────────────────────────────────────────────────────"
if [[ $failed -eq 0 ]]; then
    echo "ALL PASSED  ($passed/$total · $skipped skipped)"
else
    echo "FAILED  $failed/$total  ($passed passed · $skipped skipped)"
fi
echo ""

exit $failed
