#!/usr/bin/env bash
# spec-coverage.sh — pipeline-wide spec-annotation coverage tracker
#
# Lifecycle of .feature/<slug>/spec-coverage.md:
#   feature-plan      → init   (extracts (spec, R) pairs from spec-bundle.md,
#                                writes table with all rows pending)
#   feature-test      → update (greps new test files for @spec, updates Test col)
#   feature-implement → update (greps new impl files for @spec, updates Impl col)
#   feature-pr        → gate   (refuses to draft if any row pending without waiver)
#   feature-retro     → report (counts loaded / annotated / waived for the summary)
#
# Subcommands:
#   init   <coverage-md> <bundle-md>
#   update <coverage-md> [--files <space-separated paths>] [--all]
#   gate   <coverage-md>
#   waive  <coverage-md> <spec-id>.<rid> "<reason>"
#   report <coverage-md>
#
# Conventions:
#   - The coverage table is the source of truth between pipeline stages.
#   - Cell values: `pending`, `<file>:<line>` (or comma-separated when multiple
#     locations), `waived: <reason>`.
#   - `init` is idempotent: re-running on an existing file preserves any
#     non-pending cells (so coverage already established by an earlier substage
#     survives a re-plan).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_cmds() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || { echo "ERROR: '$c' is required but not found." >&2; exit 1; }
  done
}
require_cmds awk grep sed

# Spec-id grammar shared with spec-trace.sh / spec-resolve.sh.
SPEC_ID_RE='(F[0-9]{2,}|[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+)'

usage() {
  cat <<'EOF' >&2
spec-coverage.sh — pipeline-wide spec-annotation coverage tracker

Usage:
  spec-coverage.sh init   <coverage-md> <bundle-md>
  spec-coverage.sh update <coverage-md> [--files <paths...>] [--all]
  spec-coverage.sh gate   <coverage-md>
  spec-coverage.sh waive  <coverage-md> <spec-id>.<rid> "<reason>"
  spec-coverage.sh report <coverage-md>
EOF
  exit 2
}

