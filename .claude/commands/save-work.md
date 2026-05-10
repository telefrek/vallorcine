# /save-work

Close out the current development session by updating project context.

---

## Step 1 — Update CONTEXT.md and graduate to SETTLED.md

Read the current CONTEXT.md, then update it:

- **Replace "Current focus" entirely** with what we did this session and where things stand
- **Add new decisions** to "Recent decisions" (date + rationale)
- **Update "Open questions"** — resolve closed ones, add new ones
- **Leave "Working preferences" alone** unless something genuinely changed
- If "Recent decisions" exceeds ~10 items, **graduate the oldest to SETTLED.md**
  (append them as new sections at the bottom of SETTLED.md, then remove from CONTEXT.md)

If any good-but-deferred thoughts arose this session, **append them to DEFERRED.md**
under "Active deferrals" — do not add them to CONTEXT.md. The "Deferred ideas"
section in CONTEXT.md is a pointer only.

If competitive landscape information changed this session, update COMPETITIVE.md.

---

## Step 2 — Sync DESIGN.md and README.md

Check whether this session's changes affect:

- **DESIGN.md** — file manifest, structural patterns, token budget table, agent
  write authority, or extension points. If any section is now stale, update it.
- **README.md** — feature list, installation instructions, or development workflow.
  If any section no longer matches reality, update it.

Skip if the session was purely internal (e.g., only CONTEXT.md or decision content changed).

---

## Step 3 — Stage changelog notes

If this session made meaningful changes (bug fixes, new features, improvements):

1. Read `.changelog-staging.md` if it exists (may have entries from previous sessions)
2. Append a new section for this session's changes using Keep a Changelog format
   (Added / Changed / Fixed / Removed). Include the date.
3. Write the updated `.changelog-staging.md`

This file is consumed by `/release` when drafting release notes — it does NOT
bump VERSION or write to CHANGELOG.md directly. VERSION is only bumped during
`/release` to prevent multi-session version drift.

If no meaningful changes were made, skip this step.

---

## Step 3.5 — Session learnings

Ask the user:

> **Learnings check:** What did we learn this session about how Claude/agents
> behave, or about our pipeline design, that we didn't know before? Not what
> we did — what we now understand differently.
>
> I'd suggest these candidates:
> - <1-3 specific findings from the session, if any>
>
> Keep any? (list numbers, "all", or "none")

Guidelines for proposing candidates:
- Only propose things that would change how we design prompts, agents, or pipelines
- Don't propose code patterns, architecture decisions, or project state — those
  belong in SETTLED.md, CONTEXT.md, or the user's .kb/
- Don't propose things that are obvious from the code or git history
- When in doubt, don't propose — the user can always add their own

If the user selects any:
1. Write each to `.claude/research/<slug>.md` using this format:
   ```markdown
   ---
   title: <concise title>
   date: <YYYY-MM-DD>
   source: <session context>
   tags: [<free-form tags from: agent-behavior, prompt-design, cost-model, failure-modes, schema-compliance, context-management>]
   ---

   <2-5 sentences: the finding, then its implication for vallorcine design>
   ```
2. List the files written in the Step 5 confirmation output

If the user says "none", skip silently.

---

## Step 4 — Clear WIP.md

If `WIP.md` exists, delete it. The work is either committed or captured in
CONTEXT.md now — the checkpoint has served its purpose.

> **Note.** `/save-work` is end-of-session: it deletes `WIP.md` because the
> session is done. For a mid-flight save before `/clear` (where you want
> WIP.md preserved as a resume affordance), use `/save-wip` instead.

---

## Step 5 — Confirm

Display what was updated:

```
── Session closed ──────────────────────────────────
Updated: CONTEXT.md
<If decisions graduated:>
Updated: SETTLED.md
<If deferrals added:>
Updated: DEFERRED.md
<If competitive landscape changed:>
Updated: COMPETITIVE.md
<If docs synced:>
Updated: DESIGN.md
Updated: README.md
<If learnings captured:>
Added: .claude/research/<slug>.md
<If version bumped:>
Updated: VERSION → <new version>
Updated: CHANGELOG.md

Ready to commit. Suggested:
  git add -A && git commit -m "session: <one line summary>"
────────────────────────────────────────────────────
```
