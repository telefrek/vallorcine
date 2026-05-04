#!/usr/bin/env bash
# curate-review-log.sh — append-only review log for /curate findings
#
# Replaces the prior pattern of a Review Log table embedded in
# .curate/curation-state.md, which the /curate skill rewrote on every run
# and so silently lost every prior `deferred`/`suggested` row. This tool
# manages a separate .curate/review-log.md that:
#   - is append-only (never overwritten in whole),
#   - records each finding with a stable structured key,
#   - exposes an `unresolved` query so the /curate skill can re-present
#     items the user previously deferred or noted-for-later.
#
# Subcommands:
#   migrate <state-md> <log-md>
#       If <state-md> contains a "## Review Log" section, copy its rows
#       into <log-md> (creating it with a header if needed) and remove
#       the Review Log section from <state-md>. Idempotent — re-running
#       on a migrated state file is a no-op.
#
#   append <log-md> <date> <key> "<description>" <status> ["<notes>"]
#       Append a row. Idempotent within a (date, key, status, notes)
#       tuple — repeated calls with identical values do not duplicate.
#
#   unresolved <log-md>
#       Emit `<key>|<latest-status>|<latest-description>|<latest-date>`
#       for each key whose most-recent row has status `deferred` or
#       `suggested`. A later `resolved` or `dismissed` row for the same
#       key supersedes earlier deferrals and excludes the key.
#
#   report <log-md>
#       One-line counts: total rows / unresolved keys / resolved keys.
#
# Status values:
#   deferred  — user picked Skip / Defer; should resurface next /curate.
#   suggested — user noted-for-later (closed session without acting).
#   resolved  — user took action (ran /architect, /research, etc.).
#   dismissed — user explicitly dismissed (will not resurface).
#   explored  — user investigated; no further action; treat as resolved.

set -euo pipefail

require_cmds() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || { echo "ERROR: '$c' is required but not found." >&2; exit 1; }
  done
}
require_cmds awk grep sed

usage() {
  cat <<'EOF' >&2
curate-review-log.sh — append-only review log

Usage:
  curate-review-log.sh migrate <state-md> <log-md>
  curate-review-log.sh append  <log-md> <date> <key> "<description>" <status> ["<notes>"]
  curate-review-log.sh unresolved <log-md>
  curate-review-log.sh report <log-md>
EOF
  exit 2
}

# ── header ──────────────────────────────────────────────────────────────────
LOG_HEADER='# Curate Review Log

> **Append-only.** Managed by `/curate`. Each row records a finding and
> the user'\''s response on a specific run. Never edit by hand; never
> delete rows. Use `curate-review-log.sh unresolved <log-md>` to query
> items pending re-presentation on the next run.

| Date | Key | Description | Status | Notes |
|------|-----|-------------|--------|-------|'

ensure_log_header() {
  local log="$1"
  if [[ ! -f "$log" ]]; then
    mkdir -p "$(dirname "$log")"
    printf '%s\n' "$LOG_HEADER" > "$log"
    return
  fi
  # File exists — make sure it has the header. If not, prepend.
  if ! grep -q '^# Curate Review Log' "$log"; then
    local tmp; tmp=$(mktemp)
    { printf '%s\n' "$LOG_HEADER"; cat "$log"; } > "$tmp"
    mv "$tmp" "$log"
  fi
}

# Strip an outer pair of `|` then trim each cell of leading/trailing spaces.
# Awk function — used internally.
TRIM_AWK='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
'

