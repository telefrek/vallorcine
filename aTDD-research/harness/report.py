#!/usr/bin/env python3
"""Generate comparison report from aTDD validation results.

Reads collected results for all features and the standard TDD baseline
(token-report.json) to produce a structured comparison.

Usage:
    python3 report.py --results-dir results/ \
                      --baseline ../token-report.json \
                      [--inventory ../feature-inventory.json] \
                      [--output comparison-report]
"""

import argparse
import json
import os
import sys


def load_baseline(baseline_path, inventory_path, missing_path):
    """Load standard TDD baseline data from token-report and inventory."""
    baseline = {}

    if os.path.exists(baseline_path):
        with open(baseline_path) as f:
            token_data = json.load(f)
        for slug, feat in token_data.get("features", {}).items():
            baseline[slug] = {
                "tdd_tokens": feat.get("tdd_tokens_best", 0),
                "pre_tdd_tokens": feat.get("pre_tdd_tokens", 0),
                "total_tokens": feat.get("total_tokens", 0),
                "tdd_method": feat.get("tdd_method", "unknown"),
                "test_runs": feat.get("test_runs", 0),
                "work_units": len(feat.get("work_units", [])),
            }

    if inventory_path and os.path.exists(inventory_path):
        with open(inventory_path) as f:
            inventory = json.load(f)
        for slug, feat in inventory.get("features", {}).items():
            if slug in baseline:
                baseline[slug]["files_changed"] = feat.get("git", {}).get("files_changed", 0)
                baseline[slug]["insertions"] = feat.get("git", {}).get("insertions", 0)
                baseline[slug]["commit_msg"] = feat.get("git", {}).get("commit_msg", "")

    if missing_path and os.path.exists(missing_path):
        with open(missing_path) as f:
            missing = json.load(f)
        for slug, feat in missing.get("features", {}).items():
            baseline[slug] = {
                "tdd_tokens": feat.get("tdd_tokens", 0),
                "total_tokens": feat.get("total_tokens", 0),
                "files_changed": feat.get("files_changed", 0),
                "insertions": feat.get("insertions", 0),
                "commit_msg": feat.get("commit_msg", ""),
                "tdd_method": "subagent",
                "pre_tdd_tokens": 0,
                "test_runs": 0,
                "work_units": 0,
            }

    return baseline


def load_atdd_results(results_dir):
    """Load aTDD results for all features that have been collected."""
    results = {}
    if not os.path.isdir(results_dir):
        return results

    for slug in os.listdir(results_dir):
        result_file = os.path.join(results_dir, slug, "atdd-results.json")
        if os.path.exists(result_file):
            with open(result_file) as f:
                results[slug] = json.load(f)

    return results


def compute_comparison(baseline, atdd_results):
    """Compute per-feature and aggregate comparisons."""
    features = []

    for slug in sorted(set(list(baseline.keys()) + list(atdd_results.keys()))):
        base = baseline.get(slug, {})
        atdd = atdd_results.get(slug)

        entry = {
            "slug": slug,
            "standard_tdd": {
                "tdd_tokens": base.get("tdd_tokens", 0),
                "total_tokens": base.get("total_tokens", 0),
                "files_changed": base.get("files_changed", 0),
                "method": base.get("tdd_method", "unknown"),
            },
        }

        if atdd:
            atdd_tokens = atdd.get("session_tokens", {})
            atdd_total = (atdd_tokens.get("input", 0) + atdd_tokens.get("output", 0) +
                         atdd_tokens.get("cache_read", 0) + atdd_tokens.get("cache_create", 0))
            status = atdd.get("atdd_status", {})
            issues = atdd.get("known_issues", {})
            tests = atdd.get("adversarial_tests", {})

            confirmed_bugs = issues.get("resolved", 0)
            additional_tests = tests.get("total_test_methods", 0)

            # Cost per additional bug
            standard_tdd = base.get("tdd_tokens", 0)
            token_delta = atdd_total  # aTDD is purely additional cost
            cost_per_bug = (token_delta / confirmed_bugs) if confirmed_bugs > 0 else None

            # Cost multiplier
            multiplier = ((standard_tdd + atdd_total) / standard_tdd
                         if standard_tdd > 0 else None)

            entry["atdd"] = {
                "rounds_completed": status.get("current_round", 0),
                "status": status.get("status", "not-run"),
                "atdd_tokens": atdd_total,
                "confirmed_bugs": confirmed_bugs,
                "tendencies": issues.get("tendency", 0),
                "watch_items": issues.get("watch", 0),
                "additional_tests": additional_tests,
                "test_files": tests.get("file_count", 0),
            }
            entry["comparison"] = {
                "token_delta": token_delta,
                "cost_per_bug": cost_per_bug,
                "cost_multiplier": multiplier,
                "bugs_per_million_tokens": (
                    (confirmed_bugs / (token_delta / 1_000_000))
                    if token_delta > 0 else None
                ),
            }
        else:
            entry["atdd"] = None
            entry["comparison"] = None

        features.append(entry)

    return features


