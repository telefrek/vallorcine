#!/usr/bin/env python3
"""Set up a comparative experiment: Enhanced TDD vs aTDD.

Creates two identical jlsm checkouts at the feature's parent commit,
applies planning overlays and stubs, installs vallorcine, and generates
run scripts for each experiment arm.

Usage:
    python3 setup-experiment.py --feature table-indices-and-queries \
        [--budget-usd 20] [--max-rounds 3] \
        [--work-dir /tmp/vallorcine-experiment]
"""

import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import uuid
from datetime import datetime, timezone

# Import functions from run-feature.py (dash in filename requires importlib)
_harness_dir = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "run_feature", os.path.join(_harness_dir, "run-feature.py")
)
run_feature = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(run_feature)


def load_stubs(slug):
    """Load pre-defined stub files for a feature."""
    stubs_path = os.path.join(_harness_dir, "stubs", f"{slug}.json")
    if not os.path.exists(stubs_path):
        print(f"Error: no stubs file at {stubs_path}", file=sys.stderr)
        sys.exit(1)
    with open(stubs_path) as f:
        data = json.load(f)
    return data["stubs"]


def write_stubs(checkout_path, stubs):
    """Write stub files into the checkout."""
    written = 0
    for stub in stubs:
        dst = os.path.join(checkout_path, stub["path"])
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "w") as f:
            f.write(stub["content"])
        written += 1
    print(f"  Wrote {written} stub files", file=sys.stderr)
    return written


def synthesize_status_md(checkout_path, slug):
    """Write a status.md that looks like planning just completed."""
    feature_dir = os.path.join(checkout_path, ".feature", slug)
    os.makedirs(feature_dir, exist_ok=True)

    now = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    content = f"""---
feature: "{slug}"
created: "{now}"
last_updated: "{now}"
---

# Feature Status -- {slug}

## Current Position
**Stage:** testing
**Substage:** not-started
**Last successful checkpoint:** work-plan.md written, stubs created (harness)
**Automation mode:** autonomous
**Execution strategy:** cost

## Stage Completion

| Stage | Status | Completed | Notes |
|-------|--------|-----------|-------|
| Scoping | complete | {now} | harness |
| Domains | complete | {now} | harness |
| Planning | complete | {now} | harness |
| Testing | not-started | — | — |
| Implementation | not-started | — | — |
| Refactor | not-started | — | — |

## Work Units

| Unit | Name | Constructs | Depends On | Status | Cycle |
|------|------|------------|------------|--------|-------|
| WU-1 | Index infrastructure | IndexType, IndexDefinition, FieldValueCodec, SecondaryIndex, FieldIndex, FullTextFieldIndex, VectorFieldIndex, IndexRegistry | none | not-started | 1 |
| WU-2 | Query API + execution | Predicate, TableQuery, QueryExecutor | WU-1 | not-started | 1 |

## TDD Cycle Tracker

| Cycle | Unit | Tests written | Tests passing | Refactor done |
|-------|------|--------------|---------------|---------------|
"""
    status_path = os.path.join(feature_dir, "status.md")
    with open(status_path, "w") as f:
        f.write(content)
    print(f"  Synthesized status.md at testing:not-started", file=sys.stderr)


