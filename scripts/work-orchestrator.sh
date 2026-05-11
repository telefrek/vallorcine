#!/usr/bin/env bash
# work-orchestrator.sh — persistent state machine for dynamic-DAG /work-run.
#
# Background. /work-start's `--parallel` mode dispatches the current ready
# set of SPECIFIED WDs as concurrent sub-agents, waits for ALL to return,
# aggregates, and exits. It does not watch for completions and dispatch
# newly-unblocked WDs as a wave-of-waves. For a 10+ WD work group with
# inter-WD dependencies, this leaves wall-clock on the table — finished WDs
# sit idle while the orchestrator waits for the slowest in-flight sibling.
#
# This script provides the persistent state machine that a future /work-run
# skill (PR C) drives to do dynamic dispatch: enumerate ready, dispatch up
# to a cap, wait for any one to return, mark it done, re-resolve readiness,
# dispatch any newly-ready WDs, repeat until terminal.
#
# Storage layout (one directory per work group, in .work/<group>/):
#
#   .work/<group>/.orchestrator/
#     state.json          top-level config + paused flag + epoch
#     queue.txt           one WD-id per line, dispatched FIFO
#     in-flight/<wd>.json per-WD record: dispatched_at, feature_slug
#     completed/<wd>.json per-WD record: status, summary_line, finished_at
#     blocked/<wd>.json   per-WD record: reason, escalation_path, blocked_at
#
# Each subset is a separate directory so moves between sets are atomic mv
# operations (POSIX rename within the same filesystem). state.json and
# queue.txt mutations use tmp + rename. No jq dependency — every state
# file is small, flat JSON or plain text the script writes from scratch.
#
# Subcommands:
#   init     <group> [--cap N]                  initial state from work-resolve
#   status   <group>                            human-readable state dump
#   dump     <group> [--section <sub>]          raw state (for tests/integrations)
#   ready    <group>                            print WD-ids to dispatch next
#   dispatch <group> <wd-id> <feature-slug>     queue -> in-flight
#   complete <group> <wd-id> <status> <line>    in-flight -> completed
#                                               + re-resolve readiness
#   block    <group> <wd-id> <reason> <esc>     in-flight -> blocked
#                                               (also sets paused=true)
#   unblock  <group> <wd-id>                    blocked -> queue
#   resume   <group>                            clear paused flag
#   hung     <group> [--threshold-seconds N]    print in-flight WDs whose
#                                               status.md hasn't transitioned
#                                               in N seconds (default 1800)
#   resolve  <group>                            force re-resolve from
#                                               work-resolve.sh; add
#                                               newly-SPECIFIED WDs to queue
#   clear    <group>                            remove .orchestrator/
#
# All writes are atomic. Concurrent readers see either the old or new
# state, never a torn read.
#
# Exit codes:
#   0   success
#   1   state error (missing dir, malformed state)
#   2   usage error
#   3   conflict (e.g., WD not in expected set)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./work-lib.sh
source "$SCRIPT_DIR/work-lib.sh"

work_require_deps

usage() {
  cat >&2 <<EOF
Usage:
  work-orchestrator.sh init     <group> [--cap N]
  work-orchestrator.sh status   <group>
  work-orchestrator.sh dump     <group> [--section state|queue|in-flight|completed|blocked]
  work-orchestrator.sh ready    <group>
  work-orchestrator.sh dispatch <group> <wd-id> <feature-slug>
  work-orchestrator.sh complete <group> <wd-id> <status> <summary-line>
  work-orchestrator.sh block    <group> <wd-id> <reason> <escalation-path>
  work-orchestrator.sh unblock  <group> <wd-id>
  work-orchestrator.sh resume   <group>
  work-orchestrator.sh hung     <group> [--threshold-seconds N]
  work-orchestrator.sh resolve  <group>
  work-orchestrator.sh clear    <group>

See the comment at the top of this file for details.
EOF
  exit 2
}

