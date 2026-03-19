# Showcase Pipeline — Test Plan

Bugs found and fixed during development. Each section describes the bug,
the fix, and how to write a regression test. Tests should use synthetic
Token/TokenStream/Node objects — no real JSONL files needed.

## Future: vallorcine version tracking

Showcase articles should show which vallorcine version was used. Currently
the JSONL logs don't capture this. Need to write the vallorcine version
somewhere during sessions (e.g., status.md, a dedicated token, or a
version stamp file) so the tokenizer can extract it.

---

## parse.py

### 1. Trailing phases from other features bleed through

**Bug:** After a feature's retro, `in_feature` stayed `True`. Subsequent
`/feature-domains` (no args) from a different feature was kept as "pipeline
continuation."

**Fix (two layers):**
- `build_phase` rejects commands where args are present but don't contain
  the target slug (line: `elif cmd_args and feature_slug not in cmd_args`).
- `in_feature` state machine treats `resume` without slug as a different
  feature, and `retro`/`complete` as terminal stages that reset `in_feature`.

**Test:** Build a token stream with:
1. `/feature slug-a` → some tokens
2. `/feature-domains` → tokens
3. `/feature-retro` → tokens
4. `/feature-domains` → tokens (different feature, no args)

Parse with `feature_slug="slug-a"`. Assert phases 0-2 are kept, phase 3 is
excluded.

### 2. Coordination phase duration included crash gap

**Bug:** Phase duration was `last_token_ts - first_token_ts`, which included
multi-hour crash gaps when `session_end → session_start` pairs were inside
the phase's tokens.

**Fix:** `_compute_idle_time` detects crash gaps (session_end → session_start)
and subtracts them.

**Test:** Build tokens with timestamps:
- `agent_prose` at T+0
- `session_end` at T+10min
- `session_start` at T+70min (60 min crash gap)
- `agent_prose` at T+80min

Build phase, assert `duration_ms ≈ 20min` (not 80min).

### 3. User wait time inflated durations

**Bug:** Phase duration included time the user spent reading and typing.
A 3-minute scoping phase showed as 9 minutes because the user took 6
minutes to read and respond.

**Fix:** `_compute_idle_time` detects assistant→user gaps and subtracts them.

**Test:** Build tokens:
- `command` at T+0
- `agent_prose` at T+5s
- `user_text` at T+65s (60s user wait)
- `agent_prose` at T+70s

Build phase, assert `duration_ms ≈ 10s` (not 65s). The 60s gap between
agent_prose and user_text is subtracted.

### 4. Crashed subagent inflated phase duration

**Bug:** A `subagent_start` with no matching `subagent_result` before a
`session_end` meant the subagent was running when the session crashed.
The 8-hour gap was counted as work time.

**Fix:** `_compute_idle_time` tracks pending subagents and subtracts the
gap between last work token and session_end when subagents are unmatched.

**Test:** Build tokens:
- `agent_prose` at T+0
- `subagent_start` at T+1min
- `session_end` at T+481min (8 hours later, subagent crashed)
- `session_start` at T+482min

Build phase, assert duration is ~1min (not 482min).

### 5. `_has_slug` stringified entire data dicts

**Bug:** `str(n.data)` allocated a temporary string for every node's data
dict just to check for slug presence. Not a correctness bug but a
performance issue.

**Fix:** Check `n.data.values()` directly for string values containing slug.

**Test:** Build a Node with `data={"key": "my-feature-slug"}`. Assert
`_has_slug([node], "my-feature-slug")` returns True. Also test with
non-string values in data (ints, lists) — should not crash.

---

## tokenizer.py

### 6. Subagent user wait time not subtracted

**Bug:** `tokenize_subagent` reported wall-clock `duration_ms` which included
time the user was away (e.g., sleeping while a permission prompt blocked
the subagent). A 4.3-hour sleep showed as subagent work time.

**Fix:** Track assistant→user gaps (>30s) and user→assistant gaps (>2min)
inside `tokenize_subagent`. Subtract from duration. Propagate via
`user_wait_ms` metadata so the parser can subtract from phase duration too.

**Test:** Create a minimal JSONL file with:
- assistant message at T+0
- user message at T+4h (permission prompt response)
- assistant message at T+4h+5s

Tokenize, assert `duration_ms ≈ 5s` and `user_wait_ms ≈ 4h`.

### 7. `find_sessions_for_feature` read entire files

**Bug:** `fh.read()` slurped multi-hundred-MB JSONL files into memory just
to check for a substring match.

**Fix:** Line-scan with `break` on first match.

**Test:** Not a correctness test — behavior is identical. Performance test
would need a large file. Skip or test that the function still finds
sessions correctly with a small test JSONL.

