#!/usr/bin/env bash
# spec-validate.sh — structural validation for spec files
# Usage: spec-validate.sh <spec-file>
# Exit 0 = PASS | Exit 1 = FAIL (prints all errors before exiting)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/spec-lib.sh"

spec_require_deps

FILE="${1:-}"
[[ -z "$FILE" ]] && { echo "Usage: spec-validate.sh <spec-file>" >&2; exit 1; }
[[ ! -f "$FILE" ]] && { echo "ERROR: File not found: $FILE" >&2; exit 1; }

# Locate .spec/ and project root
SPEC_DIR="$(spec_find_root)" || exit 1
PROJECT_ROOT="$(dirname "$SPEC_DIR")"
MANIFEST="$SPEC_DIR/registry/manifest.json"
ERRORS=()

# ── CRLF check first — all other checks are meaningless if CRLF present
if ! spec_check_crlf "$FILE"; then
  echo "FAIL: $FILE"
  echo "  CRLF line endings corrupt all parsing — fix before re-running"
  exit 1
fi

# ── Check 1: Front matter is valid JSON
raw_fm=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$FILE")
if [[ -z "$raw_fm" ]]; then
  ERRORS+=("No front matter found between --- delimiters")
elif ! echo "$raw_fm" | jq . >/dev/null 2>&1; then
  ERRORS+=("Front matter is not valid JSON")
fi

