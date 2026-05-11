#!/usr/bin/env bash
# Scenario: --nested flag prevents /feature-coordinate from running inside
# a /work-start or /work-run dispatched sub-agent.
#
# Background. The user hit a real bug on jlsm: /work-start dispatched a
# sub-agent that ran /feature-plan, which (because the WD's
# execution_strategy was balanced) invoked /feature-coordinate, which
# tried to dispatch its own work-unit sub-agents via Agent. Nested Agent
# dispatch isn't supported in dispatched sub-agent contexts, so the
# pipeline broke.
#
# Fix: /work-start grows a --nested flag. When set, Step 4c writes
# nested_in_dispatch: true + execution_strategy: cost into status.md.
# /feature-plan honors the flag by forcing execution_strategy: cost
# (bypassing /feature-coordinate). /feature-coordinate has a defensive
# Step 0 guard that errors if invoked with the flag set.
#
# This is a contract-validation test — SKILL.md text + flag wiring.
# Runtime LLM behavior is out of scope.
#
# Run from repo root: bash tests/scenario-nested-dispatch.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

WORK_START="$REPO_ROOT/skills/work-start/SKILL.md"
WORK_RUN="$REPO_ROOT/skills/work-run/SKILL.md"
FEATURE_PLAN="$REPO_ROOT/skills/feature-plan/SKILL.md"
FEATURE_COORDINATE="$REPO_ROOT/skills/feature-coordinate/SKILL.md"

passed=0
failed=0
total=0

pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }

echo ""
echo "scenario: --nested dispatch flag"
echo "────────────────────────────────────────────────"

# ── /work-start advertises --nested in argument-hint + header ───────────────

echo ""
echo "  /work-start exposes --nested"
echo "  ───────────────────────────"

if grep -qE -- '^argument-hint:.*--nested' "$WORK_START"; then
    pass "argument-hint lists --nested"
else
    fail "--nested missing from argument-hint"
fi

if grep -qE -- '^# /work-start.*--nested' "$WORK_START"; then
    pass "usage header lists --nested"
else
    fail "usage header missing --nested"
fi

# ── Step 4c documents the --nested status.md fields ─────────────────────────

echo ""
echo "  Step 4c writes nested_in_dispatch + execution_strategy"
echo "  ────────────────────────────────────────────────────"

step4c=$(awk '/^### 4c — Write status.md/,/^### 4d/' "$WORK_START")

if echo "$step4c" | grep -qF -- "--nested"; then
    pass "Step 4c references --nested flag"
else
    fail "Step 4c missing --nested handling"
fi

if echo "$step4c" | grep -qF "nested_in_dispatch: true"; then
    pass "Step 4c writes nested_in_dispatch: true"
else
    fail "Step 4c missing nested_in_dispatch field"
fi

if echo "$step4c" | grep -qF "execution_strategy: cost"; then
    pass "Step 4c forces execution_strategy: cost when nested"
else
    fail "Step 4c missing execution_strategy: cost"
fi

# Why-section reasoning must be documented (so future readers don't remove it)
if echo "$step4c" | grep -qiE "nested.*Agent.*call|cannot.*dispatch|nested.*sub-agent"; then
    pass "Step 4c explains why nesting fails"
else
    fail "Step 4c missing the explanation of WHY"
fi

# ── Sequential `all` mode sub-agent prompt uses --nested ────────────────────

echo ""
echo "  Sequential all-mode sub-agent prompt passes --nested"
echo "  ──────────────────────────────────────────────────"

seq_prompt=$(awk '/sequential pipeline runner/,/parses this string/' "$WORK_START")
if echo "$seq_prompt" | grep -qF -- "--nested"; then
    pass "sequential sub-agent prompt invokes /work-start with --nested"
else
    fail "sequential prompt missing --nested"
fi

# ── Parallel-mode Step 4 treats --nested as set ────────────────────────────

echo ""
echo "  Parallel mode parent Step 4 treats --nested as set"
echo "  ────────────────────────────────────────────────"

# The parallel-mode parent runs single-WD Step 4 directly (not via Agent).
# It must explicitly include the --nested fields.
parallel_section=$(awk '/^### Parallel-mode flow|^## Parallel mode/,/^## /' "$WORK_START")
if echo "$parallel_section" | tr '\n' ' ' | tr -s ' ' | grep -qiE "treating .--nested. as set|--nested.*set"; then
    pass "parallel-mode Step 4 says to treat --nested as set"
else
    fail "parallel-mode doesn't enforce --nested fields"
fi

