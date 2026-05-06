#!/usr/bin/env bash
# spec-backfill-log.sh — append-only progress log for /spec-backfill
#
# Stores per-(spec, R-id) backfill outcomes so re-running /spec-backfill on
# the same corpus skips already-decided requirements (annotated, waived, or
# explicitly skipped). The log is append-only — callers MUST NOT rewrite
# rows; later rows for the same key supersede earlier ones for the
# `latest-status` query semantics.
#
# Default location: .spec/backfill-log.md (corpus-wide). Per-spec scoping is
# achieved by the row's `spec` column, not by separate files.
#
# Subcommands:
#   init <log-md>
#       Create <log-md> with a header table if it does not exist. Idempotent.
#
#   append <log-md> <date> <spec-id> <r-id> <status> [<file:line>] [<notes>]
#       Append a row. Status values:
#         annotated — `@spec` annotation applied at <file:line>.
#         skipped   — user chose to skip this R-id (will resurface on rerun).
#         waived    — user marked the requirement intentionally uncovered.
#       Idempotent within a (date, spec, r-id, status, location, notes) tuple.
#
#   has-decision <log-md> <spec-id> <r-id>
#       Exit 0 if the latest row for (spec, r-id) is `annotated` or `waived`
#       (a terminal decision); exit 1 otherwise. Used by /spec-backfill to
#       skip already-decided R-ids on resume. `skipped` is NOT terminal —
#       skipped R-ids resurface on rerun by design.
#
#   list-decisions <log-md> <spec-id>
#       Emit `<r-id>|<latest-status>|<location>|<date>` for every R-id of
#       the given spec that has at least one log row. Most-recent row wins.
#
#   report <log-md>
#       Three-line summary: total rows / annotated / skipped+waived.

set -euo pipefail

usage() {
  sed -n '2,/^set -e/p' "$0" | sed 's/^# *//;s/^#$//' | head -n -1
  exit 2
}

cmd_init() {
  local log="${1:-}"
  [[ -z "$log" ]] && { echo "ERROR: init requires <log-md>" >&2; exit 2; }
  if [[ -f "$log" ]]; then
    echo "[backfill-log] init: $log already exists — no-op" >&2
    return 0
  fi
  cat > "$log" <<'HEADER'
# Spec Backfill Log

> **Append-only. Managed by `scripts/spec-backfill-log.sh`.**
> Records per-requirement backfill outcomes for `/spec-backfill`. Later
> rows for the same `(spec, R-id)` supersede earlier ones — never edit
> or delete prior rows.

| Date | Spec | R-id | Status | Location | Notes |
|------|------|------|--------|----------|-------|
HEADER
  echo "[backfill-log] init: created $log" >&2
}

cmd_append() {
  local log="${1:-}" date="${2:-}" spec="${3:-}" rid="${4:-}" status="${5:-}"
  local location="${6:-}" notes="${7:-}"
  [[ -z "$log" || -z "$date" || -z "$spec" || -z "$rid" || -z "$status" ]] && {
    echo "ERROR: append requires <log-md> <date> <spec-id> <r-id> <status> [location] [notes]" >&2
    exit 2
  }
  case "$status" in
    annotated|skipped|waived) ;;
    *) echo "ERROR: status must be one of: annotated, skipped, waived (got '$status')" >&2; exit 2 ;;
  esac
  [[ -f "$log" ]] || cmd_init "$log"

  # Sanitize pipes in user-supplied fields (notes especially).
  local s_loc s_notes
  s_loc=$(echo "$location" | tr '|' '/' )
  s_notes=$(echo "$notes" | tr '|' '/' )

  local new_row
  new_row="| $date | $spec | $rid | $status | $s_loc | $s_notes |"

  # Idempotence: skip if the exact row already exists (rare in practice).
  if grep -Fxq "$new_row" "$log" 2>/dev/null; then
    echo "[backfill-log] append: row already present — no-op" >&2
    return 0
  fi
  echo "$new_row" >> "$log"
  echo "[backfill-log] append: $spec.$rid → $status" >&2
}

# Emit the latest status for (spec, rid) on stdout. Empty if no rows.
_latest_status() {
  local log="$1" spec="$2" rid="$3"
  awk -F'|' -v s="$spec" -v r="$rid" '
    {
      gsub(/^ +| +$/, "", $3); gsub(/^ +| +$/, "", $4); gsub(/^ +| +$/, "", $5)
      if ($3 == s && $4 == r) last = $5
    }
    END { print last }
  ' "$log"
}

cmd_has_decision() {
  local log="${1:-}" spec="${2:-}" rid="${3:-}"
  [[ -z "$log" || -z "$spec" || -z "$rid" ]] && {
    echo "ERROR: has-decision requires <log-md> <spec-id> <r-id>" >&2
    exit 2
  }
  [[ ! -f "$log" ]] && exit 1
  local status
  status=$(_latest_status "$log" "$spec" "$rid")
  case "$status" in
    annotated|waived) exit 0 ;;
    *) exit 1 ;;
  esac
}

cmd_list_decisions() {
  local log="${1:-}" spec="${2:-}"
  [[ -z "$log" || -z "$spec" ]] && {
    echo "ERROR: list-decisions requires <log-md> <spec-id>" >&2
    exit 2
  }
  [[ ! -f "$log" ]] && return 0
  awk -F'|' -v s="$spec" '
    {
      gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $3); gsub(/^ +| +$/, "", $4)
      gsub(/^ +| +$/, "", $5); gsub(/^ +| +$/, "", $6)
      if ($3 == s && $4 ~ /^R[0-9]/) {
        # Last write wins per (spec, rid)
        rid_status[$4] = $5
        rid_loc[$4]    = $6
        rid_date[$4]   = $2
      }
    }
    END {
      for (r in rid_status) {
        print r "|" rid_status[r] "|" rid_loc[r] "|" rid_date[r]
      }
    }
  ' "$log" | sort
}

cmd_report() {
  local log="${1:-}"
  [[ -z "$log" ]] && { echo "ERROR: report requires <log-md>" >&2; exit 2; }
  [[ ! -f "$log" ]] && {
    echo "no log file at $log"
    return 0
  }
  local total ann skp wav
  total=$(grep -cE '^\| [0-9]{4}-[0-9]{2}-[0-9]{2} \|' "$log" 2>/dev/null || echo 0)
  ann=$(awk -F'|' '$5 ~ /annotated/ {n++} END {print n+0}' "$log")
  skp=$(awk -F'|' '$5 ~ /skipped/   {n++} END {print n+0}' "$log")
  wav=$(awk -F'|' '$5 ~ /waived/    {n++} END {print n+0}' "$log")
  echo "rows: $total  annotated: $ann  skipped: $skp  waived: $wav"
}

CMD="${1:-}"
shift || true
case "$CMD" in
  init)            cmd_init "$@" ;;
  append)          cmd_append "$@" ;;
  has-decision)    cmd_has_decision "$@" ;;
  list-decisions)  cmd_list_decisions "$@" ;;
  report)          cmd_report "$@" ;;
  ""|-h|--help)    usage ;;
  *) echo "ERROR: unknown subcommand '$CMD'" >&2; usage ;;
esac
