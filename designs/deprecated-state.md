# DEPRECATED spec state — pre-release deprecation discipline

**Status:** proposed (revision 2) — 2026-05-17
**Originating signal:** jlsm session proposed a pre-release format-deprecation
discipline that introduces a `DEPRECATED` state between `APPROVED` and
`INVALIDATED`. Most of the proposal is jlsm-specific (Java annotations,
storage-format KB paths), but the **state machine + validator + resolver +
audit-trail contract** are reusable across any pre-release project.

This design scopes the vallorcine-kit-level support. Language and
domain specifics stay in `.feature/project-config.md` so other languages
(Rust, Python, Go, TS) and other artifact types (algorithms, protocols)
can plug in.

**Revision 2 changes** (after Nathan's review of revision 1):
1. `removal_scheduled_in` is now a **semver version string**, not a
   WD-ID. Removals and WDs aren't strictly related — a version is the
   natural deprecation cycle marker, and SemVer projects already think
   in versions.
2. **No rescind path.** Once a spec is DEPRECATED, it cannot return to
   APPROVED. Deprecation is a one-way ratchet — declaring "alternatives
   exist" is irreversible. If alternatives didn't exist, you shouldn't
   have deprecated.
3. **Reframed DEPRECATED semantics.** Not "scheduled for removal" but
   "still active, but alternatives exist — prefer the alternative."
   This drives a new REQUIRED field: `displaced_by: <spec-id>`. The
   resolver does NOT error when a WD depends on a DEPRECATED spec as
   long as the displacing alternative is APPROVED and covers the domain.

---

## Problem

vallorcine's current spec state machine has three states:

```
DRAFT ──→ APPROVED ──→ INVALIDATED
```

- `DRAFT`: authoring in progress, may have unresolved obligations
- `APPROVED`: behavioral contract is settled and load-bearing
- `INVALIDATED`: contract is no longer in force; preserved for history

This works for released projects using SemVer (deprecate in minor,
remove in major). It breaks down for **pre-release projects** that:

1. Have no released versions yet (or are pre-1.0) — but still track a
   working VERSION file
2. Need to retire code/contracts as the design evolves
3. Need an audit trail for what was removed and why

The current options for pre-release deprecation:

- **APPROVED → INVALIDATED in one step.** Loses the "alternative exists,
  prefer it" signal. Code keeps running until it's deleted; nothing
  surfaces the intent.
- **APPROVED with prose annotations.** No structural signal. Resolver
  can't differentiate; validator can't enforce displacing-spec presence;
  tools can't grep for migration candidates.
- **DRAFT used as "scheduled for removal."** Wrong semantics — DRAFT
  means "not yet load-bearing," but a deprecated spec IS load-bearing.

The proposal: a new `DEPRECATED` state meaning **"still active, but
alternatives exist — prefer the alternative."** With required pointer
to the displacing spec and a scheduled removal version.

---

## Goal

Add `DEPRECATED` to the spec state machine. Sits between APPROVED and
INVALIDATED. Specs in DEPRECATED state:

- Satisfy `required_state: APPROVED` dependencies (with resolver
  awareness — no warning when the displacing spec is APPROVED and
  covers the dependent's needs)
- Carry required scheduling metadata (validator-enforced)
- Surface in `/work-status` and during `/curate` scans for awareness
- Trigger audit-trail-before-deletion enforcement when transitioning to
  INVALIDATED

**No rescind path.** Once DEPRECATED, only forward transition (to
INVALIDATED) is allowed.

---

## Non-goals

- **Language-specific code markers.** `@Deprecated(forRemoval=true)`,
  `#[deprecated]`, `warnings.warn`, `// Deprecated:` — these are
  language-layer concerns. The kit prescribes the *contract* (code
  marker MUST cite the spec); `.feature/project-config.md` specifies
  the language convention.
- **Domain-specific archaeology.** jlsm's `.kb/systems/storage-formats/legacy/`
  path is jlsm-specific. The kit prescribes a generic `.kb/_legacy/<slug>.md`
  with required frontmatter; projects can route to subdirectories as needed.
- **Reproducer specifics.** Byte-stream synthesizers, reference
  implementations, protocol replay — the kit requires *some* reproducer;
  the type is project-declared.
- **Rescind / un-deprecate.** Once a spec is DEPRECATED, it stays
  DEPRECATED until INVALIDATED. No backward transitions. Deprecation
  is a one-way ratchet — see "Why no rescind" below.
- **Automatic transitions.** Specs don't auto-DEPRECATE or
  auto-INVALIDATE based on age, version, or any other heuristic. Every
  state change is an explicit user action.
- **Multiple deprecation severity levels.** No SOFT_DEPRECATED vs
  HARD_DEPRECATED. One state with age-aware resolver warning escalation
  handles the same concern with less surface area.

### Why no rescind

Earlier revision had a `DEPRECATED → APPROVED` rescind path for cases
where a migration target slipped. Nathan's feedback: that path
shouldn't exist. DEPRECATED means "alternatives exist." Declaring that
is a downstream-visible commitment — consumers start migrating, code
markers go in, ADRs cite the displacement.

If alternatives turn out to be insufficient, the fix isn't to
un-deprecate the old spec. It's:
- Recognize that the alternative spec has a gap → AMEND the alternative
  spec to cover the gap
- If the gap is fundamental and the alternative was wrong → INVALIDATE
  the alternative and write a NEW spec that subsumes both the old and
  alternative behaviors

The old spec stays DEPRECATED throughout. Its history is preserved
honestly — "we tried to migrate to X, X had a gap, we fixed X" is a
better audit trail than "we un-deprecated Y when X didn't work."

The discipline forces honest scheduling. You only DEPRECATE when the
alternative is real.

---

## Design

### State machine

```
DRAFT ──→ APPROVED ──→ DEPRECATED ──→ INVALIDATED
                              │
                              └──→ (resolves required_state: APPROVED)
                                   resolver checks displaced_by;
                                   may warn or stay silent based on
                                   whether alternative covers the
                                   dependent's domain
```

| State | Meaning | Satisfies `required_state: APPROVED`? |
|---|---|---|
| `DRAFT` | Authoring in progress | No |
| `APPROVED` | Settled and load-bearing, no successor | Yes |
| `DEPRECATED` | Still load-bearing, but alternative exists — prefer alternative | **Yes** (resolver-aware) |
| `INVALIDATED` | No longer in force, preserved for history | No |

**Transitions allowed:**
- `DRAFT → APPROVED` (existing)
- `DRAFT → INVALIDATED` (existing, for never-shipped specs)
- `APPROVED → DEPRECATED` (new)
- `DEPRECATED → INVALIDATED` (new, with audit-trail contract)
- `APPROVED → INVALIDATED` (existing — direct retirement, no displacement)

**Transitions disallowed:**
- `DEPRECATED → APPROVED` (no rescind)
- `DEPRECATED → DRAFT` (no rescind)
- `INVALIDATED → anything` (terminal)

### DEPRECATED frontmatter (validator-enforced)

When `state: "DEPRECATED"`, these fields are REQUIRED:

```yaml
state: "DEPRECATED"
displaced_by: "<spec-id>"          # the spec that supersedes this one.
                                   # MUST exist and be at state APPROVED.
                                   # This is the "alternative" — the
                                   # whole reason DEPRECATED exists.
deprecation_reason: "..."          # one-line rationale. Often "superseded
                                   # by <displaced_by>"; may add context.
removal_scheduled_in: "0.23.0"     # semver version string for the planned
                                   # removal. MUST be > current VERSION.
                                   # NOT tied to a specific WD — removals
                                   # may span multiple WDs or merge across
                                   # versions.
deprecation_date: "2026-05-17"     # ISO date when DEPRECATED state set.
                                   # used for resolver context (e.g.,
                                   # "deprecated 60 days ago") and
                                   # /curate aging displays.
```

The validator (`spec-validate.sh`) refuses a DEPRECATED spec missing
any of these fields.

**Why a version, not a WD-ID** (changed from revision 1):

- Removals and WDs aren't strictly related. A WD might span multiple
  removals; a single removal might span multiple WDs across versions.
- Versions are the natural deprecation cycle marker — SemVer projects
  already think in versions, downstream consumers learn deprecation
  windows in version terms.
- Even pre-release projects track a working VERSION. `0.5.0-dev` is
  valid; `removal_scheduled_in: "0.6.0"` is meaningful even before
  0.6.0 is cut.
- Version-based scheduling is checkable: validator confirms the version
  is well-formed semver, parseable, and strictly greater than current
  VERSION at the time of marking.

**Why `displaced_by` is REQUIRED:**

DEPRECATED means "alternative exists." If there's no alternative, the
spec isn't deprecated — it's just being retired (use APPROVED →
INVALIDATED directly with `displacement_reason` capturing the "no
replacement" rationale). The required `displaced_by` field structurally
prevents misuse of DEPRECATED as a backdoor for state changes without
migration paths.

### Resolver behavior — displacement-aware, three-tier severity

When a WD's `artifact_deps` references a DEPRECATED spec X:

1. Look up the `displaced_by` field on spec X. Let Y be the displacing spec.

2. Determine whether Y *covers* the dependent's needs:
   - Read Y's `applies_to` / `domains` / R-clauses
   - Compare against the dependent WD's stated domain or the artifact
     it depends on
   - **Heuristic:** if Y is APPROVED AND Y has overlapping `domains` or
     `applies_to` patterns with what the WD's artifact_deps is asking
     for, consider Y a covering alternative.

3. Branch on coverage + age + removal version:

**Tier 0 — SILENT (no warning):**
- `displaced_by` is APPROVED AND covers the dependent's needs
- Current VERSION is far below `removal_scheduled_in` (more than 1
  minor version away)
- Pure "use the new thing when you next touch this" case — no urgency

**Tier 1 — ADVISORY:**
- `displaced_by` is APPROVED but the WD genuinely needs the deprecated
  surface (e.g., backward-compat code path, integration glue)
- Current VERSION is approaching `removal_scheduled_in` but not yet at it
- Output:
  ```
  [resolve] WD <wd-id> depends on <spec-id> which is DEPRECATED
            (superseded by <displaced_by>; scheduled for removal in
            <removal_scheduled_in>; current version <VERSION>)
  ```

**Tier 2 — WARNING:**
- Current VERSION is at or one-minor-bump below `removal_scheduled_in`
- OR `displaced_by` is not yet APPROVED (still DRAFT) — alternative
  isn't ready yet, scheduling looks off
- OR `deprecation_date` is more than `deprecation_age_threshold_days`
  (default 90) old AND `displaced_by` has not been touched recently
- Output:
  ```
  [resolve] WARNING: WD <wd-id> depends on <spec-id> which is DEPRECATED
            and approaching removal in <removal_scheduled_in> (current
            <VERSION>). Migrate to <displaced_by> before <removal_scheduled_in>
            is cut.
  ```

**Tier 3 — ERROR:**
- Current VERSION >= `removal_scheduled_in` AND spec is still DEPRECATED
  (overdue — should have been INVALIDATED)
- Output:
  ```
  [resolve] ERROR: WD <wd-id> depends on <spec-id> which is DEPRECATED
            but the scheduled removal version (<removal_scheduled_in>)
            has been reached or passed (current <VERSION>). The marker
            spec is overdue for INVALIDATION — investigate.
  ```

Tier 3 is still SATISFIED (the resolver doesn't block in-flight work),
but the message is severity ERROR rather than ADVISORY, surfacing in
`/work-status` and any `/curate` scan.

**Coverage heuristic notes:**

The "covers the dependent's needs" check is a heuristic, not a
guarantee. The kit's default check uses tag/domain/applies_to overlap.
Projects can override with a stricter check in
`.feature/project-config.md`:

```yaml
displacement_coverage:
  strict: true  # require explicit displaced_by → dependent mapping
                # in the migration metadata, not just tag overlap
```

For v1, default to heuristic (tag/domain overlap). Strict mode is a
future enhancement.

### Audit-trail-before-deletion contract (DEPRECATED → INVALIDATED)

Three artifacts MUST be present before the validator allows DEPRECATED
→ INVALIDATED:

1. **Spec gets `displacement_reason`** when transitioning to INVALIDATED.
   Already supported by vallorcine.

2. **Reproducer reference** in the INVALIDATED spec's frontmatter:

   ```yaml
   reproducer:
     type: "synthesizer"           # synthesizer | reference-impl | protocol-replay | other
     path: "src/test/java/legacy/V5FileSynthesizer.java"
     description: "Produces v5-format byte streams for forensic tests"
   ```

   The kit doesn't prescribe the *type* — it requires that *some*
   reproducer exists and the spec points at it. Project declares
   accepted types in `.feature/project-config.md`:

   ```yaml
   reproducer_types:
     - synthesizer
     - reference-impl
     - protocol-replay
   ```

3. **Archaeological KB article** at `.kb/_legacy/<slug>.md`:

   ```yaml
   ---
   type: legacy-archaeology
   spec_ref: "<spec-id-at-INVALIDATED>"
   removed_in: "<version>"          # the version that landed the removal
   removed_at: "YYYY-MM-DD"
   reproducer: "<reproducer-path>"
   ---

   # Legacy: <human-readable-name>

   ## What it was
   <byte layout / algorithm / protocol description>

   ## Why it existed
   <design rationale at the time>

   ## Why it was removed
   <removal rationale; cite the displacing spec>

   ## How to reproduce
   <how to use the reproducer; what tests still exercise the legacy
   path defensively>
   ```

The validator's INVALIDATION check:

```bash
# spec-validate.sh excerpt
if [[ "$old_state" == "DEPRECATED" && "$new_state" == "INVALIDATED" ]]; then
  # Refuse unless all three artifacts present
  [[ -n "$displacement_reason" ]] || fail "missing displacement_reason"
  [[ -n "$reproducer" ]] || fail "missing reproducer frontmatter"
  [[ -f ".kb/_legacy/${slug}.md" ]] || fail "missing archaeology KB article"
  # Reproducer path must exist (lazy check — file or directory)
  [[ -e "$reproducer_path" ]] || fail "reproducer path does not exist: $reproducer_path"
fi
```

Projects can override `.kb/_legacy/` with a different path in
`.feature/project-config.md`:

```yaml
legacy_kb_path: ".kb/systems/storage-formats/legacy/"
```

### Code-level marker (loose check, project-declared)

The kit-level rule: code carrying behavior governed by a DEPRECATED
spec SHOULD carry a code-level marker that:

1. Cites the marker spec
2. Triggers the strongest available compiler/lint warning the language
   provides
3. Is suppressible at legitimate call sites, with required explanation

Project declares the convention in `.feature/project-config.md`:

```yaml
deprecation_marker:
  java:
    annotation: "@Deprecated(forRemoval = true)"
    doc_format: "javadoc"
    citation_pattern: "See spec {@code <spec-id>}"
    suppress: "@SuppressWarnings(\"deprecation\")"
  rust:
    annotation: "#[deprecated(since = \"<version>\", note = \"<spec-id>\")]"
    suppress: "#[allow(deprecated)]"
  python:
    convention: "warnings.warn(DeprecationWarning(\"<spec-id>\"))"
  go:
    convention: "// Deprecated: <spec-id>; <reason>"
  typescript:
    convention: "@deprecated <spec-id>"
```

The validator's check (loose — can't AST-parse every language):

```bash
# For each file referenced by a DEPRECATED spec's applies_to:
# grep for the language's convention pattern + spec-id citation
# Emit WARNING if no marker found; do NOT block
```

Validator-as-warning is intentional. Some code may be marker-free for
legitimate reasons (helper utilities not directly governed by the
spec). User decides whether to add markers or accept the warning.

---

## Edge cases

**EC1 — `displaced_by` spec doesn't exist.** Validator refuses the
DEPRECATED transition. You cannot deprecate without a real successor.

**EC2 — `displaced_by` spec is DRAFT.** Validator refuses the DEPRECATED
transition — the alternative isn't ready. Wait until `displaced_by`
is APPROVED, then deprecate.

**EC3 — `displaced_by` spec is itself DEPRECATED.** Validator refuses
— chain deprecations create confusion. If the original alternative
was wrong and a third spec is now the path forward, point `displaced_by`
to the third spec directly.

**EC4 — `removal_scheduled_in` is at or below current VERSION.**
Validator refuses at deprecation time — scheduling must be forward.
(Catches typos like `removal_scheduled_in: "0.1.0"` when current
VERSION is `0.5.0-dev`.)

**EC5 — Multiple specs DEPRECATED with same `displaced_by`.** Allowed.
A single new spec can supersede multiple old specs (consolidation
case).

**EC6 — `displaced_by` covers only part of the deprecated spec's
domain.** The coverage heuristic flags this as Tier 2 (WARNING) for
WDs depending on the uncovered part. User either: (a) extends the
displacing spec, (b) accepts the warning and tracks migration
separately, or (c) writes a second spec to cover the gap and amends
`displaced_by` to a list (future feature — v1 only supports single
`displaced_by`).

**EC7 — Removal version is cut without the spec being INVALIDATED.**
Tier 3 ERROR on every subsequent resolve until either:
- The spec transitions to INVALIDATED (audit-trail-before-deletion
  contract enforced), OR
- `removal_scheduled_in` is bumped to a later version (validator
  allows this; counts as a deliberate slip with the existing
  deprecation reason still applying)

**EC8 — A WD wants to bump `removal_scheduled_in` after deprecation
because the migration is taking longer.** Allowed by the validator
(updates to a later version are fine; updates to an earlier version
are refused per EC4). The slip is captured in git history; no
additional audit field needed for v1.

**EC9 — Spec in DRAFT state proposed for deprecation.** Refuse —
deprecation only applies to load-bearing contracts. A DRAFT spec
that's no longer wanted should be deleted (not yet committed
beyond the working branch) or transitioned DRAFT → INVALIDATED
directly with displacement_reason.

---

## Open questions

**OQ1 — Default `deprecation_age_threshold_days`?** Proposing 90 as
the default for Tier 2 warning escalation. Long enough that small
projects don't trip warnings on every routine deprecation; short
enough that aging deprecations surface within a quarter. User can
override in project-config. Confirm 90 is the right starting point.

**OQ2 — Coverage heuristic for `displaced_by`.** Default v1 is
tag/domain/applies_to overlap. Strict mode (explicit displaced_by →
dependent mapping) is a future enhancement. Confirm the loose
default is fine for v1.

**OQ3 — Should `removal_scheduled_in` allow a version *range*?**
E.g., `removal_scheduled_in: "0.23.0..0.25.0"` meaning "any time
in that window." Rejected for v1 — point values are simpler and
slipping is allowed (EC8). Revisit if real cases emerge.

**OQ4 — KB archaeology article: auto-generated stub vs. user-written?**
Auto-generated stubs risk shipping near-empty articles ("[fill this
in]") that rot. User-written articles have higher friction but
better content. Recommendation: user-written, with a `/spec-invalidate`
helper that pre-fills frontmatter + section headings from spec
metadata and waits for the user to flesh out the body.

**OQ5 — Should the resolver block instead of warn for Tier 3 overdue
cases?** Current design: Tier 3 is advisory (surfaces in output,
doesn't fail the resolve). Alternative: Tier 3 fails the resolve and
forces user to either INVALIDATE the spec or bump
`removal_scheduled_in` forward. Recommendation: advisory for v1 — too
easy to block in-flight work otherwise. Revisit if users report
missing overdue cases.

**OQ6 — Multiple `displaced_by` (a list)?** EC6 raises the case where
a deprecated spec is partially covered by one new spec and partially
by another. v1 supports single `displaced_by` only. List support is
queued for v2 if multi-coverage cases prove common.

---

## Rejected alternatives

**RA1 — Metadata on APPROVED (no new state).** A spec at `state: APPROVED`
with `removal_scheduled_in: 0.23.0` would carry the audit information
without state-machine complexity. Rejected because: state IS the
semantic — "approved AND scheduled for removal AND has alternative" is
genuinely different from "approved." Tools scanning for migration
candidates benefit from a typed marker. The state-machine validator is
also easier to enforce strictly (required fields tied to state) than
metadata-on-APPROVED.

**RA2 — Multiple deprecation states (SOFT_DEPRECATED, HARD_DEPRECATED).**
Conflates severity with state. Single state + age-and-version-aware
resolver tiering gives the same UX with less surface area.

**RA3 — Freeform `removal_scheduled_in: "<marker>"`.** jlsm's original
proposal allowed branch/sprint/PR/WD as the marker. Limbo case:
"after the jan release" never resolves, never decays. Revision 1
tightened to WD-ID; revision 2 (this) tightens further to **semver
version**. Removals and WDs aren't strictly related — versions are
the natural cycle marker.

**RA4 — Rescind path (DEPRECATED → APPROVED).** Revision 1 included
this for the "migration target slipped" case. Removed in revision 2
based on Nathan's reframing: deprecation is a one-way ratchet. If
the alternative was wrong, amend the alternative; don't un-deprecate
the old spec. The discipline forces honest scheduling — you only
DEPRECATE when the alternative is real.

**RA5 — Auto-INVALIDATE on overdue.** If a DEPRECATED spec is past
its `removal_scheduled_in` AND has no remaining dependents,
auto-transition to INVALIDATED. Rejected — silent state changes
erode audit trail. Better to surface as Tier 3 ERROR and let the
user explicitly transition.

**RA6 — Bytes-on-disk fixtures as the reproducer.** Already rejected
in jlsm's original proposal (fixtures rot). Restated here for the
record: the reproducer must be code (synthesizer, reference-impl,
replay tool), not committed binary artifacts.

**RA7 — Auto-generate KB archaeology articles.** Half-empty articles
("[describe byte layout here]") rot worse than no article at all.
The helper command pre-fills *structure* (frontmatter + headings)
but the body content is user-written.

**RA8 — Language-specific markers in the vallorcine kit core.**
Putting `@Deprecated(forRemoval=true)` in the kit forks support
when projects use different languages. The project-config.md layer
keeps the kit language-agnostic per `project_multi_language_intent.md`.

---

## Implementation plan

This is a 5-PR sequence, each independently mergeable. Total ~3–5
sessions depending on pace.

**P1 — Spec state machine + validator basics** (~1 session)
- Add `DEPRECATED` to the state enum in `scripts/spec-validate.sh`
- Required-field validation: `displaced_by`, `deprecation_reason`,
  `removal_scheduled_in`, `deprecation_date`
- `displaced_by` resolution: spec must exist, be APPROVED, and not
  be DEPRECATED itself (EC1, EC2, EC3)
- `removal_scheduled_in` validation: well-formed semver, strictly
  greater than current VERSION (EC4)
- Forbid `DEPRECATED → APPROVED` transition (no rescind)
- Refuse `DEPRECATED` state on DRAFT spec (EC9)
- Tests: `tests/scenario-deprecated-state-validate.sh`

**P2 — Resolver tiered warnings** (~1 session)
- Resolver emits Tier 0 SILENT when displaced_by covers + version far
- Tier 1 ADVISORY when WD genuinely needs deprecated surface
- Tier 2 WARNING when approaching `removal_scheduled_in` or
  `displaced_by` is DRAFT or `deprecation_date` is over threshold
- Tier 3 ERROR when current VERSION >= `removal_scheduled_in`
- Coverage heuristic (tag/domain/applies_to overlap)
- `deprecation_age_threshold_days` configurable via project-config
- Tests: `tests/scenario-deprecated-resolver.sh`

**P3 — Audit-trail-before-deletion contract (DEPRECATED → INVALIDATED)**
(~1 session)
- Validator refuses INVALIDATION without `displacement_reason` +
  `reproducer` frontmatter + KB article at `.kb/_legacy/<slug>.md`
  (or project-overridden path)
- KB article frontmatter schema validation
- Project-config hooks for `legacy_kb_path` and `reproducer_types`
- Tests: `tests/scenario-deprecated-invalidation-gate.sh`

**P4 — Code-level marker convention (loose check)** (~0.5–1 session)
- `.feature/project-config.md` schema additions: `deprecation_marker`
  section per language
- Validator runs grep-based check on files matching DEPRECATED spec's
  `applies_to`: emit WARNING (not block) if no marker found
- Tests: `tests/scenario-deprecated-code-marker.sh`

**P5 — Docs + changelog + helper commands** (~0.5 session)
- New rule `rules/deprecation-discipline.md` or extension of
  `spec-annotation-protocol.md`
- `/spec-deprecate <spec-id> --displaced-by <other-id> --in <version>`
  helper — interactive command that pre-fills DEPRECATED frontmatter
  and prompts for the reason
- `/spec-invalidate <spec-id>` helper — pre-fills KB archaeology
  article stub from spec metadata, waits for user to flesh out
- CHANGELOG for v0.23.0

---

## Success criteria

- Pre-release projects (jlsm, future ones) can use DEPRECATED as
  a substitute for the classical SemVer deprecation cycle without
  losing audit-trail discipline
- The validator catches at least one structural error per project
  in the first 5 real deprecation cycles (proof the enforcement
  is doing work, not just decorating frontmatter)
- The resolver's Tier 3 overdue warnings catch at least one case
  where a removal version was cut but the marker spec didn't
  transition to INVALIDATED (the lazy / forgotten case)
- Zero auto-state-transitions (every state change is user-initiated)
- jlsm adopts the kit-level support and ships its Java-specific
  layer on top, demonstrating the project-config.md split works
- A second project (non-Java) uses the same kit support with its
  own language layer, validating the multi-language design

---

## Relationship to other vallorcine designs

- **`designs/wd-sizing-feedback.md`** — orthogonal. WD-sizing tells you
  if your decomposition is too coarse; DEPRECATED tells you what to
  do when a contract has a successor.
- **`designs/central-invariant-gate.md`** — orthogonal. The gate
  catches incomplete shipping; DEPRECATED is about scheduled
  succession of previously-shipped work.
- **`designs/memory-to-kb-migration.md`** — adjacent. The "Keep in
  memory vs migrate to KB" classification is conceptually similar to
  "Approved vs Deprecated vs Invalidated" — both are lifecycle
  management. Could share helpers in a future refactor.
- **`rules/spec-annotation-protocol.md`** — adjacent. Spec annotations
  point at code; DEPRECATED specs trigger the code-marker check. P4
  may want to absorb or cross-reference annotation discipline.
- **`rules/completeness-contract.md`** — adjacent. The
  audit-trail-before-deletion contract is in the same family as the
  Scope-reconciliation contract — both refuse-on-incompleteness.
  DEPRECATED → INVALIDATED enforcement is "completeness for legacy
  removal."
