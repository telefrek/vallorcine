# vallorcine — Deferred Ideas

Good thoughts not being worked on now. Captured here to avoid losing them,
but not blocking current work. Not settled — these may be revisited, dropped,
or promoted to open questions at any time.

**Updated by:** `/save-work` — appends new deferrals, never auto-removes them.
**Read by:** `/ideate` on request only — pull-model, not loaded every session.
**Review cadence:** Check periodically; promote items to Open questions in
CONTEXT.md when you're ready to act on them, or drop them if no longer relevant.

---

## Active deferrals

- **Spec model v2 — retirement of displacement machinery** (2026-04-21) —
  replace `invalidates` / `displaced_by` / `amends` / `revives` /
  `revived_by` / `displacement_reason` with requirement-level `because_of`
  refs (forward provenance + reverse-scan for impact). Domain-era
  reframing: domains are orthogonal and stable; change is add/subtract
  requirements in place; Claude maintains all spec files. Strategy:
  design-first, jlsm pilot (75 specs / 12 domains), kit last. Estimated
  3-5 sessions. See `project_spec_model_redesign.md` memory. Subsumes
  Items 3+5 (one-sided displaced_by bug) from the post-v0.14.0 priority
  stack — those become moot once the machinery retires.

- **LSP integration** — document in README which LSP plugins pair well with
  vallorcine's Code Writer stage as a recommended companion. No bundled dependency.

- ~~**/feature-split**~~ — **subsumed by work layer** (2026-04-11). `/work-decompose`
  handles scope decomposition at the work group level.

- **KB coding agent** — third KB role that reads entries and implements against
  them. Would close the loop between research and implementation.

- **KB staleness: `depends-on` field** — frontmatter `depends-on` field in
  subject files for cross-entry dependency tracking. Staleness detection by
  date is now built into `/kb` query (checks `last_researched` and `Last Updated`
  against configurable threshold in project-config). The `depends-on` field
  would add structural staleness: "entry X changed, so entry Y needs review."

- **Team KB commands** — `/kb sync` (post-merge integrity check), `/kb
  consolidate` (merge overlapping entries), `/kb status` (human-readable
  summary), `/decisions revisit` (review contested ADRs). The git merge driver
  for concurrent index writes is already built — these commands would extend
  the team support further.

- **HANDOFF.md for cross-developer session handoff** — `/save-work` writes a
  structured summary of decisions made, approaches tried, and open questions.
  Useful for team handoffs and solo resume after long gaps. Documentation/convention
  for now — can't be enforced by tooling.

- **ADR contradiction check** — scan `.decisions/CLAUDE.md` for duplicate
  question slugs with `accepted` status. Originally spec'd as CI/GitHub Actions.
  Redesigned (2026-03-16): bash script (`scripts/adr-validate.sh`) to stay within
  principle 1. Can run as pre-flight check alongside version-check.sh.

- **Curate backfill: distinguish "deferred" from "not needed"** — the backfill
  logic currently trusts domain analysis labels like "no ADR needed" at face
  value. But "user deferred to work planner" is a different signal from "no
  alternative was considered." Deferred decisions that resulted in API designs
  or interfaces other code depends on should still surface as backfill
  candidates. Found via JLSM dogfood: VectorIndex Precision API was dismissed
  because the domain analysis labelled it as deferred, but the pragmatic
  decision created a public API surface worth documenting.

- **Subagent UI staleness (partial)** — two user-visible feedback mechanisms
  go stale during delegated work unit execution:
  1. **TodoWrite** — task lists created inside subagents don't bubble up to
     the parent's task list. Progress checklists are invisible to the user.
     Still a Claude Code platform limitation.
  2. ~~**Status line**~~ — **addressed** (v0.5.4). SubagentStart/SubagentStop
     hooks now write `.claude/.subagent-state`; the status line reads it to
     show which subagent is active. Enhanced implementations (Python/Node.js)
     provide native JSON parsing with bash fallback.

