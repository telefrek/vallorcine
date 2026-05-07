#!/usr/bin/env bash
# work-index.sh — maintain the .work/CLAUDE.md Active Work Groups table.
#
# The Active Work Groups table at the corpus root is a per-group rollup
# of WD counts. Prior to this script, every skill that changed group
# state (group creation, decomposition, feature completion) hand-edited
# the row via Edit. That pattern was fragile (any drift in column shape
# broke the table) and stale (the SKILL doc falsely claimed work-resolve
# auto-synced it; nothing did). This script is the authoritative writer.
#
# Subcommands:
#   add <group-slug> <goal>
#       Append a new row for a freshly-created group. Idempotent — if
#       a row already exists for the slug, fall through to update.
#       Also adds a "Recently Added" log row.
#
#   update <group-slug>
#       Recompute the row for one group from the actual WD files in
#       `.work/<slug>/`. Counts:
#         WDs       = number of WD-*.md files
#         Ready     = WDs whose status is READY
#         Complete  = WDs whose status is COMPLETE
#       Sets Last Updated to today's date.
#
#   update-all
#       Recompute every row in the Active Work Groups table from the
#       filesystem. Use after a bulk operation or to repair drift.
#
#   remove <group-slug>
#       Drop the row for a group (e.g. fully archived).
#
# Output: edits .work/CLAUDE.md in place; emits a one-line diagnostic
# on stderr per write so callers can confirm the change happened.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=work-lib.sh disable=SC1091
source "$SCRIPT_DIR/work-lib.sh"

usage() {
  cat <<'EOF' >&2
Usage:
  work-index.sh add    <group-slug> <goal>
  work-index.sh update <group-slug>
  work-index.sh update-all
  work-index.sh remove <group-slug>
EOF
  exit 2
}

# Locate .work/ root and the index file. Walk up from CWD.
_find_work_index() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.work/CLAUDE.md" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "ERROR: .work/CLAUDE.md not found (run /work to bootstrap)" >&2
  return 1
}

# Compute Total / Ready / Complete for a group by reading WD files
# directly. Status is the WD's own declared status; READY for the index
# is the literal status-rank READY (DRAFT WDs whose deps are met would
# resolve to READY at runtime via work-resolve.sh, but the index only
# reflects authored status — work-resolve is the dynamic readiness view).
_count_group() {
  local group_dir="$1"
  local total=0 ready=0 complete=0 wd_status
  while IFS= read -r wd_file; do
    [[ -z "$wd_file" ]] && continue
    total=$((total + 1))
    wd_status="$(work_fm "$wd_file" "status")"
    case "$wd_status" in
      READY)    ready=$((ready + 1)) ;;
      COMPLETE) complete=$((complete + 1)) ;;
    esac
  done < <(work_list_wds "$group_dir")
  echo "$total|$ready|$complete"
}

# Atomic in-place edit: write to .tmp then rename. Prevents readers
# from seeing a half-written table.
_atomic_replace() {
  local target="$1" tmp="$2"
  mv "$tmp" "$target"
}

# Strip surrounding pipes/whitespace from a Markdown table cell.
_trim() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  echo "$v"
}

cmd_update() {
  local slug="${1:-}"
  [[ -z "$slug" ]] && { echo "ERROR: update requires <group-slug>" >&2; exit 2; }

  local root index group_dir
  root="$(_find_work_index)" || exit 1
  index="$root/.work/CLAUDE.md"
  group_dir="$root/.work/$slug"

  if [[ ! -d "$group_dir" ]]; then
    echo "ERROR: group not found: $group_dir" >&2
    exit 1
  fi

  local counts total ready complete
  counts="$(_count_group "$group_dir")"
  IFS='|' read -r total ready complete <<<"$counts"

  # Match rows by literal prefix `| <slug> |`. Pipe is `\|` in grep ERE
  # but plain `|` is alternation in awk regex, so we use awk's index()
  # for literal substring match below.
  local row_prefix="| $slug |"
  if ! grep -qF "$row_prefix" "$index"; then
    echo "[work-index] update: no row for '$slug' — use 'add' first" >&2
    exit 1
  fi

  # Read the existing row's Path / Goal / counts / date so we can decide
  # whether anything actually needs to change. Idempotence matters here:
  # callers (feature-finalize, feature-complete) re-run update routinely,
  # and bumping Last Updated on a no-op leaves a spurious tracked change
  # that downstream skills then have to commit + push separately.
  local existing
  existing="$(grep -F "$row_prefix" "$index" | head -1)"
  local ex_path ex_goal ex_total ex_ready ex_complete ex_date
  IFS='|' read -r _ _ ex_path ex_goal ex_total ex_ready ex_complete ex_date _ <<<"$existing"
  local path goal date_col
  path="$(_trim "$ex_path")"
  goal="$(_trim "$ex_goal")"
  ex_total="$(_trim "$ex_total")"
  ex_ready="$(_trim "$ex_ready")"
  ex_complete="$(_trim "$ex_complete")"
  ex_date="$(_trim "$ex_date")"

  # Keep the existing Last Updated unless the counts actually moved.
  # That way "Last Updated" reflects the last meaningful change, not the
  # last time the script was invoked.
  if [[ "$ex_total" == "$total" && "$ex_ready" == "$ready" && "$ex_complete" == "$complete" ]]; then
    date_col="$ex_date"
  else
    date_col="$(date +%F)"
  fi

  local new_row
  new_row="| $slug | $path | $goal | $total | $ready | $complete | $date_col |"

  if [[ "$existing" == "$new_row" ]]; then
    echo "[work-index] update: $slug already current ($total/$ready/$complete) — no-op" >&2
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  awk -v prefix="$row_prefix" -v new_row="$new_row" '
    index($0, prefix) == 1 { print new_row; next }
    { print }
  ' "$index" > "$tmp"
  _atomic_replace "$index" "$tmp"
  echo "[work-index] update: $slug → $total WDs / $ready ready / $complete complete" >&2
}

