#!/usr/bin/env bash
# Scenario: /curate KB structural drift detectors (Analyses 23, 24, 25).
#
# Validates curate-scan.sh's three KB-quality analyses:
#
#   23. Cross-folder filename collisions
#   24. Schema drift (frontmatter validation)
#   25. Type ↔ location mismatch
#
# Layered cover:
#
#   1. Two files with the same name under different folders are flagged.
#   2. A file with no frontmatter is flagged.
#   3. Missing required fields (title, last_researched, research_status) are flagged.
#   4. Bad enum values (research_status not in {active,mature,stable,deprecated}) are flagged.
#   5. Legacy research_status (archived) is flagged with a distinct issue code.
#   6. Type-specific required fields (domain/severity, domains/constructs) are flagged when missing.
#   7. confidence: high without ≥2 corroborating sources is flagged as overclaim.
#   8. topic/category fields that disagree with the file's path are flagged.
#   9. type: adversarial-finding outside patterns/ is flagged as location mismatch.
#  10. type: feature-footprint outside architecture/feature-footprints/ is flagged.
#  11. Files with valid frontmatter and correct location are NOT flagged.
#  12. _refs/ files and CLAUDE.md files are excluded from all three analyses.
#
# Run from repo root: bash tests/scenario-curate-kb-schema-drift.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

passed=0
failed=0
total=0

pass() { ((passed++)) || true; ((total++)) || true; echo "  PASS  $1"; }
fail() {
  ((failed++)) || true; ((total++)) || true
  echo "  FAIL  $1"
  [[ -n "${2:-}" ]] && echo "        $2"
}

assert_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc" "pattern not found: $pattern"
  fi
}

assert_not_contains() {
  local file="$1" pattern="$2" desc="$3"
  if ! grep -qE "$pattern" "$file" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc" "pattern unexpectedly found: $pattern"
  fi
}

echo ""
echo "scenario: /curate KB schema drift (Analyses 23, 24, 25)"
echo "────────────────────────────────────────────────"

TMPDIR_TEST="$(mktemp -d /tmp/vallorcine/curate-kb-schema.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PROJ="$TMPDIR_TEST/proj"
mkdir -p "$PROJ/.kb/_refs" \
         "$PROJ/.kb/algorithms/encryption" \
         "$PROJ/.kb/patterns/validation" \
         "$PROJ/.kb/patterns/concurrency" \
         "$PROJ/.kb/architecture/feature-footprints" \
         "$PROJ/.kb/systems/database-engines" \
         "$PROJ/.curate"
cd "$PROJ"

# Init git so timestamp logic works.
git init -q
git config user.email test@example.com
git config user.name "Test"

# .kb root index with no entries (script tolerates this).
cat > .kb/CLAUDE.md << 'EOF'
# Knowledge Base — Root Index
## Topic Map
| Topic | Path | Categories | Files | Last Updated |
|-------|------|------------|-------|--------------|
EOF

# _refs file should be excluded from all analyses.
cat > .kb/_refs/frontmatter.md << 'EOF'
---
type: reference-fragment
title: KB Frontmatter Schema
---
# Schema reference (must be ignored by scan).
EOF

# ── Fixture 1: filename collision ──────────────────────────────────────────
# Same filename in two patterns/ subfolders.
cat > .kb/patterns/validation/partial-init-no-rollback.md << 'EOF'
---
title: "Partial Init No Rollback (Validation)"
type: adversarial-finding
domain: validation
severity: confirmed
applies_to: ["modules/foo"]
last_researched: "2026-04-22"
research_status: stable
---
# Partial Init No Rollback
## What happens
Builder mutation before validation.
## Why implementations default to this
Reads naturally.
## Test guidance
Test reverse order.
## Found in
- feature-a (round 1, 2026-04-22): noted
EOF

cat > .kb/patterns/concurrency/partial-init-no-rollback.md << 'EOF'
---
title: "Partial Init No Rollback (Concurrency)"
type: adversarial-finding
domain: concurrency
severity: confirmed
applies_to: ["modules/bar"]
last_researched: "2026-04-22"
research_status: stable
---
# Partial Init No Rollback (Concurrency)
## What happens
Multi-step init across threads.
## Why implementations default to this
Single-threaded mental model.
## Test guidance
Inject failures.
## Found in
- feature-b (round 1, 2026-04-22): noted
EOF

# ── Fixture 2: schema drift (multiple issues per file) ─────────────────────

