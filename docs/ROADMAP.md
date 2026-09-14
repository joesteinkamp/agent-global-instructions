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

### 1. Add a prose section to `template.md` — **shipped 2026-09-06**

Fifteen sections, none governing how the agent writes. Everything produced
*outside* a project — chat replies, PR bodies, commit messages, Change Log
entries, and the HTML artifacts `/verify` and `/improve` emit as their primary
deliverable — is ungoverned. The starter pack's `WRITING.md` deliberately
doesn't cover it; that governs words the *product* ships.

**The raw material this phase assumed does not exist.** It named the session
rating survey as the source — mine the recurring complaints and write the
section from those. In six weeks that survey produced 23 records, 22 dismissed
and one completed lesson, and that lesson has already been spent (it became the
"scale verification to the artifact" rule). The survey was removed on
2026-09-06; see `hooks/README.md`.

So this phase needs an evidence base before it needs an author. Two exist:
**corrections the user makes in-session**, which now feed the memoryOS lesson
store and are more specific than any rating, and **the prose this repo has
already shipped** — its own PR bodies, commit messages and Change Log entries
are a corpus of exactly the writing the section would govern. Whichever is used,
state it in the section's provenance line: a rule attributed to evidence that
was never consulted is the fabrication failure phase 7 exists to ban.

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

**Shipped. Provenance, as this phase requires:** the section was written from the
corrections its owner made during the 2026-09-05/06 session, not from the rating
survey — four corrections, every one of the same class. A root cause asserted
that could not explain all the evidence; a term used in a rule that was defined
nowhere; a repository reported as non-existent on a document's word; a phase
reported as unstarted after checking a working tree but not the open PRs. None
concerned length, tone, or structure. So the section governs the **truthfulness
of claims**, not style: claims name how they were established, the system is
checked rather than a description of it, and no specific is invented to fill a
slot. The two protected rules survive verbatim and are asserted by name in
`test.sh`. `/verify`'s and `/improve`'s report artifacts are named as governed
surfaces, and a project's `WRITING.md` is explicitly not overridden.

### 2. Make `guardrails/` visible past `/verify` — **shipped 2026-09-10**

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

**Shipped.** `/improve` gained the brief-discovery line `/verify` already had,
plus a registry probe that reports whether `guardrails/registry.json` is present
and says to cite ban IDs when it is. Its panel now reads the project's bans
*before* applying any rubric, and where a ban and a rubric line cover the same
ground the ban wins — it is the one with a detector attached. The three design
roles each gained a hard rule pointing at the prefix they own: `DES-*` for
`ui-designer`, `PRD-*` for `product-designer`, `UX-*` for `ux-researcher`, each
told to cite the ID rather than re-derive the objection. Codex port re-rendered.
The upgrade this phase deferred until the registry existed — citing ban IDs
rather than reading prose — is therefore done in the same pass, because the
registry shipped first.

### 3. Route instead of restating — **shipped 2026-09-10**

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

**Shipped, with the duplication named rather than guessed at.** Four rules had
counterparts in the registry: raw hex (`DES-03`), type scale (`DES-10`),
reduced-motion (`DES-22`), target size (`UX-07`). "Stay on the scales" is gone
and its ground is routed. Two things stay by design: *if the project ships a
system, it wins*, and the accessibility floor — the latter kept **because** it
partly duplicates `DES-22` and `UX-07`, since a project with no `guardrails/`
would otherwise get no a11y rule at all. Where a registry does exist, the section
now says its IDs are the citable form. `evals/BEH-08` anchors the routing rule so
a later edit that re-inlines a ban fails by name.

### 4. Give `refuter` a rubric — **shipped 2026-09-10**

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

**Shipped.** Five weighted axes — grounding, scope match, failure case,
assumption load, reproducibility — scored 0/1/2 with written anchors per level,
because coarse levels reproduce across runs where a 0–100 judgement does not.
Four verdict bands, and the threshold is an action rather than a note: below
`holds`, a claim does not enter a handoff as settled. `Scope match` at 2 is
required for `holds`, which encodes this session's own most expensive error —
a cause verified on Linux and asserted for macOS. The band wins over the math, so
an unverifiable load-bearing claim reads `unverified` whatever the weights say,
and score compression is named as a calibration failure.