# ── JSON string escape (same approach as dispatch-marker.sh) ─────────────────
# Strip ASCII control bytes that break JSON, then escape backslash, quote,
# tab, CR, LF. The escape sequence order matters: backslash first so we don't
# double-escape the escapes we add below.
json_escape() {
  local s="${1-}"
  s=$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Reject WD-ids that would corrupt queue.txt (newlines) or escape the
# per-set directory (slashes / dot-dot / etc.). The orchestrator trusts
# its caller (the future /work-run skill) to pass canonical IDs, but
# defensive validation here protects against path injection if a malicious
# WD frontmatter gets through work-resolve.
validate_wd_id() {
  local wd_id="$1"
  if [[ ! "$wd_id" =~ ^WD-[0-9]+[a-z]?$ ]]; then
    echo "ERROR: invalid WD-id: '$wd_id' (must match ^WD-[0-9]+[a-z]?\$)" >&2
    exit 2
  fi
}

# Concurrency note: this script assumes a single driver (one /work-run
# skill invocation at a time). State mutations are atomic per-command via
# tmp+rename, but two concurrent invocations could lose updates (e.g.,
# both read epoch=5, both write epoch=6). The future /work-run skill
# should detect contention via the orchestrator-state directory's existence
# rather than running two sessions against the same group.

# ── State-directory locator ─────────────────────────────────────────────────

orch_dir() {
  local group="$1"
  local work_root
  work_root=$(work_find_root)
  echo "$work_root/$group/.orchestrator"
}

require_init() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "ERROR: orchestrator not initialized for this group ($dir does not exist)" >&2
    echo "       Run: work-orchestrator.sh init <group>" >&2
    exit 1
  fi
  if [[ ! -f "$dir/state.json" ]]; then
    echo "ERROR: orchestrator state corrupt — $dir/state.json missing" >&2
    exit 1
  fi
}

# ── Atomic file writers ─────────────────────────────────────────────────────

write_atomic() {
  local target="$1" content="$2"
  local tmp="${target}.tmp.$$"
  printf '%s' "$content" > "$tmp"
  mv "$tmp" "$target"
}

