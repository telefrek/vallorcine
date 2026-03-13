# /ideate $ARGUMENTS

Start or continue a vallorcine development session.

---

## Step 1 — Determine session goal

If `$ARGUMENTS` is non-empty, use it as the session goal verbatim.

If `$ARGUMENTS` is empty, ask the user:

```
What's your session goal? (one sentence — what you want to accomplish today)
```

Wait for their response and use it as the session goal.

---

## Step 2 — Read context

Read these files in order:

1. **WIP.md** (if it exists) — in-flight work from a previous session that may
   have crashed or been interrupted. If present and non-empty, this takes
   priority: the session goal should incorporate finishing or continuing this work
   unless the user's goal explicitly overrides it.
2. **DESIGN.md** — system architecture and the 9 core principles
3. **CONTEXT.md** — focus on: Current focus, Recent decisions, Open questions.
   CONTEXT.md is the active working state only. Settled design history lives in
   SETTLED.md and competitive landscape in COMPETITIVE.md — do not read those
   unless the session goal specifically requires them.

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

Then state the session goal clearly:

```
Session goal: <the goal from Step 1>
```

Ready to work.