### 8. `detect_interest` used regex for literal substrings

**Bug:** ~600K regex calls for patterns that could use `in` checks.

**Fix:** Split into `_INTEREST_LITERALS` (fast `in`) and `_INTEREST_REGEX`
(compiled patterns). Same detection results, ~100x faster for literals.

**Test:** Assert all original patterns still match:
- `"escalation detected"` → `("escalation")`
- `"contract conflict found"` → `("escalation")`
- `"structural issue in module"` → `("refactor_finding")`
- `"cycle 3 retry"` → `("retry")`
- `"normal code review"` → `(False, None)`

---

## render_narrative.py

### 9. Box-drawing decoration leaked into conversation blockquotes

**Bug:** `clean_agent_prose` was applied to standalone prose nodes but not
to conversation exchange content. Scoping conversations showed raw
code fences with box-drawing banners.

**Fix:** Apply `clean_agent_prose` to the question field before rendering
in `_render_conversation`.

**Test:** Create a conversation node with question containing:
```
\`\`\`\n── SCOPING AGENT ───────\n\`\`\`\nWhat feature?
```
Render, assert output contains "What feature?" but not `───` or triple
backticks.

### 10. In-banner content kept trailing box-drawing

**Bug:** The `in_banner` code path in `clean_agent_prose` stripped leading
box-drawing but not trailing. Lines like `── Title ────────` became
`Title ────────`.

**Fix:** Added trailing `[─━═]{2,}` strip to the in_banner path.

**Test:** `clean_agent_prose("```\n── My Title ───────\nContent\n```")`
should return `"My Title\nContent"` with no box-drawing.

### 11. False positive test results in non-TDD phases

**Bug:** Tool results containing words like "pass", "fail", "error" were
matched as test results even in scoping/research phases where they're
grep output or file reads.

**Fix:** `_render_test_result` returns empty outside `_TDD_PHASES`
(testing, implementation, refactor, coordination, resume).

**Test:** Create a TEST_RESULT node. Render with `ctx.current_phase="scoping"`.
Assert empty output. Render with `ctx.current_phase="implementation"`.
Assert non-empty output.

### 12. Gantt chart phases all started at t=0

**Bug:** Mermaid gantt with `dateFormat X` and absolute start/end positions
rendered all bars starting from zero.

**Fix:** Switched to `dateFormat HH:mm` with cumulative minute positions
and `after` chain implied by sequential timestamps.

**Test:** Render a story with 3 phases (5min, 10min, 3min). Parse the
Mermaid output, assert phase 2 starts at `00:05`, phase 3 at `00:15`.

### 13. Gantt sessions not visually distinguished

**Bug:** All gantt bars were the same color regardless of session, making
crash boundaries invisible.

**Fix:** Phases are grouped into Mermaid `section` blocks per session.
SESSION_BREAK children trigger a new section.

**Test:** Render a story with a phase containing a SESSION_BREAK child.
Assert the Mermaid output contains `section Session 1` and
`section Session 2 (after crash)`.

### 14. Test badge showed misleading pass/fail counts

**Bug:** Hero badge showed cumulative "298 passed 290 failed" across all
TDD retry cycles. Implied half the tests were broken.

**Fix:** Changed to `count_new_tests` which sums `test_passed` from
TDD cycles — representing tests created, not intermediate noise.
Badge label changed to "new tests".

**Test:** Create two TDD_CYCLE nodes: one with test_passed=10, test_failed=5;
another with test_passed=8, test_failed=0. `count_new_tests` should return
18 (not 18 passed / 5 failed).

### 15. `/feature-complete slug` didn't reset `in_feature`

**Bug:** The terminal stage check (`retro`/`complete`) was in an `elif`
branch that was unreachable when the slug appeared in the command args.
`/feature-complete encrypt-memory-data` matched the slug check first
(setting `in_feature = True`), so the terminal reset never ran. Subsequent
phases from a different feature bled through.

**Fix:** Moved the terminal check after the main if/elif chain so it runs
regardless of how `in_feature` was set. Retro/complete are in the pipeline
continuation list to reach the check, then reset `in_feature` after being
appended.

**Test:** Build a token stream with:
1. `/feature slug-a` → tokens
2. `/feature-retro` → tokens (no args)
3. `/feature-complete slug-a` → tokens (slug in args)
4. `/feature-domains` → tokens (different feature, no args)

Parse with `feature_slug="slug-a"`. Assert phases 0-2 are kept, phase 3
is excluded.

---

## tokenizer.py (additional)

### 16. Subagent result description mismatch

**Bug:** `tokenize_subagent` got the description from `.meta.json` which
sometimes had a generic value ("subagent") instead of the real description
from the parent's Agent tool call. The parser couldn't match start/result
pairs, so TDD cycles were classified as action groups.

