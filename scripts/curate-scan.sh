#!/usr/bin/env bash
# vallorcine curation scanner
# Scans git history and correlates against KB/ADR/feature artifacts to find
# areas worth re-examining. Produces a bounded summary file for Claude to read.
#
# Usage:
#   bash .claude/scripts/curate-scan.sh [--init] [--window <months>] [--max-commits <n>]
#
# Options:
#   --init           First-time scan (ignores last-scanned SHA)
#   --window <n>     Months of history to scan (default: 3)
#   --max-commits <n> Maximum commits to process (default: 500)
#
# Output: .curate/scan-summary.md (gitignored, read by Claude)
# Zero token cost — runs as shell outside Claude's context window.

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────

INIT_MODE=0
WINDOW_MONTHS=3
MAX_COMMITS=500
CURATE_DIR=".curate"
STATE_FILE="$CURATE_DIR/curation-state.md"
SUMMARY_FILE="$CURATE_DIR/scan-summary.md"

# ── Argument handling ────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --init)       INIT_MODE=1; shift ;;
        --window)     WINDOW_MONTHS="$2"; shift 2 ;;
        --max-commits) MAX_COMMITS="$2"; shift 2 ;;
        *)            shift ;;
    esac
done

# ── Safety checks ────────────────────────────────────────────────────────────

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: not a git repository" >&2
    exit 1
fi

mkdir -p "$CURATE_DIR"

# ── Read last-scanned state ─────────────────────────────────────────────────

LAST_SHA=""
if [[ "$INIT_MODE" != "1" && -f "$STATE_FILE" ]]; then
    LAST_SHA="$(grep '^Last scanned:' "$STATE_FILE" 2>/dev/null | awk '{print $NF}' || true)"
    # Verify the SHA still exists in the repo
    if [[ -n "$LAST_SHA" ]] && ! git cat-file -e "$LAST_SHA" 2>/dev/null; then
        LAST_SHA=""
    fi
fi

# ── Determine scan range ────────────────────────────────────────────────────

CURRENT_SHA="$(git rev-parse HEAD)"
SINCE_DATE="$(date -d "-${WINDOW_MONTHS} months" +%Y-%m-%d 2>/dev/null || date -v-${WINDOW_MONTHS}m +%Y-%m-%d 2>/dev/null || echo "")"

if [[ -n "$LAST_SHA" && "$LAST_SHA" != "$CURRENT_SHA" ]]; then
    # Incremental scan from last position
    SCAN_RANGE="${LAST_SHA}..HEAD"
    SCAN_MODE="incremental"
elif [[ -n "$LAST_SHA" && "$LAST_SHA" == "$CURRENT_SHA" ]]; then
    echo "No new commits since last scan." >&2
    exit 0
else
    # Full scan with time window
    if [[ -n "$SINCE_DATE" ]]; then
        SCAN_RANGE="--since=$SINCE_DATE"
    else
        SCAN_RANGE="-n $MAX_COMMITS"
    fi
    SCAN_MODE="full"
fi

# ── Noise filtering ─────────────────────────────────────────────────────────

EXCLUDE_PATTERN='(node_modules|vendor|dist|build|\.git|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|go\.sum|Gemfile\.lock|\.min\.|migrations/|__pycache__|\.pyc$|\.class$)'

# ── Collect changed files ────────────────────────────────────────────────────

TMPDIR_SCAN="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_SCAN"' EXIT

if [[ "$SCAN_MODE" == "incremental" ]]; then
    git log --name-only --pretty=format:'%H' "$SCAN_RANGE" -n "$MAX_COMMITS" \
        | grep -v '^$' > "$TMPDIR_SCAN/raw-log.txt" 2>/dev/null || true
else
    if [[ -n "$SINCE_DATE" ]]; then
        git log --name-only --pretty=format:'%H' --since="$SINCE_DATE" -n "$MAX_COMMITS" \
            | grep -v '^$' > "$TMPDIR_SCAN/raw-log.txt" 2>/dev/null || true
    else
        git log --name-only --pretty=format:'%H' -n "$MAX_COMMITS" \
            | grep -v '^$' > "$TMPDIR_SCAN/raw-log.txt" 2>/dev/null || true
    fi
fi

# Count commits processed
COMMIT_COUNT="$(grep -cE '^[0-9a-f]{40}$' "$TMPDIR_SCAN/raw-log.txt" 2>/dev/null || echo 0)"

if [[ "$COMMIT_COUNT" -eq 0 ]]; then
    echo "No commits found in scan range." >&2
    exit 0
fi

# ── Analysis 1: Churn hotspots ───────────────────────────────────────────────
# Files sorted by how many commits they appear in

grep -vE "^[0-9a-f]{40}$" "$TMPDIR_SCAN/raw-log.txt" \
    | grep -vE "$EXCLUDE_PATTERN" \
    | sort | uniq -c | sort -rn \
    | head -30 > "$TMPDIR_SCAN/churn.txt" 2>/dev/null || true

# ── Analysis 2: Co-change clusters ──────────────────────────────────────────
# Files that appear together in commits (excluding large commits with 50+ files)

# Group files by commit
current_commit=""
declare -A commit_files
commit_index=0

while IFS= read -r line; do
    if [[ "$line" =~ ^[0-9a-f]{40}$ ]]; then
        current_commit="$line"
        commit_index=$((commit_index + 1))
        commit_files[$commit_index]=""
    elif [[ -n "$line" ]] && ! echo "$line" | grep -qE "$EXCLUDE_PATTERN"; then
        if [[ -n "${commit_files[$commit_index]+x}" ]]; then
            commit_files[$commit_index]="${commit_files[$commit_index]}|$line"
        fi
    fi
done < "$TMPDIR_SCAN/raw-log.txt"

