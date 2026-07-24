---
description: Deep-research current public model benchmarks and refresh MODEL-ROUTING.md (the advisory per-task routing table), showing the diff for approval before anything is kept
argument-hint: [optional focus, e.g. "coding categories only"]
allowed-tools: Bash(git:*), Bash(cat:*), Bash(cp:*), Bash(date:*), Bash(ls:*), Bash(head:*), Read, Edit, Write, Grep, Glob, WebSearch, WebFetch, Task
---

Today: !`date +%Y-%m-%d`
Current table header: !`head -20 MODEL-ROUTING.md 2>/dev/null || echo "MISSING"`
Installed CLIs: !`cat "$HOME/.ai/clis" 2>/dev/null || command -v codex agy claude agent cursor-agent 2>/dev/null | sed 's|.*/||'`
Repo check: !`ls customize.sh template.md MODEL-ROUTING.md 2>/dev/null || echo "NOT THE HARNESS REPO"`

Refresh the advisory model-routing table from **current public benchmark evidence**. $ARGUMENTS

1. **Guard.** This runs in the agent-global-instructions checkout (see the repo
   check above). If the probe says `NOT THE HARNESS REPO`, ask for the checkout
   path or stop — never create a stray MODEL-ROUTING.md elsewhere.
2. **Research — current evidence only.** For each category heading in
   `MODEL-ROUTING.md`, search the web for the latest results (prefer results
   ≤3 months old; today's date is in the probes): SWE-bench Verified,
   Terminal-Bench, Aider polyglot, LMArena (incl. WebDev Arena), ARC-AGI,
   GPQA / HLE, long-context benches (e.g. MRCR), plus each vendor's newest
   model card (Anthropic, OpenAI, Google, and Cursor's current default/frontier
   options). Rules: **independent leaderboards outrank vendor-reported
   numbers**; every ranking claim needs a source URL + retrieval date; note the
   harness/scaffold when it materially affects a score; where evidence
   conflicts or is thin, write "no clear winner" — never manufacture a ranking.
   Fan categories out to parallel subagents when available.
3. **Map models → installed CLIs** (the roster probe above): `claude` =
   Anthropic, `codex` = OpenAI, `agy` = Google Gemini (Antigravity), `agent` =
   Cursor. Keep the `agent`-is-a-wildcard caveat (its strength depends on its
   selected model). Flag any CLI whose current default model you could not
   confirm.
4. **Rewrite `MODEL-ROUTING.md` preserving its structure exactly** — the
   metadata header (set `Last updated` to today), the seven fixed category
   headings, per-claim citations, the caveats paragraph verbatim, and the
   Benchmarks-consulted list. Keep the whole file under ~90 lines — it is read
   mid-session; trim, don't accumulate.
5. **Show the diff and ask.** `git --no-pager diff MODEL-ROUTING.md`, plus one
   line per category on what moved and why. On approval, mirror the machine
   copy: `cp MODEL-ROUTING.md ~/.ai/model-routing.md`. On rejection,
   `git checkout -- MODEL-ROUTING.md` and stop.
6. **Changelog gate.** Propose a `CHANGELOG.md` entry (what changed in the
   rankings and the evidence that drove it); **never write the changelog or
   commit anything without explicit approval** — this gate overrides "finish
   the task".