def setup_arm(jlsm_path, vallorcine_path, slug, metadata, scope,
              arm_name, work_dir, briefs_dir, overlay_dir):
    """Set up one experiment arm: checkout + overlay + stubs + vallorcine."""
    print(f"\n--- Setting up {arm_name} arm ---", file=sys.stderr)

    arm_dir = os.path.join(work_dir, arm_name)
    os.makedirs(arm_dir, exist_ok=True)

    parent_sha = metadata["parent_sha"]

    # Step 1: Clone at parent_sha
    print(f"  Step 1: Cloning at {parent_sha}...", file=sys.stderr)
    checkout_path = run_feature.setup_checkout(
        jlsm_path, parent_sha, arm_dir, f"jlsm-{arm_name}"
    )
    if not checkout_path:
        print(f"  Error: checkout failed for {arm_name}", file=sys.stderr)
        sys.exit(1)

    # Rename to just "checkout" for cleaner paths
    final_path = os.path.join(arm_dir, "checkout")
    os.rename(checkout_path, final_path)
    checkout_path = final_path

    # Step 2: Apply planning overlay (feature metadata files)
    print(f"  Step 2: Applying planning overlay...", file=sys.stderr)
    if os.path.exists(os.path.join(overlay_dir, "manifest.json")):
        result = subprocess.run(
            [sys.executable, os.path.join(_harness_dir, "apply-overlay.py"),
             "--checkout", checkout_path, "--overlay", overlay_dir],
            capture_output=True, text=True,
        )
        if result.stderr:
            # Only show non-cosmetic warnings
            for line in result.stderr.split("\n"):
                if "FAIL" in line and ".feature/" not in line:
                    print(f"    {line}", file=sys.stderr)
        print(f"  Planning overlay applied", file=sys.stderr)
    else:
        print(f"  Warning: no planning overlay found", file=sys.stderr)

    # Step 3: Write source stubs
    print(f"  Step 3: Writing source stubs...", file=sys.stderr)
    stubs = load_stubs(slug)
    write_stubs(checkout_path, stubs)

    # Step 4: Install vallorcine
    print(f"  Step 4: Installing vallorcine...", file=sys.stderr)
    if not run_feature.install_vallorcine(checkout_path, vallorcine_path):
        print(f"  Warning: vallorcine install failed — continuing", file=sys.stderr)

    # Step 5: Write scope manifest + brief + work plan
    print(f"  Step 5: Writing scope and brief...", file=sys.stderr)
    run_feature.write_scope_manifest(checkout_path, slug, metadata, scope)
    run_feature.write_brief_if_missing(checkout_path, slug, briefs_dir)

    # Step 6: Synthesize status.md
    print(f"  Step 6: Synthesizing status.md...", file=sys.stderr)
    synthesize_status_md(checkout_path, slug)

    # Step 7: Save pre-run state
    pre_state = {
        "label": f"pre-{arm_name}",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "checkout_path": checkout_path,
        "parent_sha": parent_sha,
        "source_checksums": run_feature.file_checksums(checkout_path),
    }
    pre_state_path = os.path.join(arm_dir, "pre-run-state.json")
    with open(pre_state_path, "w") as f:
        json.dump(pre_state, f, indent=2)
    print(f"  Pre-run state saved ({len(pre_state['source_checksums'])} files)",
          file=sys.stderr)

    return checkout_path


def verify_identical_state(arm1_dir, arm2_dir):
    """Verify both arms have identical file checksums."""
    with open(os.path.join(arm1_dir, "pre-run-state.json")) as f:
        state1 = json.load(f)
    with open(os.path.join(arm2_dir, "pre-run-state.json")) as f:
        state2 = json.load(f)

    cs1 = state1["source_checksums"]
    cs2 = state2["source_checksums"]

    if cs1 == cs2:
        print(f"\n  Verification: both arms have identical checksums "
              f"({len(cs1)} files)", file=sys.stderr)
        return True
    else:
        only1 = set(cs1.keys()) - set(cs2.keys())
        only2 = set(cs2.keys()) - set(cs1.keys())
        diff = {k for k in cs1 if k in cs2 and cs1[k] != cs2[k]}
        print(f"\n  WARNING: arms differ!", file=sys.stderr)
        if only1:
            print(f"    Only in arm 1: {only1}", file=sys.stderr)
        if only2:
            print(f"    Only in arm 2: {only2}", file=sys.stderr)
        if diff:
            print(f"    Different content: {diff}", file=sys.stderr)
        return False


