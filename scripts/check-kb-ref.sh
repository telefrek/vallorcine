#!/usr/bin/env bash
# check-kb-ref.sh — PostToolUse hook for Write/Edit that links source code
# back to the KB.
#
# Purpose. Vallorcine ships a structured KB; without a back-link from code to
# KB, articles drift from the implementations they describe and a future
# reader has no way to find the research that informed a design choice.
# `@spec` annotations cover spec→code; this hook covers KB→code.
#
# Convention. A source file SHOULD declare which KB articles informed it:
#
#     // KB: .kb/algorithms/encryption/three-level-key-hierarchy.md
#     // KB: .kb/patterns/validation/silent-fallthrough.md, .kb/systems/database-engines/wal-recovery.md
#
# Single-line comment syntaxes recognised: `// KB:` (Java/JS/TS/Go/Rust/C/C++),
# `# KB:` (Python/Bash/Ruby/Perl), `<!-- KB: ... -->` (HTML/XML/Markdown).
# Multiple citations may appear comma-separated on one line, OR on separate
# `KB:` lines.
#
# When the hook fires (warn-only, never blocks):
#
#   1. Citation present but path missing — `.kb/foo/bar.md` doesn't exist.
#      The most common bit-rot: rename a KB entry, code citation goes stale.
#
#   2. Citation present but `applies_to` doesn't include this file path —
#      likely a copy-paste citation. The cited entry's applies_to globs
#      do not match the file being written.
#
#   3. No citation AND there exist KB entries whose `applies_to` matches the
#      file path. Suggest those entries by path; the writer can ignore or
#      pick one.
#
# Auto-disable. If `.kb/` doesn't exist, contains only `_refs/`, or contains
# no entries with `applies_to` set, the hook exits silently — projects that
# don't use the KB for code-relevant research aren't nagged.
#
# Output. JSON `{"systemMessage": "..."}` to stdout when there's something
# to surface; nothing otherwise. Always exits 0 — hook is advisory.
#
# Stdin. Standard PostToolUse JSON: `{"tool_input": {"file_path": "..."}}`
# or `{"tool_response": {"filePath": "..."}}`. Tolerates both shapes.

set -euo pipefail
shopt -s globstar nullglob

# ── Read the tool result ─────────────────────────────────────────────────────

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

FILE_PATH="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    p = ((d.get("tool_input") or {}).get("file_path")
         or (d.get("tool_response") or {}).get("filePath")
         or "")
    print(p)
except Exception:
    pass
' 2>/dev/null || true)"

