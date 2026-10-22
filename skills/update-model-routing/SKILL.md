---
name: update-model-routing
description: "Regenerate this machine's model-routing data — probe which models each CLI can actually reach, price them, research their tier, and refresh the vendor-by-task table — showing the diff for approval before anything is kept"
---

Today: run `date +%Y-%m-%d`
Machine copy header: run `sed -n '/generated:begin/,/^## [A-Z]/p' "$HOME/.ai/model-routing.md" 2>/dev/null | head -12 || echo "MISSING"`
Installed CLIs: run `cat "$HOME/.ai/clis" 2>/dev/null || command -v codex agy claude agent cursor-agent 2>/dev/null | sed 's|.*/||'`
Local models: run `cat "$HOME/.ai/local-models" 2>/dev/null || echo "none registered"`

Regenerate **this machine's** routing data in `~/.ai/model-routing.md`. Use any focus supplied in the user request.

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
   `cp ~/.ai/model-routing.md ~/.ai/model-routing.prev.md`, and
   `rm -f ~/.ai/model-catalog.next.json` so a leftover from an abandoned run
   can't be mistaken for this one.
2. **List what each CLI offers.** For every CLI in the roster probe above, run
   its listing command from the "Calling each CLI" table. Skip models marked
   hidden. Collapse effort and speed variants (`-low`/`-high`/`-xhigh`/`-fast`/
   `-thinking-*`) into one row per base model: effort is never part of the tier.
   `claude` has no listing, so use its four aliases.
3. **Probe reachability, because a listing isn't proof.** For each base model in
   each CLI, make one minimal headless call (prompt `Reply with: ok`, lowest
   effort, `timeout 90`, which is `gtimeout` or the installer's
   `~/.local/bin/timeout` shim on macOS) in the CLI's documented headless form, using the
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
   lower tier rather than giving the same model two tiers. **Pins win:** if the
   snapshot's generated block has a `Pinned tiers:` line, carry it forward
   verbatim and give each pinned model its pinned tier, with the evidence and
   `pinned by user` in the row. Fan the research out
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
9. **Stage the machine-readable catalog.** Beside the markdown, write
   `~/.ai/model-catalog.next.json` (schema version 1; the format is
   `contracts/model-catalog-v1.schema.json` in the harness checkout, which lists
   every field). **Build it from the markdown block you just wrote, not from
   fresh research**, so the two can't disagree:
   - `schemaVersion` 1; `generatedAt` today as `YYYY-MM-DD`.
   - `accounts`: one `{cli, note}` per CLI's account note in `## This machine`.
     `cli` is `claude`, `codex`, `agent` (Cursor), `agy` or `lm`. Local models
     stay in `~/.ai/model-routing.local.md`, not in `models`, so add them only as
     an `lm` account note.
   - `models`: one entry per table row, **every row, in table order** (T1, then
     T2, then T3). `name`, `family` as in the row. `tier` is the bare
     `T1`/`T2`/`T3`; a row whose tier cell says "pinned" becomes `pinned: true`
     plus a `pinReason` string, otherwise `pinned: false, pinReason: null`.
     `routable` is `false` when the tier cell says "at most" or the family is
     `varies` (auto-style rows), `true` otherwise. `priceIn`/`priceOut` are
     $/Mtok numbers, `null` where the row has `—` or only a billing pool. The
     validator compares them with the row, so write a known price cell as
     `<in> / <out>` first (a billing pool note may follow it).
     `reach` has one entry per backticked command prefix in the row's
     "Reachable via" cell, same order, read with these rules (the validator
     applies the same ones, so write the commands to fit them): `cli` is the
     command's first word; `model` is the word after `--model` or `-m`, minus a
     trailing `-<low|medium|high>` or `-<lvl>` placeholder, so every command
     must carry one; `effortStyle`/`efforts` are `flag`/`[]` for `--effort`,
     `codex-config` for `-c model_reasoning_effort=<lvl>` (list the levels that
     apply), `suffix` for a slug ending `-<a|b|c>` (efforts `[a,b,c]`; for
     `-<lvl>` list the levels that apply), and `none`/`[]` otherwise. The
     table can't carry the levels behind `model_reasoning_effort=<lvl>` or a
     `-<lvl>` suffix, so the validator can't check them: it prints each one on
     an `unchecked:` line, and they reach approval only through step 10. `command`
     is the row's prefix text, for people: nothing may run it. `evidence` is the
     row's evidence cell. Stay within the schema's size limits (name and slug
     200 characters, family 80, 50 reach entries, 20 efforts, 500 models).
   - `unreachable`: the "Listed but not reachable" models with their reasons.
     Models whose reachability is still unknown go here too, with a reason that
     starts `unknown:`, because nothing may route to them yet.
   - `notRouted`: the "Listed but not routed" models with the superseding model.
   - `vendorByTask`: one `{category, tier, primary, fallback, evidence}` per
     category, with `tier` the bare required tier. Write the code review
     category as one entry per author family, its `category` being
     `code review & refutation (authored by <family>)`.
   - `sources`: each benchmark in `## Benchmarks consulted` as
     `{name, url, retrieved}`. Where a source has no URL, use the board's
     homepage you actually fetched, never a guessed one.
   Then validate it, from the harness checkout. This skill is installed as a
   symlink into the checkout, so `cd -P` into this skill's own directory and
   run `../../contracts/check-model-catalog.sh ~/.ai/model-catalog.next.json
   ~/.ai/model-routing.md`. Fix every error it prints, in the JSON (or in the
   markdown, if the markdown is what's wrong) and re-run until it exits 0.
   **If the validator can't be found or won't pass, publish nothing:** say so,
   leave the markdown for approval as before, and delete the `.next` file.
   Never write `model-catalog*.json` inside a repo checkout.
10. **Show the diff and ask.** `diff -u ~/.ai/model-routing.prev.md
   ~/.ai/model-routing.md`, plus one line per section on what moved and why, and
   every model whose reachability changed. For the catalog, show the validator's
   whole output, its `ok:` line and every `unchecked:` line, and, if
   `~/.ai/model-catalog.json` exists,
   `diff -u ~/.ai/model-catalog.json ~/.ai/model-catalog.next.json` (otherwise
   say it is new and show the model count). Every time, including on first
   publication, also show each effort list behind a suffix or `codex-config`
   reach, since those pick the exact variant that launches:
   `jq -r '.models[] | .name as $n | .reach[] | select(.effortStyle == "suffix" or .effortStyle == "codex-config") | "\($n): \(.cli) \(.model) \(.effortStyle) \(.efforts)"' ~/.ai/model-catalog.next.json`. On approval, delete the `.prev`
   snapshot and `mv ~/.ai/model-catalog.next.json ~/.ai/model-catalog.json`. On
   rejection, `mv ~/.ai/model-routing.prev.md ~/.ai/model-routing.md`, delete
   `~/.ai/model-catalog.next.json` (the published catalog is untouched), and
   stop. There's no changelog entry: nothing here is in the repo. If the stable
   method itself looks wrong (a flag changed, a gotcha is missing), say so and
   propose the repo edit to `MODEL-ROUTING.md`, since that part changes only
   through the repo.
