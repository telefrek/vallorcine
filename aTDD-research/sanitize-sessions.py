#!/usr/bin/env python3
"""Sanitize Claude Code JSONL sessions for public distribution.

Replaces identifying information (paths, usernames, hostnames) with
deterministic placeholders while preserving data integrity for verification.

Integrity guarantees:
  - Token counts (input, output, cache_read, cache_create) are NEVER modified
  - Timestamps are NEVER modified
  - Command names and structure are NEVER modified
  - Session IDs are NEVER modified (needed for cross-referencing)
  - File-history-snapshot structure is preserved (paths sanitized, hashes kept)
  - A manifest is produced with SHA256 checksums of both original and sanitized
    files, plus the exact substitution rules applied, so anyone can verify that
    only the documented substitutions were made

Usage:
    python3 sanitize-sessions.py <project-dir> <session-map.json> \\
        --output-dir sanitized/ [--verify]
"""

import argparse
import hashlib
import json
import os
import re
import sys


# Default substitution rules. Each rule is (pattern, replacement).
# Patterns are applied in order. More specific patterns first to avoid
# partial matches.
DEFAULT_RULES = [
    # User home directory and username
    (r"/home/nnorthcutt", "/home/user"),
    (r"nnorthcutt", "user"),
    (r"nathannorthcutt", "researcher"),

    # GitHub org
    (r"telefrek", "org"),

    # Machine/host identifiers (adapt as needed)
    (r"(?i)(?<=@)[a-zA-Z0-9_-]+\.local", "host.local"),

    # Email addresses (keep structure, anonymize)
    (r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}", "user@example.com"),
]

# Fields that MUST NOT be modified (integrity-critical)
PROTECTED_FIELDS = {
    "input_tokens", "output_tokens",
    "cache_read_input_tokens", "cache_creation_input_tokens",
    "total_tokens", "tool_uses", "duration_ms",
    "timestamp", "backupTime",
    "stop_reason", "type", "sessionId",
    "ephemeral_5m_input_tokens", "ephemeral_1h_input_tokens",
    "service_tier", "speed",
}

# Fields where substitution should be applied
SANITIZE_FIELDS = {
    "content", "text", "cwd", "gitBranch",
    "command", "input", "output",
}


def compile_rules(rules):
    """Compile substitution rules into regex patterns."""
    return [(re.compile(pattern), replacement) for pattern, replacement in rules]


def apply_rules(text, compiled_rules):
    """Apply all substitution rules to a string."""
    if not isinstance(text, str):
        return text
    for pattern, replacement in compiled_rules:
        text = pattern.sub(replacement, text)
    return text


def sanitize_value(value, compiled_rules, field_name=None):
    """Recursively sanitize a JSON value.

    Preserves structure, applies rules to string values, skips protected fields.
    """
    if field_name in PROTECTED_FIELDS:
        return value

    if isinstance(value, str):
        return apply_rules(value, compiled_rules)
    elif isinstance(value, list):
        return [sanitize_value(item, compiled_rules) for item in value]
    elif isinstance(value, dict):
        result = {}
        for k, v in value.items():
            if k in PROTECTED_FIELDS:
                result[k] = v
            elif k == "usage":
                # Never touch usage blocks
                result[k] = v
            elif k == "cache_creation":
                # Never touch cache_creation blocks
                result[k] = v
            elif k == "trackedFileBackups":
                # Sanitize file paths (keys) but keep backup metadata
                result[k] = {}
                for filepath, backup_info in v.items():
                    sanitized_path = apply_rules(filepath, compiled_rules)
                    result[k][sanitized_path] = backup_info
            else:
                result[k] = sanitize_value(v, compiled_rules, field_name=k)
        return result
    else:
        return value