- **Vallorcine version tracking for showcase** — showcase articles should display
  which vallorcine version was used. JSONL logs capture the Claude Code CLI version
  but not vallorcine's. Need to write a version stamp during sessions (e.g., to
  status.md, a `.vallorcine-version` file, or a dedicated JSONL entry) so the
  tokenizer can extract it.

- **ADR out-of-scope extraction** — accepted ADRs contain "out of scope" and
  "future work" sections that document deferred work, but these items are
  invisible to `/decisions triage` because the ADR itself is in `accepted`
  status. Two parts: (1) a `/decisions backfill` or `/curate` enhancement that
  scans accepted ADRs for out-of-scope sections and surfaces them as triage
  candidates, covering repositories that already have ADRs with embedded
  deferrals; (2) update the Architect Agent flow so that when an ADR lists
  out-of-scope items, each one gets a separate `deferred` decision record
  created automatically — ensuring future `/decisions triage` picks them up.
  Found via JLSM dogfood: 12 of 13 ADRs had 45+ deferred items that
  `/decisions triage` couldn't see.

- ~~Consolidate /feature-init and /setup-vallorcine~~ — **done**. `/setup-vallorcine`
  now handles everything: KB, decisions, feature pipeline, project profile, and
  .gitignore. `/feature-init` removed.

- **Security-aware analysis lens** — add a security domain lens to the audit
  pipeline, scoped to code handling keys, credentials, PII, or sensitive data.
  NOT a full security audit — targeted checks within the existing prove-fix
  model. Examples: key material not zeroed after use, IV/nonce reuse potential,
  plaintext leaking into logs/exceptions, non-constant-time secret comparison,
  credentials in memory longer than necessary. Triggers only when constructs
  handle sensitive data (encryption APIs, credential stores, PII fields).
  Evidence: encryption audit found 10 critical key-lifecycle bugs through
  generic resource_lifecycle lens, but missed timing channels, IV reuse, and
  ciphertext integrity — bugs that require adversary-model reasoning. The
  security lens would ask "what can an attacker extract?" not just "is this
  resource cleaned up?" Verification model: same prove-fix for testable
  findings (key not zeroed = testable), advisory output for untestable ones
  (timing channel = needs manual review). Promote to Open questions when
  ready to design the lens prompt and advisory output format.

- ~~`/decisions roadmap`~~ — **done** (v0.13.3). Bulk planning pass with clustering,
  effort classification, dependency analysis. Now includes "Create work group" option
  that translates roadmap clusters into `.work/` WDs for parallel execution via
  `/work-plan` (specification) and `/work-start` (implementation).

- **`/project-context` evolution — "what should I work on next?"** — broader version
  of `/decisions roadmap` that synthesizes across all project signals (deferred
  decisions, deferred audit findings, spec-code drift, KB staleness, open obligations,
  git churn, recently completed features) to recommend the highest-value next work
  unit. Routes to the appropriate skill per item type. `/decisions roadmap` has
  validated the planning-only approach — this can be promoted when ready.

- **Lightweight post-TDD audit** — after refactor completes, before PR, run a
  scoped suspect + prove-fix pass on the feature's constructs. Skip the
  expensive discovery phases (classification, exploration, card construction)
  — use the work plan as the construct graph and test-plan.md as the coverage
  map. Focus only on cross-construct boundary analysis: shared state mutations,
  resource lifecycle across owners, interface inconsistencies. These are the
  bugs individual construct tests can't see. Estimated: 3-4 suspect clusters,
  ~10 minutes, ~$20-30 per feature. Could be a mode on `/audit` or a step in
  the refactor phase. Wait for json-only-simd-jsonl audit results before
  designing — need to know what the full audit finds that TDD missed to scope
  the lightweight version correctly.