# Only continue field checks if JSON is valid
if [[ ${#ERRORS[@]} -eq 0 ]]; then

  # ── Check 2: Required fields present
  for field in id version status state domains; do
    val=$(fm "$FILE" ".${field} // \"__missing__\"")
    [[ "$val" == "__missing__" ]] && ERRORS+=("Missing required field: $field")
  done

  # ── Check 3: state is valid enum
  STATE=$(fm "$FILE" '.state // ""')
  [[ ! "$STATE" =~ ^(DRAFT|APPROVED|INVALIDATED)$ ]] && \
    ERRORS+=("Invalid state: '$STATE' — must be DRAFT|APPROVED|INVALIDATED")

  # ── Check 4: status is valid enum
  STATUS=$(fm "$FILE" '.status // ""')
  [[ ! "$STATUS" =~ ^(DRAFT|ACTIVE|STABLE|DEPRECATED)$ ]] && \
    ERRORS+=("Invalid status: '$STATUS' — must be DRAFT|ACTIVE|STABLE|DEPRECATED")

  # ── Check 4b: kind is valid enum (optional field)
  KIND=$(fm "$FILE" '.kind // ""')
  if [[ -n "$KIND" && ! "$KIND" =~ ^(interface-contract)$ ]]; then
    ERRORS+=("Invalid kind: '$KIND' — must be interface-contract (or omit field)")
  fi

  # ── Check 5: domains is a non-empty array
  DOMAIN_COUNT=$(fm "$FILE" '.domains | length // 0')
  [[ "$DOMAIN_COUNT" == "0" ]] && ERRORS+=("domains array is empty — at least one domain required")

  # ── Check 6: requires[] IDs resolve via registry
  if [[ -f "$MANIFEST" ]]; then
    while IFS= read -r req_id; do
      [[ -z "$req_id" ]] && continue
      req_file=$(spec_file_for_id "$MANIFEST" "$req_id")
      if [[ -z "$req_file" || ! -f "$req_file" ]]; then
        ERRORS+=("Unresolvable requires ID: $req_id (not in registry)")
      fi
    done < <(fm "$FILE" '.requires // [] | .[]')
  else
    echo "[validate] Warning: manifest not found, skipping requires check" >&2
  fi

  # ── Spec ID format patterns (legacy FXX or domain.slug, optionally nested) ──
  # Spec ID alone:           F01  OR  schema.field-access  OR
  #                          encryption.primitives-lifecycle.key-rotation
  # Spec requirement ref:    F01.R3  OR  schema.field-access.R3  OR
  #                          encryption.primitives-lifecycle.key-rotation.R3
  #                          (letter-suffix RNs like R51a are supported;
  #                           multi-dot IDs are nested specs.)
  spec_id_re='^(F[0-9]+|[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+)$'
  spec_ref_re='^(F[0-9]+|[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+)\.R[0-9]+[a-z]*(-[0-9]+[a-z]*)?$'

  # ── Check 7: invalidates[] format AND target existence
  while IFS= read -r inv; do
    [[ -z "$inv" ]] && continue
    if ! echo "$inv" | grep -qE "$spec_ref_re"; then
      ERRORS+=("Invalid invalidates format: '$inv' (expected FXX.RN or domain.slug.RN, e.g. F01.R3 or schema.field-access.R3)")
    elif [[ -f "$MANIFEST" ]]; then
      inv_err=$(spec_invalidates_check "$MANIFEST" "$inv" 2>&1 || true)
      if [[ -n "$inv_err" ]]; then
        ERRORS+=("$inv_err")
      fi
    fi
  done < <(fm "$FILE" '.invalidates // [] | .[]')

  # ── Check 7b: displaced_by[] IDs resolve via registry (optional field)
  while IFS= read -r dby; do
    [[ -z "$dby" ]] && continue
    if ! echo "$dby" | grep -qE "$spec_id_re"; then
      ERRORS+=("Invalid displaced_by format: '$dby' (expected FXX or domain.slug, e.g. F05 or schema.field-access)")
    elif [[ -f "$MANIFEST" ]]; then
      dby_file=$(spec_file_for_id "$MANIFEST" "$dby")
      if [[ -z "$dby_file" || ! -f "$dby_file" ]]; then
        ERRORS+=("Unresolvable displaced_by ID: $dby (not in registry)")
      fi
    fi
  done < <(fm "$FILE" '.displaced_by // [] | .[]')

  # ── Check 7c: revives[] IDs must be INVALIDATED specs
  while IFS= read -r rev; do
    [[ -z "$rev" ]] && continue
    if ! echo "$rev" | grep -qE "$spec_id_re"; then
      ERRORS+=("Invalid revives format: '$rev' (expected FXX or domain.slug)")
    elif [[ -f "$MANIFEST" ]]; then
      rev_file=$(spec_file_for_id "$MANIFEST" "$rev")
      if [[ -z "$rev_file" || ! -f "$rev_file" ]]; then
        ERRORS+=("Unresolvable revives ID: $rev (not in registry)")
      else
        rev_state=$(fm "$rev_file" '.state // ""')
        if [[ "$rev_state" != "INVALIDATED" ]]; then
          ERRORS+=("revives '$rev' has state '$rev_state' — must be INVALIDATED")
        fi
      fi
    fi
  done < <(fm "$FILE" '.revives // [] | .[]')

  # ── Check 7d: revived_by[] IDs resolve via registry (optional field)
  while IFS= read -r rby; do
    [[ -z "$rby" ]] && continue
    if ! echo "$rby" | grep -qE "$spec_id_re"; then
      ERRORS+=("Invalid revived_by format: '$rby' (expected FXX or domain.slug)")
    elif [[ -f "$MANIFEST" ]]; then
      rby_file=$(spec_file_for_id "$MANIFEST" "$rby")
      if [[ -z "$rby_file" || ! -f "$rby_file" ]]; then
        ERRORS+=("Unresolvable revived_by ID: $rby (not in registry)")
      fi
    fi
  done < <(fm "$FILE" '.revived_by // [] | .[]')

  # ── Check 7f: parent_spec resolves + ID-prefix consistency + acyclic ────────
  # parent_spec is a single-string field. When set:
  #   1. The parent must exist in the manifest.
  #   2. The child's ID must be the parent's ID + "." + a single hierarchical
  #      segment (so encryption.primitives-lifecycle.key-rotation may declare
  #      encryption.primitives-lifecycle as parent, but NOT encryption.foo).
  #   3. The chain walked via parent_spec MUST be acyclic. spec_walk_parent_chain
  #      surfaces any cycle on stderr; we verify by counting hops vs depth cap.
  PARENT_SPEC=$(fm "$FILE" '.parent_spec // ""')
  if [[ -n "$PARENT_SPEC" && "$PARENT_SPEC" != "null" ]]; then
    # Format check
    if ! echo "$PARENT_SPEC" | grep -qE "$spec_id_re"; then
      ERRORS+=("Invalid parent_spec format: '$PARENT_SPEC' (expected FXX or domain.slug[.subdomain...])")
    elif [[ -f "$MANIFEST" ]]; then
      # Existence check
      par_file=$(spec_file_for_id "$MANIFEST" "$PARENT_SPEC")
      if [[ -z "$par_file" || ! -f "$par_file" ]]; then
        ERRORS+=("Unresolvable parent_spec: $PARENT_SPEC (not in registry)")
      else
        # ID-prefix check: child ID must be parent ID + "." + one segment
        SELF_ID=$(fm "$FILE" '.id // ""')
        if [[ -n "$SELF_ID" ]]; then
          expected_prefix="${PARENT_SPEC}."
          if [[ "$SELF_ID" != ${expected_prefix}* ]]; then
            ERRORS+=("ID prefix mismatch: '$SELF_ID' must start with '$expected_prefix' to declare parent_spec '$PARENT_SPEC'")
          else
            # Trailing portion after the prefix must be a single hierarchical
            # segment (one or more lowercase-hyphenated words separated by dots
            # is valid for grandchildren — actually, wait, exactly one segment
            # for an immediate parent). We enforce ONE segment because
            # parent_spec is the *immediate* parent.
            tail_part="${SELF_ID#${expected_prefix}}"
            if [[ "$tail_part" == *.* ]]; then
              ERRORS+=("ID-segment mismatch: '$SELF_ID' has more than one segment beyond parent_spec '$PARENT_SPEC' — parent_spec must point to the IMMEDIATE parent (e.g. for a.b.c.d, parent_spec must be a.b.c, not a.b)")
            elif [[ -z "$tail_part" ]]; then
              ERRORS+=("ID equals parent_spec — '$SELF_ID' cannot declare itself as its own parent")
            fi
          fi
        fi
        # Acyclic check: walk the chain; spec_walk_parent_chain emits an
        # error to stderr if it detects a cycle or exceeds depth.
        chain_err=$(spec_walk_parent_chain "$MANIFEST" "$SELF_ID" 2>&1 >/dev/null || true)
        if echo "$chain_err" | grep -q "ERROR:"; then
          ERRORS+=("parent_spec chain invalid for '$SELF_ID': $(echo "$chain_err" | head -1 | sed 's/^\[spec-lib\] //')")
        fi
      fi
    fi
  fi

  # ── Check 7e: displacement_reason present when displaced_by is non-empty (warning)
  DISPLACED_BY_COUNT=$(fm "$FILE" '.displaced_by // [] | length')
  if [[ "$DISPLACED_BY_COUNT" != "0" && "$DISPLACED_BY_COUNT" != "null" ]]; then
    DISP_REASON=$(fm "$FILE" '.displacement_reason // ""')
    if [[ -z "$DISP_REASON" ]]; then
      echo "  WARN: displaced_by is non-empty but displacement_reason is missing" >&2
    fi
  fi

  # ── Check 7f: status:DEPRECATED requires the deprecation discipline contract
  #
  # When status:DEPRECATED is set, the spec is asserting "still load-bearing
  # but alternative exists." That assertion requires:
  #   - state:APPROVED (or state:INVALIDATED for the terminal phase — no
  #     extra fields enforced there)
  #   - non-empty displaced_by (the alternative)
  #   - each displaced_by target is state:APPROVED and not status:DEPRECATED
  #   - displacement_reason (the rationale)
  #   - removal_scheduled_in (semver string, > current VERSION)
  #   - deprecation_date (ISO date)
  #
  # See designs/deprecated-state.md and rules/deprecation-discipline.md.
  if [[ "$STATUS" == "DEPRECATED" ]]; then

    # 7f.1 — state must be APPROVED (load-bearing) or INVALIDATED (terminal)
    if [[ "$STATE" != "APPROVED" && "$STATE" != "INVALIDATED" ]]; then
      ERRORS+=("status:DEPRECATED requires state:APPROVED (load-bearing) or state:INVALIDATED (retired); got state:$STATE")
    fi

    # The required-fields contract applies during the APPROVED phase only.
    # Once INVALIDATED, the fields were enforced previously and may have
    # carried forward — they're informational, not gated.
    if [[ "$STATE" == "APPROVED" ]]; then

      # 7f.2 — declare deprecation MODE: succession (displaced_by non-empty)
      # OR retirement (retirement: true, no successor). Mutually exclusive.
      RETIREMENT=$(fm "$FILE" '.retirement // ""')
      DISPLACED_NONEMPTY=false
      if [[ "$DISPLACED_BY_COUNT" != "0" && "$DISPLACED_BY_COUNT" != "null" ]]; then
        DISPLACED_NONEMPTY=true
      fi
      RETIREMENT_TRUE=false
      if [[ "$RETIREMENT" == "true" ]]; then
        RETIREMENT_TRUE=true
      fi

      if $DISPLACED_NONEMPTY && $RETIREMENT_TRUE; then
        ERRORS+=("status:DEPRECATED has BOTH displaced_by AND retirement:true — these are mutually exclusive. Succession mode uses displaced_by; retirement mode uses retirement:true. Pick one.")
      elif ! $DISPLACED_NONEMPTY && ! $RETIREMENT_TRUE; then
        ERRORS+=("status:DEPRECATED requires either non-empty displaced_by (succession mode: alternative exists) OR retirement:true (retirement mode: no successor, code path going away). Declare your intent.")
      elif $DISPLACED_NONEMPTY; then
        # 7f.3 — succession mode: each displaced_by target must be
        # state:APPROVED and not status:DEPRECATED
        if [[ -f "$MANIFEST" ]]; then
          while IFS= read -r dby; do
            [[ -z "$dby" ]] && continue
            dby_file=$(spec_file_for_id "$MANIFEST" "$dby")
            [[ -z "$dby_file" || ! -f "$dby_file" ]] && continue  # 7b already flagged
            dby_state=$(fm "$dby_file" '.state // ""')
            dby_status=$(fm "$dby_file" '.status // ""')
            if [[ "$dby_state" != "APPROVED" ]]; then
              ERRORS+=("displaced_by target '$dby' has state:$dby_state — must be state:APPROVED to displace a DEPRECATED spec (alternative must be live)")
            fi
            if [[ "$dby_status" == "DEPRECATED" ]]; then
              ERRORS+=("displaced_by target '$dby' is itself status:DEPRECATED — chain deprecations create confusion; point directly to the live successor")
            fi
          done < <(fm "$FILE" '.displaced_by // [] | .[]')
        fi
      fi
      # else: retirement mode — no target validation needed

      # 7f.4 — displacement_reason required
      DISP_REASON_NOW=$(fm "$FILE" '.displacement_reason // ""')
      if [[ -z "$DISP_REASON_NOW" ]]; then
        ERRORS+=("status:DEPRECATED requires displacement_reason (one-line rationale; often 'superseded by <displaced_by[0]>')")
      fi

      # 7f.5 — removal_scheduled_in required, semver, > current VERSION
      RSI=$(fm "$FILE" '.removal_scheduled_in // ""')
      if [[ -z "$RSI" ]]; then
        ERRORS+=("status:DEPRECATED requires removal_scheduled_in (semver version string, e.g. '0.23.0', must be > current VERSION)")
      else
        # Semver pattern: X.Y.Z optionally followed by -prerelease or +build
        semver_re='^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$'
        if ! [[ "$RSI" =~ $semver_re ]]; then
          ERRORS+=("removal_scheduled_in '$RSI' is not a well-formed semver (expected X.Y.Z or X.Y.Z-suffix)")
        elif [[ -f "$PROJECT_ROOT/VERSION" ]]; then
          CUR_VERSION=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null | tr -d '[:space:]')
          if [[ -n "$CUR_VERSION" ]]; then
            # Use sort -V for semver comparison; sort -uV with both values
            # and check if RSI comes after CUR_VERSION. If equal, that's
            # already "removal version reached" — disallow at marking time.
            if [[ "$RSI" == "$CUR_VERSION" ]]; then
              ERRORS+=("removal_scheduled_in '$RSI' equals current VERSION — must be strictly greater (schedule a future version)")
            else
              sorted=$(printf '%s\n%s\n' "$CUR_VERSION" "$RSI" | sort -V | head -1)
              if [[ "$sorted" != "$CUR_VERSION" ]]; then
                # current sorts AFTER scheduled — means scheduled is in the past
                ERRORS+=("removal_scheduled_in '$RSI' is below current VERSION '$CUR_VERSION' — must be strictly greater")
              fi
            fi
          fi
        fi
      fi

      # 7f.6 — deprecation_date required, ISO format
      DEP_DATE=$(fm "$FILE" '.deprecation_date // ""')
      if [[ -z "$DEP_DATE" ]]; then
        ERRORS+=("status:DEPRECATED requires deprecation_date (ISO date, e.g. '2026-05-17')")
      elif ! [[ "$DEP_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        ERRORS+=("deprecation_date '$DEP_DATE' is not a valid ISO date (expected YYYY-MM-DD)")
      fi
    fi
  fi

  # ── Check 7g: status:DEPRECATED cannot apply to a state:DRAFT spec
  #
  # Deprecation means "load-bearing AND has alternative." A DRAFT spec
  # isn't load-bearing yet, so it can't be deprecated. If you no longer
  # want a DRAFT spec, delete it or transition DRAFT → INVALIDATED
  # directly with displacement_reason.
  if [[ "$STATUS" == "DEPRECATED" && "$STATE" == "DRAFT" ]]; then
    ERRORS+=("status:DEPRECATED on a state:DRAFT spec is not allowed — deprecation requires the spec to have been load-bearing (state:APPROVED) at some point")
  fi

  # ── Check 7i: code-marker presence for status:DEPRECATED + state:APPROVED
  #
  # Code carrying behavior governed by a DEPRECATED spec SHOULD have a
  # code-level deprecation marker (Java @Deprecated, Rust #[deprecated],
  # Python warnings.warn, Go // Deprecated:, TS @deprecated, etc.).
  #
  # The kit performs a loose grep-based check: for each @spec annotation
  # referencing this spec in the codebase, check whether the same file
  # contains "deprecat" (case-insensitive substring covering all common
  # language conventions). Emit WARNING per file lacking the marker —
  # NEVER block the validation.
  #
  # This is intentionally loose. Per-language strict checks are out of
  # scope for v1 — a future enhancement reads .feature/project-config.md
  # for per-language patterns. The substring "deprecat" catches the
  # 5 common languages cheaply.
  #
  # Skipped when:
  #   - $PROJECT_ROOT/.git doesn't exist (test/sandbox environments)
  #   - the spec is not status:DEPRECATED + state:APPROVED (terminal
  #     phase doesn't care about markers anymore)
  if [[ "$STATUS" == "DEPRECATED" && "$STATE" == "APPROVED" ]]; then
    SELF_ID_CM=$(fm "$FILE" '.id // ""')
    if [[ -n "$SELF_ID_CM" && -d "$PROJECT_ROOT/.git" ]]; then
      # Find files annotated with @spec <SELF_ID_CM> (with or without R-clause).
      # Use git grep for speed; fall back to grep -r if not a git repo.
      annotation_re="@spec[[:space:]]+${SELF_ID_CM//./\\.}"
      annotated_files=$(cd "$PROJECT_ROOT" && git grep -l -E "$annotation_re" 2>/dev/null || true)
      if [[ -n "$annotated_files" ]]; then
        while IFS= read -r afile; do
          [[ -z "$afile" ]] && continue
          [[ "$afile" == *"$FILE"* ]] && continue  # skip the spec file itself
          # Check for any case-insensitive substring of "deprecat" in the file
          if ! grep -qi "deprecat" "$PROJECT_ROOT/$afile" 2>/dev/null; then
            echo "  WARN: code file '$afile' carries @spec $SELF_ID_CM annotation but no deprecation marker (no 'deprecat*' substring found) — consider adding language-appropriate marker (Java @Deprecated, Rust #[deprecated], Python warnings.warn, Go // Deprecated:, TS @deprecated)" >&2
          fi
        done <<< "$annotated_files"
      fi
    fi
  fi

  # ── Check 7h: audit-trail-before-deletion contract
  #
  # When state:INVALIDATED AND the spec was previously DEPRECATED (either
  # mode), the kit requires three artifacts to land alongside this
  # transition so the removed work is forensically recoverable:
  #   1. displacement_reason
  #   2. reproducer frontmatter — type + path; path must exist
  #   3. KB archaeology article at .kb/_legacy/<spec-id>.md
  #
  # "Was previously DEPRECATED" is detected via:
  #   - displaced_by non-empty (succession mode marker carried forward), OR
  #   - retirement: true (retirement mode marker carried forward)
  #
  # Specs invalidated WITHOUT either marker (direct retire that never went
  # through DEPRECATED) bypass this check.
  #
  # See designs/deprecated-state.md §"Audit-trail-before-deletion contract".
  INV_RETIREMENT=$(fm "$FILE" '.retirement // ""')
  INV_RETIREMENT_TRUE=false
  [[ "$INV_RETIREMENT" == "true" ]] && INV_RETIREMENT_TRUE=true
  INV_HAS_DISPLACED=false
  [[ "$DISPLACED_BY_COUNT" != "0" && "$DISPLACED_BY_COUNT" != "null" ]] && INV_HAS_DISPLACED=true
  if [[ "$STATE" == "INVALIDATED" ]] && ($INV_HAS_DISPLACED || $INV_RETIREMENT_TRUE); then

    # 7h.1 — displacement_reason required (promote 7e warning to error)
    DISP_REASON_INV=$(fm "$FILE" '.displacement_reason // ""')
    if [[ -z "$DISP_REASON_INV" ]]; then
      ERRORS+=("INVALIDATED spec with displaced_by requires displacement_reason (audit-trail-before-deletion contract)")
    fi

    # 7h.2 — reproducer frontmatter (type + path)
    REPRO_TYPE=$(fm "$FILE" '.reproducer.type // ""')
    REPRO_PATH=$(fm "$FILE" '.reproducer.path // ""')
    if [[ -z "$REPRO_TYPE" || -z "$REPRO_PATH" ]]; then
      ERRORS+=("INVALIDATED spec with displaced_by requires reproducer frontmatter (type + path) — see audit-trail-before-deletion contract")
    elif [[ ! -e "$PROJECT_ROOT/$REPRO_PATH" ]]; then
      ERRORS+=("reproducer path does not exist: $REPRO_PATH (relative to project root)")
    fi

    # 7h.3 — KB archaeology article at .kb/_legacy/<spec-id>.md
    SELF_ID=$(fm "$FILE" '.id // ""')
    if [[ -n "$SELF_ID" ]]; then
      # Default path: .kb/_legacy/<spec-id>.md (dot-separated ID kept as-is)
      KB_LEGACY_PATH="$PROJECT_ROOT/.kb/_legacy/${SELF_ID}.md"
      if [[ ! -f "$KB_LEGACY_PATH" ]]; then
        ERRORS+=("missing KB archaeology article: .kb/_legacy/${SELF_ID}.md (audit-trail-before-deletion contract requires forensic record of removed contracts)")
      else
        # 7h.4 — KB article frontmatter sanity check
        KB_TYPE=$(fm "$KB_LEGACY_PATH" '.type // ""')
        KB_SPEC_REF=$(fm "$KB_LEGACY_PATH" '.spec_ref // ""')
        if [[ "$KB_TYPE" != "legacy-archaeology" ]]; then
          ERRORS+=("KB article $KB_LEGACY_PATH missing type:legacy-archaeology (got '$KB_TYPE')")
        fi
        if [[ "$KB_SPEC_REF" != "$SELF_ID" ]]; then
          ERRORS+=("KB article $KB_LEGACY_PATH spec_ref ('$KB_SPEC_REF') does not match this spec's ID ('$SELF_ID')")
        fi
      fi
    fi
  fi

  # ── Check 8: decision_refs resolve (warning, not error)
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    spec_decision_ref_check "$PROJECT_ROOT" "$ref" 2>&1 || true
  done < <(fm "$FILE" '.decision_refs // [] | .[]')

  # ── Check 9: kb_refs resolve (warning, not error)
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    spec_kb_ref_check "$PROJECT_ROOT" "$ref" 2>&1 || true
  done < <(fm "$FILE" '.kb_refs // [] | .[]')

  # ── Check 9b: APPROVED specs must not have unresolved conflict markers
  # Use here-strings (not `echo "$var" | grep`) so SIGPIPE under pipefail
  # cannot flip the result on very large machine sections — observed at
  # 134 KB on encryption.primitives-lifecycle in jlsm.
  if [[ "$STATE" == "APPROVED" ]]; then
    spec_body=$(machine_section "$FILE")
    if grep -qE '\[UNRESOLVED\]' <<< "$spec_body" 2>/dev/null; then
      ERRORS+=("APPROVED spec has [UNRESOLVED] markers — should be DRAFT")
    fi
    if grep -qE '\[CONFLICT\]' <<< "$spec_body" 2>/dev/null; then
      ERRORS+=("APPROVED spec has [CONFLICT] markers — should be DRAFT")
    fi
  fi

fi  # end JSON-valid block

# ── Check 10: human narrative separator exists after requirements
# Count --- occurrences — need at least 3 (open FM, close FM, narrative separator)
delim_count=$(grep -c '^---$' "$FILE" || true)
if (( delim_count < 3 )); then
  ERRORS+=("Missing human narrative separator — need 3x '---' lines, found $delim_count")
fi

# ── Check 11: numbered requirements exist in machine section
# Here-string instead of pipe — see 9b above for SIGPIPE rationale.
machine=$(machine_section "$FILE")
if ! grep -qE '^R[0-9]+[a-z]*(-[0-9]+[a-z]*)?\.' <<< "$machine"; then
  ERRORS+=("No numbered requirements found in machine section (expected R1. R2. format)")
fi

# ── Report
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "FAIL: $FILE"
  for err in "${ERRORS[@]}"; do
    echo "  $err"
  done
  exit 1
else
  echo "PASS: $FILE"
  exit 0
fi
