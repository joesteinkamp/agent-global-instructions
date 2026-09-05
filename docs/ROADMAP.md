# Roadmap — the three-layer plan

Sixteen phases across three repositories, aimed at one problem: **a rule written
in prose and a rule enforced by code drift apart, because nothing binds them.**

> **Status, 2026-09-05.** Rows 1, 2 and 6 of the sequence shipped in
> `project-starter-pack` #18 — the guardrail registry, its fixtures, and the
> token contrast validator. Row 3, the prose section, is next. `design-craft`
> exists and is fully planned; it is blocked on five decisions, not on work.

Every phase below is an application of a pattern this repo already contains —
the one in [`.agents/skills/ux-audit/`](../.agents/skills/ux-audit/). Nothing
here adds an external dependency, vendors anyone's prose, or installs a
third-party skill.

This doc lives here because the harness is the top layer, but the plan spans
three repos. Phases are labelled with the repo that owns them.

**Who owns what.** Each repo's own plan is authoritative for its phases, their
numbering, and their status — that is where the work happens and where a
contributor looks first. This document owns the cross-repo view only: the
thesis, the layer diagram, the gates between repos, and Plan 1, whose phases
belong to this repo. Where a repo has its own plan, the section below is a
pointer and a status line, never a restatement. That is this roadmap's own
"route, don't restate" rule (Plan 1 phase 3) applied to itself — the four
planning documents had already drifted into contradicting each other on build
order, on what exists, and on what was done.

## Why this exists

The harness enforces **safety** with code — `hooks/guard-paths.sh` blocks writes
to generated paths, `hooks/guard-bash.sh` trips on catastrophic shell. Those
run, and the model can't talk past them.

It enforces **quality** by asking the model nicely. Across this repo and
`project-starter-pack`, the entire anti-slop apparatus is ~253 lines of
guardrail prose plus about seven hardcoded grep rules in the starter pack's
advisory hooks. The greps duplicate a hand-picked subset of the prose, with
nothing keeping the two in step — the hook comments say so out loud
("only the near-zero-false-positive subset of the ban list").

`ux-audit` is the one place in either repo where that drift is impossible.

## The registry pattern

Extracted from `ux-audit`, which already does all seven of these:

| Move | Where it lives today |
|---|---|
| **Prose is the source.** Humans edit markdown, one file per domain, length-capped. Nobody hand-edits generated JSON. | `references/frameworks/*.md` |
| **A format contract.** States exactly what the parser expects, so a contributor can't write something unparseable by accident. | `references/frameworks/_format.md` |
| **Generation fails loudly.** `sys.exit()` on a duplicate ID, a missing frontmatter key, an invalid category. A broken source never yields a silently-wrong registry. | `scripts/build_registry.py` |
| **Stable, immutable IDs.** `NLS-01`, `WCAG-3.3.2`, `DARK-02`. Never change once published, because findings and fixtures cite them. | `references/registry.json` |
| **Output is validated.** Schema + citation checks, exit 1 with itemized errors, skill re-runs until clean. | `scripts/validate_findings.py` |
| **Fixtures are golden.** `must_find` *and* `must_not_find`, plus score tolerances. False positives are caught, not just misses. | `fixtures/*/expected.json`, `scripts/check_fixtures.py` |
| **Evidence gates claims.** "No numeric contrast/size claim without `measured:` evidence. Unmeasured suspicion ⇒ medium severity max." | `SKILL.md` §4 |

Every gap below is a place with none of these.

## The three layers

```
agent-global-instructions    the person layer      (this repo)
  what's true regardless of which project is open
  reply shape, truthfulness, safety, autonomy, memory, teams
      │  gates Plan 3 via skills-lock.json directory mode
      ▼
project-starter-pack         the project layer
  what this product is, and what it may not look or sound like
  the briefs + the anti-pattern registry
      │  gates Plan 3 (shared registry) and Plan 1 (routing target)
      ▼
design-craft                 the task layer        (planned, no skills yet)
  invoked when the task is THIS KIND of design work
  detect · draw · extract · critique
  ux-audit is already the first citizen
```

**Plan 2 phase 1 — the registry — shipped on 2026-09-05.** Prose is now a machine
registry that the edit hooks and the `validate` skill consume, so adding a ban
arms its detector in the same edit. It was called the keystone here on the
grounds that everything else depended on it; that was overstated, and the
correction is recorded under Sequence. Its value was local, immediate, and
sufficient on its own.

