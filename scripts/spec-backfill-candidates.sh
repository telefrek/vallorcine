#!/usr/bin/env bash
# spec-backfill-candidates.sh — find code locations likely enforcing a
# requirement, ranked by subject-token overlap.
#
# Usage:
#   spec-backfill-candidates.sh <spec-id> <R-id> [--top N] [project-root]
#
# Output (stdout, one row per candidate, ranked by score descending):
#   <score>\t<rel-path>:<line>\t<truncated-context>
#
# Stderr:
#   [backfill] <spec-id>.<R-id> text: <requirement text>
#   [backfill] <spec-id>.<R-id> tokens: <tok1>, <tok2>, ...
#   [backfill] <N> candidate(s) above threshold
#
# The ranking heuristic mirrors `spec-resolve.sh` Step 7c displacement
# detection: extract subject tokens from the requirement text (CamelCase or
# snake_case identifiers >=4 chars, deduped, common stopwords excluded),
# grep the codebase for each token, and score each line by how many distinct
# requirement tokens appear on or within +/-2 lines of it. Lines are filtered
# below a minimum score (default 2) to prune noise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=spec-lib.sh disable=SC1091
source "$SCRIPT_DIR/spec-lib.sh"

SPEC_ID=""
R_ID=""
PROJECT_ROOT=""
TOP_N=8
MIN_SCORE=2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --top)        shift; TOP_N="${1:-8}" ;;
    --min-score)  shift; MIN_SCORE="${1:-2}" ;;
    --help|-h)
      echo "Usage: spec-backfill-candidates.sh <spec-id> <R-id> [--top N] [--min-score N] [project-root]" >&2
      exit 0
      ;;
    -*)
      echo "ERROR: unknown flag '$1'" >&2
      exit 1
      ;;
    *)
      if   [[ -z "$SPEC_ID" ]]; then SPEC_ID="$1"
      elif [[ -z "$R_ID" ]];    then R_ID="$1"
      elif [[ -z "$PROJECT_ROOT" ]]; then PROJECT_ROOT="$1"
      else echo "ERROR: extra positional argument '$1'" >&2; exit 1
      fi
      ;;
  esac
  shift
done

[[ -z "$SPEC_ID" || -z "$R_ID" ]] && {
  echo "Usage: spec-backfill-candidates.sh <spec-id> <R-id> [--top N] [project-root]" >&2
  exit 1
}

# ── Locate project root ──────────────────────────────────────────────────────
if [[ -z "$PROJECT_ROOT" ]]; then
  dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.spec" ]] || [[ -d "$dir/.git" ]]; then
      PROJECT_ROOT="$dir"
      break
    fi
    dir="$(dirname "$dir")"
  done
  [[ -z "$PROJECT_ROOT" ]] && {
    echo "ERROR: Could not find project root (no .spec/ or .git/ found)." >&2
    exit 1
  }
fi

MANIFEST="$PROJECT_ROOT/.spec/registry/manifest.json"
[[ ! -f "$MANIFEST" ]] && {
  echo "ERROR: spec manifest not found at $MANIFEST" >&2
  exit 1
}

SPEC_FILE=$(spec_file_for_id "$MANIFEST" "$SPEC_ID")
[[ -z "$SPEC_FILE" || ! -f "$SPEC_FILE" ]] && {
  echo "ERROR: Could not resolve spec file for '$SPEC_ID'" >&2
  exit 1
}