cmd_add() {
  local slug="${1:-}" goal="${2:-}"
  [[ -z "$slug" || -z "$goal" ]] && {
    echo "ERROR: add requires <group-slug> <goal>" >&2; exit 2
  }

  local root index
  root="$(_find_work_index)" || exit 1
  index="$root/.work/CLAUDE.md"

  # Sanitize pipe characters in goal so they cannot split the table column.
  local safe_goal
  safe_goal="$(echo "$goal" | tr '|' '/')"

  local row_prefix="| $slug |"
  if grep -qF "$row_prefix" "$index"; then
    echo "[work-index] add: row exists for '$slug' — running update instead" >&2
    cmd_update "$slug"
    return 0
  fi

  local today
  today="$(date +%F)"
  local new_row="| $slug | .work/$slug/ | $safe_goal | 0 | 0 | 0 | $today |"

  # Insert immediately after the table header separator (`|---|...|`)
  # so new rows append to the top of the row list. We rely on awk's
  # match() against a leading `|---` substring rather than a regex
  # involving `|`, since `|` is alternation in awk regex.
  local tmp
  tmp="$(mktemp)"
  awk -v active_new_row="$new_row" '
    BEGIN { phase = "" }
    /^## Active Work Groups *$/ { phase = "active"; print; next }
    /^## Recently Added/        { phase = "recent"; print; next }
    phase == "active" && substr($0, 1, 4) == "|---" {
      print
      print active_new_row
      phase = ""
      next
    }
    { print }
  ' "$index" > "$tmp"
  _atomic_replace "$index" "$tmp"

  # Append a "Recently Added" log row below the corresponding header.
  local recent_row="| $today | $slug | — | — | active |"
  local tmp2
  tmp2="$(mktemp)"
  awk -v recent_new_row="$recent_row" '
    BEGIN { phase = "" }
    /^## Recently Added/ { phase = "recent"; print; next }
    /^## /               { phase = ""; print; next }
    phase == "recent" && substr($0, 1, 4) == "|---" {
      print
      print recent_new_row
      phase = ""
      next
    }
    { print }
  ' "$index" > "$tmp2"
  _atomic_replace "$index" "$tmp2"
  echo "[work-index] add: appended '$slug' to Active Work Groups" >&2
}

cmd_remove() {
  local slug="${1:-}"
  [[ -z "$slug" ]] && { echo "ERROR: remove requires <group-slug>" >&2; exit 2; }

  local root index
  root="$(_find_work_index)" || exit 1
  index="$root/.work/CLAUDE.md"

  local row_prefix="| $slug |"
  if ! grep -qF "$row_prefix" "$index"; then
    echo "[work-index] remove: no row for '$slug' — no-op" >&2
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  grep -vF "$row_prefix" "$index" > "$tmp"
  _atomic_replace "$index" "$tmp"
  echo "[work-index] remove: dropped '$slug'" >&2
}

cmd_update_all() {
  local root index
  root="$(_find_work_index)" || exit 1
  index="$root/.work/CLAUDE.md"

  # Iterate every group directory under .work/ that has a manifest.md
  # or any WD file. Skip _archive and other reserved directories.
  while IFS= read -r group_dir; do
    [[ -z "$group_dir" ]] && continue
    local slug
    slug="$(basename "$group_dir")"
    cmd_update "$slug" || true
  done < <(find "$root/.work" -mindepth 1 -maxdepth 1 -type d \
             ! -name '_archive' ! -name '_refs' 2>/dev/null | sort)
}

CMD="${1:-}"
shift || true
case "$CMD" in
  add)        cmd_add "$@" ;;
  update)     cmd_update "$@" ;;
  update-all) cmd_update_all "$@" ;;
  remove)     cmd_remove "$@" ;;
  ""|-h|--help) usage ;;
  *) echo "ERROR: unknown subcommand '$CMD'" >&2; usage ;;
esac