---

## Plan 1 — agent-global-instructions

### 1. Add a prose section to `template.md`

Fifteen sections, none governing how the agent writes. Everything produced
*outside* a project — chat replies, PR bodies, commit messages, Change Log
entries, and the HTML artifacts `/verify` and `/improve` emit as their primary
deliverable — is ungoverned. The starter pack's `WRITING.md` deliberately
doesn't cover it; that governs words the *product* ships.

The raw material is already here: `hooks/scorecard-survey.sh` has been
collecting "rate it 1–5, why, what to do differently" into memoryOS since it was
built. Mine the recurring complaints and write the section from those.

Two rules must survive the edit, because they protect existing behaviour:

- **Brevity never applies to findings.** On any review or audit, report
  everything there's evidence for and rank it — ranking is the filter, omission
  never is. Otherwise a concision rule quietly makes `/improve` report less than
  was asked for.
- **Keep hedges that carry real uncertainty.** Deleting those manufactures
  confidence, which is worse than verbosity.

*Touches:* `template.md` (new `<!--SECTION:prose-->` after Output artifacts),
`my-context.env.example`, `customize.sh`, `examples/*` re-render.
*Done when:* the section renders into all four dialects, `./test.sh` passes.

### 2. Make `guardrails/` visible past `/verify`

The string `guardrails` appears in exactly one file in this repo:
`commands/verify.md`, twice. `/improve` runs a multi-role review panel and never
mentions them. Neither does `roles/ui-designer.md`, `roles/product-designer.md`,
nor `roles/ux-researcher.md`. So the starter pack writes a design anti-pattern
registry into a project and this repo's own design reviewers never open it.

Copy `/verify`'s brief-discovery line into `/improve`; give the design-side roles
an instruction to read the project's guardrails before reviewing. **Plan 2 phase
1 has landed**, so the upgrade to citing stable ban IDs (`DES-04`, `WRT-11`) is
available immediately rather than deferred — `guardrails/registry.json` ships
the IDs, severities and `detect:` fields to cite.

*Touches:* `commands/improve.md`, `roles/{ui-designer,product-designer,ux-researcher}.md`,
then `./render-roles.sh`.
*Done when:* an `/improve` run in a starter-pack project cites a guardrail by name.

### 3. Route instead of restating

`project-starter-pack`'s README states the principle: *"AGENTS.md carries no
brief content — it routes to the briefs, so it never goes stale when a brief
changes."* That principle is correct and isn't applied one layer up.

`template.md`'s **Design system & UI** section carries content — stay on the
defined scales, don't introduce one-off values, meet WCAG 2.2 AA, compose rather
than hand-roll — and every one has a counterpart in
`guardrails/design-anti-patterns.md`. Two files, one policy, no link. That's
drift with a timer on it.

Keep here only what holds when there is *no* starter pack in the project: the
accessibility floor, and "if the project ships a system, it wins." Route the rest.

*Touches:* `template.md` `<!--SECTION:design-->`, `docs/GUIDE.md` lens 4.
*Done when:* no design rule exists in two places, and a project with no
guardrails still gets the a11y floor.

### 4. Give `refuter` a rubric

`roles/refuter.md` is the best idea in the harness — an adversarial lens on every
conclusion, sandboxed read-only, defaulting to refuted when it can't verify. It
has no scoring instrument, so its output varies run to run and can't be compared
across sessions.

Give it a fixed return contract with named axes and a stated threshold that
triggers an action, the way `references/scoring.md` does for `ux-audit`. Run it
**pre-emit** — before handoff — so it doesn't erode the explicit-only rule on
`/verify` and `/improve`.

*Touches:* `roles/refuter.md`, `./render-roles.sh`, `playbooks/quality-workflows.md`.
*Done when:* two refuter runs on the same claim produce comparable scores.

### 5. Build `evals/` — behavioural regression tests

`test.sh` is 82 KB and thorough, and it tests the **installer**: that files
render, hooks wire up, permissions merge, examples match templates. Nothing
tests whether the ~20 KB of instructions in `template.md` changes what a model
does. The changelog shows frequent instruction edits — untested changes to the
most load-bearing file in the repo.

No new methodology needed. `scripts/check_fixtures.py` is already this shape: a
case, an expected result with tolerances, a non-zero exit. Port it —
`evals/cases.jsonl` (prompt + pass criteria), `evals/rubric.md` (weighted
dimensions + blocker flag), `evals/run.sh`.

