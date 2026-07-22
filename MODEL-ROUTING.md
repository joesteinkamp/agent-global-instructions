# Model routing — advisory reference

<!-- Machine copy: ~/.ai/model-routing.md (mirrored by customize.sh --global).
     The repo copy is the source of truth; refresh it with /update-model-routing,
     which re-researches current public benchmarks and rewrites this file. -->

- **Last updated:** 2026-07-21
- **Method:** deep web research over current public benchmarks and vendor model
  cards; independent leaderboards outrank vendor-reported numbers; every ranking
  claim cites a source with its retrieval date (all retrievals 2026-07-21).
- **CLI → vendor:** `claude` = Anthropic Claude (flagship Fable 5; Opus 4.8,
  Sonnet 5, Haiku 4.5) · `codex` = OpenAI (GPT-5.6 Sol/Terra/Luna; GPT-5.5) ·
  `agy` = Google Gemini (3.1 Pro still "preview"; 3.5 Pro delayed — flagship
  slot genuinely unsettled) · `agent` = Cursor (Composer 2.5, Kimi-K2.5-based;
  vendor-reported numbers only, no independent leaderboard presence — treat as
  a wildcard).

**Advisory only.** Benchmarks measure benchmarks, not your workload. Consult,
then choose freely — availability, cost, and your own observed results on this
task type outrank any row below. Ties and uncertainty are stated, not hidden.

## Hard coding & refactoring

*Multi-file implementation, debugging, agentic terminal work.*

| Rank | CLI | Evidence |
|------|-----|----------|
| 1 | `claude` | Terminal-Bench 2.1 #1: Fable 5 + Claude Code 83.8% (tbench.ai, independent). SWE-bench Verified 95.0% widely cited but primary unreached; SWE-bench Pro 80.3% is Anthropic-scaffold vendor-reported. |
| 2 | `codex` | Terminal-Bench 2.1 #2: GPT-5.5 + Codex 83.1% — statistical tie with #1. New flagship Sol has no TB2.1 entry yet; OpenAI claims Sol tops the AA Coding Agent Index (vendor-reported). |
| 3 | `agy` | Gemini 3.1 Pro + Gemini CLI 65.8% on TB2.1 (independent); 3.5 Pro repeatedly delayed over coding quality. |
| — | `agent` | Composer 2.5 vendor-reported only (TB2.0 69.3%); Cursor CLI + Grok 4.5 scored 79.3% on TB2.1 — the CLI's strength depends on which model it routes to. |

## Code review & refutation

*Cross-vendor "find what's wrong" passes.*

| Rank | CLI | Evidence |
|------|-----|----------|
| — | no clear winner | No public benchmark isolates review/refutation. Proxy signals split: reasoning is a near-tie (`agy` 95.5% / `codex` 95.2% GPQA Diamond, vals.ai + artificialanalysis.ai), `claude` leads HLE no-tools (53.3%, artificialanalysis.ai). Rule that matters: **pick the strongest vendor that didn't author the work** — independence beats rank here. |

## Deep research & synthesis

*Multi-source investigation, fact-checking, long reports.*

| Rank | CLI | Evidence |
|------|-----|----------|
| 1 | `codex` | Leads agentic browsing: BrowseComp 90.4% (Sol) / 92.2% (Sol Ultra) vs Claude Fable 5 88.0% (steel.dev + benchlm.ai, independent). Best for hard fact-finding on the open web. |
| 2 | `claude` | Leads knowledge-heavy synthesis: HLE 53.3% (artificialanalysis.ai) and GAIA 52.3% (benchlm.ai, ref-only). Best for weighing and writing up what was found. |
| 3 | `agy` | BrowseComp 85.9% on one board (steel.dev) but absent from others; thin evidence. |

## Planning & architecture

*Decomposition, novel reasoning, trade-off judgment.*

| Rank | CLI | Evidence |
|------|-----|----------|
| — | no clear winner (`codex`/`claude`) | GPQA Diamond is saturated and near-tied: `agy` 95.5%, `codex` 95.2%, `claude` 93.2% (vals.ai). `codex` leads ARC-AGI-2 (~85% GPT-5.5, aggregator; eval-set caveats apply — arcprize.org). `claude` leads HLE no-tools 53.3% vs Sol 47.2% (artificialanalysis.ai). Evidence splits by benchmark; treat `codex` and `claude` as peers, `agy` close behind. |

## UI / frontend design

*Visual quality, component work, design-system fidelity.*

| Rank | CLI | Evidence |
|------|-----|----------|
| 1 | `claude` | Best of the four routed vendors on both frontend boards: Fable 5 #2 WebDev Arena (Elo 1636) and #3 Design Arena Website (arena.ai + designarena.ai via benchlm.ai, independent). |
| 2 | `codex` | GPT-5.6 Sol #3 WebDev Arena (1633, tie with #2) but notably weak on design preference (~#22 Design Arena). Strong builds, weaker aesthetics. |
| 3 | `agy` | Faded from both frontend boards' current top 10 despite top-tier overall-text Elo. |

Note: Moonshot Kimi K3 and Z.ai GLM-5.2 currently top both frontend boards but are not installed CLIs.

## Quick mechanical edits & cheap fan-out

*High-volume, low-difficulty subtasks — optimize cost and latency, not peak IQ.*

| Rank | CLI | Evidence |
|------|-----|----------|
| 1 | `codex` / `agy` | Cheapest current-gen floors (official pricing pages, $/Mtok in/out): gpt-5.4-nano 0.20/1.25, gpt-5.4-mini 0.75/4.50; Gemini 3.1 Flash-Lite 0.25/1.50, 3.5 Flash-Lite 0.30/2.50 (2.5 Flash-Lite 0.10/0.40 is cheaper still but retires 2026-10-16). |
| 2 | `claude` | Haiku 4.5 at 1/5 — ~4-5× the floor above. |
| — | `agent` | Subscription credits, not per-token; Composer 2.5 pool is cheap within a paid plan. CLI default model unconfirmed from official docs. |

Note: a CLI's *default* model is usually its flagship — pass an explicit cheap-tier model flag when fanning out.

## Long-context analysis

*Whole-repo or long-document comprehension; note usable context windows.*

| Rank | CLI | Evidence |
|------|-----|----------|
| — | no clear winner | Splits by task type. Multi-needle retrieval at depth: `claude` leads (MRCR 8-needle@1M: Opus 4.6 76.0% vs GPT-5.4 36.6%, Gemini 3.1 Pro 26.3% — yage.ai; Fable 5/Opus 4.8 unpublished). Deep narrative comprehension ≤192k: `codex` leads (Fiction.liveBench ~97%, epoch.ai; older Claude historically weak there). `agy` advertises the biggest window (2.5M, conflicting sources) but degrades hardest past ~128k. Windows: Claude/GPT ~1M, Composer 200k. |

## Benchmarks consulted

- Terminal-Bench 2.1 (tbench.ai) · SWE-bench Verified + Pro (swebench.com;
  mostly via aggregators — primaries JS-blocked) · Aider polyglot (stale,
  excluded) · LMArena WebDev + text (arena.ai) · Design Arena (designarena.ai)
  · GPQA Diamond (vals.ai) · HLE (artificialanalysis.ai; scale.com stale) ·
  ARC-AGI-1/2/3 (arcprize.org) · BrowseComp (leaderboard.steel.dev,
  benchlm.ai) · GAIA (benchlm.ai, ref-only) · MRCR v2 (yage.ai) ·
  Fiction.liveBench (epoch.ai) · vendor pricing/model pages (Anthropic,
  OpenAI, Google, Cursor). All retrieved 2026-07-21.
