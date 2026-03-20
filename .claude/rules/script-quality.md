# Script Quality Standards

These rules apply to all scripts in `scripts/` — the runtime hooks and utilities
that ship to every vallorcine user. Scripts run on every Claude response (statusline)
or every stage transition (stop hook), so performance and robustness are critical.

## Performance constraints

- **Statusline scripts: <10ms total execution** — they fire after every assistant
  message AND between tool calls. A slow statusline visibly degrades the UX.
- **Stop hook no-op path: <5ms** — most invocations detect "same stage" and exit.
  The no-op path must be two stat() calls and an exit, not file reads.
- **Stage transition path: <200ms** — acceptable since transitions happen ~6 times
  per feature. JSONL transcript parsing is the bottleneck.
- **Never spawn subprocesses from Python/Node scripts** — no `subprocess.run`,
  no `child_process.exec`. Pure stdlib file I/O only.
- **Use `max()` not `sorted()` when finding the most recent file** — avoids
  stat() calls on every file when only the newest matters.
- **Don't read a file twice** — if you need both content and line count, get both
  in one pass.

## Memory constraints

- **No unbounded memory** — don't load entire JSONL transcripts into a list/array.
  Stream line-by-line (Python: iterate file object; Node: `split('\n')` is
  acceptable since the full file is already in memory from `readFileSync`).
- **Scripts run and exit** — no long-lived state, no caching between invocations.
  All state lives in files.

## Multi-language parity

Every script in `scripts/` that has Python and Node.js implementations MUST
produce identical side effects:
- Same state file content (JSON format, same keys)
- Same token-log.md row format (8 pipe-delimited columns)
- Same ANSI escape sequences in output (using `\\033` for wrapper `echo -e`)

Wrappers (`*-wrapper.sh`) are the entry points in settings.json. They detect
runtimes at execution time and delegate: `python3 → node → bash`.

## State file format

All state files use **flat JSON objects**. No nested objects. This ensures bash
can read them with `grep -o '"key":"[^"]*"'` without jq.

Scripts MUST detect and read the **legacy shell variable format** (lines with
`key=value` and no leading `{`). On the next write, convert to JSON. This
provides backwards compatibility during upgrade.

**Atomic writes:** Always write to `.tmp` then rename. Prevents partial reads
by concurrent hooks (statusline and stop hook can fire simultaneously).

## Error handling

- **All scripts MUST exit 0** — a nonzero exit from a hook can block Claude Code
  or surface confusing error messages to users.
- **Catch all filesystem errors** — `OSError` in Python, `try {} catch {}` in
  Node, `2>/dev/null || exit 0` in bash.
- **Malformed state files must not crash** — invalid JSON, binary garbage,
  truncated writes. Read with try/catch, fall back to empty state.

## Test requirements

Every script change requires tests in `tests/scenario-*.sh`:
- **All three languages tested** — bash, Python (if `python3` available),
  Node.js (if `node` available). Use `SKIP` for unavailable runtimes.
- **Malformed input tested** — corrupt state files, empty stdin, missing dirs.
- **Backwards compatibility tested** — legacy shell variable format still works.
- **Use `/tmp/vallorcine/*` paths** — pre-granted test permissions.

New scripts also require install tests in `tests/test-install.sh`:
- File exists after install
- Wrapper referenced in settings.json
- Hooks registered if applicable
- MANIFEST entry present
