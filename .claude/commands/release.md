# /release

Creates a versioned release of vallorcine.

Bumps VERSION, updates CHANGELOG.md, builds the release zip, commits,
tags, and pushes. Run from the vallorcine repo root.

---

## Pre-flight checks

Run silently before displaying anything:

1. Check that `VERSION` exists in the current directory.
   If not: "This command must be run from the vallorcine repo root."

2. Check that git is available: `git --version`
   If not: "git is not available. Install git and retry."

3. Check that the working tree is clean: `git status --porcelain`
   If there are uncommitted changes:
   ```
   🚀 RELEASE
   ───────────────────────────────────────────────
   ⚠  Uncommitted changes detected:
   <list of changed files from git status>

   A release should be cut from a clean working tree.
   Commit or stash your changes, then re-run /release.

   To release anyway, type: force
   ```
   Wait for input. If anything other than "force": stop.
   If "force": proceed with a warning note in the release commit message.

4. Read `VERSION` — store as CURRENT_VERSION.
   Parse into MAJOR.MINOR.PATCH integers.

Display opening header:
```
───────────────────────────────────────────────
🚀 RELEASE · current: v<CURRENT_VERSION>
───────────────────────────────────────────────
```

---

## Step 1 — Version bump

Check the latest GitHub release to determine whether VERSION was already bumped
(e.g. by `/save-work`):

```bash
gh release list --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null
```

Strip the leading `v` from the result to get LATEST_RELEASE.

**If LATEST_RELEASE could not be determined** (gh unavailable, not authenticated,
or no releases yet): fall through to the normal bump prompt.

**If CURRENT_VERSION != LATEST_RELEASE** (VERSION is already ahead of the latest
release — `/save-work` bumped it):

```
── Version bump ─────────────────────────────────
Current: <CURRENT_VERSION>  (latest release: v<LATEST_RELEASE>)
Version was already bumped — proceeding with <CURRENT_VERSION>.

Type: bump  to increment further instead.
```

Wait for input. If anything other than "bump": set NEW_VERSION = CURRENT_VERSION
and proceed to Step 2. If "bump": fall through to the normal bump prompt below.

**Normal bump prompt** (CURRENT_VERSION == LATEST_RELEASE, or user typed "bump"):

Display:
```
── Version bump ─────────────────────────────────
Current: <CURRENT_VERSION>

Type: patch  (<MAJOR>.<MINOR>.<PATCH+1>)  ·  minor  ·  major
```

Wait for input:
- "patch": increment PATCH, reset nothing
- "minor": increment MINOR, reset PATCH to 0
- "major": increment MAJOR, reset MINOR and PATCH to 0

Compute NEW_VERSION. Display:
```
  New version: <NEW_VERSION>
```

Proceed immediately — no confirmation step.

---

## Step 1.5 — Documentation review (REQUIRED)

Before drafting release notes, review all user-facing documentation against
the changes being released. This catches feature additions, behavior changes,
and renamed/removed commands that haven't been documented.

**Files to check:**

1. **README.md** — command tables, descriptions, post-install instructions.
   Every command in `skills/` should appear. Descriptions should reflect
   current behavior, not historical.
2. **EXAMPLES.md** — walkthroughs for new features. Every major new capability
   should have at least one example showing how to use it.
3. **DESIGN.md** — file manifest (matches actual files), token budget table,
   architecture descriptions.
4. **CONTEXT.md** — "Current focus" section should describe what's shipping,
   not what was shipping last session. "Recent decisions" should include
   decisions made during this development cycle.

**How to check:**

1. Run `git log v<CURRENT_VERSION>..HEAD --oneline` to see all commits
2. For each feature commit (feat:), verify it's reflected in README and EXAMPLES
3. For each renamed/removed command, verify old references are updated
4. For each new script or file, verify DESIGN.md manifest includes it

**If gaps are found:** fix them now, before proceeding. Commit documentation
updates as a separate `docs:` commit. Do not bundle doc fixes into the
release commit — they should be reviewable independently.

