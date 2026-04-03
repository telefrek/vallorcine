---
name: No enter-to-continue prompts
description: Empty Enter does not work in Claude Code — never use ↵ to continue prompts, require typed responses instead
type: feedback
---

Never use `↵ to continue` or empty-Enter prompts. Empty Enter does not work in Claude Code.

**Why:** The Claude Code CLI does not support blank-line-as-confirmation. The user must type something to respond.

**How to apply:** When confirmation is needed, ask the user to type `yes` to proceed or a specific alternative action word (e.g., `stop`, `skip`, `promote`). For directed tasks where the plan is clear and unambiguous, proceed without prompting. This overrides the `↵ to continue` convention in `.claude/rules/prompt-conventions.md` for all interactive prompts.
