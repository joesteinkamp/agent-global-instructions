# Plan — bake tiers into model routing

**Status:** BUILT 2026-10-10, uncommitted, awaiting cross-family review and
Joe's go-ahead to commit. Grilled (decisions in §0 and §6), rival draft taken
(§6). Written 2026-10-10 by Claude (Opus 5.5).
**Joe's calls on §6:** routine PR review is T2 and the review that decides "done"
is T1. File may grow to ~180 lines. Role pinning stays out. The falsifier is a
judgment check after the first real runs, not a hard number, and nothing logs
it yet.
**Lives on:** branch `worktree-bridge-cse_01Bb2E4S1AP4EWUaTgbmx422` (host worktree).
**Scope:** make `MODEL-ROUTING.md` answer *which model* as well as *which
vendor*. Tiers aren't a separate system: it's all model routing, so it all goes
in that one file. Out of scope for now: the delegator's prompt, role pinning,
and measuring the redo rate. This plan file is temporary and gets deleted once
the work lands.

---

## 0. One file, two kinds of section (decided 2026-10-10)

Joe: "It's all model routing, so having another file makes no sense." So there's
no tier file, no rules split into the playbook, and no method split into the
command. `MODEL-ROUTING.md` holds all of it, laid out in this order:

| Section | Kind | Who writes it |
|---|---|---|
| **How to route.** Tier definitions, task-to-tier rules, the consistency rule, model family as the independence unit, effort as a separate setting | **Stable.** Changes only when the thinking changes | hand-edited in the repo; the generator keeps it **verbatim** (the same way it already keeps the caveats paragraph) |
| **How to call each CLI.** Model listing, model and effort flags (the §3 flag table) | **Stable.** Changes when a CLI's interface changes | same as above |
| **Model tiers.** One row per model: tier, family, price, which CLIs reach it | **Generated** | `/update-model-routing`, from live CLI listings + OpenRouter prices + a capability score |
| **Vendor by task.** The current seven categories | **Generated** | `/update-model-routing`, as today |

**Staying current without hand-maintenance:** the generated sections are
rebuilt from APIs and live listings, not from research someone typed in. The
machine copy `~/.ai/model-routing.md` is what agents read. The repo copy is the
stable sections plus the last approved snapshot, which serves as a seed for a
fresh install. The existing staleness rule (`orchestration.md:125`) triggers a
refresh.

**What the playbook keeps:** only its existing pointer, "consult
`~/.ai/model-routing.md`" (`orchestration.md:124`), and the staleness rule.
The local-model tier names `light`/`strong` (`orchestration.md:179`) fold into
T1/T2/T3 (probably `strong`→T2, `light`→T3) and move into the file's local-model
note, so there's one tier vocabulary.

**Size (decided 2026-10-10):** raise the command's cap from ~90 to ~130 lines.
Don't shorten the vendor-by-task evidence.

**Capability source (decided 2026-10-10): web search** on each refresh, not an
Artificial Analysis key. The generator researches a capability signal for each
listed model, with the command's existing sourcing rules (independent boards
outrank vendor numbers, every claim cited with a date, "no clear winner"
rather than a made-up ranking). Prices still come from OpenRouter's keyless
API, and availability still comes from the live CLI listings, so web search
decides only the tier.

**Defaults taken without an explicit answer (say so if wrong):** cost means
"which pool has room": T2/T3 fan-out goes to included pools (Composer, agy
quota) first, and the Anthropic plan is spent on T1. Gemini 3.8 Flash is T1 on
current evidence.

## 1. The model

The whole design is two questions, asked in this order:

1. **Which tier does this task need?** That depends only on the task, never on a vendor.
2. **Which vendor, at that tier?** That's the existing `MODEL-ROUTING.md` question
   (strength by task type, independence for review), now limited to the
   models in one tier.

Keeping these separate is what makes it maintainable. Tier rules rarely change.
The model lists change monthly. A new model release only changes the table in §3.

### Tier definitions

| Tier | What it's for | What it costs you if it's wrong |
|---|---|---|
| **T1, top** | Judgment: decomposing a plan, architecture, refutation that has to count, synthesizing contested evidence, final review before done | The whole task goes in the wrong direction |
| **T2, mid** | Building against a clear brief: multi-file implementation, debugging with a known repro, research that needs weighing, UI work against a spec | A wasted attempt; the T1 reviewer catches it |
| **T3, low** | Mechanical work with checkable output: search and find, summarizing a file, docs lookup, structured extraction, renames, formatting, first-pass triage | Nearly nothing; the output is verified anyway |

