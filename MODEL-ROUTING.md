# Model routing — advisory reference

<!-- Machine copy: ~/.ai/model-routing.md (mirrored by customize.sh --global).
     The repo copy is the source of truth; refresh it with /update-model-routing,
     which re-researches current public benchmarks and rewrites this file. -->

- **Last updated:** 2026-07-24
- **Method:** deep web research over current public benchmarks and vendor model
  cards; independent leaderboards outrank vendor-reported numbers; every claim
  cites a source + retrieval date (all retrievals 2026-07-24).
- **CLI → vendor:** `claude` = Anthropic Claude (flagship Fable 5; Opus 4.8,
  Sonnet 5, Haiku 4.5) · `codex` = OpenAI (GPT-5.6 Sol/Terra/Luna; GPT-5.5) ·
  `agy` = Google Gemini (3.1 Pro still "preview"; 3.5 Pro's July 17 target
  missed, now rumored August) · `agent` = Cursor (Composer 2.5, Kimi-K2.5-based;
  vendor-reported only, no independent leaderboard presence — a wildcard).

**Advisory only.** Benchmarks measure benchmarks, not your workload. Consult,
then choose freely — availability, cost, and your own observed results on this
task type outrank any row below. Ties and uncertainty are stated, not hidden.

## Hard coding & refactoring
*Multi-file implementation, debugging, agentic terminal work.*

| Rank | CLI | Evidence |
|------|-----|----------|
| 1 (tie) | `claude` / `codex` | Independent boards split at the top: tbench.ai (native harnesses) has Claude Code + Fable 5 #1 at 83.8% vs Codex + GPT-5.5 #2 at 83.1% (Sol not yet submitted); vals.ai (neutral Terminus-2 harness) has GPT-5.6 Sol #1 at 85.77% vs Fable 5 #3 at 80.52%. A genuine tie, not a clean #1/#2. |
| 3 | `agy` | Gemini 3.1 Pro + Gemini CLI 65.8% on TB2.1 (vals.ai); 3.5 Pro still not shipped (July 17 target missed). |
| — | `agent` | Cursor CLI + Grok 4.5 79.3% on TB2.1 (tbench.ai, independent); Composer 2.5 vendor-reported only (TB2.0 69.3%). |

## Code review & refutation
*Cross-vendor "find what's wrong" passes.*

| Rank | CLI | Evidence |
|------|-----|----------|
| — | no clear winner | No benchmark isolates review/refutation by base-model vendor. Proxy signals near-saturated: `agy` 95.45% / `codex` 95.20% GPQA Diamond (vals.ai), `claude` leads HLE no-tools (53.3%, artificialanalysis.ai). A new Martian Code Review Bench ranks review *products* (CodeRabbit, Copilot, Gemini Code Assist…), not base vendors, so it doesn't decide this row. Rule that matters: **pick the strongest vendor that didn't author the work** — independence beats rank here. |

## Deep research & synthesis
*Multi-source investigation, fact-checking, long reports.*

| Rank | CLI | Evidence |
|------|-----|----------|
| 1 | `codex` | Leads agentic browsing: BrowseComp 90.4% (Sol) / 92.2% (Sol Ultra) vs Claude Fable 5 88.0% (steel.dev, independent). Best for hard fact-finding on the open web. |
| 2 | `claude` | Leads knowledge-heavy synthesis: HLE 53.3% (artificialanalysis.ai) and GAIA 52.3% (benchlm.ai, ref-only). Best for weighing and writing up what was found. |
| 3 | `agy` | BrowseComp 85.9% on one board (steel.dev) but absent from others; thin evidence. |

## Planning & architecture
*Decomposition, novel reasoning, trade-off judgment.*

