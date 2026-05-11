#!/usr/bin/env bash
# Scenario: /work-run skill — contract validation
#
# The full dynamic-DAG flow requires Claude Code's Agent tool + AskUserQuestion
# which can't be exercised in a scenario test. This test validates that the
# SKILL.md contains all the documented contracts the runtime relies on:
#   - frontmatter shape (description + argument-hint)
#   - concurrency guard (driver.pid lock)
#   - resume vs init branching
#   - escalation handler (AskUserQuestion routing per blocked WD)
#   - hung-WD prompt
#   - termination + cleanup
#   - integration with work-orchestrator.sh + dispatch-marker.sh
#
# Run from repo root: bash tests/scenario-work-run.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SKILL="$REPO_ROOT/skills/work-run/SKILL.md"

passed=0
failed=0
total=0

pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() { ((failed++)) || true; ((total++)) || true; echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }

echo ""
echo "scenario: /work-run skill"
echo "────────────────────────────────────────────────"

# ── Frontmatter + header ────────────────────────────────────────────────────

echo ""
echo "  Frontmatter + header"
echo "  ────────────────────"

if [[ -f "$SKILL" ]]; then
    pass "skill file exists: skills/work-run/SKILL.md"
else
    fail "skill file missing"
    exit 1
fi

if grep -qE '^description:' "$SKILL"; then
    pass "frontmatter has description"
else
    fail "frontmatter missing description"
fi

if grep -qE '^argument-hint:.*<group-slug>' "$SKILL"; then
    pass "argument-hint mentions <group-slug>"
else
    fail "argument-hint missing <group-slug>"
fi

if grep -qE 'argument-hint:.*--cap' "$SKILL"; then
    pass "argument-hint mentions --cap"
else
    fail "argument-hint missing --cap"
fi

if grep -qE 'argument-hint:.*--resume' "$SKILL"; then
    pass "argument-hint mentions --resume"
else
    fail "argument-hint missing --resume"
fi

# ── Concurrency guard (Step 0) ─────────────────────────────────────────────

echo ""
echo "  Concurrency guard (Step 0)"
echo "  ─────────────────────────"

step0_block=$(awk '/^## Step 0 — Concurrency guard/,/^---$/' "$SKILL")

if echo "$step0_block" | grep -qE "driver\.(pid|lock)"; then
    pass "Step 0 names the lock (driver.pid or driver.lock)"
else
    fail "Step 0 missing driver lock"
fi

if echo "$step0_block" | grep -qE 'kill -0|process is dead'; then
    pass "Step 0 checks whether held PID is alive"
else
    fail "Step 0 missing liveness check"
fi

if echo "$step0_block" | grep -qF "trap"; then
    pass "Step 0 sets EXIT trap to release lock"
else
    fail "Step 0 missing trap (lock would leak on exit)"
fi

# ── Init vs resume branching (Step 2) ───────────────────────────────────────

echo ""
echo "  Init vs resume branching (Step 2)"
echo "  ────────────────────────────────"

step2_block=$(awk '/^## Step 2 — Initialize or resume orchestrator/,/^## Step 3/' "$SKILL")

if echo "$step2_block" | grep -qF "AskUserQuestion"; then
    pass "Step 2 uses AskUserQuestion for resume vs clear"
else
    fail "Step 2 missing AskUserQuestion (prose alone allows silent decision)"
fi

if echo "$step2_block" | grep -qF "work-orchestrator.sh init"; then
    pass "Step 2 calls work-orchestrator.sh init for fresh state"
else
    fail "Step 2 missing init invocation"
fi

if echo "$step2_block" | grep -qF -- "--cap"; then
    pass "Step 2 wires --cap through to init"
else
    fail "Step 2 doesn't pass --cap to init"
fi

# ── Driver loop reconciliation (Step 3a) ────────────────────────────────────

echo ""
echo "  Driver loop · Step 3a (reconcile completions)"
echo "  ─────────────────────────────────────────────"

step3a_block=$(awk '/^### 3a/,/^### 3b/' "$SKILL")

# Must cover all 5 classification outcomes from PR A
for outcome in COMPLETE ESCALATION_AT_ STOPPED_AT_ ERROR SKIPPED; do
    if echo "$step3a_block" | grep -qF "$outcome"; then
        pass "3a classifies $outcome"
    else
        fail "3a missing $outcome classification"
    fi
done

# Must distinguish escalation routing (block) from clean routing (complete)
if echo "$step3a_block" | tr '\n' ' ' | tr -s ' ' | grep -qF "complete <group> <wd-id>"; then
    pass "3a routes clean returns to complete"
