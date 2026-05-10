# /save-wip

Save the current session state for a post-`/clear` resume — capture what's
in flight without ending the session.

Use this when you're about to `/clear` to free context but plan to come back
to the same work in a fresh session. Unlike `/save-work` (end-of-session
wrap-up) this command **preserves WIP.md** and skips the heavy doc-sync
ceremony.

| Command | Purpose | Touches |
|---|---|---|
| `/save-wip` (this) | Mid-flight checkpoint before `/clear` or restart | CONTEXT focus + WIP.md + learnings |
| `/save-work` | Session done, ready to commit | CONTEXT, SETTLED, DESIGN, README, changelog staging, **deletes WIP** |

If the session is genuinely done, run `/save-work` instead — `/save-wip`
leaves cleanup work behind that `/save-work` would have done.

---

## Step 1 — Refresh CONTEXT.md "Current focus"

Read CONTEXT.md, then update:

- **"Current focus"** — replace with what we're actively working on right
  now: the goal, where we are in it, what's next. Two or three sentences,
  written so a fresh agent reading CONTEXT.md can pick up the thread.
- **"Open questions"** — add any new ones from this session; resolve any
  that have been answered.
- **Leave** "Recent decisions", "Working preferences", deferrals untouched
  — those graduate during `/save-work`, not `/save-wip`.

Don't add session learnings to CONTEXT.md — those go to
`.claude/research/` in Step 3 (same convention as `/save-work`).

---

## Step 2 — Write WIP.md

`WIP.md` is the "if you `/clear` and come back, read this first" file.
Gitignored, regenerated each `/save-wip`. Keep it tactical and concrete —
file paths, branch names, exact next commands. CONTEXT.md is the
narrative; WIP.md is the runtime checklist.

Use this template:

```markdown
# WIP — <YYYY-MM-DD HH:MM>

## Where we are

<2-4 sentences: what's mid-flight, what was just finished, what blocks
progress if anything. Concrete enough that a fresh agent can act, not
just understand.>

## Branch state

- Current branch: `<branch-name>`
- Tracks: `<remote/branch>` (or "local-only")
- Ahead of base by: <N> commits
- Dirty files: <list, or "clean working tree">
- Stashes: <list with messages, or "none">

## In-flight tasks

<List the TaskCreate items that are pending or in_progress, by ID and
subject. Note which one is up next. If TaskList is empty, say so.>

## Next concrete action

<The exact command or operation to run when the session resumes. Examples:
"run `bash tests/scenario-foo.sh` to verify the new check passes",
"open PR #N", "investigate why test bar exits 2 in CI but passes locally".>

## Pointers

<Files, line numbers, or external resources the next agent will need.
Keep this list to ~5 items — anything more belongs in CONTEXT.md.>

- `path/to/file.md:42` — <one-line note about why>
- `path/to/script.sh` — <one-line note>

## Risks / loose ends

<Anything fragile or partial that the next agent should be careful about.
"WIP commit on branch X is not pushed yet", "scenario test passes but
hasn't been run against the real fixture", etc.>
```

Write atomically — `WIP.md.tmp` + rename — so if you're interrupted
mid-write the prior `WIP.md` survives.

---

## Step 3 — Session learnings

Same prompt as `/save-work` Step 3.5. Critical here because the user is
about to `/clear`; this is the last chance to capture insights before the
context window resets.

Ask:

> **Learnings check:** What did we learn this session about how
> Claude/agents behave, or about our pipeline design, that we didn't
> know before? Not what we did — what we now understand differently.
>
> I'd suggest these candidates:
> - <1-3 specific findings from the session, if any>
>
> Keep any? (list numbers, "all", or "none")

Guidelines for proposing candidates:
- Only propose things that would change how we design prompts, agents,
  or pipelines.
- Don't propose code patterns, architecture decisions, or project state
  — those belong in SETTLED.md, CONTEXT.md, or `.kb/`.
- Don't propose things obvious from the code or git history.
- When in doubt, don't propose — the user can always add their own.

If the user selects any:

1. Write each to `.claude/research/<slug>.md`:
   ```markdown
   ---
   title: <concise title>
   date: <YYYY-MM-DD>
   source: <session context>
   tags: [<from: agent-behavior, prompt-design, cost-model, failure-modes, schema-compliance, context-management>]
   ---

   <2-5 sentences: the finding, then its implication for vallorcine design>
   ```
2. List the files written in the Step 4 confirmation.

If "none", skip silently.

---

## Step 4 — Confirm

Display what was saved:

```
── WIP saved ───────────────────────────────────────
Updated: CONTEXT.md (Current focus + Open questions)
Wrote:   WIP.md (<N> lines)
<If learnings captured:>
Added:   .claude/research/<slug>.md
         <one per line for each>

When you resume:
  1. Read CONTEXT.md and WIP.md.
  2. Pick up at: <copy of the "Next concrete action" line>

Safe to /clear now.
────────────────────────────────────────────────────
```

The "Safe to /clear now" line is the contract this skill makes — once
you've seen it, you can clear the context window without losing thread.

---

## What this skill does NOT do

Deliberately omitted from `/save-wip`, available in `/save-work`:

- DESIGN.md / README.md sync — end-of-session activity.
- `.changelog-staging.md` updates — only meaningful at release time.
- SETTLED.md graduation — premature mid-session; if a decision graduates
  here it should also be settled enough to survive in CONTEXT.md until
  the real `/save-work` runs.
- Deleting WIP.md — that's `/save-work`'s exit semantic, not ours.

If you find yourself wanting one of these mid-session, it's a signal the
session is actually done — run `/save-work`.
