# /ideate $ARGUMENTS

Start or continue a vallorcine development session.

---

## Step 1 — Determine session goal

If `$ARGUMENTS` is "continue" (case-insensitive): check if `WIP.md` exists.
- If WIP.md exists: the session goal is to continue the in-progress work
  described there. Skip Step 1.5 entirely (WIP.md already has the state).
  Proceed to Step 2.
- If WIP.md does not exist: tell the user "No WIP.md found — nothing to
  continue." Then ask for a session goal as if `$ARGUMENTS` were empty.

If `$ARGUMENTS` is non-empty (and not "continue"), use it as the session goal
verbatim.

If `$ARGUMENTS` is empty, ask the user:

```
What's your session goal? (one sentence — what you want to accomplish today)
```

Wait for their response and use it as the session goal.

---

## Step 1.5 — Write WIP.md immediately

Before reading any context files, write `WIP.md` at the project root so the
session goal survives a crash or context overflow:

```markdown
# WIP — <session goal>

**Session goal:** <the goal from Step 1>
**Status:** Starting — reading context.
**Started:** <YYYY-MM-DD>

## TODO

- [ ] (to be filled in once session work begins)
```

If WIP.md already exists and contains in-flight work: do NOT overwrite it.
Instead, append the new session goal under a `## New session` heading so
both the old state and the new goal are preserved.

---

## Step 2 — Read context

Read these files in order:

1. **WIP.md** (if it exists) — in-flight work from a previous session that may
   have crashed or been interrupted. If present and non-empty, this takes
   priority: the session goal should incorporate finishing or continuing this work
   unless the user's goal explicitly overrides it.
2. **DESIGN.md** — system architecture and the 10 core principles
3. **CONTEXT.md** — focus on: Current focus, Recent decisions, Open questions.
   CONTEXT.md is the active working state only. Settled design history lives in
   SETTLED.md and competitive landscape in COMPETITIVE.md — do not read those
   unless the session goal specifically requires them.
   If the session goal is about exploring future ideas or picking up deferred work,
   also read **DEFERRED.md**. Otherwise skip it — it is pull-model.

---

## Step 3 — Confirm orientation

Respond with a 3–4 sentence orientation covering:
- Where we are in the project
- What's been completed recently
- What the main open questions are

If WIP.md was found, also mention:
- What was in progress
- What's done vs remaining
- Which files have uncommitted changes

If this is a `continue` session and WIP.md has an "In Progress" section with
open questions: surface those questions directly. The user left off mid-discussion
and wants to pick up exactly where they stopped — lead with the pending question,
not a summary of what they already know.

Then state the session goal clearly:

```
Session goal: <the goal from Step 1>
```

Ready to work.
