<!-- Codex port. Canonical source: commands/audit.md (Claude dialect).
     Install location: ~/.codex/prompts/audit.md  ->  invoke as /prompts:audit
     Codex prompts have no !`cmd` shell-injection, so context lines are rewritten
     as instructions for the agent to run. Args: $ARGUMENTS (and $1..$9). -->
---
description: UX/design audit of a screen — runs the ux-audit skill and serves the report
argument-hint: SCREENSHOTS=<path(s) or design> FOCUS=<optional focus>
---

Run a UX/design audit. $ARGUMENTS

1. Resolve the target screenshot(s) from the arguments above — explicit file
   path(s), a directory, or the most recent screenshot if none were given.
2. Run the **`ux-audit`** skill on them
   (repo: github.com/joesteinkamp/ux-audit-skill). It scores the UI against 15
   UX heuristic frameworks. Answer its intake (design goal, target persona,
   platform, artifact stage) from the arguments and surrounding context; ask me
   only what genuinely can't be inferred. If the skill isn't installed, tell me
   how to add it and stop.
3. It writes `audits/<slug>-<date>/` — `findings.json`, `summary.md`,
   `annotated/*.png`, and a self-contained `report.html`.
4. Serve the report per my environment's preview method: if headless, start a
   static server on `0.0.0.0` (never `127.0.0.1`), verify it returns 200, and
   hand me the Tailscale URL to `report.html`; otherwise open it locally. Keep
   it running.
5. Summarize the top severity-ranked findings inline, then link the full report
   for the annotated detail.