# Build co-occurrence pairs (skip commits with 50+ files)
> "$TMPDIR_SCAN/pairs.txt"
for idx in "${!commit_files[@]}"; do
    IFS='|' read -ra files <<< "${commit_files[$idx]}"
    # Skip large commits
    if [[ "${#files[@]}" -gt 50 || "${#files[@]}" -lt 2 ]]; then
        continue
    fi
    # Generate sorted pairs
    for ((i=0; i<${#files[@]}; i++)); do
        for ((j=i+1; j<${#files[@]}; j++)); do
            if [[ -n "${files[$i]}" && -n "${files[$j]}" ]]; then
                if [[ "${files[$i]}" < "${files[$j]}" ]]; then
                    echo "${files[$i]}|${files[$j]}"
                else
                    echo "${files[$j]}|${files[$i]}"
                fi
            fi
        done
    done
done >> "$TMPDIR_SCAN/pairs.txt"

# Count pair frequency (only pairs appearing 3+ times)
sort "$TMPDIR_SCAN/pairs.txt" | uniq -c | sort -rn \
    | awk '$1 >= 3' | head -20 > "$TMPDIR_SCAN/co-change.txt" 2>/dev/null || true

# ── Analysis 3: Correlate against vallorcine artifacts ───────────────────────
# Find ADRs, KB entries, and feature archives that reference changed files

# Get unique changed files
grep -vE "^[0-9a-f]{40}$" "$TMPDIR_SCAN/raw-log.txt" \
    | grep -vE "$EXCLUDE_PATTERN" \
    | sort -u > "$TMPDIR_SCAN/changed-files.txt" 2>/dev/null || true

# Search for artifact matches
> "$TMPDIR_SCAN/artifact-hits.txt"

# Check ADRs for files: field or file path references
if [[ -d ".decisions" ]]; then
    while IFS= read -r changed_file; do
        [[ -z "$changed_file" ]] && continue
        # Search ADR files for references to this file
        matches="$(grep -rl "$changed_file" .decisions/*/adr.md .decisions/*/constraints.md 2>/dev/null || true)"
        if [[ -n "$matches" ]]; then
            while IFS= read -r match; do
                echo "ADR|$match|$changed_file" >> "$TMPDIR_SCAN/artifact-hits.txt"
            done <<< "$matches"
        fi
    done < "$TMPDIR_SCAN/changed-files.txt"
fi

# Check KB entries for applies-to field or file path references
if [[ -d ".kb" ]]; then
    while IFS= read -r changed_file; do
        [[ -z "$changed_file" ]] && continue
        matches="$(grep -rl "$changed_file" .kb/ --include='*.md' 2>/dev/null | grep -v 'CLAUDE.md' || true)"
        if [[ -n "$matches" ]]; then
            while IFS= read -r match; do
                echo "KB|$match|$changed_file" >> "$TMPDIR_SCAN/artifact-hits.txt"
            done <<< "$matches"
        fi
    done < "$TMPDIR_SCAN/changed-files.txt"
fi

# Check feature archives for file references
if [[ -d ".feature/_archive" ]]; then
    while IFS= read -r changed_file; do
        [[ -z "$changed_file" ]] && continue
        matches="$(grep -rl "$changed_file" .feature/_archive/*/domains.md .feature/_archive/*/work-plan.md 2>/dev/null || true)"
        if [[ -n "$matches" ]]; then
            while IFS= read -r match; do
                echo "FEATURE|$match|$changed_file" >> "$TMPDIR_SCAN/artifact-hits.txt"
            done <<< "$matches"
        fi
    done < "$TMPDIR_SCAN/changed-files.txt"
fi

# ── Analysis 3b: ADR Pressure ────────────────────────────────────────────────
# Aggregate ADR artifact hits by slug to detect decisions under concentrated
# change. When multiple files constrained by the same ADR change, the decision
# may need re-evaluation.
#
# DESIGN NOTE: File references are found via grep of ADR body text + files:
# frontmatter, not just the structured files: field. This is intentionally
# broad — a file mentioned in rationale or constraints is a signal even if not
# formally constrained. If this proves too noisy in practice, restrict to
# files: frontmatter only. Track user feedback on false positive rate.

TEST_PATTERN='(test[_/]|_test\.|\.test\.|Test\.|tests/|spec[_/]|_spec\.|\.spec\.)'

> "$TMPDIR_SCAN/adr-pressure.txt"
> "$TMPDIR_SCAN/adr-gravity.txt"
> "$TMPDIR_SCAN/hub-files.txt"

if [[ -d ".decisions" ]] && [[ -s "$TMPDIR_SCAN/artifact-hits.txt" ]]; then

    # Extract slug|changed_file pairs from ADR artifact hits
    grep '^ADR|' "$TMPDIR_SCAN/artifact-hits.txt" 2>/dev/null \
        | awk -F'|' '{
            split($2, parts, "/")
            slug = parts[2]
            print slug "|" $3
        }' | sort -u > "$TMPDIR_SCAN/adr-slug-files.txt" 2>/dev/null || true

    # --- Pressure: count unique changed files per ADR slug ---
    cut -d'|' -f1 "$TMPDIR_SCAN/adr-slug-files.txt" \
        | sort | uniq -c | sort -rn \
        | awk '$1 >= 2 {print $2 "|" $1}' > "$TMPDIR_SCAN/adr-pressure-counts.txt" 2>/dev/null || true

    while IFS='|' read -r slug changed; do
        # Count total file references in this ADR (all references, not just changed)
        total=0
        for adr_f in .decisions/"$slug"/adr.md .decisions/"$slug"/constraints.md; do
            [[ -f "$adr_f" ]] || continue
            t=$( (grep -oE '[a-zA-Z0-9_./+-]+/[a-zA-Z0-9_.+-]+\.[a-zA-Z0-9]+' "$adr_f" 2>/dev/null || true) \
                | sort -u | wc -l)
            total=$((total + t))
        done
        # Floor: total can't be less than changed
        [[ "$total" -ge "$changed" ]] || total="$changed"
        pct=$(( (changed * 100) / total ))
        echo "PRESSURE|$slug|$changed|$total|$pct" >> "$TMPDIR_SCAN/adr-pressure.txt"
    done < "$TMPDIR_SCAN/adr-pressure-counts.txt"

    sort -t'|' -k5 -rn "$TMPDIR_SCAN/adr-pressure.txt" -o "$TMPDIR_SCAN/adr-pressure.txt" 2>/dev/null || true

    # ── Analysis 3c: ADR Gravity ─────────────────────────────────────────────
    # Cross-reference co-change pairs with ADR constrained files. If one file
    # in a pair is ADR-constrained and the other isn't, the unconstrained file
    # is gravitationally linked — it may belong in the ADR's scope.
    # Test files are excluded on the unconstrained side (they co-change with
    # everything and inflate every relationship).

    > "$TMPDIR_SCAN/adr-gravity-raw.txt"

    if [[ -s "$TMPDIR_SCAN/co-change.txt" ]] && [[ -s "$TMPDIR_SCAN/adr-slug-files.txt" ]]; then
        # Build set of ADR-constrained changed files
        cut -d'|' -f2 "$TMPDIR_SCAN/adr-slug-files.txt" | sort -u > "$TMPDIR_SCAN/adr-constrained-set.txt"

        while IFS= read -r line; do
            count="$(echo "$line" | awk '{print $1}')"
            pair="$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ //')"
            file_a="$(echo "$pair" | cut -d'|' -f1)"
            file_b="$(echo "$pair" | cut -d'|' -f2)"

            a_constrained=0
            grep -qxF "$file_a" "$TMPDIR_SCAN/adr-constrained-set.txt" 2>/dev/null && a_constrained=1
            b_constrained=0
            grep -qxF "$file_b" "$TMPDIR_SCAN/adr-constrained-set.txt" 2>/dev/null && b_constrained=1

            # Case: A constrained, B not — B is the gravity signal
            if [[ "$a_constrained" -gt 0 && "$b_constrained" -eq 0 ]]; then
                if ! echo "$file_b" | grep -qE "$TEST_PATTERN"; then
                    awk -F'|' -v f="$file_a" '$2 == f {print $1}' "$TMPDIR_SCAN/adr-slug-files.txt" \
                        | while IFS= read -r slug; do
                            echo "$slug|$file_b|$file_a|$count"
                        done >> "$TMPDIR_SCAN/adr-gravity-raw.txt"
                fi
            fi

            # Case: B constrained, A not — A is the gravity signal
            if [[ "$b_constrained" -gt 0 && "$a_constrained" -eq 0 ]]; then
                if ! echo "$file_a" | grep -qE "$TEST_PATTERN"; then
                    awk -F'|' -v f="$file_b" '$2 == f {print $1}' "$TMPDIR_SCAN/adr-slug-files.txt" \
                        | while IFS= read -r slug; do
                            echo "$slug|$file_a|$file_b|$count"
                        done >> "$TMPDIR_SCAN/adr-gravity-raw.txt"
                fi
            fi
        done < "$TMPDIR_SCAN/co-change.txt"
    fi

    # ── Analysis 3d: Classify gravity → signals vs hub files ─────────────────
    # Hub files (3+ ADRs) are fragility/test-coverage concerns, not attributed
    # to any single ADR. High gravity on a single ADR (5+ unconstrained files)
    # suggests a boundary/isolation problem worth architect review.

    if [[ -s "$TMPDIR_SCAN/adr-gravity-raw.txt" ]]; then
        # Count distinct ADR slugs per unconstrained file
        awk -F'|' '{print $1 "|" $2}' "$TMPDIR_SCAN/adr-gravity-raw.txt" \
            | sort -u \
            | cut -d'|' -f2 | sort | uniq -c | sort -rn \
            > "$TMPDIR_SCAN/gravity-adr-counts.txt"

        # Hub files: unconstrained files co-changing with 3+ ADRs
        awk '$1 >= 3' "$TMPDIR_SCAN/gravity-adr-counts.txt" \
            | while read -r adr_count uncon_file; do
                slugs=$(awk -F'|' -v f="$uncon_file" '$2 == f {print $1}' "$TMPDIR_SCAN/adr-gravity-raw.txt" \
                    | sort -u | tr '\n' ',' | sed 's/,$//')
                echo "HUB|$uncon_file|$adr_count|$slugs" >> "$TMPDIR_SCAN/hub-files.txt"
            done

        # Build set of hub files for filtering
        awk '$1 >= 3 {$1=""; print $0}' "$TMPDIR_SCAN/gravity-adr-counts.txt" \
            | sed 's/^ //' > "$TMPDIR_SCAN/hub-set.txt" 2>/dev/null || true

        # Gravity signals: non-hub unconstrained files
        while IFS='|' read -r slug uncon_file constrained co_count; do
            if ! grep -qxF "$uncon_file" "$TMPDIR_SCAN/hub-set.txt" 2>/dev/null; then
                echo "GRAVITY|$slug|$uncon_file|$constrained|$co_count"
            fi
        done < "$TMPDIR_SCAN/adr-gravity-raw.txt" \
            | sort -u >> "$TMPDIR_SCAN/adr-gravity.txt"

        sort -t'|' -k5 -rn "$TMPDIR_SCAN/adr-gravity.txt" -o "$TMPDIR_SCAN/adr-gravity.txt" 2>/dev/null || true
        sort -t'|' -k3 -rn "$TMPDIR_SCAN/hub-files.txt" -o "$TMPDIR_SCAN/hub-files.txt" 2>/dev/null || true
    fi
fi

# ── Analysis 4: Identify orphaned files (high churn, no artifact coverage) ───

> "$TMPDIR_SCAN/orphaned.txt"
while IFS= read -r line; do
    count="$(echo "$line" | awk '{print $1}')"
    file="$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ //')"
    # Check if this file has any artifact references
    if ! grep -q "$file" "$TMPDIR_SCAN/artifact-hits.txt" 2>/dev/null; then
        echo "$count $file" >> "$TMPDIR_SCAN/orphaned.txt"
    fi
done < "$TMPDIR_SCAN/churn.txt"

# ── Analysis 5: KB staleness check ──────────────────────────────────────────

> "$TMPDIR_SCAN/stale-kb.txt"
if [[ -d ".kb" ]]; then
    find .kb -name '*.md' -not -name 'CLAUDE.md' -not -path '*/_refs/*' -not -path '*/_archive*' 2>/dev/null | while IFS= read -r kb_file; do
        # Extract last_researched from frontmatter
        last_researched="$(grep '^last_researched:' "$kb_file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || true)"
        if [[ -n "$last_researched" ]]; then
            # Check if older than 6 months
            if [[ -n "$SINCE_DATE" ]]; then
                if [[ "$last_researched" < "$SINCE_DATE" ]]; then
                    echo "STALE|$kb_file|$last_researched" >> "$TMPDIR_SCAN/stale-kb.txt"
                fi
            fi
        fi
    done
fi

# ── Analysis 6: ADR revisit condition check ─────────────────────────────────

> "$TMPDIR_SCAN/adr-revisit.txt"
if [[ -d ".decisions" ]]; then
    find .decisions -name 'adr.md' 2>/dev/null | while IFS= read -r adr_file; do
        # Check for "Conditions for Revision" section
        if grep -q "Conditions for Revision" "$adr_file" 2>/dev/null; then
            slug="$(dirname "$adr_file" | xargs basename)"
            accepted_date="$(grep '^date:' "$adr_file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || true)"
            echo "REVISIT|$adr_file|$slug|$accepted_date" >> "$TMPDIR_SCAN/adr-revisit.txt"
        fi
    done
fi

# ── Analysis 7: Test-source correlation ───────────────────────────────────────
# Find source files that changed but whose corresponding test files didn't.
# Uses naming conventions and work-plan archives to match source ↔ test.

> "$TMPDIR_SCAN/test-drift.txt"

# Build a map of changed source files (exclude test files themselves)
grep -vE "^[0-9a-f]{40}$" "$TMPDIR_SCAN/raw-log.txt" \
    | grep -vE "$EXCLUDE_PATTERN" \
    | grep -vE '(test[_/]|_test\.|\.test\.|Test\.|tests/|spec[_/]|_spec\.|\.spec\.)' \
    | sort -u > "$TMPDIR_SCAN/changed-source.txt" 2>/dev/null || true

# Build a map of changed test files
grep -vE "^[0-9a-f]{40}$" "$TMPDIR_SCAN/raw-log.txt" \
    | grep -vE "$EXCLUDE_PATTERN" \
    | grep -E '(test[_/]|_test\.|\.test\.|Test\.|tests/|spec[_/]|_spec\.|\.spec\.)' \
    | sort -u > "$TMPDIR_SCAN/changed-tests.txt" 2>/dev/null || true

# For each changed source file, check if a corresponding test file also changed
while IFS= read -r src_file; do
    [[ -z "$src_file" ]] && continue

    # Extract base name without extension for matching
    base="$(basename "$src_file")"
    name="${base%.*}"
    ext="${base##*.}"

    # Generate possible test file name patterns
    # Java: Foo.java → FooTest.java, TestFoo.java
    # Python: foo.py → test_foo.py, foo_test.py
    # TypeScript/JS: foo.ts → foo.test.ts, foo.spec.ts
    # Go: foo.go → foo_test.go
    matched=0
    for pattern in \
        "${name}Test.${ext}" "Test${name}.${ext}" \
        "${name}_test.${ext}" "test_${name}.${ext}" \
        "${name}.test.${ext}" "${name}.spec.${ext}" \
        "${name}_test.go" "${name}_spec.${ext}"; do
        if grep -q "$pattern" "$TMPDIR_SCAN/changed-tests.txt" 2>/dev/null; then
            matched=1
            break
        fi
    done

    if [[ "$matched" == "0" ]]; then
        # Source changed but no corresponding test changed
        # Count how many commits touched this source file
        src_commits="$(grep -c "$src_file" "$TMPDIR_SCAN/churn.txt" 2>/dev/null || echo 0)"
        if [[ "$src_commits" -gt 0 ]]; then
            echo "$src_commits|$src_file" >> "$TMPDIR_SCAN/test-drift.txt"
        fi
    fi
done < "$TMPDIR_SCAN/changed-source.txt"

# Sort by commit count descending
sort -t'|' -k1 -rn "$TMPDIR_SCAN/test-drift.txt" -o "$TMPDIR_SCAN/test-drift.txt" 2>/dev/null || true

# ── Analysis 8: Backfill candidates (orphaned areas with decision patterns) ──
# Scan archived feature domains for implicit decisions not documented as ADRs.

> "$TMPDIR_SCAN/backfill-candidates.txt"

if [[ -d ".feature/_archive" ]]; then
    # Read dismissed list if it exists
    dismissed_file=".decisions/.backfill-dismissed"

    find .feature/_archive -name 'domains.md' 2>/dev/null | while IFS= read -r domains_file; do
        feature_slug="$(echo "$domains_file" | sed 's|.feature/_archive/||; s|/domains.md||')"

        # Look for domains with no governing ADR
        # Scan for "Governing ADR: None" or absence of ADR reference
        if grep -q "Governing ADR.*None\|No ADR\|no decision" "$domains_file" 2>/dev/null; then
            # Extract domain names from the file
            grep -E "^### |^## Domain:" "$domains_file" 2>/dev/null | while IFS= read -r domain_line; do
                domain_name="$(echo "$domain_line" | sed 's/^### //; s/^## Domain: //')"
                candidate_key="archive:${feature_slug}:$(echo "$domain_name" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"

                # Check if dismissed
                if [[ -f "$dismissed_file" ]] && grep -q "$candidate_key" "$dismissed_file" 2>/dev/null; then
                    continue
                fi

                # Check if an ADR already exists for this domain
                domain_slug="$(echo "$domain_name" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"
                if [[ -d ".decisions/$domain_slug" ]]; then
                    continue
                fi

                echo "BACKFILL|$feature_slug|$domain_name|$candidate_key" >> "$TMPDIR_SCAN/backfill-candidates.txt"
            done
        fi
    done
fi

# ── Analysis 9: Out-of-scope items from accepted ADRs ──────────────────────
# Extract "What This Decision Does NOT Solve" items from confirmed ADRs.
# These are deferred work that was never tracked as deferred decision stubs.
# Items are skipped if a deferred stub with a matching slug already exists.

> "$TMPDIR_SCAN/out-of-scope.txt"

if [[ -d ".decisions" ]]; then
    find .decisions -name 'adr.md' -path '*/*/adr.md' 2>/dev/null | while IFS= read -r adr_file; do
        # Only scan confirmed/accepted ADRs
        status="$(grep -m1 '^status:' "$adr_file" 2>/dev/null | sed 's/^status:[[:space:]]*//' | tr -d '"' || true)"
        if [[ "$status" != "confirmed" && "$status" != "accepted" ]]; then
            continue
        fi

        parent_slug="$(basename "$(dirname "$adr_file")")"

        # Extract "What This Decision Does NOT Solve" section
        in_section=0
        while IFS= read -r line; do
            if [[ "$line" == "## What This Decision Does NOT Solve"* ]]; then
                in_section=1
                continue
            fi
            # Stop at next heading
            if [[ $in_section -eq 1 && "$line" == "## "* ]]; then
                break
            fi
            if [[ $in_section -eq 1 && "$line" == "- "* ]]; then
                item="${line#- }"
                # Skip template placeholders (contain < and >)
                if [[ "$item" == *"<"*">"* ]]; then
                    continue
                fi
                # Split on " — " to get concern and reason
                if [[ "$item" == *" — "* ]]; then
                    concern="${item%% — *}"
                    reason="${item#* — }"
                else
                    concern="$item"
                    reason=""
                fi
                # Derive a slug for deduplication: first 5 words, kebab-case
                candidate_slug="$(echo "$concern" | tr '[:upper:]' '[:lower:]' | \
                    sed 's/[^a-z0-9 ]//g' | awk '{for(i=1;i<=5&&i<=NF;i++) printf "%s-",$i}' | \
                    sed 's/-$//')"
                # Skip if a deferred stub already exists
                if [[ -d ".decisions/$candidate_slug" ]]; then
                    continue
                fi
                echo "OUTOFSCOPE|$parent_slug|$concern|$reason" >> "$TMPDIR_SCAN/out-of-scope.txt"
            fi
        done < "$adr_file"
    done
fi

# ── Analysis 10: Spec coverage signals ─────────────────────────────────────
# Three spec signals: unspecified shared types, open obligations, spec-code drift.
# All require .spec/ to exist — skip silently if absent.

> "$TMPDIR_SCAN/spec-unspecified.txt"
> "$TMPDIR_SCAN/spec-obligations.txt"
> "$TMPDIR_SCAN/spec-drift.txt"

if [[ -d ".spec" && -d ".spec/domains" ]]; then

    # ── 10a: Unspecified shared types ──────────────────────────────────────
    # Find CamelCase type names referenced in 3+ spec files that have no
    # spec of their own.

    > "$TMPDIR_SCAN/spec-type-refs.txt"

    # Extract CamelCase words from all spec files, record which spec references them
    find .spec/domains -name '*.md' 2>/dev/null | while IFS= read -r spec_file; do
        spec_base="$(basename "$spec_file" .md)"
        # Extract CamelCase identifiers (2+ chars, starts uppercase, has lowercase)
        (grep -oE '\b[A-Z][a-z]+([A-Z][a-z]*)+\b' "$spec_file" 2>/dev/null || true) \
            | sort -u \
            | while IFS= read -r type_name; do
                [[ -z "$type_name" ]] && continue
                echo "$type_name|$spec_base"
            done
    done >> "$TMPDIR_SCAN/spec-type-refs.txt"

    if [[ -s "$TMPDIR_SCAN/spec-type-refs.txt" ]]; then
        # Count distinct spec files per type name
        cut -d'|' -f1 "$TMPDIR_SCAN/spec-type-refs.txt" \
            | sort | uniq -c | sort -rn \
            | awk '$1 >= 3' > "$TMPDIR_SCAN/spec-type-counts.txt" 2>/dev/null || true

        # Build list of spec file base names for cross-reference
        find .spec/domains -name '*.md' 2>/dev/null \
            | xargs -I{} basename {} .md \
            | sort -u > "$TMPDIR_SCAN/spec-names.txt" 2>/dev/null || true

        while IFS= read -r line; do
            ref_count="$(echo "$line" | awk '{print $1}')"
            type_name="$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ //')"
            # Check if any spec file name contains this type name (case-insensitive)
            type_lower="$(echo "$type_name" | tr '[:upper:]' '[:lower:]')"
            has_spec=0
            while IFS= read -r spec_name; do
                spec_lower="$(echo "$spec_name" | tr '[:upper:]' '[:lower:]')"
                if [[ "$spec_lower" == *"$type_lower"* ]]; then
                    has_spec=1
                    break
                fi
            done < "$TMPDIR_SCAN/spec-names.txt"

            if [[ "$has_spec" -eq 0 ]]; then
                # Collect which specs reference this type
                referencing_specs="$(grep "^${type_name}|" "$TMPDIR_SCAN/spec-type-refs.txt" \
                    | cut -d'|' -f2 | sort -u | tr '\n' ',' | sed 's/,$//')"
                echo "UNSPECIFIED|$type_name|$ref_count|$referencing_specs" >> "$TMPDIR_SCAN/spec-unspecified.txt"
            fi
        done < "$TMPDIR_SCAN/spec-type-counts.txt"

        sort -t'|' -k3 -rn "$TMPDIR_SCAN/spec-unspecified.txt" -o "$TMPDIR_SCAN/spec-unspecified.txt" 2>/dev/null || true
    fi

    # ── 10b: Specs with open obligations ──────────────────────────────────
    # Scan specs for open_obligations in frontmatter or [UNRESOLVED]/[CONFLICT] markers

    find .spec/domains -name '*.md' 2>/dev/null | while IFS= read -r spec_file; do
        spec_base="$(basename "$spec_file" .md)"
        obligation_count=0
        obligations=""

        # Check frontmatter for open_obligations
        fm_obligations="$(sed -n '/^---$/,/^---$/p' "$spec_file" 2>/dev/null \
            | grep 'open_obligations' | head -1 || true)"

        # Count [UNRESOLVED] and [CONFLICT] markers in body
        unresolved_count="$(grep -c '\[UNRESOLVED\]' "$spec_file" 2>/dev/null || echo 0)"
        conflict_count="$(grep -c '\[CONFLICT\]' "$spec_file" 2>/dev/null || echo 0)"
        obligation_count=$((unresolved_count + conflict_count))

        # Extract obligation text for display
        if [[ "$obligation_count" -gt 0 ]]; then
            obligations="$(grep -oE '\[UNRESOLVED\][^.]*\.|\[CONFLICT\][^.]*\.' "$spec_file" 2>/dev/null \
                | head -5 | tr '\n' ';' | sed 's/;$//' || true)"
            echo "OBLIGATION|$spec_base|$obligation_count|$obligations" >> "$TMPDIR_SCAN/spec-obligations.txt"
        fi

        # Also check for DRAFT status with open_obligations in frontmatter
        if [[ -n "$fm_obligations" && "$obligation_count" -eq 0 ]]; then
            ob_text="$(echo "$fm_obligations" | sed 's/.*open_obligations:[[:space:]]*//' | tr -d '[]"' || true)"
            if [[ -n "$ob_text" ]]; then
                ob_count="$(echo "$ob_text" | tr ',' '\n' | grep -c '[a-z]' 2>/dev/null || echo 1)"
                echo "OBLIGATION|$spec_base|$ob_count|$ob_text" >> "$TMPDIR_SCAN/spec-obligations.txt"
            fi
        fi
    done

    sort -t'|' -k3 -rn "$TMPDIR_SCAN/spec-obligations.txt" -o "$TMPDIR_SCAN/spec-obligations.txt" 2>/dev/null || true

    # ── 10c: Spec-code drift ──────────────────────────────────────────────
    # For each spec, check if its domain files have been committed after the
    # spec's created date.

    find .spec/domains -name '*.md' 2>/dev/null | while IFS= read -r spec_file; do
        spec_base="$(basename "$spec_file" .md)"

        # Extract created date from frontmatter
        created_date="$(sed -n '/^---$/,/^---$/p' "$spec_file" 2>/dev/null \
            | grep -m1 '^created:' | awk '{print $2}' | tr -d '"' || true)"
        [[ -z "$created_date" ]] && continue

        # Extract domain/files references from the spec
        # Look for domains: field in frontmatter or file paths in body
        domain_dir=""
        # Try to extract domains from frontmatter
        domains_field="$(sed -n '/^---$/,/^---$/p' "$spec_file" 2>/dev/null \
            | grep -m1 '^domains:' | sed 's/^domains:[[:space:]]*//' | tr -d '[]"' || true)"

        if [[ -n "$domains_field" ]]; then
            # Count commits to domain directories since spec creation
            commit_count=0
            IFS=',' read -ra domain_list <<< "$domains_field"
            for domain in "${domain_list[@]}"; do
                domain="$(echo "$domain" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                [[ -z "$domain" ]] && continue
                # Count git commits touching files in this domain since spec date
                dc="$(git log --oneline --since="$created_date" -- "$domain" 2>/dev/null | wc -l || echo 0)"
                commit_count=$((commit_count + dc))
            done

            if [[ "$commit_count" -gt 0 ]]; then
                domain_desc="$(echo "$domains_field" | sed 's/,/, /g')"
                echo "DRIFT|$spec_base|$created_date|$commit_count|$domain_desc" >> "$TMPDIR_SCAN/spec-drift.txt"
            fi
        else
            # Fallback: extract file paths from spec body (lines with src/ or similar)
            file_paths="$(grep -oE '(src|lib|pkg|app|internal)/[a-zA-Z0-9_/.-]+' "$spec_file" 2>/dev/null \
                | sort -u | head -20 || true)"
            if [[ -n "$file_paths" ]]; then
                commit_count=0
                while IFS= read -r fpath; do
                    [[ -z "$fpath" ]] && continue
                    # Get the directory containing the file
                    fdir="$(dirname "$fpath")"
                    dc="$(git log --oneline --since="$created_date" -- "$fdir" 2>/dev/null | wc -l || echo 0)"
                    commit_count=$((commit_count + dc))
                done <<< "$file_paths"

                if [[ "$commit_count" -gt 0 ]]; then
                    echo "DRIFT|$spec_base|$created_date|$commit_count|inferred from file paths" >> "$TMPDIR_SCAN/spec-drift.txt"
                fi
            fi
        fi
    done

    sort -t'|' -k4 -rn "$TMPDIR_SCAN/spec-drift.txt" -o "$TMPDIR_SCAN/spec-drift.txt" 2>/dev/null || true

fi

# ── Write summary file ──────────────────────────────────────────────────────

SCAN_DATE="$(date +%Y-%m-%d)"

cat > "$SUMMARY_FILE" << HEADER
# Curation Scan Summary

Scan date: $SCAN_DATE
Scan mode: $SCAN_MODE
Commits scanned: $COMMIT_COUNT
Window: ${WINDOW_MONTHS} months
Current HEAD: $CURRENT_SHA

HEADER

# Churn hotspots
if [[ -s "$TMPDIR_SCAN/churn.txt" ]]; then
    echo "## Churn Hotspots" >> "$SUMMARY_FILE"
    echo "Files with the most commits in scan window:" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "| Commits | File |" >> "$SUMMARY_FILE"
    echo "|---------|------|" >> "$SUMMARY_FILE"
    while IFS= read -r line; do
        count="$(echo "$line" | awk '{print $1}')"
        file="$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ //')"
        echo "| $count | $file |" >> "$SUMMARY_FILE"
    done < "$TMPDIR_SCAN/churn.txt"
    echo "" >> "$SUMMARY_FILE"
fi

# Co-change clusters
if [[ -s "$TMPDIR_SCAN/co-change.txt" ]]; then
    echo "## Co-change Clusters" >> "$SUMMARY_FILE"
    echo "File pairs that frequently change together (3+ commits):" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "| Co-changes | File A | File B |" >> "$SUMMARY_FILE"
    echo "|------------|--------|--------|" >> "$SUMMARY_FILE"
    while IFS= read -r line; do
        count="$(echo "$line" | awk '{print $1}')"
        pair="$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ //')"
        file_a="$(echo "$pair" | cut -d'|' -f1)"
        file_b="$(echo "$pair" | cut -d'|' -f2)"
        echo "| $count | $file_a | $file_b |" >> "$SUMMARY_FILE"
    done < "$TMPDIR_SCAN/co-change.txt"
    echo "" >> "$SUMMARY_FILE"
fi

# Artifact correlations
if [[ -s "$TMPDIR_SCAN/artifact-hits.txt" ]]; then
    echo "## Artifact Correlations" >> "$SUMMARY_FILE"
    echo "Changed files that are referenced by existing KB/ADR/feature artifacts:" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "| Type | Artifact | Changed File |" >> "$SUMMARY_FILE"
    echo "|------|----------|--------------|" >> "$SUMMARY_FILE"
    sort -u "$TMPDIR_SCAN/artifact-hits.txt" | head -30 | while IFS='|' read -r type artifact file; do
        echo "| $type | $artifact | $file |" >> "$SUMMARY_FILE"
    done
    echo "" >> "$SUMMARY_FILE"
fi

# ADR Pressure
if [[ -s "$TMPDIR_SCAN/adr-pressure.txt" ]]; then
    echo "## ADR Pressure" >> "$SUMMARY_FILE"
    echo "Decisions with concentrated file changes (2+ constrained files changed):" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "| ADR | Changed | Total | Pressure |" >> "$SUMMARY_FILE"
    echo "|-----|---------|-------|----------|" >> "$SUMMARY_FILE"
    while IFS='|' read -r _ slug changed total pct; do
        echo "| $slug | $changed | $total | ${pct}% |" >> "$SUMMARY_FILE"
    done < "$TMPDIR_SCAN/adr-pressure.txt"
    echo "" >> "$SUMMARY_FILE"
fi

# ADR Gravity
if [[ -s "$TMPDIR_SCAN/adr-gravity.txt" ]]; then
    echo "## ADR Gravity" >> "$SUMMARY_FILE"
    echo "Files co-changing with ADR-constrained files but not in the ADR's scope:" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "| ADR | Unconstrained File | Co-changes With | Count |" >> "$SUMMARY_FILE"
    echo "|-----|-------------------|-----------------|-------|" >> "$SUMMARY_FILE"
    head -20 "$TMPDIR_SCAN/adr-gravity.txt" | while IFS='|' read -r _ slug uncon constrained co_count; do
        echo "| $slug | $uncon | $constrained | $co_count |" >> "$SUMMARY_FILE"
    done
    echo "" >> "$SUMMARY_FILE"
fi

# Hub Files
if [[ -s "$TMPDIR_SCAN/hub-files.txt" ]]; then
    echo "## Hub Files" >> "$SUMMARY_FILE"
    echo "Files co-changing with 3+ ADRs' constrained files (fragility/test-coverage concern):" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "| File | ADR Count | ADRs |" >> "$SUMMARY_FILE"
    echo "|------|-----------|------|" >> "$SUMMARY_FILE"
    while IFS='|' read -r _ file adr_count slugs; do
        echo "| $file | $adr_count | $slugs |" >> "$SUMMARY_FILE"
    done < "$TMPDIR_SCAN/hub-files.txt"
    echo "" >> "$SUMMARY_FILE"
fi

# Orphaned high-churn files
if [[ -s "$TMPDIR_SCAN/orphaned.txt" ]]; then
    echo "## Orphaned Areas (no KB/ADR/feature coverage)" >> "$SUMMARY_FILE"
    echo "High-churn files with no structured knowledge behind them:" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "| Commits | File |" >> "$SUMMARY_FILE"
    echo "|---------|------|" >> "$SUMMARY_FILE"
    while IFS= read -r line; do
        count="$(echo "$line" | awk '{print $1}')"
        file="$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ //')"
        echo "| $count | $file |" >> "$SUMMARY_FILE"
    done < "$TMPDIR_SCAN/orphaned.txt"
    echo "" >> "$SUMMARY_FILE"
fi

# Stale KB entries
if [[ -s "$TMPDIR_SCAN/stale-kb.txt" ]]; then
    echo "## Stale KB Entries" >> "$SUMMARY_FILE"
    echo "KB entries past their review window:" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "| KB File | Last Researched |" >> "$SUMMARY_FILE"
    echo "|---------|-----------------|" >> "$SUMMARY_FILE"
    while IFS='|' read -r _ kb_file date; do
        echo "| $kb_file | $date |" >> "$SUMMARY_FILE"
    done < "$TMPDIR_SCAN/stale-kb.txt"
    echo "" >> "$SUMMARY_FILE"
fi

# ADRs with revisit conditions
if [[ -s "$TMPDIR_SCAN/adr-revisit.txt" ]]; then
    echo "## ADRs With Revisit Conditions" >> "$SUMMARY_FILE"
    echo "Decisions that have explicit conditions for re-evaluation:" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "| ADR | Slug | Accepted |" >> "$SUMMARY_FILE"
    echo "|-----|------|----------|" >> "$SUMMARY_FILE"
    while IFS='|' read -r _ adr_file slug date; do
        echo "| $adr_file | $slug | $date |" >> "$SUMMARY_FILE"
    done < "$TMPDIR_SCAN/adr-revisit.txt"
    echo "" >> "$SUMMARY_FILE"
fi

# Test-source drift
if [[ -s "$TMPDIR_SCAN/test-drift.txt" ]]; then
    echo "## Test-Source Drift" >> "$SUMMARY_FILE"
    echo "Source files that changed but their corresponding test files didn't:" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "| Source Commits | Source File |" >> "$SUMMARY_FILE"
    echo "|---------------|-------------|" >> "$SUMMARY_FILE"
    head -20 "$TMPDIR_SCAN/test-drift.txt" | while IFS='|' read -r count file; do
        echo "| $count | $file |" >> "$SUMMARY_FILE"
    done
    echo "" >> "$SUMMARY_FILE"
fi

# Backfill candidates
if [[ -s "$TMPDIR_SCAN/backfill-candidates.txt" ]]; then
    echo "## Backfill Candidates" >> "$SUMMARY_FILE"
    echo "Archived feature domains with implicit decisions (no ADR):" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "| Feature | Domain | Candidate Key |" >> "$SUMMARY_FILE"
    echo "|---------|--------|---------------|" >> "$SUMMARY_FILE"
    while IFS='|' read -r _ feature domain key; do
        echo "| $feature | $domain | $key |" >> "$SUMMARY_FILE"
    done < "$TMPDIR_SCAN/backfill-candidates.txt"
    echo "" >> "$SUMMARY_FILE"
fi

# Out-of-scope items
if [[ -s "$TMPDIR_SCAN/out-of-scope.txt" ]]; then
    echo "## Out-of-Scope Items (from accepted ADRs)" >> "$SUMMARY_FILE"
    echo 'Items from "What This Decision Does NOT Solve" sections with no corresponding deferred stub:' >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "| Parent ADR | Item | Reason |" >> "$SUMMARY_FILE"
    echo "|------------|------|--------|" >> "$SUMMARY_FILE"
    while IFS='|' read -r _ parent concern reason; do
        echo "| $parent | $concern | $reason |" >> "$SUMMARY_FILE"
    done < "$TMPDIR_SCAN/out-of-scope.txt"
    echo "" >> "$SUMMARY_FILE"
fi

# Spec coverage gaps
has_spec_signals=0
if [[ -s "$TMPDIR_SCAN/spec-unspecified.txt" ]] || [[ -s "$TMPDIR_SCAN/spec-obligations.txt" ]] || [[ -s "$TMPDIR_SCAN/spec-drift.txt" ]]; then
    echo "## Spec Coverage Gaps" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    has_spec_signals=1
fi

if [[ -s "$TMPDIR_SCAN/spec-unspecified.txt" ]]; then
    echo "### Unspecified shared types" >> "$SUMMARY_FILE"
    echo "Types referenced by 3+ specs that have no spec of their own:" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "| Type | Ref Count | Referenced By |" >> "$SUMMARY_FILE"
    echo "|------|-----------|---------------|" >> "$SUMMARY_FILE"
    while IFS='|' read -r _ type_name ref_count specs; do
        echo "| $type_name | $ref_count | $specs |" >> "$SUMMARY_FILE"
    done < "$TMPDIR_SCAN/spec-unspecified.txt"
    echo "" >> "$SUMMARY_FILE"
fi

if [[ -s "$TMPDIR_SCAN/spec-obligations.txt" ]]; then
    echo "### Specs with open obligations" >> "$SUMMARY_FILE"
    echo "Specs with unresolved conflicts or open obligations:" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "| Spec | Open Count | Details |" >> "$SUMMARY_FILE"
    echo "|------|------------|---------|" >> "$SUMMARY_FILE"
    while IFS='|' read -r _ spec_name ob_count details; do
        echo "| $spec_name | $ob_count | $details |" >> "$SUMMARY_FILE"
    done < "$TMPDIR_SCAN/spec-obligations.txt"
    echo "" >> "$SUMMARY_FILE"
fi

if [[ -s "$TMPDIR_SCAN/spec-drift.txt" ]]; then
    echo "### Spec-code drift" >> "$SUMMARY_FILE"
    echo "Specs whose domain files have changed since the spec was created:" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "| Spec | Created | Commits Since | Domains |" >> "$SUMMARY_FILE"
    echo "|------|---------|---------------|---------|" >> "$SUMMARY_FILE"
    while IFS='|' read -r _ spec_name created commits domains; do
        echo "| $spec_name | $created | $commits | $domains |" >> "$SUMMARY_FILE"
    done < "$TMPDIR_SCAN/spec-drift.txt"
    echo "" >> "$SUMMARY_FILE"
fi

# ── Report ───────────────────────────────────────────────────────────────────

echo "Scan complete: $COMMIT_COUNT commits analyzed"
echo "Summary written to: $SUMMARY_FILE"
echo "  Churn hotspots: $(wc -l < "$TMPDIR_SCAN/churn.txt" 2>/dev/null || echo 0)"
echo "  Co-change clusters: $(wc -l < "$TMPDIR_SCAN/co-change.txt" 2>/dev/null || echo 0)"
echo "  Artifact correlations: $(wc -l < "$TMPDIR_SCAN/artifact-hits.txt" 2>/dev/null || echo 0)"
echo "  ADR pressure: $(wc -l < "$TMPDIR_SCAN/adr-pressure.txt" 2>/dev/null || echo 0)"
echo "  ADR gravity signals: $(wc -l < "$TMPDIR_SCAN/adr-gravity.txt" 2>/dev/null || echo 0)"
echo "  Hub files: $(wc -l < "$TMPDIR_SCAN/hub-files.txt" 2>/dev/null || echo 0)"
echo "  Orphaned areas: $(wc -l < "$TMPDIR_SCAN/orphaned.txt" 2>/dev/null || echo 0)"
echo "  Stale KB entries: $(wc -l < "$TMPDIR_SCAN/stale-kb.txt" 2>/dev/null || echo 0)"
echo "  ADRs to revisit: $(wc -l < "$TMPDIR_SCAN/adr-revisit.txt" 2>/dev/null || echo 0)"
echo "  Test-source drift: $(wc -l < "$TMPDIR_SCAN/test-drift.txt" 2>/dev/null || echo 0)"
echo "  Backfill candidates: $(wc -l < "$TMPDIR_SCAN/backfill-candidates.txt" 2>/dev/null || echo 0)"
echo "  Out-of-scope items: $(wc -l < "$TMPDIR_SCAN/out-of-scope.txt" 2>/dev/null || echo 0)"
echo "  Unspecified shared types: $(wc -l < "$TMPDIR_SCAN/spec-unspecified.txt" 2>/dev/null || echo 0)"
echo "  Specs with obligations: $(wc -l < "$TMPDIR_SCAN/spec-obligations.txt" 2>/dev/null || echo 0)"
echo "  Spec-code drift: $(wc -l < "$TMPDIR_SCAN/spec-drift.txt" 2>/dev/null || echo 0)"

# ── Update curation state ─────────────────────────────────────────────────

cat > "$STATE_FILE" << STATE
Last scanned: $CURRENT_SHA
Scan date: $SCAN_DATE
Commits: $COMMIT_COUNT
Window: ${WINDOW_MONTHS} months
STATE

exit 0
