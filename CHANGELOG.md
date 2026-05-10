# Changelog

All notable changes to vallorcine are documented here.
Format: `## [version] — YYYY-MM-DD` with sections Added / Changed / Fixed / Removed.

---
## [0.17.2] — 2026-05-09

### Added

- **`scripts/check-kb-ref.sh`** — PostToolUse hook on Write/Edit/MultiEdit
  that links source code back to the KB. Source files now SHOULD declare
  which KB articles informed them via a `// KB: <path>` (or `# KB:`,
  `<!-- KB: -->`) comment. The hook:
  - Auto-disables when `.kb/` has no entries beyond `_refs/` — projects
    that don't use vallorcine for code-relevant research are not nagged.
  - Validates that each cited path exists; flags rotted citations
    (entry was renamed, deleted, never existed).
  - Validates that the cited entry's `applies_to:` includes the file
    path; flags applies_to-mismatch (likely a copy-paste citation).
  - When no citation is present and at least one KB entry's `applies_to`
    covers the file path, lists those entries as suggestions. When no
    entry matches, stays silent — no nagging projects whose KB hasn't
    grown into a given area yet.
  - Recognises three comment forms: `// KB:` (Java/JS/TS/Go/Rust/C/C++),
    `# KB:` (Python/Bash/Ruby), `<!-- KB: -->` (HTML/XML/Markdown).
    Multiple citations may be comma-separated on one line.
  - Always exits 0 — the hook is advisory and never blocks the tool use.

  Inspired by faas-rippling's check-kb-ref.sh; vallorcine's version
  adds path validation, applies_to cross-checking, citation suggestions,
  multi-citation parsing, the three comment syntaxes, and the
  auto-disable so the kit-default is safe for every project.

- **`/curate` Analysis 26 — KB citation drift in source.** Closes the
  loop with the hook: scans source files that changed in the scan
  window for `KB:` citations and flags drift the hook missed (kit
  installed mid-stream, citation predates an entry rename). Two reason
  codes: `missing-entry` and `applies_to-mismatch`. Empty `applies_to`
  (general research) is exempt.

- **`/curate` SKILL.md routing for citation drift.** Section 2s
  documents how to read the finding. Step-4 routing offers four
  actions: update the citation (when wrong), extend the entry's
  `applies_to:` (when correct but the entry's stated scope is too
  narrow), dismiss as intentional, skip. Review-log key
  `kb-citation:<source>:<entry>` for deferred items.

### Changed

- **`rules/kb-protocol.md`** — documents the citation convention,
  comment syntaxes, hook behaviour, and the `/curate` Analysis 26
  backstop. Single canonical reference for contributors who hit a
  hook warning and want to understand the rule.

- **Install plumbing** — MANIFEST entry, `install.sh` (script copy +
  chmod + permission allowlist + PostToolUse hook in both seed JSON
  and jq-merge path so existing installs pick up the hook on next
  upgrade).

- **DESIGN.md script manifest** — listed `check-kb-ref.sh`; bumped
  curate-scan.sh's "25 analyses" count to 26.

### Tests

- `scenario-check-kb-ref.sh` — 18/18 covering all 12 enhancement paths
  (auto-disable, internals skipped, suggestions, citation validation,
  applies_to mismatch, multi-citation, three comment syntaxes,
  advisory-exit-0, empty-applies_to exemption).
- `scenario-curate-kb-citation-drift.sh` — 11/11 with section-scoped
  assertions so other analyses' file lists don't cause false positives.
- `tests/test-install.sh` — still 72/72.

---
## [0.17.1] — 2026-05-09

### Fixed

- **Sub-agent dispatch failures no longer silently corrupt the orchestrator's
  task list.** Two failure modes left a `/work-start` coordinator with a
  task entry stuck at `in_progress` and no signal of actual sub-agent
  state:
  1. Agent tool returned `[Tool result missing due to internal error]` —
     payload lost, sub-agent may have run / partially run / never started.
  2. Agent tool returned `The user doesn't want to proceed with this tool
     use. The tool use was rejected.` (e.g. ESC during dispatch) —
     sub-agent never started.

  Both required manual filesystem inspection (does `.feature/` exist, did
  `work-claim.sh` flip the WD to `IMPLEMENTING`, is there a branch with
  commits) to recover. This release adds a per-dispatch JSON marker that
  makes recovery automatic.

### Added

- **`scripts/work-dispatch.sh`** — writes a small JSON marker per dispatch
  at `.work/<group>/_dispatch-<wd-id>.json` (gitignored). Subcommands:
  - `begin <group> <wd-id>` — coordinator runs this BEFORE the Agent call;
    marker has `ack: false`.
  - `ack <group> <wd-id> <result-line>` — coordinator runs this when the
    Agent returned a clean parseable line; marker flips to `ack: true`.
  - `fail <group> <wd-id> <reason>` — coordinator runs this for the three
    failure modes: `payload-lost`, `user-stopped`, `parse-failed`.
  - `status <group> <wd-id>` — print marker JSON; exit 1 when absent.
  - `stuck <group>` — list unacknowledged markers, one per line.
  - `clear <group> <wd-id>` — delete marker after recovery (idempotent).

  Atomic writes via `.tmp.$$` + rename. JSON-escapes control bytes in
  result lines (mirrors `work-resolve.sh`'s `json_escape`) so a stray
  byte in a sub-agent's final line cannot produce invalid JSON downstream.

### Changed

- **`/work-start` sequential `all` mode** — Step 3d inserts
  `work-dispatch.sh begin` before the Agent call. Step 3f classifies the
  return into four shapes (clean / payload-lost / user-stopped /
  parse-failed) and routes to the right marker action plus an
  `AskUserQuestion` (Pause for `/work-resume` recovery / Continue with
  next WD / Stop). The coordinator MUST NOT silently advance the
  TaskTool entry to `completed` when the result is lost — the marker is
  the durable record.

- **`/work-start --parallel` mode** — Step 5 runs `begin` in a
  sequential loop before the multi-Agent dispatch. Step 6 classifies
  each return identically; dispatch failures are aggregated separately
  in the parallel-run summary so the user sees them.

- **`/work-resume`** — gains rule 0 in Step 5 routing: any
  unacknowledged dispatch marker pre-empts every other rule. For each
  stuck marker, gathers filesystem evidence (WD status from manifest,
  `.feature/` directory presence, cycle-log entries) and recommends the
  right recovery path:
  - `user-stopped` + WD still SPECIFIED + no `.feature/` → re-dispatch
    via `/work-start "<group>" <wd-id>`.
  - any reason + WD `IMPLEMENTING` + `.feature/` present → suggest
    `/feature-resume "<group>--<wd-slug>"` to inspect actual state.
  - other shapes → surface evidence, let the user decide.

  Reminds the user to clear the marker after recovery.

- **Install plumbing** — MANIFEST entry, `install.sh` (script copy +
  chmod + permission allowlist), and gitignore for
  `.work/*/_dispatch-*.json` (both new-install and upgrade paths).
  Test coverage extended: `tests/test-install.sh` goes 70 → 72 with
  two new gitignore assertions.

- **DESIGN.md script manifest** — listed `work-dispatch.sh` and
  bumped curate-scan.sh's "22 analyses" count to 25 (the three KB
  structural-drift analyses added in v0.17.0 weren't reflected in the
  prior release's docs sweep).

---
## [0.17.0] — 2026-05-09

### Added

- **Canonical KB frontmatter schema (`kb/_refs/frontmatter.md`).** Single
  authoritative reference for all entry types (`research`,
  `adversarial-finding`, `feature-footprint`, `detail-companion`,
  `reference-fragment`). Defines required core fields (title, type,
  applies_to, last_researched, research_status), optional fields with clear
  semantics, tag vocabulary (lowercase kebab-case, fixed domain/concern/
  discovery/construct sets), source format (no bare URLs — `accessed:`
  required), confidence discipline (earned not asserted: `high` requires
  ≥2 corroborating sources or ≥2 audit findings). Migration rules cover
  legacy entries (path-canonical for topic/category, `archived` ↔ `deprecated`,
  type inference from section headings). Both `/research` and `/curate`
  now treat this file as the source of truth.

- **Detail-companion convention (`kb/_refs/detail-companion.md`).**
  Formalises the `<subject>-detail.md` split for entries that exceed ~200
  lines: when to split, naming, placement, **frontmatter requirements
  (now mandatory on companion files** — was silently optional, breaking
  tag-overlap cross-reference repair), what content belongs in the
  companion vs the parent, and the rules `/curate` enforces (parent
  ↔ companion bidirectional link, companion not listed as standalone
  subject in indexes, etc.).

- **Three `/curate` analyses for KB structural drift.**
  - **Cross-folder filename collisions** — flags any KB filename living
    at 2+ paths under different folders. Catches the
    `partial-init-no-rollback` / `mutation-outside-rollback-scope` class
    of collision before grep silently fragments search and pattern-
    recurrence evidence under separate filenames.
  - **Schema drift** — parses every KB entry's frontmatter and validates
    against the canonical schema. 12 distinct issue codes:
    `missing-frontmatter`, `missing-title`, `missing-last-researched`,
    `bad-last-researched`, `missing-research-status`, `bad-research-status`,
    `legacy-research-status` (archived → deprecated rename),
    `missing-domain`/`severity` (adversarial-finding required fields),
    `missing-domains`/`constructs` (feature-footprint required fields),
    `missing-companion-to`, `missing-type`, `bad-type`,
    `confidence-overclaim` (counted from the entry's own evidence, not
    author assertion), `topic-mismatch`/`category-mismatch`. One row per
    distinct issue per entry so the user can address each independently.
  - **Type ↔ location mismatch** — flags `type: adversarial-finding`
    outside `patterns/<concern>/` and `type: feature-footprint` outside
    `architecture/feature-footprints/`. These are entries the test-writer's
    lens-based loaders never see.

- **`/curate` SKILL.md routing for KB drift findings.** Section 2r
  documents how to read all three findings; three Step-4 routing blocks
  add AskUserQuestion options (rename / merge / dismiss for collisions;
  apply patches / walk-one-at-a-time / dismiss for schema drift;
  relocate / re-classify-type / dismiss for location mismatches). All
  resolutions stage with `git add` and let the user commit — drift
  remediation stays reviewer-gated. Review-log keys
  (`kb-collision:<basename>`, `kb-schema:<path>:<issue-code>`,
  `kb-location:<path>`) so deferred items resurface deterministically.

- **Regression test (`tests/scenario-curate-kb-schema-drift.sh`).**
  Synthetic fixture with a known mix of clean and drifted KB entries
  asserts: collision detection finds the cross-folder pair, all 12
  schema-drift codes fire on the right entries, clean entries do NOT
  appear in any KB-quality finding, `_refs/` files excluded from
  KB-quality analyses (may still appear in general git-history analyses
  like Churn Hotspots), type/location detection works for both
  adversarial-findings and feature-footprints. 21/21 assertions pass.

### Changed

- **`/research` is type-aware.** Step 3 placement determination now infers
  `type: research | adversarial-finding | feature-footprint` from the
  context hint (`feature-retro footprint for ...` ⇒ `feature-footprint`,
  `audit adversarial pattern from ...` / `Suggested: patterns/<concern>` ⇒
  `adversarial-finding`, otherwise `research`) and surfaces the inferred
  type in the facet plan so the user can correct before any file is
  written. Step 6 selects the appropriate template — inline research
  template for research, the `_refs/` templates for findings and
  footprints. Clean separation that was previously absent (one template
  applied to all writes was the root cause of the schema drift this
  release addresses).

- **`/research` cross-folder filename collision check.** Before opening
  the writer, `/research` runs `find .kb -name "<filename>.md"` and
  refuses to write if the name already exists under a different folder.
  Disambiguation prompt offers a more specific name; intentional collisions
  require explicit user confirmation.

- **`/research` frontmatter validation against the canonical schema.**
  After drafting, `/research` validates: required core fields present,
  type recognised, type-specific required fields present,
  `last_researched` ISO-quoted, `research_status` is one of four valid
  values, tags are kebab-case, sources have url+title+accessed (no bare
  URLs), confidence defaults to `medium` and never to `high` without ≥2
  corroborating sources, path ↔ frontmatter `topic`/`category`
  consistency.

- **Audit feedback hint repointed at `patterns/<concern>`.** The
  feedback-loop dispatch hint changed from
  `Suggested: <topic>/adversarial-findings` (which never existed as a
  folder convention) to `Suggested: patterns/<concern>` (the lens, not
  the discovery domain). Findings discovered while researching SQL
  parsing now land at `patterns/validation/<finding>.md` where the
  test-writer's lens-based loaders will find them.

- **Realigned `_refs/adversarial-finding-template.md` and
  `_refs/feature-footprint-template.md`** as schema instances, not
  overlapping schemas. Both now reference the canonical
  `frontmatter.md` and document the type-specific guidance unique to
  each (e.g. `tags` should always include `adversarial-finding` for
  findings; footprints use `domains:` plural and `research_status:
  stable` because they're historical records).

- **`kb/CLAUDE.md` root template includes decision rules.** "Where does X
  go?" section explains the domain-topic vs `patterns/` boundary;
  filename uniqueness rule documented (must be unique across the entire
  `.kb/` tree, not just within category).

- **install.sh + tests/test-install.sh ship and verify the new `_refs/`
  files.** Existing installs receive the new files on next
  `/upgrade-vallorcine` (upgrade.sh's existing glob over
  `kb/_refs/*.md` picks them up automatically). Test coverage extended
  to verify all six `_refs/` files install (was checking only two).

---
## [0.16.8] — 2026-05-09

### Added

- **`/work-resume` skill** — work-layer counterpart to `/feature-resume`.
  Cheap entry point after `/clear`, a crash, or a context switch. With
  no arg or `--list`, shows every active work group on one line each.
  With a group slug, shows a compact summary (active WDs, next-up
  candidates) and routes to the next command — `/work-plan`,
  `/work-start`, `/feature-resume`, or an unblock action — without
  re-running the full readiness resolver every time. Reads the new
  `_readiness.json` cache for this; falls back to running the resolver
  if the cache is missing or stale.

- **Cached readiness JSON (`.work/<group>/_readiness.json`)** —
  `work-resolve.sh` now writes a structured JSON file alongside its
  markdown report. Schema: `{ schema_version, generated_at, group,
  summary, external_blocker, wds[] }` where each `wds[]` entry has
  `id, title, status, deps_count, blockers, unblocks`. Atomic write via
  `.tmp.$$` + rename. Lets `/work-resume` (and future parallel
  coordination) read structured state without parsing the markdown
  table. Per-machine cache; gitignored.

- **`/work-decompose` Phase A→B checkpoint
  (`.work/<group>/_decompose-progress.md`)** — Phase A now persists its
  seam analysis to a checkpoint file before showing it to the user.
  Phase B updates the checkpoint as each coordination surface settles.
  An interrupted `/work-decompose` can be resumed at the next
  invocation (the skill detects the checkpoint and offers to resume
  from where Phase B left off, or discard and restart). Cleared on
  successful manifest update. Per-machine; gitignored.

### Changed

- **Refresh readiness cache after WD status mutations.** `/work-plan`,
  `/work-start`, `/work-decompose`, and `/feature-complete` now call
  `work-resolve.sh` after they `sed`-flip a WD's status (DRAFT →
  SPECIFYING → SPECIFIED → IMPLEMENTING → COMPLETE). Without this,
  parallel sessions and `/work-resume` calls in the same group would
  see stale `_readiness.json` until the next `/work-status` invocation.
  The refresh is a fast no-op when state is already current.

- **work-resolve.sh hardened for parallel sessions and partial failures.**
  - `flock`-based serialization on `.work/<group>/.work-resolve.lock`
    (when `flock` is available — gracefully no-op on platforms without
    util-linux). The lock now wraps the **compute phase as well as the
    writes**; locking only the writes left a snapshot race where two
    parallel runs read state at different times and the second writer
    could overwrite with stale content while still bumping mtime,
    invisibly defeating the freshness check.
  - EXIT trap cleans up `_readiness.json.tmp.<PID>` if printf aborts
    mid-write (`set -e` + a parameter-expansion error would otherwise
    leak `.tmp` files into `.work/<group>/`).
  - `json_escape` strips ASCII control chars (0x00–0x08, 0x0B–0x0C,
    0x0E–0x1F) before escape transforms, so a stray control byte in a
    WD title can never produce invalid JSON downstream.

- **`/work-resume` more robust on edge cases.**
  - Detects orphan decompose checkpoints. Detection rule uses **"any WD
    past DRAFT"** (a strong signal — Phase C must have run for any WD
    to exist past DRAFT) rather than count-matching against the
    checkpoint's "Tentative WDs" list (fragile under manual edits).
    Stale-by-age (>7 days) is independently flagged.
  - The orphan-detection bash uses `find -exec` rather than
    `find ... | xargs grep` because `xargs` without `-r` hangs on
    macOS when its input is empty.
  - On `--list`, surfaces a one-line "(refreshed N stale cache(s))"
    diagnostic when it had to run the resolver — the "cheap list"
    claim is now honest about its actual cost.
  - On JSON parse failure after a fresh resolver run, surfaces an
    explicit error and stops rather than silently falling back to
    parsing the markdown report.