**Effort is a second, independent setting.** Within a tier, pick effort by how
much reasoning the task needs, not how much it matters. A T1 model on `low`
effort is often a better choice than a T2 model on `max`. Try that before
moving up a tier.

## 2. Task-to-tier rules (the delegator applies these, in order)

1. **Is anyone checking the output?** If nothing downstream verifies it (no
   test, no reviewer, no human), the task is **at least T2**. A T3 output is
   only cheap because something checks it.
2. **Is it a judgment call?** Choosing between approaches, deciding "done",
   refuting a claim, or weighing evidence that conflicts → **T1**.
3. **Is it expensive to undo?** Schema, auth, public API, migrations, or
   anything touching most of the codebase → **T1 plans it**, T2 may build it.
4. **Is the brief complete?** If a worker would have to infer intent, either
   send it up a tier or have T1 finish the brief first. An incomplete brief is
   what makes cheap workers expensive.
5. **Is it mechanical, with checkable output?** → **T3**.
6. **Otherwise** → **T2**.

**Escalation:** a T3 or T2 worker that fails the same check twice, or reports
low confidence, gets redone *one* tier up. It never retries at the same tier a
third time.
**Floors that never go lower:** the refuter is always T1 and from a different
vendor than the author. The final pre-done review is always T1.

## 3. Per-vendor tier table

**Source of truth is each CLI's live model list**, not public lineups. What a
user can reach depends on the account: this machine's `codex` exposes
Terra and Luna but not Sol, which is only reachable through Cursor.

| CLI | How to list models | Model flag | Effort flag |
|---|---|---|---|
| `claude` | none (aliases `fable`/`opus`/`sonnet`/`haiku`) | `--model` | `--effort` |
| `codex` | `codex debug models` | `-m` | `-c model_reasoning_effort=<lvl>` |
| `agy` | `agy models` | `--model` (effort is in the slug suffix) | `--effort` |
| `agent` | `agent --list-models` | `--model` (effort is in the slug) | in the slug |

### A listed model isn't always a reachable one (observed 2026-10-10)

`agent --list-models` lists Sol, Opus, Fable, and the rest, but calling
`agent -p --model gpt-5.6-sol-high` failed with: `ActionRequiredError: Named
models unavailable Free plans can only use Auto.` **This machine's Cursor account
is on the free plan, so every named model in the `agent` column below is
unreachable.** The only one that works is `auto`, and how it chooses isn't
documented. So Sol can't be reached at all from this machine.

So the generator can't trust a listing. For each CLI it has to make one cheap
probe call per model (or per family on CLIs with many effort slugs) and mark
the model reachable or not, with the error text. A delegator that picks an
unreachable model fails after launch, wasting a round trip.

### Draft tier assignments (research 2026-10-10)

**This table is a sample of what the generator should produce, not a file to
commit** (see §0). Its prices are already wrong in places. OpenRouter's
`/api/v1/models`, checked the same day, lists GPT-5.6 Luna at $0.20/$1.20 and
Terra at $2/$12, against the $1/$6 and $2.50/$15 below. That's why prices
have to come from an API at generation time.

Prices are $/Mtok in/out. Most come from **secondary sources** (aggregators and
blogs). The research agents couldn't load openai.com/pricing (it returned 403)
and didn't load Anthropic's or Cursor's pricing pages directly. Treat prices as
"likely" until `/update-model-routing` primary-sources them.

**Consistency rule: a tier belongs to the model, not to the CLI.** A model gets
one tier and keeps it in every CLI that offers it, and the table is laid out so
a mismatch can't happen. Effort is never part of the tier. A slug's effort
suffix (`-high`, `-low`, `-thinking-xhigh`) is how §1's second setting gets
expressed, so all effort variants of a model share its row.