Display:
```
── Documentation review ────────────────────────
Checking README, EXAMPLES, DESIGN, CONTEXT against changes since v<CURRENT_VERSION>...

<For each gap found:>
  ⚠ <file> — <what's missing or stale>
<If no gaps:>
  ✓ All documentation up to date.
```

If gaps were found and fixed, show what was updated before proceeding.

---

## Step 2 — Draft release notes

**Check for staged changelog notes:** read `.changelog-staging.md` if it exists.
This file is written by `/save-work` across sessions and contains pre-drafted
changelog entries.

Run: `git log v<CURRENT_VERSION>..HEAD --oneline 2>/dev/null || git log --oneline -20`

Display the commits found:
```
── Commits since v<CURRENT_VERSION> ─────────────────
<list of commits, one per line>
─────────────────────────────────────────────────
```

**If `.changelog-staging.md` exists**, display its contents and use it as the
base for the CHANGELOG entry. Show:
```
── Staged changelog notes ──────────────────────────
<contents of .changelog-staging.md>
─────────────────────────────────────────────────
Using staged notes as the base. Type: auto  to regenerate from commits instead.
```

**Otherwise**, display:
```
── Release notes ────────────────────────────────
Describe what changed in this release, or type: auto
to generate a draft from the commit log.
```

Wait for input.

**If the user provides notes:** use them as the base for the CHANGELOG entry.
**If "auto":** draft the CHANGELOG entry yourself from the commit messages.
  Group commits by type if they follow conventional commit format (feat/fix/chore).
  Otherwise summarise them plainly. Keep it factual — what changed, not why.

Show the drafted entry:
```
── Draft CHANGELOG entry ────────────────────────
## [<NEW_VERSION>] — <YYYY-MM-DD>

<drafted content>
─────────────────────────────────────────────────

  Type **yes** to proceed · or: edit
```

Wait for input. If "edit": ask for corrections, incorporate them, show again,
then proceed. If "yes": proceed immediately.

---

## Step 3 — Build release zip

```
── Building release zip ─────────────────────────
```

Run the following, capturing any errors:

```bash
cd <repo_root>
zip -r "vallorcine-v<NEW_VERSION>.zip" . \
  --exclude "*.git*" \
  --exclude ".claude/*" \
  --exclude ".feature/*" \
  --exclude ".kb/*" \
  --exclude ".decisions/*" \
  --exclude ".DS_Store" \
  --exclude "*.zip" \
  --exclude ".env*"
```

If the zip command fails: display the error and stop.

Display:
```
  Built: vallorcine-v<NEW_VERSION>.zip  (<size>)
```

Write `.vallorcine-source` in the repo root:

```
repo=<REMOTE_URL>
api=https://api.github.com/repos/<OWNER>/<REPO>/releases
```

Derive OWNER and REPO by parsing REMOTE_URL:
- Strip `https://github.com/` prefix or `git@github.com:` prefix
- Strip `.git` suffix
- Split on `/` to get OWNER and REPO

If the remote URL cannot be parsed as a GitHub URL: write the raw URL to
`repo=` and leave `api=` blank with a comment `# non-GitHub remote`.

This file is included in the zip (not gitignored) so consumers get it on
install. install.sh copies it to `.claude/.vallorcine-source`.

Display:
```
  Wrote: .vallorcine-source  (repo + API endpoint)
```

---

## Step 4 — Apply version changes

Make the following file changes:

1. **Write `VERSION`**: single line containing `<NEW_VERSION>`

2. **Sync plugin manifests**: update the `"version"` field in both
   `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` to
   match `<NEW_VERSION>`.

3. **Sync `README.md` version**: find the line matching `Current: <old version>`
   in the Version section and replace with `Current: <NEW_VERSION>`.

