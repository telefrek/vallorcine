#!/usr/bin/env bash
# vallorcine status line script
# Displays feature pipeline stage, per-stage token usage, and context % in Claude Code's status line.
#
# Installed to .claude/scripts/statusline.sh
# Configured via settings.json: "statusLine": { "type": "command", "command": "bash .claude/scripts/statusline.sh" }
#
# Performance: <10ms typical. Reads 2-3 small files + stdin JSON.
# Zero token cost — runs locally by Claude Code after each assistant message.

input=$(cat)

# ── Extract session info from stdin JSON ─────────────────────────────────────

context_pct=""
total_tokens=""
if command -v jq &>/dev/null; then
    read -r context_pct ctx_size < <(
        echo "$input" | jq -r '[(.context_window.used_percentage // empty), (.context_window.context_window_size // empty)] | @tsv' 2>/dev/null
    )
fi

# ── Format token count (e.g. 1234567 → "1.2M") ─────────────────────────────

fmt_tokens() {
    local n="$1"
    [[ "$n" =~ ^[0-9]+$ ]] || return
    if [[ "$n" -ge 1000000 ]]; then
        local whole=$(( n / 1000000 ))
        local frac=$(( (n % 1000000) / 100000 ))
        echo "${whole}.${frac}M"
    elif [[ "$n" -ge 1000 ]]; then
        local whole=$(( n / 1000 ))
        local frac=$(( (n % 1000) / 100 ))
        echo "${whole}.${frac}K"
    else
        echo "$n"
    fi
}

# ── Read pipeline state ──────────────────────────────────────────────────────

stage_display=""
stage_tokens=""
BASELINE_FILE=".claude/.statusline-baseline"

