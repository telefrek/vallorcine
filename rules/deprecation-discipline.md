# Deprecation Discipline

How vallorcine handles deprecation and removal of spec contracts in
pre-release and released projects. Language-agnostic. Enforced by
`spec-validate.sh` and `work_check_spec_dep` in `work-lib.sh`.

See `designs/deprecated-state.md` for the design rationale and
rejected alternatives.

---

## The state-status pair

vallorcine specs carry two independent lifecycle fields:

- **`state`** — verification dimension: `DRAFT | APPROVED | INVALIDATED`
- **`status`** — lifecycle dimension: `DRAFT | ACTIVE | STABLE | DEPRECATED`

The four common combinations:

| `(state, status)` | Meaning |
|---|---|
| `(DRAFT, DRAFT)` | Authoring in progress |
| `(APPROVED, ACTIVE)` | Live, recently approved |
| `(APPROVED, STABLE)` | Live, settled, no expected churn |
| `(APPROVED, DEPRECATED)` | **Still load-bearing, alternative exists** |
| `(INVALIDATED, *)` | No longer in force; preserved for history |

The mental state machine `DRAFT → APPROVED → DEPRECATED → INVALIDATED`
is expressed via the `(state, status)` pair.

---

## What `status: DEPRECATED` means

> "Still active, but alternatives exist — prefer the alternative."

A `status: DEPRECATED` spec:

- Still **satisfies** `required_state: APPROVED` dependencies (the
  verification dimension is unchanged)
- **Names a successor** (`displaced_by`) so consumers know where to
  migrate
- **Has a scheduled removal version** so the deprecation isn't
  open-ended
- **Is one-way** — no rescind back to ACTIVE/STABLE. Once you've
  declared alternatives exist, that's a downstream-visible commitment.

If you intended "this spec is being retired with no successor," use
`state: INVALIDATED` directly (no audit-trail-before-deletion contract).

---

## Required fields when `status: DEPRECATED`

Set on the deprecated spec's frontmatter (validator-enforced):

```yaml
state: "APPROVED"                  # still load-bearing
status: "DEPRECATED"               # the marker
displaced_by: ["<spec-id>", ...]   # non-empty; targets must exist
                                   # and be state:APPROVED, not
                                   # themselves status:DEPRECATED
displacement_reason: "..."         # one-line rationale
removal_scheduled_in: "0.23.0"     # valid semver, > current VERSION
deprecation_date: "YYYY-MM-DD"     # ISO date the spec was deprecated
```

The validator refuses the deprecation if any of these is missing,
malformed, or contradictory. See `tests/scenario-deprecated-status-validate.sh`
for the full enforcement matrix.

---

## Resolver tier escalation

When a WD's `artifact_deps` references a `status: DEPRECATED` spec,
the resolver emits a tiered message on stderr:

- **Tier 0 (SILENT)** — Spec is `APPROVED + ACTIVE/STABLE`. No
  deprecation involvement. Nothing emitted.
- **Tier 1 (ADVISORY)** — Spec is `DEPRECATED`. Removal version is
  far away (>1 minor bump). Background awareness.
- **Tier 2 (WARNING)** — Current VERSION is within 1 minor bump of
  `removal_scheduled_in`, OR `displaced_by` target is not
  `state: APPROVED`. Migration is needed soon.
- **Tier 3 (ERROR)** — Current VERSION has reached or passed
  `removal_scheduled_in`. The marker spec is overdue for INVALIDATION.

All tiers leave the dep **SATISFIED** (rc=0). The resolver doesn't
block in-flight work on deprecation alone — warnings raise awareness,
not bars.

---

## Audit-trail-before-deletion contract

When a spec transitions to `state: INVALIDATED` AND has non-empty
`displaced_by`, the validator requires three artifacts before
accepting the INVALIDATION:

1. **`displacement_reason`** — one-line rationale (already a vallorcine
   convention; promoted from WARN to ERROR when `displaced_by` is set).

2. **`reproducer` frontmatter** — pointer to forensic recovery code:
   ```yaml
   reproducer:
     type: "synthesizer"       # synthesizer | reference-impl | protocol-replay | other
     path: "src/legacy/V5FileSynthesizer.java"
     description: "v5 byte-stream synthesizer for forensic tests"
   ```
   The path must exist (relative to project root).

3. **KB archaeology article** at `.kb/_legacy/<spec-id>.md` with
   frontmatter:
   ```yaml
   ---
   {
     "type": "legacy-archaeology",
     "spec_ref": "<spec-id>",
     "removed_in": "<version>",
     "removed_at": "YYYY-MM-DD"
   }
   ---
   ```
   Article body documents: what it was (byte layout / algorithm /
   protocol), why it existed, why it was removed, how to reproduce.

