# Roadmap — the three-layer plan

Seventeen phases across three repositories, aimed at one problem: **a rule
written in prose and a rule enforced by code drift apart, because nothing binds
them.**

Every phase below is an application of a pattern this repo already contains —
the one in [`.agents/skills/ux-audit/`](../.agents/skills/ux-audit/). Nothing
here adds an external dependency, vendors anyone's prose, or installs a
third-party skill.

This doc lives here because the harness is the top layer, but the plan spans
three repos. Phases are labelled with the repo that owns them.

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
design-craft                 the task layer        (new)
  invoked when the task is THIS KIND of design work
  detect · draw · extract · critique
  ux-audit is already the first citizen
```

**The keystone is Plan 2 phase 1** — applying the registry pattern to
`guardrails/`. It turns prose into a machine registry that the edit hook, the
`validate` skill, and the whole third layer all consume. Build it first;
everything else gets easier or becomes possible.

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
an instruction to read the project's guardrails before reviewing. After Plan 2
phase 1 lands, upgrade to citing ban IDs.

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

## Plan 2 — project-starter-pack

Right architecture, wrong enforcement. The briefs are well-designed, the router
principle is sound, and the anti-pattern registries are good writing. But the
hooks hardcode a subset of that prose, and the `validate` skill asks a language
model to compute contrast ratios.

### 1. Make `guardrails/` a real registry — **keystone**

Today: five markdown files, 253 lines, prose only. Separately,
`hooks/check-anti-patterns.sh` hardcodes three CSS greps,
`hooks/check-writing-slop.sh` hardcodes three prose greps and an em-dash density
count, `hooks/guard-design.sh` hardcodes one hex check. Add a ban to the prose
and nothing detects it. Change a ban and the grep keeps enforcing the old one.

Apply the registry pattern:

- Give each ban a stable ID — `DES-04`, `WRT-11`, `UX-07`, `CODE-03`, `PRD-02`.
- Add structured fields alongside the prose that already exists: severity, a
  `detect:` expression or `manual`, the rationale, the fix.
- Write `guardrails/_format.md` stating the contract.
- Write `build-guardrails.sh` emitting `guardrails/registry.json`, failing
  loudly on a duplicate ID exactly as `build_registry.py` does.
- Hooks read the registry instead of hardcoding.

Adding a ban to the prose then **arms the detector in the same edit**. This beats
importing a foreign rule set: the rules stay ours, they live where a human reads
them, the count grows as we learn rather than arriving as a wall, and the doc
can't drift from the enforcement.

*Touches:* `guardrails/*.md` (+ `_format.md`), new `build-guardrails.sh`, all
three `hooks/*.sh`, `test.sh`, `skills/validate/SKILL.md`.
*Done when:* a new ban with a `detect:` field is enforced by the hook with no
other edit, and `test.sh` fails on a duplicate ID.

### 2. Fixtures — catch false positives, not just misses

A grep-based linter dies of false positives, not of missing rules. The hook
comments already show this is understood: *"'robust' and 'leverage' are excluded
because tech docs use them honestly."* That judgement lives in a comment and is
enforced by nothing.

`check_fixtures.py`'s `must_find` / `must_not_find` shape is the instrument. For
each ban with a `detect:` expression, ship a minimal file that must trip it and a
clean counterpart that must not.

*Touches:* new `fixtures/guardrails/<ban-id>/{trips,clean}`, new
`check-guardrail-fixtures.sh`, `test.sh`, CI.
*Done when:* every `detect:` ban has both fixtures, and tightening a regex that
breaks a clean fixture fails CI.

### 3. Compute the contrast instead of asking for it

`skills/validate/SKILL.md` Mode A already names the exact work: check
`foreground/background`, `muted/background`, `accent/background`,
`accentForeground/accent` at 4.5:1, and `borderStrong/background` at 3:1 per WCAG
1.4.11 — *"in every theme block the file ships. Compute the contrast, don't
eyeball it."*

That spec is complete and correct, and it's handed to a language model as
arithmetic on OKLCH values. Make it a script: `validate-tokens.sh` resolves the
references, walks every theme block in `DESIGN.json`, computes the five pairs,
exits 1 with the failing pair and its ratio. The skill then *runs* it. Same rule
as `ux-audit`: no numeric claim without measured evidence.

*Touches:* new `scripts/validate-tokens.sh`, `skills/validate/SKILL.md` Mode A,
`commands/validate.md`, `test.sh`.
*Done when:* `examples/saga-reader/DESIGN.json` passes, and a deliberately
failing pair exits 1 naming the pair and the ratio.

### 4. Write down the `WRITING.md` boundary

Once Plan 1 phase 1 lands there are prose rules in two repos and the boundary is
implicit. State it in both directions:

- **`WRITING.md` governs words the product ships** — UI labels, errors, empty
  states, docs, marketing, release notes.
- **The harness governs words the agent says** — replies, PR bodies, commits,
  changelog entries, report artifacts.

Then delete the overlap.

*Touches:* `guardrails/writing-anti-patterns.md` preamble,
`templates/WRITING.template.md`, `README.md`.
*Done when:* each prose rule lives in exactly one repo and both files name the
boundary.

### 5. Later — grow our own reference corpus

One worked example ships, `examples/saga-reader/`, and it does real work —
`test.sh` checks it's a complete, placeholder-free render matching the templates.
That makes it a regression fixture, but one example isn't a corpus, and a corpus
is what stops the model reaching for an average.

Extend `extract` so it can write a reference `DESIGN.md` + `DESIGN.json` pair
from a project already shipped, and accumulate those in `examples/`. Three or
four real identities of our own beat any borrowed collection — they're the ones
we can defend in a review and the ones `validate` was tuned against.

*Touches:* `skills/extract/SKILL.md`, `examples/`, `test.sh`.

---

## Plan 3 — design-craft, the task layer

The third layer already has one inhabitant. `ux-audit` is not a harness feature
and not a project brief — it's invoked when the task is *audit this screen*, it
carries its own corpus, scripts, and tests, and it degrades gracefully when the
project has no briefs. That is what a layer-3 skill is.

The layer doesn't need inventing. It needs **naming, specifying, and
populating** — and the specification is a description of what's already built.

### 1. Write the shape spec

Before any second skill, extract the shape from `ux-audit` into a
`SKILL-SHAPE.md` every skill in the layer is built against. This is what makes it
a layer rather than a folder of unrelated skills.

- **SKILL.md** — trigger-rich description, explicit progressive-disclosure tiers
  naming which files load when, and a stated "never load" set.
- **references/** — prose corpus, `_format.md` contract, generated
  `registry.json`, stable immutable IDs.
- **scripts/** — deterministic measurement wherever measurement is possible; a
  validator for the skill's own output; stdlib-only and offline; frozen CLI
  contracts in `scripts/README.md`.
- **fixtures/** — inputs plus `expected.json` with must-find, must-not-find, and
  tolerances; a checker that exits 1.
- **assets/** — output template, self-contained, zero network requests.
- **A rubric** — named axes, a threshold, a defined action at the threshold.
- **The evidence rule** — no numeric claim without measured evidence; unmeasured
  suspicion capped in severity and phrased as suspicion.

*Creates:* new repo `design-craft` with `SKILL-SHAPE.md` and a `_template/` skeleton.
*Done when:* the spec describes `ux-audit` accurately without needing to change
it. If it doesn't, the spec is wrong, not the skill.

### 2. First new skill — `slop-detect`

Build first: it proves the cross-repo seam and closes the gap. It consumes the
guardrail registry from Plan 2 phase 1, so no rules are authored twice.

The split with the starter-pack hook matters:

| | Starter-pack hook | `slop-detect` skill |
|---|---|---|
| Trigger | Passive, on edit | Active, on request |
| Scope | One file | Whole tree, or a rendered route |
| Rules | The `detect:` regex subset | Full set, including render-dependent |
| Output | Warn-only stderr | Report with severity, ban-ID citations, score |

Same registry, two consumers, different depth — the way `ux-audit` relates to
axe-core rather than replacing it. The skill can check bans a regex never could,
because it can render the page and read computed styles.

Degrade gracefully: with no `guardrails/registry.json` in the project, fall back
to a bundled default set **and say so in the report**.

*Creates:* `design-craft/skills/slop-detect/`. *Depends on:* Plan 2 phase 1.
*Done when:* it runs against a starter-pack project, cites ban IDs, and its
fixtures pass — including the clean ones.

### 3. Second skill — `design-diagram`

`/verify` and `/improve` both emit findings that want diagrams, the Output
artifacts rule covers HTML and Markdown and stops, and the model's default
therefore wins. Own the medium.

The shape maps cleanly: `references/` holds one file per diagram type with a
stable ID and the rules for when it's the right type; the registry is generated;
`scripts/` validates emitted SVG structure and label geometry rather than
trusting it; `fixtures/` pair a spec with its expected structural output. Read
tokens from `DESIGN.json` when the project has one — the same seam `slop-detect`
uses, so build it once and share it.

*Creates:* `design-craft/skills/design-diagram/`, plus a shared `lib/` for token
resolution.
*Done when:* a diagram generated in a starter-pack project uses that project's
tokens and passes structural validation.

### 4. Then — `design-critique` and `design-extract`

**`design-critique`** is the pre-emit scoring pass, and the natural partner to
Plan 1 phase 4: the harness's `refuter` gets a rubric for *claims*, this gets one
for *artifacts*. Same instrument, different target. Its fixtures are artifacts
already judged, so scores can be checked against a real opinion.

**`design-extract`** is the deep counterpart to the starter pack's repo-scoped
`extract`: given a URL or screenshot, produce a `DESIGN.md` + `DESIGN.json` pair
that passes Plan 2 phase 3's token validator. That closes the loop — the layer
that consumes design systems can also produce them, and what it produces is
checkable by the layer below.

### 5. Last — migrate `ux-audit` in

Deliberately last. `ux-audit` is the reference implementation and it currently
works; moving it early risks the one proven thing in the layer to serve tidiness.
Move it once the spec has survived contact with two skills built *to* it rather
than derived *from* it — that's when the spec is real.

The migration is also the acceptance test for Plan 1 phase 6: if directory lock
mode can pin `ux-audit`'s full tree and `audit.sh` detects a single-byte change
inside it, the lock format is correct.

*Done when:* the pack installs as one locked directory and every skill's
fixtures pass in one CI run.

### Two decisions to make deliberately

- **Monorepo or repo-per-skill.** Today it's repo-per-skill — `ux-audit` lives in
  its own repo, pinned by hash. That works at one skill and gets tedious at five,
  especially since they'll share token-resolution code and a fixture runner. The
  monorepo is the right call, and it's why Plan 1 phase 6 is a hard gate rather
  than a nicety.
- **Where the registry lives.** `slop-detect` reads the guardrail registry *from
  the project*. That's correct — bans are project policy, not task craft. Resist
  bundling a canonical rule set into the skill; that recreates the same drift
  Plan 2 phase 1 exists to eliminate, just relocated. The bundled fallback is for
  projects with no starter pack, and the report should say when it was used.

---

## Sequence

The order that never leaves you blocked:

| # | Phase | Repo | Unblocks |
|---|---|---|---|
| 1 | Guardrails → registry | starter-pack | Everything. The keystone. |
| 2 | Guardrail fixtures | starter-pack | Safe rule growth |
| 3 | Prose section | harness | Every session, every tool |
| 4 | Guardrails past `/verify` | harness | `/improve`, design roles |
| 5 | Route, don't restate | harness | Stops design drift |
| 6 | Token validator | starter-pack | `design-extract`'s target |
| 7 | Lock directory mode | harness | Plan 3 entirely |
| 8 | Shape spec + repo | design-craft | Every layer-3 skill |
| 9 | `slop-detect` | design-craft | Proves the seam |
| 10 | `refuter` rubric | harness | `design-critique` |
| 11 | `evals/` | harness | Safe instruction edits |
| 12 | `design-diagram` | design-craft | Artifact policy |
| 13 | `WRITING.md` boundary | starter-pack | Prevents overlap |
| 14 | Artifact + fact policy | harness | — |
| 15 | `design-critique` / `design-extract` | design-craft | — |
| 16 | Own reference corpus | starter-pack | — |
| 17 | Migrate `ux-audit` in | design-craft | Validates phase 7 |

### If only the first three

Phases 1–3 are a coherent milestone, not just a beginning. After them:
anti-pattern rules can no longer drift from their enforcement, adding a rule is
one edit instead of two, false positives are caught by tests instead of by
noticing, and every reply in every tool has a governed shape.

Nothing after phase 3 is wasted if you stop there — it's all additive to a
foundation that already holds.

## Provenance

Derived from a review of fifteen widely-installed "anti-slop" agent skills,
read from source in August 2026. **None of them is installed, vendored, or
depended on by any phase above.** The review's value was diagnostic: it showed
which enforcement classes exist in the field, and therefore which ones this
toolchain has none of. The patterns adopted are this project's own.
