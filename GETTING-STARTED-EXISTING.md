# Getting Started on an Existing Codebase

This document is for teams that want to bring vallorcine into a codebase
that already has real history — maybe thousands of commits, dozens of
contributors, existing tests, existing docs, existing architectural
decisions that were made but never written down. The path in
[GETTING-STARTED.md](GETTING-STARTED.md) assumes you're starting fresh.
This one assumes you're not.

The short version: **don't try to retro-spec your whole codebase on day
one.** The value of specs/KB/ADRs accrues where features touch them.
Seed the directories, capture what's obvious, and then let each new
feature pull the right context into the right place. Six months in,
you'll have a rich, curated knowledge base — and you won't have spent
a quarter "documenting" instead of shipping.

---

## The slow-adoption premise

Vallorcine's value compounds: your 5th feature is faster than your 1st
because the 1st wrote usable KB entries, usable ADRs, and usable specs
that the 5th consumes. That compounding only works if the durable
assets *are real* — research you actually did, decisions you actually
made, specs that actually describe the system.

If you retro-spec a 50K-line codebase in a three-week sprint, most of
those specs will be fiction. They'll describe what the code *seems* to
do from the outside, not what it's actually guaranteeing. Tests won't
link to them. The audit pipeline will produce false positives. Worst
case: you'll throw the whole system away because "vallorcine didn't
work for us" — when the real problem is that the inputs were never
real.

The alternative: grow the knowledge layers alongside real work, anchored
by `/curate`. Every commit you make touches some subset of the codebase.
Let vallorcine capture what's happening in *that subset*, not the rest.
Six months in, the parts of the codebase that got touched are
well-specified; the parts that didn't are unchanged. That's fine. You
weren't changing them anyway.

---

## Day 1 — install and scan

```
bash install.sh .
/setup-vallorcine
/curate --init
```

### What `/setup-vallorcine` does

Creates the four layer directories (`.kb/`, `.decisions/`, `.spec/`,
`.feature/`), writes seed index files, adds a minimal block to your
project's root `CLAUDE.md`, and generates a project config
(`.feature/project-config.md`) with build/test commands, language hints,
and team conventions if you tell it about them.

This is idempotent. If you've already done this, running it again
doesn't hurt anything — it just notices the directories exist.

### What `/curate --init` does (the important part)

Scans git history and the current tree for signals that should become
durable assets but aren't captured yet:

- **Backfill-candidate decisions** — commits whose messages imply a
  decision was made ("chose X over Y", "migrate from A to B",
  "decided to use ..."). Surfaces them as candidates you can promote to
  real ADRs via `/architect` — capturing the rationale *while the
  context is still fresh* in someone's head.
- **Research topics worth capturing** — code that references a specific
  algorithm, protocol, or library in a non-trivial way but has no KB
  entry explaining the design choice. Candidates for `/research`.
- **Implicit dependencies** — files that consistently co-change but
  aren't linked by imports or explicit contracts. Signal for missing
  interface documentation.
- **Orphaned areas** — modules with no tests, no docs, no ADRs, and
  significant churn. High-risk regions.

`/curate --init` is the *only* curate run that does a deep historical
scan. Every subsequent `/curate` is incremental — runs in minutes,
surfaces only new signals since the last scan. That makes it cheap to
run weekly.

**Crucial:** `/curate --init` surfaces *candidates*. It doesn't write
ADRs, KB entries, or specs. You pick items by number, and each picked
item routes to the right follow-up command. Many candidates you'll
skip — they weren't worth capturing. That's fine. The goal isn't 100%
capture; it's to surface the ones that *are* worth capturing.

---

## Week 1 — capture what's obvious

Work through the `/curate --init` findings. Typical items:

- **3-5 backfill decisions** that are genuinely load-bearing — the
  choice of HTTP client, the serialization format, the auth strategy.
  Promote via `/architect` or `/decisions backfill`. Don't try to
  document every minor decision.
- **1-3 research topics** that the team regularly re-explains when
  someone joins — "why we use HNSW not IVF-Flat", "how the CRDT
  reconciliation works". Capture via `/research`.
- **Skip the spec layer entirely this week.** Specs take real effort
  to write well, and the best signal for "is this spec worth writing"
  comes from a feature that needs the spec — which you don't have yet.

By end of week 1, you want:

- `.kb/` has 2-5 real entries covering the highest-value
  recurring-explanation topics.
