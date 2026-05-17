# Memory → KB migration

**Status:** proposed — 2026-05-17
**Originating signal:** session feedback during v0.21.0 work — durable
auto-memory entries (70+ in current user's vallorcine memory) hold
high-signal content that dispatched subagents cannot see, because
memory lives under `~/.claude/projects/<hash>/memory/` and is not part
of the project's loaded context.

---

## Problem

Auto-memory accumulates content in three rough categories:

1. **Behavioral feedback** ("don't suggest stopping", "stream large
   files line-by-line") — applies to how Claude works, not what the
   project does.
2. **Project tendencies** ("this project's audits cost ~$13/bug",
   "spec violations must be fixed inline") — durable observations about
   the project that should shape future decisions.
3. **Session state** ("WD-04 is in IMPLEMENTING", "next session: review
   jlsm KB outputs") — ephemeral.

Today, all three sit in the same `~/.claude/projects/<hash>/memory/`
directory. This causes two structural problems:

### Problem 1 — Memory is invisible to subagents

When a skill dispatches a subagent via the Agent tool, the subagent
inherits the project's environment: `rules/*.md`, `.kb/`, `.decisions/`,
`CLAUDE.md` files. It does **not** inherit the parent's memory entries.

That means a subagent doing TDD work in a project where the user has
30 memory entries about "this project's testing tendencies" sees none
of them. Behavioral patterns recorded across sessions stay stuck in
the main-session orbit.

### Problem 2 — Memory rots

Memory entries are point-in-time observations. Old entries reference
files or symbols that may have been renamed or removed; the
`fix_now_not_defer.md` memory I superseded in v0.21.0 was 25 days old
and the framing had drifted. Without a curation mechanism, memory
accumulates without a forgetting mechanism.

The KB has structural advantages memory lacks:

- **Visible to subagents.** `.kb/` is part of the project tree.
- **Curated.** `/curate` runs structural checks; `/kb` provides query
  surfaces.
- **Has frontmatter + cross-refs.** Entries can be discovered via tag
  overlap, applies_to globs, related links.
- **Repair-friendly.** `/curate` already detects stale entries and
  surfaces them for review.

---

## Goal

Durable, project-relevant memory content migrates to `.kb/` so:

- Dispatched subagents can pull it via `/kb` search.
- `/curate` can detect when entries go stale.
- Cross-refs between memories and KB entries work both directions.

Ephemeral memory (session state, current-task tracking) stays in
memory — that's the right home for it.

---

## Non-goals

- **Auto-migrate everything.** Migration is a user-approved per-entry
  decision via `/curate` or a dedicated skill. Bulk auto-migration
  would corrupt the KB with session noise.
- **Delete memory once migrated.** Migrated entries leave a memory
  stub pointing at the KB entry, so prior cross-refs (e.g., other
  memories that reference the migrated one by filename) keep working.
  Stub deletion is a separate user action.
- **Make memory unnecessary.** Memory still hosts the right
  categories (session state, user-profile, ephemeral observations).
  Migration is targeted, not wholesale.
- **Replace `/kb` lifecycle.** KB entries continue to follow the
  existing `/kb` and `/curate` mechanics. Migrated entries become
  ordinary KB entries.

---

## Categorization

Three categories, three handling rules:

### Promote to KB

- **Type:** `feedback` (behavioral guidance with broad applicability)
- **Type:** `project` (durable project tendencies, not session state)
- **Type:** `reference` (pointers to external systems — same role as
  KB but more discoverable in KB form)

**Signal markers:**
- Mentions `tendency`, `gotcha`, `pattern`, `principle`
- Cross-applies across multiple sessions (referenced by other
  memories)
- Describes the project itself, not the user's day

**Examples (from current state):**
- `feedback_stream_large_files.md` — behavioral tendency → promote
- `project_audit_scorecard.md` — durable project measurement → promote
- `feedback_efficiency_as_laziness.md` — design principle → promote
- `reference_jlsm_repo.md` — external pointer → promote

### Keep in memory

- **Type:** `user` (user-profile data — not project-relevant)
- **Type:** `project` BUT session-state ("current focus", "next steps")
- Entries referencing in-progress work that will be irrelevant after
  the work completes

**Signal markers:**
- Mentions dates that will pass ("starting 2026-04-02")
- Tracks WIP, not knowledge
- References specific sessions, not patterns

**Examples (from current state):**
- `project_next_session_naming.md` — session priority → keep
- `project_jlsm_release_prep.md` — has a date → keep
- `feedback_branch_workflow.md` — user habit → keep

### Delete

- Entries already superseded
- Entries that turned out to be wrong
- Entries describing problems that were solved (the solution is in
  code; the memory is now noise)

**Examples (from current state):**
- `project_dashboard_intent.md` — dashboard retired; observation now
  irrelevant → delete on next curation
- `feedback_fix_now_not_defer.md` — superseded by
  `feedback_fix_or_prove_cant.md`; could be deleted after a
  deprecation window

---

## Migration mechanism

### Option A — Extend `/curate` with a `memory-to-kb` mode

Pros:
- Reuses existing curation surface
- Already has user-approved finding flow (numbered pick list)
- Lifecycle already handled (review-log, scan state)

Cons:
- /curate is already a heavy skill with many modes
- Memory access requires the skill to read outside the project tree
  (`~/.claude/projects/<hash>/memory/`) — new permission surface

### Option B — New skill `/memory-promote`

Pros:
- Single-purpose; easier to reason about
- Clean separation: /curate handles project artifacts, /memory-promote
  handles personal memory

Cons:
- Adds a kit surface to maintain
- Users have to remember a new command

### Option C — Hook into `/ideate continue` startup

Pros:
- Runs naturally at session start when memory is already being read
- No new user-facing command
- Catches stale memory immediately when it would be relevant

Cons:
- Tied to /ideate flow (user-facing); not available outside that flow
- Mixes session orientation with migration housekeeping

### Recommendation: Option A (extend `/curate`)

Migrate as `/curate memory-promote` sub-mode:

```
/curate memory-promote
```

Runs a scan over `~/.claude/projects/<hash>/memory/` and
classifies each entry into:

1. **Promote candidates** — entries matching the "promote to KB"
   signal markers (type: feedback/project/reference, durable language,
   project-applicable).
2. **Keep candidates** — entries matching "keep in memory" markers.
3. **Delete candidates** — entries flagged as superseded or
   ephemeral-state.

Surfaces findings via the existing /curate numbered-pick-list
pattern. User picks per-entry: Promote, Keep, Delete, Skip.

Why /curate is the right home:
- The classification rules above are exactly the kind of pattern
  detection /curate already does for ADR drift, KB rot, spec
  coverage, etc.
- The user already invokes /curate when they want to clean up; memory
  hygiene fits the same workflow.
- The review-log already handles "user-approved this finding" state,
  so promoting an entry leaves a trail.

---

## Format mapping

When promoting a memory entry to a KB entry:

| Memory field | KB field | Notes |
|--------------|----------|-------|
| `name:` frontmatter | `title:` frontmatter | One-line description |
| `description:` frontmatter | `summary:` frontmatter | Used for /kb search |
| `type: feedback` | `category: behavioral` | Naming convention shift |
| `type: project` | `category: project-tendency` | |
| `type: reference` | `category: external-reference` | |
| Body content | Body content | Direct transfer |
| `**Why:**` section | `## Why` heading | Promote inline section to heading |
| `**How to apply:**` section | `## How to apply` heading | Same |
| (none) | `tags:` frontmatter | Derived from memory content via NLP or user input |
| (none) | `applies_to:` frontmatter | User-supplied during promotion (glob or path) |
| (none) | `related:` frontmatter | Cross-refs to other KB entries |

The user supplies the `tags` and `applies_to` interactively during the
/curate flow — they're the user's call, not the script's. The
`related:` field is auto-populated by scanning for existing KB entries
with overlapping tags.

The migrated memory file becomes a stub:

```markdown
---
name: Stub — see KB entry
description: Migrated to .kb/<category>/<slug>.md on 2026-05-17
type: <original-type>
---

**Migrated to KB:** `.kb/<category>/<slug>.md`

Original content preserved at `.kb/<category>/<slug>.md`. This stub
exists so existing cross-references (other memory entries citing this
file by name) continue to resolve.

Safe to delete this stub after 30 days if no cross-refs remain.
```

---

## Deduplication and conflict resolution

When `/curate memory-promote` identifies a promote candidate, it
first checks the KB for existing entries on the same topic:

1. **Same name/title match:** existing entry wins; memory entry is
   shown as "superseded — delete memory?".
2. **Same applies_to + overlapping content:** offer merge — user
   picks which version's text to keep.
3. **Same tags but different content:** offer "create as related
   entry" — promote with explicit `related:` link.
4. **No match:** straight promotion.

The /curate scan-result format includes a "duplicate of" field when
match (1) is detected.

---

## Repair flow

When `/curate` finds that an existing KB entry has the same content
as a memory entry (e.g., promoted-then-forgotten), the repair option
is:

```
This memory entry duplicates KB entry .kb/<x>/<y>.md.
  - Delete memory entry (KB is canonical)
  - Convert memory to stub pointing at KB
  - Keep both (false alarm)
```

This is the standard /curate finding shape — user picks the action.

---

## Subagent access patterns

Once an entry lives in `.kb/`, dispatched subagents can find it via:

- **`/kb` search** — the existing pull-model query surface. Subagents
  invoke `/kb "term"` and get matching entries.
- **Tag overlap** — `kb-search.sh` already supports tag-based search.
- **applies_to globs** — entries flagged with `applies_to: src/parser/*`
  surface automatically when the subagent's work touches matching
  paths.

No new subagent integration needed — the existing `/kb` mechanics
handle it. The migration just makes the right content visible.

---

## Open questions

**OQ1 — Should the migration include user-type memories?**
"user" type entries describe the user's role and preferences. They
shape Claude's interaction style with the user but are not
project-relevant. Probably keep in memory. But: if multiple users
collaborate on a project, the user-profile becomes project-shared
context. v1 stays user-private.

**OQ2 — Cross-project memory promotion?**
Some memories (e.g., `feedback_stream_large_files.md`) apply to ALL
projects, not just vallorcine. Promoting to vallorcine's `.kb/` makes
the memory invisible to subagents in jlsm. Two options:
  (a) Promote to a shared `~/.claude/kb/` location loaded by all
      projects (new mechanism)
  (b) Per-project: promote separately when the same insight applies
      in jlsm
  Recommendation: (b) for v1. Cross-project KB sharing is a separate
  design.

**OQ3 — How to detect ephemeral session state?**
Heuristic markers like "current focus", date-stamps, and "next session"
phrases work for obvious cases. Edge cases need user judgment. The
/curate flow surfaces candidates with a confidence score so users see
the easy cases auto-classified and the ambiguous ones flagged for
review.

**OQ4 — Memory deletion lifecycle?**
Once promoted-and-stub-replaced, when does the stub itself get
deleted? Proposal: 30-day window, then /curate offers delete. Too
short risks breaking cross-refs; too long accumulates stubs.

**OQ5 — Should `/kb` queries auto-include current memory?**
A simpler alternative to migration: extend `/kb` to also search
memory at query time. Subagents would call `/kb` and get KB +
memory results.
  Pros: no migration needed; existing memory becomes immediately
        useful to subagents.
  Cons: cross-project memory unsharable; doesn't solve rot; doesn't
        introduce structural curation.
  Recommendation: REJECT for v1. Migration is the right long-term
  shape. /kb augmentation papers over the visibility problem without
  solving rot.

---

## Rejected alternatives

**RA1 — Auto-migrate all memory at install time.** Too aggressive;
ships project-irrelevant content (user profile, session state) into
KB. User judgment is required per-entry.

**RA2 — Symlink memory into the project tree.** Makes memory visible
but doesn't solve rot, doesn't get the /kb search surface, exposes
user data into the repo.

**RA3 — New memory category specifically for "promoteable" entries.**
Adds a fourth memory type (user/feedback/project/reference →
+kb-promote-candidate). Increases complexity for marginal benefit.

**RA4 — Promote in reverse direction (KB → memory).** Wrong direction
— memory is the bottleneck for subagent visibility, KB is the
canonical store.

---

## Implementation plan

This is a 4-PR sequence, each independently mergeable.

**P1 — Classification rules + dry-run reporter** (~1 session)
- Write `scripts/memory-classify.sh` that reads
  `~/.claude/projects/<hash>/memory/*.md` and emits a JSONL
  classification for each entry: `{file, type, category, signal, confidence}`
- Output goes to `.curate/memory-classification.jsonl`
- No mutations yet — this is the scanner

**P2 — `/curate memory-promote` sub-mode** (~1–2 sessions)
- Add `memory-promote` argument handling to `skills/curate/SKILL.md`
- Wire up the numbered pick list, integrating with the existing
  /curate flow
- AskUserQuestion per entry: Promote / Keep / Delete / Skip
- For Promote: AskUserQuestion for tags and applies_to

**P3 — Migration mechanics** (~1 session)
- Write `scripts/memory-to-kb.sh` that takes a memory file path +
  KB target path + frontmatter args → produces the KB entry + memory
  stub
- Wire up MANIFEST entries
- Handle deduplication checks (Step 4 above)
- Append to `.curate/review-log.md` with status

**P4 — Stub lifecycle + tests** (~0.5 session)
- Add 30-day stub expiration to /curate scan
- Test scenarios:
  - Promote-then-stub flow
  - Duplicate-detection paths
  - Stub-deletion after expiration
- Update `tests/test-completeness-contract.sh` to verify the new
  prompt and scripts are wired

---

## Success criteria

- Pick 5 high-signal memory entries from the user's current memory and
  migrate them to vallorcine `.kb/` via /curate memory-promote
- Verify a subagent dispatched by /audit can find those entries via
  /kb query
- Verify stale-promoted-memory detection works on at least one case
- /curate scan time grows by less than 15% (this is a structural test
  to ensure the new sub-mode doesn't bloat the existing scan)
- User reports they no longer manually copy-paste memory content into
  subagent prompts (qualitative — first 3 sessions post-merge)