ENHANCED_TDD_PROMPT = r"""You are running the Enhanced TDD pipeline for the feature "table-indices-and-queries".
The work plan is complete. Planning, scoping, and domain analysis are done.
You are starting from the Testing stage. Run the full pipeline autonomously
without pausing for user input.

Read these files first:
- .claude/rules/tdd-protocol.md (timeout and escalation rules)
- .claude/agents/test-writer-agent.md (your identity for Phase 1)
- .claude/agents/code-writer-agent.md (your identity for Phase 2)
- .claude/agents/refactor-agent.md (your identity for Phase 3)
- .feature/table-indices-and-queries/brief.md (acceptance criteria)
- .feature/table-indices-and-queries/work-plan.md (contracts and constructs)
- .feature/table-indices-and-queries/status.md (current state)

## Phase 1: Test Writing (act as Test Writer)

For each construct in the work plan, in implementation order:
1. Read the contract signature and stub file
2. Derive test cases covering:
   - Happy path (normal usage per contract)
   - Error cases (null inputs, invalid args per contract)
   - Boundary values (empty collections, zero-length, max capacity)
   - Structural patterns (round-trip encode/decode, lifecycle close/use-after-close,
     paired insert/delete, sealed interface exhaustiveness)
3. Write test files to the standard test directory
   (modules/jlsm-table/src/test/java/jlsm/table/)

Apply defensive test vectors from tdd-protocol:
- Null/empty inputs on every public method
- Boundary values (zero, one, max capacity)
- Resource lifecycle (close, use-after-close)
- Error path behaviour (exceptions propagate, not silent null returns)

After writing ALL tests for ALL constructs:
- Run: ./gradlew :modules:jlsm-table:test (5-minute timeout)
- Expected: compilation errors or test failures (stubs throw UnsupportedOperationException)
- This verifies tests are syntactically correct and reference real types

Update .feature/table-indices-and-queries/status.md: Testing -> complete
Append a tests-written entry to .feature/table-indices-and-queries/cycle-log.md

## Phase 2: Implementation (act as Code Writer)

For each construct in implementation order from the work plan:
1. Read the contract and the tests for that construct
2. Implement the minimum correct code to pass all tests
3. Run that construct's tests: ./gradlew :modules:jlsm-table:test --tests "ClassName" (5-min timeout)
4. If tests fail: fix the IMPLEMENTATION (never modify tests), re-run
5. Apply fix-forward: after fixing a bug, scan other constructs for the same anti-pattern

After all constructs are implemented:
- Run the full suite: ./gradlew :modules:jlsm-table:test (5-min timeout)
- All tests must pass before proceeding

Update status.md: Implementation -> complete
Append an implemented entry to cycle-log.md

## Phase 3: Refactor (act as Refactor Agent — light pass)

Review implementation for:
- Duplicated code that should be extracted
- Assert-based safety checks that should use explicit validation with exceptions
- Silent exception swallowing (catch returning null in error paths)
- Style violations

Do NOT add new functionality or change test behavior.

Update status.md: Refactor -> complete

## Completion

Output a structured summary:
```
EXPERIMENT SUMMARY — Enhanced TDD
==================================
Test files created: <count>
Test methods total: <count>
Implementation files modified: <count>
Test suite: PASS / FAIL
Failures encountered during implementation: <count>
Fix-forward instances: <count>
Refactor changes: <count>
```
"""