# Try .token-state first (lightweight, single file)
if [[ -f .claude/.token-state ]]; then
    feature_dir=""
    cached_stage=""
    source .claude/.token-state 2>/dev/null

    if [[ -n "$feature_dir" && -n "$cached_stage" && -f "$feature_dir/status.md" ]]; then
        slug=$(basename "$feature_dir")

        # Get substage for finer detail
        substage=$(grep -m1 '^\*\*Substage:\*\*' "$feature_dir/status.md" 2>/dev/null \
            | sed 's/\*\*Substage:\*\* *//' | tr -d '[:space:]')

        # Terminal states — feature is done, don't show stale stage
        is_terminal=0
        case "$cached_stage/$substage" in
            pr/created|pr/complete) is_terminal=1 ;;
        esac

        if [[ "$is_terminal" == "0" ]]; then
            # Build stage display with substage detail
            sub=""
            case "$cached_stage" in
                scoping)
                    case "$substage" in
                        interviewing)     sub="interviewing" ;;
                        confirming-brief) sub="confirming brief" ;;
                        complete)         sub="complete" ;;
                    esac
                    stage_display="$slug · scoping${sub:+ · $sub}" ;;
                domains)
                    stage_display="$slug · domains${substage:+ · $substage}" ;;
                planning)
                    case "$substage" in
                        loading-context)    sub="loading context" ;;
                        surveying-codebase) sub="surveying code" ;;
                        confirmed-design)   sub="design confirmed" ;;
                        writing-stubs)      sub="writing stubs" ;;
                        contract-revised)   sub="contract revised" ;;
                    esac
                    stage_display="$slug · planning${sub:+ · $sub}" ;;
                testing)
                    case "$substage" in
                        planning)             sub="planning tests" ;;
                        confirming-plan)      sub="confirming plan" ;;
                        writing-tests)        sub="writing tests" ;;
                        verifying-failures)   sub="verifying failures" ;;
                        *verified*failing*)   sub="tests verified" ;;
                        escalation*)          sub="escalation" ;;
                    esac
                    stage_display="$slug · testing${sub:+ · $sub}" ;;
                implementation)
                    case "$substage" in
                        loading-context)    sub="loading context" ;;
                        implementing)       sub="implementing" ;;
                        implemented:*)      sub="${substage#implemented: }" ;;
                        *all*tests*passing) sub="all passing" ;;
                        escalat*)           sub="escalation" ;;
                    esac
                    stage_display="$slug · implementing${sub:+ · $sub}" ;;
                refactor)
                    case "$substage" in
                        loading-context)        sub="loading context" ;;
                        refactor:*coding*)      sub="coding standards" ;;
                        refactor:*duplication*) sub="DRY" ;;
                        refactor:*security)     sub="security" ;;
                        refactor:*performance*) sub="performance" ;;
                        refactor:*missing*)     sub="missing tests" ;;
                        refactor:*integration*) sub="integration" ;;
                        refactor:*documentation*) sub="docs" ;;
                        refactor:*security-review*) sub="security review" ;;
                        refactor:*final-lint*)  sub="final lint" ;;
                        *refactor*complete*)    sub="complete" ;;
                        escalat*)               sub="escalation" ;;
                        cycle-5*)               sub="cycle limit" ;;
                    esac
                    stage_display="$slug · refactor${sub:+ · $sub}" ;;
                pr)
                    case "$substage" in
                        pr-draft-written) sub="draft ready" ;;
                    esac
                    stage_display="$slug · PR draft${sub:+ · $sub}" ;;
                *)
                    stage_display="$slug · $cached_stage" ;;
            esac

            # ── Per-stage token tracking via context % baseline ────────
            # Derive current tokens from used_percentage * context_window_size
            if [[ "$ctx_size" =~ ^[0-9]+$ && -n "$context_pct" ]]; then
                # Compute current tokens in context (integer math: pct * size / 100)
                # Use awk for floating point since context_pct can be "24.5"
                current_ctx_tokens=$(awk "BEGIN { printf \"%d\", $context_pct * $ctx_size / 100 }")

                baseline_stage=""
                baseline_ctx_tokens=""
                [[ -f "$BASELINE_FILE" ]] && source "$BASELINE_FILE" 2>/dev/null

                if [[ "$baseline_stage" != "$cached_stage" || ! "$baseline_ctx_tokens" =~ ^[0-9]+$ ]]; then
                    # Stage changed or no baseline — set new baseline
                    baseline_ctx_tokens="$current_ctx_tokens"
                    printf 'baseline_stage=%q\nbaseline_ctx_tokens=%s\n' \
                        "$cached_stage" "$current_ctx_tokens" > "$BASELINE_FILE"
                fi

                stage_used=$(( current_ctx_tokens - baseline_ctx_tokens ))
                [[ "$stage_used" -lt 0 ]] && stage_used=0
                stage_tokens=$(fmt_tokens "$stage_used")
            fi
        else
            # Terminal state — clean up baseline
            rm -f "$BASELINE_FILE"
        fi
    fi
else
    # No active feature — clean up baseline if stale
    rm -f "$BASELINE_FILE"
fi

# ── Build output line ────────────────────────────────────────────────────────

parts=()

if [[ -n "$stage_display" ]]; then
    parts+=("\033[36m$stage_display\033[0m")
fi

# Show per-stage tokens if available
if [[ -n "$stage_tokens" ]]; then
    parts+=("${stage_tokens} tokens")
fi

if [[ -n "$context_pct" ]]; then
    # Color context usage: green < 50%, yellow 50-80%, red > 80%
    ctx_int=${context_pct%.*}
    [[ "$ctx_int" =~ ^[0-9]+$ ]] || ctx_int=0
    if [[ "$ctx_int" -ge 80 ]]; then
        parts+=("\033[31mctx ${context_pct}%\033[0m")
    elif [[ "$ctx_int" -ge 50 ]]; then
        parts+=("\033[33mctx ${context_pct}%\033[0m")
    else
        parts+=("\033[32mctx ${context_pct}%\033[0m")
    fi
fi

# Join with separator
if [[ ${#parts[@]} -gt 0 ]]; then
    output=""
    for i in "${!parts[@]}"; do
        if [[ $i -gt 0 ]]; then
            output+=" · "
        fi
        output+="${parts[$i]}"
    done
    echo -e "$output"
fi
