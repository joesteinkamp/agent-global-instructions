<!-- Canonical source: commands/audit.md (Claude dialect). This is the Cursor port.
     Cursor commands are plain-Markdown prompt templates in .cursor/commands/*.md —
     NO YAML frontmatter, NO shell injection, NO $ARGUMENTS placeholder. The Claude
     frontmatter is folded into prose; anything I type after `/audit` is the args
     (screenshot path(s) or design, + optional focus).
     NOTE: the canonical command runs the Claude `ux-audit` *skill*. Cursor has its
     own Skills system (.cursor/skills/), so install ux-audit as a Cursor skill or
     run its steps directly. -->

# Audit

Run a UX/design audit. Anything I type after `/audit` is the target — screenshot path(s) or design, plus an optional focus.

1. Resolve the target screenshot(s) from what I typed — explicit file path(s), a
   directory, or the most recent screenshot if none were given.
2. Run the **`ux-audit`** skill on them
   (repo: github.com/joesteinkamp/ux-audit-skill). In Cursor, install it as a
   skill under `.cursor/skills/ux-audit/` (or `~/.cursor/skills/ux-audit/`) and
   invoke it; if Cursor skills aren't available, follow the skill's steps directly
   from its SKILL.md. It scores the UI against 15 UX heuristic frameworks. Answer
   its intake (design goal, target persona, platform, artifact stage) from what I
   typed and surrounding context; ask me only what genuinely can't be inferred. If
   the skill isn't installed, tell me how to add it and stop.
3. It writes `audits/<slug>-<date>/` — `findings.json`, `summary.md`,
   `annotated/*.png`, and a self-contained `report.html`.
4. Serve the report per my environment's preview method: if headless, start a
   static server on `0.0.0.0` (never `127.0.0.1`), verify it returns 200, and
   hand me the Tailscale URL to `report.html`; otherwise open it locally. Keep
   it running.
5. Summarize the top severity-ranked findings inline, then link the full report
   for the annotated detail.
