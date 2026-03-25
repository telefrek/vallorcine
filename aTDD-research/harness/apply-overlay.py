#!/usr/bin/env python3
"""Apply a planning-state overlay to a git checkout.

Takes the overlay produced by extract-planning-state.py and applies it
to a checkout at parent_sha, producing the exact end-of-planning state.

Write operations create files directly.
Edit operations apply string replacements to existing files.

Usage:
    python3 apply-overlay.py --checkout /path/to/checkout \
                             --overlay planning-state/<slug>/
"""

import argparse
import json
import os
import sys


def apply_write(checkout_path, relpath, overlay_dir):
    """Apply a Write operation — copy file from overlay to checkout."""
    src = os.path.join(overlay_dir, "files", relpath)
    dst = os.path.join(checkout_path, relpath)

    os.makedirs(os.path.dirname(dst), exist_ok=True)

    with open(src) as f:
        content = f.read()
    with open(dst, "w") as f:
        f.write(content)

    return True


def apply_edit(checkout_path, edit_file, overlay_dir):
    """Apply an Edit operation — string replacement in an existing file."""
    edit_path = os.path.join(overlay_dir, edit_file)
    with open(edit_path) as f:
        edit = json.load(f)

    target_path = os.path.join(checkout_path, edit["path"])
    if not os.path.exists(target_path):
        print(f"  Warning: target file not found: {edit['path']}", file=sys.stderr)
        return False

    with open(target_path) as f:
        content = f.read()

    old = edit["old_string"]
    new = edit["new_string"]

    if old not in content:
        print(f"  Warning: old_string not found in {edit['path']}", file=sys.stderr)
        print(f"    Looking for: {old[:80]}...", file=sys.stderr)
        return False

    if edit.get("replace_all", False):
        content = content.replace(old, new)
    else:
        content = content.replace(old, new, 1)

    with open(target_path, "w") as f:
        f.write(content)

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Apply planning-state overlay to a git checkout"
    )
    parser.add_argument("--checkout", required=True,
                        help="Path to the git checkout (at parent_sha)")
    parser.add_argument("--overlay", required=True,
                        help="Path to the overlay directory from extract-planning-state.py")
    args = parser.parse_args()

    checkout_path = os.path.abspath(args.checkout)
    overlay_dir = os.path.abspath(args.overlay)

    manifest_path = os.path.join(overlay_dir, "manifest.json")
    if not os.path.exists(manifest_path):
        print(f"Error: manifest.json not found in {overlay_dir}", file=sys.stderr)
        sys.exit(1)

    with open(manifest_path) as f:
        manifest = json.load(f)

    ops = manifest["operations"]

    # Sort operations: Writes before Edits per file, then by line number.
    # This ensures a file is created before it's edited, and sequential
    # edits apply in the correct order.
    def op_sort_key(op):
        path = op.get("path", "")
        is_write = 0 if op["op"] == "write" else 1
        line = op.get("line", 0)
        return (path, is_write, line)

    ops = sorted(ops, key=op_sort_key)

    # Cosmetic files: .feature/ status, .decisions/ indexes, .kb/ indexes.
    # Sequential edit failures on these are expected and harmless — the aTDD
    # run only needs source stubs, brief.md, and work-plan.md to be correct.
    cosmetic_prefixes = (".feature/", ".decisions/", ".kb/", ".claude/")

    print(f"Applying {len(ops)} operations to {checkout_path}...", file=sys.stderr)

    success = 0
    failed = 0
    silent_failures = 0

    for op in ops:
        is_cosmetic = any(op.get("path", "").startswith(p) for p in cosmetic_prefixes)

        if op["op"] == "write":
            if apply_write(checkout_path, op["path"], overlay_dir):
                print(f"  WRITE  {op['path']}", file=sys.stderr)
                success += 1
            else:
                if is_cosmetic:
                    silent_failures += 1
                else:
                    print(f"  FAIL   {op['path']}", file=sys.stderr)
                    failed += 1

        elif op["op"] == "edit":
            if apply_edit(checkout_path, op["edit_file"], overlay_dir):
                print(f"  EDIT   {op['path']}", file=sys.stderr)
                success += 1
            else:
                if is_cosmetic:
                    silent_failures += 1
                else:
                    print(f"  FAIL   {op['path']}", file=sys.stderr)
                    failed += 1

    print(f"\n  Applied: {success}  Failed: {failed}", file=sys.stderr)
    if silent_failures > 0:
        print(f"  Skipped: {silent_failures} cosmetic edits (.feature/, .decisions/, etc.)",
              file=sys.stderr)
    if failed > 0:
        print(f"  WARNING: {failed} source file operations failed — state may be incomplete",
              file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