else
    fail "3a missing complete-routing"
fi

if echo "$step3a_block" | tr '\n' ' ' | tr -s ' ' | grep -qE "block <group> <wd-id>[^|]*escalation:"; then
    pass "3a routes escalations to block with escalation:<category> reason"
else
    fail "3a missing block-routing for escalations"
fi

# Dispatch failure modes (payload-lost / user-stopped / parse-failed).
# Case-insensitive — SKILL.md uses "Payload-lost" at the routing line.
for mode in payload-lost user-stopped parse-failed; do
    if echo "$step3a_block" | grep -qiF "$mode"; then
        pass "3a handles dispatch failure: $mode"
    else
        fail "3a missing dispatch failure: $mode"
    fi
done

# ── Hung detection (Step 3b) ────────────────────────────────────────────────

echo ""
echo "  Driver loop · Step 3b (hung detection)"
echo "  ──────────────────────────────────────"

step3b_block=$(awk '/^### 3b/,/^### 3c/' "$SKILL")

if echo "$step3b_block" | grep -qF "work-orchestrator.sh hung"; then
    pass "3b calls work-orchestrator.sh hung"
else
    fail "3b missing hung invocation"
fi

if echo "$step3b_block" | grep -qF -- "--threshold-seconds"; then
    pass "3b passes --threshold-seconds"
else
    fail "3b missing threshold flag"
fi

if echo "$step3b_block" | grep -qF "AskUserQuestion"; then
    pass "3b uses AskUserQuestion (not prose) for hung handling"
else
    fail "3b uses prose for decision (should be AskUserQuestion)"
fi

# ── Escalation handler (Step 3c) ────────────────────────────────────────────

echo ""
echo "  Driver loop · Step 3c (escalation handler)"
echo "  ─────────────────────────────────────────"

step3c_block=$(awk '/^### 3c/,/^### 3d/' "$SKILL")

if echo "$step3c_block" | grep -qF "AskUserQuestion"; then
    pass "3c uses AskUserQuestion for escalation"
else
    fail "3c missing AskUserQuestion"
fi

if echo "$step3c_block" | grep -qF "escalation.json"; then
    pass "3c reads escalation.json"
else
    fail "3c doesn't reference escalation.json"
fi

if echo "$step3c_block" | grep -qF "options"; then
    pass "3c honors sub-agent options field if present"
else
    fail "3c ignores sub-agent options"
fi

if echo "$step3c_block" | grep -qF "Skip this WD"; then
    pass "3c offers skip option"
else
    fail "3c missing skip option"
fi

if echo "$step3c_block" | grep -qF "Abort"; then
    pass "3c offers abort option"
else
    fail "3c missing abort option"
fi

if echo "$step3c_block" | grep -qF "unblock"; then
    pass "3c calls orchestrator unblock on resolution"
else
    fail "3c missing unblock call"
fi

# Per-WD iteration (not batched)
if echo "$step3c_block" | grep -qE "Repeat per blocked WD|per escalation|per blocked"; then
    pass "3c iterates per blocked WD (not batched at end)"
else
    fail "3c not clearly per-WD"
fi

# ── Dispatch loop (Step 3e) ─────────────────────────────────────────────────

echo ""
echo "  Driver loop · Step 3e (dispatch)"
echo "  ───────────────────────────────"

step3e_block=$(awk '/^### 3e/,/^### 3f/' "$SKILL")

if echo "$step3e_block" | grep -qF "work-orchestrator.sh ready"; then
    pass "3e queries orchestrator for ready set"
else
    fail "3e doesn't call ready"
fi

if echo "$step3e_block" | grep -qF "work-orchestrator.sh dispatch"; then
    pass "3e calls orchestrator dispatch"
else
    fail "3e doesn't call dispatch"
fi

if echo "$step3e_block" | grep -qF "work-dispatch.sh begin"; then
    pass "3e writes dispatch marker via work-dispatch.sh"
else
    fail "3e missing dispatch marker"
fi

if echo "$step3e_block" | grep -qF "run_in_background"; then
    pass "3e dispatches Agent with run_in_background: true"
else
    fail "3e missing run_in_background (would block on first wave)"
fi

# Sub-agent prompt should reference the escalation contract from /work-start
if echo "$step3e_block" | grep -qF "escalation contract"; then
    pass "3e sub-agent prompt references escalation contract"
else
    fail "3e sub-agent prompt missing escalation contract reference"
