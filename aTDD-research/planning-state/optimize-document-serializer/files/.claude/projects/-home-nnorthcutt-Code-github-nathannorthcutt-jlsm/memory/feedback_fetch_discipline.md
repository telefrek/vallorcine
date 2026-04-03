---
name: fetch-discipline
description: WebFetch calls during research can hang — limit to 3 sources, never block on slow fetches, skip and note failures
type: feedback
---

When doing web research, limit WebFetch to 3 sources max. Fetches can hang indefinitely on slow/unresponsive pages. If a fetch hasn't returned quickly, move on. Prefer small pages (GitHub wikis, docs sites, arxiv HTML) over large PDFs or JS-heavy pages. Note failed fetches in sources as "(not fetched — timeout/error)" rather than retrying.

**Why:** A single slow WebFetch blocked an entire research session during the streaming-block-decompression feature domain analysis (2026-03-18).

**How to apply:** During any /research session, cap fetches at 3 and run them in parallel when possible. If one hangs, the others likely provided sufficient material.