# Missing title + missing last_researched + bad research_status.
cat > .kb/systems/database-engines/missing-fields.md << 'EOF'
---
type: research
research_status: foo
applies_to: []
---
# Entry With Missing Fields
EOF

# Legacy research_status: archived.
cat > .kb/systems/database-engines/legacy-status.md << 'EOF'
---
title: "Legacy Status Entry"
type: research
research_status: archived
last_researched: "2025-01-01"
applies_to: []
---
# Legacy Status
EOF

# Adversarial-finding missing required domain + severity.
cat > .kb/patterns/validation/missing-finding-fields.md << 'EOF'
---
title: "Finding Without Domain"
type: adversarial-finding
applies_to: ["modules/foo"]
last_researched: "2026-04-22"
research_status: stable
---
# Finding Without Domain
## What happens
Test
## Why implementations default to this
Test
## Test guidance
Test
## Found in
- feature (round 1, 2026-04-22): noted
EOF

# Feature-footprint missing required domains + constructs.
cat > .kb/architecture/feature-footprints/missing-footprint-fields.md << 'EOF'
---
title: "footprint-missing-fields"
type: feature-footprint
applies_to: ["modules/x"]
last_researched: "2026-04-22"
research_status: stable
---
# footprint-missing-fields
EOF

# Confidence overclaim — high but only 1 source.
cat > .kb/systems/database-engines/confidence-overclaim.md << 'EOF'
---
title: "Confidence Overclaim Entry"
type: research
applies_to: []
last_researched: "2026-04-22"
research_status: stable
confidence: high
sources:
  - url: "https://example.com/single"
    title: "Single source"
    accessed: "2026-04-22"
    type: docs
---
# Single-source High-confidence
EOF

# Topic/category mismatch — frontmatter says different from path.
cat > .kb/systems/database-engines/path-mismatch.md << 'EOF'
---
title: "Path Mismatch Entry"
type: research
topic: algorithms
category: encryption
applies_to: []
last_researched: "2026-04-22"
research_status: stable
---
# Path Mismatch
EOF

# Missing frontmatter entirely.
cat > .kb/systems/database-engines/no-frontmatter.md << 'EOF'
# No frontmatter at all

This file has no YAML block.
EOF

# ── Fixture 3: type/location mismatch ──────────────────────────────────────

# Adversarial-finding under algorithms/ instead of patterns/.
cat > .kb/algorithms/encryption/asymmetric-operand-assumption.md << 'EOF'
---
title: "Asymmetric Operand Assumption"
type: adversarial-finding
domain: data-integrity
severity: tendency
applies_to: ["modules/sql"]
last_researched: "2026-03-25"
research_status: active
---
# Asymmetric Operand Assumption
## What happens
SQL translator assumes left=field.
## Why implementations default to this
Common case.
## Test guidance
Test reversed.
## Found in
- sql-feature (round 1, 2026-03-25): noted
EOF

# Feature-footprint outside architecture/feature-footprints/.
cat > .kb/algorithms/encryption/wrong-place-footprint.md << 'EOF'
---
title: "wrong-place-footprint"
type: feature-footprint
domains: [encryption]
constructs: [Encryptor]
applies_to: ["modules/enc"]
last_researched: "2026-04-22"
research_status: stable
---
# wrong-place-footprint
## What it built
Encryptor.
EOF

# ── Fixture 4: a CLEAN entry that should NOT be flagged ────────────────────

cat > .kb/patterns/validation/clean-finding.md << 'EOF'
---
title: "Clean Finding"
type: adversarial-finding
domain: validation
severity: confirmed
applies_to: ["modules/clean"]
last_researched: "2026-04-22"
research_status: stable
confidence: medium
---
# Clean Finding
## What happens
Test
## Why implementations default to this
Test
## Test guidance
Test
## Found in
- a-feature (round 1, 2026-04-22): noted
EOF

git add -A
git commit -q --date='2026-04-22T00:00:00Z' -m "fixtures"

# Run scan with link-rot disabled to keep the test fast.
MAX_LINK_ROT_URLS=0 \
    bash "$REPO_ROOT/scripts/curate-scan.sh" --init >/dev/null 2>&1 || true

SUMMARY="$PROJ/.curate/scan-summary.md"

