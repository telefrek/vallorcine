# Knowledge Base & Decisions Protocol

The .kb/ directory is a pull-model research knowledge base.
The .decisions/ directory is a pull-model architecture decision store.

Structure:
  .kb/<topic>/<category>/<subject>.md
  .decisions/<problem-slug>/{constraints,evaluation,adr,log}.md

## Rules for all Claude Code sessions
- Do NOT proactively scan or read .kb/ or .decisions/ contents
- Do NOT load files from either directory unless the current task requires them
- Navigate via indexes: .kb/CLAUDE.md → topic → category → subject file
- Load only the specific file(s) needed — not siblings, not parents
- Only the Research Agent may write to .kb/
- Only the Architect Agent may write to .decisions/

## To load KB content
  /kb lookup <topic> <category> <subject>

## To load a decision
  Read .decisions/CLAUDE.md → .decisions/<slug>/adr.md

## KB → code citation convention

Source files SHOULD declare which KB articles informed them. A future reader
of `modules/auth/KeyStore.java` should be able to find the research that
explains the design without grepping the KB.

Comment forms:
- `// KB: <path>` for languages with `//` comments (Java, JS, TS, Go, Rust, C, C++)
- `# KB: <path>` for Python, Bash, Ruby, Perl
- `<!-- KB: <path> -->` for HTML, XML, Markdown

Multiple citations may appear comma-separated on one line, OR on separate
`KB:` lines:

```java
// KB: .kb/algorithms/encryption/three-level-keys.md
// KB: .kb/patterns/validation/silent-fallthrough.md
```

The `check-kb-ref.sh` PostToolUse hook (registered in `settings.json`)
fires on Write/Edit. It:

1. Auto-disables when `.kb/` has no entries beyond `_refs/` (projects that
   don't use the KB are not nagged).
2. Validates that each cited path exists.
3. Validates that the cited entry's `applies_to:` includes the file path.
4. When no citation is present and at least one KB entry's `applies_to`
   covers the file path, suggests those entries.

`/curate` Analysis 26 closes the loop after the fact: it scans changed
source files for `KB:` citations and flags drift the hook missed
(citation predates an entry rename, kit installed mid-stream, etc.).
