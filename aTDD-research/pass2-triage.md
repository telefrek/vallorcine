# Pass 2 — Concern Triage

You are triaging which concern areas apply to each construct. This is a
classification task — read each construct's code and decide which concerns
are relevant. Do not perform deep analysis or look for specific bugs.

## Input

Read the construct inventory (Pass 1 output) for the full list of constructs.

Read the implementation files to understand each construct well enough to
answer the triage questions below.

If `.kb/CLAUDE.md` exists, read adversarial-finding entries. KB patterns
make you MORE sensitive — if the KB says "overflow in bounds checks is
common in this codebase," mark "Input validation" as applicable for any
construct that does arithmetic on parameters, even if the arithmetic looks
correct at first glance.

## Critical framing

The triage question for each concern is: **"COULD this be a problem here?"**
— not "does the code currently handle this?" A construct with NO validation
is the one most likely to need "Input validation: applicable." A record
with NO compact constructor is exactly the one that needs "Data integrity:
applicable."

You are identifying WHERE to look, not whether bugs exist. Err on the side
of marking applicable. A false positive costs one deep-analysis check. A
false negative means a bug is never examined.

## The 7 concern areas

For each construct, answer these triage questions with **applicable** or
**not applicable**. If applicable, add a one-phrase reason WHY.

### 1. Input validation
Could this construct receive values that are negative, zero, null, very
large, or otherwise outside the domain it assumes? This includes:
- Method parameters used in arithmetic, allocation, or indexing
- Data read from byte arrays, files, or deserialized from untrusted sources
- Values passed through from callers without re-validation
Mark applicable if the construct uses ANY external value in a way that
could fail with adversarial input, REGARDLESS of whether it currently
validates.

### 2. Data integrity
Could data be silently lost, corrupted, or misinterpreted as it passes
through this construct? This includes:
- Fields that should be preserved but might be hardcoded, defaulted, or
  dropped (e.g., a builder that ignores an input field and substitutes a
  constant — the caller gets back different data than what was stored)
- Type conversions that lose precision (long→int, double→float)
- Records or DTOs that accept any values without enforcing invariants
- Mutable state exposed through accessors without defensive copies
- Constructs that assemble output from partial input, potentially omitting
  fields that the consumer expects to be populated from the source
Mark applicable if the construct transforms, stores, or transfers data
between representations.

### 3. Contract conformance
Could callers experience behavior different from what the API promises?
This includes:
- Exception types thrown vs documented
- Return value guarantees (nullability, emptiness, ordering)
- Implicit assumptions between producer and consumer constructs
- Behavior that depends on configuration callers can't predict (e.g.,
  a writer silently using a codec the reader doesn't know about)
- Reporting methods (size, count, status, metadata) that could return
  stale or misleading values after state-changing operations
- API accepting inputs that are technically valid types but produce
  semantically nonsensical or degenerate behavior
Mark applicable if the construct has callers that depend on specific
behavior, if it interacts with another construct across a boundary,
or if it returns values that callers might use for decisions.

### 4. Concurrency safety
Could this construct be accessed from multiple threads, or does it share
state with other constructs that might be accessed concurrently?
- Shared channels, streams, or file handles (including I/O handles held by
  a parent object that multiple methods read through — e.g., a lazy reader
  whose methods all share the same underlying channel)
- Fields accessed without synchronization
- Check-then-act sequences (test a flag, then use a resource)
- close() racing with operational methods
- Multiple methods on the same object that use a shared I/O resource without
  coordination (concurrent reads from the same channel/stream/handle)
Mark applicable even if the construct is "supposed to be single-threaded"
— the question is whether concurrent access COULD happen, not whether it's
intended.

### 5. Resource lifecycle
Does this construct acquire, hold, depend on, or pass through resources
that have a lifecycle (open/close, allocate/free)?
- File channels, arenas, memory segments
- References that might outlive the scope they were allocated in
- Close methods that might race with or be called after operations
Mark applicable if the construct touches ANY resource with a lifecycle,
including receiving a resource from a caller.

### 6. Error handling
Could error paths in this construct produce wrong outcomes?
- Assert statements used as the sole validation (disabled in production)
- Catch blocks that swallow or re-wrap exceptions with wrong types
- Multi-step operations where failure partway leaves partial state
- Error messages that don't identify the actual problem
Mark applicable if the construct has ANY error path — try/catch, assert,
throws, or conditional validation.

### 7. Capacity and bounds
Could values in this construct overflow, truncate, or exceed expected
bounds at scale?
- Int arithmetic on sizes, counts, or offsets (can overflow)
- `(int) longValue` casts (truncates silently)
- Accumulators in loops (sum grows past int range)
- Allocations proportional to untrusted input sizes
Mark applicable if the construct does ANY arithmetic on sizes or counts,
or casts between numeric types.

## Output

Write the triage matrix file:

```markdown
# Triage Matrix — <feature-name>

## <TypeName> (<FileName>)

| Construct | Input | Data | Contract | Concurrency | Resource | Error | Capacity |
|-----------|-------|------|----------|-------------|----------|-------|----------|
| method1 | applicable: params used in allocation | — | — | — | — | applicable: assert guard | — |
| method2 | — | applicable: deserializes from byte[] | — | — | — | — | applicable: int accumulator |

```

One table per top-level class. Use **applicable: <reason>** or **—** for
each cell. The reason must be specific to this construct, not generic.

At the end, write a summary:

```markdown
## Summary

Total constructs: <n>
Applicable cells: <n> / <total cells>
Coverage by concern:
  1. Input validation: <n> constructs
  2. Data integrity: <n> constructs
  3. Contract conformance: <n> constructs
  4. Concurrency safety: <n> constructs
  5. Resource lifecycle: <n> constructs
  6. Error handling: <n> constructs
  7. Capacity and bounds: <n> constructs
```

Write the file and return the summary.
