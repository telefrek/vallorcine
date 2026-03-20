---
description: "TDD pipeline for vallorcine scripts (bash/python/node)"
argument-hint: "<description>"
---

# /script-dev "<description>"

Dev-only TDD pipeline for vallorcine script work. Follows the same test-first
discipline as /feature-quick but specialized for the multi-language hook/script
pattern used throughout this repo.

Use this when:
- Adding or modifying scripts in `scripts/`
- Adding or modifying hooks (statusline, stop hook, subagent hook, etc.)
- Changes that need bash + Python + Node.js implementations
- Changes to install.sh, MANIFEST, or settings.json hook registration

Use /ideate instead when:
- The work is broader than scripts (skills, agents, rules, etc.)
- You're designing something new that needs discussion first

---

## Step 1 — Understand the change

Read the description and determine:

1. **Which scripts are affected?** List every file in `scripts/` that will change.
2. **Is this a new script or a modification?** New scripts need all three
   implementations + wrapper + MANIFEST + install.sh entries.
3. **Which test file covers this?** Usually `tests/scenario-*.sh` or
   `tests/test-install.sh`.

Read the affected files and their test files before proceeding.

Display a brief summary:

```
SCRIPT DEV — <description>
─────────────────────────────────────────────
Files:     <list of scripts to modify/create>
Tests:     <test file(s)>
Languages: bash / python / node  (or subset)
─────────────────────────────────────────────
  Type **yes**  to proceed  ·  or: adjust
```

---

## Step 2 — Write tests first

**This step is mandatory. No implementation before tests.**

### 2a — Identify test scenarios

For each script change, identify:
- Happy path (normal operation)
- Edge cases (empty input, missing files, malformed state)
- Backwards compatibility (if changing state file formats)
- Cross-implementation parity (if bash/python/node must produce identical output)
- Error handling (permission errors, missing directories, corrupt data)

### 2b — Write the tests

Add test cases to the appropriate `tests/scenario-*.sh` file. Follow the
existing pattern:

```bash
# ── Test N: <description> ─────────────────────────────────────────
echo ""
echo "  testing: <category>"

# Setup
<prepare state>

# Execute
(cd "$PROJECT_PATH" && <run script>)

# Assert
if <condition>; then
    pass "<description>"
else
    fail "<description>" "<diagnostic>"
fi
```

**Test requirements:**
- Use `/tmp/vallorcine/*` paths (pre-granted permissions)
- Test all three language implementations if applicable
- Test malformed/corrupt input gracefully handled (exit 0, no crash)
- Test backwards compatibility with legacy shell variable format if touching state files

### 2c — Verify tests fail

Run the test file and confirm new tests fail (they test behavior that doesn't
exist yet):

```bash
bash tests/<test-file>.sh
```

Show the failure output. If tests pass before implementation, they're not
testing the right thing — rewrite them.

Display:

```
TESTS WRITTEN — <N> new tests, all failing as expected
─────────────────────────────────────────────
  Type **yes**  to proceed to implementation  ·  or: adjust tests
```

---

## Step 3 — Implement

### Multi-language implementation order

Always implement in this order:

1. **Bash first** — the fallback that must always work. No jq required for
   flat JSON objects (use `grep -o` / `sed` patterns). Shell variable
   backwards-compat via `_is_json` detection.

2. **Python second** — stdlib only (`json`, `sys`, `os`, `pathlib`,
   `datetime`). No pip dependencies. Must produce identical side effects
   (state files, log entries, ANSI output) as bash.

3. **Node.js third** — stdlib only (`fs`, `path`, `os`, `process`). No npm
   dependencies. Must produce identical side effects as bash and Python.

### Script conventions

**State files:** JSON format. Flat objects only — no nesting beyond one level.
Bash reads via `grep -o '"key":"[^"]*"' | cut -d'"' -f4`. Always detect legacy
shell variable format with `_is_json` and read it if found.

**Atomic writes:** Write to `.tmp` then `rename()` / `mv`. Prevents partial
reads by concurrent hooks.

**ANSI output:** Use `\\033[NNm` (double-escaped) in Python/Node output strings.
The wrapper scripts call `echo -e` which interprets them. This matches how bash
`echo -e` works natively.

**Error handling:** All scripts must exit 0 on any error. Hooks that crash with
nonzero exit may block Claude Code. Wrap filesystem operations in try/catch
(Python: `try/except OSError`, Node: `try {} catch {}`).

**Wrappers:** Every user-facing script has a wrapper at
`scripts/<name>-wrapper.sh` that detects runtimes and delegates:
`python3 → node → bash`. Wrappers catch errors from enhanced implementations
and fall back silently.

### Implementation checklist

For each script:
- [ ] Bash implementation works without jq (for JSON state files)
- [ ] Python implementation uses only stdlib
- [ ] Node.js implementation uses only stdlib
- [ ] All three produce identical side effects (files written, content format)
- [ ] All three exit 0 on any error condition
- [ ] Atomic writes for state files (`.tmp` + rename)
- [ ] Backwards-compat: reads legacy shell variable format if detected
- [ ] Wrapper delegates correctly

### Run tests after each implementation

```bash
bash tests/<test-file>.sh
```

Fix failures before moving to the next language.

---

## Step 4 — Review

After all tests pass, perform a self-review against these criteria:

### Performance review

Scripts run on **every assistant message** (statusline) or **every response**
(stop hook). They must be fast.

- [ ] **No unnecessary file reads** — don't read a file twice when one read
  suffices (e.g., return line count from usage parsing, don't re-read)
- [ ] **No unnecessary stat calls** — `existsSync` before `readFileSync` is
  redundant if the read has a try/catch
- [ ] **Use `max()` not `sorted()` when only the most recent file is needed**
- [ ] **Avoid spawning subprocesses** — no `child_process.exec` in Node, no
  `subprocess.run` in Python. Pure stdlib file I/O only.
- [ ] **Target: <10ms for statusline, <5ms for no-op stop hook path**

### Memory and resource review

- [ ] **No unbounded reads** — don't slurp entire large files into memory when
  line-by-line streaming works (Python: iterate file object, Node: be aware
  that `readFileSync` loads the full file)
- [ ] **No accumulation** — scripts run and exit, no long-lived state. But
  within a run, don't build arrays of all transcript entries when only a
  sum is needed.
- [ ] **Close file handles** — use `with` in Python, don't hold open FDs

### Correctness review

- [ ] **Race conditions** — state file reads/writes across concurrent hooks.
  Atomic writes mitigate but don't eliminate. Document any remaining windows.
- [ ] **Path assumptions** — hooks run from project root (`cwd`). Don't assume
  subdirectory or absolute paths unless reading from state.
- [ ] **Integer arithmetic** — `parseInt` always with radix 10 in Node.
  Token counts can exceed 32-bit — use standard Number (safe to 2^53).

### Distribution review (if new files added)

- [ ] **MANIFEST** updated with all new script paths
- [ ] **install.sh** copies new files and registers any new hooks
- [ ] **settings.json** uses wrapper scripts, not direct implementations
- [ ] **.gitignore** includes any new runtime state files
- [ ] **tests/test-install.sh** asserts new files are installed

---

## Step 5 — Final verification

Run the full test suite:

```bash
bash tests/scenario-token-tracking.sh && bash tests/test-install.sh
```

All tests must pass. Display the final count.

```
SCRIPT DEV COMPLETE
─────────────────────────────────────────────
Tests:  <N> passed, 0 failed
Files:  <list of files changed/created>
─────────────────────────────────────────────
```