ATDD_PROMPT = r"""You are running the adversarial TDD (aTDD) pipeline for the feature
"table-indices-and-queries" in greenfield mode. The work plan is complete.
Implementation files contain only stubs. Run the full aTDD cycle autonomously
for up to {max_rounds} rounds without pausing for user input.

Read these files first:
- .claude/rules/tdd-protocol.md (timeout and escalation rules)
- .claude/agents/spec-analyst-agent.md (your identity for Step 1)
- .claude/agents/breaker-agent.md (your identity for Step 2)
- .claude/agents/code-writer-agent.md (your identity for Step 3)
- .feature/table-indices-and-queries/brief.md (acceptance criteria)
- .feature/table-indices-and-queries/work-plan.md (contracts and constructs)
- .feature/table-indices-and-queries/status.md (current state)
- .feature/table-indices-and-queries/atdd-scope.md (target files)

## Round 1 (Greenfield — no implementation exists)

### Step 1 — Spec Analyst
Analyse the contracts in work-plan.md across four dimensions:
1. Completeness gaps — error cases, boundaries, concurrent access, resource cleanup
2. Security surface — trust boundaries, input validation, resource limits
3. Memory/resource risks — lifecycle patterns, closeable resources, cache eviction
4. Performance traps — algorithmic choices, hot-path allocations, contention

Write .feature/table-indices-and-queries/breaker-prompt.md with the complete
vector list, organised by dimension.

### Step 2 — Breaker
Write TWO categories of tests:
1. Standard functional tests covering every contract from work-plan.md
   (happy path, error cases, boundary values) — named *Test.java
2. Adversarial tests targeting the Analyst's vectors
   (security, memory, performance, concurrency) — named *AdversarialTest.java
   with a comment citing which vector each test targets

Write all tests to modules/jlsm-table/src/test/java/jlsm/table/
All tests should fail (stubs throw UnsupportedOperationException).
Do NOT run the test suite yet.

### Step 3 — Implementer (act as Code Writer)
Make ALL tests pass — both functional and adversarial.
Follow implementation order from work-plan.md.
Run ./gradlew :modules:jlsm-table:test after each construct (5-min timeout).
Apply fix-forward: after fixing a bug, scan for the same anti-pattern elsewhere.
Never modify test files.

### Step 4 — Round summary
Create .feature/table-indices-and-queries/known_issues.md with:
- RESOLVED entries for any bugs found during implementation
- TENDENCY entries for any anti-patterns the implementation exhibited

Create .feature/table-indices-and-queries/atdd-status.md with round results.
Append round entries to .feature/table-indices-and-queries/cycle-log.md.

## Rounds 2-{max_rounds} (Audit mode — implementation now exists)

For each subsequent round:

### Step 1 — Spec Analyst (incremental)
Read the implementation files. Compare against known_issues.md.
Find deeper gaps the round-1 tests missed — focus on:
- Interactions between constructs (IndexRegistry + QueryExecutor)
- Edge cases in the Breaker's own fixes from prior rounds
- Regression on RESOLVED patterns
Write an incremental breaker-prompt.md with NEW vectors only.

### Step 2 — Breaker (incremental)
Write NEW adversarial tests only (named *AdversarialTest.java).
Run the full test suite (5-min timeout).
Classify results: confirmed failures, theoretical concerns, untriggerable.

### Step 3 — Implementer
Fix confirmed failures. Apply fix-forward.

### Step 4 — Round summary
Update known_issues.md and atdd-status.md.

### Decision gate (automated)
- If confirmed failures > 0: continue to next round
- If all vectors untriggerable or confirmed failures == 0: STOP (convergence)
- If max rounds reached: STOP

## Completion

Output a structured summary:
```
EXPERIMENT SUMMARY — aTDD
==========================
Rounds completed: <N>
Convergence: yes/no
Test files created: <count> (functional: <N>, adversarial: <N>)
Test methods total: <count>
Confirmed bugs per round: [<r1>, <r2>, ...]
Implementation files modified: <count>
Test suite: PASS / FAIL
RESOLVED patterns: <count>
TENDENCY warnings: <count>
```
"""


def write_run_script(arm_dir, arm_name, prompt, session_id):
    """Generate run.sh for an experiment arm."""
    run_path = os.path.join(arm_dir, "run.sh")
    # Escape single quotes in prompt for shell heredoc safety
    # (using a delimiter that won't appear in the prompt)
    content = f"""#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/checkout"

ARM_NAME="{arm_name}"
SESSION_ID="{session_id}"

echo "Starting $ARM_NAME arm at $(date -Iseconds)..."
echo $$ > "../$ARM_NAME.pid"

claude -p \\
  --dangerously-skip-permissions \\
  --verbose \\
  --output-format stream-json \\
  --session-id "$SESSION_ID" \\
  "$(cat <<'EXPERIMENT_PROMPT'
{prompt}
EXPERIMENT_PROMPT
)" > "../$ARM_NAME-output.jsonl" 2>&1

EXIT_CODE=$?
echo "$EXIT_CODE" > "../$ARM_NAME.exit-code"
rm -f "../$ARM_NAME.pid"

# Extract final token totals by streaming through the output line-by-line
# Accumulates input_tokens and output_tokens from all usage blocks
OUTPUT_FILE="../$ARM_NAME-output.jsonl"
if [[ -f "$OUTPUT_FILE" ]]; then
    awk '
    /"input_tokens"/ {{
        match($0, /"input_tokens":([0-9]+)/, a); if (a[1]) input += a[1]
        match($0, /"output_tokens":([0-9]+)/, b); if (b[1]) output += b[1]
        match($0, /"cache_read_input_tokens":([0-9]+)/, c); if (c[1]) cache += c[1]
    }}
    END {{
        printf "{{\\"input_tokens\\": %d, \\"output_tokens\\": %d, \\"cache_read_input_tokens\\": %d, \\"total_tokens\\": %d}}\\n", input, output, cache, input+output
    }}
    ' "$OUTPUT_FILE" > "../$ARM_NAME-token-summary.json"

    echo ""
    echo "=== Token Usage ==="
    cat "../$ARM_NAME-token-summary.json"
fi

echo ""
echo "$ARM_NAME arm finished at $(date -Iseconds) with exit code $EXIT_CODE"
echo "Output: $(dirname "$0")/$ARM_NAME-output.jsonl"
echo "Token summary: $(dirname "$0")/$ARM_NAME-token-summary.json"
echo "Session ID: $SESSION_ID"
"""
    with open(run_path, "w") as f:
        f.write(content)
    os.chmod(run_path, 0o755)
    print(f"  Generated {run_path}", file=sys.stderr)


