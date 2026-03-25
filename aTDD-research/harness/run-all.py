#!/usr/bin/env python3
"""Run aTDD validation across all jlsm features, one at a time.

Sets up each feature's worktree and outputs instructions for the manual
Claude Code invocation. After each feature completes, collect results
and generate an incremental report.

Usage:
    python3 run-all.py --jlsm-path /path/to/jlsm \
                       --max-rounds 3 \
                       [--inventory ../feature-inventory.json] \
                       [--results-dir results/] \
                       [--start-from <slug>]
"""

import argparse
import json
import os
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(
        description="Run aTDD validation across all features"
    )
    parser.add_argument("--jlsm-path", required=True)
    parser.add_argument("--max-rounds", type=int, default=3)
    parser.add_argument("--inventory", default=None)
    parser.add_argument("--results-dir", default="results")
    parser.add_argument("--start-from", default=None,
                        help="Skip features before this slug (alphabetical)")
    args = parser.parse_args()

    # Find inventory
    inventory_path = args.inventory
    if not inventory_path:
        inventory_path = os.path.join(os.path.dirname(__file__), "..", "feature-inventory.json")
    inventory_path = os.path.abspath(inventory_path)

    # Load all features
    with open(inventory_path) as f:
        inventory = json.load(f)

    # Also load missing features
    missing_path = os.path.join(os.path.dirname(inventory_path), "missing-features.json")
    all_features = {}
    for slug, feat in inventory.get("features", {}).items():
        all_features[slug] = {
            "feature_sha": feat["git"]["feature_sha"],
            "parent_sha": feat["git"]["parent_sha"],
            "commit_msg": feat["git"]["commit_msg"],
            "files_changed": feat["git"]["files_changed"],
            "tdd_tokens_best": feat["tokens"]["tdd_tokens_best"],
        }

    if os.path.exists(missing_path):
        with open(missing_path) as f:
            missing = json.load(f)
        for slug, feat in missing.get("features", {}).items():
            all_features[slug] = {
                "feature_sha": feat["feature_sha"],
                "parent_sha": feat["parent_sha"],
                "commit_msg": feat["commit_msg"],
                "files_changed": feat.get("files_changed", 0),
                "tdd_tokens_best": feat.get("tdd_tokens", 0),
            }

    # Sort by complexity (files changed) for a natural progression
    sorted_features = sorted(all_features.items(),
                            key=lambda x: x[1]["files_changed"])

    # Skip features before start-from
    if args.start_from:
        skip = True
        filtered = []
        for slug, feat in sorted_features:
            if slug == args.start_from:
                skip = False
            if not skip:
                filtered.append((slug, feat))
        sorted_features = filtered

    # Check which features already have results
    results_dir = os.path.abspath(args.results_dir)
    completed = set()
    for slug, _ in sorted_features:
        result_file = os.path.join(results_dir, slug, "atdd-results.json")
        if os.path.exists(result_file):
            completed.add(slug)

    print(f"\n=== aTDD Validation Plan ===", file=sys.stderr)
    print(f"  Features: {len(sorted_features)}", file=sys.stderr)
    print(f"  Already completed: {len(completed)}", file=sys.stderr)
    print(f"  Remaining: {len(sorted_features) - len(completed)}", file=sys.stderr)
    print(f"  Max rounds per feature: {args.max_rounds}", file=sys.stderr)
    print(f"\n  Feature order (by complexity):", file=sys.stderr)
    for i, (slug, feat) in enumerate(sorted_features, 1):
        status = "DONE" if slug in completed else "pending"
        print(f"    {i:2d}. {slug:40s}  {feat['files_changed']:3d} files  "
              f"{feat['tdd_tokens_best']:>12,} std tokens  [{status}]", file=sys.stderr)

    print(f"\n  To run each feature:", file=sys.stderr)
    for slug, feat in sorted_features:
        if slug in completed:
            continue
        print(f"\n  --- {slug} ---", file=sys.stderr)
        print(f"  python3 harness/run-feature.py --jlsm-path {args.jlsm_path} "
              f"--feature {slug} --max-rounds {args.max_rounds} "
              f"--results-dir {args.results_dir}", file=sys.stderr)
        print(f"  # Then run Claude Code in the worktree", file=sys.stderr)
        print(f"  # Then collect: python3 harness/collect-results.py "
              f"--jlsm-path <worktree> --feature {slug} "
              f"--results-dir {args.results_dir}", file=sys.stderr)

    print(f"\n  After each feature, regenerate the report:", file=sys.stderr)
    print(f"  python3 harness/report.py --results-dir {args.results_dir} "
          f"--baseline {os.path.join(os.path.dirname(inventory_path), 'token-report.json')} "
          f"--inventory {inventory_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
