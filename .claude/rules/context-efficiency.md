# Context Efficiency Principles

Design insights from the aTDD hardening sweep (2026-03-25/26) that apply to
all vallorcine skills and agents. These are rules for how we design prompts
and pipelines in this repo.

## Split phases to prevent context carry

The biggest token driver in multi-phase work is context window growth — each
turn pays for all previous turns in input tokens. A 40-turn analysis phase
means turn 40 carries turns 1-39 as input cost.

**Rule:** When a skill has distinct cognitive phases (analysis → code
generation → bookkeeping), split them into separate sessions. Each phase
writes its output to a file; the next phase reads that file instead of
inheriting the full conversation history.

**Example:** Audit Phase 1 writes spec-analysis.md. Phase 2 starts a fresh
session and reads spec-analysis.md — it gets the findings without the 40
turns of reasoning that produced them.

## Use file handoffs for condensed, targeted context

When one phase produces output that the next phase needs, write it to a
structured file rather than relying on conversation context. The file is
the compression function — it distills deep reasoning into a document that
the next phase consumes cheaply.

**Rule:** Design handoff files to be self-contained. The consuming phase
should be able to do its job by reading the handoff file + the relevant
source code, without needing the producing phase's reasoning trail.

**Example:** spec-analysis.md contains finding IDs, construct names, line
numbers, bug descriptions, and suggested test approaches — everything Phase
2 needs to write adversarial tests without re-analyzing the source.

## Cluster by work, not by file count

The unit of analytical work is a construct (class, interface, inner type),
not a file. A single 800-line file with 6 inner classes is more work than
5 files with one class each.

**Rule:** When deciding whether to chunk work, count constructs. Threshold
at ~8 constructs per chunk. Allow constructs to appear in multiple chunks
if dependency rules require it — overlap is preferable to artificial splits.

## Pre-read shared dependencies once

When multiple chunks depend on the same types, read those types once before
starting the first chunk and summarize their contracts. This avoids redundant
deep reads and reduces per-chunk context cost.

## Emit progress incrementally

Long silent analysis periods (8+ minutes) give no visibility and waste tokens
on a single massive output. Instruct agents to write preliminary findings
per file or per construct rather than accumulating everything into one output.

**Note:** Current instruction to "write findings to the user" gets batched
into one message. May need structural enforcement (e.g., explicit per-file
write-to-disk step) rather than just instructional prompting.