def write_compare_script(work_dir, vallorcine_path, slug):
    """Generate compare.sh for post-run metric collection."""
    harness = os.path.join(vallorcine_path, "aTDD-research", "harness")
    compare_path = os.path.join(work_dir, "compare.sh")
    content = f"""#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS="{harness}"
SLUG="{slug}"

echo "=== Collecting Enhanced TDD results ==="
python3 "$HARNESS/collect-results.py" \\
  --jlsm-path "$SCRIPT_DIR/enhanced-tdd/checkout" \\
  --feature "$SLUG" \\
  --results-dir "$SCRIPT_DIR/results/enhanced-tdd"

echo "=== Collecting aTDD results ==="
python3 "$HARNESS/collect-results.py" \\
  --jlsm-path "$SCRIPT_DIR/atdd/checkout" \\
  --feature "$SLUG" \\
  --results-dir "$SCRIPT_DIR/results/atdd"

echo ""
echo "=== Results ==="
echo "Enhanced TDD: $SCRIPT_DIR/results/enhanced-tdd/"
echo "aTDD:         $SCRIPT_DIR/results/atdd/"
"""
    with open(compare_path, "w") as f:
        f.write(content)
    os.chmod(compare_path, 0o755)
    print(f"  Generated {compare_path}", file=sys.stderr)