# ── Extract requirement text ─────────────────────────────────────────────────
# R-ids may span multiple lines. Read from the matching `^R<id>.` line up to
# the next `^R[0-9]` or the end of the `## Requirements` section.
R_TEXT=$(awk -v rid="$R_ID" '
  /^## Requirements *$/ { in_req = 1; next }
  /^## / && in_req     { in_req = 0 }
  in_req {
    # Match the line that opens our R-id (e.g., `R3.` or `R51a.`).
    if ($0 ~ ("^" rid "\\.")) { capture = 1 }
    else if (capture && $0 ~ /^R[0-9]+[a-z]*(-[0-9]+[a-z]*)?\./) { capture = 0 }
    if (capture) print
  }
' "$SPEC_FILE")

[[ -z "$R_TEXT" ]] && {
  echo "ERROR: Requirement '$R_ID' not found in $SPEC_FILE" >&2
  exit 1
}

echo "[backfill] $SPEC_ID.$R_ID text: $(echo "$R_TEXT" | head -1)" >&2

# ── Extract subject tokens ───────────────────────────────────────────────────
# Same heuristic as spec-resolve.sh Step 7c: CamelCase or snake_case
# identifiers, length >=4, deduplicated, common stopwords skipped.
# Lowercase plural tokens get a singular variant added (charges → charge,
# entries → entry) so prose plurals match singular code identifiers.
TOKENS=$(echo "$R_TEXT" | awk '
  BEGIN {
    # Common English / spec-prose stopwords that survive the length filter.
    # Mirrors the prune list in spec-resolve.sh tokens_from_line.
    split("must shall will should when then this that with from into upon they them their there these those have been being which what whose where because every", sw)
    for (i in sw) skip[sw[i]] = 1
  }
  function emit(tok) {
    if (length(tok) < 4) return
    if (tolower(tok) in skip) return
    if (tok in dedup) return
    dedup[tok] = 1
    print tok
  }
  {
    s = $0
    while (match(s, /[A-Z][a-zA-Z0-9]+|[a-z_][a-z_0-9]+/)) {
      tok = substr(s, RSTART, RLENGTH)
      s   = substr(s, RSTART + RLENGTH)
      emit(tok)
      # For lowercase tokens, also emit a simple singular form so prose
      # plurals match singular code identifiers (charges → charge,
      # entries → entry, classes → class).
      if (tok ~ /^[a-z]/) {
        if (tok ~ /ies$/)         emit(substr(tok, 1, length(tok)-3) "y")
        else if (tok ~ /sses$/)   emit(substr(tok, 1, length(tok)-2))
        else if (tok ~ /[^s]es$/) emit(substr(tok, 1, length(tok)-2))
        else if (tok ~ /[^s]s$/)  emit(substr(tok, 1, length(tok)-1))
      }
    }
  }
')

if [[ -z "$TOKENS" ]]; then
  echo "[backfill] no subject tokens extracted from requirement text" >&2
  exit 0
fi

token_list=$(echo "$TOKENS" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
echo "[backfill] $SPEC_ID.$R_ID tokens: $token_list" >&2

# ── Determine scan directories ───────────────────────────────────────────────
SCAN_DIRS=()
if [[ -n "${SPEC_TRACE_DIRS:-}" ]]; then
  IFS=',' read -ra USER_DIRS <<< "$SPEC_TRACE_DIRS"
  for d in "${USER_DIRS[@]}"; do
    d=$(echo "$d" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -d "$PROJECT_ROOT/$d" ]] && SCAN_DIRS+=("$PROJECT_ROOT/$d")
  done
else
  for candidate in src lib app main test tests spec modules examples benchmarks; do
    [[ -d "$PROJECT_ROOT/$candidate" ]] && SCAN_DIRS+=("$PROJECT_ROOT/$candidate")
  done
fi

if [[ ${#SCAN_DIRS[@]} -eq 0 ]]; then
  echo "[backfill] no source directories to scan in $PROJECT_ROOT" >&2
  exit 0
fi

# ── Grep each token, accumulate hits, then score ────────────────────────────
# A line's score = number of distinct requirement tokens appearing on it OR
# within ±2 lines of it (a small window so a method declaration scores
# alongside its body). We greatly simplify: per-line single-token hits with
# a final aggregation by file+line.

HITS_FILE=$(mktemp)
trap 'rm -f "$HITS_FILE"' EXIT

while IFS= read -r tok; do
  [[ -z "$tok" ]] && continue
  # Case-insensitive substring (fixed-string, not regex). Word boundaries
  # would miss tokens fragmented inside CamelCase identifiers (e.g., the
  # prose token `Expiry` would not word-boundary-match `validateExpiry` in
  # code). Substring + min-score filtering trades precision for recall:
  # noise gets pruned by requiring at least MIN_SCORE distinct token hits
  # at the same line.
  grep -rniIF -- "$tok" "${SCAN_DIRS[@]}" \
    --include='*.java' --include='*.py' --include='*.js' --include='*.ts' \
    --include='*.go' --include='*.rs' --include='*.kt' --include='*.scala' \
    --include='*.c' --include='*.cpp' --include='*.h' --include='*.hpp' \
    --include='*.cs' --include='*.rb' --include='*.swift' --include='*.m' \
    --include='*.sh' \
    2>/dev/null | while IFS= read -r ghit; do
      # ghit format: file:line:content
      printf '%s\t%s\n' "$tok" "$ghit"
    done >> "$HITS_FILE" || true
done <<< "$TOKENS"

if [[ ! -s "$HITS_FILE" ]]; then
  echo "[backfill] 0 candidate(s) above threshold" >&2
  exit 0
fi

# ── Aggregate score per (file, line) — distinct tokens per location ────────
# For each unique (file:line), count distinct tokens that hit. Filter test
# files OUT of impl candidates? No — annotation in tests is also valid.
# Output: score \t file:line \t context (truncated)

CANDIDATES=$(awk -F'\t' -v root="$PROJECT_ROOT/" '
  {
    tok = $1
    # $2 is "file:line:content" — split.
    n = index($2, ":")
    file = substr($2, 1, n - 1)
    rest = substr($2, n + 1)
    n2 = index(rest, ":")
    lineno = substr(rest, 1, n2 - 1)
    content = substr(rest, n2 + 1)

    # Make path relative to project root for display
    rel = file
    sub(root, "", rel)

    key = rel ":" lineno
    if (!(key SUBSEP tok in seen)) {
      seen[key SUBSEP tok] = 1
      score[key]++
      # First-seen content wins for the snippet
      if (!(key in ctx)) {
        # Trim leading/trailing whitespace; truncate to 80 chars
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", content)
        if (length(content) > 80) content = substr(content, 1, 77) "..."
        ctx[key] = content
      }
    }
  }
  END {
    for (k in score) {
      printf "%d\t%s\t%s\n", score[k], k, ctx[k]
    }
  }
' "$HITS_FILE" | awk -F'\t' -v min="$MIN_SCORE" '$1 >= min' | sort -t$'\t' -k1,1nr -k2,2)

if [[ -z "$CANDIDATES" ]]; then
  echo "[backfill] 0 candidate(s) above threshold (min-score=$MIN_SCORE)" >&2
  exit 0
fi

# Emit top N
total=$(echo "$CANDIDATES" | wc -l | tr -d ' ')
echo "[backfill] $total candidate(s) above threshold (min-score=$MIN_SCORE), showing top $TOP_N" >&2
echo "$CANDIDATES" | head -"$TOP_N"
