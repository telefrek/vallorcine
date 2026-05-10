#!/usr/bin/env bash
# work-dispatch.sh — track WD sub-agent dispatches so payload loss / cancel
# does not silently corrupt the orchestrator's view of in-flight work.
#
# Background. The /work-start coordinator dispatches each WD's
# implementation as a sub-agent (Agent tool call). The Agent call blocks
# until the child emits its final assistant message — and the coordinator
# parses that message into one of three return shapes (COMPLETE,
# STOPPED_AT_<stage>, ERROR).
#
# Two failure modes break that contract without touching the WD's
# manifest status or the .feature/ working dir:
#
#   1. Tool error: Agent returns "[Tool result missing due to internal
#      error]". The payload is gone. The coordinator has no return-line
#      to parse and no signal of whether the sub-agent ran, partially
#      ran, or never started.
#
#   2. User stop: Agent returns "The user doesn't want to proceed with
#      this tool use. The tool use was rejected." (e.g. user pressed
#      ESC during the dispatch). Sub-agent never started.
#
# In both cases the coordinator's task list / TaskTool entry sits at
# in_progress and recovery requires manual filesystem inspection.
#
# This script writes a small JSON marker per dispatch
# (.work/<group>/_dispatch-<wd-id>.json, gitignored) that the
# coordinator updates as it dispatches and acknowledges. /work-resume
# scans for unacknowledged markers and surfaces them as recovery
# candidates.
#
# Schema (current: schema_version 1):
#   {
#     "schema_version": 1,
#     "wd_id": "WD-02",
#     "group": "auto-index-maintenance",
#     "dispatched_at": "2026-05-09T20:30:00Z",
#     "ack": false,
#     "result": null,
#     "failure_reason": null,
#     "acknowledged_at": null
#   }
#
# Subcommands:
#   begin <group> <wd-id>
#     Write a fresh marker (dispatched_at=NOW, ack=false). Exits 0 even
#     if a marker already exists — the coordinator is the sole writer
#     and a re-dispatch overwrites the previous attempt.
#
#   ack <group> <wd-id> <result-line>
#     Mark the marker as acknowledged. <result-line> is the exact one-
#     line return string the coordinator parsed (COMPLETE, STOPPED_AT_*,
#     ERROR, or whatever the child sent). Used when the dispatch
#     completed cleanly.
#
#   fail <group> <wd-id> <reason>
#     Mark the marker as acknowledged with a failure reason. <reason>
#     is one of: payload-lost | user-stopped | parse-failed | <free-text>.
#     Used when the coordinator decides the dispatch did not yield a
#     parseable result. ack flips to true so the marker stops appearing
#     in stuck-list, but the failure_reason is preserved for /work-resume
#     to surface during recovery.
#
#   status <group> <wd-id>
#     Print the marker's JSON contents to stdout. Exit 0 if marker
#     exists, exit 1 if absent (with no output).
#
#   stuck <group>
#     One line per unacknowledged marker:
#       <wd-id>|<dispatched_at>|<has_result>|<failure_reason>
#     The list is empty (and exit 0) when no markers are unacknowledged.
#
#   clear <group> <wd-id>
#     Delete the marker file. Idempotent — exit 0 even if absent.
#     Called by /work-resume after the user resolves the stuck dispatch.
#
# Atomic writes: every write goes through .tmp.$$ + rename to prevent
# torn reads when /work-resume reads the marker concurrently with a
# dispatcher writing it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# work-lib provides work_find_root + work_require_deps. work-dispatch
# does not mutate the WD frontmatter, so it does NOT need the resolver
# lock — markers are per-WD files and only the coordinator writes them.
source "$SCRIPT_DIR/work-lib.sh"
work_require_deps

usage() {
  cat >&2 <<EOF
Usage:
  work-dispatch.sh begin   <group> <wd-id>
  work-dispatch.sh ack     <group> <wd-id> <result-line>
  work-dispatch.sh fail    <group> <wd-id> <reason>
  work-dispatch.sh status  <group> <wd-id>
  work-dispatch.sh stuck   <group>
  work-dispatch.sh clear   <group> <wd-id>

See the comment at the top of this file for details.
EOF
  exit 2
}