[[ -z "$FILE_PATH" ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

# Resolve to project-relative for cleaner paths in messages and matching.
PROJECT_ROOT="$(pwd -P)"
case "$FILE_PATH" in
  /*) REL_PATH="${FILE_PATH#"$PROJECT_ROOT/"}" ;;
  *)  REL_PATH="$FILE_PATH" ;;
esac

# ── Filter: skip vallorcine internals and known non-source ──────────────────

case "$REL_PATH" in
  .kb/*|.spec/*|.work/*|.feature/*|.curate/*|.decisions/*|.claude/*|.git/*) exit 0 ;;
  WIP.md|CONTEXT.md|SETTLED.md|CHANGELOG.md|README.md|VERSION) exit 0 ;;
esac

EXT="${REL_PATH##*.}"
case "$EXT" in
  md|json|yaml|yml|toml|lock|txt|gitignore|env|properties) exit 0 ;;
esac

# ── Auto-disable: no meaningful KB ─────────────────────────────────────────

if [[ ! -d ".kb" ]]; then exit 0; fi

# Count KB entries (excluding indexes, refs, archive). Bail if zero.
KB_ENTRY_COUNT=0
for f in .kb/**/*.md; do
  case "$f" in
    .kb/CLAUDE.md|.kb/_refs/*|.kb/_archive*|*/CLAUDE.md) continue ;;
  esac
  [[ -f "$f" ]] && KB_ENTRY_COUNT=$((KB_ENTRY_COUNT + 1))
done
[[ "$KB_ENTRY_COUNT" -eq 0 ]] && exit 0

# ── Helpers ──────────────────────────────────────────────────────────────────

# Extract every cited KB path from the source file. Looks for KB: <path>
# in line- or HTML-comment form, supports comma-separated multi-citation.
# Echoes one path per line.
extract_citations() {
  local file="$1"
  # Patterns:
  #   //  KB: <paths>
  #   #   KB: <paths>
  #   <!-- KB: <paths> -->
  # Strip optional `-->` suffix and split on commas.
  grep -E '^[[:space:]]*(//|#|<!--)[[:space:]]*KB:' "$file" 2>/dev/null \
    | sed -E 's~^[[:space:]]*(//|#|<!--)[[:space:]]*KB:[[:space:]]*~~' \
    | sed -E 's~[[:space:]]*-->[[:space:]]*$~~' \
    | tr ',' '\n' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | grep -v '^$' || true
}

# Extract applies_to entries from a KB entry's frontmatter. Echoes one
# pattern per line. Tolerates the inline (`applies_to: ["a", "b"]`) and
# block (`applies_to:\n  - a\n  - b`) YAML forms.
extract_applies_to() {
  local kb_file="$1"
  awk '
    BEGIN { in_fm = 0; in_at = 0 }
    /^---[[:space:]]*$/ { in_fm = !in_fm; next }
    in_fm && /^applies_to:[[:space:]]*\[/ {
      # Inline list — strip key, brackets, quotes; print each comma-separated entry.
      sub(/^applies_to:[[:space:]]*\[[[:space:]]*/, "")
      sub(/[[:space:]]*\][[:space:]]*$/, "")
      gsub(/"/, "")
      gsub(/'\''/, "")
      n = split($0, parts, /[[:space:]]*,[[:space:]]*/)
      for (i = 1; i <= n; i++) if (parts[i] != "") print parts[i]
      next
    }
    in_fm && /^applies_to:[[:space:]]*$/ { in_at = 1; next }
    in_fm && in_at && /^[[:space:]]*-[[:space:]]+/ {
      sub(/^[[:space:]]*-[[:space:]]+/, "")
      gsub(/"/, "")
      gsub(/'\''/, "")
      print
      next
    }
    in_fm && in_at && /^[^[:space:]-]/ { in_at = 0 }
  ' "$kb_file" 2>/dev/null
}

# Match a glob pattern against a path. Supports **, *, ?, [...]. Uses
# bash globstar for ** semantics (any number of intermediate dirs).
match_pattern() {
  local pattern="$1" path="$2"
  # shellcheck disable=SC2053
  [[ "$path" == $pattern ]]
}

# Returns 0 if any pattern in the entry's applies_to matches the path.
entry_applies_to_path() {
  local kb_file="$1" path="$2" pat
  while IFS= read -r pat; do
    [[ -z "$pat" ]] && continue
    if match_pattern "$pat" "$path"; then return 0; fi
  done < <(extract_applies_to "$kb_file")
  return 1
}

# Find KB entries whose applies_to covers $REL_PATH. Echoes paths.
suggest_entries() {
  local f
  for f in .kb/**/*.md; do
    case "$f" in
      .kb/CLAUDE.md|.kb/_refs/*|.kb/_archive*|*/CLAUDE.md) continue ;;
    esac
    [[ -f "$f" ]] || continue
    if entry_applies_to_path "$f" "$REL_PATH"; then
      printf '%s\n' "$f"
    fi
  done
}

# Emit a systemMessage. Properly JSON-escapes the body.
emit() {
  local msg="$1"
  python3 -c 'import json, sys; print(json.dumps({"systemMessage": sys.argv[1]}))' "$msg"
}

# ── Run the checks ───────────────────────────────────────────────────────────

mapfile -t CITATIONS < <(extract_citations "$FILE_PATH")

PROBLEMS=()

if [[ "${#CITATIONS[@]}" -gt 0 ]]; then
  # Validate each citation.
  for cited in "${CITATIONS[@]}"; do
    # Normalise — accept both `.kb/foo.md` and `kb/foo.md`.
    local_path="$cited"
    case "$local_path" in
      .kb/*) ;;
      kb/*)  local_path=".$local_path" ;;
      *)     local_path=".kb/$local_path" ;;
    esac

    if [[ ! -f "$local_path" ]]; then
      PROBLEMS+=("citation points at missing entry: $cited")
      continue
    fi

    # Empty applies_to is acceptable (general research). Only flag a
    # mismatch when applies_to has entries AND none of them match.
    AT_COUNT=$(extract_applies_to "$local_path" | grep -c . 2>/dev/null || echo 0)
    if [[ "$AT_COUNT" -gt 0 ]]; then
      if ! entry_applies_to_path "$local_path" "$REL_PATH"; then
        PROBLEMS+=("$cited: applies_to does not include $REL_PATH (likely wrong citation)")
      fi
    fi
  done
else
  # No citation — see if anything in the KB applies to this file.
  mapfile -t SUGGESTIONS < <(suggest_entries)
  if [[ "${#SUGGESTIONS[@]}" -gt 0 ]]; then
    msg="${REL_PATH}: no KB citation, but matching entries exist:"
    for s in "${SUGGESTIONS[@]}"; do
      msg+=$'\n  '"// KB: $s"
    done
    msg+=$'\n''(add a `// KB: <path>` comment near the top of the file, or document why no KB applies.)'
    emit "$msg"
  fi
  # If no citations and nothing matches, stay silent — no nagging projects
  # whose KB hasn't grown into a given area yet.
  exit 0
fi

if [[ "${#PROBLEMS[@]}" -gt 0 ]]; then
  msg="${REL_PATH}: KB citation issues:"
  for p in "${PROBLEMS[@]}"; do
    msg+=$'\n  · '"$p"
  done
  emit "$msg"
fi

exit 0
