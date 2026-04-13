# Verify Implementation Before Scoping Work

When items from CONTEXT.md Open Questions, DEFERRED.md, or memory are being
considered as work to do, verify whether the implementation already exists
before accepting them as "needs implementation."

## Why this rule exists

Two items were scoped as implementation work and turned out to already be
fully built (audit budget controls, audit→TDD feedback loop). CONTEXT.md
and memory described them as future work because planning docs track intent,
not implementation status. This wasted planning time and created false urgency.

## Verification steps

Before scoping any item from a planning doc:

1. **Read the actual skill/script files** — not just the planning description.
   If the item mentions a feature of `/audit`, read `skills/audit/SKILL.md`.
2. **Grep for key terms** — function names, script names, frontmatter fields,
   CLI flags mentioned in the design.
3. **Distinguish "needs implementation" from "needs validation"** — these have
   very different effort profiles. A designed-and-coded feature that hasn't
   been exercised is validation work (~1 session), not implementation (~1 week).
4. **Update the planning doc** — if something is already built, update
   CONTEXT.md with `[implemented]` status so the next session doesn't repeat
   the same mistake.

## When a discovery changes the scope

If verification reveals that scoped work is already done:
1. Update CONTEXT.md to reflect actual status
2. Update or correct any stale memory entries
3. Add a rule if the root cause is structural (repeatable mistake)
4. Tell the user — don't silently absorb the finding