def write_watch_script(work_dir, slug):
    """Generate watch-progress.sh for monitoring experiment runs."""
    watch_path = os.path.join(work_dir, "watch-progress.sh")
    content = r"""#!/bin/bash
# Watch experiment progress. All log parsing is line-by-line streaming.
# Usage: ./watch-progress.sh [--once] [--interval N]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SLUG=""" + f'"{slug}"' + r"""
INTERVAL=30
ONCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --once) ONCE=true; shift ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        *) echo "Usage: $0 [--once] [--interval N]"; exit 1 ;;
    esac
done

get_arm_status() {
    local arm_name="$1"
    local arm_dir="$SCRIPT_DIR/$arm_name"
    local checkout="$arm_dir/checkout"
    local pid_file="$arm_dir/$arm_name.pid"
    local exit_file="$arm_dir/$arm_name.exit-code"
    local output_file="$arm_dir/$arm_name-output.jsonl"

    # Process state
    local state="WAITING"
    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        if kill -0 "$pid" 2>/dev/null; then
            state="RUNNING"
        else
            state="STALE-PID"
        fi
    elif [[ -f "$exit_file" ]]; then
        local code
        code=$(cat "$exit_file" 2>/dev/null)
        if [[ "$code" == "0" ]]; then
            state="COMPLETE"
        else
            state="FAILED($code)"
        fi
    fi

    # Stage from status.md (small file, safe to read fully)
    local stage="—"
    local status_file="$checkout/.feature/$SLUG/status.md"
    if [[ -f "$status_file" ]]; then
        stage=$(grep -m1 '^\*\*Stage:\*\*' "$status_file" 2>/dev/null | sed 's/.*\*\* //' || echo "—")
    fi

    # Test count — only NEW test files (exclude pre-existing ones)
    # Pre-existing: DocumentSerializerTest, Float16Test, JlsmDocumentTest, JlsmSchemaTest,
    # JlsmTableTest, JsonRoundTripTest, YamlRoundTripTest = 7 files
    local test_count=0
    local test_total=0
    if [[ -d "$checkout/modules/jlsm-table/src/test" ]]; then
        test_total=$(find "$checkout/modules/jlsm-table/src/test" -name '*Test.java' -o -name '*AdversarialTest.java' 2>/dev/null | wc -l)
        test_count=$((test_total - 7))
        if [[ $test_count -lt 0 ]]; then test_count=0; fi
    fi

    # Impl file count — check the 11 specific stub files for real content (>20 lines = implemented)
    local impl_done=0
    local impl_total=11
    local stub_files=(
        "modules/jlsm-table/src/main/java/jlsm/table/IndexType.java"
        "modules/jlsm-table/src/main/java/jlsm/table/IndexDefinition.java"
        "modules/jlsm-table/src/main/java/jlsm/table/Predicate.java"
        "modules/jlsm-table/src/main/java/jlsm/table/TableQuery.java"
        "modules/jlsm-table/src/main/java/jlsm/table/internal/FieldValueCodec.java"
        "modules/jlsm-table/src/main/java/jlsm/table/internal/SecondaryIndex.java"
        "modules/jlsm-table/src/main/java/jlsm/table/internal/FieldIndex.java"
        "modules/jlsm-table/src/main/java/jlsm/table/internal/FullTextFieldIndex.java"
        "modules/jlsm-table/src/main/java/jlsm/table/internal/VectorFieldIndex.java"
        "modules/jlsm-table/src/main/java/jlsm/table/internal/IndexRegistry.java"
        "modules/jlsm-table/src/main/java/jlsm/table/internal/QueryExecutor.java"
    )
    for sf in "${stub_files[@]}"; do
        local fpath="$checkout/$sf"
        if [[ -f "$fpath" ]]; then
            local lines
            lines=$(wc -l < "$fpath" 2>/dev/null || echo "0")
            # Stubs are ~15-30 lines; real implementations are 50+
            if [[ $lines -gt 40 ]]; then
                impl_done=$((impl_done + 1))
            fi
        fi
    done

    # Token usage from stream-json output (sum all input+output tokens, streamed via awk)
    local tokens="—"
    if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
        local total_k
        total_k=$(awk '
        /"input_tokens"/ {
            match($0, /"input_tokens":([0-9]+)/, a); if (a[1]) input += a[1]
            match($0, /"output_tokens":([0-9]+)/, b); if (b[1]) output += b[1]
        }
        END { printf "%d", (input + output) / 1000 }
        ' "$output_file" 2>/dev/null)
        if [[ -n "$total_k" ]] && [[ "$total_k" -gt 0 ]]; then
            tokens="${total_k}K"
        fi
    fi

    # aTDD-specific: round info
    local round_info=""
    local atdd_status="$checkout/.feature/$SLUG/atdd-status.md"
    if [[ -f "$atdd_status" ]]; then
        local current_round
        current_round=$(grep -m1 'Current round:' "$atdd_status" 2>/dev/null | grep -o '[0-9]*' || echo "?")
        local substage
        substage=$(grep -m1 'Substage:' "$atdd_status" 2>/dev/null | sed 's/.*: *//' || echo "—")
        round_info=" | Round: $current_round ($substage)"
    fi

    # Bug count from known_issues.md
    local bugs=""
    local ki_file="$checkout/.feature/$SLUG/known_issues.md"
    if [[ -f "$ki_file" ]]; then
        local resolved
        resolved=$(grep -c 'RESOLVED' "$ki_file" 2>/dev/null || echo "0")
        if [[ "$resolved" -gt 0 ]]; then
            bugs=" | Bugs: $resolved"
        fi
    fi

    # Recent activity from cycle-log.md (last meaningful line)
    local activity=""
    local cycle_log="$checkout/.feature/$SLUG/cycle-log.md"
    if [[ -f "$cycle_log" ]]; then
        local last_entry
        last_entry=$(grep -m1 '^###' "$cycle_log" 2>/dev/null | head -1 || true)
        if [[ -n "$last_entry" ]]; then
            activity=" | Last: ${last_entry:4:40}"
        fi
    fi

    printf "%-14s [%-10s] Stage: %-15s | Tests: %-3s | Impl: %s/%-2s | Tokens: %-8s%s%s%s\n" \
        "$arm_name:" "$state" "$stage" "$test_count" "$impl_done" "$impl_total" \
        "$tokens" "$round_info" "$bugs" "$activity"
}

show_status() {
    echo "=== Experiment Status ($(date '+%Y-%m-%d %H:%M:%S')) ==="
    get_arm_status "enhanced-tdd"
    get_arm_status "atdd"
    echo ""
}

if $ONCE; then
    show_status
else
    echo "Watching experiment progress every ${INTERVAL}s (Ctrl+C to stop)"
    echo ""
    while true; do
        clear
        show_status
        sleep "$INTERVAL"
    done
fi
"""
    with open(watch_path, "w") as f:
        f.write(content)
    os.chmod(watch_path, 0o755)
    print(f"  Generated {watch_path}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description="Set up Enhanced TDD vs aTDD comparative experiment"
    )
    parser.add_argument("--feature", required=True,
                        help="Feature slug to experiment on")
    parser.add_argument("--jlsm-path", default=None,
                        help="Path to jlsm repo (default: auto-detect)")
    parser.add_argument("--vallorcine-path", default=None,
                        help="Path to vallorcine repo (default: auto-detect)")
    parser.add_argument("--budget-usd", type=float, default=0,
                        help="Max budget per arm in USD (default: 0 = no limit, for subscriptions)")
    parser.add_argument("--max-rounds", type=int, default=3,
                        help="Max aTDD rounds (default: 3)")
    parser.add_argument("--work-dir", default="/tmp/vallorcine-experiment",
                        help="Directory for experiment (default: /tmp/vallorcine-experiment)")
    args = parser.parse_args()

    slug = args.feature

    # Auto-detect paths
    vallorcine_path = args.vallorcine_path
    if not vallorcine_path:
        vallorcine_path = os.path.abspath(os.path.join(_harness_dir, "..", ".."))
    vallorcine_path = os.path.abspath(vallorcine_path)

    jlsm_path = args.jlsm_path
    if not jlsm_path:
        jlsm_path = os.path.abspath(
            os.path.join(vallorcine_path, "..", "..", "nathannorthcutt", "jlsm")
        )
    jlsm_path = os.path.abspath(jlsm_path)

    # Validate paths
    if not os.path.isdir(jlsm_path):
        print(f"Error: jlsm not found at {jlsm_path}", file=sys.stderr)
        sys.exit(1)
    if not os.path.isdir(vallorcine_path):
        print(f"Error: vallorcine not found at {vallorcine_path}", file=sys.stderr)
        sys.exit(1)

    # Load feature metadata
    inventory_path = os.path.join(vallorcine_path, "aTDD-research", "feature-inventory.json")
    missing_path = os.path.join(vallorcine_path, "aTDD-research", "missing-features.json")
    briefs_dir = os.path.join(vallorcine_path, "aTDD-research", "briefs")
    overlay_dir = os.path.join(vallorcine_path, "aTDD-research",
                               "planning-state", slug)

    metadata = run_feature.collect_feature_metadata(inventory_path, missing_path, slug)
    if not metadata:
        print(f"Error: feature '{slug}' not found in inventory", file=sys.stderr)
        sys.exit(1)

    # Compute scope
    scope = run_feature.compute_feature_scope(
        jlsm_path, metadata["parent_sha"], metadata["feature_sha"]
    )
    if not scope:
        print(f"Error: could not compute feature scope", file=sys.stderr)
        sys.exit(1)

    work_dir = os.path.abspath(args.work_dir)

    print(f"\n{'='*60}", file=sys.stderr)
    print(f"Enhanced TDD vs aTDD Experiment", file=sys.stderr)
    print(f"{'='*60}", file=sys.stderr)
    print(f"  Feature:    {slug}", file=sys.stderr)
    print(f"  Parent SHA: {metadata['parent_sha']}", file=sys.stderr)
    print(f"  Budget:     subscription (no API limit)", file=sys.stderr)
    print(f"  Max rounds: {args.max_rounds} (aTDD)", file=sys.stderr)
    print(f"  Work dir:   {work_dir}", file=sys.stderr)
    print(f"  jlsm:       {jlsm_path}", file=sys.stderr)
    print(f"  vallorcine: {vallorcine_path}", file=sys.stderr)

    # Clean up existing experiment
    if os.path.exists(work_dir):
        print(f"\n  Removing existing experiment at {work_dir}...", file=sys.stderr)
        shutil.rmtree(work_dir)

    os.makedirs(work_dir, exist_ok=True)

    # Generate session IDs
    session_ids = {
        "enhanced-tdd": str(uuid.uuid4()),
        "atdd": str(uuid.uuid4()),
    }

    # Set up both arms
    etdd_checkout = setup_arm(
        jlsm_path, vallorcine_path, slug, metadata, scope,
        "enhanced-tdd", work_dir, briefs_dir, overlay_dir,
    )
    atdd_checkout = setup_arm(
        jlsm_path, vallorcine_path, slug, metadata, scope,
        "atdd", work_dir, briefs_dir, overlay_dir,
    )

    # Verify identical state
    verify_identical_state(
        os.path.join(work_dir, "enhanced-tdd"),
        os.path.join(work_dir, "atdd"),
    )

    # Generate run scripts
    print(f"\n--- Generating run scripts ---", file=sys.stderr)
    atdd_prompt = ATDD_PROMPT.replace("{max_rounds}", str(args.max_rounds))

    write_run_script(
        os.path.join(work_dir, "enhanced-tdd"),
        "enhanced-tdd", ENHANCED_TDD_PROMPT,
        session_ids["enhanced-tdd"],
    )
    write_run_script(
        os.path.join(work_dir, "atdd"),
        "atdd", atdd_prompt,
        session_ids["atdd"],
    )

    # Generate utility scripts
    write_compare_script(work_dir, vallorcine_path, slug)
    write_watch_script(work_dir, slug)

    # Save experiment manifest
    manifest = {
        "feature": slug,
        "parent_sha": metadata["parent_sha"],
        "feature_sha": metadata["feature_sha"],
        "budget": "subscription",
        "max_rounds": args.max_rounds,
        "session_ids": session_ids,
        "created": datetime.now(timezone.utc).isoformat(),
        "work_dir": work_dir,
        "jlsm_path": jlsm_path,
        "vallorcine_path": vallorcine_path,
        "arms": {
            "enhanced-tdd": {
                "checkout": os.path.join(work_dir, "enhanced-tdd", "checkout"),
                "run_script": os.path.join(work_dir, "enhanced-tdd", "run.sh"),
                "output_file": os.path.join(work_dir, "enhanced-tdd-output.jsonl"),
            },
            "atdd": {
                "checkout": os.path.join(work_dir, "atdd", "checkout"),
                "run_script": os.path.join(work_dir, "atdd", "run.sh"),
                "output_file": os.path.join(work_dir, "atdd-output.jsonl"),
            },
        },
    }
    manifest_path = os.path.join(work_dir, "experiment-manifest.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    # Print instructions
    print(f"\n{'='*60}", file=sys.stderr)
    print(f"Experiment ready!", file=sys.stderr)
    print(f"{'='*60}", file=sys.stderr)
    print(f"", file=sys.stderr)
    print(f"  Directory: {work_dir}", file=sys.stderr)
    print(f"", file=sys.stderr)
    print(f"  Run Enhanced TDD first:", file=sys.stderr)
    print(f"    {work_dir}/enhanced-tdd/run.sh", file=sys.stderr)
    print(f"", file=sys.stderr)
    print(f"  Then run aTDD:", file=sys.stderr)
    print(f"    {work_dir}/atdd/run.sh", file=sys.stderr)
    print(f"", file=sys.stderr)
    print(f"  Monitor progress:", file=sys.stderr)
    print(f"    {work_dir}/watch-progress.sh", file=sys.stderr)
    print(f"", file=sys.stderr)
    print(f"  Collect results after both complete:", file=sys.stderr)
    print(f"    {work_dir}/compare.sh", file=sys.stderr)
    print(f"", file=sys.stderr)
    print(f"  Session IDs:", file=sys.stderr)
    for arm, sid in session_ids.items():
        print(f"    {arm}: {sid}", file=sys.stderr)
    print(f"{'='*60}", file=sys.stderr)


if __name__ == "__main__":
    main()