The rubric is inline in the role rather than a referenced file, because the Codex
dialect is a single TOML string with no way to reference one; `test.sh` asserts
both dialects carry it. `playbooks/quality-workflows.md` places the refuter
**pre-emit** — it runs while the work is still the agent's to change, and spawning
one is explicitly *not* starting a quality workflow, so it never needs the user's
ask and cannot be reported as a `/verify` result. `evals/BEH-09` anchors it.

### 5. Build `evals/` — behavioural regression tests — **partly shipped 2026-09-06**

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

**Shipped: the anchor half.** `evals/behaviours.md` names each behaviour the
instructions exist to produce, the exact text it depends on, and where it came
from; `evals/run.sh` fails by behaviour — quoting why it exists — when that text
is deleted or reworded, and runs in CI with no model, no network and no spend.
Verified against the phase's own done-condition: replacing "Findings are never
trimmed for brevity" with a plausible "Keep findings brief" fails `BEH-04` and
exits 1. `test.sh` asserts that failure, so the instrument cannot rot into
decoration.

**Deferred: the live half, and the fork it turns on.** An anchor proves a
behaviour is *instructed*, not that it *happens*. Grading that needs a model, and
this repo's CI has no secrets, no network and no model access — so the question
is who pays and when, not how to grade. `evals/PLAN.md` states the three options
and recommends the cheapest: keep growing `behaviours.md` from real corrections,
and build the live runner once the set is worth paying to run. Each entry already
carries its `case:`, so nothing is lost by waiting. The rubric this phase asks
for is deferred with it — including its own warning that **autonomy must be
weighted as its own dimension**, for which `BEH-07` is the anchor that fails
first.

*Seeding.* This phase said to seed the first cases from the rating survey's
history. That history is 23 records, 22 of them dismissals, and the survey is
gone. Seed instead from the corrections in the memoryOS lesson store and from
behaviours this repo already asserts in prose — the autonomy dimension this
phase calls for is testable directly, with no historical data at all.

### 6. Vendored-tree integrity — **superseded 2026-09-10; the premise was wrong**

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