write_atomic_lines() {
  local target="$1"; shift
  local tmp="${target}.tmp.$$"
  if [[ $# -eq 0 ]]; then
    : > "$tmp"
  else
    printf '%s\n' "$@" > "$tmp"
  fi
  mv "$tmp" "$target"
}

# ── State-file accessors (minimal parsing, no jq) ───────────────────────────
# state.json is a flat JSON object. We use grep -oE to pull individual
# fields. This is brittle for arbitrary JSON but FINE for state.json since
# we control its shape and write it from scratch every time.

state_get() {
  local dir="$1" key="$2"
  # Match "key": <value> where value is a JSON string. Tolerant of missing
  # file and missing key — both return empty string under set -e/pipefail.
  [[ -f "$dir/state.json" ]] || { printf ''; return 0; }
  local out
  out=$(grep -oE "\"$key\":[[:space:]]*\"[^\"]*\"" "$dir/state.json" 2>/dev/null | head -1 || true)
  [[ -n "$out" ]] && printf '%s' "$out" | sed -E "s/.*\"$key\":[[:space:]]*\"([^\"]*)\"/\1/" || printf ''
}

state_get_num() {
  local dir="$1" key="$2"
  [[ -f "$dir/state.json" ]] || { printf ''; return 0; }
  local out
  out=$(grep -oE "\"$key\":[[:space:]]*-?[0-9]+" "$dir/state.json" 2>/dev/null | head -1 || true)
  [[ -n "$out" ]] && printf '%s' "$out" | sed -E "s/.*\"$key\":[[:space:]]*//" || printf ''
}

state_get_bool() {
  local dir="$1" key="$2"
  [[ -f "$dir/state.json" ]] || { printf ''; return 0; }
  local out
  out=$(grep -oE "\"$key\":[[:space:]]*(true|false)" "$dir/state.json" 2>/dev/null | head -1 || true)
  [[ -n "$out" ]] && printf '%s' "$out" | sed -E "s/.*\"$key\":[[:space:]]*//" || printf ''
}

state_write() {
  local dir="$1"
  local group_slug started_at last_tick_at epoch cap paused pause_reason
  group_slug="${2:-$(state_get "$dir" group_slug)}"
  started_at="${3:-$(state_get "$dir" started_at)}"
  last_tick_at="${4:-$(iso_now)}"
  epoch="${5:-$(state_get_num "$dir" epoch)}"
  cap="${6:-$(state_get_num "$dir" concurrency_cap)}"
  paused="${7:-$(state_get_bool "$dir" paused)}"
  pause_reason="${8:-$(state_get "$dir" pause_reason)}"
  [[ -z "$paused" ]] && paused="false"

  local pause_field
  if [[ -z "$pause_reason" || "$pause_reason" == "null" ]]; then
    pause_field="null"
  else
    pause_field="\"$(json_escape "$pause_reason")\""
  fi

  write_atomic "$dir/state.json" "$(cat <<EOF
{
  "schema_version": 1,
  "group_slug": "$(json_escape "$group_slug")",
  "started_at": "$(json_escape "$started_at")",
  "last_tick_at": "$(json_escape "$last_tick_at")",
  "epoch": $epoch,
  "concurrency_cap": $cap,
  "paused": $paused,
  "pause_reason": $pause_field
}
EOF
)"
}

# Bump epoch + last_tick_at, preserve everything else.
state_tick() {
  local dir="$1"
  local current_epoch
  current_epoch=$(state_get_num "$dir" epoch)
  : "${current_epoch:=0}"
  state_write "$dir" "" "" "$(iso_now)" "$((current_epoch + 1))"
}

# ── Queue helpers ───────────────────────────────────────────────────────────

queue_contains() {
  local dir="$1" wd_id="$2"
  [[ -f "$dir/queue.txt" ]] || return 1
  grep -qxF "$wd_id" "$dir/queue.txt"
}

queue_append() {
  local dir="$1" wd_id="$2"
  if queue_contains "$dir" "$wd_id"; then
    return 0  # idempotent
  fi
  if [[ -f "$dir/queue.txt" && -s "$dir/queue.txt" ]]; then
    local existing
    existing=$(cat "$dir/queue.txt")
    write_atomic "$dir/queue.txt" "$existing"$'\n'"$wd_id"$'\n'
  else
    write_atomic "$dir/queue.txt" "$wd_id"$'\n'
  fi
}

queue_remove() {
  local dir="$1" wd_id="$2"
  [[ -f "$dir/queue.txt" ]] || return 0
  local tmp="$dir/queue.txt.tmp.$$"
  grep -vxF "$wd_id" "$dir/queue.txt" > "$tmp" || true
  mv "$tmp" "$dir/queue.txt"
}

# ── Set membership (for routing checks) ─────────────────────────────────────

in_set() {
  local dir="$1" subset="$2" wd_id="$3"
  [[ -f "$dir/$subset/$wd_id.json" ]]
}

# ── Per-WD record writers ───────────────────────────────────────────────────

write_in_flight() {
  local dir="$1" wd_id="$2" feature_slug="$3"
  mkdir -p "$dir/in-flight"
  write_atomic "$dir/in-flight/$wd_id.json" "$(cat <<EOF
{
  "dispatched_at": "$(iso_now)",
  "feature_slug": "$(json_escape "$feature_slug")"
}
EOF
)"
}

write_completed() {
  local dir="$1" wd_id="$2" status="$3" summary_line="$4"
  mkdir -p "$dir/completed"
  write_atomic "$dir/completed/$wd_id.json" "$(cat <<EOF
{
  "status": "$(json_escape "$status")",
  "summary_line": "$(json_escape "$summary_line")",
  "finished_at": "$(iso_now)"
}
EOF
)"
}

write_blocked() {
  local dir="$1" wd_id="$2" reason="$3" escalation_path="$4" feature_slug="$5"
  mkdir -p "$dir/blocked"
  write_atomic "$dir/blocked/$wd_id.json" "$(cat <<EOF
{
  "reason": "$(json_escape "$reason")",
  "blocked_at": "$(iso_now)",
  "escalation_path": "$(json_escape "$escalation_path")",
  "feature_slug": "$(json_escape "$feature_slug")"
}
EOF
)"
}

