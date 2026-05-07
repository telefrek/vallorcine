#!/usr/bin/env bash
# feature-state-reconcile.sh — reconcile a feature's status.md against
# durable artifacts (specs in manifest, etc.) and surface stage drift
# that local cache missed.
#
# Usage:
#   feature-state-reconcile.sh <feature-slug> [--read-only]
#
# Why this exists:
#   .feature/<slug>/ is gitignored. When a sibling WD authors a spec
#   that this WD's `produces:` declares, the spec lands in the manifest
#   (durable, committed) but this feature's status.md still says
#   "Spec Authoring pending" — the local cache never observed the
#   change, since it lives only on whoever ran the spec-authoring
#   session. Re-entering this feature on a fresh machine or session
#   then misreads the state and tries to redo work that's already done.
#
#   Reconciliation: read the WD's `produces:` list, look up each
#   produced spec's state in the manifest, and if all are APPROVED,
#   advance the Spec Authoring row in status.md to `complete`.
#
# Scope:
#   - Spec Authoring substage only. Planning/Testing/Implementation
#     produce code + tests in git, which is the canonical state — and
#     status.md drift on those is rarer because they advance within a
#     single session.
#   - Only work-group features. Plain features without `work_group`
#     have no cross-session artifact production to reconcile against.
#
# Output (stdout): one human-readable summary line per check.
# Exit code: 0 always (drift is informational, not an error).

set -euo pipefail

_FSR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=spec-lib.sh disable=SC1091
source "$_FSR_SCRIPT_DIR/spec-lib.sh"
# shellcheck source=work-lib.sh disable=SC1091
source "$_FSR_SCRIPT_DIR/work-lib.sh"

SLUG="${1:-}"
READ_ONLY=false
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --read-only) READ_ONLY=true ;;
    *) echo "ERROR: unknown flag '$1'" >&2; exit 2 ;;
  esac
  shift
done

[[ -z "$SLUG" ]] && {
  echo "Usage: feature-state-reconcile.sh <feature-slug> [--read-only]" >&2
  exit 2
}

# ── Locate feature dir ──────────────────────────────────────────────────────
FEATURE_DIR=""
if   [[ -d ".feature/$SLUG" ]];          then FEATURE_DIR=".feature/$SLUG"
elif [[ -d ".feature/_archive/$SLUG" ]]; then FEATURE_DIR=".feature/_archive/$SLUG"
fi

[[ -z "$FEATURE_DIR" ]] && {
  echo "no feature directory for '$SLUG' — nothing to reconcile" >&2
  exit 0
}

STATUS_FILE="$FEATURE_DIR/status.md"
[[ ! -f "$STATUS_FILE" ]] && {
  echo "no status.md for '$SLUG' — nothing to reconcile" >&2
  exit 0
}

# ── Detect work group + WD (mirrors work-finalize.sh) ──────────────────────
WORK_GROUP="$(grep -m1 '^work_group:' "$STATUS_FILE" 2>/dev/null \
              | sed 's/^work_group:[[:space:]]*//' || true)"
WORK_DEF="$(grep -m1 '^work_definition:' "$STATUS_FILE" 2>/dev/null \
            | sed 's/^work_definition:[[:space:]]*//' || true)"

if [[ -z "$WORK_GROUP" && "$SLUG" == *"--"* ]]; then
  WORK_GROUP="${SLUG%%--*}"
  wd_suffix="${SLUG##*--}"
  WORK_DEF="$(echo "$wd_suffix" | tr '[:lower:]' '[:upper:]' | sed 's/-/\-/g')"
fi

if [[ -z "$WORK_GROUP" ]]; then
  echo "'$SLUG' is not work-group-sourced — no cross-session reconciliation needed"
  exit 0
fi

WD_FILE=""
WORK_DIR=".work/$WORK_GROUP"
if [[ -d "$WORK_DIR" ]]; then
  for f in "$WORK_DIR"/WD-*.md; do
    [[ ! -f "$f" ]] && continue
    wd_id="$(work_fm "$f" "id")"
    if [[ "$wd_id" == "$WORK_DEF" ]]; then
      WD_FILE="$f"
      break
    fi
  done
fi

