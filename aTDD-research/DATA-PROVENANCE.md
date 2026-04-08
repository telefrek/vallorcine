# Data Provenance — aTDD Validation Research

This document records every manual intervention, override, or deviation from
automated data extraction. Reviewers should verify these decisions are justified
and do not bias the comparison.

---

## Automated extraction pipeline

All data was extracted from Claude Code JSONL session logs stored at
`~/.claude/projects/<project-hash>/`. The pipeline is:

1. **map-sessions.py** — scans all 130 JSONL sessions, maps to features by
   branch name and `/feature-*` slash command tags
2. **feature-aliases.json** — merges variant branch names to canonical slugs
3. **extract-tokens.py** — extracts per-stage token usage, TDD boundaries,
   git commit SHAs, file modifications
4. **extract-planning-state.py** — extracts Write/Edit operations from session
   JSONL to reconstruct end-of-planning state (stubs + work-plan)
5. **sanitize-sessions.py** — removes PII with SHA256 integrity verification

---

## Manual interventions

### 1. Feature alias mappings (feature-aliases.json)

**What:** Mapped variant branch names to canonical feature slugs.

| Variant | Canonical | Justification |
|---------|-----------|---------------|
| add-float16-support | float16-vector-support | Same feature, branch renamed mid-development |
| float16-support | float16-vector-support | Command arg variant of the same feature |
| update | (excluded) | docs/update branch, not a feature |
| init-repository-structure | (excluded) | Repository setup, not a feature |
| improve-code-quality | (excluded) | Code quality pass, not a feature |
| fix-vscode-jpms-integration | (excluded) | IDE fix, not a feature |
| improve-remote-wal-testing | (excluded) | Test improvement, not a feature |
| add-full-text-search | (excluded) | Feature not in archive (incomplete/abandoned) |
| add-sample-database-example | (excluded) | Example code, not a feature |

**Risk:** Incorrect aliasing would merge unrelated sessions' tokens. Verified
by checking that aliased sessions share the same feature slug in their
`/feature-*` commands.

### 2. Session-to-feature mapping overrides for planning state extraction

**What:** 4 features had their planning work (stubs) done in sessions not
automatically mapped to the feature by the session mapper. The planning
subagents were in sessions on the `main` branch or in mega-sessions that
contained multiple features.

| Feature | Mapped sessions | Added session | Justification |
|---------|----------------|---------------|---------------|
| in-process-database-engine | 6296fbfb | + bc9772c4 | Planning subagent "Write stubs and work plan" is in bc9772c4 (main branch, encryption mega-session). Verified: subagent wrote 13 jlsm-engine source files. |
| streaming-block-decompression | ea5188cc | + 43347015 | Planning subagent with source stubs is in 43347015 (verify-perf session). Verified: subagent wrote 9 source files for decompression. |
| vector-field-type | a56b57eb | (no override) | Stubs were inline edits to existing files in main session, not new files. Cannot extract separately — greenfield starts without stubs. |
| table-indices-and-queries | 655dabe1, 09f49eda | (no override) | No planning subagent found with source writes. Stubs unknown — greenfield starts without stubs. |

**Risk:** Adding sessions could include non-planning operations. Mitigated by
the `extract-planning-state.py` boundary detection (stops at first test file
write) and the subagent keyword filter (only processes subagents with "stub",
"work plan", "write plan", or "plan and" in their description).

### 3. Features excluded from scope

**What:** 3 features excluded from validation entirely.

| Feature | Reason |
|---------|--------|
| extract-core-encryption | Developed as subagent within encrypt-memory-data mega-session, interleaved with jlsm-specific perf-review commands. Clean state extraction impractical. |
| fix-encryption-performance | Same mega-session, depends on extract-core-encryption completing first. |
| ope-type-aware-bounds | Same mega-session, depends on fix-encryption-performance completing first. |

**Risk:** Excluding features could bias the dataset toward simpler features.
Mitigated: remaining 12 features span 3–47 files changed and 7M–118M tokens,
covering a wide complexity range. The excluded features are small (54K–324K
tokens) and would not significantly shift aggregate metrics.

### 4. Greenfield state incompleteness

**What:** 2 of 12 features have incomplete greenfield overlays (0 source stubs).

| Feature | Issue | Impact |
|---------|-------|--------|
| vector-field-type | Stubs were Edit ops to existing files (adding VectorType to FieldType.java, etc.), not new file writes. Overlay captures edits but they depend on exact file state. | Greenfield Implementer creates files from contracts instead of having pre-existing stubs. Adds work but doesn't invalidate comparison — both paths start from same contracts in work-plan.md. |
| table-indices-and-queries | No planning subagent found with source writes. Stubs were likely in unmapped main-branch sessions. | Same as above. |

**Risk:** Starting without stubs gives the greenfield Implementer more
latitude (and more work). This could make greenfield appear slower (more
tokens) than it would with stubs, but also gives the Implementer more freedom
to make different design choices — which could affect bug prevention rates
in either direction.

---

## Verification checklist for reviewers

1. **Token counts are not modified.** Sanitize-sessions.py preserves all
   `usage` fields. SHA256 checksums of original and sanitized files are in
   `sanitized/sanitization-manifest.json`. Compare `token_total_check` values.

2. **Git SHAs are verifiable.** All feature and parent SHAs in
   `feature-commits.json` can be verified against the jlsm repository at
   `github.com/nathannorthcutt/jlsm`.

3. **Planning overlays are deterministic.** Re-running `extract-planning-state.py`
   with the same sessions produces the same overlay. The extraction is
   purely mechanical — it replays Write/Edit operations from the JSONL.

4. **No cherry-picking of results.** All 12 in-scope features are included
   in the comparison, not a selected subset.