if [[ ! -s "$SUMMARY" ]]; then
    fail "scan-summary.md was created and non-empty"
    echo ""
    echo "── Summary ──"
    echo "  Passed: $passed/$total"
    echo "  Failed: $failed/$total"
    [[ $failed -eq 0 ]] && exit 0 || exit 1
fi

# ── Analysis 23: filename collisions ──────────────────────────────────────

assert_contains "$SUMMARY" "## KB Filename Collisions" \
    "section: KB Filename Collisions present"

assert_contains "$SUMMARY" "partial-init-no-rollback.md" \
    "collision: partial-init-no-rollback flagged"

# ── Analysis 24: schema drift ─────────────────────────────────────────────

assert_contains "$SUMMARY" "## KB Schema Drift" \
    "section: KB Schema Drift present"

assert_contains "$SUMMARY" "missing-fields.md.*missing-title" \
    "drift: missing-title issue raised"

assert_contains "$SUMMARY" "missing-fields.md.*missing-last-researched" \
    "drift: missing-last-researched issue raised"

assert_contains "$SUMMARY" "missing-fields.md.*bad-research-status" \
    "drift: bad-research-status issue raised"

assert_contains "$SUMMARY" "legacy-status.md.*legacy-research-status" \
    "drift: legacy-research-status (archived) flagged"

assert_contains "$SUMMARY" "missing-finding-fields.md.*missing-domain" \
    "drift: adversarial-finding missing-domain"

assert_contains "$SUMMARY" "missing-finding-fields.md.*missing-severity" \
    "drift: adversarial-finding missing-severity"

assert_contains "$SUMMARY" "missing-footprint-fields.md.*missing-domains" \
    "drift: feature-footprint missing-domains"

assert_contains "$SUMMARY" "missing-footprint-fields.md.*missing-constructs" \
    "drift: feature-footprint missing-constructs"

assert_contains "$SUMMARY" "confidence-overclaim.md.*confidence-overclaim" \
    "drift: confidence-overclaim flagged"

assert_contains "$SUMMARY" "path-mismatch.md.*topic-mismatch" \
    "drift: topic-mismatch flagged"

assert_contains "$SUMMARY" "path-mismatch.md.*category-mismatch" \
    "drift: category-mismatch flagged"

assert_contains "$SUMMARY" "no-frontmatter.md.*missing-frontmatter" \
    "drift: missing-frontmatter flagged"

# Clean entry should NOT appear in schema drift.
assert_not_contains "$SUMMARY" "clean-finding.md.*missing-" \
    "drift: clean entry not flagged for missing fields"

# _refs files should NEVER appear as findings of the three KB-quality
# analyses (23, 24, 25). They MAY appear in general git-history analyses
# like Churn Hotspots — that's expected for a file that gets edited.
# Extract just the three KB-quality sections and check those.
KB_QUALITY_SECTIONS="$(awk '
    /^## KB Filename Collisions/ { in_section = 1 }
    /^## KB Schema Drift/        { in_section = 1 }
    /^## KB Type\/Location/      { in_section = 1 }
    /^## / && !/^## KB / && in_section { in_section = 0 }
    in_section { print }
' "$SUMMARY")"
if echo "$KB_QUALITY_SECTIONS" | grep -qE '\| \.kb/_refs/'; then
    fail "exclude: _refs files not flagged in KB-quality analyses" \
        "row matched: $(echo "$KB_QUALITY_SECTIONS" | grep -E '\| \.kb/_refs/' | head -1)"
else
    pass "exclude: _refs files not flagged in KB-quality analyses"
fi

# ── Analysis 25: type/location mismatch ───────────────────────────────────

assert_contains "$SUMMARY" "## KB Type/Location Mismatch" \
    "section: KB Type/Location Mismatch present"

assert_contains "$SUMMARY" "asymmetric-operand-assumption.md.*adversarial-finding outside patterns" \
    "location: adversarial-finding outside patterns/ flagged"

assert_contains "$SUMMARY" "wrong-place-footprint.md.*feature-footprint outside architecture/feature-footprints" \
    "location: feature-footprint outside architecture/feature-footprints/ flagged"

# Clean entry should NOT appear in location mismatch.
assert_not_contains "$SUMMARY" "clean-finding.md.*outside" \
    "location: clean entry not flagged"

# ── Final report ──────────────────────────────────────────────────────────

echo ""
echo "── Summary ──"
echo "  Passed: $passed/$total"
echo "  Failed: $failed/$total"

[[ $failed -eq 0 ]] && exit 0 || exit 1