if [[ -z "$WD_FILE" ]]; then
  echo "WD file not found for $WORK_GROUP/$WORK_DEF — nothing to reconcile"
  exit 0
fi

# ── Read produces specs and check their manifest state ─────────────────────
MANIFEST=".spec/registry/manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "no spec manifest — nothing to reconcile"
  exit 0
fi

PRODUCED_SPECS=()
while IFS='|' read -r prod_type prod_path _ _; do
  [[ -z "$prod_type" ]] && continue
  [[ "$prod_type" != "spec" ]] && continue
  # Normalize slash → dot so domain-shaped paths match manifest IDs.
  normalized="${prod_path//\//.}"
  PRODUCED_SPECS+=("$normalized")
done < <(work_fm_produces "$WD_FILE")

if [[ ${#PRODUCED_SPECS[@]} -eq 0 ]]; then
  echo "$SLUG: WD produces no specs — spec authoring substage has no durable check"
  exit 0
fi

approved=0
total=${#PRODUCED_SPECS[@]}
not_approved=()
for sid in "${PRODUCED_SPECS[@]}"; do
  state="$(spec_manifest_state "$MANIFEST" "$sid")"
  if [[ "$state" == "APPROVED" ]]; then
    approved=$((approved + 1))
  else
    not_approved+=("$sid${state:+ ($state)}")
  fi
done

# ── Read current Spec Authoring substage from status.md ────────────────────
# The Stage Completion table row we care about:
#   "| Spec Authoring | <status> | ... |"
current_row="$(grep -E '^\| Spec Authoring \|' "$STATUS_FILE" 2>/dev/null | head -1)"
if [[ -z "$current_row" ]]; then
  echo "$SLUG: no Spec Authoring row in status.md — pipeline_mode may exclude it"
  exit 0
fi

current_status="$(echo "$current_row" | awk -F'|' '{gsub(/^ +| +$/, "", $3); print $3}')"

# ── Decide ──────────────────────────────────────────────────────────────────
if [[ "$approved" -eq "$total" ]]; then
  if [[ "$current_status" == "complete" ]]; then
    echo "$SLUG: Spec Authoring already complete in status.md; $approved/$total produced specs APPROVED in manifest — current"
    exit 0
  fi

  echo "$SLUG: drift — Spec Authoring '$current_status' in status.md but $approved/$total produced specs APPROVED in manifest"
  if [[ "$READ_ONLY" == "true" ]]; then
    echo "  (read-only mode — not rewriting status.md)"
    exit 0
  fi

  # Apply: flip the row's status column to "complete" and stamp the
  # Completed column to today. Awk index() avoids regex hazards with `|`.
  today="$(date +%F)"
  prefix='| Spec Authoring |'
  tmp="$(mktemp)"
  awk -v prefix="$prefix" -v today="$today" '
    index($0, prefix) == 1 {
      # Reformat the row, preserving the trailing columns past Completed.
      n = split($0, cols, "|")
      # cols[2] = " Spec Authoring "
      # cols[3] = " <status> "
      # cols[4] = " <completed> "
      # cols[5] = " <est tokens> "
      # cols[6] = " <actual tokens> "
      # cols[7] = " <notes> "
      cols[3] = " complete "
      if (cols[4] ~ /^[ ]*—[ ]*$/ || cols[4] ~ /^[ ]*$/) {
        cols[4] = " " today " "
      }
      cols[7] = " reconciled — produced specs APPROVED in manifest "
      out = ""
      for (i = 2; i <= n - 1; i++) out = out "|" cols[i]
      print out "|"
      next
    }
    { print }
  ' "$STATUS_FILE" > "$tmp"
  mv "$tmp" "$STATUS_FILE"
  echo "  reconciled status.md: Spec Authoring → complete (Completed=$today)"
  exit 0
fi

# Some produced specs not yet APPROVED — surface the gap so the caller
# can decide. No write either way: status.md "in-progress" or
# "not-started" is consistent with reality.
echo "$SLUG: Spec Authoring '$current_status' in status.md; $approved/$total produced specs APPROVED in manifest"
if [[ ${#not_approved[@]} -gt 0 ]]; then
  echo "  not yet APPROVED:"
  for s in "${not_approved[@]}"; do
    echo "    - $s"
  done
fi
