---
type: reference-fragment
title: Detail Companion Convention
---

# Detail Companion Convention

Some KB entries grow past the size where a single file serves the reader well.
The detail-companion convention splits such an entry into two files: a main
article that fits in a research-agent's context budget, and a `-detail.md`
companion that holds long code skeletons, extended edge cases, and active
research notes that exceed the main article's scope.

The split is a tool for context efficiency. It is NOT a tool for hiding
unfinished content or for sidestepping the schema.

## When to split

Split an entry when ALL of the following are true:

- The main article exceeds ~200 lines or ~12 000 characters.
- The overflow is concentrated in one or two sections (typically a code
  skeleton, an extended edge-case list, or a research-directions section).
- The overflow content is genuinely optional for most readers — readers asking
  "what is X" or "how does X compare to Y" should never need the detail file.

If the overflow is spread evenly across the article, the entry is too broad
for one subject and SHOULD be split into multiple subject files instead.

## Naming and placement

- Main file: `<subject>.md` at its normal location (e.g. `data-structures/caching/byte-budget-cache.md`).
- Detail file: `<subject>-detail.md` in the **same directory**.
- One main may have at most one detail companion.
- Do not nest detail companions (`<subject>-detail-detail.md` is not allowed).

## Frontmatter requirements (the part that has been silently broken)

A detail companion MUST carry frontmatter, even though it is consumed via
include from the main file. Detail files without frontmatter are invisible to
tag-overlap scans, link-rot checks, and cross-reference repair.

```yaml
---
title: "<parent title> — Detail"
type: detail-companion
companion_to: "<topic>/<category>/<subject>.md"
last_researched: "YYYY-MM-DD"   # SHOULD match parent
research_status: "<parent's status>"
applies_to: []                  # MAY be empty; parent's applies_to is canonical
---
```

The `companion_to:` field is mandatory. It points at the parent so `/curate`
can verify the link is bidirectional (parent ends with `@./<subject>-detail.md`,
companion's `companion_to:` points at parent).

## Linking from the parent

The main article includes the detail file via Claude Code's `@`-include
syntax, typically at the end of a section that would otherwise overflow:

```markdown
## code-skeleton

@./<subject>-detail.md
```

This works inside Claude Code but does NOT render in plain Markdown viewers
(e.g. GitHub web). Therefore:

- The main article MUST be useful on its own when read on the web. The detail
  file holds *additional* depth, not load-bearing primary content.
- The main article SHOULD include a one-sentence pointer at the include site
  for web readers: e.g. "Full code skeleton: see [byte-budget-cache-detail.md](byte-budget-cache-detail.md)."

## What goes in the companion

Acceptable content:
- Full code skeletons (Java/Python/Rust) longer than ~50 lines.
- Extended edge-case enumerations beyond the 5–7 most important.
- Active-research-direction notes (open questions, draft directions).
- Reference implementations with extended commentary.

Unacceptable content (move to the main article or a separate subject):
- The article's `summary`, `tradeoffs`, `practical-usage`, or `sources`.
- Anything a "what is X" / "when do I use X" / "what are the tradeoffs"
  question would need.
- Findings or audit results — those belong in adversarial-finding entries.

## Indexing

In the parent category's `CLAUDE.md`, the detail companion is NOT a separate
subject. List the parent normally; do not give the companion its own row in
the contents table. (`/curate` flags detail companions that have their own
row as index drift.)

## Validation rules `/curate` enforces

1. Every `<subject>-detail.md` has frontmatter.
2. Every `<subject>-detail.md` has `type: detail-companion` and `companion_to:`
   pointing at an existing parent.
3. Every parent that includes `@./<subject>-detail.md` has a corresponding
   detail file.
4. The category index does not list detail companions as standalone subjects.
5. Detail companions never appear in `Recently Added` in the root index
   independently of their parent.
