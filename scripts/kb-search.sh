#!/usr/bin/env bash
# vallorcine KB search wrapper
# Detects available runtimes and delegates to the best implementation.
# Falls back to grep-based hit counting if neither python3 nor node is available.
#
# Usage:
#   bash kb-search.sh "<query>" [--kb-root <path>] [--top <n>]
#
# Output (stdout): ranked list, one per line:
#   <score>  <topic>/<category>/<subject>
#
# Exit 0 always. Empty output if KB doesn't exist or no matches.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Argument parsing ─────────────────────────────────────────────────────────

QUERY=""
KB_ROOT=".kb"
TOP_N=10
FACET=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kb-root)
            KB_ROOT="${2:-}"
            shift 2
            ;;
        --top)
            TOP_N="${2:-10}"
            shift 2
            ;;
        --facet)
            # Comma-separated key=value list. Switches the script into
            # index-based filter mode (no keyword ranking; exact / list-
            # membership matching against the structured index at
            # .kb/_index.json).
            FACET="${2:-}"
            shift 2
            ;;
        *)
            if [[ -z "$QUERY" ]]; then
                QUERY="$1"
            fi
            shift
            ;;
    esac
done

if [[ ! -d "$KB_ROOT" ]]; then
    exit 0
fi

# ── Facet mode ───────────────────────────────────────────────────────────────
#
# When --facet is set, ignore keyword search and filter the JSON index by
# exact (scalar) or membership (list) match. The index is rebuilt on
# demand if missing or stale (older than any KB markdown file). One path
# per line on stdout; no score column.

if [[ -n "$FACET" ]]; then
    if ! command -v python3 >/dev/null 2>&1; then
        # Facet mode requires python3. Stay silent (consistent with the
        # exit-0-on-failure pattern of the keyword path) so callers
        # don't get tripped up by missing dependencies.
        exit 0
    fi

    INDEX="$KB_ROOT/_index.json"

    # Stale check: rebuild if any *.md under KB_ROOT is newer than the index.
    rebuild=0
    if [[ ! -f "$INDEX" ]]; then
        rebuild=1
    elif [[ -n "$(find "$KB_ROOT" -name '*.md' -newer "$INDEX" -print -quit 2>/dev/null)" ]]; then
        rebuild=1
    fi
    if [[ "$rebuild" -eq 1 ]]; then
        bash "$SCRIPT_DIR/kb-index.sh" --kb-root "$KB_ROOT" --out "$INDEX" \
            >/dev/null 2>&1 || exit 0
    fi

    python3 - "$INDEX" "$FACET" <<'PYEOF'
import json
import sys

index_path = sys.argv[1]
expr = sys.argv[2]

try:
    doc = json.load(open(index_path, encoding="utf-8"))
except Exception:
    sys.exit(0)

# Parse comma-separated key=value pairs. A value containing a literal
# comma is not currently supported — facet expressions stay simple.
filters: list[tuple[str, str]] = []
for pair in expr.split(","):
    pair = pair.strip()
    if not pair or "=" not in pair:
        continue
    k, _, v = pair.partition("=")
    filters.append((k.strip(), v.strip()))

if not filters:
    sys.exit(0)

# Field categories. Scalar fields use exact equality; list fields use
# membership (any element matches the value).
SCALAR_FIELDS = {"type", "topic", "category", "domain", "severity",
                 "research_status", "confidence", "last_researched", "title"}
LIST_FIELDS = {"tags", "applies_to", "domains", "constructs",
               "related", "decision_refs", "spec_refs"}


def matches(entry: dict, key: str, val: str) -> bool:
    if key in SCALAR_FIELDS:
        ev = entry.get(key)
        return ev == val
    if key in LIST_FIELDS:
        ev = entry.get(key) or []
        return val in ev
    # Unknown key — never matches. Caller's typo, not our problem.
    return False


for entry in doc.get("entries", []):
    if all(matches(entry, k, v) for k, v in filters):
        print(entry.get("path", ""))
PYEOF
    exit 0
fi

if [[ -z "$QUERY" ]]; then
    exit 0