**Weight autonomy as its own dimension.** Otherwise phase 1's brevity rules
silently regress the agent into handing work back, and a shape test would never
catch it.

*Touches:* new `evals/`, `.github/workflows/ci.yml`, `README.md`.
*Done when:* a deliberately bad edit to `template.md` makes `evals/run.sh` fail.
Seed the first cases from scorecard history.

### 6. Teach `skills-lock.json` about directories — **gates Plan 3**

The lock pins one `skillPath` to one file with one SHA-256. That suits the five
skills vendored today. A layer-3 skill built to the `ux-audit` shape is a tree —
`references/`, `scripts/`, `fixtures/`, `assets/` — and vendoring only the entry
`SKILL.md` leaves every `references/` link resolving against an unpinned
upstream, defeating the point of a lock.

Add a directory mode: a `skillDir` alongside `skillPath`, with a manifest hash
computed over the sorted file list plus each file's hash. Decide it deliberately
now rather than discovering it when the first pack skill fails to install.

*Touches:* `skills-lock.json` schema, `install.sh`, `converge.sh`, `audit.sh`, `test.sh`.
*Done when:* `ux-audit` re-locks as a directory and `./audit.sh` detects a
single-byte change anywhere in its tree.

### 7. Later — artifact policy and fingerprint memory

**Artifact policy.** The Output artifacts section covers self-contained HTML and
Markdown and stops, so diagrams fall through to whatever the model reaches for.
State the policy there. Add a fabricated-fact rule next to the Change Log
honesty rules — inventing a metric to fill a slot you created is a truthfulness
failure, not a design one, and it applies equally to a report, a PR body, and a
slide.

**Fingerprint memory.** This project is built "bit by bit across sessions" —
`commands/verify.md` says so — and nothing records the *shape* of what was
produced. Nothing stops session twelve's artifact from having session three's
structure. memoryOS is the natural host; it already persists and is read at
session start. Cheapest version: stamp the structure in an HTML comment and read
the last one back.

*Touches:* `template.md` artifacts section; `hooks/memory-os.sh`, `hooks/load-memory.sh`.

---

## Plan 2 — project-starter-pack · **phases 1–3 shipped**