| Model | Family | Tier | ~$/Mtok in/out | Reachable through |
|---|---|---|---|---|
| Fable 5.1 / Fable 5 | Anthropic | **T1** | $10/$50; usage credits on some plans | `claude` (`fable`), `agent` (`claude-fable-5-thinking-*`, no ZDR) |
| Opus 5.5 | Anthropic | **T1** | $4/$20 | `claude` (`opus`), `agy` (`claude-opus-5-5-*`), `agent` (`claude-opus-5-5-*`) |
| Opus 5 | Anthropic | **T1** | — | `agent` (`claude-opus-5-*`) |
| GPT-5.6 Sol | OpenAI | **T1** | $5/$30 | `agent` only (`gpt-5.6-sol-*`); not on this codex account |
| Gemini 3.8 Flash | Google | **T1**\* | $0.75/$3.75 promo, $1.50/$7.50 after | `agy` (`gemini-3.8-flash-*`) |
| Sonnet 5.5 | Anthropic | **T2** | $2/$10 | `claude` (`sonnet`), `agy` (`claude-sonnet-5-5-*`) |
| Sonnet 5 | Anthropic | **T2** | $2/$10 | `agent` (`claude-sonnet-5-thinking-*`) |
| GPT-5.6 Terra | OpenAI | **T2** | $2.50/$15 | `codex` (`gpt-5.6-terra`) |
| GPT-5.3 Codex | OpenAI | **T2** | $1.75/$14 | `agent` (`gpt-5.3-codex-*`) |
| Gemini 3.1 Pro | Google | **T2**\* | $2/$12 | `agy` (`gemini-3.1-pro-*`) |
| Gemini 3.7 Flash | Google | **T2** | $0.75/$3.75 promo | `agy` (`gemini-3.7-flash-*`), `agent` (`gemini-3.7-flash-high`) |
| Grok 4.7 | xAI | **T2** | — | `agent` (`grok-4.7-*`) |
| Composer 2.5 | Cursor | **T2** | included Cursor pool | `agent` (`composer-2.5`, `-fast`) |
| Haiku 5.5 | Anthropic | **T3** | not found | `claude` (`haiku`) |
| GPT-5.6 Luna | OpenAI | **T3** | $1/$6 | `codex` (`gpt-5.6-luna`), `agent` (`gpt-5.6-luna-high`) |
| Gemini 3.6 Flash | Google | **T3** | $0.75/$3.75 promo | `agy` (`gemini-3.6-flash-*`) |
| GPT-OSS 120B | OpenAI (open-weight) | **T3** | not found | `agy` (`gpt-oss-120b-medium`) |

**Listed but not routed:** these are superseded by a newer model in the same
family. `gpt-5.5` is hidden in codex, and Terra matches it.
`gpt-5.2`, `cursor-grok-4.6-*`, and `cursor-grok-4.5-high` are older versions
in `agent`. **Not models:** `gpt-reserve` (extra Luna quota), `codex-auto-review`
(a safety reviewer), and `agent`'s `auto` (a router whose choices aren't documented).

**How Gemini 3.7 Flash was placed, and the reasoning behind its row:** 3.8 Flash
beats it, and the only evidence it reaches higher puts it level with Terra and
Sonnet 5 (a single source, not verified). So it sits at **T2**, the same tier as
the models it's compared with. The earlier draft put it in T3 under `agent`
only because its price there wasn't found. A missing price is never a reason to
drop a tier.

\* **A model's name doesn't tell you its tier.** On Artificial Analysis, Gemini
3.8 Flash scores above 3.1 Pro (the research found two index versions that
don't reconcile, so how far above isn't settled). Gemini 3.5 Pro hasn't shipped.
Tiers have to come from evidence and get rechecked, never from "Pro" or "Flash" in a slug.

### Three findings that change the design

