#!/usr/bin/env bash
# vallorcine narrative generation wrapper
# Detects available runtimes and delegates to the best implementation.
# Reports failures instead of swallowing them — narrative is required
# for pipeline observability (token data, phase durations, session counts).
#
# Priority: python3 → node
# Both implementations produce identical markdown output.
#
# Usage: narrative-wrapper.sh <slug> <feature-dir>
# Exit codes:
#   0 = narrative.md written successfully
#   1 = generation failed (stderr has details)
#   2 = no runtime available (python3 or node required)
#   3 = missing arguments

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

slug="${1:-}"
feature_dir="${2:-}"

if [[ -z "$slug" || -z "$feature_dir" ]]; then
    echo "narrative-wrapper: missing arguments (slug='$slug', feature_dir='$feature_dir')" >&2
    exit 3
fi

output_file="$feature_dir/narrative.md"

# Try Python (best: native JSON parsing, streaming JSONL)
if command -v python3 &>/dev/null; then
    if python3 "$SCRIPT_DIR/narrative/generate.py" "$slug" "$feature_dir" 2>/tmp/vallorcine-narrative-err.log; then
        if [[ -f "$output_file" && -s "$output_file" ]]; then
            exit 0
        else
            echo "narrative-wrapper: python3 exited 0 but $output_file not written or empty" >&2
            cat /tmp/vallorcine-narrative-err.log >&2 2>/dev/null
            # Fall through to try node
        fi
    else
        echo "narrative-wrapper: python3 failed (exit $?)" >&2
        cat /tmp/vallorcine-narrative-err.log >&2 2>/dev/null
        # Fall through to try node
    fi
fi

# Try Node.js
if command -v node &>/dev/null; then
    if node "$SCRIPT_DIR/narrative/generate.js" "$slug" "$feature_dir" 2>/tmp/vallorcine-narrative-err.log; then
        if [[ -f "$output_file" && -s "$output_file" ]]; then
            exit 0
        else
            echo "narrative-wrapper: node exited 0 but $output_file not written or empty" >&2
            cat /tmp/vallorcine-narrative-err.log >&2 2>/dev/null
            exit 1
        fi
    else
        echo "narrative-wrapper: node failed (exit $?)" >&2
        cat /tmp/vallorcine-narrative-err.log >&2 2>/dev/null
        exit 1
    fi
fi

# No runtime available
echo "narrative-wrapper: neither python3 nor node available — cannot generate narrative" >&2
exit 2