# ── Readiness integration ───────────────────────────────────────────────────
# Run work-resolve.sh, parse the resulting _readiness.json, and return
# every WD whose status is SPECIFIED. These are the WDs that have a spec
# AND have all artifact_deps satisfied — i.e., dispatchable.

read_specified_set() {
  local group="$1"
  local work_root
  work_root=$(work_find_root)
  local readiness="$work_root/$group/_readiness.json"

  # Trigger regeneration. work-resolve writes _readiness.json as a side
  # effect. Errors get propagated to stderr; we only need the file.
  (cd "$(dirname "$work_root")" && bash "$SCRIPT_DIR/work-resolve.sh" "$group" >/dev/null 2>&1) || true

  if [[ ! -f "$readiness" ]]; then
    echo "ERROR: $readiness not generated by work-resolve.sh" >&2
    return 1
  fi

  # Parse: extract every WD whose "status": "SPECIFIED". The JSON is line-
  # formatted by work-resolve, so we can use awk over { ... } blocks.
  awk '
    /^    \{/ { in_wd = 1; id = ""; status = "" }
    in_wd && /"id":/ {
      match($0, /"id":[ ]*"[^"]*"/); s = substr($0, RSTART, RLENGTH)
      gsub(/.*"id":[ ]*"/, "", s); gsub(/".*/, "", s); id = s
    }
    in_wd && /"status":/ {
      match($0, /"status":[ ]*"[^"]*"/); s = substr($0, RSTART, RLENGTH)
      gsub(/.*"status":[ ]*"/, "", s); gsub(/".*/, "", s); status = s
    }
    in_wd && /^    \}/ {
      if (status == "SPECIFIED") print id
      in_wd = 0
    }
  ' "$readiness"
}

# ── Subcommand: init ────────────────────────────────────────────────────────

cmd_init() {
  local group="$1"; shift
  local cap=3

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cap) cap="$2"; shift 2 ;;
      *) echo "ERROR: unknown init arg: $1" >&2; usage ;;
    esac
  done

  local dir
  dir=$(orch_dir "$group")

  if [[ -d "$dir" ]]; then
    echo "ERROR: orchestrator already initialized at $dir" >&2
    echo "       Run 'clear' first, or use 'resolve' to refresh the queue." >&2
    exit 3
  fi

  mkdir -p "$dir/in-flight" "$dir/completed" "$dir/blocked"
  : > "$dir/queue.txt"

  state_write "$dir" "$group" "$(iso_now)" "$(iso_now)" 0 "$cap" false ""

  # Populate initial queue from SPECIFIED set.
  local wd added=0
  while IFS= read -r wd; do
    [[ -z "$wd" ]] && continue
    queue_append "$dir" "$wd"
    added=$((added + 1))
  done < <(read_specified_set "$group")

  echo "Initialized orchestrator: $dir"
  echo "  concurrency_cap: $cap"
  echo "  queued: $added WD(s)"
}

# ── Subcommand: status ──────────────────────────────────────────────────────

