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

1. **DESIGN.md** — system architecture and the 9 core principles
2. **CONTEXT.md** — focus on: Current focus, Recent decisions, Open questions.
   Settled design is reference only, skim it.

---

## Step 3 — Confirm orientation

Respond with a 3–4 sentence orientation covering:
- Where we are in the project
- What's been completed recently
- What the main open questions are

Then state the session goal clearly:

```
Session goal: <the goal from Step 1>
```

Ready to work.