fi

# ── Try Python ───────────────────────────────────────────────────────────────

if command -v python3 &>/dev/null; then
    if output=$(python3 "$SCRIPT_DIR/kb-search.py" "$QUERY" "$KB_ROOT" "$TOP_N" 2>/dev/null); then
        [[ -n "$output" ]] && echo "$output"
        exit 0
    fi
fi

# ── Try Node.js ──────────────────────────────────────────────────────────────

if command -v node &>/dev/null; then
    if output=$(node "$SCRIPT_DIR/kb-search.js" "$QUERY" "$KB_ROOT" "$TOP_N" 2>/dev/null); then
        [[ -n "$output" ]] && echo "$output"
        exit 0
    fi
fi

# ── Bash fallback: grep-based hit counting (not BM25) ────────────────────────
# Same output format but scores are integer hit counts instead of BM25 floats.

# Extract tokens from query (same pattern as spec-resolve.sh)
STOPWORDS="must|should|shall|will|when|then|that|this|with|from|into|each|have|does|been|also|only|the|and|for|are|but|not|you|all|can|her|was|one|our|out"

mapfile -t QUERY_TOKENS < <(
    echo "$QUERY" | grep -oE '[A-Z][a-zA-Z0-9]+|[a-z_][a-z_0-9]+' | \
    awk 'length >= 4' | \
    tr '[:upper:]' '[:lower:]' | \
    grep -vE "^($STOPWORDS)$" | \
    sort -u
)

if [[ ${#QUERY_TOKENS[@]} -eq 0 ]]; then
    exit 0
fi

# Scan category CLAUDE.md files and count token hits per subject
declare -A SCORES

while IFS= read -r cat_index; do
    # Extract topic/category from path
    rel="${cat_index#"$KB_ROOT/"}"
    # rel is like "topic/category/CLAUDE.md"
    topic="${rel%%/*}"
    rest="${rel#*/}"
    category="${rest%%/*}"

    # Read category index content
    content=$(cat "$cat_index" 2>/dev/null || true)
    content_lower=$(echo "$content" | tr '[:upper:]' '[:lower:]')

    # Extract subject filenames from Contents table links
    mapfile -t subject_files < <(
        echo "$content" | grep -oE '\[[^]]+\.md\]' | tr -d '[]' || true
    )

    for subj_file in "${subject_files[@]}"; do
        [[ -z "$subj_file" ]] && continue
        stem="${subj_file%.md}"
        key="$topic/$category/$stem"

        # Count query token hits in category index. Use here-strings so
        # SIGPIPE under pipefail cannot flip the result on a large KB
        # category index (`grep -q` closes stdin after first match).
        hits=0
        for token in "${QUERY_TOKENS[@]}"; do
            if grep -q "$token" <<< "$content_lower" 2>/dev/null; then
                hits=$((hits + 1))
            fi
        done

        # Also check subject file frontmatter if it exists
        subj_path="$KB_ROOT/$topic/$category/$subj_file"
        if [[ -f "$subj_path" ]]; then
            # Read up to second --- (frontmatter only)
            fm=$(awk '/^---$/{c++; if(c==2) exit} c>=1{print}' "$subj_path" 2>/dev/null || true)
            fm_lower=$(echo "$fm" | tr '[:upper:]' '[:lower:]')
            for token in "${QUERY_TOKENS[@]}"; do
                if grep -q "$token" <<< "$fm_lower" 2>/dev/null; then
                    hits=$((hits + 1))
                fi
            done
        fi

        if [[ $hits -gt 0 ]]; then
            SCORES["$key"]=$hits
        fi
    done
done < <(find "$KB_ROOT" -mindepth 3 -maxdepth 3 -name 'CLAUDE.md' -not -path '*/\.*' 2>/dev/null || true)

# Sort by score descending and emit top N
if [[ ${#SCORES[@]} -gt 0 ]]; then
    for key in "${!SCORES[@]}"; do
        echo "${SCORES[$key]}.00  $key"
    done | sort -t. -k1 -rn | head -n "$TOP_N"
fi

exit 0