fi

if echo "$step3e_block" | grep -qF "ESCALATION_AT_<stage>"; then
    pass "3e sub-agent prompt documents ESCALATION_AT_ return form"
else
    fail "3e sub-agent prompt missing return-form documentation"
fi

# ── Termination + completion summary ────────────────────────────────────────

echo ""
echo "  Termination + completion (Step 4)"
echo "  ────────────────────────────────"

if grep -q "^## Step 4 — Completion summary" "$SKILL"; then
    pass "Step 4 covers completion summary"
else
    fail "missing Step 4 completion summary"
fi

step4_block=$(awk '/^## Step 4/,/^## Failure modes/' "$SKILL")

if echo "$step4_block" | grep -qF "work-orchestrator.sh clear"; then
    pass "Step 4 offers clear option"
else
    fail "Step 4 missing clear offer"
fi

if echo "$step4_block" | grep -qF "AskUserQuestion"; then
    pass "Step 4 uses AskUserQuestion for clear-vs-keep"
else
    fail "Step 4 missing AskUserQuestion"
fi

# ── Recovery / failure modes section ────────────────────────────────────────

echo ""
echo "  Failure modes documented"
echo "  ────────────────────────"

failure_block=$(awk '/^## Failure modes/,/^## Why this skill exists/' "$SKILL")

for mode in "user pressed ESC" "payload-lost" "killed mid-turn" "wedged"; do
    # Match case-insensitively, allow paraphrases
    if echo "$failure_block" | grep -qiE "$mode|$(echo "$mode" | tr '-' ' ')"; then
        pass "failure mode covered: $mode"
    else
        fail "failure mode missing: $mode"
    fi
done

# ── No prose-prompt decisions (CRITICAL kit rule) ───────────────────────────

echo ""
echo "  AskUserQuestion compliance"
echo "  ─────────────────────────"

# The kit's CLAUDE.md says: every user decision MUST use AskUserQuestion,
# never prose alternatives. Spot-check that "decision-shaped" prose isn't
# masquerading as a question.
prose_patterns=(
    "Type [a-z]"
    "Want me to"
    "Should I "
    "Shall we"
    "press Enter"
    "yes — "
    "y/n"
)

bad=0
for p in "${prose_patterns[@]}"; do
    if grep -qE "$p" "$SKILL"; then
        fail "prose-prompt pattern found: '$p'"
        bad=1
    fi
done
if [[ $bad -eq 0 ]]; then
    pass "no prose-prompt patterns (all decisions use AskUserQuestion)"
fi

# ── MANIFEST entry ──────────────────────────────────────────────────────────

echo ""
echo "  MANIFEST entry"
echo "  ──────────────"

if grep -qF ".claude/skills/work-run/SKILL.md" "$REPO_ROOT/MANIFEST"; then
    pass "MANIFEST lists skills/work-run/SKILL.md"
else
    fail "MANIFEST missing work-run entry"
fi

# ── User-facing command list ────────────────────────────────────────────────

if grep -qE "/work-run" "$REPO_ROOT/.claude/rules/kit-development.md"; then
    pass "kit-development.md lists /work-run in user-facing commands"
else
    fail "/work-run not in user-facing commands list"
fi

# ════════════════════════════════════════════════════════════════════════════
# Coverage from adversarial review 2026-05-11 (PR C, 14 findings).
# These assertions catch the bug patterns the original test missed.
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "── post-adversarial coverage"
echo "  ──────────────────────────"

# CRITICAL #1: Skip path uses orchestrator's `skip` subcommand, NOT
# the `unblock + complete` sequence that the state machine rejects.
if grep -qE 'skip <group>|orchestrator.sh skip|cmd_skip' "$SKILL"; then
    pass "Step 3c Skip path references orchestrator skip subcommand"
else
    fail "Step 3c Skip path missing skip subcommand reference"
fi

if grep -qiE 'Do NOT use.*unblock.*complete|use `unblock + complete' "$SKILL"; then
    pass "Step 3c warns against unblock + complete sequence"
else
    fail "Step 3c missing warning about unblock + complete"
fi

# CRITICAL #2: Step 3a does NOT reference dispatch marker `result` field
# as source of truth (nothing writes it). Source of truth is the
# new-turn agent-message text.
if echo "$step3a_block" | grep -qE "marker.*result|result field"; then
    fail "Step 3a still references dispatch marker result (nothing writes it)"
else
    pass "Step 3a does not rely on dispatch marker result"
fi