5. **Prepend to `CHANGELOG.md`**: insert the new entry after the first `---`
   separator (after the header section), before the previous latest entry.
   The entry format:
   ```
   ## [<NEW_VERSION>] — <YYYY-MM-DD>

   <release notes>

   ---
   ```

6. **Clean up staging file**: if `.changelog-staging.md` exists, delete it.
   Its contents have been incorporated into the CHANGELOG entry.

Display:
```
── Files updated ────────────────────────────────
  VERSION              <CURRENT_VERSION> → <NEW_VERSION>
  plugin.json          <NEW_VERSION>
  marketplace.json     <NEW_VERSION>
  README.md            version → <NEW_VERSION>
  CHANGELOG.md         entry added for v<NEW_VERSION>
```

---

## Step 5 — Commit and tag

Run the following git commands in sequence, displaying each before running:

```bash
git add VERSION CHANGELOG.md README.md .vallorcine-source .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "release: v<NEW_VERSION>"
git tag -a "v<NEW_VERSION>" -m "Release v<NEW_VERSION>"
```

If any command fails: display the error, show what succeeded, and stop.
Do not push until commit and tag both succeed.

Display:
```
── Git ──────────────────────────────────────────
  Committed: release: v<NEW_VERSION>
  Tagged:    v<NEW_VERSION>
```

---

## Step 6 — Push

Check if a remote named `origin` exists: `git remote get-url origin`

If no remote:
```
── No remote configured ─────────────────────────
No git remote named 'origin' found.
Commit and tag are local. To push manually:

  git remote add origin <url>
  git push origin main --tags
```
Stop.

If remote exists, display:
```
── Push ─────────────────────────────────────────
Remote: <remote URL>
Pushing main + tag.

  Type **yes** to push · or: skip
```

Wait for input. If "skip": show the manual push commands and stop.
If "yes": run immediately:

```bash
git push origin main
git push origin "v<NEW_VERSION>"
```

If push fails (e.g. branch protection, auth): display the error and the
manual commands. Do not retry automatically.

---

## Step 7 — GitHub Release (if gh CLI available)

Check: `gh --version 2>/dev/null`

If `gh` is not available: skip to summary.

If available, check auth: `gh auth status 2>/dev/null`

If not authenticated: skip to summary with a note.

If authenticated:
```
── GitHub Release ───────────────────────────────
Creating GitHub Release with zip attached.

  Type **yes** to create · or: skip
```

Wait for input. If "skip": display manual instructions and skip.
If "yes": run immediately:

```bash
gh release create "v<NEW_VERSION>" \
  "vallorcine-v<NEW_VERSION>.zip" \
  --title "v<NEW_VERSION>" \
  --notes "<release notes — first paragraph only>"
```

Display the release URL on success.

If gh fails: display instructions for creating manually:
```
To create a GitHub Release manually:
  1. Go to: <remote URL>/releases/new
  2. Tag: v<NEW_VERSION>
  3. Title: v<NEW_VERSION>
  4. Attach: vallorcine-v<NEW_VERSION>.zip
  5. Paste the CHANGELOG entry as the release description
```

---

## Step 8 — Summary

```
───────────────────────────────────────────────
🚀 RELEASE complete · v<NEW_VERSION>
───────────────────────────────────────────────
Version  : <CURRENT_VERSION> → <NEW_VERSION>
Tag      : v<NEW_VERSION>
Zip      : vallorcine-v<NEW_VERSION>.zip  (<size>)
Pushed   : <yes / no — skipped / no — no remote>
GH Release: <URL / not created>
───────────────────────────────────────────────
Install command for users:
  bash install.sh /path/to/project
  (after cloning or downloading the zip)
───────────────────────────────────────────────
```

Note: `vallorcine-v<NEW_VERSION>.zip` is in the repo root but gitignored.
It is the distributable artifact — attach to GitHub Release or share directly.
It is not committed to git history.

`.vallorcine-source` IS committed — it tells consumers where to check
for upgrades. install.sh copies it to `.claude/.vallorcine-source` in
the target project.