- `.decisions/` has 3-8 ADRs backfilled for the most load-bearing
  architectural choices.
- `.spec/` is still empty. That's intentional.

This is enough to make the next feature's domain analysis non-trivially
better than it would have been without any of this.

---

## Month 1 — first new feature uses the full pipeline

Now a real feature lands. Use `/feature "<description>"` for it, even
though the rest of the codebase doesn't have specs or structured
context.

What you'll notice:

- **`/feature-domains`** finds the 2-3 ADRs and 1-2 KB entries you
  backfilled in week 1 that apply. They go into the feature brief's
  context section.
- **`/feature-plan`** writes its plan without a spec to consume (because
  you don't have one for this area yet). The plan references your
  existing code as context.
- **`/feature-test`** generates tests from the brief + domain patterns
  (no spec requirements to operationalize — yet).
- **If the feature touches sensitive logic**, this is the moment to
  write a spec. Run `/spec-author "<feature-id>" "<title>"` on the
  behavior the feature introduces — a two-pass adversarial authoring
  run that produces an APPROVED spec in a single session.
- **Audit runs against the new code,** not the whole codebase.
  Findings either get fixed or get recorded as obligations. KB entries
  get created for any adversarial patterns the audit discovered.
- **Retrospective writes back.** A KB entry or two. Maybe an ADR if
  an architectural choice got made during the feature. A narrative
  article about the arc of the work.

By end of month 1 you've shipped 1-3 features and the knowledge layers
have grown *in exactly the places the features touched*. The rest of
the codebase is unchanged. That's fine — you weren't working on the
rest of the codebase.

### The lazy-spec rule

Only write specs for behavior a feature is *introducing* or
*significantly changing*. Don't write specs for:

- Code that's been stable for 18 months and no one's planning to touch.
- "Completeness" — trying to cover every public interface.
- CRUD plumbing that's self-describing.

Do write specs for:

- New public APIs.
- Cross-cutting guarantees (encryption, consistency, auth).
- Anything where a failure mode would matter in production.
- Code you're about to significantly refactor — write the spec first,
  then the refactor is "make the tests pass" with the old code as
  reference rather than ground truth.

---

## Month 3 — work groups and `/spec-verify`

Three months in, you have:
- 15-30 KB entries covering the areas features have touched.
- 8-15 ADRs covering load-bearing decisions.
- 5-20 specs covering the behavior features have shipped.
- A `/curate` habit — incremental runs every 1-2 weeks.

Now the advanced workflows become useful.

### Use `/work` for multi-feature initiatives

When a planned initiative will span 3+ features over 2+ weeks — auth
migration, new storage backend, major refactor — use `/work` instead of
a series of one-off `/feature` runs. Work groups capture the
dependencies between features, let you plan specs before implementation
starts, and (optionally) let you run parallel WDs concurrently.

### Use `/spec-verify` when you touch specified code

If a feature touches code under an existing spec, run `/spec-verify
<spec-id>` after the implementation lands. It checks that the code
still matches what the spec claims — finds drift early, repairs either
the code or the spec based on which is correct.

This is different from the audit pass, which finds *bugs*. `/spec-verify`
finds *violations of documented behavior* — changes that broke a
contract without updating the contract.

### Run `/curate` regularly

Every 1-2 weeks. It surfaces:
- ADRs that don't match current code (drift).
- KB entries past their `last_researched` threshold.
- Specs with aging `open_obligations` (debt that's been deferred too
  long).
- Work groups that haven't moved in weeks.

Each finding routes to the right fix-up command. Don't accept every
finding — curation surfaces, humans decide.

---

## Common pitfalls

### "Let me spec the whole codebase first"

This fails. Specs written without a feature that needs them are
fiction. You'll spend a quarter writing specs that no tests reference
and no code verifies, then abandon the system because "it didn't
work."

Grow specs alongside features. The codebase doesn't need to be 100%
specified for vallorcine to be valuable — it needs the *touched* parts
specified, and the touched parts grow naturally.

### "Research is taking too long — we'll skip the KB"

KB entries compound. A single entry researched once and used in 5
features saved 4 re-researches. If `/research` is taking too long, the
symptoms are:

- You're researching things you didn't need (trust the domain analysis
  output — if it didn't commission research, it probably wasn't needed).
- Your `last_researched` threshold is too tight and entries are being
  re-researched that haven't actually gone stale.

Tune rather than skip. The compounding effect is real and measurable
on projects with 20+ entries.

### "Decisions are obvious — we don't need ADRs"

They're obvious *now, to the person who made them*. Six months later,
the new team member asks "why do we use X?" and you've lost the
context. ADRs are notes-to-future-self-and-teammates, not
ceremony.

Rule of thumb: if the decision shaped a public API, crossed module
boundaries, or involved rejecting alternatives, write the ADR.
`/decisions backfill` can pull candidates out of git history if you
haven't been doing this.

### "Every feature needs a spec"

No. `/feature` works without specs — the domain analysis pulls in
whatever context exists, and the test plan is generated from the
brief. Specs add value when:

- Multiple features will share the behavior.
- The behavior has adversarial failure modes worth enumerating.
- You want the audit pipeline to have concrete requirements to check
  against.

For a one-off internal change, `/feature` without a spec is the right
call.

### "I installed vallorcine but nothing seems different"

You probably skipped `/setup-vallorcine` and `/curate --init`. Without
those, the knowledge layers are empty and the commands have nothing to
pull context from. Run them.

If you've done both and still feel nothing's happening: try a full
`/feature` run on a real piece of work. The value shows up in the
domain analysis stage, when you see the agent actually pulling the
backfilled ADRs and KB entries into context. If it's still empty,
your `/curate --init` probably didn't surface much — either the
codebase is genuinely young (in which case start with
[GETTING-STARTED.md](GETTING-STARTED.md)) or the git history is shallow
(e.g., fresh monorepo cut from a larger tree) and `/curate --deeper`
is worth a shot.

---

## What exists → what to do

| You already have | vallorcine workflow |
|------------------|---------------------|
| Existing tests (unit, integration) | Keep them. `/feature` reuses them as a safety net; the pipeline adds new tests rather than replacing old ones. |
| Existing docs (README, ARCHITECTURE.md) | Keep them. Capture the decisions as ADRs via `/architect` or `/decisions backfill`; docs stay as narrative. |
| Existing ADRs (other systems — MADR, nygard format) | Keep them in their current location; treat `.decisions/` as the vallorcine-managed set going forward. Don't bulk-migrate. |
| Existing wiki or internal docs | Source material for `/research`. Each time you reference wiki content in a feature, capture the relevant slice as a KB entry with the wiki as the source. |
| Existing specs (OpenAPI, protobuf, types) | Orthogonal to vallorcine specs — those are *interface* specs (structural), vallorcine specs are *behavioral* (what the system guarantees). Both are useful; neither replaces the other. |
| Existing test coverage gaps | `/curate` will flag "orphaned areas" — use them as candidates for adversarial work, not guilt. |
| Existing technical debt | `/decisions backfill` captures *why* the debt exists; `/architect` deliberates *how* to pay it down. Don't pretend the debt isn't there. |
| CI/CD pipeline | Keep it. `/feature-pr` produces PRs that flow through the existing pipeline unchanged. The kit doesn't replace your CI. |

---

## Realistic timeline

| Phase | Elapsed | State |
|-------|---------|-------|
| Day 1 | 30-60 min | Installed, scanned, `/curate --init` results in hand. |
| Week 1 | 3-5 hours | 3-8 ADRs backfilled, 2-5 KB entries, no specs yet. |
| Month 1 | 1-3 features shipped | Knowledge grows in touched areas; everywhere else unchanged. |
| Month 3 | ~8-15 features | `/spec-verify` becoming useful; `/work` used for 1-2 larger initiatives. |
| Month 6 | Compounding visible | 20+ KB entries, 10+ ADRs, 10+ specs. Domain analysis pulls real context on every feature. `/curate` runs catch drift before it becomes a problem. New team members orient in hours instead of weeks. |

The timeline above assumes a team of 2-4 developers shipping regularly.
Faster teams compound faster; slower teams compound slower. The shape is
the same either way.

---

## Where to go next

- **[GETTING-STARTED.md](GETTING-STARTED.md)** — the mental model
  overview: how KB, ADRs, specs, and features relate, and the decision
  tree for what to run when.
- **[README.md](README.md)** — full command reference.
- **[DESIGN.md](DESIGN.md)** — the architecture and the ten core
  principles that shaped the kit's design.
- **[EXAMPLES.md](EXAMPLES.md)** — end-to-end walkthroughs of real
  features.

If you get stuck: run `/vallorcine-help "<what you're trying to do>"`.
It's a router — it reads your current project context, asks you one
question, and hands you the right command.
