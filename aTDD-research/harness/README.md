# aTDD Validation Harness

Automates the comparison between standard TDD and adversarial TDD (aTDD)
across jlsm features. Produces reproducible metrics for cost/benefit analysis.

## What it does

For each feature in the inventory:

1. **Reconstructs post-standard-TDD state** — checks out the feature commit
   in jlsm, giving us the code as it existed after standard TDD completed
2. **Runs aTDD audit** — executes `/atdd-audit` against the feature to find
   bugs that standard TDD missed
3. **Collects metrics** — tokens per round, tests written, confirmed bugs,
   theoretical concerns, convergence signal
4. **Produces comparison report** — standard TDD cost (from extracted data)
   vs aTDD additional cost vs additional bugs found

## Prerequisites

- jlsm repository cloned locally
- vallorcine installed in jlsm (with aTDD skills)
- Python 3.8+
- Claude Code CLI

## Usage

```bash
# Run against a single feature
python3 run-feature.py --jlsm-path /path/to/jlsm \
                       --feature table-partitioning \
                       --max-rounds 3

# Run against all features
python3 run-all.py --jlsm-path /path/to/jlsm \
                   --inventory ../feature-inventory.json \
                   --max-rounds 3

# Generate comparison report from collected results
python3 report.py --results-dir results/ \
                  --baseline ../token-report.json
```

## Output

```
results/
  <feature-slug>/
    pre-run-state.json     # git SHA, file checksums before aTDD
    atdd-log.json          # per-round metrics from aTDD execution
    post-run-state.json    # git SHA, file checksums after aTDD
    new-tests/             # adversarial test files written
  comparison-report.json   # aggregated standard vs aTDD comparison
  comparison-report.md     # human-readable summary
```