**Owned by [`project-starter-pack/ROADMAP.md`](https://github.com/joesteinkamp/project-starter-pack/blob/main/ROADMAP.md).** That
document is the authority on this layer's phases, their numbering, and their
status; it also records what actually happened, where the build diverged from
the plan, and two bugs only behavioural testing caught. This section is a
pointer and a status line, nothing more — restating its detail here is how the
two would drift, which is the failure this whole roadmap exists to end.

| Phase here | There | Status |
|---|---|---|
| 1. `guardrails/` → a real registry (**keystone**) | its Phase 2 | **Shipped** (#18, 2026-09-05) |
| 2. Fixtures — catch false positives, not only misses | its Phase 3 | **Shipped** (#18) |
| 3. Compute the contrast instead of asking for it | its Phase 1 | **Shipped** (#18) |
| 4. Write down the `WRITING.md` boundary | not yet planned there | Open — depends on Plan 1 phase 1 |
| 5. Later — grow our own reference corpus | its "Later" | Open |

Note the numbering does **not** line up: this roadmap ordered the phases by
dependency, the starter-pack ordered them by build sequence, and its Phase 0
("fix the drift that already exists") has no counterpart here at all. Cite the
starter-pack's numbers when working in that repo.

**What shipped:** the five prose files stay where a human authors a ban;
`build-guardrails.sh` generates `guardrails/registry.json` and fails loudly on a
duplicate or malformed ID; `guardrails/_format.md` states the contract; the
hooks read the registry instead of hardcoding a grep subset; every `detect:` ban
ships a `trips` fixture it must fire on and a `clean` one it must stay quiet on.
Verified at merge: `./test.sh` 294 → **336 passed, 0 failed** with no check
deleted or relaxed, ten live detectors proven in both directions, and
`registry.json` rebuilding byte-identically from the prose — the property the
pattern rests on. CI was deliberately not built; see that repo's Phase 4.


## Plan 3 — design-craft, the task layer · **planned, not started**

**The repo exists** — [`design-craft`](https://github.com/joesteinkamp/design-craft),
created 2026-08-27 — and holds two planning documents and no skills yet, which
its README says is deliberate. Milestone M0 has not started.

**Owned by that repo's own plans:** `docs/DESIGN-PLAN.md` (the shape spec's
contents, the routing discipline, cross-repo dependencies, six open questions
answered, five decisions reserved for you) and `docs/EXECUTION-PLAN.md`
(milestones M0–M6, each with the files it creates by path, a checkable gate, and
its cross-repo dependency). Those supersede the sketch that used to sit here:
they were written after executing `ux-audit`'s own scripts, and its README says
outright that three findings from doing so *"shape the plan more than the roadmap
does."*

**Two places this roadmap was overruled, deliberately:**

- **Build order.** This document said `slop-detect` second, to prove the
  cross-repo seam. The execution plan makes it **M5, conditional and not yet
  approved**, and builds `design-diagram` second instead — because that one
  depends on nothing unbuilt, ships as `runtime: stdlib`, and stresses the spec
  harder by being the first skill with a registry of *types* rather than
  principles.
- **Scope.** `slop-detect` is narrowed to reading a source tree, never a
  rendered page; the render-dependent bans are reported as `unmeasurable` with
  `ux-audit` named as the instrument for them.

**One premise of that ordering has since expired.** Its case rested partly on
`slop-detect` depending on *"a registry that is unbuilt, whose construction is
gated on an owner approval in another repo."* That registry shipped in
`project-starter-pack` #18 on 2026-09-05, so the dependency is now built and the
approval given. Decision D3 is worth re-deciding on the arguments that survive —
`design-diagram` still needs no `.venv` and still stresses the spec harder,
which may well be enough on its own.

**Blocked on you, not on work:** decisions D1–D5 in the design plan (monorepo vs
repo-per-skill, routing architecture, which skill is second, whether `ux-audit`
migrates at all, the repo name — settled de facto), plus `slop-detect`'s own
approval. No amount of building unblocks those.


## Sequence

The order that never leaves you blocked. **Rows 1, 2 and 6 shipped in
`project-starter-pack` #18 on 2026-09-05.** Within a repo, that repo's own plan
is the authority on ordering; this table is the cross-repo view.

| # | Phase | Repo | Status | Unblocks |
|---|---|---|---|---|
| 1 | Guardrails → registry | starter-pack | **Shipped** | The keystone — see the note below |
| 2 | Guardrail fixtures | starter-pack | **Shipped** | Safe rule growth |
| 3 | Prose section | harness | Next | Every session, every tool |
| 4 | Guardrails past `/verify` | harness | Open | `/improve`, design roles |
| 5 | Route, don't restate | harness | Open | Stops design drift |
| 6 | Token validator | starter-pack | **Shipped** | `design-extract`'s target |
| 7 | Lock directory mode | harness | Open | Plan 3 entirely |
| 8 | Shape spec + repo | design-craft | Planned (M0–M1) | Every layer-3 skill |
| 9 | Second skill | design-craft | Planned (M3); which one is decision D3 | Proves the spec |
| 10 | `refuter` rubric | harness | Open | `design-critique` |
| 11 | `evals/` | harness | Open | Safe instruction edits |
| 12 | Remaining layer-3 skills | design-craft | Planned (M4–M6) | Artifact policy |
| 13 | `WRITING.md` boundary | starter-pack | Open | Prevents overlap |
| 14 | Artifact + fact policy | harness | Open | — |
| 15 | Own reference corpus | starter-pack | Open | — |
| 16 | Migrate `ux-audit` in | design-craft | Decision D4 — may not happen | Validates row 7 |

**On "the keystone".** Row 1 was described here as unblocking *everything*. That
was overstated: design-craft's plan says the pack does *"nothing that depends on
it"* while waiting, and routed around it rather than blocking. Its real value is
local and was always sufficient on its own — adding a ban to the prose now arms
its detector in the same edit, where before it armed nothing.


### If only the first three

Rows 1–3 are a coherent milestone, not just a beginning, and **two of the three
are done.** Anti-pattern rules can no longer drift from their enforcement, and
adding a rule is one edit instead of two with false positives caught by fixtures
rather than by noticing. What remains of the milestone is row 3, the prose
section, after which every reply in every tool has a governed shape too.

Nothing after row 3 is wasted if you stop there — it is all additive to a
foundation that already holds.

## Provenance

Derived from a review of fifteen widely-installed "anti-slop" agent skills,
read from source in August 2026. **None of them is installed, vendored, or
depended on by any phase above.** The review's value was diagnostic: it showed
which enforcement classes exist in the field, and therefore which ones this
toolchain has none of. The patterns adopted are this project's own.
