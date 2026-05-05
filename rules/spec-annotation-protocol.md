# Spec Annotation Protocol

Always-loaded. Defines how requirements bind to code via `@spec` annotations.
Every test or implementation that satisfies a requirement loaded into the
current work plan MUST carry an `@spec` annotation. The pipeline enforces
this at exit gates — these rules tell agents the format and intent.

## The contract

When `feature-plan` (or `work-plan`) loads specs via `spec-resolve.sh`, every
requirement (R1, R2, ...) in the bundle becomes an obligation to annotate.
Closing the obligation requires at least one annotation pointing back to the
requirement, in either a test file or an implementation file. `feature-pr`
refuses to draft a PR while obligations remain open.

The annotation IS the traceability — without it, `spec-trace.sh` cannot link
requirements to code, `/spec-verify` reports false gaps, and `/curate`'s
annotation-drift analysis cannot tell live requirements from forgotten ones.

## The format

```
@spec <spec-id>.R<n>[, R<m>, R<k>] [— optional comment]
```

- `<spec-id>` is the full spec identifier as it appears in the spec file's
  frontmatter (e.g. `auth.token-validation`, `encryption.primitives-lifecycle`,
  legacy `F13`). Never abbreviate, never drop the domain prefix.
- `R<n>` matches the requirement's number (R1, R2, ..., R39h supported).
- Comma-separated when one test or method satisfies multiple requirements
  from the same spec: `@spec auth.token-validation.R3, R7, R12`.
- One annotation per spec when a method satisfies requirements from multiple
  specs: stack them on consecutive comment lines:

```python
# @spec auth.token-validation.R3
# @spec session.lifecycle.R5
def validate_session(token):
    ...
```

Free-text after `--` or `—` is ignored by the trace tool but useful for
reviewers:

```java
// @spec query.vector-index.R12 — guards the build-time invariant
private void validateIndexState() { ... }
```

## Comment syntax per language

The annotation is a plain comment in the target file's comment syntax. The
`@spec` token must appear after the comment marker, optionally preceded by
whitespace. Common forms:

| Language family       | Form                          |
|-----------------------|-------------------------------|
| Java/JS/TS/C/C++/Go/Rust/Kotlin/Scala | `// @spec ...` or `/* @spec ... */` |
| Python/Ruby/Shell     | `# @spec ...`                 |
| Lisp/Elixir           | `;; @spec ...` / `# @spec ...` |
| HTML/Markdown         | `<!-- @spec ... -->`          |

`spec-trace.sh` greps the line for `@spec` and is comment-syntax-agnostic —
any prefix that ends in whitespace before `@spec` matches.

## Where to put the annotation

**Tests:** above the test method or test class. One annotation per test, or
stack when one test exercises multiple requirements.

**Implementation:** above the method, class, or block whose behaviour
satisfies the requirement. Prefer the smallest enforcing scope — a single
guard clause that enforces R3 should carry `@spec ...R3`, not the whole
class.

If a requirement is satisfied by absence (e.g. "the system must not log
secrets") — annotate the explicit guard that prevents the prohibited
behavior, not the data flow that would have produced it.

## When the annotation belongs

Add the annotation in the SAME pipeline stage that satisfies the
requirement:

- Test writers add `@spec` while writing the failing test (test-plan
  `covers: <spec-id>.R<n>` is the write-time hint — translate it directly).
- Implementation writers add `@spec` while writing the code that makes the
  test pass. Don't wait for refactor or PR-prep stages — by then the writer
  is no longer in the relevant context.
- Refactor agents may move annotations along with the code they migrate;
  they MUST NOT delete annotations without a matching `@spec` landing on
  the new enforcement site.
- Audit's `prove-fix` stage adds `@spec` when a fix satisfies an existing
  requirement OR when the audit's apply-spec-updates step mints a new R-id
  for the just-landed fix.

## What this rule is NOT

- Not a substitute for tests. `@spec` is traceability metadata, not proof
  of behavior. The test still has to exercise the requirement.
- Not a substitute for `/spec-verify`. Verification confirms the
  annotations point at code that actually enforces what the requirement
  says — annotation alone does not prove behavior.
- Not a license to over-annotate. Annotate the enforcing site, not every
  file that touches the area.

## See also

- `scripts/spec-trace.sh` — discovers `@spec` annotations across a codebase
- `scripts/spec-coverage.sh` — pipeline-wide coverage tracker (init, update,
  gate)
- `skills/spec-verify/SKILL.md` — semantic verification that annotations
  point at correct enforcement sites
- `.feature/<slug>/spec-coverage.md` — per-feature coverage table managed by
  the pipeline; never hand-edit