**This phase was wrong about ownership, and is superseded.** Checked 2026-09-10:
`skills-lock.json` is [`npx skills`](https://skills.sh)' lockfile, not a format
this repo owns, and **no script here reads it** — `install-commands.sh` names it
in a comment only. `install.sh`, `converge.sh` and `audit.sh` contain no
reference to `skillPath` or `computedHash`, so three of the four scripts this
phase lists as touched have nothing to do with the lock. Whether the upstream
tool supports a directory mode is undocumented on skills.sh and was not
determined; either way it is that tool's decision, not ours.

The *problem* was real and worse than stated. The lock pins one `skillPath` per
skill; for `ux-audit` that is `SKILL.md` while the vendored tree is **66 files**,
so 65 were pinned by nothing. It also became load-bearing rather than
theoretical once `design-craft` D1 was decided as **import-when-ready**, which
makes an import the moment integrity matters.

**Replaced by `verify-skills.sh` + `skills-manifest.json`**, which the harness
owns outright: a manifest hash per vendored tree over every file's path and
content, `--update` to re-record after a deliberate import, and `--list` to show
what is vendored. It does not touch `skills-lock.json` — that stays the upstream
tool's business. Wired into `test.sh` and CI, and the suite performs a one-byte
edit deep inside `ux-audit`'s tree in a throwaway copy and requires a non-zero
exit, so the instrument cannot rot into decoration.

The phase's original done-condition is met by a different route: a single-byte
change anywhere in the tree is detected. It no longer gates Plan 3 in the sense
this phase meant — Plan 3's own D1 decision made tree integrity a *general*
import requirement rather than a precondition for one layer.

### 7. Later — artifact policy and fingerprint memory — **artifact policy shipped 2026-09-10**

**Artifact policy — shipped.** The Output artifacts section now states when a
diagram earns its place (a mechanism, relationship or flow that prose makes the
reader hold in their head) and what it must be: inline SVG or mermaid inside the
artifact, never a raster or generated picture, labels as selectable text, legible
in both themes. It also extends the no-invented-specifics rule to shapes — a box
or arrow added to balance a composition is a false claim that happens to be
drawn. `evals/BEH-10` anchors it.

**The fabricated-fact half was already done.** It shipped in the prose section
(phase 1) as *"never invent a specific to fill a slot you created"*, which covers
the metric-in-a-slot case and names its surfaces — replies, PR bodies, commit
messages, changelog entries, and the reports `/verify` and `/improve` emit. This
phase asked for it "next to the Change Log honesty rules"; it landed in a section
that governs all of those at once, which is the better home. Nothing further is
owed here.

**Fingerprint memory** remains open — nothing records the *shape* of what was
produced, so nothing stops session twelve's artifact from having session three's
structure.

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


## Plan 3 — design-craft, the task layer · **M0–M2 shipped; stopped there**

**Shipped, then deliberately stopped.** [`design-craft`](https://github.com/joesteinkamp/design-craft)
carries M0 (a gate proven able to fail, frozen dual-homed contracts, CI), M1 (the
shape spec, the `_template/` skeleton, the trigger ledger, and `check_shape.py`
which exits 0 against an unmodified `ux-audit`), and M2 (`lib/fixtures.py`, proven
byte-identical to the implementation it was extracted from).

**M3 onward is not proceeding** (2026-09-14, owner). `design-diagram` was to be the
layer's second skill; the owner does not want it. M4, M5 and M6 stop with it —
export has nothing to export, `slop-detect` was already conditional and never
approved, and the disposition review reviews a populated layer.

Two things had already narrowed the case, and are worth keeping because they
generalise. The design plan's §7 concluded the evidence supported *a spec and two
skills, not a layer of five*. And the gap `design-diagram` existed to fill — a
diagram falling through to whatever the model reached for — was substantially
closed by **a rule instead of a skill**: Plan 1 phase 7's artifact policy. A rule
costs nothing to maintain; a skill costs a corpus, a validator, fixtures and a
gate. That trade is worth checking before any future phase proposes a skill.

What was built stands without a second inhabitant: a working description of the
layer-3 pattern, with a command that proves the description is accurate against a
real skill.

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

The order that never leaves you blocked. Within a repo, that repo's own plan is
the authority on ordering; this table is the cross-repo view.

**Status, 2026-09-14 — the plan is closed out.** Every harness row is shipped
except `evals/`'s live half (deferred on a spend decision, see `evals/PLAN.md`) and
fingerprint memory inside row 14. `project-starter-pack` is complete except row 15,
a feature rather than a cleanup. `design-craft` shipped M0–M2 and stopped there by
decision: rows 9 and 12 are not proceeding, and row 16 was already closed by D4.

The three-layer thesis held. What it produced, measured against its own premise —
*a rule written in prose and a rule enforced by code drift apart, because nothing
binds them* — is that every layer now has something that binds them: the guardrail
registry arms a detector in the same edit as a ban, `evals/` fails by behaviour
when a rule is edited away, `verify-skills.sh` catches a byte inside a vendored
tree, and `check_shape.py` proves a spec describes a real skill.

| # | Phase | Repo | Status | Unblocks |
|---|---|---|---|---|
| 1 | Guardrails → registry | starter-pack | **Shipped** | The keystone — see the note below |
| 2 | Guardrail fixtures | starter-pack | **Shipped** | Safe rule growth |
| 3 | Prose section | harness | **Shipped** | Every session, every tool |
| 4 | Guardrails past `/verify` | harness | **Shipped** | `/improve`, design roles |
| 5 | Route, don't restate | harness | **Shipped** | Stops design drift |
| 6 | Token validator | starter-pack | **Shipped** | `design-extract`'s target |
| 7 | Vendored-tree integrity | harness | **Shipped** (superseded the lock-schema plan) | Safe imports, everywhere |
| 8 | Shape spec + repo | design-craft | **Shipped** (M0–M2) | Every layer-3 skill |
| 9 | Second skill | design-craft | **Stopped** — owner does not want `design-diagram` | — |
| 10 | `refuter` rubric | harness | **Shipped** | `design-critique` |
| 11 | `evals/` | harness | **Anchors shipped**; live half deferred on a spend decision | Safe instruction edits |
| 12 | Remaining layer-3 skills | design-craft | **Stopped** with row 9 | — |
| 13 | `WRITING.md` boundary | starter-pack | Open | Prevents overlap |
| 14 | Artifact + fact policy | harness | **Shipped** (fact half landed in row 3) | — |
| 15 | Own reference corpus | starter-pack | Open | — |
| 16 | Migrate `ux-audit` in | design-craft | **Closed** — D4 decided: imported, never migrated | — |

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