- **Distributed work layer — multi-party decomposition and merge** — when multiple
  people run `/work-decompose` on the same work group from different branches,
  the merged result must be coherent. Five data model changes:
  (1) **Slug-based WD IDs** — derive from title (e.g., `wd-jwt-validation`)
  instead of sequential `WD-01`. Eliminates ID collisions on parallel branches.
  (2) **Regenerable indexes** — `work-rebuild-index.sh` regenerates `manifest.md`
  and `.work/CLAUDE.md` from WD files. Index conflicts become "re-run the script."
  (3) **Additive decomposition** — `/work-decompose` appends WDs to existing set
  rather than replacing. Two independent decompositions produce a union.
  (4) **Overlap detection in `/work-decompose`** — when existing WDs are present,
  compare `produces` lists before writing. Surface overlaps interactively: keep
  existing, replace with new, or merge scope. Resolves conflicts at authoring time
  when the person has full context.
  (5) **Post-merge validation** — `work-validate.sh --merged` catches the parallel-
  branch case: `produces` overlap (two WDs claim same artifact), unresolved deps
  (naming mismatch across branches), redundant WDs (similar scope). Triggers
  the same resolution tool as (4).
  Two merge paths: sequential (B pulls A's work, decomposes additively, resolves
  inline) and parallel (both branch from same commit, git merge succeeds due to
  slug IDs + regenerable indexes, post-merge validation catches semantic issues).
  The irreducible problem — different artifact naming for the same concept — requires
  human judgment in both paths. Tooling surfaces it; humans resolve it.
  Promote when ready for team/multi-developer workflows.

- **Pipeline observability** — velocity metrics (time/tokens per stage across
  features), KB utilization (which entries get read), pipeline trends. Token
  tracking exists but is narrow. Premature until more projects use vallorcine.

- **KB cross-referencing** — reverse mapping from decisions to KB entries. One-way
  (KB → decisions) exists in `/kb query`. Low urgency until KB is large enough.

- **Internal research KB for vallorcine development** — ~~structure and capture
  mechanism~~ **done** (2026-03-26): `.claude/research/` directory + /save-work
  Step 3.5 learnings capture. Remaining: bootstrap by scanning recent session
  history for key learnings from the aTDD research sessions.

- ~~`/decisions backfill`~~ — **subsumed by `/curate`** (2026-03-18). Curation's
  analysis 8 (backfill candidates) + analysis 3b-3d (ADR pressure/gravity/hubs)
  cover all five signal sources. Archived feature domains (source 1) are scanned
  directly. Module boundaries, interface hierarchies, encoding choices, and
  dependency edges (sources 2-5) are detected via ADR gravity — files that
  co-change with ADR-constrained files but aren't in the ADR's scope. High
  gravity signals isolation problems that route to `/architect`.

---

## Dropped

- ~~Hooks for non-TDD tooling~~ — **dropped** (2026-03-16). Requires Claude Code
  hooks infrastructure — violates principle 1 (bash-first, zero required dependencies).
- ~~Context7 / live docs in Domain Scout~~ — **dropped** (2026-03-16). Requires
  MCP server — violates principle 1 (bash-first, zero required dependencies).
- ~~Coverage gating in refactor~~ — **dropped** (2026-03-16). Requires
  language-specific coverage tools — violates principle 1. Step 2e (missing test
  detection) is the language-agnostic proxy.

## Done

- ~~/decisions list~~ — **done** (v0.2.4)
- ~~Project-level CONTEXT.md~~ — **done** (v0.2.4)
- ~~Diff-based install~~ — **done** (v0.2.4)
- ~~Auto-capture of accidental decisions~~ — **done** (v0.2.4)
- ~~Feature retrospectives~~ — **done** (v0.2.4)
- ~~Dependency-aware work splitting~~ — **done** (v0.2.4)
- ~~/decisions explain~~ — **done** (v0.2.4)
- ~~/feature-cleanup~~ — **done** (v0.2.4)