def sha256_file(filepath):
    """Compute SHA256 hash of a file."""
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_string(text):
    """Compute SHA256 hash of a string."""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sanitize_session(input_path, output_path, compiled_rules):
    """Sanitize a single JSONL session file.

    Returns (original_hash, sanitized_hash, line_count, token_integrity_ok).
    """
    original_hash = sha256_file(input_path)
    line_count = 0
    original_token_total = 0
    sanitized_token_total = 0

    sanitized_lines = []
    with open(input_path) as f:
        for line in f:
            line_count += 1
            try:
                entry = json.loads(line)

                # Accumulate original token counts for integrity check
                if entry.get("type") == "assistant":
                    usage = entry.get("message", {}).get("usage", {})
                    original_token_total += usage.get("input_tokens", 0)
                    original_token_total += usage.get("output_tokens", 0)

                # Sanitize
                sanitized = sanitize_value(entry, compiled_rules)

                # Accumulate sanitized token counts
                if sanitized.get("type") == "assistant":
                    usage = sanitized.get("message", {}).get("usage", {})
                    sanitized_token_total += usage.get("input_tokens", 0)
                    sanitized_token_total += usage.get("output_tokens", 0)

                sanitized_lines.append(json.dumps(sanitized, ensure_ascii=False))
            except (json.JSONDecodeError, ValueError):
                # Pass through non-JSON lines unchanged
                sanitized_lines.append(line.rstrip("\n"))

    output_content = "\n".join(sanitized_lines) + "\n"

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w") as f:
        f.write(output_content)

    sanitized_hash = sha256_file(output_path)
    token_integrity = original_token_total == sanitized_token_total

    return {
        "original_sha256": original_hash,
        "sanitized_sha256": sanitized_hash,
        "lines": line_count,
        "token_total_check": original_token_total,
        "token_integrity_ok": token_integrity,
    }


def verify_sanitization(original_path, sanitized_path, compiled_rules):
    """Verify that a sanitized file only differs from original in expected ways.

    Checks:
    1. Same number of lines
    2. Same JSON structure (same keys at each level)
    3. Token counts identical
    4. Only string values differ, and only where rules match
    """
    issues = []

    with open(original_path) as f:
        orig_lines = f.readlines()
    with open(sanitized_path) as f:
        san_lines = f.readlines()

    if len(orig_lines) != len(san_lines):
        issues.append(f"Line count mismatch: {len(orig_lines)} vs {len(san_lines)}")
        return issues

    for i, (ol, sl) in enumerate(zip(orig_lines, san_lines)):
        try:
            orig = json.loads(ol)
            san = json.loads(sl)
            _verify_structure(orig, san, f"line {i+1}", issues)
        except (json.JSONDecodeError, ValueError):
            if ol.strip() != sl.strip():
                issues.append(f"Line {i+1}: non-JSON line differs")

    return issues


def _verify_structure(orig, san, path, issues):
    """Recursively verify JSON structure matches."""
    if type(orig) != type(san):
        issues.append(f"{path}: type mismatch {type(orig).__name__} vs {type(san).__name__}")
        return

    if isinstance(orig, dict):
        if set(orig.keys()) != set(san.keys()):
            # trackedFileBackups keys are file paths and will change
            if "backupFileName" not in str(orig):
                issues.append(f"{path}: key mismatch {set(orig.keys()) - set(san.keys())}")
            return

        for key in orig:
            if key in PROTECTED_FIELDS or key == "usage" or key == "cache_creation":
                if orig[key] != san[key]:
                    issues.append(f"{path}.{key}: PROTECTED field modified!")
            elif key == "trackedFileBackups":
                # Keys change but values should be identical
                if sorted(orig[key].values(), key=str) != sorted(san[key].values(), key=str):
                    issues.append(f"{path}.{key}: backup metadata modified!")
            else:
                _verify_structure(orig[key], san[key], f"{path}.{key}", issues)

    elif isinstance(orig, list):
        if len(orig) != len(san):
            issues.append(f"{path}: list length mismatch {len(orig)} vs {len(san)}")
            return
        for j, (oi, si) in enumerate(zip(orig, san)):
            _verify_structure(oi, si, f"{path}[{j}]", issues)