# ── migrate ─────────────────────────────────────────────────────────────────
cmd_migrate() {
  local state="${1:-}" log="${2:-}"
  [[ -z "$state" || -z "$log" ]] && { echo "ERROR: migrate requires <state-md> <log-md>" >&2; exit 2; }
  [[ ! -f "$state" ]] && return 0   # nothing to migrate

  # Extract any rows under "## Review Log" with the legacy column shape:
  #   | <date> | <item> | <status> | <notes> |
  # Map to the new five-column shape (Key reuses Item value when no
  # structured key is present in the legacy row — old free-text Items
  # become best-effort keys; nothing depends on perfect uniqueness post-
  # migration since old free-text rows simply won't match new structured
  # findings and become benign history).
  local migrated
  migrated=$(awk "$TRIM_AWK"'
    /^## Review Log/ { in_log = 1; next }
    in_log && /^## /  { in_log = 0 }
    in_log && /^\|/   {
      n = split($0, c, "|")
      # Legacy: | empty | date | item | status | notes | empty (4 cells, 6 fields after split).
      # Filter the header row and the divider row.
      if (n < 5) next
      d = trim(c[2]); item = trim(c[3]); st = trim(c[4]); nt = trim(c[5])
      if (d == "Date" || d == "" || d ~ /^[-]+$/) next
      # Mirror Item into Key column (free-text legacy keys are fine).
      printf("%s|%s|%s|%s|%s\n", d, item, item, st, nt)
    }
  ' "$state")

  if [[ -n "$migrated" ]]; then
    ensure_log_header "$log"
    while IFS='|' read -r d k desc st nt; do
      [[ -z "$d" ]] && continue
      # Append directly here (the append subcommand handles dedup, so use it).
      cmd_append "$log" "$d" "$k" "$desc" "$st" "$nt" >/dev/null
    done <<<"$migrated"
  fi

  # Remove the Review Log section from the state file (also idempotent —
  # if the section is absent we leave the file untouched).
  if grep -q '^## Review Log' "$state"; then
    local tmp; tmp=$(mktemp)
    awk '
      /^## Review Log/ { skip = 1; next }
      skip && /^## /   { skip = 0 }
      !skip { print }
    ' "$state" > "$tmp"
    mv "$tmp" "$state"
  fi
}

# ── append ──────────────────────────────────────────────────────────────────
cmd_append() {
  local log="${1:-}" date="${2:-}" key="${3:-}" desc="${4:-}" status="${5:-}" notes="${6:-}"
  [[ -z "$log" || -z "$date" || -z "$key" || -z "$desc" || -z "$status" ]] && {
    echo "ERROR: append requires <log-md> <date> <key> <description> <status> [notes]" >&2
    exit 2
  }
  ensure_log_header "$log"

  # De-dup: skip if an identical row already exists (compares date|key|status|notes).
  if awk -F'|' "$TRIM_AWK"'
      /^\|/ && !/^\| Date /  && !/^\|[-: ]+\|/ {
        d  = trim($2); k = trim($3); s = trim($5); nt = trim($6)
        if (d == DATE && k == KEY && s == STATUS && nt == NOTES) { found = 1 }
      }
      END { exit (found ? 0 : 1) }
    ' DATE="$date" KEY="$key" STATUS="$status" NOTES="$notes" "$log"; then
    return 0
  fi
  printf "| %s | %s | %s | %s | %s |\n" "$date" "$key" "$desc" "$status" "$notes" >> "$log"
}

# ── unresolved ──────────────────────────────────────────────────────────────
cmd_unresolved() {
  local log="${1:-}"
  [[ -z "$log" ]] && { echo "ERROR: unresolved requires <log-md>" >&2; exit 2; }
  [[ ! -f "$log" ]] && return 0   # no log → nothing unresolved

  # For each key, find the most-recent (last) row in file order. Emit if its
  # status is `deferred` or `suggested`. File order doubles as recency
  # because the log is append-only (later rows have later dates).
  awk -F'|' "$TRIM_AWK"'
    /^\|/ && !/^\| Date /  && !/^\|[-: ]+\|/ {
      d = trim($2); k = trim($3); desc = trim($4); s = trim($5)
      if (k == "" || s == "") next
      latest_status[k] = s
      latest_desc[k]   = desc
      latest_date[k]   = d
    }
    END {
      for (k in latest_status) {
        s = latest_status[k]
        if (s == "deferred" || s == "suggested") {
          print k "|" s "|" latest_desc[k] "|" latest_date[k]
        }
      }
    }
  ' "$log" | sort
}

# ── report ──────────────────────────────────────────────────────────────────
cmd_report() {
  local log="${1:-}"
  [[ -z "$log" ]] && { echo "ERROR: report requires <log-md>" >&2; exit 2; }
  [[ ! -f "$log" ]] && { echo "Curate review log: 0 rows · 0 unresolved · 0 resolved"; return 0; }

  awk -F'|' "$TRIM_AWK"'
    /^\|/ && !/^\| Date /  && !/^\|[-: ]+\|/ {
      total++
      k = trim($3); s = trim($5)
      if (k != "") {
        latest_status[k] = s
      }
    }
    END {
      total = total + 0
      unres = 0; res = 0
      for (k in latest_status) {
        s = latest_status[k]
        if (s == "deferred" || s == "suggested") unres++
        else if (s == "resolved" || s == "dismissed" || s == "explored") res++
      }
      printf("Curate review log: %d rows · %d unresolved · %d resolved\n", total, unres, res)
    }
  ' "$log"
}

# ── dispatch ────────────────────────────────────────────────────────────────
sub="${1:-}"
shift || true
case "$sub" in
  migrate)    cmd_migrate    "$@" ;;
  append)     cmd_append     "$@" ;;
  unresolved) cmd_unresolved "$@" ;;
  report)     cmd_report     "$@" ;;
  ""|-h|--help|help) usage ;;
  *) echo "ERROR: unknown subcommand '$sub'" >&2; usage ;;
esac