**Fix:** After getting `sa_token` from `tokenize_subagent`, override its
description with `agent_desc` from the parent's `pending_agents` dict.

**Test:** Create a subagent token pair where the meta file has
`description: "subagent"` but the Agent tool call had `description:
"WU-1 test-implement-refactor"`. After tokenization, the result token
should have the parent's description.

### 17. Model field empty on session_start

**Bug:** The `model` field was extracted from the first JSONL entry's
`message.model`, but the first entry is a `user` type which doesn't
have a model. The model lives on `assistant` entries.

**Fix:** Backfill: after emitting `session_start`, check subsequent
`assistant` entries and update the session_start token's model metadata
from the first one that has it.

**Test:** Create a JSONL with a user entry (no model) followed by an
assistant entry with `model: "claude-opus-4-6"`. Tokenize, assert the
session_start token has `model="claude-opus-4-6"`.

### 18. CLI version not captured

**Bug:** The Claude Code CLI version (`version` field on JSONL entries)
was not extracted during tokenization.

**Fix:** Read `entry.get("version")` during session_start emission and
store in session_start metadata as `cli_version`. Propagated through
Story dataclass to the renderer.

**Test:** Create a JSONL with `version: "2.1.78"` on entries. Tokenize,
assert session_start metadata has `cli_version="2.1.78"`.

---

## render_narrative.py (additional)

### 19. Routine confirmations polluted conversations

**Bug:** Single-word user responses like "yes", "create", "auto" were
rendered as full conversation turns, adding noise.

**Fix:** `_is_confirmation` checks against a set of known confirmation
words. `_render_conversation` and `_render_exchange` skip them.

**Test:** Render a conversation with exchanges where answers are "yes",
"create", "I want field-level encryption". Assert only the substantive
answer renders.

### 20. `<details>` content ran into summary label

**Bug:** Expanded `<details>` content had no visual gap from the summary
toggle, making them look like a single block.

**Fix:** Added `<br>` spacer after `</summary>` in all three `<details>`
block types.

**Test:** Render a prose node long enough to trigger `<details>`. Assert
output contains `<br>` between `</summary>` and the body content.

### 21. Prose `<details>` duplicated content

**Bug:** The summary showed the first line of content, and the expanded
body showed the full content including that same first line.

**Fix:** Body starts from the second line (after the summary line).

**Test:** Render a 10-line prose node. Assert the content after
`</summary>` does not repeat the summary text.

### 22. Feature slug redundant in phase titles

**Bug:** Phase titles like "Resume — encrypt-memory-data" were redundant
since the entire article is about that feature.

**Fix:** Strip `— {story.title}` from phase titles in both the heading
and the phase breakdown table.

**Test:** Render a story with title "my-feature" and a phase with title
"Resume — my-feature". Assert the heading shows "Resume" not
"Resume — my-feature".

### 23. Shields.io badges broke on hyphenated values

**Bug:** Model name `claude-opus-4-6` contained hyphens which shields.io
uses as field separators, causing 404 badge-not-found.

**Fix:** Escape hyphens as `--` and underscores as `__` before URL
encoding in the `badge()` function.

**Test:** `badge("model", "claude-opus-4-6", "blue")` should produce a
URL containing `claude--opus--4--6`.

### 24. Session count included irrelevant sessions

**Bug:** `story.sessions` included all sessions that mentioned the feature
slug anywhere (19 for table-partitioning), not just sessions that
contributed phases.

**Fix:** After phase filtering, scan session boundaries to find which
sessions contain phase timestamps. Filter `story.sessions` to only those.

**Test:** Create a token stream from 3 sessions where only 1 has phases
matching the slug. Parse, assert `story.sessions` has length 1.

### 25. Gantt sections were session-based instead of work-type-based

**Bug (design):** Original gantt used sessions as sections (Session 1,
Session 2). This showed crash boundaries but not the shape of the work.

**Fix:** Changed to work-type sections: Discovery (scoping, domains,
research, architect), Execution (planning, coordination), Delivery
(PR, retro). Crash boundaries are shown via `[!CAUTION]` alerts in
the body instead.

**Test:** Render a story with scoping, planning, and retro phases. Assert
Mermaid output contains `section Discovery`, `section Execution`,
`section Delivery`.

### 26. Retro checklist shown as escalation

**Bug:** The retro's acceptance criteria output was classified as an
escalation (keyword match on "escalat" in the text) and rendered as
a warning block, even though all criteria were met.

**Fix:** `_render_escalation` detects the retro phase and delegates to
`_render_retro_checklist`, which parses numbered items with "— met" /
"— deferred" status markers into a green success card and blue deferred
card. Remaining prose is filtered for orphaned headings.