# ── Subcommand: init ─────────────────────────────────────────────────────────
# Parse the spec-resolve bundle for (spec-id, R-id) pairs and produce a
# coverage table where every requirement defaults to pending.
cmd_init() {
  local cov="${1:-}" bundle="${2:-}"
  [[ -z "$cov" || -z "$bundle" ]] && { echo "ERROR: init requires <coverage-md> <bundle-md>" >&2; exit 2; }
  [[ ! -f "$bundle" ]] && { echo "ERROR: bundle file not found: $bundle" >&2; exit 1; }

  # Preserve existing non-pending cells if cov already exists (idempotent re-plan).
  local existing_rows=""
  if [[ -f "$cov" ]]; then
    existing_rows=$(awk -F'|' '
      /^\| *[a-zA-Z0-9.-]+ *\| *R[0-9]+/ {
        gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $3)
        gsub(/^ +| +$/, "", $4); gsub(/^ +| +$/, "", $5)
        gsub(/^ +| +$/, "", $6)
        # store as: spec\tR\tTest\tImpl\tNotes
        print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6
      }' "$cov")
  fi

  # Extract (spec, R) pairs from the bundle. The spec-resolve bundle's
  # `## Feature Requirements` section contains one or more spec sections;
  # each starts with `# <spec-id>` (matching the SPEC_ID grammar) and
  # carries `R<n>.` requirement lines.
  local pairs
  pairs=$(awk -v re="^# $SPEC_ID_RE\$" '
    BEGIN { in_features = 0; cur_spec = "" }
    /^## Feature Requirements *$/ { in_features = 1; next }
    in_features && /^## / && !/^## Requirements *$/ { in_features = 0 }
    in_features && /^# / {
      if (match($0, re)) {
        cur_spec = substr($0, 3)
        sub(/[ \t]+$/, "", cur_spec)
      }
    }
    in_features && /^R[0-9]+[a-z]*(-[0-9]+[a-z]*)?\./ {
      if (cur_spec != "") {
        rid = $0
        sub(/\..*$/, "", rid)
        print cur_spec "\t" rid
      }
    }
  ' "$bundle")

  if [[ -z "$pairs" ]]; then
    # Empty bundle (no specs loaded) — write a header-only file so downstream
    # stages can still detect "no specs in scope" from a present-but-empty table.
    cat > "$cov" <<HEADER
# Spec Coverage

> **Managed by vallorcine pipeline. Do not hand-edit.**
> Updated by /feature-plan, /feature-test, /feature-implement, /feature-pr.

No specs loaded for this feature. Coverage gate is satisfied vacuously.
HEADER
    echo "[coverage] init: no specs in bundle — wrote vacuous coverage" >&2
    return 0
  fi

  {
    cat <<HEADER
# Spec Coverage

> **Managed by vallorcine pipeline. Do not hand-edit.**
> Updated by /feature-plan, /feature-test, /feature-implement, /feature-pr.
> Cell values: \`pending\`, \`<file>:<line>\` (multiple comma-separated), \`waived: <reason>\`.

| Spec | Req | Test | Impl | Notes |
|------|-----|------|------|-------|
HEADER
    while IFS=$'\t' read -r spec rid; do
      [[ -z "$spec" || -z "$rid" ]] && continue
      # Restore prior cell values for this row if present
      local prior
      prior=$(echo "$existing_rows" | awk -F'\t' -v s="$spec" -v r="$rid" '$1==s && $2==r {print $3 "\t" $4 "\t" $5; exit}')
      local test_cell="pending" impl_cell="pending" notes_cell=""
      if [[ -n "$prior" ]]; then
        IFS=$'\t' read -r test_cell impl_cell notes_cell <<<"$prior"
        [[ -z "$test_cell" ]] && test_cell="pending"
        [[ -z "$impl_cell" ]] && impl_cell="pending"
      fi
      printf '| %s | %s | %s | %s | %s |\n' "$spec" "$rid" "$test_cell" "$impl_cell" "$notes_cell"
    done <<<"$pairs"
  } > "$cov"

  local total
  total=$(echo "$pairs" | wc -l | tr -d ' ')
  echo "[coverage] init: wrote $total requirement rows to $cov" >&2
}

# ── Subcommand: update ───────────────────────────────────────────────────────
# Re-runs spec-trace.sh per spec mentioned in the table, then refreshes
# Test/Impl cells. With --files, restricts the trace to those paths (sets
# SPEC_TRACE_DIRS to their parent directories — best-effort scoping).
cmd_update() {
  local cov="${1:-}"
  shift || true
  [[ -z "$cov" ]] && { echo "ERROR: update requires <coverage-md>" >&2; exit 2; }
  [[ ! -f "$cov" ]] && { echo "ERROR: coverage file not found: $cov" >&2; exit 1; }

  local files_arg="" mode="all"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --files) shift; files_arg="${1:-}"; mode="files" ;;
      --all)   mode="all" ;;
      *) echo "ERROR: unknown update flag '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done

  # Vacuous coverage (no specs loaded) — nothing to update.
  if grep -q "^No specs loaded" "$cov"; then
    echo "[coverage] update: vacuous coverage (no specs) — no-op" >&2
    return 0
  fi

  # Locate project root the way spec-trace.sh does.
  local project_root="$PWD"
  while [[ "$project_root" != "/" ]]; do
    if [[ -d "$project_root/.spec" ]] || [[ -d "$project_root/.git" ]]; then
      break
    fi
    project_root="$(dirname "$project_root")"
  done

  # Best-effort directory scoping when --files is given.
  local trace_dirs=""
  if [[ "$mode" == "files" && -n "$files_arg" ]]; then
    declare -A dirs_seen
    for f in $files_arg; do
      local d="${f%/*}"
      [[ "$d" == "$f" ]] && d="."
      if [[ -z "${dirs_seen[$d]+x}" ]]; then
        dirs_seen[$d]=1
        trace_dirs+="${trace_dirs:+,}$d"
      fi
    done
  fi

  local specs
  specs=$(awk -F'|' '
    /^\| *[a-zA-Z0-9.-]+ *\| *R[0-9]+/ {
      gsub(/^ +| +$/, "", $2); print $2
    }' "$cov" | sort -u)

  # Build a lookup table of (spec, rid) -> "TEST_LOCS\tIMPL_LOCS".
  # Use a script-level variable + module-scoped trap so set -u doesn't fire
  # when the EXIT trap references it after the function returns.
  COVERAGE_LOCS_TSV=$(mktemp)
  trap 'rm -f "${COVERAGE_LOCS_TSV:-}"' EXIT
  local locs_tsv="$COVERAGE_LOCS_TSV"

  for spec in $specs; do
    [[ -z "$spec" ]] && continue
    # JSON output is most parseable; fall back gracefully if missing.
    local trace_json=""
    if [[ -n "$trace_dirs" ]]; then
      trace_json=$(SPEC_TRACE_DIRS="$trace_dirs" SPEC_TRACE_FORMAT=json \
        bash "$SCRIPT_DIR/spec-trace.sh" "$spec" "$project_root" 2>/dev/null) || trace_json=""
    else
      trace_json=$(SPEC_TRACE_FORMAT=json \
        bash "$SCRIPT_DIR/spec-trace.sh" "$spec" "$project_root" 2>/dev/null) || trace_json=""
    fi
    [[ -z "$trace_json" ]] && continue
    # Extract requirements with their test/impl arrays.
    echo "$trace_json" | awk -v spec="$spec" '
      /"[A-Za-z0-9.-]+\.R[0-9]+[a-z]*(-[0-9]+[a-z]*)?":/ {
        # current line is the start of a requirement entry
        rid = $0
        sub(/^[[:space:]]+"/, "", rid)
        sub(/":.*$/, "", rid)
        # rid currently looks like "<spec>.RN" — strip the spec prefix
        sub(/^.*\./, "R", rid); sub(/^RR/, "R", rid)
        # accumulate impl + test locations from the same line
        impl = ""
        test = ""
        if (match($0, /"implementation": \[[^]]*\]/)) {
          impl = substr($0, RSTART + length("\"implementation\": [") )
          sub(/\].*$/, "", impl)
          gsub(/"[ ,]*"/, ",", impl)
          gsub(/^"|"$/, "", impl)
        }
        if (match($0, /"test": \[[^]]*\]/)) {
          test = substr($0, RSTART + length("\"test\": [") )
          sub(/\].*$/, "", test)
          gsub(/"[ ,]*"/, ",", test)
          gsub(/^"|"$/, "", test)
        }
        gsub(/, +/, ",", test); gsub(/, +/, ",", impl)
        print spec "\t" rid "\t" test "\t" impl
      }
    ' >> "$locs_tsv"
  done

  # Rewrite the coverage table.
  local tmp
  tmp=$(mktemp)
  awk -v locs="$locs_tsv" '
    BEGIN {
      while ((getline ln < locs) > 0) {
        n = split(ln, parts, "\t")
        key = parts[1] FS parts[2]
        test_locs[key] = (n >= 3 ? parts[3] : "")
        impl_locs[key] = (n >= 4 ? parts[4] : "")
      }
      close(locs)
    }
    /^\| *[a-zA-Z0-9.-]+ *\| *R[0-9]+/ {
      n = split($0, c, "|")
      spec = c[2]; rid = c[3]
      gsub(/^ +| +$/, "", spec); gsub(/^ +| +$/, "", rid)
      key = spec FS rid

      cur_test = c[4]; cur_impl = c[5]
      gsub(/^ +| +$/, "", cur_test); gsub(/^ +| +$/, "", cur_impl)

      # Preserve waivers (manual override).
      new_test = (cur_test ~ /^waived:/) ? cur_test : (key in test_locs && test_locs[key] != "" ? test_locs[key] : "pending")
      new_impl = (cur_impl ~ /^waived:/) ? cur_impl : (key in impl_locs && impl_locs[key] != "" ? impl_locs[key] : "pending")

      notes = c[6]; gsub(/^ +| +$/, "", notes)
      printf("| %s | %s | %s | %s | %s |\n", spec, rid, new_test, new_impl, notes)
      next
    }
    { print }
  ' "$cov" > "$tmp" && mv "$tmp" "$cov"

  echo "[coverage] update: refreshed Test/Impl columns in $cov" >&2
}

# ── Subcommand: gate ─────────────────────────────────────────────────────────
# Exits 0 if every row has at least one annotation (Test or Impl) OR is waived.
# Exits 1 (with a list of pending rows on stdout) otherwise.
cmd_gate() {
  local cov="${1:-}"
  [[ -z "$cov" ]] && { echo "ERROR: gate requires <coverage-md>" >&2; exit 2; }
  [[ ! -f "$cov" ]] && { echo "ERROR: coverage file not found: $cov" >&2; exit 1; }

  if grep -q "^No specs loaded" "$cov"; then
    echo "[coverage] gate: vacuous coverage — pass" >&2
    return 0
  fi

  local pending
  pending=$(awk -F'|' '
    /^\| *[a-zA-Z0-9.-]+ *\| *R[0-9]+/ {
      spec = $2; rid = $3; t = $4; i = $5
      gsub(/^ +| +$/, "", spec); gsub(/^ +| +$/, "", rid)
      gsub(/^ +| +$/, "", t); gsub(/^ +| +$/, "", i)
      # Pending iff BOTH Test and Impl are pending and neither is waived.
      if (t == "pending" && i == "pending") {
        printf("%s.%s\n", spec, rid)
      }
    }' "$cov")

  if [[ -z "$pending" ]]; then
    echo "[coverage] gate: PASS — every loaded requirement has at least one @spec annotation or waiver" >&2
    return 0
  fi

  local count
  count=$(echo "$pending" | wc -l | tr -d ' ')
  echo "## Spec coverage gate failed"
  echo ""
  echo "The following $count requirement(s) have no \`@spec\` annotation in"
  echo "either tests or implementation. Add an annotation pointing to the"
  echo "enforcing site, or waive with documented reason:"
  echo ""
  echo "$pending" | sed 's/^/- /'
  echo ""
  echo "Waive a row:"
  echo "  bash .claude/scripts/spec-coverage.sh waive <coverage-md> <spec-id>.R<n> \"<reason>\""
  return 1
}

# ── Subcommand: waive ────────────────────────────────────────────────────────
cmd_waive() {
  local cov="${1:-}" target="${2:-}" reason="${3:-}"
  [[ -z "$cov" || -z "$target" || -z "$reason" ]] && {
    echo "ERROR: waive requires <coverage-md> <spec-id>.<rid> \"<reason>\"" >&2; exit 2; }
  [[ ! -f "$cov" ]] && { echo "ERROR: coverage file not found: $cov" >&2; exit 1; }

  local target_spec="${target%.R*}"
  local target_rid="R${target##*.R}"
  if [[ "$target_spec" == "$target" || -z "$target_rid" ]]; then
    echo "ERROR: waive target must look like '<spec-id>.R<n>' (e.g. auth.token-validation.R3)" >&2
    exit 2
  fi

  local tmp
  tmp=$(mktemp)
  awk -F'|' -v ts="$target_spec" -v tr="$target_rid" -v rsn="$reason" '
    /^\| *[a-zA-Z0-9.-]+ *\| *R[0-9]+/ {
      spec = $2; rid = $3
      gsub(/^ +| +$/, "", spec); gsub(/^ +| +$/, "", rid)
      if (spec == ts && rid == tr) {
        # Waive both Test and Impl cells; preserve notes column verbatim.
        notes = $6; sub(/^ +/, "", notes); sub(/ +$/, "", notes)
        printf("| %s | %s | waived: %s | waived: %s | %s |\n", ts, tr, rsn, rsn, notes)
        matched = 1
        next
      }
    }
    { print }
    END { if (!matched) exit 3 }
  ' "$cov" > "$tmp"
  local rc=$?
  if (( rc == 3 )); then
    rm -f "$tmp"
    echo "ERROR: row '$target' not found in $cov" >&2
    exit 1
  fi
  mv "$tmp" "$cov"
  echo "[coverage] waive: $target — $reason" >&2
}

# ── Subcommand: report ───────────────────────────────────────────────────────
cmd_report() {
  local cov="${1:-}"
  [[ -z "$cov" ]] && { echo "ERROR: report requires <coverage-md>" >&2; exit 2; }
  [[ ! -f "$cov" ]] && { echo "ERROR: coverage file not found: $cov" >&2; exit 1; }

  if grep -q "^No specs loaded" "$cov"; then
    echo "Spec coverage: vacuous (no specs loaded for this feature)"
    return 0
  fi

  awk -F'|' '
    /^\| *[a-zA-Z0-9.-]+ *\| *R[0-9]+/ {
      total++
      t = $4; i = $5
      gsub(/^ +| +$/, "", t); gsub(/^ +| +$/, "", i)
      if (t ~ /^waived:/ || i ~ /^waived:/) waived++
      else if (t != "pending" || i != "pending") covered++
      else pending++
    }
    END {
      total = total + 0
      printf("Spec coverage: %d loaded · %d annotated · %d waived · %d pending\n",
             total, covered+0, waived+0, pending+0)
    }
  ' "$cov"
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
sub="${1:-}"
shift || true
case "$sub" in
  init)   cmd_init   "$@" ;;
  update) cmd_update "$@" ;;
  gate)   cmd_gate   "$@" ;;
  waive)  cmd_waive  "$@" ;;
  report) cmd_report "$@" ;;
  ""|-h|--help|help) usage ;;
  *) echo "ERROR: unknown subcommand '$sub'" >&2; usage ;;
esac
