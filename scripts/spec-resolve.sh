#!/usr/bin/env bash
# spec-resolve.sh — deterministic context bundle builder
# Usage: spec-resolve.sh "<feature description>" [token-budget]
# Optional env: OVERRIDE_DOMAINS="storage,compaction"
# Optional env: EXPLICIT_SPEC_IDS="id1,id2" — bypass fuzzy match; use these IDs directly
# Optional env: NEW_SPEC_FILES="path1:path2" — draft specs to check for displacement
# Optional env: INCLUDE_INVALIDATED=true — include INVALIDATED specs in separate section
# Optional env: FILTER_KIND="interface-contract" — only include specs with this kind field
# Optional env: INCLUDE_SIBLINGS=true — when a child spec lands in candidates,
#                also include its siblings (other children of the same parent).
#                Used by adversarial paths (/spec-author Pass 2/3) that need
#                cross-sibling contradiction detection. Default off.
# Output: markdown bundle on stdout | diagnostics on stderr

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/spec-lib.sh"

spec_require_deps

FEATURE_DESC="${1:-}"
# Default budget sized for a typical 2-spec mature-domain bundle (~22K tokens).
# Empirically derived from jlsm membership/encryption domains where individual
# specs run 9-12K tokens each. The previous default of 8000 produced empty
# bundles for almost any mature spec.
TOKEN_BUDGET="${2:-25000}"
[[ -z "$FEATURE_DESC" ]] && {
  echo "Usage: spec-resolve.sh '<feature description>' [token-budget]" >&2
  exit 1
}

SPEC_DIR="$(spec_find_root)" || exit 1
PROJECT_ROOT="$(dirname "$SPEC_DIR")"
MANIFEST="$SPEC_DIR/registry/manifest.json"

[[ ! -f "$MANIFEST" ]] && {
  echo "ERROR: manifest not found at $MANIFEST — run /spec-init first" >&2
  exit 1
}

# ── Step 1: Determine matched domains ────────────────────────────────────────
EXPLICIT_ID_MODE=false
CANDIDATE_FILES=()
CONFLICT_OMITTED=()

