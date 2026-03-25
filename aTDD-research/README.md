# aTDD Validation Research

Comparative study of standard TDD vs adversarial TDD (aTDD) using 12 features
from the [jlsm](../../nathannorthcutt/jlsm) storage engine project. Data was
extracted from 130 Claude Code JSONL sessions covering the full development
history.

## External dependency

This research requires the **jlsm repository** at `../../nathannorthcutt/jlsm`
(absolute: `/home/nnorthcutt/Code/github/nathannorthcutt/jlsm`). The harness
creates isolated git clones at specific commits — the planning-state overlays
are applied on top of those checkouts.

## Directory structure

```
aTDD-research/
  README.md                   # This file
  DATA-PROVENANCE.md          # Manual interventions, overrides, exclusion rationale
  feature-inventory.json      # 12 features: git SHAs, token costs, file lists, test counts
  missing-features.json       # 3 excluded sub-features (interleaved in mega-sessions)
  feature-aliases.json        # Branch name → canonical slug mappings
  feature-commits.json        # Git commit SHAs for state reconstruction
  session-map.json            # Maps 130 JSONL sessions → features by branch/command
  token-report.json           # Per-stage token breakdown (large — ~111MB)

  briefs/                     # Feature scope documents (15 briefs)
    <slug>-brief.md           # Actors, inputs, business rules, acceptance criteria

  work-plans/                 # Implementation plans (15 plans)
    <slug>-work-plan.md       # Constructs, contracts, work units, implementation order

  planning-state/             # Reconstructed end-of-planning state per feature
    <slug>/
      manifest.json           # Ordered list of Write/Edit operations
      edits/                  # Individual edit operations (JSON)
      files/                  # File snapshots (.feature/ directory state)

  sanitized/                  # PII-scrubbed JSONL session logs (84 sessions)
    <session-uuid>.jsonl      # Sanitized session data
    sanitization-manifest.json
    session-map.json

  harness/                    # Automation scripts (see harness/README.md)
    run-feature.py            # Set up isolated checkout + vallorcine for one feature
    run-all.py                # Batch runner for all features
    extract-planning-state.py # Parse JSONL → planning overlay
    apply-overlay.py          # Apply planning overlay onto git checkout
    collect-results.py        # Gather metrics after aTDD run
    report.py                 # Generate cost/benefit comparison report

  results/                    # Completed validation runs
    encrypt-memory-data/          # Audit mode — 3 rounds, 8 bugs, 1.4M billable
    encrypt-memory-data-greenfield/  # Greenfield — 3 rounds, 20 bugs, 2.2M billable
    striped-block-cache/          # Audit placeholder
    striped-block-cache-audit/    # Audit mode
    striped-block-cache-greenfield/   # Greenfield — 3 rounds, 0 confirmed bugs
    striped-block-cache-greenfield-v2/ # Re-run with updated harness

  extract-tokens.py           # Token extraction from JSONL sessions
  map-sessions.py             # Session-to-feature mapping
  sanitize-sessions.py        # PII removal with SHA256 verification
```

## Features in scope

12 features, ordered by TDD token cost:

| Feature | Files | Insertions | TDD tokens | Sessions | Tests |
|---------|-------|------------|------------|----------|-------|
| float16-vector-support | 39 | 3,975 | 7M | 6 | 21 |
| table-indices-and-queries | 20 | 2,673 | 7M | 2 | — |
| striped-block-cache | 3 | 575 | 9M | 10 | 26 |
| in-process-database-engine | 40 | 4,617 | 11M | 1 | 134 |
| sql-query-support | 22 | 2,446 | 13M | 3 | — |
| engine-clustering | 28 | 4,334 | 14M | 3 | 340 |
| block-compression | 27 | 2,893 | 20M | 5 | — |
| vector-field-type | 31 | 2,192 | 32M | 1 | — |
| streaming-block-decompression | 8 | 696 | 60M | 1 | — |
| encrypt-memory-data | 47 | 6,018 | 64M | 1 | 426 |
| table-partitioning | 34 | 3,851 | 89M | 4 | 85 |
| optimize-document-serializer | 4 | 345 | 118M | 2 | — |

3 sub-features excluded (interleaved within encrypt-memory-data mega-session):
extract-core-encryption, fix-encryption-performance, ope-type-aware-bounds.

## Validation results so far

### encrypt-memory-data (2026-03-24)
- **Greenfield aTDD:** 3 rounds, 20 bugs, 34.1M total tokens, 9.1 bugs/M billable
- **Audit aTDD:** 3 rounds, 8 bugs (7+1+0), 17.1M total tokens, 5.7 bugs/M billable
- **Combined pipeline:** 633 tests, 3 impl bugs, 0 audit bugs, 17.7M total tokens (3.7x cheaper than original 64.9M TDD)
- Key finding: spec analysis prevented the bug classes that aTDD found post-hoc

### striped-block-cache (2026-03-24)
- **Greenfield aTDD:** 3 rounds, 0 confirmed bugs (5 resolved, 3 tendency, 2 ADR-protected)
- **Combined pipeline:** 62 tests, 0 bugs, 2.9M tokens (7.3x cheaper than original 21.6M TDD)
- Simpler feature — TDD already covered well

## Pipeline enhancements shipped from findings

These improvements were backported into the standard TDD pipeline agents:
- **test-writer-agent:** defensive test vectors (boundary values, error paths, security)
- **code-writer-agent:** fix-forward rule (scan for same anti-pattern after fixing)
- **refactor-agent:** assert-only validation check, exception swallowing check
- **tdd-protocol:** 5-minute Bash timeout on all test execution

## How to run a validation

```bash
# Single feature, audit mode (post-TDD, find missed bugs)
python3 harness/run-feature.py \
  --jlsm-path ../../nathannorthcutt/jlsm \
  --feature table-indices-and-queries \
  --mode audit \
  --max-rounds 3

# Single feature, greenfield mode (replace TDD entirely)
python3 harness/run-feature.py \
  --jlsm-path ../../nathannorthcutt/jlsm \
  --feature table-indices-and-queries \
  --mode greenfield \
  --max-rounds 3

# Then follow the printed instructions to run Claude Code in the checkout
```

## Data expiry

JSONL session logs in `~/.claude/projects/` expire around **2026-04-02**.
The sanitized copies in `sanitized/` and extracted planning states are permanent.