def generate_markdown(features):
    """Generate a human-readable markdown report."""
    lines = ["# aTDD vs Standard TDD — Comparison Report\n"]

    # Summary table
    lines.append("## Summary\n")
    lines.append("| Feature | Std TDD tokens | aTDD tokens | Bugs found | "
                 "Cost/bug | Multiplier |")
    lines.append("|---------|---------------|-------------|------------|"
                 "---------|------------|")

    total_std = 0
    total_atdd = 0
    total_bugs = 0

    for f in features:
        std = f["standard_tdd"]["tdd_tokens"]
        total_std += std

        if f["atdd"]:
            atdd = f["atdd"]["atdd_tokens"]
            bugs = f["atdd"]["confirmed_bugs"]
            total_atdd += atdd
            total_bugs += bugs

            cpb = f["comparison"]["cost_per_bug"]
            mult = f["comparison"]["cost_multiplier"]
            cpb_str = f"{cpb:,.0f}" if cpb else "N/A"
            mult_str = f"{mult:.2f}x" if mult else "N/A"
            lines.append(
                f"| {f['slug']} | {std:,} | {atdd:,} | {bugs} | "
                f"{cpb_str} | {mult_str} |"
            )
        else:
            lines.append(f"| {f['slug']} | {std:,} | — | — | — | — |")

    lines.append("")

    # Aggregates
    if total_bugs > 0:
        avg_cpb = total_atdd / total_bugs
        overall_mult = (total_std + total_atdd) / total_std if total_std > 0 else 0
        lines.append("## Aggregate metrics\n")
        lines.append(f"- **Total standard TDD tokens:** {total_std:,}")
        lines.append(f"- **Total aTDD tokens (additional):** {total_atdd:,}")
        lines.append(f"- **Total bugs found by aTDD:** {total_bugs}")
        lines.append(f"- **Average cost per bug:** {avg_cpb:,.0f} tokens")
        lines.append(f"- **Overall cost multiplier:** {overall_mult:.2f}x")
        lines.append(f"- **Bugs per million aTDD tokens:** "
                     f"{(total_bugs / (total_atdd / 1_000_000)):.1f}")
    else:
        lines.append("## Aggregate metrics\n")
        lines.append("No aTDD results collected yet.")

    lines.append("")

    # Per-feature detail
    lines.append("## Per-feature detail\n")
    for f in features:
        if not f["atdd"]:
            continue
        lines.append(f"### {f['slug']}\n")
        lines.append(f"- Standard TDD: {f['standard_tdd']['tdd_tokens']:,} tokens "
                     f"({f['standard_tdd']['method']})")
        lines.append(f"- aTDD rounds: {f['atdd']['rounds_completed']}")
        lines.append(f"- aTDD tokens: {f['atdd']['atdd_tokens']:,}")
        lines.append(f"- Confirmed bugs: {f['atdd']['confirmed_bugs']}")
        lines.append(f"- Additional tests: {f['atdd']['additional_tests']} "
                     f"({f['atdd']['test_files']} files)")
        lines.append(f"- Tendencies: {f['atdd']['tendencies']}")
        lines.append(f"- Watch items: {f['atdd']['watch_items']}")
        if f["comparison"]["cost_per_bug"]:
            lines.append(f"- Cost per bug: {f['comparison']['cost_per_bug']:,.0f} tokens")
        if f["comparison"]["cost_multiplier"]:
            lines.append(f"- Cost multiplier: {f['comparison']['cost_multiplier']:.2f}x")
        lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Generate aTDD vs standard TDD comparison report"
    )
    parser.add_argument("--results-dir", default="results",
                        help="Directory with collected aTDD results")
    parser.add_argument("--baseline", required=True,
                        help="Path to token-report.json (standard TDD baseline)")
    parser.add_argument("--inventory", default=None,
                        help="Path to feature-inventory.json")
    parser.add_argument("--output", default="comparison-report",
                        help="Output filename prefix (default: comparison-report)")
    args = parser.parse_args()

    # Find missing-features.json alongside baseline
    baseline_dir = os.path.dirname(os.path.abspath(args.baseline))
    missing_path = os.path.join(baseline_dir, "missing-features.json")

    baseline = load_baseline(args.baseline, args.inventory, missing_path)
    atdd_results = load_atdd_results(args.results_dir)

    print(f"Baseline features: {len(baseline)}", file=sys.stderr)
    print(f"aTDD results collected: {len(atdd_results)}", file=sys.stderr)

    features = compute_comparison(baseline, atdd_results)

    # Write JSON report
    json_path = os.path.join(args.results_dir, f"{args.output}.json")
    with open(json_path, "w") as f:
        json.dump({"features": features}, f, indent=2)
    print(f"JSON report: {json_path}", file=sys.stderr)

    # Write markdown report
    md_path = os.path.join(args.results_dir, f"{args.output}.md")
    with open(md_path, "w") as f:
        f.write(generate_markdown(features))
    print(f"Markdown report: {md_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