if [[ -n "${EXPLICIT_SPEC_IDS:-}" ]]; then
  # Caller passed spec IDs directly — bypass fuzzy match and domain inference.
  # Used by skills (e.g. /feature-test --specs flag, brief.md explicit list)
  # when the spec set is known and fuzzy matching would be unreliable.
  EXPLICIT_ID_MODE=true
  IFS=',' read -ra EXPLICIT_IDS <<< "$EXPLICIT_SPEC_IDS"
  echo "[resolve] Explicit spec IDs: ${EXPLICIT_IDS[*]}" >&2

  declare -A DOMAIN_SET
  for fid in "${EXPLICIT_IDS[@]}"; do
    fid="$(echo "$fid" | tr -d ' ')"
    [[ -z "$fid" ]] && continue
    spec_file=$(spec_file_for_id "$MANIFEST" "$fid")
    if [[ -z "$spec_file" || ! -f "$spec_file" ]]; then
      echo "[resolve] WARN: explicit spec '$fid' not in registry — skipping" >&2
      continue
    fi
    spec_check_crlf "$spec_file" 2>/dev/null || continue
    CANDIDATE_FILES+=("$spec_file")
    while IFS= read -r dom; do
      [[ -n "$dom" ]] && DOMAIN_SET["$dom"]=1
    done < <(fm "$spec_file" '.domains // [] | .[]')
  done
  MATCHED_DOMAINS=("${!DOMAIN_SET[@]}")
  [[ ${#MATCHED_DOMAINS[@]} -eq 0 ]] && MATCHED_DOMAINS=("unknown")
elif [[ -n "${OVERRIDE_DOMAINS:-}" ]]; then
  IFS=',' read -ra MATCHED_DOMAINS <<< "$OVERRIDE_DOMAINS"
  echo "[resolve] Domain override: ${MATCHED_DOMAINS[*]}" >&2
else
  mapfile -t ALL_DOMAINS < <(spec_manifest_all_domains "$MANIFEST")
  desc_lower=$(echo "$FEATURE_DESC" | tr '[:upper:]' '[:lower:]')
  MATCHED_DOMAINS=()
  # v2 manifests carry no domain descriptions; description-keyword matching
  # degrades to name-only matching, which is correct behavior — ambiguous
  # cases fall through to NEEDS_DOMAIN_INFERENCE.
  v2_manifest=false
  spec_manifest_is_v2 "$MANIFEST" && v2_manifest=true
  for domain in "${ALL_DOMAINS[@]}"; do
    if [[ "$v2_manifest" == "true" ]]; then
      domain_desc=""
    else
      domain_desc=$(jq -r --arg d "$domain" '.domains[$d].description // ""' "$MANIFEST" \
        | tr '[:upper:]' '[:lower:]')
    fi
    # Match if feature desc contains domain name OR any keyword in domain desc
    if echo "$desc_lower" | grep -qw "$domain"; then
      MATCHED_DOMAINS+=("$domain")
    else
      for word in $domain_desc; do
        if [[ ${#word} -gt 4 ]] && echo "$desc_lower" | grep -qw "$word"; then
          MATCHED_DOMAINS+=("$domain")
          break
        fi
      done
    fi
  done
fi

# Emit partial bundle for domain inference if no match
if [[ ${#MATCHED_DOMAINS[@]} -eq 0 ]]; then
  echo "NEEDS_DOMAIN_INFERENCE=true" >&2
  echo "# Partial Bundle — Domain Inference Required"
  echo "Feature request: $FEATURE_DESC"
  echo ""
  echo "## Available Domains"
  jq -r '
    if .specs then
      ([.specs[].domains[]] | unique | .[] | "- \(.)")
    else
      (.domains | to_entries[] | "- \(.key): \(.value.description)")
    end
  ' "$MANIFEST"
  exit 0
fi

echo "[resolve] Domains matched: ${MATCHED_DOMAINS[*]}" >&2

# ── Step 2: Collect candidate spec files via registry ────────────────────────
# Skipped when EXPLICIT_SPEC_IDS populated CANDIDATE_FILES above.
mapfile -t ALL_FEATURE_IDS < <(spec_manifest_ids "$MANIFEST")

if [[ "$EXPLICIT_ID_MODE" == "true" ]]; then
  : # CANDIDATE_FILES already populated from explicit IDs; skip domain filter loop
else
for fid in "${ALL_FEATURE_IDS[@]}"; do
  # Check if this feature belongs to any matched domain
  feature_domains=$(spec_manifest_domains_for "$MANIFEST" "$fid")
  matched=false
  for fd in $feature_domains; do
    for md in "${MATCHED_DOMAINS[@]}"; do
      [[ "$fd" == "$md" ]] && matched=true && break 2
    done
  done
  [[ "$matched" != "true" ]] && continue

  # Resolve file path via registry
  spec_file=$(spec_file_for_id "$MANIFEST" "$fid")
  [[ -z "$spec_file" || ! -f "$spec_file" ]] && {
    echo "[resolve] Warning: $fid has no resolvable file, skipping" >&2
    continue
  }

  spec_check_crlf "$spec_file" 2>/dev/null || continue

  # Filter by kind if FILTER_KIND is set
  if [[ -n "${FILTER_KIND:-}" ]]; then
    spec_kind=$(fm "$spec_file" '.kind // ""')
    if [[ "$spec_kind" != "$FILTER_KIND" ]]; then
      continue
    fi
  fi

  # Only include APPROVED or ACTIVE states; DRAFT only if no unresolved conflicts
  state=$(fm "$spec_file" '.state // "UNKNOWN"')
  status=$(fm "$spec_file" '.status // "UNKNOWN"')
  if [[ "$state" == "APPROVED" || "$status" == "ACTIVE" ]]; then
    CANDIDATE_FILES+=("$spec_file")
    # Deprecation discipline (rules/deprecation-discipline.md):
    # When bundling a status:DEPRECATED + state:APPROVED spec, emit a tier
    # message on stderr so users see the deprecation signal during
    # /spec-resolve. Parity with work_check_spec_dep in work-lib.sh.
    if [[ "$status" == "DEPRECATED" && "$state" == "APPROVED" ]]; then
      # Source work-lib's emitter if available; fall back to a minimal
      # inline message if work-lib isn't on the path.
      if declare -F work_emit_deprecation_message >/dev/null 2>&1; then
        work_emit_deprecation_message "$PROJECT_ROOT" "$spec_file" "$fid" >&2
      elif [[ -f "$SCRIPT_DIR/work-lib.sh" ]]; then
        # shellcheck disable=SC1091
        source "$SCRIPT_DIR/work-lib.sh" 2>/dev/null || true
        if declare -F work_emit_deprecation_message >/dev/null 2>&1; then
          work_emit_deprecation_message "$PROJECT_ROOT" "$spec_file" "$fid" >&2
        else
          echo "[deprecation:ADVISORY] bundling DEPRECATED spec $fid" >&2
        fi
      else
        echo "[deprecation:ADVISORY] bundling DEPRECATED spec $fid" >&2
      fi
    fi
  elif [[ "$state" == "DRAFT" ]]; then
    # Check for unresolved conflict markers before including a DRAFT spec
    has_conflicts=false
    if grep -qE '\[UNRESOLVED\]' "$spec_file" 2>/dev/null; then
      has_conflicts=true
    elif grep -qE '\[CONFLICT\]' "$spec_file" 2>/dev/null; then
      has_conflicts=true
    elif [[ "$(fm "$spec_file" '.open_obligations | length // 0')" != "0" ]]; then
      has_conflicts=true
    fi
    if [[ "$has_conflicts" == "true" ]]; then
      CONFLICT_OMITTED+=("$fid")
      echo "[resolve] Excluding $fid — DRAFT with unresolved conflicts" >&2
    else
      CANDIDATE_FILES+=("$spec_file")
    fi
  fi
done
fi  # end: if EXPLICIT_ID_MODE else

# Collect INVALIDATED specs separately when requested (for revival detection)
INVALIDATED_FILES=()
if [[ "${INCLUDE_INVALIDATED:-}" == "true" ]]; then
  for fid in "${ALL_FEATURE_IDS[@]}"; do
    feature_domains=$(spec_manifest_domains_for "$MANIFEST" "$fid")
    matched=false
    for fd in $feature_domains; do
      for md in "${MATCHED_DOMAINS[@]}"; do
        [[ "$fd" == "$md" ]] && matched=true && break 2
      done
    done
    [[ "$matched" != "true" ]] && continue
    spec_file=$(spec_file_for_id "$MANIFEST" "$fid")
    [[ -z "$spec_file" || ! -f "$spec_file" ]] && continue
    spec_check_crlf "$spec_file" 2>/dev/null || continue
    state=$(fm "$spec_file" '.state // "UNKNOWN"')
    if [[ "$state" == "INVALIDATED" ]]; then
      INVALIDATED_FILES+=("$spec_file")
    fi
  done
  echo "[resolve] INVALIDATED specs found: ${#INVALIDATED_FILES[@]}" >&2
fi

echo "[resolve] Candidates: ${#CANDIDATE_FILES[@]} files" >&2

# ── Step 3: Sort by direct domain match first ────────────────────────────────
# No relevance_weight — direct matches before transitive requires
if [[ ${#CANDIDATE_FILES[@]} -gt 0 ]]; then
    SORTED_FILES=("${CANDIDATE_FILES[@]}")
else
    SORTED_FILES=()
fi

# ── Step 4: Expand transitive requires[], parent chain, optional siblings ───
declare -A SEEN_FILES
ALL_FILES=()

add_file() {
  local f="$1"
  [[ -n "${SEEN_FILES[$f]+x}" ]] && return
  SEEN_FILES["$f"]=1
  ALL_FILES+=("$f")
}

# Helper: given a spec ID, walk parents and add each to the bundle. Cross-cutting
# requirements at a parent are part of every child's contract, so when a child
# lands in candidates, the parent chain MUST be loaded too.
add_parent_chain() {
  local fid="$1"
  while IFS= read -r ancestor_id; do
    [[ -z "$ancestor_id" ]] && continue
    ancestor_file=$(spec_file_for_id "$MANIFEST" "$ancestor_id")
    if [[ -n "$ancestor_file" && -f "$ancestor_file" ]]; then
      spec_check_crlf "$ancestor_file" 2>/dev/null && add_file "$ancestor_file"
    else
      echo "[resolve] Warning: parent_spec $ancestor_id has no resolvable file" >&2
    fi
  done < <(spec_walk_parent_chain "$MANIFEST" "$fid")
}

# Helper: given a parent ID, add its children. Used by INCLUDE_SIBLINGS path.
add_siblings_via_parent() {
  local pid="$1"
  while IFS= read -r child_id; do
    [[ -z "$child_id" ]] && continue
    child_file=$(spec_file_for_id "$MANIFEST" "$child_id")
    if [[ -n "$child_file" && -f "$child_file" ]]; then
      spec_check_crlf "$child_file" 2>/dev/null && add_file "$child_file"
    fi
  done < <(spec_children_for "$MANIFEST" "$pid")
}

for f in "${SORTED_FILES[@]+"${SORTED_FILES[@]}"}"; do
  add_file "$f"
  this_id=$(fm "$f" '.id')
  this_parent=$(fm "$f" '.parent_spec // ""')

  # Parent chain: always include ancestors when a child is selected.
  if [[ -n "$this_id" ]]; then
    add_parent_chain "$this_id"
  fi

  # Siblings: opt-in via INCLUDE_SIBLINGS. When set, every child whose parent
  # is `this_parent` is added (we do this once per parent — dedup is via
  # add_file's SEEN_FILES guard).
  if [[ "${INCLUDE_SIBLINGS:-false}" == "true" && -n "$this_parent" && "$this_parent" != "null" ]]; then
    add_siblings_via_parent "$this_parent"
  fi

  while IFS= read -r req_id; do
    [[ -z "$req_id" ]] && continue
    req_file=$(spec_file_for_id "$MANIFEST" "$req_id")
    if [[ -n "$req_file" && -f "$req_file" ]]; then
      spec_check_crlf "$req_file" 2>/dev/null && add_file "$req_file"
    else
      echo "[resolve] Warning: requires $req_id has no resolvable file" >&2
    fi
  done < <(fm "$f" '.requires // [] | .[]')
done

# ── Step 5: Build bundle with token budget ───────────────────────────────────
# Order in ALL_FILES is direct matches first (Step 4 iterates SORTED_FILES
# before transitive expansions). When the very first direct match exceeds the
# budget, force-include it anyway: an empty bundle is the worst possible
# failure mode — callers downstream silently proceed without spec context. A
# single over-budget spec is recoverable; an empty bundle is invisible drift.
BUNDLE_PARTS=()
OMITTED=()
FORCED=()
PRIMARY_IDS=()
CONTEXT_IDS=()
RUNNING_TOKENS=0
HEADER_RESERVE=300

# Build a lookup of direct-match files for the at-least-one guarantee.
declare -A DIRECT_FILES
for d in "${SORTED_FILES[@]+"${SORTED_FILES[@]}"}"; do
  DIRECT_FILES["$d"]=1
done

for f in "${ALL_FILES[@]+"${ALL_FILES[@]}"}"; do
  section=$(machine_section "$f")
  spec_id=$(fm "$f" '.id')

  section_tokens=$(count_tokens "$section")
  over_budget=false
  (( RUNNING_TOKENS + section_tokens + HEADER_RESERVE > TOKEN_BUDGET )) && over_budget=true

  # Force-include the first direct-match spec when nothing else has fit yet,
  # so we never emit a bundle whose Feature Requirements section is empty.
  must_force=false
  if [[ "$over_budget" == "true" \
        && "${DIRECT_FILES[$f]+x}" == "x" \
        && ${#BUNDLE_PARTS[@]} -eq 0 ]]; then
    must_force=true
  fi

  if [[ "$over_budget" == "true" && "$must_force" == "false" ]]; then
    OMITTED+=("$spec_id")
    echo "[resolve] Over budget — omitting $spec_id (~$section_tokens tokens)" >&2
    continue
  fi

  BUNDLE_PARTS+=("$section")
  RUNNING_TOKENS=$(( RUNNING_TOKENS + section_tokens ))
  # Track primary (direct-match) vs context (transitively pulled —
  # parent chain, requires:, sibling expansion). spec-coverage uses
  # this to scope its gate: only primary-spec R-clauses are
  # gate-enforced; context rows are visible in the table but not
  # required to be annotated by this feature.
  if [[ "${DIRECT_FILES[$f]+x}" == "x" ]]; then
    PRIMARY_IDS+=("$spec_id")
  else
    CONTEXT_IDS+=("$spec_id")
  fi
  if [[ "$must_force" == "true" ]]; then
    FORCED+=("$spec_id")
    echo "[resolve] WARNING: $spec_id (~$section_tokens tokens) force-included over budget $TOKEN_BUDGET — bump --token-budget to suppress this warning" >&2
  fi
done

# ── Step 6: Load open obligations — domain-filtered ──────────────────────────
OBLIGATIONS_FILE="$SPEC_DIR/registry/_obligations.json"
MATCHED_DOMAINS_JSON=$(printf '%s\n' "${MATCHED_DOMAINS[@]}" | jq -R . | jq -sc .)
OBLIGATIONS=$(jq -r --argjson domains "$MATCHED_DOMAINS_JSON" '
  .obligations[]
  | select(.status == "open")
  | select(.domains[] as $d | $domains | index($d) != null)
  | "- [" + (.domains | join(", ")) + "] " + .description
    + " (target: " + .target_feature + ")"
' "$OBLIGATIONS_FILE" 2>/dev/null || echo "none")

# ── Step 7: Collect cross-references (decision_refs + kb_refs) ───────────────
CROSS_REFS=""
for f in "${ALL_FILES[@]+"${ALL_FILES[@]}"}"; do
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    CROSS_REFS+="- ADR: .decisions/$ref/adr.md"$'\n'
  done < <(fm "$f" '.decision_refs // [] | .[]')
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    CROSS_REFS+="- KB: .kb/$ref.md"$'\n'
  done < <(fm "$f" '.kb_refs // [] | .[]')
done

# ── Step 7b: Conflict detection ─────────────────────────────────────────────
# Check for invalidates cross-references and overlapping requirement subjects
# between included specs. Structural checks only — no semantic analysis.

CONFLICTS=""

# Build a map of included spec IDs for fast lookup
declare -A INCLUDED_IDS
for f in "${ALL_FILES[@]+"${ALL_FILES[@]}"}"; do
  sid=$(fm "$f" '.id')
  [[ -n "$sid" ]] && INCLUDED_IDS["$sid"]=1
done

# Check 1: invalidates cross-references within the bundle
for f in "${ALL_FILES[@]+"${ALL_FILES[@]}"}"; do
  src_id=$(fm "$f" '.id')
  while IFS= read -r inv_ref; do
    [[ -z "$inv_ref" ]] && continue
    # Strip trailing .RN to get the target spec ID. Works for both
    # FXX.RN (→ FXX) and domain.slug.RN (→ domain.slug).
    target_id=$(echo "$inv_ref" | sed -E 's/\.R[0-9]+[a-z]*(-[0-9]+[a-z]*)?$//')
    [[ -z "$target_id" ]] && continue
    if [[ -n "${INCLUDED_IDS[$target_id]+x}" ]]; then
      CONFLICTS+="INVALIDATES: $src_id invalidates $inv_ref, but $target_id is also in this bundle"$'\n'
    fi
  done < <(fm "$f" '.invalidates // [] | .[]')
done

# Check 2: overlapping requirement subjects with contradictory language.
# Single awk pass over all requirement lines from every included spec —
# replaces a per-token, per-antonym-pair bash subprocess fanout that took
# 30+ seconds on a single ~10K-token spec and hung indefinitely on multi-spec
# bundles. The output line format is byte-identical to the previous
# implementation; existing scenario-spec-resolve.sh tests are the contract.
CHECK2_CONFLICTS=$(
  {
    for f in "${ALL_FILES[@]+"${ALL_FILES[@]}"}"; do
      src_id=$(fm "$f" '.id')
      [[ -z "$src_id" ]] && continue
      machine_section "$f" \
        | awk -v sid="$src_id" '/^R[0-9]+\./ { print sid "\t" $0 }'
    done
  } | awk '
    BEGIN {
      # 16 antonym pairs — same set as the predecessor implementation.
      pairs[1]  = "must reject:must accept"
      pairs[2]  = "must accept:must reject"
      pairs[3]  = "must be null:must not be null"
      pairs[4]  = "must not be null:must be null"
      pairs[5]  = "must throw:must not throw"
      pairs[6]  = "must not throw:must throw"
      pairs[7]  = "must fail:must succeed"
      pairs[8]  = "must succeed:must fail"
      pairs[9]  = "must ignore:must require"
      pairs[10] = "must require:must ignore"
      pairs[11] = "is immutable:is mutable"
      pairs[12] = "is mutable:is immutable"
      pairs[13] = "must return null:must not return null"
      pairs[14] = "must not return null:must return null"
      pairs[15] = "must be empty:must not be empty"
      pairs[16] = "must not be empty:must be empty"
      npairs    = 16

      split("must should shall will when then that this with from into each have does been also only", swords, " ")
      for (i in swords) skip[swords[i]] = 1
    }

    {
      tab = index($0, "\t")
      if (tab == 0) next
      sid = substr($0, 1, tab - 1)
      line = substr($0, tab + 1)

      if (match(line, /^R[0-9]+/) == 0) next
      rid = substr(line, RSTART, RLENGTH)

      line_lower = tolower(line)
      delete seen_in_line

      s = line
      while (match(s, /[A-Z][a-zA-Z0-9]+|[a-z_][a-z_0-9]+/)) {
        tok = substr(s, RSTART, RLENGTH)
        s   = substr(s, RSTART + RLENGTH)

        if (length(tok) < 4) continue
        if (tok in skip) continue
        if (tok in seen_in_line) continue
        seen_in_line[tok] = 1

        if (tok in first_spec) {
          if (first_spec[tok] == sid) continue
          prev_lower = first_lower[tok]
          prev_full  = first_full[tok]
          for (p = 1; p <= npairs; p++) {
            ci = index(pairs[p], ":")
            pat_a = substr(pairs[p], 1, ci - 1)
            pat_b = substr(pairs[p], ci + 1)
            if (index(line_lower, pat_a) && index(prev_lower, pat_b)) {
              print "CONFLICT: " prev_full " references " tok "; " sid "." rid " also references " tok " with different semantics"
              break
            }
          }
        } else {
          first_spec[tok]  = sid
          first_lower[tok] = line_lower
          first_full[tok]  = sid "." rid
        }
      }
    }
  '
)
[[ -n "$CHECK2_CONFLICTS" ]] && CONFLICTS+="${CHECK2_CONFLICTS}"$'\n'

# ── Step 7c: Displacement detection ─────────────────────────────────────────
# When NEW_SPEC_FILES is set, check if new specs' requirements contradict
# existing APPROVED specs. Detection is mechanical: subject-token overlap
# combined with antonym pairs or displacement signal keywords.

DISPLACEMENTS=""

if [[ -n "${NEW_SPEC_FILES:-}" ]]; then
  IFS=':' read -ra NEW_FILES <<< "$NEW_SPEC_FILES"

  # Validate input files exist; collect (id, file) pairs that survive.
  NEW_PAIRS=()
  for new_file in "${NEW_FILES[@]}"; do
    if [[ ! -f "$new_file" ]]; then
      echo "[resolve] Warning: NEW_SPEC_FILES entry not found: $new_file" >&2
      continue
    fi
    new_id=$(fm "$new_file" '.id')
    [[ -z "$new_id" ]] && continue
    NEW_PAIRS+=("$new_id|$new_file")
  done

  # Single awk pass over (NEW reqs ∪ EXISTING reqs). Tag each line with its
  # provenance and let awk handle token extraction, overlap detection,
  # antonym matching and keyword matching in-process. Replaces a four-deep
  # bash loop that spawned tens of thousands of grep subprocesses per
  # (new-req × existing-req) pair.
  if (( ${#NEW_PAIRS[@]} > 0 )); then
    DISPLACEMENTS=$(
      {
        # Build the set of new-spec IDs so the existing-stream can skip any
        # spec that is itself one of the new specs (preserves the original
        # `[[ "$existing_id" == "$new_id" ]] && continue` guard).
        for pair in "${NEW_PAIRS[@]}"; do
          new_id="${pair%%|*}"
          new_file="${pair#*|}"
          machine_section "$new_file" \
            | awk -v sid="$new_id" '/^R[0-9]+\./ { print "NEW\t" sid "\t" $0 }'
        done
        for f in "${ALL_FILES[@]+"${ALL_FILES[@]}"}"; do
          ex_id=$(fm "$f" '.id')
          [[ -z "$ex_id" ]] && continue
          # Skip if ex_id is one of the new specs.
          skip_self=false
          for pair in "${NEW_PAIRS[@]}"; do
            [[ "${pair%%|*}" == "$ex_id" ]] && skip_self=true && break
          done
          [[ "$skip_self" == "true" ]] && continue
          machine_section "$f" \
            | awk -v sid="$ex_id" '/^R[0-9]+\./ { print "EXIST\t" sid "\t" $0 }'
        done
      } | awk '
        BEGIN {
          pairs[1]  = "must reject:must accept"
          pairs[2]  = "must accept:must reject"
          pairs[3]  = "must be null:must not be null"
          pairs[4]  = "must not be null:must be null"
          pairs[5]  = "must throw:must not throw"
          pairs[6]  = "must not throw:must throw"
          pairs[7]  = "must fail:must succeed"
          pairs[8]  = "must succeed:must fail"
          pairs[9]  = "must ignore:must require"
          pairs[10] = "must require:must ignore"
          pairs[11] = "is immutable:is mutable"
          pairs[12] = "is mutable:is immutable"
          pairs[13] = "must return null:must not return null"
          pairs[14] = "must not return null:must return null"
          pairs[15] = "must be empty:must not be empty"
          pairs[16] = "must not be empty:must be empty"
          npairs    = 16

          nkw = split("only support|replace|remove|eliminate|drop support|no longer|prohibit|must not support|exclusive", keywords, "|")

          split("must should shall will when then that this with from into each have does been also only", swords, " ")
          for (i in swords) skip[swords[i]] = 1

          n_new = 0
          n_exist = 0
        }

        # Parse "TAG\tSPECID\tLINE"
        function split_line(   t1, t2, tag, sid, rest) {
          t1 = index($0, "\t")
          tag = substr($0, 1, t1 - 1)
          rest = substr($0, t1 + 1)
          t2 = index(rest, "\t")
          sid = substr(rest, 1, t2 - 1)
          line = substr(rest, t2 + 1)
          ctx_tag = tag
          ctx_sid = sid
          ctx_line = line
        }

        # Extract requirement ID from a line into ctx_rid; return 1 on success.
        function extract_rid(   m) {
          if (match(ctx_line, /^R[0-9]+/) == 0) return 0
          ctx_rid = substr(ctx_line, RSTART, RLENGTH)
          return 1
        }

        # Extract subject tokens from ctx_line into the toks_out array
        # (1..count). Returns count.
        function tokens_from_line(toks_out,    s, n, tok) {
          n = 0
          delete dedup
          s = ctx_line
          while (match(s, /[A-Z][a-zA-Z0-9]+|[a-z_][a-z_0-9]+/)) {
            tok = substr(s, RSTART, RLENGTH)
            s   = substr(s, RSTART + RLENGTH)
            if (length(tok) < 4) continue
            if (tok in skip) continue
            if (tok in dedup) continue
            dedup[tok] = 1
            toks_out[++n] = tok
          }
          return n
        }

        {
          split_line()
          if (extract_rid() == 0) next

          if (ctx_tag == "NEW") {
            n_new++
            new_sid[n_new]   = ctx_sid
            new_rid[n_new]   = ctx_rid
            new_lower[n_new] = tolower(ctx_line)
            ntok = tokens_from_line(toks)
            new_ntoks[n_new] = ntok
            for (k = 1; k <= ntok; k++) {
              new_tok[n_new, k] = toks[k]
            }
          } else if (ctx_tag == "EXIST") {
            n_exist++
            ex_sid[n_exist]   = ctx_sid
            ex_rid[n_exist]   = ctx_rid
            ex_lower[n_exist] = tolower(ctx_line)
            etok = tokens_from_line(toks)
            ex_ntoks[n_exist] = etok
            for (k = 1; k <= etok; k++) {
              ex_tok[n_exist, k] = toks[k]
              # Index for fast lookup: which existing reqs use this token?
              key = ctx_sid SUBSEP toks[k]
              ex_byspec_tok[key] = 1
            }
          }
        }

        END {
          # For each new requirement, check every existing requirement for
          # token overlap + antonym/keyword signal. The original bash had no
          # token index either, so we keep the simple O(n_new × n_exist)
          # nested walk — but every step is in-process awk, not a subprocess.
          for (i = 1; i <= n_new; i++) {
            nlow = new_lower[i]
            nsid = new_sid[i]
            nrid = new_rid[i]
            ntoks = new_ntoks[i]

            for (j = 1; j <= n_exist; j++) {
              if (ex_sid[j] == nsid) continue   # never compare a spec to itself

              # Find first shared token (mirrors the bash break-2 short-circuit).
              shared = ""
              for (k = 1; k <= ntoks; k++) {
                key = ex_sid[j] SUBSEP new_tok[i, k]
                if (key in ex_byspec_tok) {
                  # Confirm the specific existing req (j) actually uses this token
                  for (m = 1; m <= ex_ntoks[j]; m++) {
                    if (ex_tok[j, m] == new_tok[i, k]) { shared = new_tok[i, k]; break }
                  }
                  if (shared != "") break
                }
              }
              if (shared == "") continue

              elow = ex_lower[j]
              signal = ""

              # Antonym pair check
              for (p = 1; p <= npairs; p++) {
                ci = index(pairs[p], ":")
                pat_a = substr(pairs[p], 1, ci - 1)
                pat_b = substr(pairs[p], ci + 1)
                if (index(nlow, pat_a) && index(elow, pat_b)) {
                  signal = "antonym: " pat_a " vs " pat_b
                  break
                }
              }

              # Keyword check (only if no antonym signal)
              if (signal == "") {
                for (q = 1; q <= nkw; q++) {
                  if (index(nlow, keywords[q])) {
                    signal = "keyword: " keywords[q]
                    break
                  }
                }
              }

              if (signal != "") {
                print "DISPLACED: " nsid "." nrid " → " ex_sid[j] "." ex_rid[j] " | subject: " shared " | signal: " signal
              }
            }
          }
        }
      '
    )
    if [[ -n "$DISPLACEMENTS" ]]; then
      DISPLACEMENTS+=$'\n'
      disp_count=$(echo -n "$DISPLACEMENTS" | grep -c '.')
      echo "[resolve] WARNING: $disp_count displacement(s) detected" >&2
    fi
  fi
fi

# ── Step 8: Emit bundle ─────────────────────────────────────────────────────
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [[ ${#OMITTED[@]} -gt 0 ]]; then
    OMITTED_STR="${OMITTED[*]}"
else
    OMITTED_STR="none"
fi
if [[ ${#CONFLICT_OMITTED[@]} -gt 0 ]]; then
    CONFLICT_OMITTED_STR="${CONFLICT_OMITTED[*]}"
else
    CONFLICT_OMITTED_STR="none"
fi
if [[ ${#FORCED[@]} -gt 0 ]]; then
    FORCED_STR="${FORCED[*]}"
else
    FORCED_STR="none"
fi
if [[ ${#PRIMARY_IDS[@]} -gt 0 ]]; then
    PRIMARY_STR="$(IFS=', '; echo "${PRIMARY_IDS[*]}")"
else
    PRIMARY_STR="none"
fi
if [[ ${#CONTEXT_IDS[@]} -gt 0 ]]; then
    CONTEXT_STR="$(IFS=', '; echo "${CONTEXT_IDS[*]}")"
else
    CONTEXT_STR="none"
fi

cat <<EOF
# Resolved Context Bundle
Generated: $TIMESTAMP
Feature request: $FEATURE_DESC
Domains matched: ${MATCHED_DOMAINS[*]}
Token budget: $TOKEN_BUDGET | Tokens used: ~$RUNNING_TOKENS
Omitted (budget): $OMITTED_STR
Force-included (over budget, kept to avoid empty bundle): $FORCED_STR
Omitted (DRAFT with unresolved conflicts): $CONFLICT_OMITTED_STR
Primary specs: $PRIMARY_STR
Context specs: $CONTEXT_STR

## Open Obligations (must be addressed in this feature)
${OBLIGATIONS:-none}

## Feature Requirements
$(if [[ ${#BUNDLE_PARTS[@]} -gt 0 ]]; then printf '%s\n\n---\n\n' "${BUNDLE_PARTS[@]}" | head -c -6; else echo "none"; fi)

## Cross-References
${CROSS_REFS:-none}
EOF

# Emit conflicts section only if conflicts were found
if [[ -n "$CONFLICTS" ]]; then
  echo ""
  echo "## Conflicts"
  echo ""
  echo -n "$CONFLICTS"
  conflict_count=$(echo -n "$CONFLICTS" | grep -c '.')
  echo "[resolve] WARNING: $conflict_count conflict(s) detected in bundle" >&2
fi

# Emit displacement section if detected
if [[ -n "$DISPLACEMENTS" ]]; then
  echo ""
  echo "## Displacement"
  echo ""
  echo -n "$DISPLACEMENTS"
  disp_count=$(echo -n "$DISPLACEMENTS" | grep -c '.')
  echo "[resolve] WARNING: $disp_count displacement(s) in bundle output" >&2
fi

# Emit INVALIDATED specs section if requested and found
if [[ "${INCLUDE_INVALIDATED:-}" == "true" && ${#INVALIDATED_FILES[@]} -gt 0 ]]; then
  echo ""
  echo "## INVALIDATED Specs (historical reference)"
  echo ""
  for f in "${INVALIDATED_FILES[@]}"; do
    inv_id=$(fm "$f" '.id')
    inv_reason=$(fm "$f" '.displacement_reason // "no reason recorded"')
    inv_displaced_by=$(fm "$f" '.displaced_by // [] | join(", ")')
    echo "- $inv_id — displaced by: ${inv_displaced_by:-unknown} — reason: $inv_reason"
  done
fi

echo "[resolve] Done. ~$RUNNING_TOKENS tokens across ${#BUNDLE_PARTS[@]} specs." >&2