# ── The execution_strategy comment in the choosing-mode table ──────────────

echo ""
echo "  Mode-comparison note reflects execution_strategy: cost"
echo "  ────────────────────────────────────────────────────"

if grep -qE "execution_strategy: cost.*dispatched|cost.*for the dispatched" "$WORK_START"; then
    pass "/work-start documents execution_strategy: cost for dispatched"
else
    fail "/work-start still says balanced for dispatched (stale)"
fi

if grep -qF "balanced" "$WORK_START" && grep -qF "for the dispatched sub-agents" "$WORK_START" && grep -qE "execution_strategy: balanced.*dispatched" "$WORK_START"; then
    fail "/work-start still describes execution_strategy: balanced for dispatched"
else
    pass "no stale 'execution_strategy: balanced for dispatched' claim"
fi

# ── /work-run dispatch prompt uses --nested ────────────────────────────────

echo ""
echo "  /work-run dispatch prompt uses --nested"
echo "  ──────────────────────────────────────"

if grep -qF -- "--nested" "$WORK_RUN"; then
    pass "/work-run references --nested"
else
    fail "/work-run missing --nested"
fi

# Extract the sub-agent prompt block from /work-run (around line 440)
run_prompt=$(awk '/dynamic pipeline runner/,/^   \`\`\`$/' "$WORK_RUN")
if echo "$run_prompt" | grep -qF -- "--nested"; then
    pass "/work-run sub-agent prompt invokes /work-start --nested"
else
    fail "/work-run dispatch prompt missing --nested"
fi

# ── /feature-plan honors nested_in_dispatch ────────────────────────────────

echo ""
echo "  /feature-plan honors nested_in_dispatch"
echo "  ──────────────────────────────────────"

# Step 4b is the routing decision (coordinator vs sequential)
step4b=$(awk '/^### Step 4b/,/^### Step 4c|^## Step 5|^### Step 5/' "$FEATURE_PLAN")

if echo "$step4b" | grep -qF "nested_in_dispatch"; then
    pass "Step 4b checks nested_in_dispatch field"
else
    fail "Step 4b doesn't read nested_in_dispatch"
fi

if echo "$step4b" | grep -qiE "force execution_strategy|forced from|overwrite.*execution_strategy"; then
    pass "Step 4b forces execution_strategy: cost when nested"
else
    fail "Step 4b doesn't force cost-mode when nested"
fi

# Must NOT invoke /feature-coordinate when nested. The text path for nested
# should fall through to the cost branch.
if echo "$step4b" | tr '\n' ' ' | tr -s ' ' | grep -qiE "nested.*cost.*branch|fall through to the .cost. branch|forced from .nested"; then
    pass "Step 4b routes nested case to cost branch (skips coordinator)"
else
    fail "Step 4b doesn't route nested case away from coordinator"
fi

# ── /feature-coordinate defensive guard ────────────────────────────────────

echo ""
echo "  /feature-coordinate refuses to run when nested"
echo "  ────────────────────────────────────────────"

step0=$(awk '/^## Step 0 — Pre-flight/,/^## Step 0a|^## Step 1/' "$FEATURE_COORDINATE")

if echo "$step0" | grep -qF "nested_in_dispatch"; then
    pass "Step 0 checks nested_in_dispatch"
else
    fail "Step 0 missing nested_in_dispatch guard"
fi

if echo "$step0" | grep -qiE "cannot run inside.*dispatched|refuse to run|nested-dispatch guard"; then
    pass "Step 0 explicitly refuses to run when nested"
else
    fail "Step 0 missing refuse-to-run message"
fi

if echo "$step0" | grep -qE 'exit 1|Stop with exit 1'; then
    pass "Step 0 nested guard exits non-zero"
else
    fail "Step 0 nested guard doesn't exit non-zero"
fi

# Defensive guard must come BEFORE the existing execution_strategy check,
# so a misconfigured status.md still fails the right way.
nested_line=$(echo "$step0" | grep -n "nested_in_dispatch" | head -1 | cut -d: -f1)
strategy_line=$(echo "$step0" | grep -n "Verify .execution_strategy. is .balanced. or .speed" | head -1 | cut -d: -f1)
if [[ -n "$nested_line" && -n "$strategy_line" && "$nested_line" -lt "$strategy_line" ]]; then
    pass "nested guard runs before execution_strategy check"
else
    fail "nested guard should be first" "nested=$nested_line strategy=$strategy_line"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "Total: $total | Passed: $passed | Failed: $failed"
echo ""

[[ $failed -eq 0 ]] && exit 0 || exit 1
