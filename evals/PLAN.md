# evals — plan and the open fork

Roadmap Plan 1 phase 5. `test.sh` is 82 KB and tests the **installer**: files
render, hooks wire up, permissions merge, examples match templates. Nothing
tested whether the ~20 KB of instructions in `template.md` changes what a model
does — and the changelog shows those instructions edited constantly. Six edits
landed in a single session on 2026-09-05/06 alone.

## What is built

`behaviours.md` + `run.sh`. Every behaviour the instructions exist to produce
names the exact text it depends on, plus where the behaviour came from. Delete
or reword that rule and the run fails **by behaviour**, quoting the reason the
behaviour exists, rather than as a bare missing string in a 200-assertion suite.

Prose is the source and `run.sh` reads it directly, so there is no generated
second list to drift. That is deliberate: at seven entries a build step would be
ceremony. When a second consumer appears — a case runner, a coverage report —
generate `registry.json` from `behaviours.md` the way `build-guardrails.sh` does
in `project-starter-pack`, and fail loudly on a duplicate ID.

*Verified:* replacing "Findings are never trimmed for brevity" with a
plausible-looking "Keep findings brief" fails `BEH-04` and exits 1. That is the
roadmap's stated done-condition for this phase, and it is exactly the regression
the phase warns a concision edit would cause.

## What is not built, and the fork

**A rendered anchor proves a behaviour is *instructed*, not that it *happens*.**
That is the near half of the gap. The far half needs a live model, and it runs
into a wall worth stating rather than papering over:

CI here is `shellcheck` plus `./test.sh` on every push and PR. No secrets, no
network, no model access. **A model-in-the-loop eval can never run in it.** So
the choice is not "how do we grade a model response" but "who pays, and when":

- **Local, opt-in, deliberate.** `./evals/run.sh --live` sends each `case:` to a
  model and grades the reply against `rubric.md`. Costs real tokens on the
  owner's account every run, is non-deterministic, and gates nothing — a human
  runs it before a release or after a large instruction edit.
- **A second CI with credentials.** Deterministic cadence, catches regressions
  without anyone remembering. Requires putting an API key in repository secrets
  and accepting per-PR spend on a repo whose CI is currently free.
- **Neither.** Keep the anchor check, accept that behaviour is unverified, and
  say so — which is what this file does today.

**Recommendation: the first, when there is something to spend it on.** Seven
cases is not yet a suite worth paying to run, and a grader written before the
cases are real will fit the grader rather than the behaviour. Grow
`behaviours.md` from actual corrections until the set is worth the money, then
build the runner. The cases are already written in each entry, so nothing is
lost by waiting and the decision stays the owner's.

**The rubric that phase 5 asks for is deferred with it** — weighted dimensions
and a blocker flag are only meaningful once something scores against them. When
it is written, the phase's own warning applies: **weight autonomy as its own
dimension**, or a future concision rule regresses the agent into handing work
back and no shape test catches it. `BEH-07` is the anchor that would fail first.

## Falsifier for this instrument

If a rule can be deleted from `template.md` with every check still green, this
file is decoration. The honest test is not that `run.sh` passes — it is that
someone tries a plausible bad edit and watches it fail. Do that when adding a
behaviour, not only when adding a rule.