1. **A CLI is not a vendor.** Opus 5.5 can be reached through `claude`, `agy`, and
   `agent`, and Sol only through `agent`. The independence rule ("the refuter is
   from a different vendor than the author") has to compare **model families**
   (Anthropic / OpenAI / Google / xAI / Cursor-Composer), not CLIs. Sending Opus
   through `agy` to refute Opus is still a same-model check.
2. **Each CLI bills from its own pool.** `claude` uses your Anthropic plan.
   `codex` uses ChatGPT quota. `agy` uses Google's AI Pro/Ultra quota, *including
   its Claude models*. `agent` uses Cursor's pools, where Composer comes from the
   included pool and frontier models are charged at API rates. So "cost" is
   really "which pool has room", and the same model can be cheaper to reach
   through another CLI.
3. **Effort is set differently per CLI.** `agy`/`agent` put it in the model slug,
   while `claude`/`codex` take a separate flag. The delegator needs the §3 flag
   table to translate (task tier, effort) into a command line.

## 4. Done-condition and falsifier

**Done when** each installed CLI has its listed models placed in T1/T2/T3 with
a cited reason, and the six rules in §2 send a sample of 10 real past tasks from
this repo's history to a tier Joe agrees with on at least 8.

**Falsified if** any of these happens:
- Over a run of real delegations, T3/T2 output gets redone by T1 often enough
  to cost more than running T1 directly. Then the tier lines are drawn wrong.
- The tier of a model can't be decided without knowing the task. Then tiers
  aren't a property of the model and the two-question split is wrong.

## 5. Open items

- Seed vs delete for the repo copy is settled as **seed** (§0). `test.sh:923`
  (repo and machine copies must match) has to become "the machine copy
  exists and its stable sections match the repo's."
- Rival draft from a different vendor (codex) before building, per the
  orchestration playbook. Diff it against this plan.
- Build order once that's done: (1) stable sections into `MODEL-ROUTING.md`;
  (2) generator steps in `commands/update-model-routing.md` (live listings →
  OpenRouter prices → web-researched tier → rewrite the generated sections, keep
  the stable ones exactly); (3) `customize.sh` seed-only copy + `test.sh`; (4) fold
  `light`/`strong` into the tier scale in the playbook; (5) changelog proposal.

## 6. Rival draft (Gemini 3.8 Flash via `agy`, 2026-10-10)

The draft was written blind: it got the problem, the established facts, and
Joe's four decisions, but not this plan. Its full text is at
`~/.ai-context/model-tiers-rival/rival-gemini.md`. A Sol draft through `agent`
was attempted first and failed (free plan, §3).

**Adopt (it has these; this plan didn't):**
- **Each task category gets a `Tier required` column plus primary and fallback
  `CLI + model + effort`.** That bakes tiers into the existing seven categories
  rather than leaving them only in a separate table. Keep the per-model tier
  table too, as the lookup the categories point into.
- **Ready-to-run invocation strings** in the rows, so a delegator never writes
  flag syntax from memory. This plan's own run proved the need: `agy -p --model …`
  failed because `-p` takes the next token as the prompt, so it has to come last.
- **Quota failover:** on a 429 or a quota error, fall back to the same tier
  through a different CLI rather than dropping a tier or stopping.
- **Quota starvation** as a failure mode: spread same-tier work across pools
  rather than sending everything to the benchmark leader.
- **Numeric falsifiers:** spend vs an all-flagship baseline, and the low-tier
  redo rate. Its thresholds (≥35% spend drop, ≤20% retries) aren't sourced.
  Joe picks the numbers.

**Reject (this plan already covers these, and the rival gets them wrong):**
- **It has no reachability probe** and trusts listings. That was disproven the same
  day: Cursor's listing offers Sol, Opus, and Fable on an account that can only use `auto`.
- **"Prefer flat subscription pools (`agent`)."** That's backwards on this machine,
  where `agent` can't run any named model.
- **Independence "from a vendor other than the authoring CLI"** compares CLIs.
  Opus through `agy` refuting Opus through `claude` would pass. It has to compare
  model families.
- **A CLI × tier matrix with models in the cells** puts the same model in several
  cells, which is exactly the inconsistency Joe caught with Gemini 3.7 Flash.
  Per-model rows stay.
- **Tier rules written as category lists** ("formatting, lint fixes…") rather than
  decision questions. They can't handle a task that isn't on the list. §2's
  ordered questions stay, and its lists can be the worked examples.

**Disagreements for Joe (not settled here):**
1. **What tier is code review?** The rival puts "code reviews" in Mid. This plan
   makes refutation and the final pre-done review always T1. A middle option:
   routine PR review is T2, and the review that decides "done" is T1.
2. **File size:** the rival targets 180–220 lines. Joe approved raising the cap to
   ~130. Fallback columns and invocation strings push toward the rival's number.
3. **Claude role frontmatter in the routing file:** the rival wants a `model:`
   mapping for Claude Code roles inside `MODEL-ROUTING.md`. This plan scoped
   role pinning out. Including it would make the routing file also own role config.
