# Model routing

<!-- Two kinds of section. Everything OUTSIDE the generated block is the stable
     method: hand-edited here in the repo, copied to every machine by
     customize.sh --global. Everything INSIDE the generated block is this
     machine's data: written by /update-model-routing into
     ~/.ai/model-routing.md, never committed, never hand-edited. The repo copy
     carries only a stub there, which seeds a fresh install. -->

Routing answers three questions, in this order: **which tier does the task
need, which model family at that tier, and which CLI reaches it.** The first
question depends only on the task. The data that answers the other two goes
stale monthly, so it's generated per machine (below), never typed in by hand.

**Advisory only.** Benchmarks measure benchmarks, not your workload. Consult,
then choose freely: availability, cost, and your own observed results on this
task type outrank any row below, and the user's explicit choice always wins.

## Tiers

| Tier | For | Cost of getting it wrong |
|---|---|---|
| **T1** | Judgment: decomposing a plan, architecture, refutation that has to count, weighing contested evidence, the review that decides "done" | The whole task heads the wrong way |
| **T2** | Building against a clear brief: multi-file implementation, debugging with a repro, routine PR review, research that needs weighing, UI to a spec | One wasted attempt; a T1 review catches it |
| **T3** | Mechanical work with checkable output: search, file summaries, docs lookup, extraction, renames, formatting, first-pass triage | Almost nothing; the output gets checked anyway |

- **A tier belongs to the model, not the CLI.** A model has one tier in every CLI
  that reaches it. Name doesn't decide tier, evidence does (a "Flash" can outrank a "Pro").
- **Effort is a separate dial.** Every effort variant of a model shares its tier.
  Set effort by how much reasoning the task needs; a T1 model on low effort often
  beats a T2 model on max. Try that before moving up a tier.
- **Local models** (`lm`) sit on the same scale: `strong` counts as T2, `light` as T3.
- **A pinned tier overrides the evidence.** The generated block may carry a
  `Pinned tiers:` line, meaning the user set a model's tier by hand (e.g. because
  it runs at default effort, not max). Regeneration keeps the pin and still
  records the evidence beside it.

## Which tier a task needs

Ask in order and stop at the first that applies:

1. **Will anything check the output?** No test, reviewer, or human downstream → at least **T2**. T3 is only cheap because something checks it.
2. **Is it a judgment call?** Choosing an approach, deciding "done", refuting a claim, weighing evidence that conflicts → **T1**.
3. **Is it expensive to undo?** Schema, auth, public API, migrations, or most of the codebase → **T1 plans it**, T2 may build it.
4. **Is the brief complete?** If the worker would have to guess intent, have T1 finish the brief first, or send the task a tier up.
5. **Is it mechanical, with checkable output?** → **T3**.
6. **Otherwise** → **T2**.

- **Escalate one tier, once.** A worker that fails the same check twice, or reports low confidence, gets redone one tier up, never a third time at the same tier.
- **Floors:** refutation and the review that decides "done" are always T1, from a **different model family** than the author. A lower-tier or local model may add an *extra* review lens, never the one that counts.
- **When no cross-family T1 is reachable, do the best you can and say so.** Use the strongest reachable model from a different family, at its highest effort, as the review that counts, and tell the user in the report that it was a cross-family check below T1. Don't drop independence to keep the tier (a same-family T1 is not a substitute), and don't stall waiting for a T1.

## When the lead is below the tier

The rules above say what tier a task needs. They don't do anything unless the lead
also knows its own tier. A T2 lead that plans the work itself, and spawns
subagents that inherit its model, runs the whole job at T2 without any error.

- **Know your own tier.** Look up the model you're running as in *Model tiers*
  below. If it isn't listed, treat yourself as T2.
- **Below T1, escalate judgment instead of making it.** The T1 points are
  planning, changing approach, a contested call, being stuck after one retry,
  and deciding "done". At each one, bring in a T1 model before you commit, using
  the first path the host supports:
  1. **Claude Code's advisor**, if `advisorModel` is set. It reads the whole
     conversation, so there's no brief to write. Call it before substantive
     work, when stuck, when changing approach, and before declaring done.
  2. **A subagent with an explicit T1 model.** Claude Code: the Agent tool's
     `model` param (`opus`). Cursor: the subagent tool's model param. The
     global instructions are the user's standing request to pick a model per
     spawn, so don't wait for it to be repeated in chat.
  3. **A cross-vendor T1 delegate** from *Model tiers* (e.g. `claude -p --model
     opus`, `codex exec -m <T1 slug>`), via `~/.ai/orchestration.md`.
- **The advisor fixes the tier, not independence.** It's the same family as an
  Anthropic lead, so the review that decides "done" still goes to a different
  family (see *Floors*).
- **Delegate down, not sideways.** T3 work goes to a T3 model or a T2 at low
  effort, not to a spawn that inherits the lead's model. Inheriting is right only
  when the subtask's tier matches the lead's.
- **Say which path you used.** One line in the report, e.g. "plan checked by the
  Opus advisor", or "no T1 path available, planned at T2".

## Choosing within a tier

- **Independence is per model family, not per CLI.** Families: Anthropic, OpenAI, Google, xAI, Cursor (Composer). Opus through `agy` refuting Opus through `claude` is a same-model check.
- **Only route to a model marked reachable.** Model lists show models the account can't call (a free Cursor plan lists Opus but runs only `auto`). The generated table records a probe result for each model.
- **Cost means "which pool has room."** Each CLI bills its own pool: `claude` uses the Anthropic plan, `codex` uses ChatGPT quota, `agy` uses Google AI quota (*including its Claude models*), and `agent` uses Cursor's pools. Send T2/T3 fan-out to included pools first, and save the scarcest pool for T1.
- **Spread same-tier work across pools** rather than sending a whole wave to one benchmark leader and running it dry.
- **On a 429 or quota error, stay at the same tier through another CLI.** Never drop a tier to get around a quota limit.

## Calling each CLI

| CLI | List models | Pick model | Pick effort | Gotcha |
|---|---|---|---|---|
| `claude` | none: aliases `fable` `opus` `sonnet` `haiku` follow the newest model on their own | `--model <alias\|id>` | `--effort low…max` | Subagents: the Agent tool's `model` param per spawn, or `model:` in a role file. Advisor: `advisorModel` in settings, or `--advisor <model>` per session; it must rank at least as high as the main model |
| `codex` | `codex debug models` (JSON; `visibility: hide` = don't route) | `-m <slug>` | `-c model_reasoning_effort=<lvl>` | Headless form: see `~/.ai/orchestration.md` |
| `agy` | `agy models` | `--model <slug>` | effort suffix in the slug, or `--effort` | **`-p` must come last.** It treats the next token as the prompt, so `agy -p --model …` sends "--model" as the prompt |
| `agent` | `agent --list-models` | `--model <slug>` | in the slug (`-high`, `-xhigh`) | **Plan-dependent.** On a paid or team plan, pass the routed slug. On a free plan, named models fail with `Named models unavailable` and only `auto` runs, so pass `--model auto` explicitly, or a named default in `~/.cursor/cli-config.json` fails the same way. The `agent` account note below says which plan this machine has |

<!-- generated:begin — /update-model-routing rewrites everything from here down to the end marker -->

## This machine

- **Last updated:** never. This is the repo's seed stub.

Not generated on this machine yet. Run `/update-model-routing` to fill in the
model-tier table (each reachable model with its tier, family, price, and the
exact command string per CLI) and the vendor-by-task recommendations. Until
then, use the rules above with each CLI's live model list, and assume nothing
is reachable until a call succeeds.

<!-- generated:end -->