**Test:** Create an escalation node in retro phase context with content:
```
1. Criterion A — met (details)
2. Criterion B — **deferred** (reason)
```
Render, assert green card contains "Criterion A" with ✅ and blue card
contains "Criterion B" with ⏸️.

---

## Issues found by code review agent

### 27. Corrupt meta file crashes session tokenization

**Bug:** The lazy `meta_index` builder opened every `.meta.json` and called
`json.load()` with no error handling. A single malformed or truncated meta
file (common after crashes) would raise `JSONDecodeError` and abort
tokenization of the entire session.

**Fix:** Wrapped `json.load()` in try/except, skipping corrupt meta files.

**Test:** Create a subagent dir with a valid `.meta.json` and a truncated
one (e.g., `{` with no closing brace). Tokenize a session pointing to
that dir. Assert tokenization completes without error.

### 28. Mermaid gantt breaks at >24h cumulative duration

**Bug:** Gantt used `dateFormat HH:mm` which wraps at 24:00. Features
with >24h of active work time produced invalid timestamps like `25:30`.

**Fix:** Switched to `dateFormat YYYY-MM-DD HH:mm` with a synthetic
date that increments for each day boundary. Axis still shows `%H:%M`.

**Test:** Render a story with phases totaling 25+ hours. Assert the
Mermaid gantt output contains valid timestamps and the chart renders.

### 29. Slug substring match pulls irrelevant sessions

**Bug:** `find_sessions_for_feature` used bare `slug in line` which
matched substrings — slug "log" would match "logging", "catalog", etc.

**Fix:** Boundary-aware regex requiring the slug to appear surrounded
by quotes, path separators, whitespace, or line boundaries.

**Test:** Create JSONL files: one containing `"table-partitioning"` in
a command, another containing `"table-partitioning-v2"` as a different
feature. Search for slug `"table-partitioning"`. Assert both match
(the second has the slug as a prefix with boundary after the hyphen).
Search for `"log"`. Assert a file containing only `"logging"` does NOT
match.

### 30. Subagent idle tracking keyed by description causes collisions

**Bug:** `_compute_idle_time` tracked pending subagents by description
string. Two subagents with the same description (e.g., both named
"WU-1 test-implement-refactor" in different sessions) would collide —
`pop(desc)` would remove the wrong entry, losing the other's timestamp.

**Fix:** Key by `tool_use_id` from the subagent_start metadata. Match
results by scanning pending entries for description overlap.

**Test:** Create tokens with two `subagent_start` tokens with the same
description but different `tool_use_id`s, then two matching results.
Assert idle time is computed correctly for both.

### 31. Crashed subagent idle double-counts prior gap

**Bug:** For crashed subagents, the launch timestamp was set to `prev_ts`
(the token before the subagent_start) instead of the start's own
timestamp. If there was a user wait gap before the launch, it was
counted both as user wait (assistant→user gap) and as crashed subagent
idle — double subtraction.

**Fix:** Use `t.timestamp` (the subagent_start's own timestamp) as the
launch time.

**Test:** Create tokens:
- `agent_prose` at T+0
- `user_text` at T+60s (60s user wait)
- `subagent_start` at T+65s
- `session_end` at T+365s (crashed after 5min)

Assert idle = 60s (user wait) + 300s (crashed subagent) = 360s.
Not 60s + 365s = 425s (the old double-count).

### 32. Token usage duplicated across text blocks in same message

**Bug:** When an assistant message had multiple text content blocks,
each `agent_prose` token got the full message's `usage` assigned.
Aggregation then counted the usage N times instead of once.

**Fix:** Track `usage_assigned` flag per assistant message. Only the
first text block gets the real usage; subsequent blocks get empty
`TokenUsage()`.

**Test:** Create a JSONL entry with one assistant message containing
3 text blocks, with usage `{input_tokens: 100, output_tokens: 50}`.
Tokenize, sum all token usage across the 3 resulting agent_prose tokens.
Assert total is 100 input / 50 output (not 300 / 150).

### 33. Unclosed code fence banner corrupts content

**Bug:** If agent prose had an opening `` ``` `` but no closing one,
`in_banner` stayed True for the rest of the text. The banner path
aggressively stripped leading emoji and box-drawing characters, silently
corrupting legitimate content that happened to start with those chars.

**Fix:** After processing all lines, if `in_banner` is still True,
re-process all lines without banner mode — treating the unclosed fence
as non-banner content.

**Test:** `clean_agent_prose("` `` ``` `` `\nReal content here\nMore content")`
should return `"Real content here\nMore content"` without stripping.
