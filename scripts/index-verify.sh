#!/usr/bin/env bash
# vallorcine index verification and self-healing
# Checks that .kb/CLAUDE.md and .decisions/CLAUDE.md are consistent with
# their directory contents. Rebuilds missing rows if mismatched.
#
# Usage:
#   bash .claude/scripts/index-verify.sh [--kb] [--decisions] [--both] [--quiet]
#
# Called automatically at the start of commands that read indexes.
# Designed to self-heal after crashes that interrupted bottom-up index updates.
#
# Output: nothing if consistent, warnings if repaired.
# Performance: ~5-20ms typical (directory listing + grep).

# Note: no set -euo pipefail — this script is called automatically before
# commands that read indexes. It must never block, always exits 0.

CHECK_KB=0
CHECK_DECISIONS=0
QUIET=0

for arg in "$@"; do
    case "$arg" in
        --kb)        CHECK_KB=1 ;;
        --decisions) CHECK_DECISIONS=1 ;;
        --both)      CHECK_KB=1; CHECK_DECISIONS=1 ;;
        --quiet)     QUIET=1 ;;
    esac
done

# Default: check both
if [[ "$CHECK_KB" == "0" && "$CHECK_DECISIONS" == "0" ]]; then
    CHECK_KB=1
    CHECK_DECISIONS=1
fi

REPAIRED=0

# ── KB index verification ────────────────────────────────────────────────────

if [[ "$CHECK_KB" == "1" && -d ".kb" && -f ".kb/CLAUDE.md" ]]; then
    # Find all topic directories (exclude _refs, _archive, and hidden dirs)
    kb_topics=()
    while IFS= read -r dir; do
        topic="$(basename "$dir")"
        [[ "$topic" == _* || "$topic" == .* ]] && continue
        kb_topics+=("$topic")
    done < <(find .kb -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)

    # Check each topic has a row in the root index
    for topic in "${kb_topics[@]}"; do
        if ! grep -q "| $topic " ".kb/CLAUDE.md" 2>/dev/null && \
           ! grep -q "| $topic|" ".kb/CLAUDE.md" 2>/dev/null; then
            # Topic directory exists but no row in root index — rebuild row
            # Count categories and files
            cat_count=0
            file_count=0
            categories=""
            while IFS= read -r cat_dir; do
                cat_name="$(basename "$cat_dir")"
                [[ "$cat_name" == _* || "$cat_name" == .* ]] && continue
                ((cat_count++)) || true
                # Count .md files in category (excluding CLAUDE.md)
                cat_files="$(find "$cat_dir" -maxdepth 1 -name '*.md' ! -name 'CLAUDE.md' 2>/dev/null | wc -l)"
                file_count=$((file_count + cat_files))
                if [[ -n "$categories" ]]; then
                    categories="$categories, $cat_name"
                else
                    categories="$cat_name"
                fi
            done < <(find ".kb/$topic" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)

            # Get last updated date from most recent file
            last_updated="$(find ".kb/$topic" -name '*.md' ! -name 'CLAUDE.md' -printf '%T@ %p\n' 2>/dev/null \
                | sort -rn | head -1 | awk '{print $2}' | xargs -r stat -c '%Y' 2>/dev/null \
                | xargs -r date -d @%s +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)"

            # Insert row into Topic Map table (after the header row)
            # Find the line with the table header separator and insert after it
            if grep -qn "^|-------|" ".kb/CLAUDE.md" 2>/dev/null; then
                sep_line="$(grep -n "^|-------|" ".kb/CLAUDE.md" | head -1 | cut -d: -f1)"
                sed -i "${sep_line}a\\| $topic | .kb/$topic/ | $cat_count | $file_count | $last_updated |" ".kb/CLAUDE.md"
                ((REPAIRED++)) || true
                [[ "$QUIET" != "1" ]] && echo "  ⚠ KB index: added missing topic '$topic' ($file_count files)"
            fi
        fi
    done

    # Check Recently Added has entries if subject files exist
    subject_count="$(find .kb -name '*.md' ! -name 'CLAUDE.md' ! -path '*/_refs/*' ! -path '*/_archive*' 2>/dev/null | wc -l)"
    # grep -c prints "0" and exits 1 when there are no matches; swallow the
    # nonzero exit with `|| true` — do NOT use `|| echo 0`, which would emit
    # a second "0" and break the subsequent [[ $var -gt 0 ]] arithmetic test.
    recently_added_count="$(sed -n '/## Recently Added/,/^## /p' ".kb/CLAUDE.md" 2>/dev/null | grep -v 'Date' | grep -c '^|[^-]' || true)"

    if [[ "$subject_count" -gt 0 && "$recently_added_count" -le 1 ]]; then
        # Recently Added is empty but subjects exist — rebuild from file dates
        # Get the 10 most recent subject files
        recent_files="$(find .kb -name '*.md' ! -name 'CLAUDE.md' ! -path '*/_refs/*' ! -path '*/_archive*' -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn | head -10)"

        if [[ -n "$recent_files" ]]; then
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                filepath="$(echo "$line" | awk '{print $2}')"
                # Extract topic/category/subject from path
                # .kb/topic/category/subject.md
                rel="${filepath#.kb/}"
                topic_name="$(echo "$rel" | cut -d/ -f1)"
                category_name="$(echo "$rel" | cut -d/ -f2)"
                subject_name="$(basename "$filepath" .md)"

                # Get file date
                file_date="$(date -r "$filepath" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)"

                # Check if row already exists
                if ! grep -q "$subject_name" ".kb/CLAUDE.md" 2>/dev/null; then
                    # Find Recently Added separator line
                    ra_sep="$(grep -n "^|------|" ".kb/CLAUDE.md" | tail -1 | cut -d: -f1)"
                    if [[ -n "$ra_sep" ]]; then
                        sed -i "${ra_sep}a\\| $file_date | $topic_name | $category_name | $subject_name |" ".kb/CLAUDE.md"
                    fi
                fi
            done <<< "$recent_files"
            ((REPAIRED++)) || true
            [[ "$QUIET" != "1" ]] && echo "  ⚠ KB index: rebuilt Recently Added table ($subject_count subjects found)"
        fi
    fi
