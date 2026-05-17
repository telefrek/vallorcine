# DEPRECATED spec state — pre-release deprecation discipline

**Status:** proposed — 2026-05-17
**Originating signal:** jlsm session proposed a pre-release format-deprecation
discipline that introduces a `DEPRECATED` state between `APPROVED` and
`INVALIDATED`. Most of the proposal is jlsm-specific (Java annotations,
storage-format KB paths), but the **state machine + validator + resolver +
audit-trail contract** are reusable across any pre-release project.

This design scopes the vallorcine-kit-level support. Language and
domain specifics stay in `.feature/project-config.md` so other languages
(Rust, Python, Go, TS) and other artifact types (algorithms, protocols)
can plug in.

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

1. Have no released versions yet (so no SemVer cycle to lean on)
2. Need to retire code/contracts as the design evolves
3. Need an audit trail for what was removed and why

The current options for pre-release deprecation:

- **APPROVED → INVALIDATED in one step.** Loses the "scheduled for
  removal" signal. Code keeps running until it's deleted; nothing
  surfaces the intent.
- **APPROVED with prose annotations.** No structural signal. Resolver
  can't warn, validator can't enforce removal scheduling, tools can't
  grep for deprecation candidates.
- **DRAFT used as "scheduled for removal."** Wrong semantics —
  DRAFT means "not yet load-bearing," but a deprecated spec IS
  load-bearing right up until removal.

The proposal: a new `DEPRECATED` state that's load-bearing AND
scheduled for removal, with required scheduling metadata.

---

## Goal

Add `DEPRECATED` to the spec state machine. Sits between APPROVED and
INVALIDATED. Specs in DEPRECATED state:

- Satisfy `required_state: APPROVED` dependencies (with resolver warning)
- Carry required scheduling metadata (validator-enforced)
- Surface in `/work-status` and during `/curate` scans for awareness
- Trigger audit-trail-before-deletion enforcement when transitioning to
  INVALIDATED

Plus a rescind path: `DEPRECATED → APPROVED` when a removal is canceled,
with the rescind reason captured in an audit-trail field.

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
- **Automatic transition.** Specs don't auto-DEPRECATE based on age,
  inactivity, or any other heuristic. Transitions are explicit user
  actions.
- **Multiple deprecation severity levels.** No SOFT_DEPRECATED vs
  HARD_DEPRECATED. One state with age-aware warning escalation handles
  the same concern with less complexity.

---

## Design

### State machine

```
                         ┌──────────────────┐
                         │   (rescind)      │
                         ▼                  │
DRAFT ──→ APPROVED ──→ DEPRECATED ──→ INVALIDATED
                                │
                                └──→ (resolves required_state: APPROVED)
                                     emits resolver warning
                                     escalates with age
```

| State | Meaning | Satisfies `required_state: APPROVED`? |
|---|---|---|
| `DRAFT` | Authoring in progress | No |
| `APPROVED` | Settled and load-bearing | Yes |
| `DEPRECATED` | Scheduled for removal, still load-bearing | **Yes, with warning** |
| `INVALIDATED` | No longer in force, preserved for history | No |

### DEPRECATED frontmatter (validator-enforced)

When `state: "DEPRECATED"`, these fields are REQUIRED:

```yaml
state: "DEPRECATED"
deprecated_by: "WD-NN"             # the WD that MARKED this deprecated
                                   # MUST be COMPLETE or in-flight in the
                                   # same work group
deprecation_reason: "..."          # one-line rationale
removal_scheduled_in: "WD-MM"      # the WD scheduled to do the removal
                                   # MUST be DRAFT|SPECIFIED|READY|
                                   # BLOCKED in the same work group
                                   # (NOT yet COMPLETE — that's a
                                   # contradiction)
deprecation_date: "2026-05-17"     # ISO date when DEPRECATED state set
                                   # used for age-aware warning escalation
```

The validator (`spec-validate.sh`) refuses a DEPRECATED spec missing
any of these fields.

