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
#   bash validate-subagent-return.sh <return-file> [--require-ac-coverage]
#
# Flags:
#   --require-ac-coverage  Also require the return to contain an AC satisfaction
#                          mapping (per rules/completeness-contract.md §6).
#                          Pass this for WD-return orchestrators (work-run,
#                          work-start, work-plan). Skip for audit / spec-backfill /
#                          curate dispatches that don't carry WD-style ACs.
#
# Exit codes:
#   0 = clean (no contract violations found)
#   1 = contract violation found (trigger phrase OR missing AC coverage when required)
#   2 = file not found / usage error
#
# Design notes:
# - Biases toward false positives. The check ROUTES to the user; it doesn't
#   silently block. A false positive wastes a few seconds; a false negative
#   ships incomplete work. The asymmetry favors the user.
# - Case-insensitive substring matching (-iF) keeps phrase definitions simple
#   and avoids regex escaping for hyphens and apostrophes.
# - Writes findings to stderr so orchestrators can surface them in the
#   AskUserQuestion prompt as context.

set -euo pipefail

return_file=""
require_ac_coverage=false

for arg in "$@"; do
  case "$arg" in
    --require-ac-coverage)
      require_ac_coverage=true
      ;;
    --*)
      printf 'ERROR: unknown flag: %s\n' "$arg" >&2
      exit 2
      ;;
    *)
      if [[ -z "$return_file" ]]; then
        return_file="$arg"
      else
        printf 'ERROR: unexpected positional argument: %s\n' "$arg" >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "$return_file" ]]; then
  printf 'ERROR: usage: %s <return-file> [--require-ac-coverage]\n' "$(basename "$0")" >&2
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

violation_count=0

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
  printf '\n' >&2
  violation_count=$((violation_count + 1))
fi

if $require_ac_coverage; then
  # Look for AC-satisfaction markers. Returns claiming COMPLETE for a WD
  # MUST include a section mapping each acceptance criterion to a satisfier.
  # See rules/completeness-contract.md §6 (Scope-reconciliation contract).
  AC_PATTERNS=(
    "AC satisfaction"
    "AC coverage"
    "AC mapping"
    "Acceptance criteria satisfaction"
    "Acceptance criteria coverage"
    "Acceptance criterion"
    "satisfies AC"
    "AC[0-9]"
    "AC-[0-9]"
  )
  ac_found=false
  for pattern in "${AC_PATTERNS[@]}"; do
    if grep -iE -- "$pattern" "$return_file" >/dev/null 2>&1; then
      ac_found=true
      break
    fi
  done
  if ! $ac_found; then
    printf 'VIOLATION: return missing AC satisfaction mapping.\n' >&2
    printf '  See rules/completeness-contract.md §6 (Scope-reconciliation).\n' >&2
    printf '  Returns claiming COMPLETE for a WD MUST include a section\n' >&2
    printf '  mapping each acceptance criterion to its satisfier (code, test,\n' >&2
    printf '  or doc with file:line citation).\n\n' >&2
    violation_count=$((violation_count + 1))
  fi
fi

if (( violation_count > 0 )); then
  printf '  Orchestrator action: block COMPLETE, route to user via AskUserQuestion.\n' >&2
  exit 1
fi

exit 0