# Strip control bytes that would break JSON. Mirrors json_escape in
# work-resolve.sh — the result-line argument can contain anything the
# sub-agent put on its final line, including stray bytes from a piped
# log capture. Drop 0x00–0x08, 0x0B–0x0C, 0x0E–0x1F before escaping.
json_escape() {
  local s="$1"
  s="${s//$'\x00'/}"
  s="${s//$'\x01'/}"
  s="${s//$'\x02'/}"
  s="${s//$'\x03'/}"
  s="${s//$'\x04'/}"
  s="${s//$'\x05'/}"
  s="${s//$'\x06'/}"
  s="${s//$'\x07'/}"
  s="${s//$'\x08'/}"
  s="${s//$'\x0B'/}"
  s="${s//$'\x0C'/}"
  s="${s//$'\x0E'/}"
  s="${s//$'\x0F'/}"
  s="${s//$'\x10'/}"
  s="${s//$'\x11'/}"
  s="${s//$'\x12'/}"
  s="${s//$'\x13'/}"
  s="${s//$'\x14'/}"
  s="${s//$'\x15'/}"
  s="${s//$'\x16'/}"
  s="${s//$'\x17'/}"
  s="${s//$'\x18'/}"
  s="${s//$'\x19'/}"
  s="${s//$'\x1A'/}"
  s="${s//$'\x1B'/}"
  s="${s//$'\x1C'/}"
  s="${s//$'\x1D'/}"
  s="${s//$'\x1E'/}"
  s="${s//$'\x1F'/}"
  s="${s//\\/\\\\}"   # backslash first
  s="${s//\"/\\\"}"   # double-quote
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

marker_path() {
  local work_root="$1" group="$2" wd_id="$3"
  printf '%s/%s/_dispatch-%s.json' "$work_root" "$group" "$wd_id"
}

require_group_dir() {
  local work_root="$1" group="$2"
  local group_dir="$work_root/$group"
  if [[ ! -d "$group_dir" ]]; then
    echo "ERROR: work group not found: $group ($group_dir)" >&2
    exit 2
  fi
  printf '%s' "$group_dir"
}

# Atomic write helper. Writes to <path>.tmp.<pid> then renames.
write_marker() {
  local path="$1" content="$2"
  local tmp="${path}.tmp.$$"
  printf '%s' "$content" > "$tmp"
  mv "$tmp" "$path"
}

# Read a top-level scalar string field from a flat JSON object. Returns
# empty when the field is absent, the literal string null, or the JSON
# is malformed. Mirrors the grep-based reader pattern used elsewhere in
# scripts/ so we do not add a jq dependency.
read_field() {
  local path="$1" field="$2"
  [[ -f "$path" ]] || return 0
  grep -oE "\"$field\":[[:space:]]*\"[^\"]*\"" "$path" 2>/dev/null \
    | head -1 \
    | sed -E "s/^\"$field\":[[:space:]]*\"([^\"]*)\"$/\1/" \
    | head -1 || true
}

# Read a top-level boolean (true|false) field. Empty string when
# absent or not a boolean.
read_bool_field() {
  local path="$1" field="$2"
  [[ -f "$path" ]] || return 0
  grep -oE "\"$field\":[[:space:]]*(true|false)" "$path" 2>/dev/null \
    | head -1 \
    | sed -E "s/^\"$field\":[[:space:]]*(true|false)$/\1/" \
    | head -1 || true
}

cmd_begin() {
  local group="$1" wd_id="$2"
  local work_root group_dir marker now content
  work_root="$(work_find_root)" || exit 2
  group_dir="$(require_group_dir "$work_root" "$group")"
  marker="$(marker_path "$work_root" "$group" "$wd_id")"
  now="$(now_utc)"
  content=$(cat <<EOF
{"schema_version":1,"wd_id":"$(json_escape "$wd_id")","group":"$(json_escape "$group")","dispatched_at":"$now","ack":false,"result":null,"failure_reason":null,"acknowledged_at":null}
EOF
)
  write_marker "$marker" "$content"
  echo "[dispatch] begin $group/$wd_id at $now"
}

cmd_ack() {
  local group="$1" wd_id="$2" result_line="${3:-}"
  local work_root marker now dispatched_at content
  work_root="$(work_find_root)" || exit 2
  require_group_dir "$work_root" "$group" >/dev/null
  marker="$(marker_path "$work_root" "$group" "$wd_id")"

  if [[ ! -f "$marker" ]]; then
    # No marker — the coordinator never called begin (older kit, or a
    # manual dispatch). Create one in the acknowledged state so we have
    # a record. The dispatched_at falls back to now since we lost it.
    now="$(now_utc)"
    dispatched_at="$now"
  else
    dispatched_at="$(read_field "$marker" "dispatched_at")"
    [[ -z "$dispatched_at" ]] && dispatched_at="$(now_utc)"
    now="$(now_utc)"
  fi

  content=$(cat <<EOF
{"schema_version":1,"wd_id":"$(json_escape "$wd_id")","group":"$(json_escape "$group")","dispatched_at":"$dispatched_at","ack":true,"result":"$(json_escape "$result_line")","failure_reason":null,"acknowledged_at":"$now"}
EOF
)
  write_marker "$marker" "$content"
  echo "[dispatch] ack $group/$wd_id"
}

cmd_fail() {
  local group="$1" wd_id="$2" reason="${3:-unspecified}"
  local work_root marker now dispatched_at content
  work_root="$(work_find_root)" || exit 2
  require_group_dir "$work_root" "$group" >/dev/null
  marker="$(marker_path "$work_root" "$group" "$wd_id")"

  if [[ ! -f "$marker" ]]; then
    dispatched_at="$(now_utc)"
    now="$dispatched_at"
  else
    dispatched_at="$(read_field "$marker" "dispatched_at")"
    [[ -z "$dispatched_at" ]] && dispatched_at="$(now_utc)"
    now="$(now_utc)"
  fi

  content=$(cat <<EOF
{"schema_version":1,"wd_id":"$(json_escape "$wd_id")","group":"$(json_escape "$group")","dispatched_at":"$dispatched_at","ack":true,"result":null,"failure_reason":"$(json_escape "$reason")","acknowledged_at":"$now"}
EOF
)
  write_marker "$marker" "$content"
  echo "[dispatch] fail $group/$wd_id ($reason)"
}

cmd_status() {
  local group="$1" wd_id="$2"
  local work_root marker
  work_root="$(work_find_root)" || exit 2
  require_group_dir "$work_root" "$group" >/dev/null
  marker="$(marker_path "$work_root" "$group" "$wd_id")"
  if [[ ! -f "$marker" ]]; then
    exit 1
  fi
  cat "$marker"
}

cmd_stuck() {
  local group="$1"
  local work_root group_dir
  work_root="$(work_find_root)" || exit 2
  group_dir="$(require_group_dir "$work_root" "$group")"

  shopt -s nullglob
  local marker
  for marker in "$group_dir"/_dispatch-*.json; do
    local ack wd_id dispatched_at result failure has_result
    ack="$(read_bool_field "$marker" "ack")"
    if [[ "$ack" != "true" ]]; then
      wd_id="$(read_field "$marker" "wd_id")"
      dispatched_at="$(read_field "$marker" "dispatched_at")"
      result="$(read_field "$marker" "result")"
      failure="$(read_field "$marker" "failure_reason")"
      if [[ -n "$result" ]]; then
        has_result="true"
      else
        has_result="false"
      fi
      printf '%s|%s|%s|%s\n' "$wd_id" "$dispatched_at" "$has_result" "$failure"
    fi
  done
  shopt -u nullglob
}

cmd_clear() {
  local group="$1" wd_id="$2"
  local work_root marker
  work_root="$(work_find_root)" || exit 2
  require_group_dir "$work_root" "$group" >/dev/null
  marker="$(marker_path "$work_root" "$group" "$wd_id")"
  if [[ -f "$marker" ]]; then
    rm -f "$marker"
    echo "[dispatch] cleared $group/$wd_id"
  fi
  exit 0
}

[[ $# -ge 1 ]] || usage

case "$1" in
  begin)
    [[ $# -eq 3 ]] || usage
    cmd_begin "$2" "$3" ;;
  ack)
    [[ $# -ge 3 ]] || usage
    cmd_ack "$2" "$3" "${4:-}" ;;
  fail)
    [[ $# -ge 3 ]] || usage
    cmd_fail "$2" "$3" "${4:-unspecified}" ;;
  status)
    [[ $# -eq 3 ]] || usage
    cmd_status "$2" "$3" ;;
  stuck)
    [[ $# -eq 2 ]] || usage
    cmd_stuck "$2" ;;
  clear)
    [[ $# -eq 3 ]] || usage
    cmd_clear "$2" "$3" ;;
  -h|--help|help)
    usage ;;
  *)
    echo "ERROR: unknown subcommand: $1" >&2
    usage ;;
esac