**Why `removal_scheduled_in` is constrained to a real WD-ID** (rejecting
the freeform "<marker>" pattern from jlsm's proposal):

- "after-the-jan-release", "v2 maybe", "TBD" — these are limbo markers.
  The validator can't decay them; the spec sits forever in DEPRECATED.
- A real WD-ID is checkable: validator confirms the WD exists, is in
  the same work group, and isn't already COMPLETE. Limbo becomes
  structurally harder to enter.
- Edge case: removal is genuinely far off (next major refactor, etc.).
  Resolution: create the removal WD with explicit BLOCKED state and a
  dependency on whatever has to land first. The WD itself becomes the
  scheduling artifact.

### Rescind transition: DEPRECATED → APPROVED

Real case: removal WD gets canceled because the migration target
slipped, or because the deprecation was a mistake.

Required when transitioning DEPRECATED → APPROVED:

```yaml
state: "APPROVED"
rescind_reason: "..."              # one-line rationale for un-deprecating
_deprecation_history:              # appended array, not replaced
  - deprecated_at: "2026-05-17"
    deprecated_by: "WD-08"
    deprecation_reason: "superseded by spec X"
    removal_scheduled_in: "WD-12"
    rescinded_at: "2026-06-15"
    rescind_reason: "WD-12 canceled — migration target slipped"
```

The rescind appends to `_deprecation_history` so subsequent
deprecations (if the spec eventually gets re-deprecated) compound
rather than overwrite. Audit trail is permanent.

After rescind, the four DEPRECATED fields (deprecated_by,
deprecation_reason, removal_scheduled_in, deprecation_date) are
REMOVED from the top-level frontmatter (now archived in
`_deprecation_history`). Top-level frontmatter reflects current state.

### Resolver behavior

When a WD's `artifact_deps` references a DEPRECATED spec:

**Default (advisory warning):**

```
[resolve] WD <wd-id> depends on <spec-id> which is DEPRECATED
          (scheduled for removal in <removal_scheduled_in>;
           reason: <deprecation_reason>;
           deprecated <N> days ago)
```

The dep is SATISFIED. WD can proceed.

**Escalated (overdue warning):**

If `removal_scheduled_in` resolves to a WD that's COMPLETE, the
deprecation is *overdue* — the marker should have transitioned to
INVALIDATED but didn't:

```
[resolve] ERROR: WD <wd-id> depends on <spec-id> which is DEPRECATED
          but its removal WD <removal_scheduled_in> is already COMPLETE.
          The marker spec is overdue for INVALIDATION — investigate
          before continuing.
```

This is still SATISFIED (the resolver doesn't block in-flight work),
but the message is severity ERROR rather than ADVISORY, surfacing in
`/work-status` and any `/curate` scan.

**Age-based escalation:**

If `deprecation_date` is more than `deprecation_age_threshold_days`
(default 90, configurable in `.feature/project-config.md`) AND
`removal_scheduled_in` is still not COMPLETE:

```
[resolve] WARNING: WD <wd-id> depends on <spec-id> which has been
          DEPRECATED for <N> days. Scheduled removal in
          <removal_scheduled_in> has not landed. Confirm scheduling
          is still active or rescind.
```

Three escalation tiers (ADVISORY < WARNING < ERROR) give graceful
ramp from "FYI" to "needs attention" to "broken state, fix now."

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
   removed_in: "WD-NN"
   removed_at: "2026-05-17"
   reproducer: "src/test/java/legacy/V5FileSynthesizer.java"
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
    annotation: "#[deprecated(since = \"<wd-id>\", note = \"<spec-id>\")]"
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

**EC1 — Removal WD itself gets DEPRECATED.** Pathological case: the WD
scheduled to remove a deprecated spec is itself marked DEPRECATED.
Validator should refuse — a deprecation can't be "removed by" a
deprecated work definition. Catch via `removal_scheduled_in` lookup:
verify the target WD's state is in {DRAFT, SPECIFIED, READY, BLOCKED},
not DEPRECATED or INVALIDATED.

**EC2 — Cross-work-group references.** A spec DEPRECATED in work
group A whose removal WD lives in work group B. Initial design:
disallow — keeps validation cheap (single-group lookup). Future: if
real cases emerge, extend to cross-group references.

**EC3 — A WD references a DEPRECATED spec via `requires:` chain.** The
spec lookup is transitive. Resolver warning fires once per direct
DEPRECATED reference; for transitive cases, the user sees the chain
in `/work-status` output.

**EC4 — Rescind after partial removal.** A DEPRECATED spec is
rescinded back to APPROVED, but the removal WD has already started
writing the byte-stream synthesizer (Step 2 of the audit-trail
contract). The synthesizer is fine to keep — it's useful even without
removal. The rescind just means the spec stays load-bearing; the
synthesizer becomes optional test-only utility code.

**EC5 — The DEPRECATED → INVALIDATED transition's three artifacts
fail validation late.** User has completed the removal WD up to PR
draft, then validator refuses INVALIDATION because the KB article
isn't written. Resolution: validator's INVALIDATION check runs at the
*start* of the removal WD's PR step, surfacing the gap before the PR
opens. Caught early, fixable in the same WD.

**EC6 — Empty `_deprecation_history` on first rescind.** Spec was
DEPRECATED, never previously rescinded, now being rescinded. The
array starts at length 1 (the current DEPRECATED-then-rescinded
cycle). Future cycles append.

**EC7 — Spec in DRAFT state proposed for deprecation.** Refuse —
deprecation only applies to load-bearing contracts. A DRAFT spec
that's no longer wanted should be deleted (not yet committed
beyond the working branch) or transitioned DRAFT → INVALIDATED
directly with displacement_reason (no audit trail required since
the spec was never approved).

---

## Open questions

**OQ1 — Default `deprecation_age_threshold_days`?** Proposing 90 as
the default. Long enough that small projects don't trip warnings on
every routine deprecation; short enough that overdue deprecations
surface within a quarter. User can override in project-config.
Confirm 90 is the right starting point or pick 60/120.

**OQ2 — Should the rescind path require an ADR?** Frontmatter
history is the cheapest option; an ADR would surface the
rescind in `.decisions/` for higher discoverability. Recommendation:
frontmatter history is sufficient for v1; promote to ADR if
rescind reasons need to be searchable across projects (they likely
won't).

**OQ3 — Allow `removal_scheduled_in: <PR-number>` as fallback?**
Some projects may want to schedule removal to a specific PR rather
than a WD (especially smaller projects with no work-group decomposition).
Recommendation: REJECT for v1. WD-ID is the canonical reference;
projects without WDs aren't using the work layer yet and shouldn't
need this discipline. Revisit if cross-cutting demand emerges.

**OQ4 — KB archaeology article: auto-generated stub vs. user-written?**
Auto-generated stubs risk shipping near-empty articles ("[fill this
in]") that rot. User-written articles have higher friction but
better content. Recommendation: user-written, with a `/spec-invalidate`
helper that pre-fills the frontmatter + section headings from spec
metadata and waits for the user to flesh out the body.

**OQ5 — Should the resolver block instead of warn for ERROR-severity
overdue cases?** Current design: ERROR is advisory (surfaces in
output, doesn't fail the resolve). Alternative: ERROR fails the
resolve and forces user to either advance the marker spec to
INVALIDATED or rescind. Recommendation: advisory for v1 — too easy
to block in-flight work otherwise. Revisit if users report missing
overdue cases.

**OQ6 — Should we add `state: SUNSET` for "no longer recommended but
not yet scheduled for removal"?** This would be a 5-state machine
(DRAFT, APPROVED, SUNSET, DEPRECATED, INVALIDATED). Rejected — adds
complexity without clear value. DEPRECATED with a far-future
`removal_scheduled_in` WD captures the same intent.

---

## Rejected alternatives

**RA1 — Metadata on APPROVED (no new state).** A spec at `state: APPROVED`
with `removal_scheduled_in: WD-NN` would carry the audit
information without state-machine complexity. Rejected because:
state IS the semantic — "approved AND scheduled for removal" is
genuinely different from "approved." Tools scanning for deprecation
candidates benefit from a typed marker. The state-machine validator
is also easier to enforce strictly (required fields tied to state)
than metadata-on-APPROVED.

**RA2 — Multiple deprecation states (SOFT_DEPRECATED, HARD_DEPRECATED).**
Conflates severity with state. Single state + age-aware warning
escalation gives the same UX with less surface area.

**RA3 — Freeform `removal_scheduled_in: "<marker>"`.** jlsm's original
proposal allowed branch/sprint/PR/WD as the marker. Limbo case:
"after the jan release" never resolves, never decays, spec sits
forever in DEPRECATED. Tightened to WD-ID only — checkable, decayable,
catches limbo at validation time.

**RA4 — Auto-INVALIDATE on age threshold.** If a DEPRECATED spec is
older than N days AND its removal WD is COMPLETE, auto-transition
to INVALIDATED. Rejected — silent state changes erode audit trail.
Better to surface as an ERROR-severity resolver warning and let the
user explicitly transition.

**RA5 — Bytes-on-disk fixtures as the reproducer.** Already rejected
in jlsm's proposal (fixtures rot). Restated here for the record:
the reproducer must be code (synthesizer, reference-impl, replay
tool), not committed binary artifacts.

**RA6 — Auto-generate KB archaeology articles.** Half-empty articles
("[describe byte layout here]") rot worse than no article at all.
The helper command pre-fills *structure* (frontmatter + headings)
but the body content is user-written.

**RA7 — Language-specific markers in the vallorcine kit core.**
Putting `@Deprecated(forRemoval=true)` in the kit forks support
when projects use different languages. The project-config.md layer
keeps the kit language-agnostic per `project_multi_language_intent.md`.

---

## Implementation plan

This is a 5-PR sequence, each independently mergeable. Total ~3–5
sessions depending on pace.

**P1 — Spec state machine + validator basics** (~1 session)
- Add `DEPRECATED` to the state enum in `scripts/spec-validate.sh`
- Required-field validation: `deprecated_by`, `deprecation_reason`,
  `removal_scheduled_in`, `deprecation_date`
- `removal_scheduled_in` resolution: confirm the target WD exists,
  is in the same work group, and is in {DRAFT, SPECIFIED, READY,
  BLOCKED}
- Forbid `removal_scheduled_in` target being DEPRECATED or INVALIDATED
  itself (EC1)
- Refuse `DEPRECATED` state on a DRAFT spec (EC7)
- Tests: `tests/scenario-deprecated-state-validate.sh`

**P2 — Resolver warnings + age escalation** (~1 session)
- Resolver emits ADVISORY when WD has artifact_deps on a DEPRECATED spec
- Escalates to WARNING when `deprecation_date` is more than threshold
  days old AND removal_scheduled_in is still not COMPLETE
- Escalates to ERROR when removal_scheduled_in is COMPLETE (overdue)
- Threshold configurable via `.feature/project-config.md`
  (`deprecation_age_threshold_days`, default 90)
- Tests: `tests/scenario-deprecated-resolver.sh`

**P3 — Rescind path + audit history** (~0.5 session)
- DEPRECATED → APPROVED transition: validator requires `rescind_reason`
- `_deprecation_history` array append (NOT overwrite) on each
  deprecation/rescind cycle
- Removal of top-level DEPRECATED fields on rescind (moved to history)
- Tests: `tests/scenario-deprecated-rescind.sh`

**P4 — Audit-trail-before-deletion contract** (~1 session)
- DEPRECATED → INVALIDATED validator: refuse without
  `displacement_reason` + `reproducer` frontmatter + KB article at
  `.kb/_legacy/<slug>.md` (or project-overridden path)
- KB article frontmatter schema validation
- Project-config hooks for `legacy_kb_path` and `reproducer_types`
- Tests: `tests/scenario-deprecated-invalidation-gate.sh`

**P5 — Code-level marker convention (loose check)** (~0.5–1 session)
- `.feature/project-config.md` schema additions: `deprecation_marker`
  section per language
- Validator runs grep-based check on files matching DEPRECATED spec's
  `applies_to`: emit WARNING (not block) if no marker found
- Suppression-with-explanation: pattern detection in language-specific
  layer (e.g., `@SuppressWarnings("deprecation") // ...` requires
  non-empty comment)
- Tests: `tests/scenario-deprecated-code-marker.sh`

**P6 — Docs + changelog + helper command** (~0.5 session)
- New rule `rules/deprecation-discipline.md` or extension of
  `spec-annotation-protocol.md`
- `/spec-deprecate <spec-id> <removal-wd-id>` helper (or extension
  of `/spec-author`) — interactive command that pre-fills the
  DEPRECATED frontmatter and prompts for the reason
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
- The resolver's ERROR-tier overdue warnings catch at least one
  case where a removal WD COMPLETED but the marker spec didn't
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
  do when a contract is going away. Different problems.
- **`designs/central-invariant-gate.md`** — orthogonal. The gate
  catches incomplete shipping; DEPRECATED is about scheduled removal
  of previously-shipped work.
- **`designs/memory-to-kb-migration.md`** — adjacent. The "Keep in
  memory vs migrate to KB" classification is conceptually similar to
  "Approved vs Deprecated vs Invalidated" — both are lifecycle
  management. Could share helpers in a future refactor.
- **`rules/spec-annotation-protocol.md`** — adjacent. Spec annotations
  point at code; DEPRECATED specs trigger the code-marker check. P5
  may want to absorb or cross-reference annotation discipline.
- **`rules/completeness-contract.md`** — adjacent. The audit-trail-
  before-deletion contract is in the same family as the
  Scope-reconciliation contract — both refuse-on-incompleteness.
  DEPRECATED → INVALIDATED enforcement is "completeness for legacy
  removal."
