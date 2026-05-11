#!/usr/bin/env bash
# dispatch-marker.sh — generic per-dispatch marker tracker.
#
# Background. Several vallorcine skills dispatch subagents via the Agent
# tool to keep coordinator context bounded. The Agent call blocks until
# the child emits its final assistant message, then the coordinator
# parses that message into a structured return. Two failure modes break
# that contract without touching downstream state:
#
#   1. Tool error: Agent returns "[Tool result missing due to internal
#      error]". The payload is gone. The coordinator has no return-line
#      to parse and no signal of whether the sub-agent ran, partially
#      ran, or never started.
#
#   2. User stop: Agent returns "The user doesn't want to proceed with
#      this tool use. ..." (e.g. user pressed ESC during the dispatch).
#      Sub-agent never started.
#
# In both cases the coordinator's view sits in an undefined state and
# recovery requires manual filesystem inspection.
#
# This is the generic counterpart to scripts/work-dispatch.sh — the
# work-layer version operates inside `.work/<group>/` and is coupled
# to the work-lib helpers. The generic version takes a marker root
# directory as its first argument so any skill (`/curate`,
# `/spec-backfill`, future skills) can drop markers into its own state
# directory without duplicating this script.
#
# Schema (current: schema_version 1):
#   {
#     "schema_version": 1,
#     "id": "<dispatch-id>",
#     "dispatched_at": "2026-05-10T18:30:00Z",
#     "ack": false,
#     "result": null,
#     "failure_reason": null,
#     "acknowledged_at": null
#   }
#
# Subcommands:
#   begin   <root> <id>
#   ack     <root> <id> <result-line>
#   fail    <root> <id> <reason>
#   status  <root> <id>          (exit 1 + no output if marker absent)
#   stuck   <root>               (one line per unacked marker)
#   clear   <root> <id>          (idempotent — exit 0 even if absent)
#
# <root> is the absolute or repo-relative directory that holds the
# `_dispatch-<id>.json` files. The directory is created on `begin` if
# missing. Caller is responsible for choosing a stable location
# (.curate/_dispatches/, .spec/_backfill-dispatches/, etc.).
#
# Atomic writes: every write goes through .tmp.$$ + rename to prevent
# torn reads when concurrent readers (e.g. recovery scans) read the
# marker while a dispatcher writes it.

set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage:
  dispatch-marker.sh begin   <root> <id>
  dispatch-marker.sh ack     <root> <id> <result-line>
  dispatch-marker.sh fail    <root> <id> <reason>
  dispatch-marker.sh status  <root> <id>
  dispatch-marker.sh stuck   <root>
  dispatch-marker.sh clear   <root> <id>

See the comment at the top of this file for details.
EOF
  exit 2
}

# Strip control bytes that would break JSON. Mirrors work-dispatch.sh
# and work-resolve.sh — input strings may contain anything from a
# subagent's final line, including stray bytes from log capture.
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