Specs invalidated **without** `displaced_by` (direct retirement of an
unused contract, no successor) bypass this gate — the audit-trail
captures what was lost when a successor exists; direct retirement
needs no reproducer.

---

## Code-level marker (loose)

The validator emits a WARNING (not block) when a `status: DEPRECATED +
state: APPROVED` spec has `@spec` annotations in source files that
don't contain a `deprecat*` substring. This catches the common case
where the spec is marked DEPRECATED but the implementation forgot to
add a code-level deprecation marker:

- Java: `@Deprecated(forRemoval = true)`
- Rust: `#[deprecated(since = "...", note = "...")]`
- Python: `warnings.warn(DeprecationWarning(...))`
- Go: `// Deprecated: ...`
- TypeScript: `@deprecated <spec-id>`

The check is intentionally loose — substring matching keeps it
language-agnostic. Per-language strict patterns (with `.feature/project-config.md`
declarations) are a future enhancement when real cases emerge.

---

## Transitions allowed and disallowed

**Allowed:**
- `(DRAFT, DRAFT) → (APPROVED, ACTIVE)`
- `(DRAFT, *) → (INVALIDATED, *)` (never-shipped specs)
- `(APPROVED, ACTIVE|STABLE) → (APPROVED, DEPRECATED)` — **mark deprecated**
- `(APPROVED, DEPRECATED) → (INVALIDATED, DEPRECATED)` — **retire with audit trail**
- `(APPROVED, ACTIVE|STABLE) → (INVALIDATED, *)` — **direct retire, no successor**

**Disallowed (validator refuses):**
- `(APPROVED, DEPRECATED) → (APPROVED, ACTIVE|STABLE)` — **no rescind**
- `(APPROVED, DEPRECATED) → (DRAFT, *)` — no rescind
- `(INVALIDATED, *) → anything` — terminal
- `(DRAFT, *) → (*, DEPRECATED)` — can't deprecate a non-load-bearing spec

The "no rescind" rule is intentional. Declaring "alternatives exist"
is a downstream-visible commitment. If the alternative turns out
insufficient, AMEND the alternative or write a third spec — don't
un-deprecate. Discipline forces honest scheduling: only DEPRECATE
when the alternative is real.

---

## Workflow

To deprecate a spec:

1. Verify the successor exists and is `state: APPROVED + status: ACTIVE/STABLE`.
2. Edit the spec's frontmatter to set:
   - `status: "DEPRECATED"`
   - `displaced_by: ["<successor-id>"]`
   - `displacement_reason: "..."`
   - `removal_scheduled_in: "<future-version>"`
   - `deprecation_date: "<today-ISO>"`
3. Run `bash .claude/scripts/spec-validate.sh <spec-file>` to verify.
4. Add a code-level marker to the implementation referencing the spec
   (language-appropriate; see "Code-level marker" above).
5. Commit and PR.

To finalize removal (transition to INVALIDATED):

1. Write the reproducer (synthesizer / reference-impl / protocol-replay)
   in test-only code.
2. Write the KB archaeology article at `.kb/_legacy/<spec-id>.md`.
3. Edit the spec's frontmatter to set:
   - `state: "INVALIDATED"`
   - `reproducer: { type: "...", path: "...", description: "..." }`
   - (keep `displaced_by` + `displacement_reason` from the deprecation)
4. Delete the implementation code that the spec governed (the
   reproducer remains as test-only).
5. Run `bash .claude/scripts/spec-validate.sh <spec-file>` to verify
   the audit-trail-before-deletion contract.
6. Commit and PR.

---

## Why no rescind

A deprecation marker is a downstream-visible commitment. Consumers
start migrating; code markers go in; ADRs may cite the displacement.
Un-deprecating that work erodes trust in the discipline.

If your alternative turns out to be insufficient:
- AMEND the alternative spec to cover the missing case, OR
- Write a NEW spec that subsumes both the old and the alternative,
  invalidating both.

The old spec stays DEPRECATED. Its history is preserved honestly —
"we tried to migrate to X, X had a gap, we fixed X" is a better
audit trail than "we un-deprecated Y when X didn't work."

---

## Related rules and designs

- `designs/deprecated-state.md` — design rationale, edge cases,
  rejected alternatives
- `rules/spec-annotation-protocol.md` — `@spec` annotation conventions
  that drive the code-marker check
- `rules/completeness-contract.md` — the audit-trail-before-deletion
  contract is in the same family as the Scope-reconciliation contract
  (both refuse-on-incompleteness)