cmd_status() {
  local group="$1"
  local dir
  dir=$(orch_dir "$group")
  require_init "$dir"

  local epoch cap paused pause_reason started last_tick
  epoch=$(state_get_num "$dir" epoch)
  cap=$(state_get_num "$dir" concurrency_cap)
  paused=$(state_get_bool "$dir" paused)
  pause_reason=$(state_get "$dir" pause_reason)
  started=$(state_get "$dir" started_at)
  last_tick=$(state_get "$dir" last_tick_at)

  local q_count in_flight_count completed_count blocked_count
  q_count=$(wc -l < "$dir/queue.txt" 2>/dev/null | tr -d ' ')
  [[ -z "$(tail -c 1 "$dir/queue.txt" 2>/dev/null)" && -s "$dir/queue.txt" ]] || true
  # Counts can over-count if the file is empty but with trailing newline; clamp.
  [[ ! -s "$dir/queue.txt" ]] && q_count=0
  in_flight_count=$(find "$dir/in-flight" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
  completed_count=$(find "$dir/completed" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
  blocked_count=$(find "$dir/blocked" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')

  echo "── Orchestrator state · $group ─────────────────────"
  echo "Started:    $started"
  echo "Last tick:  $last_tick (epoch $epoch)"
  echo "Cap:        $cap concurrent"
  if [[ "$paused" == "true" ]]; then
    echo "Paused:     YES — $pause_reason"
  else
    echo "Paused:     no"
  fi
  echo ""
  echo "  Queued:     $q_count"
  if [[ "$q_count" -gt 0 ]]; then
    sed 's/^/    /' "$dir/queue.txt"
  fi
  echo "  In-flight:  $in_flight_count"
  if [[ "$in_flight_count" -gt 0 ]]; then
    for f in "$dir/in-flight"/*.json; do
      [[ -e "$f" ]] || continue
      local wd
      wd=$(basename "$f" .json)
      local feat
      feat=$(grep -oE '"feature_slug":[[:space:]]*"[^"]*"' "$f" | sed -E 's/.*"([^"]*)"/\1/')
      echo "    $wd ($feat)"
    done
  fi
  echo "  Completed:  $completed_count"
  if [[ "$completed_count" -gt 0 ]]; then
    for f in "$dir/completed"/*.json; do
      [[ -e "$f" ]] || continue
      local wd st
      wd=$(basename "$f" .json)
      st=$(grep -oE '"status":[[:space:]]*"[^"]*"' "$f" | sed -E 's/.*"([^"]*)"/\1/')
      echo "    $wd — $st"
    done
  fi
  echo "  Blocked:    $blocked_count"
  if [[ "$blocked_count" -gt 0 ]]; then
    for f in "$dir/blocked"/*.json; do
      [[ -e "$f" ]] || continue
      local wd rs
      wd=$(basename "$f" .json)
      rs=$(grep -oE '"reason":[[:space:]]*"[^"]*"' "$f" | sed -E 's/.*"([^"]*)"/\1/')
      echo "    $wd — $rs"
    done
  fi
  echo "─────────────────────────────────────────────────────"
}

# ── Subcommand: dump ────────────────────────────────────────────────────────

cmd_dump() {
  local group="$1"; shift
  local section="all"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --section) section="$2"; shift 2 ;;
      *) echo "ERROR: unknown dump arg: $1" >&2; usage ;;
    esac
  done

  local dir
  dir=$(orch_dir "$group")
  require_init "$dir"

  case "$section" in
    state) cat "$dir/state.json" ;;
    queue) [[ -f "$dir/queue.txt" ]] && cat "$dir/queue.txt" ;;
    in-flight|completed|blocked)
      for f in "$dir/$section"/*.json; do
        [[ -e "$f" ]] || continue
        echo "─── $(basename "$f" .json) ───"
        cat "$f"
        echo ""
      done
      ;;
    all)
      echo "=== state.json ==="; cat "$dir/state.json"; echo
      echo "=== queue.txt ==="; cat "$dir/queue.txt" 2>/dev/null; echo
      for subset in in-flight completed blocked; do
        for f in "$dir/$subset"/*.json; do
          [[ -e "$f" ]] || continue
          echo "=== $subset/$(basename "$f") ==="; cat "$f"; echo
        done
      done
      ;;
    *) echo "ERROR: unknown --section: $section" >&2; usage ;;
  esac
}

# ── Subcommand: ready ───────────────────────────────────────────────────────

cmd_ready() {
  local group="$1"
  local dir
  dir=$(orch_dir "$group")
  require_init "$dir"

  local paused
  paused=$(state_get_bool "$dir" paused)
  if [[ "$paused" == "true" ]]; then
    return 0  # Print nothing while paused.
  fi

  local cap in_flight_count slots
  cap=$(state_get_num "$dir" concurrency_cap)
  in_flight_count=$(find "$dir/in-flight" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
  slots=$((cap - in_flight_count))

  if [[ "$slots" -le 0 ]] || [[ ! -s "$dir/queue.txt" ]]; then
    return 0
  fi

  head -n "$slots" "$dir/queue.txt"
}

# ── Subcommand: dispatch ────────────────────────────────────────────────────

cmd_dispatch() {
  local group="$1" wd_id="$2" feature_slug="$3"
  validate_wd_id "$wd_id"
  local dir
  dir=$(orch_dir "$group")
  require_init "$dir"

  if ! queue_contains "$dir" "$wd_id"; then
    echo "ERROR: $wd_id is not in queue (cannot dispatch)" >&2
    exit 3
  fi
  if in_set "$dir" in-flight "$wd_id"; then
    echo "ERROR: $wd_id already in-flight" >&2
    exit 3
  fi

  write_in_flight "$dir" "$wd_id" "$feature_slug"
  queue_remove "$dir" "$wd_id"
  state_tick "$dir"

  echo "dispatched $wd_id ($feature_slug)"
}

# ── Subcommand: complete ────────────────────────────────────────────────────

cmd_complete() {
  local group="$1" wd_id="$2" status="$3" summary_line="$4"
  validate_wd_id "$wd_id"
  local dir
  dir=$(orch_dir "$group")
  require_init "$dir"

  if ! in_set "$dir" in-flight "$wd_id"; then
    echo "ERROR: $wd_id is not in-flight (cannot complete)" >&2
    exit 3
  fi

  write_completed "$dir" "$wd_id" "$status" "$summary_line"
  rm -f "$dir/in-flight/$wd_id.json"

  # Re-resolve readiness: any BLOCKED WDs that the just-finished WD was
  # holding back may now be SPECIFIED. Add them to the queue (dedup).
  local wd added=0
  while IFS= read -r wd; do
    [[ -z "$wd" ]] && continue
    # Skip if already known to the orchestrator.
    queue_contains "$dir" "$wd" && continue
    in_set "$dir" in-flight "$wd" && continue
    in_set "$dir" completed "$wd" && continue
    in_set "$dir" blocked "$wd" && continue
    queue_append "$dir" "$wd"
    added=$((added + 1))
  done < <(read_specified_set "$group")

  state_tick "$dir"
  echo "completed $wd_id ($status); +$added newly-ready WD(s) queued"
}

# ── Subcommand: block ───────────────────────────────────────────────────────

cmd_block() {
  local group="$1" wd_id="$2" reason="$3" escalation_path="$4"
  validate_wd_id "$wd_id"
  local dir
  dir=$(orch_dir "$group")
  require_init "$dir"

  if ! in_set "$dir" in-flight "$wd_id"; then
    echo "ERROR: $wd_id is not in-flight (cannot block)" >&2
    exit 3
  fi

  local feature_slug
  feature_slug=$(grep -oE '"feature_slug":[[:space:]]*"[^"]*"' "$dir/in-flight/$wd_id.json" \
    | sed -E 's/.*"([^"]*)"/\1/')

  write_blocked "$dir" "$wd_id" "$reason" "$escalation_path" "$feature_slug"
  rm -f "$dir/in-flight/$wd_id.json"

  state_write "$dir" "" "" "$(iso_now)" "" "" true "$wd_id: $reason"
  echo "blocked $wd_id ($reason); orchestrator paused — call 'resume' after user resolution"
}

# ── Subcommand: unblock ─────────────────────────────────────────────────────

cmd_unblock() {
  local group="$1" wd_id="$2"
  validate_wd_id "$wd_id"
  local dir
  dir=$(orch_dir "$group")
  require_init "$dir"

  if ! in_set "$dir" blocked "$wd_id"; then
    echo "ERROR: $wd_id is not in blocked set (cannot unblock)" >&2
    exit 3
  fi

  rm -f "$dir/blocked/$wd_id.json"
  queue_append "$dir" "$wd_id"
  state_tick "$dir"
  echo "unblocked $wd_id — re-queued"
}

# ── Subcommand: resume ──────────────────────────────────────────────────────

cmd_resume() {
  local group="$1"
  local dir
  dir=$(orch_dir "$group")
  require_init "$dir"

  state_write "$dir" "" "" "$(iso_now)" "" "" false ""
  echo "resumed — dispatching will proceed"
}

# ── Subcommand: hung ────────────────────────────────────────────────────────

cmd_hung() {
  local group="$1"; shift
  local threshold=1800

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --threshold-seconds) threshold="$2"; shift 2 ;;
      *) echo "ERROR: unknown hung arg: $1" >&2; usage ;;
    esac
  done

  local dir
  dir=$(orch_dir "$group")
  require_init "$dir"

  local work_root
  work_root=$(work_find_root)
  local repo_root
  repo_root=$(dirname "$work_root")

  local now_epoch
  now_epoch=$(date -u +%s)

  for f in "$dir/in-flight"/*.json; do
    [[ -e "$f" ]] || continue
    local wd feat status_md mtime delta
    wd=$(basename "$f" .json)
    feat=$(grep -oE '"feature_slug":[[:space:]]*"[^"]*"' "$f" | sed -E 's/.*"([^"]*)"/\1/')
    status_md="$repo_root/.feature/$feat/status.md"
    if [[ ! -f "$status_md" ]]; then
      # No status.md yet — use the dispatched_at timestamp instead.
      local disp
      disp=$(grep -oE '"dispatched_at":[[:space:]]*"[^"]*"' "$f" | sed -E 's/.*"([^"]*)"/\1/')
      mtime=$(date -u -d "$disp" +%s 2>/dev/null || echo "$now_epoch")
    else
      mtime=$(stat -c %Y "$status_md" 2>/dev/null || stat -f %m "$status_md" 2>/dev/null || echo "$now_epoch")
    fi
    delta=$((now_epoch - mtime))
    if [[ "$delta" -gt "$threshold" ]]; then
      echo "$wd $delta $feat"
    fi
  done
}

# ── Subcommand: resolve ─────────────────────────────────────────────────────

cmd_resolve() {
  local group="$1"
  local dir
  dir=$(orch_dir "$group")
  require_init "$dir"

  local wd added=0
  while IFS= read -r wd; do
    [[ -z "$wd" ]] && continue
    queue_contains "$dir" "$wd" && continue
    in_set "$dir" in-flight "$wd" && continue
    in_set "$dir" completed "$wd" && continue
    in_set "$dir" blocked "$wd" && continue
    queue_append "$dir" "$wd"
    added=$((added + 1))
  done < <(read_specified_set "$group")

  state_tick "$dir"
  echo "resolved: +$added newly-SPECIFIED WD(s) queued"
}

# ── Subcommand: clear ───────────────────────────────────────────────────────

cmd_clear() {
  local group="$1"
  local dir
  dir=$(orch_dir "$group")
  if [[ -d "$dir" ]]; then
    rm -rf "$dir"
    echo "cleared $dir"
  fi
}

# ── Dispatch table ──────────────────────────────────────────────────────────

[[ $# -lt 1 ]] && usage
action="$1"; shift

case "$action" in
  init)     [[ $# -lt 1 ]] && usage; cmd_init "$@" ;;
  status)   [[ $# -ne 1 ]] && usage; cmd_status "$@" ;;
  dump)     [[ $# -lt 1 ]] && usage; cmd_dump "$@" ;;
  ready)    [[ $# -ne 1 ]] && usage; cmd_ready "$@" ;;
  dispatch) [[ $# -ne 3 ]] && usage; cmd_dispatch "$@" ;;
  complete) [[ $# -ne 4 ]] && usage; cmd_complete "$@" ;;
  block)    [[ $# -ne 4 ]] && usage; cmd_block "$@" ;;
  unblock)  [[ $# -ne 2 ]] && usage; cmd_unblock "$@" ;;
  resume)   [[ $# -ne 1 ]] && usage; cmd_resume "$@" ;;
  hung)     [[ $# -lt 1 ]] && usage; cmd_hung "$@" ;;
  resolve)  [[ $# -ne 1 ]] && usage; cmd_resolve "$@" ;;
  clear)    [[ $# -ne 1 ]] && usage; cmd_clear "$@" ;;
  *)        usage ;;
esac
