# /save-work

Close out the current development session by updating project context.

---

## Step 1 — Update CONTEXT.md and graduate to SETTLED.md

Read the current CONTEXT.md, then update it:

- **Replace "Current focus" entirely** with what we did this session and where things stand
- **Add new decisions** to "Recent decisions" (date + rationale)
- **Update "Open questions"** — resolve closed ones, add new ones
- **Add any good-but-deferred thoughts** to "Deferred ideas"
- **Leave "Working preferences" alone** unless something genuinely changed
- If "Recent decisions" exceeds ~10 items, **graduate the oldest to SETTLED.md**
  (append them as new sections at the bottom of SETTLED.md, then remove from CONTEXT.md)

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

## Step 3 — Version and changelog

If this session constitutes a meaningful increment:
- Update VERSION
- Add a CHANGELOG.md entry
- **Sync version to plugin manifests**: update the `"version"` field in both
  `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` to match VERSION

If not, skip this step.

---

## Step 4 — Clear WIP.md

If `WIP.md` exists, delete it. The work is either committed or captured in
CONTEXT.md now — the checkpoint has served its purpose.

---

## Step 5 — Confirm

Display what was updated:

```
── Session closed ──────────────────────────────────
Updated: CONTEXT.md
<If decisions graduated:>
Updated: SETTLED.md
<If competitive landscape changed:>
Updated: COMPETITIVE.md
<If docs synced:>
Updated: DESIGN.md
Updated: README.md
<If version bumped:>
Updated: VERSION → <new version>
Updated: CHANGELOG.md

Ready to commit. Suggested:
  git add -A && git commit -m "session: <one line summary>"
────────────────────────────────────────────────────
```
