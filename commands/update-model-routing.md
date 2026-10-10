---
description: Regenerate this machine's model-routing data — probe which models each CLI can actually reach, price them, research their tier, and refresh the vendor-by-task table — showing the diff for approval before anything is kept
argument-hint: [optional focus, e.g. "tiers only" or "coding categories only"]
allowed-tools: Bash(cat:*), Bash(cp:*), Bash(mv:*), Bash(rm:*), Bash(diff:*), Bash(date:*), Bash(ls:*), Bash(head:*), Bash(sed:*), Bash(grep:*), Bash(curl:*), Bash(jq:*), Bash(python3:*), Bash(timeout:*), Bash(codex:*), Bash(agy:*), Bash(agent:*), Bash(claude:*), Bash(lm:*), Read, Edit, Write, Grep, Glob, WebSearch, WebFetch, Task
---

Today: !`date +%Y-%m-%d`
Machine copy header: !`sed -n '/generated:begin/,/^## [A-Z]/p' "$HOME/.ai/model-routing.md" 2>/dev/null | head -12 || echo "MISSING"`
Installed CLIs: !`cat "$HOME/.ai/clis" 2>/dev/null || command -v codex agy claude agent cursor-agent 2>/dev/null | sed 's|.*/||'`
Local models: !`cat "$HOME/.ai/local-models" 2>/dev/null || echo "none registered"`

Regenerate **this machine's** routing data in `~/.ai/model-routing.md`. $ARGUMENTS

The file has two kinds of section. Everything **outside** the
`<!-- generated:begin … -->` / `<!-- generated:end -->` markers is the stable
method (tiers, task-to-tier rules, how to call each CLI). The repo owns it and
`customize.sh --global` installs it. **Never change a byte of it here.** Read it
first, because the tier definitions and the CLI flag table it holds are the
rules this run applies. You rewrite only what's between the markers. Nothing
this command writes is committed: the data is true for this machine and this
account only.

1. **Guard and snapshot.** If `~/.ai/model-routing.md` is missing or has no
   `generated:begin` marker, stop and say to run `./customize.sh --global`
   from the harness checkout first. Otherwise
   `cp ~/.ai/model-routing.md ~/.ai/model-routing.prev.md`.
2. **List what each CLI offers.** For every CLI in the roster probe above, run
   its listing command from the "Calling each CLI" table. Skip models marked
   hidden. Collapse effort and speed variants (`-low`/`-high`/`-xhigh`/`-fast`/
   `-thinking-*`) into one row per base model: effort is never part of the tier.
   `claude` has no listing, so use its four aliases.
3. **Probe reachability, because a listing isn't proof.** For each base model in
   each CLI, make one minimal headless call (prompt `Reply with: ok`, lowest
   effort, `timeout 90`) in the CLI's documented headless form, using the
   flag table's gotchas. Record `yes`, or `no` with the error text quoted
   briefly. If the first named model in a CLI fails with a plan-level error
   (e.g. `Named models unavailable`), mark the CLI's other named models `no`
   with the same reason rather than probing each one. Keep probes cheap and
   polite: lowest effort, stdin from `/dev/null` (a headless CLI waiting on a
   TTY hangs until the timeout), at most 3 running at once, and one CLI at a
   time per account. **A 429, quota, or timeout result is `unknown`, not `no`.**
   Retry it once after the other probes finish, and if it still fails, record
   `unknown` with the error. Only an explicit refusal (plan, permission, model
   not found) makes a model `no`.
4. **Price from an API, not from articles.** Fetch the keyless
   `https://openrouter.ai/api/v1/models` once. Map each base model to its
   OpenRouter id (`anthropic/…`, `openai/…`, `google/…`, `x-ai/…`). Convert
   per-token prices to $/Mtok in/out. A model with no match gets `—`, never a
   price from a blog. For `agent` and `agy`, add the billing pool it draws on.
5. **Tier by evidence, via web search.** For each reachable base model, find a
   current capability signal: independent boards first (Artificial Analysis,
   vals.ai, tbench.ai, LMArena, SWE-bench), vendor numbers only when nothing
   independent exists. Place it in T1/T2/T3 by the stable section's
   definitions. Every placement cites a source and the retrieval date. **One
   model, one tier**: if the evidence splits, say so in the row and pick the
   lower tier rather than giving the same model two tiers. Fan the research out
   by model family to parallel subagents, **unnamed**, since this step waits on
   what they return and a named subagent becomes a teammate (which reports
   idle, not output) wherever agent teams are enabled.
6. **Vendor by task, with evidence that's current.** For each of the seven
   categories (hard coding & refactoring, code review & refutation, deep
   research & synthesis, planning & architecture, UI/frontend, quick mechanical
   edits & cheap fan-out, long-context analysis), research the latest results
   (prefer ≤3 months old): SWE-bench Verified, Terminal-Bench, Aider polyglot,
   LMArena incl. WebDev, ARC-AGI, GPQA/HLE, MRCR. Same sourcing rules: where
   evidence conflicts or is thin, write "no clear winner", never a manufactured
   ranking. Note the harness when it materially moves a score.
7. **Rewrite only the generated block**, in this shape, ≤ ~110 lines:
   - `## This machine`: `Last updated: <today>`, the method in one line, and
     each CLI's account notes (e.g. "Cursor: free plan, `auto` only").
   - `## Model tiers`: one row per base model, columns
     `Model | Family | Tier | $/Mtok in/out | Reachable via (exact command prefix) | Evidence`.
     Order T1→T3. Put unreachable models in a short "Listed but not
     reachable" line with the reason, and superseded ones in "Listed but not
     routed", not in the table.
   - `## Vendor by task`: one block per category with
     `Tier required | Primary (CLI + model + effort) | Fallback (different pool) | Evidence`.
     The primary and fallback must both be reachable. **Code review &
     refutation has no fixed primary**, because the right reviewer depends on
     who wrote the work, which isn't known at generation time. Write that row as
     one line per author family: `Authored by <family> → <reviewer CLI + model + effort>`,
     each reviewer from a different family than its author, at T1 for the
     review that decides "done".
   - `## Benchmarks consulted`: sources plus retrieval dates.
8. **Local models: machine-local scores, separate file.** If the local-models
   probe lists entries (`name|backend|url|model|tier[|tok/s]`), score them into
   `~/.ai/model-routing.local.md`. **Quality** comes from public open-model
   benchmarks for each model tag, same sourcing rules (local quants usually run a
   little below board numbers). **Speed** is measured with `lm bench`, never
   researched. Map `strong` → T2 and `light` → T3. Correct the registry `tier`
   via `LOCAL_MODELS` in `my-context.env` if the evidence contradicts it. If no
   local models are registered, skip this step and leave no file behind.
9. **Show the diff and ask.** `diff -u ~/.ai/model-routing.prev.md
   ~/.ai/model-routing.md`, plus one line per section on what moved and why, and
   every model whose reachability changed. On approval, delete the `.prev`
   snapshot. On rejection, `mv ~/.ai/model-routing.prev.md
   ~/.ai/model-routing.md` and stop. There's no changelog entry: nothing here is
   in the repo. If the stable method itself looks wrong (a flag changed, a
   gotcha is missing), say so and propose the repo edit to `MODEL-ROUTING.md`,
   since that part changes only through the repo.