fi

# ── Decisions index verification ─────────────────────────────────────────────

if [[ "$CHECK_DECISIONS" == "1" && -d ".decisions" && -f ".decisions/CLAUDE.md" ]]; then
    # Find all decision directories with adr.md
    while IFS= read -r adr_file; do
        slug_dir="$(dirname "$adr_file")"
        slug="$(basename "$slug_dir")"
        [[ "$slug" == "." || "$slug" == ".decisions" ]] && continue

        # Read status from frontmatter
        status="$(grep '^status:' "$adr_file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || echo "unknown")"

        # Check if slug appears anywhere in the decisions index
        if ! grep -q "$slug" ".decisions/CLAUDE.md" 2>/dev/null; then
            # Decision exists but not in index — add it
            case "$status" in
                confirmed|accepted)
                    # Extract problem and date from frontmatter
                    problem="$(grep '^problem:' "$adr_file" 2>/dev/null | head -1 | sed 's/^problem: *"//; s/"$//' || echo "$slug")"
                    adr_date="$(grep '^date:' "$adr_file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || date +%Y-%m-%d)"

                    # Extract recommendation (first line of ## Decision section)
                    recommendation="$(sed -n '/^## Decision/,/^## /{/^## Decision/d; /^## /d; /^$/d; p;}' "$adr_file" 2>/dev/null | head -1 | sed 's/^\*\*Chosen approach: *//; s/\*\*$//' || echo "See ADR")"
                    # Truncate long recommendations
                    if [[ ${#recommendation} -gt 60 ]]; then
                        recommendation="${recommendation:0:57}..."
                    fi

                    # Add to Recently Accepted section
                    ra_sep="$(grep -n "^|---------|" ".decisions/CLAUDE.md" | head -2 | tail -1 | cut -d: -f1)"
                    if [[ -n "$ra_sep" ]]; then
                        sed -i "${ra_sep}a\\| $problem | $slug | $adr_date | $recommendation |" ".decisions/CLAUDE.md"
                        ((REPAIRED++)) || true
                        [[ "$QUIET" != "1" ]] && echo "  ⚠ Decisions index: added missing ADR '$slug' (confirmed)"
                    fi
                    ;;
                deferred)
                    # Add to Deferred section
                    resume="$(sed -n '/^## Resume When/,/^## /{/^## /d; /^$/d; p;}' "$adr_file" 2>/dev/null | head -1 || echo "not specified")"
                    adr_date="$(grep '^date:' "$adr_file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || date +%Y-%m-%d)"

                    deferred_sep="$(sed -n '/## Deferred/,/^## /{/^|---------|/=}' ".decisions/CLAUDE.md" | head -1)"
                    if [[ -n "$deferred_sep" ]]; then
                        sed -i "${deferred_sep}a\\| $slug | $slug | $adr_date | $resume |" ".decisions/CLAUDE.md"
                        ((REPAIRED++)) || true
                        [[ "$QUIET" != "1" ]] && echo "  ⚠ Decisions index: added missing ADR '$slug' (deferred)"
                    fi
                    ;;
                closed)
                    reason="$(sed -n '/^## Reason/,/^## /{/^## /d; /^$/d; p;}' "$adr_file" 2>/dev/null | head -1 || echo "not specified")"
                    adr_date="$(grep '^date:' "$adr_file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || date +%Y-%m-%d)"

                    closed_sep="$(sed -n '/## Closed/,/^## /{/^|---------|/=}' ".decisions/CLAUDE.md" | head -1)"
                    if [[ -n "$closed_sep" ]]; then
                        sed -i "${closed_sep}a\\| $slug | $slug | $adr_date | $reason |" ".decisions/CLAUDE.md"
                        ((REPAIRED++)) || true
                        [[ "$QUIET" != "1" ]] && echo "  ⚠ Decisions index: added missing ADR '$slug' (closed)"
                    fi
                    ;;
            esac
        fi
    done < <(find .decisions -name 'adr.md' 2>/dev/null)

    # Enforce 80-line cap by overflowing oldest "Recently Accepted" rows to
    # history.md. Until v0.16.x this was a warn-and-proceed: the index grew
    # unbounded after auto-repair (e.g. 46 reconstructed ADRs → 151 lines).
    # The cap exists because this file is loaded into context on demand —
    # silent growth burns tokens. The seed CLAUDE.md documents "Once this
    # section exceeds 5 rows, oldest row moves to history.md"; this code
    # enforces it.
    #
    # Tunable: VALLORCINE_DECISIONS_KEEP (default 5) controls how many
    # most-recent rows stay in the index before overflow kicks in.
    line_count="$(wc -l < ".decisions/CLAUDE.md")"
    if [[ "$line_count" -gt 80 ]]; then
        keep="${VALLORCINE_DECISIONS_KEEP:-5}"
        ra_start="$(grep -n '^## Recently Accepted' '.decisions/CLAUDE.md' 2>/dev/null | head -1 | cut -d: -f1)"
        if [[ -n "$ra_start" ]]; then
            # Section bounds: ra_start through the line before the next "^## "
            # heading, or EOF. The found flag ensures END only fires when
            # the loop exits without hitting another heading (EOF case);
            # otherwise the inline-print + END would double-emit.
            ra_end="$(awk -v s="$ra_start" '
                NR>s && /^## /{print NR-1; found=1; exit}
                END{if (!found) print NR}
            ' '.decisions/CLAUDE.md')"
            # Find table separator within section
            sep_line="$(awk -v s="$ra_start" -v e="$ra_end" 'NR>=s && NR<=e && /^\|----/{print NR; exit}' '.decisions/CLAUDE.md')"

            if [[ -n "$sep_line" && -n "$ra_end" ]]; then
                # Row line numbers: between sep and end, starting with "| "
                mapfile -t row_nums < <(awk -v s="$sep_line" -v e="$ra_end" 'NR>s && NR<=e && /^\| / {print NR}' '.decisions/CLAUDE.md')
                total="${#row_nums[@]}"
                if (( total > keep )); then
                    # Sort the rows by accepted-date column (4th pipe field)
                    # descending before trimming. Without this, the overflow
                    # archives bottom-N rows assuming they're oldest — but
                    # auto-repair inserts missing rows on top in filesystem
                    # order, and pre-existing rows live wherever they were
                    # written. Document order ≠ date order. The 2026-05-10
                    # jlsm bug: /curate rotated newer 2026-04-26 ADRs out
                    # and pulled older 2026-03-19 ADRs in. Sorting first
                    # makes the invariant explicit (date-desc) so the
                    # bottom-N overflow really does pick the oldest.
                    first_row="${row_nums[0]}"
                    last_row="${row_nums[$((total - 1))]}"
                    sorted_rows="$(sed -n "${first_row},${last_row}p" '.decisions/CLAUDE.md' \
                        | awk -F'|' '{
                            d=$4
                            gsub(/^[[:space:]]+|[[:space:]]+$/, "", d)
                            printf "%s\t%s\n", d, $0
                          }' \
                        | sort -t$'\t' -k1,1 -r \
                        | cut -f2-)"
                    # Rebuild file with sorted rows replacing the original block.
                    {
                        sed -n "1,$((first_row - 1))p" '.decisions/CLAUDE.md'
                        printf '%s\n' "$sorted_rows"
                        sed -n "$((last_row + 1)),\$p" '.decisions/CLAUDE.md'
                    } > '.decisions/CLAUDE.md.tmp' && mv '.decisions/CLAUDE.md.tmp' '.decisions/CLAUDE.md'

                    # Re-read row positions after the rewrite (line numbers
                    # haven't shifted because we wrote the same number of rows,
                    # but be defensive).
                    mapfile -t row_nums < <(awk -v s="$sep_line" -v e="$ra_end" 'NR>s && NR<=e && /^\| / {print NR}' '.decisions/CLAUDE.md')
                    total="${#row_nums[@]}"

                    overflow_count=$(( total - keep ))
                    # Rows are now in date-desc order. Overflow the LAST
                    # `overflow_count` rows = oldest by accepted-date.
                    first_overflow_idx=$(( total - overflow_count ))
                    first_line="${row_nums[$first_overflow_idx]}"
                    last_line="${row_nums[$((total - 1))]}"

                    overflow_rows="$(sed -n "${first_line},${last_line}p" '.decisions/CLAUDE.md')"

                    # Append to history.md (create with header on first overflow).
                    if [[ ! -f '.decisions/history.md' ]]; then
                        cat > '.decisions/history.md' << 'HISTEOF'