| Rank | CLI | Evidence |
|------|-----|----------|
| — | no clear winner (`codex`/`claude`) | GPQA Diamond saturated and near-tied: `agy` 95.45%, `codex` 95.20%, `claude` 93.18% (vals.ai). `codex` leads ARC-AGI-2 (~85% GPT-5.5, aggregator; eval-set caveats apply — arcprize.org); no GPT-5.6 entry yet. `claude` leads HLE no-tools 53.3% vs Sol 47.2% (artificialanalysis.ai). Evidence splits by benchmark; treat `codex` and `claude` as peers, `agy` close behind. |

## UI / frontend design
*Visual quality, component work, design-system fidelity.*

| Rank | CLI | Evidence |
|------|-----|----------|
| 1 | `claude` | Best of the four routed vendors on both frontend boards: Fable 5 #2 WebDev Arena (Elo 1634) and #3 Design Arena Website (1332) (arena.ai + designarena.ai via benchlm.ai, independent). |
| 2 | `codex` | GPT-5.6 Sol #3 WebDev Arena (1630) but weak on design preference (~#22 Design Arena). Strong builds, weaker aesthetics. |
| 3 | `agy` | Gemini 3.1 Pro still off both frontend top 10s (#23 Design Arena Website) despite top-tier overall-text Elo. |

Note: Moonshot Kimi K3 and Z.ai GLM-5.2 top both frontend boards but are not installed CLIs.

## Quick mechanical edits & cheap fan-out
*High-volume, low-difficulty subtasks — optimize cost and latency, not peak IQ.*

| Rank | CLI | Evidence |
|------|-----|----------|
| 1 | `codex` / `agy` | Cheapest current-gen floors (official pricing pages, $/Mtok in/out): gpt-5.4-nano 0.20/1.25, gpt-5.4-mini 0.75/4.50; Gemini 3.1 Flash-Lite 0.25/1.50, 3.5 Flash-Lite 0.30/2.50 (2.5 Flash-Lite 0.10/0.40 cheaper still but retires 2026-10-16, per Google's deprecations page). No GPT-5.6 nano/mini exists — 5.6 is flagship-tier only. |
| 2 | `claude` | Haiku 4.5 at 1/5 — ~4-5× the floor above. |
| — | `agent` | Subscription credits, not per-token; Composer 2.5 pool is cheap within a paid plan. CLI default model unconfirmed from official docs. |

Note: a CLI's *default* model is usually its flagship — pass an explicit cheap-tier model flag when fanning out.

## Long-context analysis
*Whole-repo or long-document comprehension; note usable context windows.*

| Rank | CLI | Evidence |
|------|-----|----------|
| — | no clear winner | Splits by depth and by aggregate vs. peak. Multi-needle retrieval at true 1M depth is now a near-tie: `claude` Opus 4.6 76.0% vs `codex` GPT-5.6 Sol 73.8% (llm-stats MRCR v2); across shallower depths `codex` leads the aggregate (Sol 0.915 vs Opus 4.6 0.760). Fable 5 / Opus 4.8 still unpublished on MRCR. `agy` Gemini 3.1 Pro stays weak (0.263) — degrades hardest past ~128k. Deep narrative ≤192k: `codex` nominally leads (Fiction.liveBench ~97%) but that data is stale — no current-gen entries published. Windows: Claude ~1M, GPT-5.6 Sol ~1.05M, Gemini advertises biggest but degrades, Composer 200k. |

## Benchmarks consulted

- Terminal-Bench 2.1 (tbench.ai, vals.ai) · SWE-bench Verified + Pro (swebench.com;
  aggregators) · LMArena WebDev + text (arena.ai) · Design Arena (designarena.ai)
  · GPQA Diamond (vals.ai) · HLE (artificialanalysis.ai) · ARC-AGI-2
  (arcprize.org, benchlm.ai) · BrowseComp (leaderboard.steel.dev) · GAIA
  (benchlm.ai, ref-only) · MRCR v2 (llm-stats.com) · Fiction.liveBench
  (epoch.ai) · Martian Code Review Bench (withmartian) · vendor pricing/model
  pages (Anthropic, OpenAI, Google, Cursor). All retrieved 2026-07-24.
