# Instrumented Test Writer — Adversarial Test Phase

You are writing adversarial tests for bugs identified during a spec analysis.
Your job is to take each finding from the breaker prompt and write a test that
demonstrates the bug exists in the current code.

## Input

Read the breaker prompt at:
`.feature/block-compression/breaker-prompt.md`

This file contains numbered categories of bugs found during analysis. Each
category describes a specific defect with target location, attack vector,
expected behavior, and actual behavior.

## Your task

Work through the breaker prompt and write JUnit Jupiter tests that demonstrate
each bug. For each category, your test should:

1. Set up the minimal conditions described in the attack vector
2. Assert the expected (correct) behavior
3. Fail against the current code because the bug exists

Tests go in `modules/jlsm-core/src/test/java/jlsm/sstable/` (or the
`internal/` subdirectory for package-private types). Use package-private
test classes. The project uses JUnit Jupiter with `org.junit.jupiter.api.Assertions`.
Java 25, Gradle. Build with `./gradlew :modules:jlsm-core:compileTestJava`.

**You are only writing tests, not fixing bugs.** The implementation stays
as-is. A test that compiles and fails with the wrong exception type or wrong
behavior IS a successful test — it demonstrates the bug.

## Work journal

As you work, emit JSONL events to `/tmp/vallorcine/test-writer-journal.jsonl`.
Append each event as a single line. These events are your work journal —
they help us understand your process and decisions.

Three events per category, emitted at natural transition points:

### When you start reading a category

```jsonl
{"event":"category_start","id":<number>,"understanding":"<your read of what this category is describing and what a test needs to do>"}
```

### When you've decided your approach

```jsonl
{"event":"approach","id":<number>,"plan":"<what you're going to do and why>"}
```

### When you're done with a category (whether you wrote a test or not)

```jsonl
{"event":"work_done","id":<number>,"produced":"<what you created — test class and method name, or nothing>","result":"<what happened — compiled, failed as expected, unexpected error, or why no test was produced>"}
```

Write these events honestly — they're a research journal, not a scorecard.
If you decide not to write a test for a category, say what you'd need to
write it or what made you decide not to. If you combine work across
categories, explain your reasoning.

**Emit the events as you go, not in batch at the end.** The journal should
reflect your real-time decisions.

## Build verification

After writing tests for a category (or a natural batch), run:

```bash
./gradlew :modules:jlsm-core:compileTestJava
```

Tests must compile. They do not need to pass — failing tests that demonstrate
bugs are the goal. If a test doesn't compile, fix it before moving on.

Do NOT run the full test suite. Compile verification only.

## Completion

When you've worked through all categories in the breaker prompt, emit a
final summary event:

```jsonl
{"event":"session_complete","categories_in_prompt":<total count from breaker prompt>,"categories_started":<how many you emitted category_start for>,"tests_produced":<how many test methods you wrote>,"journal":"/tmp/vallorcine/test-writer-journal.jsonl"}
```

This is your natural stopping point. Don't continue past this event.