if echo "$step3a_block" | grep -qiE "new turn|final assistant message|agent.*message"; then
    pass "Step 3a names the new-turn agent message as the signal"
else
    fail "Step 3a missing source-of-truth (new-turn message)"
fi

# HIGH #1: Step 3a documents how to match notification → WD-id
if echo "$step3a_block" | grep -qE 'grep.*feature_slug|lookup.*feature_slug|in-flight/.*feature_slug'; then
    pass "Step 3a documents notification → WD-id matching pattern"
else
    fail "Step 3a missing notification matching pattern"
fi

# HIGH #2: Step 3e checks immediate Agent return for synchronous errors
if echo "$step3e_block" | grep -qiE 'synchronous|immediate.*return|sync.*error|never started'; then
    pass "Step 3e handles synchronous Agent dispatch errors"
else
    fail "Step 3e missing synchronous-error guard"
fi

# HIGH #3: Step 0 uses mkdir (atomic test-and-set), not echo > lock
if echo "$step0_block" | grep -qE 'mkdir.*LOCK|atomic.*test-and-set'; then
    pass "Step 0 uses mkdir-based atomic lock (no TOCTOU)"
else
    fail "Step 0 still has TOCTOU race (uses echo > lock)"
fi

# HIGH #5: Step 2 errors on --resume with no orchestrator state
if echo "$step2_block" | grep -qiE -- '--resume.*not.*exist|--resume requested but'; then
    pass "Step 2 errors on --resume with no state"
else
    fail "Step 2 silent-fallthrough on --resume + missing state"
fi

# HIGH #6: Step 3e prescribes ONE feature-init strategy, not two alternatives
if echo "$step3e_block" | grep -qiE "alternatively.*replicate|both work|Option [AB]"; then
    fail "Step 3e still offers Option A or B (non-deterministic)"
else
    pass "Step 3e prescribes a single feature-init approach"
fi

# HIGH #7: Step 2a includes cold-resume reconciliation
if echo "$step2_block" | grep -qiE "cold.resume|stale.*in-flight|status\.md mtime"; then
    pass "Step 2a covers cold-resume reconciliation"
else
    fail "Step 2a missing cold-resume reconciliation"
fi

# MEDIUM #1: Step 0 validates --cap >= 1
if echo "$step0_block" | grep -qE 'cap.*-lt 1|cap.*must be|cap.*>= 1'; then
    pass "Step 0 validates --cap >= 1"
else
    fail "Step 0 missing cap floor validation"
fi

# MEDIUM #2: Step 3c handles missing/malformed escalation.json
if echo "$step3c_block" | grep -qiE "missing.*malformed|missing or malformed|escalation.json.*missing"; then
    pass "Step 3c handles missing/malformed escalation.json"
else
    fail "Step 3c missing fallback for bad escalation.json"
fi

# MEDIUM #3: Step 3e sub-agent prompt reads escalation-resolved.md
if echo "$step3e_block" | grep -qF "escalation-resolved.md"; then
    pass "Step 3e prompt reads escalation-resolved.md on re-dispatch"
else
    fail "Step 3e doesn't tell re-dispatched agent about prior resolution"
fi

# MEDIUM #6: Step 3a single-quotes the reason argument
if echo "$step3a_block" | grep -qiE "single-quote|single quote|'\\\\''"; then
    pass "Step 3a documents single-quoting for shell injection safety"
else
    fail "Step 3a missing shell-quoting guidance"
fi

# MEDIUM #7: Step 3c caps AskUserQuestion options at 4
if echo "$step3c_block" | grep -qiE "cap.*at 4|option count|4 total|up to 4"; then
    pass "Step 3c caps option count at 4"
else
    fail "Step 3c missing option count cap"
fi

# Step 3a covers orphan notifications (clear-and-restart case)
if echo "$step3a_block" | grep -qiE "orphan.*notification|orphaned by.*clear|unknown WD-id"; then
    pass "Step 3a handles orphan notifications (post-clear)"
else
    fail "Step 3a missing orphan-notification path"
fi

# Step 3c calls work-orchestrator.sh resolve after escalation
if echo "$step3c_block" | grep -qE "work-orchestrator.sh resolve"; then
    pass "Step 3c calls resolve after escalations (re-scan for newly-SPECIFIED)"
else
    fail "Step 3c missing resolve call (user edits may unblock WDs)"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo "Total: $total | Passed: $passed | Failed: $failed"
echo ""

[[ $failed -eq 0 ]] && exit 0 || exit 1
