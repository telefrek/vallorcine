# /save-work

Close out the current development session by updating project context.

---

## Step 1 — Update CONTEXT.md

Read the current CONTEXT.md, then update it:

- **Replace "Current focus" entirely** with what we did this session and where things stand
- **Add new decisions** to "Recent decisions" (date + rationale)
- **Move anything newly stable** from Recent decisions into "Settled design"
- **Update "Open questions"** — resolve closed ones, add new ones
- **Add any good-but-deferred thoughts** to "Deferred ideas"
- **Leave "Working preferences" and "Settled design" alone** unless something genuinely changed
- If "Recent decisions" exceeds ~10 items, move the oldest into Settled design

---

## Step 2 — Version and changelog

If this session constitutes a meaningful increment:
- Update VERSION
- Add a CHANGELOG.md entry

If not, skip this step.

---

## Step 3 — Clear WIP.md

If `WIP.md` exists, delete it. The work is either committed or captured in
CONTEXT.md now — the checkpoint has served its purpose.

---

## Step 4 — Confirm

Display what was updated:

```
── Session closed ──────────────────────────────────
Updated: CONTEXT.md
<If version bumped:>
Updated: VERSION → <new version>
Updated: CHANGELOG.md

Ready to commit. Suggested:
  git add -A && git commit -m "session: <one line summary>"
────────────────────────────────────────────────────
```