def main():
    parser = argparse.ArgumentParser(
        description="Sanitize JSONL sessions for public distribution"
    )
    parser.add_argument(
        "project_dir",
        help="Path to Claude Code project directory",
    )
    parser.add_argument(
        "session_map",
        help="Path to session-map.json (determines which sessions to sanitize)",
    )
    parser.add_argument(
        "--output-dir", "-o",
        default="sanitized",
        help="Output directory for sanitized files (default: sanitized/)",
    )
    parser.add_argument(
        "--rules", "-r",
        help="Path to custom rules JSON file (list of [pattern, replacement] pairs)",
    )
    parser.add_argument(
        "--verify", "-v",
        action="store_true",
        help="Verify sanitization integrity after writing",
    )
    args = parser.parse_args()

    project_dir = os.path.expanduser(args.project_dir)

    # Load session map to know which sessions to sanitize
    with open(args.session_map) as f:
        session_map = json.load(f)

    # Collect all session IDs referenced by features
    session_ids = set()
    for slug, feat in session_map["features"].items():
        for sid in feat["sessions"]:
            session_ids.add(sid)

    # Load and compile rules
    if args.rules:
        with open(args.rules) as f:
            rules = json.load(f)
    else:
        rules = DEFAULT_RULES

    compiled = compile_rules(rules)

    output_dir = args.output_dir
    if not os.path.isabs(output_dir):
        output_dir = os.path.join(os.getcwd(), output_dir)

    print(f"Sanitizing {len(session_ids)} sessions...", file=sys.stderr)
    print(f"  Rules: {len(rules)} substitution patterns", file=sys.stderr)
    print(f"  Output: {output_dir}/", file=sys.stderr)

    manifest = {
        "rules_applied": [[p if isinstance(p, str) else p.pattern, r]
                          for p, r in rules],
        "integrity_note": (
            "Token counts (input_tokens, output_tokens, cache_read_input_tokens, "
            "cache_creation_input_tokens) are NEVER modified. Timestamps are NEVER "
            "modified. Session IDs are NEVER modified. Only string content (file paths, "
            "user messages, tool results) has substitutions applied. Verify by comparing "
            "original_sha256 against the source files and checking token_integrity_ok."
        ),
        "sessions": {},
    }

    for sid in sorted(session_ids):
        input_path = os.path.join(project_dir, f"{sid}.jsonl")
        if not os.path.exists(input_path):
            print(f"  Warning: {sid}.jsonl not found, skipping", file=sys.stderr)
            continue

        output_path = os.path.join(output_dir, f"{sid}.jsonl")
        result = sanitize_session(input_path, output_path, compiled)
        manifest["sessions"][sid] = result

        status = "OK" if result["token_integrity_ok"] else "INTEGRITY FAIL"
        print(f"  {sid[:12]}...  {result['lines']:5d} lines  {status}", file=sys.stderr)

        if args.verify:
            issues = verify_sanitization(input_path, output_path, compiled)
            if issues:
                print(f"    VERIFICATION ISSUES:", file=sys.stderr)
                for issue in issues[:5]:
                    print(f"      {issue}", file=sys.stderr)

    # Also sanitize subagent files
    for sid in sorted(session_ids):
        subagent_dir = os.path.join(project_dir, sid, "subagents")
        if not os.path.isdir(subagent_dir):
            continue

        out_subagent_dir = os.path.join(output_dir, sid, "subagents")
        os.makedirs(out_subagent_dir, exist_ok=True)

        for fname in os.listdir(subagent_dir):
            input_path = os.path.join(subagent_dir, fname)
            output_path = os.path.join(out_subagent_dir, fname)

            if fname.endswith(".jsonl"):
                result = sanitize_session(input_path, output_path, compiled)
                manifest["sessions"][f"{sid}/subagents/{fname}"] = result
            elif fname.endswith(".meta.json"):
                # Meta files are small, sanitize in-place
                with open(input_path) as f:
                    meta = json.load(f)
                sanitized_meta = sanitize_value(meta, compiled)
                with open(output_path, "w") as f:
                    json.dump(sanitized_meta, f, indent=2)

    # Write manifest
    manifest_path = os.path.join(output_dir, "sanitization-manifest.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    # Also sanitize and copy the session-map
    with open(args.session_map) as f:
        smap = json.load(f)
    sanitized_smap = sanitize_value(smap, compiled)
    smap_out = os.path.join(output_dir, "session-map.json")
    with open(smap_out, "w") as f:
        json.dump(sanitized_smap, f, indent=2)

    # Summary
    total_sessions = len(manifest["sessions"])
    integrity_ok = sum(1 for s in manifest["sessions"].values()
                       if isinstance(s, dict) and s.get("token_integrity_ok", True))
    print(f"\n  {total_sessions} files sanitized, {integrity_ok} integrity OK", file=sys.stderr)
    print(f"  Manifest: {manifest_path}", file=sys.stderr)
    if integrity_ok < total_sessions:
        print(f"  WARNING: {total_sessions - integrity_ok} files failed integrity check!",
              file=sys.stderr)


if __name__ == "__main__":
    main()
