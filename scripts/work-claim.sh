#!/usr/bin/env bash
# work-claim.sh — atomically transition a WD's status (compare-and-swap)
# Usage: work-claim.sh <group-slug> <wd-id> <expected-status> <new-status>
#
# Reads the current status, asserts it matches <expected-status>, and
# updates to <new-status>. The whole sequence runs under flock so two
# parallel sessions cannot both succeed when racing the same transition
# (e.g., both running /work-plan WD-01 from DRAFT).
#
# Exit codes:
#   0 — claim succeeded (status was <expected>, now <new>)
#   1 — claim failed: WD not in expected state (someone got there first,
#       OR the WD was hand-edited between resolver read and claim)
#   2 — error (WD file not found, lock acquisition failed, etc.)
#
# Stdout: "[claim] <wd-id>: <expected> → <new>" on success, error message
#         on failure (also written to stderr for piped contexts).
#
# Shares the .work-resolve.lock file with work-resolve.sh so the manifest
# sync inside work-resolve cannot interleave with a status mutation
# inside work-claim. Both ops mutate the group's effective state and
# must serialize against each other.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/work-lib.sh"

work_require_deps

if [[ $# -lt 4 ]]; then
  echo "Usage: work-claim.sh <group-slug> <wd-id> <expected-status> <new-status>" >&2
  echo "  Example: work-claim.sh auth-rewrite WD-01 DRAFT SPECIFYING" >&2
  exit 2
fi

GROUP_SLUG="$1"
WD_ID="$2"
EXPECTED="$3"
NEW="$4"

# Validate the new state is one of the known lifecycle states. Catches
# typos like "SPECIFFIED" before we sed-flip the WD into a state the
# resolver doesn't recognize.
case "$NEW" in
  DRAFT|SPECIFYING|SPECIFIED|IMPLEMENTING|COMPLETE) ;;
  *)
    echo "ERROR: unknown new-status '$NEW' (valid: DRAFT|SPECIFYING|SPECIFIED|IMPLEMENTING|COMPLETE)" >&2
    exit 2
    ;;
esac

WORK_DIR="$(work_find_root)" || exit 2
GROUP_DIR="$WORK_DIR/$GROUP_SLUG"
WD_FILE="$GROUP_DIR/$WD_ID.md"

if [[ ! -d "$GROUP_DIR" ]]; then
  echo "ERROR: Work group not found: $GROUP_SLUG ($GROUP_DIR)" >&2
  exit 2
fi

if [[ ! -f "$WD_FILE" ]]; then
  echo "ERROR: WD file not found: $WD_FILE" >&2
  exit 2
fi

# Acquire the shared work-group write lock so this transition cannot
# interleave with work-resolve.sh or another work-claim invocation.
if command -v flock >/dev/null 2>&1; then
  CLAIM_LOCK="$GROUP_DIR/.work-resolve.lock"
  exec 9>"$CLAIM_LOCK"
  if ! flock -w 30 9; then
    echo "ERROR: lock timeout after 30s on $CLAIM_LOCK" >&2
    exit 2
  fi
fi

# Read current status under the lock — this is the canonical "now" view.
CURRENT=$(work_fm "$WD_FILE" "status")

if [[ "$CURRENT" != "$EXPECTED" ]]; then
  echo "[claim] CONFLICT: $WD_ID is '$CURRENT', expected '$EXPECTED'" >&2
  echo "        Another session likely transitioned this WD first." >&2
  echo "        Re-run /work-resume \"$GROUP_SLUG\" to see the latest state." >&2
  exit 1
fi

# Atomic write: sed -i uses tmp + rename internally on most platforms.
# We're inside the lock, so even if the underlying I/O races on inode
# state, no other claim or resolver run can be in flight.
sed -i "s/^status:.*$/status: $NEW/" "$WD_FILE"

echo "[claim] $WD_ID: $EXPECTED → $NEW"
exit 0