# Decision History

Archived ADRs that overflowed from `CLAUDE.md` once the index exceeded its
80-line cap. Newest archived first within each batch; batches accumulate
oldest-first overall.

## Archived from Recently Accepted

| Problem | Slug | Accepted | Recommendation |
|---------|------|----------|----------------|
HISTEOF
                    fi
                    printf '%s\n' "$overflow_rows" >> '.decisions/history.md'

                    # Delete the overflowed range from CLAUDE.md.
                    sed -i "${first_line},${last_line}d" '.decisions/CLAUDE.md'

                    ((REPAIRED++)) || true
                    [[ "$QUIET" != "1" ]] && \
                        echo "  ⚠ Decisions index: archived $overflow_count Recently Accepted rows to history.md (kept $keep newest)"
                fi
            fi
        fi

        # Recheck after overflow attempt.
        line_count="$(wc -l < ".decisions/CLAUDE.md")"
        if [[ "$line_count" -gt 80 && "$QUIET" != "1" ]]; then
            echo "  ⚠ Decisions index: still $line_count lines after Recently Accepted overflow — review Active/Deferred/Closed sections manually"
        fi
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────

if [[ "$REPAIRED" -gt 0 && "$QUIET" != "1" ]]; then
    echo "  Index verification: $REPAIRED repair(s) made"
fi

exit 0