# Slugify an arbitrary id into a filesystem-safe filename token. Replaces
# anything other than [A-Za-z0-9._-] with `_`. Long IDs (>120 chars) get
# truncated; the original ID is preserved in-marker via the `id` field.
slug_id() {
  local raw="$1"
  local slug
  slug=$(printf '%s' "$raw" | tr -c 'A-Za-z0-9._-' '_')
  if (( ${#slug} > 120 )); then
    slug="${slug:0:120}"
  fi
  printf '%s' "$slug"
}

marker_path() {
  local root="$1" id="$2"
  printf '%s/_dispatch-%s.json' "$root" "$(slug_id "$id")"
}

ensure_root() {
  local root="$1"
  if [[ ! -d "$root" ]]; then
    mkdir -p "$root" || {
      echo "ERROR: cannot create marker root: $root" >&2
      exit 2
    }
  fi
}

write_marker() {
  local path="$1" content="$2"
  local tmp="${path}.tmp.$$"
  printf '%s' "$content" > "$tmp"
  mv "$tmp" "$path"
}

read_field() {
  local path="$1" field="$2"
  [[ -f "$path" ]] || return 0
  grep -oE "\"$field\":[[:space:]]*\"[^\"]*\"" "$path" 2>/dev/null \
    | head -1 \
    | sed -E "s/^\"$field\":[[:space:]]*\"([^\"]*)\"$/\1/" \
    | head -1 || true
}

read_bool_field() {
  local path="$1" field="$2"
  [[ -f "$path" ]] || return 0
  grep -oE "\"$field\":[[:space:]]*(true|false)" "$path" 2>/dev/null \
    | head -1 \
    | sed -E "s/^\"$field\":[[:space:]]*(true|false)$/\1/" \
    | head -1 || true
}

cmd_begin() {
  local root="$1" id="$2"
  ensure_root "$root"
  local marker now content
  marker="$(marker_path "$root" "$id")"
  now="$(now_utc)"
  content=$(cat <<EOF
{"schema_version":1,"id":"$(json_escape "$id")","dispatched_at":"$now","ack":false,"result":null,"failure_reason":null,"acknowledged_at":null}
EOF
)
  write_marker "$marker" "$content"
  echo "[dispatch] begin $id at $now"
}

cmd_ack() {
  local root="$1" id="$2" result_line="${3:-}"
  ensure_root "$root"
  local marker now dispatched_at content
  marker="$(marker_path "$root" "$id")"

  if [[ ! -f "$marker" ]]; then
    now="$(now_utc)"
    dispatched_at="$now"
  else
    dispatched_at="$(read_field "$marker" "dispatched_at")"
    [[ -z "$dispatched_at" ]] && dispatched_at="$(now_utc)"
    now="$(now_utc)"
  fi

  content=$(cat <<EOF
{"schema_version":1,"id":"$(json_escape "$id")","dispatched_at":"$dispatched_at","ack":true,"result":"$(json_escape "$result_line")","failure_reason":null,"acknowledged_at":"$now"}
EOF
)
  write_marker "$marker" "$content"
  echo "[dispatch] ack $id"
}

cmd_fail() {
  local root="$1" id="$2" reason="${3:-unspecified}"
  ensure_root "$root"
  local marker now dispatched_at content
  marker="$(marker_path "$root" "$id")"

  if [[ ! -f "$marker" ]]; then
    dispatched_at="$(now_utc)"
    now="$dispatched_at"
  else
    dispatched_at="$(read_field "$marker" "dispatched_at")"
    [[ -z "$dispatched_at" ]] && dispatched_at="$(now_utc)"
    now="$(now_utc)"
  fi

  content=$(cat <<EOF
{"schema_version":1,"id":"$(json_escape "$id")","dispatched_at":"$dispatched_at","ack":true,"result":null,"failure_reason":"$(json_escape "$reason")","acknowledged_at":"$now"}
EOF
)
  write_marker "$marker" "$content"
  echo "[dispatch] fail $id ($reason)"
}

cmd_status() {
  local root="$1" id="$2"
  local marker
  marker="$(marker_path "$root" "$id")"
  if [[ ! -f "$marker" ]]; then
    exit 1
  fi
  cat "$marker"
}

cmd_stuck() {
  local root="$1"
  [[ -d "$root" ]] || return 0

  shopt -s nullglob
  local marker
  for marker in "$root"/_dispatch-*.json; do
    local ack id dispatched_at result failure has_result
    ack="$(read_bool_field "$marker" "ack")"
    if [[ "$ack" != "true" ]]; then
      id="$(read_field "$marker" "id")"
      dispatched_at="$(read_field "$marker" "dispatched_at")"
      result="$(read_field "$marker" "result")"
      failure="$(read_field "$marker" "failure_reason")"
      if [[ -n "$result" ]]; then
        has_result="true"
      else
        has_result="false"
      fi
      printf '%s|%s|%s|%s\n' "$id" "$dispatched_at" "$has_result" "$failure"
    fi
  done
  shopt -u nullglob
}

cmd_clear() {
  local root="$1" id="$2"
  local marker
  marker="$(marker_path "$root" "$id")"
  if [[ -f "$marker" ]]; then
    rm -f "$marker"
    echo "[dispatch] cleared $id"
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
