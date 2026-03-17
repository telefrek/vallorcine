#!/usr/bin/env bash
# vallorcine status line script
# Displays feature pipeline stage, token usage, and context % in Claude Code's status line.
#
# Installed to .claude/scripts/statusline.sh
# Configured via settings.json: "statusLine": { "type": "command", "command": "bash .claude/scripts/statusline.sh" }
#
# Performance: <10ms typical. Reads 1-2 small files + stdin JSON.
# Zero token cost — runs locally by Claude Code after each assistant message.

input=$(cat)

# ── Extract session info from stdin JSON ─────────────────────────────────────

context_pct=""
total_tokens=""
if command -v jq &>/dev/null; then
    read -r context_pct total_tokens < <(
        echo "$input" | jq -r '[(.context_window.used_percentage // empty), (.context_window.total_input_tokens // empty)] | @tsv' 2>/dev/null
    )
fi

# ── Format token count (e.g. 1234567 → "1.2M") ─────────────────────────────

fmt_tokens() {
    local n="$1"
    [[ -n "$n" && "$n" != "null" ]] || return
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
            # Build stage display
            case "$cached_stage" in
                scoping)        stage_display="$slug · scoping" ;;
                domains)        stage_display="$slug · domains" ;;
                planning)       stage_display="$slug · planning" ;;
                testing)        stage_display="$slug · testing" ;;
                implementation) stage_display="$slug · implementing" ;;
                refactor)
                    # Show refactor substep if available (2a-2h)
                    if [[ "$substage" =~ ^2[a-h] ]]; then
                        case "$substage" in
                            2a*) stage_display="$slug · refactor · naming" ;;
                            2b*) stage_display="$slug · refactor · dead code" ;;
                            2c*) stage_display="$slug · refactor · structure" ;;
                            2d*) stage_display="$slug · refactor · DRY" ;;
                            2e*) stage_display="$slug · refactor · missing tests" ;;
                            2f*) stage_display="$slug · refactor · integration" ;;
                            2g*) stage_display="$slug · refactor · docs" ;;
                            2h*) stage_display="$slug · refactor · security" ;;
                            *)   stage_display="$slug · refactor" ;;
                        esac
                    else
                        stage_display="$slug · refactor"
                    fi
                    ;;
                pr)             stage_display="$slug · PR draft" ;;
                *)              stage_display="$slug · $cached_stage" ;;
            esac
        fi
    fi
fi

# ── Build output line ────────────────────────────────────────────────────────

parts=()

if [[ -n "$stage_display" ]]; then
    parts+=("\033[36m$stage_display\033[0m")
fi

# Show total tokens consumed
tokens_fmt=$(fmt_tokens "$total_tokens")
if [[ -n "$tokens_fmt" ]]; then
    parts+=("${tokens_fmt} tokens")
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
