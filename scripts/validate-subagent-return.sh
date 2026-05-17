#!/usr/bin/env bash
# validate-subagent-return.sh
#
# Scans a subagent return for completeness-contract violations.
# See rules/completeness-contract.md.
#
# Orchestrators (work-orchestrator, work-run, work-start, feature-coordinate,
# audit, spec-backfill, curate, work-plan) MUST run this on every subagent
# return BEFORE marking the dispatched unit COMPLETE. If exit code is non-zero,
# the orchestrator MUST route to the user via AskUserQuestion rather than
# accepting the return.
#
# Usage:
#   bash validate-subagent-return.sh <return-file>
#
# Exit codes:
#   0 = clean (no trigger phrases found)
#   1 = trigger phrase found (deferral detected — block COMPLETE, route to user)
#   2 = file not found / usage error
#
# Design notes:
# - Biases toward false positives. The check ROUTES to the user; it doesn't
#   silently block. A false positive wastes a few seconds; a false negative
#   ships incomplete work. The asymmetry favors the user.
# - Case-insensitive substring matching (-iF) keeps phrase definitions simple
#   and avoids regex escaping for hyphens and apostrophes.
# - Returns the matched phrase + first matching line to stderr so the
#   orchestrator can surface useful context in its AskUserQuestion prompt.

set -euo pipefail

return_file="${1:-}"

if [[ -z "$return_file" ]]; then
  printf 'ERROR: usage: %s <return-file>\n' "$(basename "$0")" >&2
  exit 2
fi

if [[ ! -f "$return_file" || ! -r "$return_file" ]]; then
  printf 'ERROR: return file not readable: %s\n' "$return_file" >&2
  exit 2
fi

# Trigger phrases. Match the prose forms a subagent is most likely to write,
# not every conceivable wording. Bias toward common shapes; user can clear
# false alarms.
TRIGGER_PHRASES=(
  "candidate"
  "follow-on"
  "follow up"
  "follow-up"
  "out of scope"
  "deferred"
  "future work"
  "for later"
  "we'll do this in a follow"
  "we will do this in a follow"
  "track separately"
  "separate concern"
  "not this PR's problem"
  "not this PR problem"
  "covered transitively"
  "edge case we can punt"
  "minor — can address later"
  "minor - can address later"
  "minor, can address later"
  "non-critical"
  "out of this scope"
)

found=()

for phrase in "${TRIGGER_PHRASES[@]}"; do
  # Use grep -iF for case-insensitive fixed-string match. -m1 stops at first
  # match per phrase. Suppress stderr in case file has weird encoding.
  if line=$(grep -iF -m1 -- "$phrase" "$return_file" 2>/dev/null); then
    found+=("${phrase}|||${line}")
  fi
done

if (( ${#found[@]} > 0 )); then
  printf 'VIOLATION: deferral trigger phrases detected in subagent return.\n' >&2
  printf '  See rules/completeness-contract.md for the contract.\n' >&2
  printf '\n  Triggers found:\n' >&2
  for entry in "${found[@]}"; do
    phrase="${entry%%|||*}"
    line="${entry##*|||}"
    # Truncate line for readability (orchestrator can re-read file for full context)
    if (( ${#line} > 120 )); then
      line="${line:0:117}..."
    fi
    printf '    - "%s" in: %s\n' "$phrase" "$line" >&2
  done
  printf '\n  Orchestrator action: block COMPLETE, route to user via AskUserQuestion.\n' >&2
  exit 1
fi

exit 0
