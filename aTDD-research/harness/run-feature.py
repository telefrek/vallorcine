#!/usr/bin/env python3
"""Run aTDD validation against a single jlsm feature.

Sets up an isolated checkout at the feature commit, installs vallorcine
(with aTDD skills), generates a scope manifest limiting the audit to only
the feature's files, and outputs the Claude Code invocation command.

Usage:
    python3 run-feature.py --jlsm-path /path/to/jlsm \
                           --vallorcine-path /path/to/vallorcine \
                           --feature table-partitioning \
                           --max-rounds 3 \
                           [--inventory ../feature-inventory.json] \
                           [--results-dir results/] \
                           [--work-dir /tmp/atdd-validation]
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime


def file_checksums(directory, extensions=None):
    """Compute SHA256 checksums for source files in a directory."""
    checksums = {}
    if extensions is None:
        extensions = {".java", ".py", ".ts", ".js", ".go", ".rs", ".kt", ".scala"}
    for root, dirs, files in os.walk(directory):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in
                   ("build", "target", "node_modules", "__pycache__", ".gradle")]
        for fname in files:
            if any(fname.endswith(ext) for ext in extensions):
                fpath = os.path.join(root, fname)
                relpath = os.path.relpath(fpath, directory)
                try:
                    h = hashlib.sha256()
                    with open(fpath, "rb") as f:
                        for chunk in iter(lambda: f.read(8192), b""):
                            h.update(chunk)
                    checksums[relpath] = h.hexdigest()
                except (OSError, IOError):
                    checksums[relpath] = "ERROR"
    return checksums


def git_run(repo_path, *args, check=False):
    """Run a git command."""
    result = subprocess.run(
        ["git", "-C", repo_path] + list(args),
        capture_output=True, text=True,
    )
    if check and result.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {result.stderr}")
    return result


def collect_feature_metadata(inventory_path, missing_path, slug):
    """Load feature metadata from inventory and missing-features."""
    with open(inventory_path) as f:
        inventory = json.load(f)

    feat = inventory.get("features", {}).get(slug)
    if feat:
        return {
            "slug": slug,
            "feature_sha": feat["git"]["feature_sha"],
            "parent_sha": feat["git"]["parent_sha"],
            "commit_msg": feat["git"]["commit_msg"],
            "files_changed": feat["git"]["files_changed"],
            "test_files": feat["git"].get("test_files", []),
            "impl_files": feat["git"].get("impl_files", []),
            "tdd_tokens_best": feat["tokens"]["tdd_tokens_best"],
            "total_tokens": feat["tokens"]["total_tokens"],
        }

    if os.path.exists(missing_path):
        with open(missing_path) as f:
            missing = json.load(f)
        feat_data = missing.get("features", {}).get(slug)
        if feat_data:
            return {
                "slug": slug,
                "feature_sha": feat_data["feature_sha"],
                "parent_sha": feat_data["parent_sha"],
                "commit_msg": feat_data["commit_msg"],
                "files_changed": feat_data.get("files_changed", 0),
                "test_files": feat_data.get("test_files", []),
                "impl_files": feat_data.get("impl_files", []),
                "tdd_tokens_best": feat_data.get("tdd_tokens", 0),
                "total_tokens": feat_data.get("total_tokens", 0),
            }

    return None


def setup_checkout(jlsm_path, feature_sha, work_dir, slug):
    """Create an isolated clone at the feature commit.

    Uses git clone --shared for speed (shares objects with original repo),
    then checks out the feature commit.
    """
    checkout_path = os.path.join(work_dir, f"jlsm-atdd-{slug}")

    if os.path.exists(checkout_path):
        print(f"  Checkout already exists at {checkout_path}", file=sys.stderr)
        print(f"  Remove it first: rm -rf {checkout_path}", file=sys.stderr)
        return None

    os.makedirs(work_dir, exist_ok=True)

    # Clone with shared objects (fast, lightweight)
    result = subprocess.run(
        ["git", "clone", "--shared", "--no-checkout", jlsm_path, checkout_path],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"  Clone failed: {result.stderr}", file=sys.stderr)
        return None

    # Checkout the feature commit
    result = git_run(checkout_path, "checkout", feature_sha)
    if result.returncode != 0:
        print(f"  Checkout failed: {result.stderr}", file=sys.stderr)
        shutil.rmtree(checkout_path, ignore_errors=True)
        return None

    print(f"  Checkout created at {checkout_path}", file=sys.stderr)
    return checkout_path


def install_vallorcine(checkout_path, vallorcine_path):
    """Install vallorcine from the current branch into the checkout."""
    install_script = os.path.join(vallorcine_path, "install.sh")
    if not os.path.exists(install_script):
        print(f"  Error: install.sh not found at {install_script}", file=sys.stderr)
        return False

    result = subprocess.run(
        ["bash", install_script],
        capture_output=True, text=True,
        cwd=checkout_path,
    )
    if result.returncode != 0:
        print(f"  Install failed: {result.stderr}", file=sys.stderr)
        return False

    print(f"  Vallorcine installed into checkout", file=sys.stderr)
    return True


def compute_feature_scope(jlsm_path, parent_sha, feature_sha):
    """Compute the scope of files changed by the feature.

    Returns:
      - changed_files: list of all files changed
      - impl_dirs: unique directories containing implementation files
      - test_dirs: unique directories containing test files
      - scope_path: the narrowest common parent directory for impl files
    """
    result = git_run(jlsm_path, "diff", "--name-only", parent_sha, feature_sha)
    if result.returncode != 0:
        return None

    changed_files = [f for f in result.stdout.strip().split("\n") if f]

    impl_files = [f for f in changed_files if "src/main" in f]
    test_files = [f for f in changed_files if "src/test" in f or "Test" in f]

    # Find common parent directories
    impl_dirs = set()
    for f in impl_files:
        impl_dirs.add(os.path.dirname(f))

    test_dirs = set()
    for f in test_files:
        test_dirs.add(os.path.dirname(f))

    # Narrowest common parent for impl files
    if impl_dirs:
        scope_path = os.path.commonpath(list(impl_dirs))
    elif changed_files:
        scope_path = os.path.commonpath([os.path.dirname(f) for f in changed_files])
    else:
        scope_path = "."

    return {
        "changed_files": changed_files,
        "impl_files": impl_files,
        "test_files": test_files,
        "impl_dirs": sorted(impl_dirs),
        "test_dirs": sorted(test_dirs),
        "scope_path": scope_path,
    }


def write_scope_manifest(checkout_path, slug, metadata, scope):
    """Write a scope manifest that /atdd-audit reads to limit its analysis.

    Written to .feature/<slug>/atdd-scope.md so the aTDD skills can find it.
    """
    feature_dir = os.path.join(checkout_path, ".feature", slug)
    os.makedirs(feature_dir, exist_ok=True)

    manifest_path = os.path.join(feature_dir, "atdd-scope.md")
    lines = [
        f"# aTDD Audit Scope — {slug}\n",
        f"<!-- Generated by validation harness. -->\n",
        f"\n",
        f"## Scope rules\n",
        f"- **Read anything** — the Spec Analyst may read the full codebase to\n",
        f"  understand dependencies, call sites, and complex interactions\n",
        f"- **Target only these files** — the Breaker writes adversarial tests\n",
        f"  targeting only the implementation files listed below\n",
        f"- **Do not fix unrelated code** — the Implementer only modifies files\n",
        f"  within this scope when making adversarial tests pass\n",
        f"\n",
        f"## Feature\n",
        f"- Slug: {slug}\n",
        f"- Commit: {metadata['feature_sha']}\n",
        f"- Parent: {metadata['parent_sha']}\n",
        f"- Description: {metadata['commit_msg']}\n",
        f"\n",
        f"## Scope path\n",
        f"{scope['scope_path']}\n",
        f"\n",
        f"## Target implementation files (Breaker attacks these)\n",
    ]
    for f in scope["impl_files"]:
        lines.append(f"- {f}\n")

    lines.append(f"\n## Existing test files (Breaker reads for coverage context)\n")
    for f in scope["test_files"]:
        lines.append(f"- {f}\n")

    lines.append(f"\n## All changed files in feature commit\n")
    for f in scope["changed_files"]:
        lines.append(f"- {f}\n")

    with open(manifest_path, "w") as f:
        f.writelines(lines)

    return manifest_path


def write_brief_if_missing(checkout_path, slug, briefs_dir):
    """Copy the feature brief into .feature/<slug>/ if it exists in our research data."""
    feature_dir = os.path.join(checkout_path, ".feature", slug)
    os.makedirs(feature_dir, exist_ok=True)

    brief_dst = os.path.join(feature_dir, "brief.md")
    if os.path.exists(brief_dst):
        return  # Already there (from archive or prior install)

    brief_src = os.path.join(briefs_dir, f"{slug}-brief.md")
    if os.path.exists(brief_src):
        shutil.copy2(brief_src, brief_dst)

    # Also copy work plan
    wp_dst = os.path.join(feature_dir, "work-plan.md")
    if not os.path.exists(wp_dst):
        wp_src = os.path.join(
            os.path.dirname(briefs_dir), "work-plans", f"{slug}-work-plan.md"
        )
        if os.path.exists(wp_src):
            shutil.copy2(wp_src, wp_dst)


def main():
    parser = argparse.ArgumentParser(
        description="Set up and run aTDD validation against a single jlsm feature"
    )
    parser.add_argument("--jlsm-path", required=True,
                        help="Path to jlsm repository")
    parser.add_argument("--vallorcine-path", default=None,
                        help="Path to vallorcine repo (for install). Default: auto-detect")
    parser.add_argument("--feature", required=True,
                        help="Feature slug to validate")
    parser.add_argument("--max-rounds", type=int, default=3,
                        help="Max aTDD rounds (default: 3)")
    parser.add_argument("--inventory", default=None,
                        help="Path to feature-inventory.json")
    parser.add_argument("--results-dir", default="results",
                        help="Directory for output (default: results/)")
    parser.add_argument("--work-dir", default="/tmp/atdd-validation",
                        help="Directory for temporary checkouts (default: /tmp/atdd-validation)")
    parser.add_argument("--mode", choices=["audit", "greenfield"], required=True,
                        help="audit: checkout at feature_sha (post-TDD, find missed bugs). "
                             "greenfield: checkout at parent_sha + stubs (replace TDD entirely).")
    args = parser.parse_args()

    jlsm_path = os.path.abspath(os.path.expanduser(args.jlsm_path))
    slug = args.feature

    # Auto-detect vallorcine path (this script is in aTDD-research/harness/)
    vallorcine_path = args.vallorcine_path
    if not vallorcine_path:
        vallorcine_path = os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..")
        )
    vallorcine_path = os.path.abspath(vallorcine_path)

    # Find inventory
    inventory_path = args.inventory
    if not inventory_path:
        inventory_path = os.path.join(os.path.dirname(__file__), "..", "feature-inventory.json")
    inventory_path = os.path.abspath(inventory_path)
    missing_path = os.path.join(os.path.dirname(inventory_path), "missing-features.json")

    # Briefs directory
    briefs_dir = os.path.join(os.path.dirname(inventory_path), "briefs")

    # Load feature metadata
    metadata = collect_feature_metadata(inventory_path, missing_path, slug)
    if not metadata:
        print(f"Error: feature '{slug}' not found in inventory", file=sys.stderr)
        sys.exit(1)

    feature_sha = metadata["feature_sha"]
    parent_sha = metadata["parent_sha"]

    # Determine mode
    mode = args.mode
    checkout_sha = parent_sha if mode == "greenfield" else feature_sha
    dir_suffix = f"{slug}-{mode}"

    print(f"\n=== aTDD Validation Setup: {slug} ({mode}) ===", file=sys.stderr)
    print(f"  Mode: {mode}", file=sys.stderr)
    print(f"  Checkout at: {checkout_sha} ({'parent — no implementation' if mode == 'greenfield' else 'feature — post-TDD'})",
          file=sys.stderr)
    print(f"  Feature commit: {feature_sha} — {metadata['commit_msg'][:60]}", file=sys.stderr)
    print(f"  Parent commit:  {parent_sha}", file=sys.stderr)
    print(f"  Standard TDD tokens: {metadata['tdd_tokens_best']:,}", file=sys.stderr)
    print(f"  Files changed: {metadata['files_changed']}", file=sys.stderr)

    # Compute scope (always from parent→feature diff, regardless of mode)
    scope = compute_feature_scope(jlsm_path, parent_sha, feature_sha)
    if not scope:
        print(f"  Error: could not compute feature scope", file=sys.stderr)
        sys.exit(1)

    scope["mode"] = mode
    print(f"  Scope: {scope['scope_path']}", file=sys.stderr)
    print(f"    Impl files: {len(scope['impl_files'])}", file=sys.stderr)
    print(f"    Test files: {len(scope['test_files'])}", file=sys.stderr)

    # Create results directory (separate for greenfield vs audit)
    results_subdir = f"{slug}-greenfield" if mode == "greenfield" else slug
    results_dir = os.path.join(os.path.abspath(args.results_dir), results_subdir)
    os.makedirs(results_dir, exist_ok=True)

    # Save metadata and scope
    metadata["mode"] = mode
    metadata["checkout_sha"] = checkout_sha
    with open(os.path.join(results_dir, "feature-metadata.json"), "w") as f:
        json.dump(metadata, f, indent=2)
    with open(os.path.join(results_dir, "feature-scope.json"), "w") as f:
        json.dump(scope, f, indent=2)

    # Step 1: Create isolated checkout
    print(f"\n  Step 1: Creating checkout at {checkout_sha}...", file=sys.stderr)
    checkout_path = setup_checkout(jlsm_path, checkout_sha, args.work_dir, dir_suffix)

    # Step 1b: For greenfield, extract and apply planning-state overlay
    if mode == "greenfield" and checkout_path:
        print(f"  Step 1b: Extracting planning state from JSONL...", file=sys.stderr)
        harness_dir = os.path.dirname(__file__)
        overlay_dir = os.path.join(results_dir, "planning-overlay")

        # Find sessions for this feature from session-map
        session_map_path = os.path.join(os.path.dirname(inventory_path), "session-map.json")
        if os.path.exists(session_map_path):
            with open(session_map_path) as f:
                smap = json.load(f)
            feature_sessions = smap.get("features", {}).get(slug, {}).get("sessions", [])
        else:
            feature_sessions = []

        if feature_sessions:
            project_jsonl_dir = os.path.expanduser(
                "~/.claude/projects/-home-nnorthcutt-Code-github-nathannorthcutt-jlsm"
            )
            extract_cmd = [
                sys.executable,
                os.path.join(harness_dir, "extract-planning-state.py"),
                "--project-dir", project_jsonl_dir,
                "--sessions", *feature_sessions,
                "--feature", slug,
                "--output-dir", overlay_dir,
            ]
            result = subprocess.run(extract_cmd, capture_output=True, text=True)
            print(result.stderr, file=sys.stderr, end="")

            if os.path.exists(os.path.join(overlay_dir, "manifest.json")):
                apply_cmd = [
                    sys.executable,
                    os.path.join(harness_dir, "apply-overlay.py"),
                    "--checkout", checkout_path,
                    "--overlay", overlay_dir,
                ]
                result = subprocess.run(apply_cmd, capture_output=True, text=True)
                print(result.stderr, file=sys.stderr, end="")
            else:
                print(f"  Warning: no planning overlay produced", file=sys.stderr)
        else:
            print(f"  Warning: no sessions found for {slug} — stubs may be missing",
                  file=sys.stderr)
    if not checkout_path:
        sys.exit(1)

    # Step 2: Install vallorcine
    print(f"  Step 2: Installing vallorcine...", file=sys.stderr)
    if not install_vallorcine(checkout_path, vallorcine_path):
        print(f"  Continuing without vallorcine install — skills may not be available",
              file=sys.stderr)

    # Step 3: Write scope manifest and copy brief/work-plan
    print(f"  Step 3: Writing scope manifest...", file=sys.stderr)
    write_scope_manifest(checkout_path, slug, metadata, scope)
    write_brief_if_missing(checkout_path, slug, briefs_dir)

    # Step 4: Save pre-run state
    pre_state = {
        "label": "pre-atdd",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "checkout_path": checkout_path,
        "feature_sha": feature_sha,
        "source_checksums": file_checksums(checkout_path),
    }
    with open(os.path.join(results_dir, "pre-run-state.json"), "w") as f:
        json.dump(pre_state, f, indent=2)
    print(f"  Pre-run state saved ({len(pre_state['source_checksums'])} files)",
          file=sys.stderr)

    # Step 5: Output invocation instructions
    scope_path = scope["scope_path"]
    print(f"\n  ═══════════════════════════════════════════════", file=sys.stderr)
    print(f"  Ready to run aTDD ({mode}).", file=sys.stderr)
    print(f"", file=sys.stderr)
    print(f"  Checkout: {checkout_path}", file=sys.stderr)
    print(f"  Scope: {scope_path}", file=sys.stderr)
    print(f"  Brief: .feature/{slug}/brief.md", file=sys.stderr)
    print(f"  Work plan: .feature/{slug}/work-plan.md", file=sys.stderr)
    print(f"  Scope manifest: .feature/{slug}/atdd-scope.md", file=sys.stderr)
    print(f"", file=sys.stderr)
    print(f"  Run Claude Code:", file=sys.stderr)
    print(f"    cd {checkout_path}", file=sys.stderr)
    print(f"    claude", file=sys.stderr)
    print(f"", file=sys.stderr)
    print(f"  Then invoke:", file=sys.stderr)
    if mode == "audit":
        print(f"    /atdd-audit {slug}", file=sys.stderr)
    print(f"    /atdd-round {slug} --max-rounds {args.max_rounds}", file=sys.stderr)
    print(f"    /atdd-refactor {slug}", file=sys.stderr)
    print(f"", file=sys.stderr)
    print(f"  Mode '{mode}' is auto-detected by /atdd-round from the", file=sys.stderr)
    print(f"  codebase state — stubs only = greenfield, real impl = audit.", file=sys.stderr)
    print(f"", file=sys.stderr)
    print(f"  After completion, collect results:", file=sys.stderr)
    print(f"    python3 {os.path.join(os.path.dirname(__file__), 'collect-results.py')} \\",
          file=sys.stderr)
    print(f"      --jlsm-path {checkout_path} \\", file=sys.stderr)
    print(f"      --feature {slug} \\", file=sys.stderr)
    print(f"      --results-dir {os.path.abspath(args.results_dir)}", file=sys.stderr)
    print(f"", file=sys.stderr)
    print(f"  Clean up when done:", file=sys.stderr)
    print(f"    rm -rf {checkout_path}", file=sys.stderr)
    print(f"  ═══════════════════════════════════════════════", file=sys.stderr)


if __name__ == "__main__":
    main()