- **`/work-decompose` Phase A→B resume confirms with the user.** When
  resuming from `_decompose-progress.md`, the skill now displays the
  parsed Phase A state (tentative WDs, settled/unsettled coordination
  surfaces) and asks the user to confirm before continuing. LLM
  markdown parsing is fragile; this verification catches misparsed
  state before it produces redundant subagent dispatches.

- **`/work-decompose` pre-flight runs the same orphan check as
  `/work-resume`.** When a checkpoint exists AND any WD has progressed
  past DRAFT (or the checkpoint is >7 days old), the skill marks the
  checkpoint as a probable orphan and recommends "Discard" instead of
  blindly offering "Resume" as the recommended option. After resume,
  Phase B explicitly skips already-settled surfaces rather than relying
  on the LLM to track which were done — fixes a duplicate-dispatch bug
  that would re-author already-settled ADRs and specs.

- **`/work-plan <group> all` and `/work-start <group> all`** —
  sequential coordinator modes that automate the
  `/clear` + `/work-resume` + per-WD-skill rhythm. Each iterates over
  eligible WDs (READY for `/work-plan`, SPECIFIED for `/work-start`),
  dispatching ONE sub-agent per WD that **recursively invokes the
  single-WD skill** (e.g., the sub-agent runs `/work-plan <group>
  WD-01`). The coordinator carries only dispatch state and one-line
  summaries; each sub-agent's heavy work lives in its own context
  window and is gone when it returns.

  Why recursive dispatch (instead of inlining the pipeline in the
  coordinator's sub-agent prompt): keeps state-transition logic
  (`work-claim.sh`, status.md initialization, manifest sync) in the
  authoritative single-WD flow rather than duplicating it in the
  coordinator's prompt template — where it would silently drift when
  the single-WD flow changes.

  **Re-enumerates between iterations.** A WD that was BLOCKED at
  iteration N may become READY/SPECIFIED at iteration N+1 because the
  previous WD's completion satisfied a dep. The coordinator re-runs
  the resolver and re-reads `_readiness.json` at the top of every
  loop, so the run picks up newly-eligible WDs that weren't in the
  initial plan.

  **Claim conflicts are non-fatal.** When another terminal advances a
  WD between the coordinator's enumeration and the sub-agent's
  dispatch, `work-claim.sh` exits 1, the sub-agent returns
  `SKIPPED — claim conflict`, and the coordinator continues to the
  next eligible WD. No corruption, no stuck loop.

  Differences from `/work-start --parallel`:
  - `all` is **sequential** (1 sub-agent at a time, no resource
    contention, smaller peak token usage at any moment)
  - `--parallel` is **concurrent** (N sub-agents at once, possible
    contention on shared writes, faster wall clock)
  - Quality at arbitration is **identical** — both modes delegate to
    the same single-WD flow which uses the same `automation_mode`
    and `execution_strategy` settings.

  `/work-plan all` specifically: `/spec-author` Pass 2 arbitration
  prompts surface to the user as designed. The coordinator pauses
  while the user answers each finding, then continues. This is "fully
  automated coordinator + manual arbitration" — preserves spec
  quality at design decisions while removing the per-WD `/clear`
  ritual.

- **`scripts/work-claim.sh`** — atomic compare-and-swap for WD status
  transitions. Reads the WD's current status under flock, asserts it
  matches the expected value, then `sed`-flips to the new status. Two
  parallel sessions racing the same DRAFT → SPECIFYING transition
  cannot both succeed — the second one gets exit code 1 and a
  CONFLICT message directing the user to `/work-resume` for the latest
  state. Without this, two terminals running `/work-plan WD-01`
  simultaneously could both see DRAFT (resolver snapshot is stale by
  the time Step 4c runs), both flip to SPECIFYING, and both proceed to
  author specs — racing on writes to the same files. `/work-plan` and
  `/work-start` now use `work-claim.sh` for every status transition.
  Shares the `.work-resolve.lock` file so claim and resolve serialize
  against each other.

### Why these changes

Token analysis of recent multi-WD jlsm planning sessions showed
~300–500K cache re-seed per skill switch in the planning chain, hitting
the practical 500K input-token wall after 1–2 invocations. Three small
additions enable a "clear-and-resume" rhythm: run a planning skill,
`/clear`, then `/work-resume` to pick the next WD with no inherited
reasoning history. The same primitives let multiple parallel sessions
coordinate via the WD frontmatter source of truth and the per-machine
readiness cache.

- **`scripts/work-index.sh`** — authoritative writer for the
  `.work/CLAUDE.md` Active Work Groups table. Subcommands `add`,
  `update`, `update-all`, `remove` recompute `WDs / Ready / Complete`
  counts from each group's WD frontmatter and bump Last Updated.
  Replaces hand-edits in `/work`, `/work-decompose`, `/feature-complete`,
  and `/decisions`. Idempotent on add; preserves Path and Goal across
  update; sanitizes pipes in goal text so the table cannot be split.

### Added

- **Spec-coverage gate now scopes to primary specs by default**.
  `/spec-resolve` builds a bundle that mixes direct-match specs (the
  feature targeted) with transitively-pulled context specs (parent
  chain, `requires:`, sibling expansion). Previously the
  `spec-coverage` gate fired on every requirement across every spec,
  forcing waiver-spam on context specs the WD has no obligation to
  annotate (e.g. jlsm#74 had to override the gate over 136 trailing
  context-spec R-clauses). Three coordinated changes:
  - `spec-resolve.sh` emits new `Primary specs:` and `Context specs:`
    preamble lines listing direct-match vs transitive IDs (data was
    already tracked internally; just surfaced now).
  - `spec-coverage.sh init` reads the preamble and tags non-primary
    rows with `context` in the Notes column. Re-init preserves prior
    waivers; legacy bundles without the preamble treat every spec as
    primary (full backwards compatibility).
  - `spec-coverage.sh gate` skips `context`-tagged rows by default.
    New `--include-context` flag flips to strict whole-bundle mode
    for audits. Failure message hints at the flag.
  - `report` subcommand breaks down primary vs context in the count
    line when context rows exist.

### Fixed

- **`spec-coverage.sh init` now parses title-bearing bundle section
  headers**. The init parser used a fully-anchored regex `^# <id>$`,
  but `spec-resolve.sh` writes each spec section through
  `machine_section` verbatim and spec files use a title-bearing top
  header `# <id> — <title>`. The anchored regex never matched, init
  fell through to the "no specs in bundle" branch, and silently
  emitted a vacuous-coverage file. Tables were only ever populated
  when `/spec-coverage update` later re-derived rows from spec-trace
  output (different code path). Two-line awk fix loosens the regex
  to allow an optional space-and-title suffix and truncates the ID
  extraction at the first whitespace. Backwards-compatible with the
  legacy bare-ID bundle form.

- **`/feature-resume` reconciles Spec Authoring substage against
  manifest**. `.feature/<slug>/` is gitignored, so `status.md`
  is a local cache that drifts when a sibling WD's session authors
  specs in a different PR. New
  `scripts/feature-state-reconcile.sh <slug>` reads the WD's
  `produces:` list, looks up each produced spec's state in
  `.spec/registry/manifest.json`, and if every produced spec is
  APPROVED, flips the Stage Completion `Spec Authoring` row to
  `complete`. `/feature-resume` Step 1 calls it before reading
  status.md so the displayed state reflects durable truth.
  Idempotent; slash- and dot-form paths both resolve.

- **`/feature-complete` no longer leaves uncommitted changes**. The
  skill's Step 2b previously asked Claude to hand-edit the Active
  Work Groups row to "increment the Complete count" — and falsely
  claimed `work-resolve.sh` auto-synced the table (it never did).
  Two changes:
  1. Step 2b now invokes `work-index.sh update <group-slug>` instead
     of hand-editing. Same change applied to `/work` Step 4c (group
     creation), `/work-decompose` Step 6 (post-decomposition refresh),
     and `/decisions` Step 9d (group creation from roadmap).
  2. `work-finalize.sh` (called at `/feature-refactor` Step 6b, before
     `/feature-pr`) now invokes `work-index.sh update` inline so the
     Active Work Groups row bumps in the same commit that flips the WD
     status. The index update lands inside the feature PR; post-merge
     `/feature-complete` has nothing tracked left to write.
  3. `work-index.sh update` is now a true no-op when counts are
     unchanged (preserves Last Updated, writes zero bytes), so the
     defensive `/feature-complete` resync produces no diff in the
     normal pipeline.

---


## [0.16.7] — 2026-05-06

### Added

- **`/spec-backfill <spec-id>` and `/spec-backfill --all`** — new skill
  that walks every requirement of an APPROVED spec lacking `@spec`
  annotations in code, presents likely enforcement sites ranked by
  subject-token overlap, and applies user-chosen annotations. The
  backfill complement to v0.16.5 forward-enforcement, closing the gap
  for mature corpora authored before annotation enforcement existed.
  `--all` corpus mode iterates every APPROVED spec in the manifest;
  progress persists in `.spec/backfill-log.md` so users can break out
  and resume.
- **`spec-trace.sh --uncovered <spec-id>`** — emits a parseable list
  of R-ids defined in the spec but absent from any `@spec` annotation
  in code. One R-id per line on stdout (e.g.
  `auth.token-validation.R3`); summary on stderr. Used by
  `/spec-backfill` and `/curate` annotation-drift analysis as the
  discovery primitive.
- **`scripts/spec-backfill-candidates.sh`** — given a (spec-id, R-id),
  reads the requirement text and ranks code locations by subject-token
  overlap (case-insensitive substring with simple plural→singular
  normalization). The candidate-finder primitive backing
  `/spec-backfill` Phase 2.
- **`scripts/spec-backfill-log.sh`** — append-only `.spec/backfill-log.md`
  tracking per-(spec, R-id) backfill outcomes (annotated / skipped /
  waived). Provides `init`, `append`, `has-decision`, `list-decisions`,
  and `report` subcommands. Later rows for the same key supersede
  earlier ones; `skipped` is intentionally non-terminal so skipped
  R-ids resurface on rerun.
- **`/curate` annotation-drift subsection** — new "Annotation drift —
  APPROVED specs below 50% coverage" subsection under "Spec Annotation
  Coverage Gaps". Routes resolution to `/spec-backfill <spec-id>`,
  with a `/spec-backfill --all` suggestion when 4+ specs have drifted.
  Surfaces partially-annotated specs at regular curation cadence so
  drift never re-accumulates.

### Fixed

- **`work-resolve.sh` strict state-equality on wd deps**. A
  `required_state: SPECIFIED` dep was reported BLOCKED when the
  predecessor had advanced to COMPLETE, even though COMPLETE is past
  SPECIFIED on the WD lifecycle. Surfaced from jlsm: `/work-plan` on a
  group with COMPLETE/SPECIFIED predecessors flagged dependents as
  blocked despite the dependency being functionally satisfied. Fix:
  new `work_wd_state_rank` helper in `work-lib.sh` mapping the
  lifecycle (DRAFT < SPECIFYING < SPECIFIED < IMPLEMENTING < COMPLETE)
  to numeric ranks, with monotonic comparison at the two wd-dep call
  sites in `work-resolve.sh`. Spec and ADR dep checks keep
  exact-match — those have terminal-replaced states (INVALIDATED,
  superseded) that should NOT silently satisfy a need-APPROVED /
  accepted dep.

### Changed

- **`/curate` step 2m routing**. The default remediation for "APPROVED
  specs with no annotations at all" is now `/spec-backfill <spec-id>`
  (was `/spec-verify`). `/spec-verify` remains as the alternative for
  cases where the gap may indicate true spec→code divergence rather
  than pure annotation backfill.

---

## [0.16.6] — 2026-05-05

### Fixed

- **`work_check_adr_dep` asymmetric quote handling** (#68). The WD-side
  parser stripped surrounding single/double quotes from frontmatter
  values; the ADR-side `status:` extractor did not. An ADR with
  `status: "accepted"` compared against an unquoted WD
  `required_status: accepted` would never match — every ADR-status
  check on a quoted YAML status silently BLOCKED the dependent WD,
  affecting both `/work-status` runtime resolution and `work-validate.sh`.
  Now `actual_status` is symmetric with WD-side parsing.

- **Narrative parser drops phases for `<group>--wd-NN` slugs** (#68).
  Work-driven feature slugs look like `add-compaction-scheduling--wd-01`,
  but the parent `/work-start` JSONL token carries args `<group> <N>`
  with no `--wd-` infix. The slug-substring filter rejected the parent
  phase, taking every subagent dispatch with it and producing
  "narrative: no phases parsed for slug" at retro time. Fix:
  - `/work-start`, `/work-plan`, `/work-decompose`, `/work` added to
    `COMMAND_TO_STAGE`.
  - Structured WD-slug match: `^(.+?)--wd-(\d+)$` against args' first
    token (group) + a later token (WD number, leading-zero tolerant).
  - `parse_story`'s second-pass `in_feature` state machine treats
    `/work-start` and `/work-plan` with a matching WD title as feature
    entry points, equivalent to scoping for non-work flows.
  - Mirrored to `parse.js` for runtime parity. Also closes a
    pre-existing parity gap by adding `/audit` to the JS
    `COMMAND_TO_STAGE` (Python had it, JS didn't).

### Documentation

- DESIGN.md test manifest synced for the new
  `scenario-work-adr-quote-and-narrative-wd.sh` regression file.

---

## [0.16.5] — 2026-05-04

### Added

- **Forward enforcement of `@spec` annotation coverage** (#67). Every spec
  requirement loaded by `/feature-plan` becomes an obligation that must be
  bound to test or implementation code via an `@spec <spec-id>.R<n>`
  annotation before `/feature-pr` will draft a PR. Pieces:
  - **`rules/spec-annotation-protocol.md`** (new always-loaded rule).
    Format, comment syntax per language, where to put the annotation,
    when to add it.
  - **`scripts/spec-coverage.sh`** (new). Pipeline-wide coverage tracker
    backed by `.feature/<slug>/spec-coverage.md` with `init / update /
    gate / waive / report` subcommands. Also produces the
    `spec-bundle.md` artifact that refactor 4a depended on but no
    upstream skill ever wrote.
  - **`/feature-test`, `/feature-implement`**: mandatory exit checks
    that refuse to advance until every loaded row has at least one
    `@spec` annotation.
  - **`/feature-pr`**: hard gate. Refuses to draft a PR if any
    requirement is unannotated. Resolutions: annotate, waive (recorded
    reason flows into PR description), or override (also recorded).
  - **`/feature-quick`**: spec-aware mode — quick tasks inherit the
    same gate semantics when `.spec/` exists.
  - **`/audit`**: when reconcile mints a new R-id from prove-fix code,
    it now writes the `@spec` annotation to the smallest enforcing
    site so the requirement is born annotated.
  - **`/feature-retro`, `/feature-complete`**: surface the final
    coverage state at every milestone.

### Fixed

- **`spec-resolve.sh` default budget + Step 7b/7c perf** (#66). Real
  specs in mature corpora run 9-12K tokens each, so the prior 8000
  default produced empty bundles for almost every multi-spec
  membership/encryption-domain feature. Bumped 8000 → 25000 across the
  script and all caller skills (and 16000 → 40000 in `/spec-author`
  Pass 2/3 sibling-loaded path). Step 7b conflict scan and Step 7c
  displacement scan rewritten as single awk passes (no subprocess
  fanout); a single 10K-token spec previously took 30+ seconds and
  multi-spec bundles hung indefinitely. New `Force-included` header
  line guarantees the bundle is never empty when there are direct
  candidates.

### Documentation

- DESIGN.md manifest synced for `rules/spec-annotation-protocol.md`,
  `scripts/spec-coverage.sh`, and the two new test scenario files.
  Always-loaded rules count updated (4 → 5 files; ~1,500 → ~2,000
  tokens).

### Migrating

- The `.feature/<slug>/spec-coverage.md` artifact is created the next
  time `/feature-plan` runs in any project that already had specs.
  Existing in-flight features without it will hit a soft gate at
  `/feature-pr` and surface the gap as actionable rather than silent.
- The 25000-token default for `spec-resolve.sh` may produce larger
  resolved bundles in projects that pinned the budget by convention.
  Pass an explicit lower budget to the resolver if you specifically
  need a smaller bundle.

---

## [0.16.4] — 2026-05-04

### Fixed

- **/curate persistence and threshold cumulation** (#65). `/curate` no longer
  reports "0 actionable items" when prior runs deferred or skipped findings.
  Three coupled defects fixed:
  - Review log was overwritten on each run, wiping every prior `deferred` /
    `suggested` row. Now lives in append-only `.curate/review-log.md` and is
    managed via the new `curate-review-log.sh` helper (`migrate` / `append`
    / `unresolved` / `report`).
  - Pre-flight read deferred items but no step re-presented them. New
    Step 2.5 merges previously-deferred items into the pick list as a
    deprioritized "Previously deferred" group, routed by structured key
    prefix (`adr-pressure:`, `kb-stale:`, `link-rot:`, etc.).
  - Pressure / gravity / drift thresholds ran against `LAST_SHA..HEAD`
    only, diluting signals on frequent-cadence runs. Now always run
    against the full configured window. `LAST_SHA` is preserved as a tag
    — findings carry a Status column (`new since last scan` / `ongoing
    since prior scan` / `ongoing (with N new since last scan)` /
    `initial scan`).

### Documentation

- DESIGN.md manifest synced for `curate-review-log.sh` and the new test
  scenario file. `scenario-curate-scan` test count corrected (47 → 61).

### Migrating

Existing `.curate/curation-state.md` files with inline Review Log rows
auto-migrate to `.curate/review-log.md` on the next `/curate` run
(idempotent — re-running on a migrated state file is a no-op).

---

## [0.16.3] — 2026-04-28

Closes the artifact↔world drift-detection gap in `/curate` with two new
mechanical analyses, plus a focused verify mode that routes those
candidates to existing repair commands. Adds a depth-pass-only entry
to `/spec-author` for re-falsifying mature specs without re-authoring
(PR #64).

### Added

- **/curate Analysis 21 — link rot in KB entries.** Extracts URLs from
  KB body text (markdown links + bare URLs, code-fence excluded), curls
  each via HEAD with a 7-day cache to bound wall-clock cost, flags 4xx
  + connection failures (000). 5xx are treated as transient and skipped.
- **/curate Analysis 22 — falsification-lens staleness.** APPROVED specs
  whose git first-commit-touched date predates a falsification lens AND
  whose body matches the lens's keyword pattern. Lens registry at
  `scripts/lens-registry.txt` is the single source of truth for lens
  names + introduction dates + keywords.
- **/spec-author `<spec-id> --depth-pass-only [--lens <name>]`** — new
  entry path that skips Pass 1 + Pass 2 and runs Pass 3 against an
  existing APPROVED spec. Optional `--lens` biases the depth pass
  toward a specific falsification lens reference (e.g.,
  `prompts/audit/lens-security.md`). Independently useful: invoke
  directly to depth-pass any APPROVED spec, not only when /curate
  routes it.
- **/curate `--verify [--analysis <name>]`** — focused pass over
  verification-shaped candidates only (Analyses 21 + 22). Skips the
  broader correlation flow. Dismissals persist to
  `.curate/verify-dismissed.txt` so future verify runs don't re-prompt
  the same items. `--analysis link-rot|falsification-stale|all`
  narrows further.

### Fixed

- **curate-scan.sh:** bare-URL extraction regex `[^[:space:]<>")\]]+`
  worked in `ugrep` (Claude Code's wrapper) but failed in GNU grep —
  `\]` is not honored as escaped `]` inside a bracket expression in
  GNU grep. Corrected to put `]` first in the negated class
  (POSIX-portable across grep implementations).

### Tests

Four new scenario tests, 55 invariants total, all green:

- `scenario-curate-link-rot.sh` (17/17)
- `scenario-curate-falsification-stale.sh` (13/13)
- `scenario-spec-author-depth-pass-only.sh` (11/11)
- `scenario-curate-verify-routing.sh` (14/14)

`tests/test-install.sh` 64/64 (verifies `lens-registry.txt` installs
to `.claude/scripts/lens-registry.txt` via MANIFEST + install.sh).

---

## [0.16.2] — 2026-04-28

Fixes the repeated "fix retro artifacts" follow-up PRs caused by `/feature-pr`
running retro after the feature PR was created. Retro now runs inline before
PR creation and its outputs ride the feature PR to merge (PR #63).

### Fixed

- **feature-pr:** Move `/feature-retro` invocation inline as a new Step 4.5,
  *before* the feature records are committed. Retro outputs (KB feature
  footprints, adversarial findings, capability index updates, work-definition
  status changes) now flow into the same commit that opens the PR. The
  pre-existing post-PR "Run retro now" offers — the structural cause of
  stranded artifacts — have been removed. Idempotent via a `retro-complete`
  check in `cycle-log.md`; skip path requires explicit confirmation and
  annotates the PR body.
- **feature-pr Step 5:** Now stages `.capabilities/` and `.work/` in addition
  to `.kb/` and `.decisions/`. Even pre-PR retro would have stranded the
  capability index and work-tracking updates without this.
- **feature-retro:** Reframed to be invoked from `/feature-pr` Step 4.5.
  Direct invocation supported for archived features (late-discovered
  learnings) or post-skip recovery (with warning that recovery needs its own
  follow-up PR). New idempotency check prompts skip-vs-rerun when
  `retro-complete` already exists in `cycle-log.md`, preventing duplicate
  KB entries from accidental re-runs.

---

## [0.16.1] — 2026-04-27

Triage from a `/spec-split` + `/curate` run on jlsm surfaced 8 issues across
`spec-split`, `curate-scan`, `index-verify`, and the installer template. All
addressed with regression tests (PR #62).

### Fixed

- **spec-split:** Compound `@spec parent.R1,R2[,R3]` annotations now route
  each R to its correct child during a split. The literal-substring rewrite
  previously matched the parent prefix and left subsequent Rs in the comma
  list dangling under the wrong child (blocked the
  `query.sql-query-support` split where 54 of 195 R-level annotations were
  compound). The sweep now pre-explodes compounds into one annotation per R
  on consecutive lines before per-R rewrite.
- **spec-split / spec-validate / spec-trace / spec-lib / spec-resolve /
  spec-ambiguity-score / curate-scan:** Recognize hyphenated sub-numbered Rs
  like `R37b-1`, `R83-1`, `R76a-1`, `R71b-2`, `R78g-3` as first-class
  R-claims. Previously these were silently swallowed when first under a
  section header.
- **spec-split:** Parent's manifest entry version is now bumped in lockstep
  with the file's frontmatter version. Previously the manifest stayed stale
  (file v14 vs manifest v13) after a split, leaving downstream tooling
  inconsistent.
- **spec-split:** Source-file rollback now uses pre-sweep snapshots, so the
  rollback log can faithfully restore files even after the compound-annotation
  explosion pass (which can rewrite multiple lines on a single source line).
- **curate-scan:** "Specs with open obligations" no longer false-positives on
  empty `open_obligations: []` arrays in JSON frontmatter. The frontmatter
  check now uses `jq` instead of a shell stripper that left punctuation
  behind and registered as content (was reporting ~79 false-positive specs
  on real-world scans).
- **curate-scan:** "Unspecified shared types" now blocklists JDK / standard
  library types (`IllegalArgumentException`, `NullPointerException`,
  `IllegalStateException`, common collections, IO, time, concurrency
  primitives) so genuine project value-types surface above the noise.
- **curate-scan:** Specs with bare `@spec engine.foo` annotations (no
  `.R<n>` suffix) are now classified as a separate `BARE_ONLY` gap class
  instead of being lumped into "no annotations at all". The remediation
  differs (refine vs. add from scratch).
- **index-verify:** Decisions index now actually overflows oldest "Recently
  Accepted" rows to `history.md` when the 80-line cap is exceeded.
  Previously the script logged a warning and proceeded, letting the index
  grow unbounded after auto-repair (e.g. 46 reconstructed ADRs → 151 lines).
  Tunable via `VALLORCINE_DECISIONS_KEEP` (default 5 most-recent rows).
- **install:** Installer's `.gitignore` template now ships with
  `.spec/.split-log/` and `.spec/.split-plan.json`. Existing installs (with
  the runtime block already present) pick these up on re-install via a new
  per-entry append path. Idempotent — re-running install does not duplicate
  entries.

### Changed

- **curate-scan summary heading:** "APPROVED specs with no annotations at
  all" → "APPROVED specs with no @spec annotations of any kind", to
  distinguish from the new `BARE_ONLY` class.

---

## [0.16.0] — 2026-04-27

Spec-layering initiative — a mature spec can now subdivide into a parent +
concern-specific children, each a full spec, with the parent retaining
R-numbered cross-cutting requirements. Subdivision is a natural progression
triggered by either `/curate` housekeeping or `/spec-author` Pass 2 just-in-
time signals; never a remediation step. PR #61 plus two soak-followup fixes
surfaced from a 4-day jlsm session sweep (2026-04-23 → 2026-04-27).

### Added

- **Spec layering — natural progression of growing domains.** A mature spec
  can subdivide into a parent + concern-specific children, each a full spec.
  The parent retains R-numbered cross-cutting requirements; children own
  concern-specific requirements. Subdivision is a normal flow, not a
  remediation step. Triggered by either `/curate` housekeeping (passive
  detection) or `/spec-author` Pass 2 (just-in-time during amendments).
  Backwards-compatible — flat specs continue to work unchanged.

  - **`/spec-split <spec-id>` skill** orchestrates the subdivision: identifies
    natural concern boundaries from the spec's existing section structure,
    confirms with the user via `AskUserQuestion` (with edit option), builds a
    JSON plan, and invokes `scripts/spec-split.sh` — a transactional executor
    that snapshots prior state into a rollback log under `.spec/.split-log/`,
    carves child files preserving R-number identity (R45 stays R45 in the
    child), rewrites the parent to retain only cross-cutting requirements,
    updates the manifest with `parent_spec` references, sweeps `@spec`
    annotations in production source dirs (skipping `test/`, `tests/`,
    `node_modules/`, `vendor/`, `target/`, `build/`, `dist/`), and runs
    `spec-validate` on parent + every child. **On any post-write validation
    failure, the executor automatically replays the rollback log** — parent
    restored, children deleted, manifest reverted, annotation rewrites
    reversed. The rollback log is preserved for one release in case manual
    inspection is needed.

  - **`/curate` subdivision-candidate detector** (Analysis 20) flags specs
    that have grown past one file's worth of behavior (≥50 R-requirements OR
    ≥15K tokens) AND show multiple distinct concerns (≥2 section headers, no
    single section holding ≥90% of requirements). Specs already in a layered
    family (`parent_spec` set) are excluded. Surfaces as a "Subdivision
    Candidates" section in the scan summary with a suggested
    `/spec-split <id>` per candidate. New `AskUserQuestion` path lets the
    user subdivide / decline (with documented reason) / defer per candidate.
    Decline is a first-class outcome — subdivision should never be forced on
    indivisible concerns.

  - **`/spec-author` Pass 2/3 layered awareness.** Pre-flight Step 6 detects
    when the target is a child spec (`parent_spec` set) and re-runs the
    resolver with `INCLUDE_SIBLINGS=true` so falsification subagents see the
    parent body + every sibling body — enabling cross-sibling contradiction
    detection. After Pass 2 arbitration, a non-blocking just-in-time
    subdivision signal surfaces a `/spec-split <id>` suggestion when the
    in-progress spec has tipped into subdivision territory by the same
    thresholds `/curate` uses. Pass 3 still runs unconditionally; the signal
    is silent when thresholds don't match.

  - **Schema and read-path foundation.** New optional `parent_spec`
    frontmatter field. Multi-dot ID grammar (`a.b.c.d`) accepted by
    `spec-validate.sh` and `spec-trace.sh`. `spec_file_for_id()` falls
    through to ID-computed path on manifest miss
    (`a.b.c.d` → `domains/a/b/c/d.md`). New `spec_walk_parent_chain()` and
    `spec_children_for()` helpers in `spec-lib.sh`. `spec-resolve.sh`
    auto-includes parent chain when a child lands in candidates;
    `INCLUDE_SIBLINGS=true` opts into siblings. `spec-validate.sh` enforces
    parent existence, ID-prefix consistency, and acyclic chains.
    `.spec/CLAUDE.md` documents the model — file layout, ID grammar,
    validation rules, when to subdivide, when not to.

### Fixed

- **`/work-start` and `/work-plan` WD status updates use `sed -i`, not
  `Edit`.** The Edit tool requires the target file to be Read in the same
  session first; three status-update instructions in
  `skills/work-start/SKILL.md` (4d) and `skills/work-plan/SKILL.md` (4c, 6)
  had the assistant Edit `.work/<group>/WD-<nn>.md` without otherwise needing
  its content, which produced predictable "File has not been read yet"
  errors during real runs. The kit already used
  `sed -i "s/^status:.*$/status: COMPLETE/"` in `scripts/work-finalize.sh:80`
  for the equivalent operation; the skill prompts now mirror that pattern.
  Surfaced from the 2026-04-23 → 2026-04-27 jlsm session sweep. Regression
  test: `tests/scenario-wd-status-update-no-edit.sh` (6 invariants).

- **Pipefail SIGPIPE on large `$var | grep` pipelines.** Three scripts piped
  potentially-large stdin into early-stdin-closing tools (`grep -q`,
  `grep -m1`), which exit-141'd under `set -o pipefail` once the input
  crossed the 64 KB pipe buffer. With negation in front of the pipe
  (`if ! echo "$x" | grep -q ...`), exit 141 was treated as success — the
  check silently flipped on large inputs. Triggered on jlsm by
  `spec-validate.sh` Check 9b on a 134 KB `encryption.primitives-lifecycle`
  machine section. Switched seven sites across `scripts/spec-validate.sh`,
  `scripts/kb-search.sh`, and `scripts/curate-scan.sh` from
  `echo "$var" | grep` to here-string form `grep ... <<< "$var"`. The
  here-string buffers the whole content before grep reads, so SIGPIPE cannot
  back-propagate. Regression test: `tests/scenario-pipefail-sigpipe.sh` (10
  invariants — structural drift detection on the patched sites + runtime
  check on a synthetic 881 KB spec).

### Tests

- 5 new scenario test files, 91 new invariants total.
- 42/42 scenario tests passing, 59/59 install tests passing.

### Migration

No migration needed. `parent_spec` is opt-in. Specs without it continue to
work; multi-dot IDs are accepted but no ID changes are forced. `/spec-split`
is run per-spec when the user agrees a subdivision is warranted.

---

## [0.15.0] — 2026-04-24

Work-layer redesign. Two PRs: #59 ships `/work-decompose` Phase A/B/C
plus `/work-status` state-routing; #60 adds cross-group dependencies,
the Group Envelope handoff into `/work-plan`, and three pre-existing
bug fixes surfaced empirically by exercising the kit end-to-end
against a fresh work group on a local jlsm clone.

### Added
- **`external_deps:` frontmatter on `work.md`** declares cross-group
  dependencies. A group with `external_deps: [{ type: group, ref:
  "<other-group>", required_state: COMPLETE }]` reports every DRAFT
  and SPECIFIED WD as BLOCKED until the referenced group reaches
  COMPLETE. IMPLEMENTING/COMPLETE/SPECIFYING WDs bypass the gate —
  in-flight or finished work is not retroactively un-done. Closes
  the gap where `implement-membership/work.md` declared its
  cross-group blocker in prose with no machine enforcement.
- **`/work-plan` Step 4a brief.md gains an authoritative "Group
  Envelope" section** listing every artifact_dep with state and
  summary, plus `out_of_scope` and `external_deps` from `work.md`.
  Frames Phase B outputs as authoritative for WD-local analysis.
- **`/feature-domains` reads the Group Envelope** in Step 2 and
  classifies covered domains as `resolved` with source annotation
  `group envelope: <ref>`. Avoids redundant `/architect` dispatches
  on decisions already settled at the group level.
- **New `escalate-decompose` classification state.** When WD-local
  analysis would contradict an envelope item, the scout halts rather
  than self-resolving and points the user back to `/work-decompose`.
- **`/work-plan` Step 5b dedupes spec authoring against the
  envelope** — specs already APPROVED at the group level are
  skipped with a "deferred to group-level spec" log line.
- **`work-validate.sh --decompose` invariant check** — verifies every
  cross-WD reference resolves to (a) an existing artifact, (b)
  another WD's `produces:`, or (c) an explicit `out_of_scope:`
  declaration. Prevents parallel `/work-plan` runs from diverging.
- **`out_of_scope:` frontmatter field on `work.md`** — explicit list
  of references the group intentionally doesn't handle. Satisfies
  the invariant check without forcing unwanted Phase B work.

### Changed
- **`/work-decompose` rewritten as Phase A/B/C** (PR #59). Was
  LLM-only scope-splitting; now Phase A is seam-finding with
  `/research` dispatch for unknowns that change WD shape, Phase B
  is user-serial `/architect` + `/spec-author` for cross-WD
  decisions and shared specs, Phase C re-carves WDs with Phase B
  outputs in hand and runs the mandatory invariant check.
  Target-count framing dropped — natural composition drives WD
  count.
- **`/work-status` routes by state.** READY → suggests `/work-plan`
  only; SPECIFIED → suggests `/work-start` only; `--all` mode has
  separate sections (Ready to specify / Ready to implement / Resume
  in progress / Blocked). Closes the wrong-command round-trip where
  `/work-status` would suggest `/work-start` for READY WDs which
  `/work-start` then rejected.
- **`produces:` in WD frontmatter is now optional.** Previously the
  LLM was instructed to predict outputs at decompose time — a
  prediction often wrong since WD-local artifact shape emerges
  during `/work-plan`. Honest empty preferred over guesses. Only
  populated for artifacts whose shape is settled at decompose time.
- **Scope discipline made explicit:** `/work-decompose` shapes
  relationships between chunks, never fully scopes each chunk.
  Zero-new-artifact decompositions are valid.
- **`work-validate.sh` no longer treats `wd:` state mismatch as a
  hard FAIL.** State alignment is the resolver's responsibility;
  validate now checks only structural correctness for `wd:` refs
  (target exists, in same group). Eliminates the false-FAIL noise
  on every freshly-decomposed downstream WD.
- **`work-validate.sh` and `work-resolve.sh` now share one spec
  lookup path (`work_check_spec_dep`).** Both accept ID-style
  (`engine.catalog-operations`) and slash-path (`engine/catalog-operations`)
  refs uniformly. Eliminates the asymmetry where validate would
  reject what resolve accepted.

### Fixed
- **`work_fm_produces` parser dropped `slug:` for ADR produces.**
  The artifact_deps parser accepted path/slug/ref, but produces
  only accepted path. Real ADR produces use `{ type: adr, slug:
  "<slug>" }` (matches `.decisions/<slug>/adr.md`), so the
  identifier was silently dropped. Surfaced 78 false-alarm
  validation errors in jlsm; verified 78 → 0 after fix.
- **Cross-group `wd:` artifact_deps now rejected by validate** with
  a pointer at `external_deps`. Previously validated OK but were
  unreachable at runtime because `work-resolve.sh` populates its
  WD table from the current group only. Validate and runtime now
  agree on what's reachable.

### Documentation
- **`/work` scoping interview should lead with tradeoff analysis
  before AskUserQuestion** when the choice has non-obvious
  implications. Bare option-and-description works for label
  picking, not for architectural decisions.
- **`/work-decompose` Phase A research-dispatch criterion added:**
  dispatch when the answer would change the *shape* of WD chunks,
  not just internal details.
- **`/work-decompose` Phase B "decidability" test added:**
  Phase B-author when the artifact's shape isn't decidable from
  any single WD's perspective alone. Bilateral
  producer→consumer flows can sequence WD-locally; multi-producer
  schemas, cross-WD invariants, and shape-ambiguous multi-consumer
  artifacts qualify for Phase B.
- **`/work-decompose` Phase C surfaces the SPECIFIED-vs-COMPLETE
  choice for `wd:` deps** explicitly. Default-by-precedent was
  COMPLETE, forcing fully sequential planning; SPECIFIED unlocks
  parallel `/work-plan` execution while still gating on spec
  contracts.
- **WD template documents both accepted forms for spec refs**
  (slash-path + ID), the same-group constraint for `wd:` refs,
  and the slug/path/ref distinction across artifact types.

### Tests
- New `tests/scenario-work-cross-group-deps.sh` (11 invariants):
  block/unblock flow, missing-group handling, malformed
  `external_deps` shapes, IMPLEMENTING/COMPLETE bypass, cross-group
  `wd:` rejection.
- `tests/scenario-work-layer-alignment.sh` extended from 20 → 25
  invariants covering Phase A/B/C contract and Group Envelope
  handoff structure.
- `tests/scenario-work-validate.sh` extended from 17 → 20 with
  tests for symmetric ID/path lookup, slug parsing in produces,
  and the corrected `wd:` state-mismatch behavior.

### Note
Empirical Gap 3 validation is post-merge. Structural tests prove the
SKILL.md says the right things; the first real `/work-plan` run on a
WD with a Group Envelope is the actual test of the LLM following
those instructions.

---

## [0.14.4] — 2026-04-24

### Fixed
- **Parallel WU-TDD subagents silently skipped the `/feature-implement`
  Step 8 KB tendency scan.** Root cause: `/feature-coordinate`'s
  dispatch-prompt template embedded the termination contract added in
  v0.14.3 but not the KB-scan instruction. Subagents ran the rich
  self-contained prompt and never reached Step 8. Empirical gap
  (2026-04-24): 0 of 4 WU-TDD subagents consulted `.kb/` across a
  real jlsm parallel run. Fix: `/feature-coordinate` Step 1a now
  carries a "KB tendency-scan contract (MANDATORY)" fragment that
  subagent prompts must include verbatim, referencing `kb-search.sh`
  and the `tendency-scan-complete` substage.
- **`/feature-implement` Step 8 was missing a substage checkpoint,
  which made skipped scans invisible.** Fix: Step 8 is now labelled
  MANDATORY and requires both a `status.md` substage write
  (`tendency-scan-complete: <construct> — <n> patterns checked,
  <n> applied`) and a `cycle-log.md` append (`tendency-scan
  (<construct>): <n> results / <n> applied / <n> skipped`) after
  every scan, including zero-result scans. The coordinator's
  post-return verification now greps for these entries and surfaces
  a `tendency-scan-missing: WU-<n>` marker when a COMPLETE unit has
  no scan evidence despite a non-empty `.kb/`.
- **Audit Suspect treated KB entries in cluster packets as passive
  reference material, not attack vectors.** Empirical result
  (2026-04-24): KB content flowed correctly Classification →
  Assembly → packet (17/17 packets carried KB summaries), but only
  2/95 Suspect findings referenced KB — per-construct protocol
  never iterated the packet KB as a sweep list. Fix: `suspect.md`
  adds step 4 "KB attack-pattern sweep (MANDATORY when packet lists
  KB entries)" which iterates each `type: adversarial-finding` entry
  as a candidate attack and emits FINDING with `kb_refs`, CLEARED
  with KB reference + defense evidence, or no-op. Finding schema
  gains `KB refs:` field; Clearings table gains a `KB ref` column;
  summary line reports `KB-driven` count alongside `card-driven`.
- **Audit prove-fix had no KB integration at all — 0/95 outputs
  referenced KB guidance.** Fix: `prove-fix.md` gains Phase 1a1 "KB
  fix-pattern lookup (when kb_refs present)" which reads
  orchestrator-supplied KB paths for `## Test guidance` and fix
  patterns before writing the test. Output schema records
  `KB refs consulted`. Hard-rules block carves out KB reads for
  paths listed in `kb_refs`. `prove-fix-orchestrator.md` now
  forwards each Suspect finding's `KB refs` value through the
  dispatch template as `kb_refs: <paths | none>`.

### Changed
- `prompts/audit/suspect.md` finding schema and summary reporting
  (non-breaking — consumers that don't read `KB refs` keep working;
  per-finding field is additive).
- `prompts/audit/prove-fix.md` output schema adds a top-level
  `KB refs consulted` block and recognises a new `UPSTREAM_MITIGATED`
  Phase 0 result (additive).
- `prompts/audit/prove-fix.md` Phase 0 budget raised from 2 to 4 turns
  to accommodate up to 2 prior-output reads in step 0c. Existing 2-turn
  short-circuits for local `ALREADY_FIXED` are unchanged.

### Performance
- **Audit cost-per-bug reduction target.** Analysis of a 95-finding
  jlsm audit run (Opus 4.7, $1,333 audit share, $14.03/finding)
  showed 16 of 36 IMPOSSIBLE returns (~17% of total findings) were
  actually mitigated by a prior prove-fix's upstream guard — the
  agent didn't have a Phase 0 path for that case and went through
  full Phase 1 anyway. New Phase 0c "upstream-mitigation check"
  scans up to 2 sibling `prove-fix-*.md` outputs for a caller-side
  guard that blocks the attack path and short-circuits to
  `IMPOSSIBLE / UPSTREAM_MITIGATED`. Estimated savings: ~11% of
  prove-fix cost per audit. Combined with KB-actionable fixes
  (suspect KB sweep pre-clears patterns that match existing KB
  entries), projected audit cost floor is ~$11/finding on runs
  with similar KB density.

### Tests
- New `tests/scenario-kb-scan-contract.sh` — 22 structural invariants
  across 7 surfaces (coordinator dispatch, coordinator verification,
  Step 8 checkpoints, suspect sweep + schema, prove-fix KB lookup +
  schema, orchestrator forwarding, Phase 0 upstream-mitigation
  short-circuit). Mirrors the
  `scenario-parallel-subagent-hang-prevention.sh` pattern from v0.14.3.

---

## [0.14.3] — 2026-04-24

### Added
- **Onboarding guides** (repo-only, not shipped to user projects) —
  `GETTING-STARTED.md` covers the mental model: the four knowledge
  layers (KB / ADR / spec / code) and how they feed each other, the
  feature pipeline at a glance, when work groups apply, and a
  "what to run when" decision tree.
  `GETTING-STARTED-EXISTING.md` covers the slow-adoption path for
  brownfield projects — Day 1 / Week 1 / Month 1 / Month 3 progression
  anchored on `/setup-vallorcine` + `/curate --init`, the lazy-spec
  rule, and common pitfalls. README links both from a new "New here?"
  section; `/vallorcine-help` gains URL hints for conceptual questions.
- **Four new `EXAMPLES.md` walkthroughs** for v0.14.2 features that had
  none: parallel execution via `/feature-coordinate` +
  `/work-start --parallel`, the opt-in spec workflow (`/spec-init` →
  `/spec-author` → `/spec-write` → `/spec-verify` → `/spec`),
  standalone `/audit` with all four entry-point shapes, and
  `/capabilities`.

### Changed
- **`/audit` wontfix findings now resurface via `/curate`** (#56) —
  option 2 ("Accept as wontfix") in the FIX_IMPOSSIBLE escalation flow
  now logs a non-blocking `wontfix: <finding-id> — <rationale>`
  obligation on the most-relevant spec (if `.spec/` exists).
  `/curate` analysis 19 (aging-obligations) ages the obligation by
  last-commit time and resurfaces it once past the threshold. The spec
  stays APPROVED — wontfix is a landed design decision, not a gap.
  Closes the only remaining graveyard path for FIX_IMPOSSIBLE outcomes.

### Fixed
- **v2 manifest schema compatibility across spec/work/curate scripts**
  — `spec-resolve.sh`, `work-lib.sh`, `work-finalize.sh`,
  `curate-scan.sh`, and `spec-stats.sh` were written against the v1
  manifest schema (`.features`/`.domains` as keyed maps) and broke
  silently after the 2026-04-20 v2 migration (`.specs[]` array, no
  top-level `.domains`). `spec-resolve.sh` hit `jq: null has no keys`
  under `set -euo pipefail` and fell through to
  `NEEDS_DOMAIN_INFERENCE=true` for every call, blocking `/work-start`,
  `/spec-write`, `/feature-plan`, `/feature-test`, `/spec-author`, and
  `/audit` on v2 repositories. Added four dual-schema manifest query
  helpers to `spec-lib.sh` (`spec_manifest_ids`,
  `spec_manifest_state`, `spec_manifest_domains_for`,
  `spec_manifest_all_domains`, plus an `is_v2` probe) and updated
  every caller to use them. `spec_registry_update` now writes v2-shape
  entries when the manifest is v2 instead of silently injecting a v1
  `features` key alongside the v2 `specs` array. Regression: 5 new
  v2-fixture tests in `scenario-spec-resolve.sh` (16 → 21 total).
- **Parallel-subagent hang prevention** — when `/feature-coordinate`
  dispatches work units as concurrent sub-agents, two failure modes
  could leave the coordinator blocked indefinitely on `Agent` tool
  calls: (a) pipeline skills (`/feature-test`, `/feature-implement`,
  `/feature-refactor`) had `AskUserQuestion` sites that fired
  regardless of `automation_mode`, which hang with no human attached;
  (b) the refactor skill's parallel-mode exit said only "STOP" as
  prose, so subagents that wrote `status.md = complete` could keep
  running tools for minutes before emitting their final summary.
  Every unconditional `AskUserQuestion` now has a `balanced | speed`
  bypass that records to `cycle-log.md`, marks substage
  `escalated-<reason>`, and returns `ESCALATED` so the coordinator can
  surface it via its existing escalation flow. `/feature-refactor`'s
  parallel exit now carries an explicit termination contract
  ("your next message MUST be the summary — no more tools"), and
  `/feature-coordinate` documents the subagent dispatch contract so
  coordinators embed the termination rules in every Agent prompt.
  Root-caused from the 2026-04-23 jlsm WU-3 hang (subagent finished
  work, wrote status complete, kept running ~2 min before user
  Ctrl+C). Regression:
  `tests/scenario-parallel-subagent-hang-prevention.sh` (10
  structural invariants).
- **Four pre-existing scenario-test failures** — baseline on main,
  surfaced during the manifest-v2 compat sweep and closed in the same
  PR. `scenario-index-verify` (grep output concatenation bug in
  `scripts/index-verify.sh`), `scenario-narrative` (stale exit-code
  assertions that pre-dated the narrative-wrapper retry contract),
  `scenario-version-skew` (legacy `.claude/commands/` path reference),
  `scenario-work-pipeline` Test 10 (v1-manifest fixture collided with
  v2-style WD artifact deps).

---

## [0.14.2] — 2026-04-22

### Added
- **`/audit` security lens** — adversary-model bug classes (info flow, auth,
  injection, crypto, config sensitivity) activate automatically when a cluster
  touches crypto APIs, credential stores, PII handling, auth paths, or input
  boundaries. Findings are split into TESTABLE (routed through prove-fix) and
  ADVISORY (non-functional properties flagged for user review). (#53)
- **`/audit` FIX_IMPOSSIBLE escalation** — when prove-fix cannot satisfy a
  finding under current spec constraints, the audit pipeline surfaces a
  relaxation request with a structured escalation report; the finding stays
  FIX_IMPOSSIBLE but is recorded as a spec obligation referencing the request. (#51)
- **`/spec-write` quantitative ambiguity gate** — `spec-ambiguity-score.sh`
  scores a spec on token/heuristic ambiguity before registration, blocking
  specs that exceed the threshold. (#52)
- **`/work-start --parallel [N]`** — start every SPECIFIED work definition
  concurrently, optionally capping at N concurrent sub-agents. (#54)

### Changed
- DESIGN.md scripts manifest now lists `spec-ambiguity-score.sh`.

---

## [0.14.1] — 2026-04-21

### Added
- **Curate drift-detection analyses** — `/curate` now surfaces two new
  spec-drift signals. Analysis 18 enumerates APPROVED specs from
  `.spec/registry/manifest.json`, invokes `spec-trace.sh` for each, and
  flags requirements whose `@spec` annotations are missing on the
  implementation or test side (plus APPROVED specs that have zero
  annotations anywhere). Analysis 19 enumerates specs with non-empty
  `open_obligations` frontmatter, computes age from the last commit
  touching the spec file, and flags obligations older than a
  configurable threshold. Both dual-schema aware (v1 `features` object +
  v2 `specs` array). New `curate-scan.sh` flags:
  `--obligation-age-days <n>` (default 30) and
  `--max-specs-traced <n>` (default 50). Routes: annotation gaps to
  `/spec-verify`; aging obligations to `/spec-author` or `/spec-resolve`.

### Changed
- **`/feature-test` no longer silently falls back when spec resolution
  misses** — Step 1a used to set SPEC_BUNDLE empty and proceed if
  `spec-resolve.sh` returned nothing, even when the project had `.spec/`
  with APPROVED specs. Tests generated in that path lost `covers: R<N>`
  annotations downstream implementers rely on. Now when `.spec/` exists
  with APPROVED specs and the resolver returns empty, `/feature-test`
  stops and offers three remediation paths: re-invoke with
  `--specs <ids>`, list spec IDs in `.feature/<slug>/brief.md`, or
  rewrite the brief. Projects without `.spec/` or with no APPROVED
  specs proceed silently as before.
- **`/feature-test` gains `--specs <id1,id2>` flag** for explicit spec
  ID pass-through when fuzzy match misses. Plumbed through to
  `spec-resolve.sh` via new `EXPLICIT_SPEC_IDS` env var that bypasses
  domain inference. Feature briefs can also list explicit spec IDs via
  a `specs:` field in `.feature/<slug>/brief.md`.
- **`/feature-refactor` runs inline `/spec-verify` before the
  adversarial audit pass** (new Step 4a) — resolves the APPROVED specs
  this feature touches (via `spec-bundle.md`, `@spec` annotations in
  changed files, or `work-plan.md` frontmatter) and invokes
  `/spec-verify` per spec as a sub-agent. Drift surfaces directly as
  spec violations rather than masquerading as adversarial findings in
  the broader Step 4b audit. Skipped when no `.spec/` directory, no
  specs loaded for the feature, or running via `/feature-quick`.

### Fixed
- **`/audit` refuses to run against non-APPROVED specs** for `spec:<id>`
  entry points. A DRAFT or INVALIDATED spec has no authoritative
  contract, so Lens A SPEC-REQ findings have nothing to prove against
  and the pipeline produces adversarial-only findings a user would
  mistake for conformance bugs. New `scripts/audit-state-gate.sh` gates
  the entry; feature/file/prior-report entries are unaffected.
  Regression tests in `tests/scenario-audit-state-gate.sh`.
- **`work-validate.sh` resolves `artifact_deps` references** — dead
  references (spec ID not in registry, WD that doesn't exist) and
  state mismatches (WD declares `required_state: APPROVED` against a
  DRAFT spec) used to pass validation and fail later during
  `/work-plan` or `/work-start`. Now resolves each reference (spec via
  manifest, ADR file, WD scan, KB file) and either matches state or
  errors with a clear message. Missing infrastructure (no manifest,
  no `.decisions/`, etc.) emits WARN and proceeds — projects not yet
  using that layer aren't blocked. Five regression tests in
  `tests/scenario-work-validate.sh` (Tests 13-17).
- **`upgrade.sh` no longer prints false "skip … refusing to remove" for
  kept kit files** ([#45](https://github.com/telefrek/vallorcine/issues/45))
  — the stale-file loop now checks the new manifest first, so files in
  both the old and new manifests skip silently. `.claude/prompts/*`
  added to the whitelist for when prompts are legitimately removed in
  future versions. Previously a clean v0.13.8 → v0.14.0 upgrade emitted
  29 misleading skip messages. Regression test in
  `tests/test-install.sh` Test 9e.

---

## [0.14.0] — 2026-04-21

### Added
- **@spec annotation standard** — `@spec FXX.RN` code comments for spec↔code
  traceability. Documented in `spec/CLAUDE.md` Code Traceability section.
- **`spec-trace.sh`** — finds `@spec` annotations across codebases, groups by
  file, distinguishes implementation vs test locations. Summary / detail /
  JSON output formats. 13 scenario tests. Accepts both `FXX.RN` and
  `domain.slug.RN` spec ID formats.
- **Work layer (`.work/`)** — fourth knowledge layer for composable
  multi-feature work. Decompose large goals into work definitions with
  artifact-based dependencies and computed readiness. Same pull-model
  pattern as KB, decisions, and specs.
- **`/work "<goal>"`** — create a work group with scoping interview.
- **`/work-decompose "<slug>"`** — break a work group into work definitions
  with dependency graph and shared interface contracts. Supports
  `--from-obligations` to carry deferred work forward.
- **`/work-status "<slug>"` / `--all`** — readiness report: what is READY,
  BLOCKED, IN_PROGRESS, or COMPLETE.
- **`/work-plan "<slug>" [WD-nn | next]`** — specification-only pipeline on
  a WD (domain analysis + spec authoring, stops before implementation).
- **`/work-start "<slug>" [WD-nn | next]`** — start implementing a ready
  work definition, bridging into the feature pipeline. Distinguishes hard
  `type: wd` blocks from soft artifact blocks.
- **Interface contracts** — specs with `kind: interface-contract` for shared
  surfaces between work definitions. Reuses all existing spec tooling.
- **Pipeline modes** — `specification` (produce artifacts only),
  `implementation` (consume existing specs, skip scoping/domains), `full`
  (default, backwards compatible). Mode-aware routing in `feature-resume`.
- **Work-aware context injection** — architect (forward compatibility,
  ordering gates), spec-author (downstream consumers), feature-domains
  (cross-WD domain reuse), feature-plan (interface stability constraints),
  feature-resume (work group grouping).
- **Obligation lifecycle** — `type: wd` WD-to-WD dependencies in
  `artifact_deps`; obligation scanning in `/curate` (analysis 10e);
  `work-finalize.sh` auto-resolves WDs + obligations on feature complete.
- **Curate analyses 15-17** — cross-WD spec displacement, stalled work
  groups, artifact dependency drift.
- **Manifest schema v2** — `.spec/registry/manifest.json` supports
  `{schema_version: 2, specs: [{id, path, ...}]}`. Kit detects both v1 and
  v2 automatically.
- **EXAMPLES.md** — added "Coordinating multi-feature goals with work
  groups" walkthrough.

### Changed
- **`/spec-verify` redesigned as verify-and-repair loop** — 6-phase flow:
  verify all requirements → classify findings (code-bug / stale-spec /
  needs-decision / test-gap) → resolve decisions → amend stale specs → fix
  code via TDD with regression tests → finalize. Violations repaired
  inline, not parked as obligations.
- **`/spec-verify` annotates during discovery** — adds `@spec` annotations
  to implementation and test files as it reads them.
- **`/spec-verify` fills test gaps** — writes structural/behavioral tests
  for requirements with no test-side annotation coverage.
- **Spec ID format support** — `spec-trace.sh`, `spec-validate.sh`,
  `spec-resolve.sh`, and `spec-lib.sh` accept both legacy `FXX.RN` and new
  `domain.slug.RN` formats. Backwards-compatible — existing user projects
  continue working unchanged.

### Fixed
- **`test-install.sh` SIGPIPE** — tests 8-14 silently weren't running due
  to a SIGPIPE early-exit in the harness. Fixed; test count went from
  13 PASS to 56 PASS.
- **`curate-scan.sh`** — 3 `grep -c` pipefail bugs producing `0\n0` instead
  of clean integers on zero matches (lines 104, 439, 637). Pattern:
  `var="$(grep -c ...)" || var=0`.
- **Interactive prompts** — migrated all 35 "Type yes" prompts across 15
  skills to AskUserQuestion with labeled options, per kit-development rules.

### Removed
- Stale `skills/audit/SKILL.md.bak` backup file.

---

## [0.13.8] — 2026-04-14

### Changed
- **`/spec-author` owns full lifecycle** — draft → falsify → arbitrate →
  register. Callers never call `/spec-write` separately, removing the
  shortcut that allowed unfalsified specs to be registered.
- **Manifest single source of truth** — `work-resolve.sh` regenerates
  manifest table from WD frontmatter on every run. No manual manifest updates.

### Fixed
- **Agent bypassing `/spec-author`** — agent was calling `/spec-write`
  directly, skipping adversarial falsification. Self-contained `/spec-author`
  eliminates the shortcut.
- **APPROVED gate** — `/work-plan` verifies each spec is APPROVED before
  marking WD as SPECIFIED. DRAFT specs block completion.
- **kb-freshness false positive** — no longer warns when branch is ahead
  of main.

---

## [0.13.7] — 2026-04-14

### Changed
- **Sequential per-spec authoring** — each spec gets its own `/spec-author`
  subagent with clean context. Sequential ordering means each spec's
  falsification sees prior specs, catching cross-spec contradictions.
- **Manifest is single source of truth** — `work-resolve.sh` regenerates the
  manifest table from WD frontmatter on every run. Skills no longer update
  manifest manually.
- **`/feature-domains` specification mode** — returns after domain analysis
  without chaining into spec authoring. `/work-plan` controls the iteration.

### Fixed
- **APPROVED gate on spec completion** — `/work-plan` verifies each spec is
  APPROVED (not DRAFT) before proceeding. DRAFT specs block WD completion.
- **kb-freshness false positive** — no longer warns when branch is ahead of
  main (differences are our changes, not missing entries).

---

## [0.13.6] — 2026-04-14

### Changed
- **Explicit WD lifecycle phases** — `DRAFT → READY → SPECIFYING → SPECIFIED
  → IMPLEMENTING → COMPLETE` replaces ambiguous `IN_PROGRESS`. `/work-plan`
  sets SPECIFYING/SPECIFIED, `/work-start` requires SPECIFIED and sets
  IMPLEMENTING. Legacy `IN_PROGRESS` auto-maps to IMPLEMENTING.

### Fixed
- **`/work-start` no longer accepts READY WDs** — must go through `/work-plan`
  first to produce specs. Prevents skipping the specification phase.
- **`/work-plan` no longer marks WDs COMPLETE** — sets SPECIFIED instead,
  correctly indicating specs are done but implementation hasn't started.

---

## [0.13.5] — 2026-04-14

### Changed
- **Multi-pass spec falsification** — Pass 3 (depth pass) is now mandatory.
  Data from 5 specs shows round 2 consistently finds critical issues that
  are consequences of round 1 fixes. Pass 4+ prompts on criticals/highs.

### Fixed
- **Spec-mode pipeline stops after spec authoring** — `/work-plan` no longer
  routes to `/feature-retro` and `/feature-complete` after spec authoring.
  Those run after implementation via `/work-start`.

---

## [0.13.4] — 2026-04-13

### Added
- **PreCompact crash recovery hook** — checkpoints active feature status
  before context compaction so `/feature-resume` can recover after overflow.

### Changed
- **Effort tuning** — `effort: high` on 4 adversarial skills (audit,
  feature-harden, spec-author, spec-verify) for deeper reasoning where
  it directly improves bug-finding quality.
- **KB article line limit relaxed** — soft target 200 lines, hard limit
  300 (was hard 200). Prevents unnecessary article splits on dense research.
- **Research agent date anchoring** — web searches use current year, not
  training-era years.

### Fixed
- **Spec authoring mandatory for all WD types** — agent was skipping spec
  authoring for decisions-only WDs. Specs capture the behavioral implications
  of ADRs; without them, hardening and audit have nothing to falsify.

---

## [0.13.3] — 2026-04-13

### Added
- `/work-plan` command — specification-only pipeline for work definitions.
  Runs domain analysis and spec authoring without implementation stages.
- `/decisions roadmap` "Create work group" option (Step 9) — translates
  roadmap clusters into `.work/` work definitions with artifact dependencies
  for parallel execution across terminal sessions.

### Changed
- `/work-start` simplified to implementation-only pipeline. Mode
  auto-detection removed; always hands off to `/feature-plan`. BLOCKED WDs
  now offer "Run /work-plan first" option.
- Cross-references updated across 8 skill files for `/work-plan` awareness.

---

## [0.13.2] — 2026-04-12

### Added

- **Standards compliance probe** — spec falsification checks every RFC/standard compliance claim against all other requirements for contradictions. Deviations must be explicit numbered requirements, not hidden behind "stricter than X." Root cause: F15 claimed RFC 8259 compliance but also rejected blank keys, which RFC 8259 allows.

---

## [0.13.1] — 2026-04-12

### Added

- **Spec falsification lenses** — 6 mandatory probe checklists in Pass 2a, derived from 51 real audit findings across 7 jlsm features:
  - **Degenerate values** — NaN, infinity, negative zero, boundary overflow, empty/null for every typed requirement
  - **Boundary validation** — unconditional validation, entry point enumeration, mutable input after validation
  - **Resource lifecycle** — derived objects after close, partial construction failure, close failure, double-close
  - **Cross-construct atomicity** — partial failure between multi-construct operations, rollback, observer visibility
  - **Error propagation** — post-error state, mid-stream output, shared resource state after exceptions
  - **Identity/equality** — equality semantics for types in comparison, lookup, dedup, caching
  - **Trust boundaries** — predicate sub-states, implicit trust between constructs
- **Mandatory concurrency contracts** — every construct in a spec must declare its thread-safety model. "Not thread-safe" is a requirement, not an omission. Pass 1 Step 1e drafts contracts, Pass 2a verifies completeness.
- **KB adversarial findings in spec falsification** — Pass 2 loads `type: adversarial-finding` KB entries for the feature's domains, providing proven attack vectors from prior audits
- **Concurrency contracts flow through full pipeline** — spec declarations inform feature-test (Lens B), feature-harden (concurrency lens), audit cards (thread_sharing), and aTDD breaker (concurrent attack generation). "Not thread-safe" prevents false positive concurrency findings everywhere.

### Fixed

- **Assembly subagent** — reads input files once instead of repeatedly (was reading analysis-cards.yaml 4 times, ~150K wasted tokens per run)

### Changed

- `/release` Step 7b now deletes old GitHub releases instead of converting to draft. Git tags are always preserved.

---

## [0.13.0] — 2026-04-12

### Added

- **Work layer (`.work/`)** — fourth knowledge layer for composable multi-feature work. Decompose large goals into work definitions with artifact-based dependencies and computed readiness. Same pull-model pattern as KB, decisions, and specs.
- **`/work "<goal>"`** — create a work group with scoping interview
- **`/work-decompose "<slug>"`** — break a work group into work definitions with dependency graph and shared interface contracts
- **`/work-status "<slug>"` / `--all`** — readiness report: what is READY, BLOCKED, IN_PROGRESS, or COMPLETE
- **`/work-start "<slug>" [WD-nn | next]`** — start implementing a ready work definition, bridging into the feature pipeline
- **Interface contracts** — specs with `kind: interface-contract` for shared surfaces between work definitions. Reuses all existing spec tooling.
- **Pipeline modes** — `specification` (produce artifacts only), `implementation` (consume existing specs, skip scoping/domains), `full` (default, backwards compatible). Mode-aware routing in feature-resume.
- **Work-aware context injection** — architect (forward compatibility, ordering gates), spec-author (downstream consumers), feature-domains (cross-WD domain reuse), feature-plan (interface stability constraints), feature-resume (work group grouping)
- **Curate analyses 15-17** — cross-WD spec displacement, stalled work groups, artifact dependency drift
- **Post-fix tendency check** — Step 2.8 in feature-implement queries KB for adversarial-finding entries after each construct passes tests, scanning for known anti-patterns before moving on

### Fixed

- **Prose prompts → AskUserQuestion** — replaced all 50 instances of prose-based interactive prompts ("Type 1 or 2", "Want me to X?", "yes / skip") with AskUserQuestion across architect, curate, decisions, feature-quick, feature-refactor, feature-pr, feature-domains. Prose prompts do not force Claude to stop — only AskUserQuestion does.
- **Architect evaluation guard** — candidate scoring (Step 4b) and falsification (Step 6) now display "analysis in progress — decision is at Step 7" to prevent users from choosing before falsification can revise candidates
- **Narrative generation required** — narrative-wrapper.sh reports failures instead of silently exiting. Retry after 2s for JSONL mid-flush. generate.py/generate.js exit 1 on failure (was always 0). feature-retro Step 6 reports failures with retry command. feature-complete Step 1b attempts generation before archival.
- **MANIFEST sync** — 9 stale audit prompt paths removed, 16 actual files added. install.sh now copies all .md files from skill dirs, all file types from prompts/audit/, installs audit-budget.sh
- **`__pycache__/`** added to target project .gitignore (narrative scripts generate Python bytecache)
- **Status line truncation** — feature slugs capped at 24 chars, construct names at 20 chars to keep stage/tokens/context visible on narrow terminals
- **Session-end prevention** — rule in tdd-protocol.md prevents Claude from suggesting "productive session" stops mid-pipeline. Only AskUserQuestion handoff points offer stopping.
- **curate-scan.sh** — 3 `grep -c` pipefail bugs producing "0\n0" instead of clean integers

### Removed

- Stale `skills/audit/SKILL.md.bak` backup file

---

## [0.12.0] — 2026-04-09

### Added
- **Facet-based research** — `/research "<subject>"` replaces the old
  `/research <topic> <category> "<subject>"` signature. The agent now
  researches first, identifies independent facets for cross-cutting subjects,
  suggests topic/category placement, and the user confirms before anything is
  written. Eliminates placement bias from commissioning context.
- **BM25 KB search** — new `kb-search.sh` script (Python + Node.js + bash
  fallback) provides ranked search over `.kb/` entries. Two-phase ranking:
  coarse over category indexes, enriched with subject frontmatter field weights
  (title/aliases 3x, tags 2x, summary 1.5x). Used by `/research` pre-scan,
  `/kb` query Step 1b, and available to `/curate` for relationship discovery.
- **Cross-linking at write time** — research sessions automatically cross-link
  new articles to each other and update existing entries' `related:` fields.
- **Context hints for callers** — all pipeline callers (`/feature-domains`,
  `/architect`, `/feature-retro`, `/audit`, etc.) pass optional `context:`
  hints describing their commissioning situation without dictating placement.
- **New test suite** — `scenario-kb-search.sh` (13 tests) covering BM25
  ranking, field weighting, Python/Node parity, and edge cases.

### Changed
- All 13 caller skills updated to new `/research` signature.
- `/kb` query Step 1b now uses `kb-search.sh` for mechanical ranking instead
  of LLM-driven keyword scanning (with fallback if script unavailable).
- Research agent identity (`agents/research-agent.md`) and rules
  (`rules/kb-research-agent.md`) updated for facet-first model.

---

## [0.11.0] — 2026-04-09

### Added
- **Spec displacement detection** — `/spec-resolve` detects when new specs
  contradict existing APPROVED specs via mechanical subject-token + antonym +
  keyword matching. Interactive resolution with four choices: accept
  invalidation, narrow new spec, narrow old spec, or defer.
- **Displacement pipeline integration** — accepted displacements flow as
  removal work units through `/feature-plan`, negative displacement tests in
  `/feature-test`, removal awareness in `/feature-implement`, and artifact
  finalization (INVALIDATED marking with cross-references) in `/feature-retro`.
- **Spec revival support** — `/spec-author` detects INVALIDATED specs in
  matching domains and offers them as reference input for fresh authoring.
  New cross-reference fields: `revives` / `revived_by`.
- **New spec frontmatter fields** — `displaced_by`, `revives`, `revived_by`,
  `displacement_reason` with validation in `spec-validate.sh`.
- **Orphaned spec detection** — `/curate` Analysis 14 finds APPROVED specs
  whose subject tokens no longer appear in any source file.
- **New test suites** — `scenario-spec-validate.sh` (8 tests),
  `scenario-spec-resolve.sh` (11 tests), orphaned spec tests in
  `scenario-curate-scan.sh` (4 new, 47 total).

### Fixed
- **subagent-hook.py/.js** — JSON parse failure now cleans up stale
  `.subagent-state` instead of leaving a permanent ghost indicator.
- **token-stop-hook.py** — `stdin.read()` replaced with chunked drain so
  the fast bail check is reachable without buffering all input.
- **statusline.py/.js/.sh** — context percentage normalized to integer
  display across all three languages.
- **token-stop-hook.py** — PID-scoped temp file prevents concurrent stop
  hook collisions.
- **statusline.js** — removed 3 redundant `existsSync` calls, baseline
  write wrapped in try/catch.
- **statusline.js, token-stop-hook.js, subagent-hook.js** — top-level
  try/catch added to guarantee exit 0.
- **token-stop-hook.js** — cold start line counting uses raw Buffer byte
  scan instead of `readFileSync` + `split`.
- **curate-scan.sh** — `grep -c` pipefail bug producing arithmetic errors
  when specs had zero UNRESOLVED markers.

---

## [0.10.0] — 2026-04-08

### Added
- `/feature-harden` — adversarial test hardening phase between test writing
  and implementation. Applies domain lenses (lifecycle, concurrency, boundaries,
  transformation, shared state, routing) to contracts pre-implementation.
  Surfaces spec gaps via [ABSENT] mechanism. Auto-selects skip/lite/full.
- Pre-prove quality gates for `/audit`: `dedup-findings.py` reorders
  dispatch queue for Phase 0 cascade; `check-test-coverage.py` matches
  findings against existing adversarial tests.
- `aggregate-results.py` pre-aggregates prove-fix outputs for report
  subagent (87% cost reduction: 98→20 turns, $44→$5.65).

### Changed
- `/feature-test` chains through `/feature-harden` before `/feature-implement`.
- `/feature-implement` reads `test-plan.md` for intent instead of individual
  test files; writes `implement-summary.md` as handoff for refactor;
  pre-checks `status.md` on resume to skip completed constructs.
- `/feature-refactor` reads `implement-summary.md` for delta awareness.
- `/feature-resume` recognizes hardening stage.
- Exploration prior-round integration hardened: unchanged CLEARED/FIXED
  constructs go to Ignore tier; DEFERRED/Frontier get highest priority.
- Audit report prompt consumes pre-aggregated summaries.

---

## [0.9.0] — 2026-04-07

### Added
- **Capability topology** — hierarchical domain → capability model replacing
  flat entries. Three capability types (core, emergent, refinement) and
  many-to-many feature mapping with roles (core, extends, quality, enables).
  Emergent capabilities capture cross-cutting behaviors from feature composition.
- **`/capabilities` command** — query, list, add, update, and backfill project
  capabilities organized by domain. Domain-aware navigation and search.
- **`/decisions roadmap`** — cluster, classify, and prioritize deferred
  decisions into an actionable roadmap with dependency analysis.
- **Budget-aware audit pipeline** — dollar cap on prove-fix loop with
  proportional allocation across findings. Remaining findings marked DEFERRED.
  Resume filters already-processed findings.
- **Phase 0 already-fixed check** — mandatory pre-flight in prove-fix subagent
  reads current source before test writing. Short-circuits cascade impossibles
  in ~2 turns instead of ~35. Validated: 31 ALREADY_FIXED in engine-clustering.
- **Orchestrator context optimization** — extract-findings.sh + reconciliation
  return format reduces context growth by ~19K tokens per audit.
- **HTML narrative renderer** — audit visualization pipeline with dashboard-style
  static views, session replay, cost/bug metrics, and severity breakdowns.
- **Curate audit feedback** — /curate picks up deferred spec updates and KB
  patterns from audit feedback loop.

### Changed
- **AskUserQuestion standardization** — all 28 interactive prompts across 11
  files converted from text menus to AskUserQuestion tool calls.
- **Architect adversarial hardening** — 6 changes from aTDD research: scope
  verification, constraint falsification, inline score falsification,
  prior-scores-not-evidence, REQUIRED annotations, write-and-justify checklist.
- **Curate cross-reference repair** — Analysis 11 in curate-scan.sh detects
  KB tag overlap, applies_to overlap, and ADR eval→KB source gaps.

### Fixed
- Feedback loop uses AskUserQuestion for forced pause instead of text "STOP"
- Resume skips already-processed findings instead of re-running all
- Resume prompt shows remaining findings count, not total
- Budget prompt uses AskUserQuestion instead of "press Enter"
- Feedback loop menus display sequentially, not simultaneously
- Phase breakdown rows link to stage sections for navigation
- Aggregate phase breakdown by stage type, not per-phase rows
- Cost/bug and total cost visible in audit hero + impact summary

---

## [0.8.0] — 2026-04-03

### Added
- **Combined prove-fix pipeline** — merged Prove + Fix stages into single
  per-finding subagent. Serial dispatch with fix cascade deduplication,
  budget control, and resume support. Validated on 3 jlsm features: $7-11/bug
  for detection + regression test + source fix.
- **`/spec` command** — unified spec query, gap discovery, and change impact
  analysis. Natural language input, discovers matching requirements across all
  specs, traces downstream impact of proposed changes.
- **`/audit` command** — renamed from `/feature-audit`. Adversarial audit
  pipeline with prove-fix model, test cleanup phase, spec conflict detection.
- **Spec extraction mode** — bottom-up spec authoring from existing
  implementation. Auto-discovers source files, consuming specs, and tests.
  Cross-references for CONTRADICTED, UNGUARANTEED, MISSING findings.
- **Spec conflict detection pipeline** — spec-resolve checks contradictions
  between included specs. feature-plan blocks on conflicts, feature-test
  marks UNTESTABLE, feature-implement diagnoses spec conflicts in test failures.
- **[ABSENT] requirement lifecycle** — extraction mode surfaces behaviors code
  doesn't have. Promote (becomes implementation work), preserve (becomes
  negative requirement), or defer (/curate resurfaces later).
- **Fix-spec conflict resolution** — audit report detects when fixes contradict
  spec requirements. Three options: keep fix + update spec, revert fix, defer.
- **Ambiguous spec detection** — spec-author Pass 2c catches "either/or"
  requirements. Job 3b detects contradictory test interpretations of same
  requirement.
- **Test cleanup phase (Job 3b)** — updates stale pre-existing tests after
  audit fixes, classifies failures as STALE, SPEC AMBIGUITY, or REGRESSION.
- **Curate spec awareness** — 4 new signal types: unspecified shared types,
  open obligations, spec-code drift, undecided [ABSENT] requirements.
- **Multi-language parity** — bash + Node.js implementations of reconcile-cards
  and extract-views pipeline scripts, plus wrapper scripts for runtime detection.
- **Architect falsification pass** — mandatory subagent between scoring and
  deliberation that challenges scores, tests rejections, exposes assumptions.
- **KB confidence field** — high/medium/low on research entries, surfaced
  during architect scoring.
- **Audit feedback loop** — reconcile-findings generates spec-updates.md and
  kb-suggestions.md from audit results.

### Changed
- **Spec integration into /feature flow** — routes through spec-author →
  spec-write after domain analysis when .spec/ exists. Backwards compatible.
- **/feature-test** — Lens A operationalizes .spec/ requirements in spec mode,
  falls back to inline analysis. Lens B spec-aware with SPEC-BOUNDARY,
  BLIND-SPOT, IMPL-RISK finding tags.
- **/feature-plan** — loads specs as primary context. Blocks on spec conflicts.
- **/feature-implement** — detects spec conflicts in test failures, escalates
  to spec-author instead of misdiagnosing as test/contract bugs.
- **/feature-refactor** — delegates to /audit instead of removed pass-based
  pipeline prompts.
- **Spec-author Pass 2** — prove/disprove framing requires concrete attacks,
  not bare assertions. Burden of proof on disproof.
- **Concurrency lens** — card construction captures thread_sharing evidence
  (none/possible/explicit). Suspect has mandatory concurrency clearings.
  Domain pruning excludes single-threaded constructs. Validated: 0 false
  positives across 2 audits.
- **DRAFT specs with unresolved conflicts** blocked from resolved context bundles.
- **/vallorcine-help** — all new commands documented, pipeline description
  updated to 9 steps.

### Fixed
- **Prove-fix edit persistence** — mandatory re-read before edits, verification
  after compile, diff in output. Fixes data loss where serial agents overwrote
  earlier agents' changes.
- **Test timeout isolation** — individual method runs to isolate hanging tests.
  Applied to prove-fix, feature-implement, feature-test.
- **API error retry** — prove-fix orchestrator retries once on 500/timeout,
  then marks DEFERRED and continues.
- **Script hardening** — ~55 fixes across 27 scripts (bash/Python/Node):
  atomic writes, exit 0 guarantees, pipefail safety, empty array guards,
  'use strict', sorted→max optimization.
- Report.md suspect file glob pattern (parallel-era assumption cleanup).

---

## [0.7.0] — 2026-03-25

### Added
- **Spec analysis pre-pass** — `/feature-test` Step 1c analyzes work-plan contracts
  across two lenses (contract gaps + implementation risk patterns) before writing tests.
  Generates defensive test vectors that prevent bugs from being written rather than
  finding them after implementation. Reads adversarial KB entries from prior features.
- **Adversarial audit loop** — `/feature-refactor` Step 4b runs a post-implementation
  audit pass: re-analyzes implementation code, writes targeted adversarial tests, and
  fixes confirmed bugs with fix-forward scanning. First loop runs automatically;
  additional rounds require user approval for cross-construct bugs.
- **Spec Analyst agent** (`spec-analyst-agent.md`) — both-lens analysis identity for
  the audit pre-pass and post-implementation audit.
- **Breaker agent** (`breaker-agent.md`) — adversarial test writing identity.
- **KB adversarial-finding template** — persists bug patterns across features so each
  audit makes the next one smarter.
- **KB feature-footprint template** — condensed feature records for cross-reference
  during domain analysis.
- **aTDD research data** — full methodology, experiment harness, and validation results
  in `aTDD-research/`. Documents why each pipeline change was made.

### Changed
- **Unified pipeline model** — one pipeline with configurable audit depth replaces the
  tier model. `/feature-quick` = 0 audit loops, `/feature` = 1 loop (default), complex
  features = user-approved additional rounds.
- **Code Writer agent** — fix-forward rule: after fixing a bug, scans all other constructs
  for the same anti-pattern.
- **Refactor agent** — assert-only validation check, silent exception swallowing check,
  known_issues.md awareness for structural invariants.
- **Test Writer agent** — reads adversarial KB entries during defensive vector generation.
- **Domain Scout** — surfaces feature footprints during `/feature-domains`, silently
  passes adversarial findings through to test phase.
- **Feature retro** — graduates adversarial findings and feature footprints to `.kb/`.
- **TDD protocol** — 5-minute Bash timeout on all test execution.
- **Pipeline timeouts** — aligned across `/feature-coordinate`, `/feature-implement`,
  `/feature-test`.
- **README** — updated pipeline diagram showing audit pass and KB feedback loop.
- **`/vallorcine-help`** — updated pipeline descriptions with spec analysis and audit.

### Validation
Validated on 3 jlsm features. Combined pipeline is 3.7x cheaper than original TDD on
the largest feature (encrypt-memory-data: 47 files, 17.7M vs 64.9M tokens) with zero
post-implementation audit bugs. Spec analysis prevents bugs rather than finding them.

---

## [0.6.0] — 2026-03-20

### Design evolution
- **Principle 1 evolved: bash-first, zero required dependencies** — previously "bash
  and markdown only" as a hard constraint. Relaxed to allow enhanced Python and
  JavaScript implementations under strict rules: every feature must have a bash
  fallback, both runtimes must be supported if either is, and detection/degradation
  must be automatic. The core kit remains bash and markdown — enhanced implementations
  are permitted only when bash cannot fully serve the need (platform constraint or
  practical constraint). This change enables shipping the narrative pipeline and
  multi-language hooks as part of the kit rather than requiring external tools.

### Added
- **Narrative pipeline in `/feature-retro`** — 3-stage pipeline (tokenizer → parser
  → renderer) generates polished `narrative.md` with shields.io badges, Mermaid gantt,
  progressive disclosure, and phase-by-phase breakdowns. Full Python + JavaScript
  parity with graceful degradation. 16 scenario tests.
- **ADR out-of-scope extraction** — `curate-scan.sh` Analysis 9 extracts "What This
  Decision Does NOT Solve" items from confirmed ADRs. `/curate` presents findings and
  offers to create deferred stubs. `/architect` Step 6c auto-creates deferred stubs
  going forward. 8 new tests (41/41 passing).
- **Architect iterative research** — Step 4c commissions targeted follow-up research
  when initial candidates don't adequately cover constraint dimensions. Up to 3
  research iterations total.
- **Architect composite candidates** — Step 4b2 identifies when combining two
  candidates would satisfy constraints better than either alone.
- **`/decisions revisit`** — replaces `/decisions review`. Accepts topic/description
  search, conversational "why" step, revision condition checking against current
  codebase, and `/feature` kickoff after revision.
- **Enhanced status line + token tracking** — Python and Node.js implementations
  alongside bash. Runtime detection wrappers. Subagent visibility via SDK hooks.
- **Mandatory documentation review in `/release`** — Step 1.5 checks README, EXAMPLES,
  DESIGN, and CONTEXT against changes before drafting release notes.

### Changed
- **`/setup-vallorcine`** absorbs `/feature-init` — single bootstrap command
  initializes KB, decisions, feature pipeline, project profile, and .gitignore.
- **Architect neutral presentation** — non-negotiable rule: never express a preference
  or declare a winner before Step 6a deliberation.
- **Disabled auto code review workflow** — `claude-code-review.yml` switched to
  manual trigger only.

### Fixed
- Crash-safe history archive — write before remove in decisions archival
- Trailing phases from other features bleeding through after retro/complete
- Crashed subagent idle time double-counting prior user wait gap
- Subagent idle tracking collisions (now keyed by tool_use_id)
- Mermaid gantt overflow for features >24h
- Corrupt `.meta.json` files crashing session tokenization
- Shields.io badges breaking on hyphenated model names
- 33 parser/tokenizer bugs documented and fixed

### Removed
- `/feature-init` — consolidated into `/setup-vallorcine`
- `/decisions review` — consolidated into `/decisions revisit`
- `tools/showcase/` — retired old pipeline; replaced by `scripts/narrative/`

---

## [0.5.3] — 2026-03-18

### Fixed

- **Token tracking** — stop hook now logs the final stage's tokens before
  cleaning up on terminal states (pr/created). Previously, refactor and
  sometimes implementation showed "—" in the token summary.
- **Statusline log pollution** — statusline no longer writes 4-column
  context-token rows to token-log.md. Token logging is now exclusively
  handled by the stop hook (transcript-based, more accurate).
- **Terminal double-logging guard** — hook firing twice after reaching
  terminal state no longer creates duplicate entries.

### Added

- **Claude Code GitHub Actions** — `@claude` mention support in issues
  and PR comments, plus automated code review on every PR.
- **GitHub issue templates** — structured bug report and feature request
  forms mapped to vallorcine's five concerns.
- **14 token tracking regression tests** — stage transitions, terminal
  handling, statusline isolation, cold start, and log format consistency.

### Changed

- **COMPETITIVE.md** — full rewrite with three-tier framing, 15+
  competitors profiled, head-to-head comparison table, and confirmed
  gaps analysis.
- **Plugin metadata** — author updated to Telefrek, added repository
  and homepage fields.
- **README** — added self-hosted marketplace install option.

---

## [0.5.2] — 2026-03-18

### Fixed
- **Token actuals in status.md** — stop hook now updates the Actual Tokens column
  in the Stage Completion table on stage transitions. Previously always showed "—".
- **Feature finalization moved to `/feature-pr`** — archive manifest, `.feature/CLAUDE.md`
  update, and knowledge/decisions file commits now happen before PR creation (Step 5),
  not post-merge in `/feature-complete`. Prevents uncommitted feature artifacts from
  being lost or leaking into the next feature's PR.
- **PR Step 0.5 separates feature vs upgrade changes** — `.decisions/` files
  (CLAUDE.md, history.md) correctly identified as feature-produced. `.claude/` files
  flagged as upgrade artifacts with recommendation to commit separately.

### Changed
- `/feature-complete` stripped to post-merge directory move only. No more data
  operations that could be skipped or forgotten.

---

## [0.5.1] — 2026-03-18

### Added
- **Research signal recognition in scoping** — uncertainty patterns ("I don't know",
  "not sure") captured as Research Commissions in the feature brief. Domain scout
  auto-commissions `/research` for each.
- **ADR Pressure** — `/curate` detects decisions with 2+ constrained files actively
  changing, reports pressure percentage for re-evaluation.
- **ADR Gravity** — `/curate` detects unconstrained files co-changing with
  ADR-constrained files, revealing implicit relationships. High gravity (5+ files)
  flags isolation problems for `/architect` boundary review.
- **Hub Files** — `/curate` flags files co-changing with 3+ ADRs' constrained areas
  as fragility/test-coverage concerns. Test files excluded from gravity signals.
- **Research fetch discipline** — research agent moves on after ~30s on hung fetches,
  3 sources sufficient, no retries in same session.

### Fixed
- `grep -cxF` under `set -e` produced dual output breaking gravity detection in
  curate-scan.sh.

### Changed
- `/decisions backfill` subsumed by `/curate` — analyses 3b-3d + analysis 8 cover
  all backfill signal sources.

---

## [0.5.0] — 2026-03-18

### Added
- `/curate` command — codebase quality review with correlation engine
  - 8 scan analyses: churn, co-change, artifact correlation, orphaned areas,
    KB staleness, ADR revisit, test-source drift, backfill candidates
  - Numbered pick list for conversational triage
  - Loop behavior: always returns to remaining items after each action
  - Incremental scanning (delta from last-scanned SHA)
  - Scale safety: 500-commit cap, 3-month default window
- `index-verify.sh` — self-healing index verification for crash recovery
- Pre-PR commit verification — `/feature-pr` scans for untracked KB/ADR files
- `/upgrade-vallorcine` auto-commit — kit changes committed as standalone `chore:`
  commit, stashes in-flight staged changes
- Runtime file gitignore — installer adds runtime files to user's `.gitignore`
- Script permissions — installer pre-approves vallorcine scripts in `settings.json`
- `files:` and `applies_to:` frontmatter fields on ADR and KB templates
- Construct analysis derives structural tests from stub interfaces
- Coverage checklist added to test writer to reduce refactor escalations
- 36 new tests (24 curate scan + 12 index verify)

### Changed
- Architecture model expanded from four concerns to five (added Curation)
- `/decisions backfill` consolidated into `/curate` as a scan analysis
- Documentation updated: DESIGN.md, README.md, plugin/marketplace descriptions

### Fixed
- Seed files no longer overwritten by FORCE_UPDATE or version mismatch auto-force
- `/feature-complete` now checks for untracked `.kb/` and `.decisions/` files

---

## [0.4.4] — 2026-03-17

### Changed
- Speed mode coordinator uses completion-driven loop instead of batch-wait.
  Units launch as soon as their dependencies resolve — no waiting for unrelated
  units in the same batch to finish. Minimizes wall-clock time on the critical path.
- Balanced mode retains batch-wait behaviour for predictable checkpoints.
- Dependency graph display now shows critical path and max parallelism.
- Architect prompts user on KB coverage gaps before evaluating decisions.

---

## [0.4.3] — 2026-03-17

### Fixed
- Status line now detects stage transitions during chained sub-agent execution
  by reading actual stage from `status.md` instead of relying on Stop hook
- Per-stage token usage logged to `token-log.md` automatically on stage
  transitions, even when stages chain without returning to the user

---

## [0.4.2] — 2026-03-17

### Fixed
- Status line per-stage token tracking now uses context window delta
  (`used_percentage * context_window_size`) instead of `total_input_tokens`
  which barely changed between status line fires
- Added substage display for all pipeline stages (scoping, planning, testing,
  implementation, refactor, PR) — not just refactor

---

## [0.4.1] — 2026-03-17

### Added
- Status line (`scripts/statusline.sh`) — shows feature slug, pipeline stage,
  total tokens, and context window % with color-coded warnings (green/yellow/red)
- Token tracking Stop hook (`scripts/token-stop-hook.sh`) — auto-detects stage
  transitions and logs to `token-log.md` without any skill-level bash calls
- `/uninstall-vallorcine` command + `scripts/uninstall.sh` — manifest-based
  removal with safety guard, `--dry-run` preview, settings/git cleanup, self-delete
- Domain scout KB empty check — offers research/continue/skip-research when KB
  has zero topics, with `skip_all_research` flag to suppress per-domain prompts
- Version display in `/vallorcine-help` headers (reads `.vallorcine-version`)
- Plugin vs shell install path documentation in README with comparison table

### Changed
- Install registers Stop hook + status line in `settings.json` automatically
- Uninstall cleans up token hook and status line from `settings.json`
- Install auto-removes stale `.claude/commands/<name>.md` when matching skill exists

### Removed
- Tmux dashboard (`/dashboard` skill, `dashboard-state.sh`, `dashboard-stop-hook.sh`,
  3 watcher scripts, `watchers/` directory) — retired in favor of status line + hooks
- All dashboard bash blocks from 9 pipeline skill files
- All `token_checkpoint` and `token_summary` bash blocks from 8 skill files
- `commands/` directory — 23 stale pre-migration files deleted from repo
- Dashboard test file (`test-dashboard.sh`, 14 tests)

### Fixed
- Unsafe `source` of state files — values now properly escaped with `printf '%q'`
- Redundant `jq` forks in stop hook (5→1) and statusline (2→1)
- Non-numeric guards on context percentage and token formatting
- Migration cleanup for pre-0.4.0 upgraders (duplicate slash commands)

---

## [0.4.0] — 2026-03-17

### Added
- Tmux dashboard with two panes: pipeline progress and stage detail
- `vallorcine_theme.sh` — shared icon/color palette for dashboard
- `vallorcine_pipeline.sh` — pipeline pane watcher (7 stages, token spend, alerts, progress bar)
- `vallorcine_stage-detail.sh` — stage detail pane watcher (tasks, artifacts, timestamp, interrupt hint)
- `dashboard-state.sh` — 12-function helper library for agents to write dashboard state
- `dashboard-stop-hook.sh` — Stop hook for live token counter during active stages
- `/dashboard` command (launch/off/on) with once-per-session tmux hint
- Dashboard state calls in all 7 pipeline commands (stage start + complete)
- `.claude/dashboard/` gitignore entry in `/feature-init`
- `test-dashboard.sh` — 23 tests for watchers, state helpers, install, and pipeline integration

### Changed
- Migrated all 23 slash commands from `.claude/commands/*.md` to `.claude/skills/<name>/SKILL.md`
- Added YAML frontmatter (description, argument-hint) to all skills
- `install.sh` installs skills instead of commands
- MANIFEST updated to `.claude/skills/` paths
- Upgrade safety guard includes `.claude/skills/*` and `.claude/watchers/*` prefixes
- Old `.claude/commands/*` files cleaned up on upgrade via stale removal
- Watcher files prefixed with `vallorcine_` to avoid namespace collisions
- Reframed project descriptions: "A reliable engineering partner for Claude Code"
- Updated README, DESIGN.md, marketplace.json, plugin.json with new positioning
- Added `/dashboard` to System commands table in README

---

## [0.3.4] — 2026-03-17

### Added
- TodoWrite two-tier progress checklists across all TDD pipeline commands
  (feature-plan, feature-domains, feature-coordinate, feature-test,
  feature-implement, feature-refactor, feature-resume)
- Pipeline-level progress (scoping → PR) visible in every command
- Stage-level granularity: per-test, per-construct, per-domain, per-refactor-check
- `activeForm` for real-time detail on in-progress items
- Parallel mode: coordinator owns TodoWrite, polls per-unit status.md
- `/ideate` Step 1.5: writes WIP.md immediately for crash recovery
- Upgrade safety guard: prefix allowlist for stale file removal
- Regression test for upgrade safety (test 9, 5 assertions)
- Delegate stub creation and work-plan assembly to subagent for context isolation
- Architect auto-resumes paused feature after decision is confirmed

### Changed
- `/feature-pr` now prompts for `/feature-retro` after PR creation (yes/skip)
- `/feature-resume` offers "Type **yes**" prompt for PR drafting and retrospective

### Fixed
- `install.sh` missing `adr-validate.sh` (was in MANIFEST but not installed)
- `/feature-resume` mapped `refactor/complete` to `/feature-complete` instead
  of `/feature-pr` — now correctly routes through PR drafting first

---

## [0.3.3] — 2026-03-16

### Added
- ADR-informed candidate ranking in `/architect` Step 4. When a KB category has
  >8 entries, reads scoring data from related ADRs to prioritize which subject
  files to load. High scorers and new/unranked entries load first. Low scorers
  deprioritized but available on request. Saves 25-40K tokens on large categories.
- ADR staleness signal: when new KB entries exist that a related ADR never
  evaluated, the Architect flags it for potential `/decisions review`. Closes
  the loop between new research and existing decisions.

---

## [0.3.2] — 2026-03-16

### Added
- Cross-topic keyword scan in `/architect`, `/kb query`, and `/feature-domains`.
  KB discovery now searches across all category indexes for tangentially related
  entries, not just top-down navigation. Catches research in unexpected
  topics/categories. ~1-2K token cost.

### Fixed
- `upgrade.sh` — removed python3 dependency for JSON parsing. Uses plain text
  `gh` output and sed/grep for API responses. Principle 1 compliance.
- `research.md` — hardcoded year range (2024/2025) replaced with relative
  `<current_year - 1> OR <current_year>`.

---

## [0.3.1] — 2026-03-16

### Added
- **Principle 1: bash-first, zero required dependencies** — new top-priority
  design principle. No feature may require anything beyond bash and markdown.
  Enhanced Python/JS implementations permitted under strict rules (see DESIGN.md).
- **Refactor step 2h: security review** — holistic security audit after all
  other refactoring. Checks auth, data handling, trust boundaries, dependencies,
  and threat surface delta. HIGH/MEDIUM/LOW severity. Always pauses on findings.
- **ADR contradiction check** (`scripts/adr-validate.sh`) — pre-flight script
  warns when duplicate accepted slugs exist. Added to pipeline pre-flight checks.
- **Backfill file threshold** — `/decisions backfill` requires explicit path on
  projects over `backfill_file_threshold` (default 50, configurable in
  project-config.md).
- `tests/scenario-adr-contradiction.sh` — 10-case regression test for ADR
  contradiction detection.

### Changed
- Design principles renumbered 1-10 by priority with violation consequences
  documented. Structural constraints (1-3) > correctness (4-7) > workflow (8-10).
- Refactor checklist updated from 7 items (2a-2g) to 8 items (2a-2h).
- DEFERRED.md reorganized into active/dropped/done sections.
- COMPETITIVE.md gaps updated — hooks, coverage gating, Context7 dropped
  as principle 1 violations.
- Open questions prioritized into four tiers (do next / do soon / when needed /
  when scale demands).

### Resolved
- Command name collision audit — zero collisions across 22 commands vs 45
  Claude Code built-ins.
- setup-vallorcine / feature-init merge — settled as separate (four-concern
  model boundary).
- install.sh --run-tests — dropped (tests are for plugin development only).
- KB depends-on field — deferred (P2/P3 tension, premature at current scale).

---

## [0.3.0] — 2026-03-16

### Added
- Parallel work unit execution with `/feature-coordinate` batch coordinator
- Execution strategy prompt (cost/balanced/speed) in `/feature-plan`
- Per-unit file isolation (`units/WU-N/`) for parallel subagent safety
- `/decisions backfill` — retroactive decision extraction from archived features and source structure
- `/decisions list` — browse and filter all decisions by status and keyword
- `/decisions explain "<slug>"` — plain-language ADR summary with KB context
- `/decisions candidates` — review decisions discovered from session transcripts
- `/feature-retro` — post-feature retrospective (scope, assumptions, domains, tokens, TDD efficiency)
- `/feature-cleanup` — interactive stale feature directory management
- `/project-context` — team-shared codebase knowledge with 90-day expiry
- `/vallorcine-help` answers plain-text questions about commands
- `install.sh --diff` — preview changes without writing
- Token estimate vs actual tracking in status.md Stage Completion table
- Dependency topology view in `/feature-resume` with batch info
- Refactor agent step 2g — documentation check

### Changed
- Domain Scout auto-invokes `/architect` and `/research` as sub-agents inline
- Domain Scout classification tightened: `resolved` requires actual ADR
- Draft ADRs display as warnings in domain analysis, don't block
- `/feature-resume` auto-invokes `/feature-domains` when scoping complete
- Renamed `/quick` to `/feature-quick` for naming consistency
- README restructured around four-concern model (knowledge, decisions, features, system)
- DESIGN.md updated with four-concern architecture description

### Fixed
- `install.sh` auto-forces update on version mismatch (bootstrapping fix)
- Standardized all prompts to "Type **yes**" pattern
- `/release` push and changelog prompts use consistent format

---

## [0.2.3] — 2026-03-16

### Added
- `/decisions backfill` — retroactive decision extraction from archived features
  and source structure. Surfaces implicit decisions for decide/draft/defer/dismiss.
  Scoped by path, incremental (default 5 per session), dismissed items don't
  resurface.
- `/vallorcine-help` answers plain-text questions about commands and workflows
  ("how do I resume a feature?") in addition to interactive routing

### Changed
- `/feature-domains` now auto-invokes `/architect` and `/research` as sub-agents
  when gaps are found, instead of deferring to manual user action
- Domain Scout classification tightened: `resolved` requires an actual ADR in
  `.decisions/`, not the scout's own reasoning. Design choices without an existing
  ADR are classified as `pending-decision` and routed to the Architect Agent.
- Draft ADRs (`status: draft`) display as warnings in domain analysis but do not
  block
- `/feature-resume` auto-invokes `/feature-domains` when scoping is complete

### Fixed
- `install.sh` auto-forces update on version mismatch, fixing the bootstrapping
  problem where a broken `upgrade.sh` could never be patched
- `/release` push and GitHub Release prompts use "Type **yes**" pattern
- Standardized remaining "confirm to proceed" prompts in feature-domains

---

## [0.2.2] — 2026-03-16

### Added
- Parallel work unit execution with batch coordinator (`/feature-coordinate`)
- Execution strategy prompt (cost/balanced/speed) in `/feature-plan`
- Per-unit file isolation (`units/WU-N/`) for parallel subagent safety
- Parallel-aware display in `/feature-resume` with batch grouping
- Per-unit change grouping in `/feature-pr` descriptions

### Fixed
- Standardized prompt language to "Type **yes**" across all commands
  (feature-domains, feature-init, kb, quick, research, upgrade-vallorcine)

---

## [0.2.1] — 2026-03-16

### Fixed
- `upgrade.sh`: `gh release` commands failed when `.vallorcine-source` contained
  an SSH URL (`git@github.com:owner/repo.git`). Added normalization to convert
  both SSH and HTTPS URLs to `OWNER/REPO` format before passing to `gh`. Also
  updated `.vallorcine-source` to write HTTPS URLs by default.

---

## [0.2.0] — 2026-03-16

### Added
- **Pre-flight checks** — three advisory scripts run at every pipeline command
  start: version skew warning, index merge driver auto-setup, KB/decisions
  freshness check against main branch
- **Index merge driver** — custom git merge driver for `.kb/CLAUDE.md` and
  `.decisions/CLAUDE.md` that auto-resolves concurrent table row additions by
  keeping all rows from both sides. Scoped via `.gitattributes` to only
  vallorcine-managed index files — never affects user code
- **KB staleness detection** — `/kb "<question>"` checks entry age against
  configurable threshold (default 90 days in project-config.md), warns on stale
  entries, and offers to invoke `/research` as sub-agent inline for gaps or
  outdated data
- **Per-phase token tracking** — `scripts/token-usage.sh` reads Claude Code
  session JSONL to track actual token consumption per pipeline phase. Integrated
  into all 8 pipeline commands and `/feature-resume`
- **Scenario test suite** — 6 scenario tests (53 assertions) covering
  project-config conflicts, version skew detection/resolution/warning, merge
  driver with/without, auto-setup, and stale KB detection. All tests use
  `/tmp/vallorcine/*` paths for permission pre-granting
- **"Known team issues" in DESIGN.md** — documents mitigated and unmitigated
  team concurrency risks
- **COMPETITIVE.md** — 7 new competitors added (claude-mem, memsearch,
  claude-cognitive, Claude Code auto-memory, claude-code-workflows, feature-dev,
  Jamie-BitFlight/claude_skills)
- **DEFERRED.md** — 6 new feature ideas from research brief

### Changed
- `/save-work` no longer bumps VERSION — stages changelog notes in
  `.changelog-staging.md` for `/release` to consume
- `/release` syncs README.md version line
- `install.sh --dev` uses temp dir instead of overwriting repo `.claude/`;
  safety guard blocks `install.sh .` from repo root
- `test-install.sh` updated to use `/tmp/vallorcine/` paths

### Fixed
- `install.sh` self-install safety guard prevents overwriting source files
  when run from the vallorcine repo root

---

## [0.1.5] — 2026-03-14

### Fixed
- `upgrade.sh`: when exec'd with `--apply` by the new script, pre-flight
  checks and the full fetch/download/extract block ran unnecessarily against
  the temp extract directory, causing an immediate exit before any files were
  applied; all args are now parsed upfront and both sections are gated behind
  `APPLY -eq 0`

---

## [0.1.4] — 2026-03-14

### Fixed
- `upgrade.sh`: `compare_versions` returns non-zero exit codes (1 and 2) which
  caused `set -e` to terminate the script before the return code could be
  captured — upgrade check always exited prematurely when a newer version was
  available
- `/release`: removed redundant `↵ confirm` step after version bump; all
  auto-proceed steps (push, GitHub release, CHANGELOG confirm) now proceed
  unless the user types `skip` or `edit`, eliminating Enter-to-confirm prompts
  that don't work in Claude Code's chat interface

---

## [0.1.3] — 2026-03-14

### Fixed
- `/feature-resume` now auto-invokes `/feature-plan` when that is the identified next step
- Autonomous mode opt-in moved to `/feature-plan` (before testing begins, not after)
- Crash recovery in autonomous mode auto-resumes without requiring a manual command
- "Hit enter to continue" prompts replaced with explicit "continue" keyword throughout
- `/feature-pr` now creates the PR via `gh pr create` directly, not just a draft file
- `/feature-init` prompts for a feature branch and applies project naming rules

### Added
- Handoff points offer to invoke the next command automatically as a sub-agent
- `DEFERRED.md` for vallorcine local development (pull-model, not loaded every session)
- `MANIFEST` file listing all kit-managed files
- `install.sh` and `upgrade.sh` remove stale files no longer in the kit MANIFEST
- Fail-forward upgrade policy documented in `upgrade.sh` summary output

---

## [0.1.2] — 2026-03-13

- Split CONTEXT.md into three bounded files with version sync
- Add tail-read rule for cycle-log.md to cap token cost
- Add escalation re-entry logic and WIP checkpoint system

---

## [0.1.1] — 2026-03-13

### Changed
- Split CONTEXT.md into three files: CONTEXT.md (active state, bounded),
  SETTLED.md (graduated design history), COMPETITIVE.md (market positioning)
- `/save-work` now graduates aged decisions to SETTLED.md and syncs DESIGN.md/README.md
- `/ideate` skips reference files unless the session goal requires them

---

## [0.1.0] — 2026-03-13

Initial release. Two subsystems: TDD Pipeline and KB/Decisions.

### Added

**TDD Pipeline**
- `/vallorcine-help` — guided entry point, routes to /feature-quick or /feature
- `/feature` — scoping agent with sequential one-question-at-a-time interview
- `/feature-init` — project profile setup with inference from existing project files
- `/feature-domains` — domain scout, commissions research and architect runs
- `/feature-plan` — work planner with token-based work unit split analysis
- `/feature-test` — test writer agent, TDD cycle management
- `/feature-implement` — code writer agent
- `/feature-refactor` — refactor agent with 8-category checklist (2a-2h)
- `/feature-pr` — PR draft generator
- `/feature-complete` — archive and cleanup
- `/feature-resume` — crash recovery from status.md checkpoint
- `/feature-resume --status` — pipeline status display with --share mode
- `/feature-quick` — lightweight single-construct path with complexity assessment
- Escalation chain: Code Writer → Test Writer → Work Planner with 3-strike limits and re-entry logic
- `cycle-log.md` tail-read rule — agents read last 30 lines by default, capping token cost

**KB/Decisions**
- `/research` — Research Agent, writes to `.kb/`
- `/kb topic` — creates new KB topics, maintains .kb/CLAUDE.md Topic Map
- `/kb lookup` — retrieves KB entries on demand
- `/setup-vallorcine` — initialises .kb/ and .decisions/ directories
- `/architect` — Architect Agent with 6-constraint deliberation loop
- `/decisions review` — revisits existing architecture decisions

**Infrastructure**
- Work unit splitting with token-based thresholds (15K crossover)
- `--unit WU-N` flag on inner-loop commands
- Enter-to-proceed prompts throughout (no yes/no required)
- `prompt-conventions.md` always-loaded rules file
- `DESIGN.md` — 9 design principles, structural patterns, token budget
- `CONTEXT.md` — active session context (bounded ~150-200 lines)
- `SETTLED.md` — graduated design history (pull-model reference)
- `COMPETITIVE.md` — market positioning and ecosystem gaps (pull-model reference)
- `RESUME.md` — session start/close instructions
- `install.sh` — idempotent installer, skip-existing, FORCE_UPDATE=1 to overwrite
- `VERSION` file with semver
- `.claude-plugin/plugin.json` — plugin manifest for `/plugin install` native path
- `.claude-plugin/marketplace.json` — single-plugin marketplace for `/plugin marketplace add`
- `/upgrade-vallorcine` — checks source repository for new release tags, shows release notes, downloads and applies with confirmation. Never touches user-generated files.
- `upgrade.sh` — shell script installed into `.claude/upgrade.sh` in target projects. Downloads release zip via gh CLI or curl fallback, applies kit files only, preserves user content.
