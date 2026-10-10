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

## Choosing within a tier

- **Independence is per model family, not per CLI.** Families: Anthropic, OpenAI, Google, xAI, Cursor (Composer). Opus through `agy` refuting Opus through `claude` is a same-model check.
- **Only route to a model marked reachable.** Model lists show models the account can't call (a free Cursor plan lists Opus but runs only `auto`). The generated table records a probe result for each model.
- **Cost means "which pool has room."** Each CLI bills its own pool: `claude` uses the Anthropic plan, `codex` uses ChatGPT quota, `agy` uses Google AI quota (*including its Claude models*), and `agent` uses Cursor's pools. Send T2/T3 fan-out to included pools first, and save the scarcest pool for T1.
- **Spread same-tier work across pools** rather than sending a whole wave to one benchmark leader and running it dry.
- **On a 429 or quota error, stay at the same tier through another CLI.** Never drop a tier to get around a quota limit.

## Calling each CLI

| CLI | List models | Pick model | Pick effort | Gotcha |
|---|---|---|---|---|
| `claude` | none: aliases `fable` `opus` `sonnet` `haiku` follow the newest model on their own | `--model <alias\|id>` | `--effort low…max` | Subagents: the Agent tool's `model` param per spawn, or `model:` in a role file |
| `codex` | `codex debug models` (JSON; `visibility: hide` = don't route) | `-m <slug>` | `-c model_reasoning_effort=<lvl>` | Headless form: see `~/.ai/orchestration.md` |
| `agy` | `agy models` | `--model <slug>` | effort suffix in the slug, or `--effort` | **`-p` must come last.** It treats the next token as the prompt, so `agy -p --model …` sends "--model" as the prompt |
| `agent` | `agent --list-models` | `--model <slug>` | in the slug (`-high`, `-xhigh`) | Free plan: named models fail with `Named models unavailable`; only `auto` runs |

<!-- generated:begin — /update-model-routing rewrites everything from here down to the end marker -->

## This machine

- **Last updated:** never. This is the repo's seed stub.

Not generated on this machine yet. Run `/update-model-routing` to fill in the
model-tier table (each reachable model with its tier, family, price, and the
exact command string per CLI) and the vendor-by-task recommendations. Until
then, use the rules above with each CLI's live model list, and assume nothing
is reachable until a call succeeds.

<!-- generated:end -->
