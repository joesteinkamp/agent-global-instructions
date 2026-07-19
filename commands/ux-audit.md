---
description: UX/design audit of a screen — ux-audit skill when available, else an inline heuristic audit; serves the report
argument-hint: [screenshot path(s) or design, + optional focus]
allowed-tools: Bash, Read, Glob, Skill
group: design
skill-backed: true
---

Run a UX/design audit. $ARGUMENTS

1. Resolve the target screenshot(s) from $ARGUMENTS — explicit file path(s), a
   directory, or the most recent screenshot if none were given.
2. If the **`ux-audit`** skill is available to you (vendored in this repo at
   `.agents/skills/ux-audit`, synced from github.com/joesteinkamp/ux-audit-skill
   via `npx skills update`; `install-commands.sh` symlinks it globally for
   skill-capable tools), run it: it scores
   the UI 0–100 against 15 UX heuristic frameworks with annotated screenshots.
   Answer its intake (design goal, target persona, platform, artifact stage)
   from $ARGUMENTS and surrounding context; ask me only what genuinely can't
   be inferred.
   **If that skill isn't available** (any tool without it), run the audit
   inline instead. First confirm you can actually view the image(s) — if you
   can't load the screenshot into view, say so and stop rather than guessing;
   ask me to attach it or run this on Claude Code. Then examine the
   screenshot(s) against the major published UX heuristics (Nielsen's 10
   usability heuristics, Gestalt principles, WCAG 2.2 AA, Fitts's/Hick's/
   Miller's laws, and a dark-pattern check) and produce severity-rated
   findings — blocker/major/minor, each with the principle cited, the location
   on screen, and a concrete fix (no 0–100 score — that's skill-only).
3. Write the results to `audits/<slug>-<date>/` — `findings.json` (an array of
   `{severity, principle, location, issue, fix}`), `summary.md`, and a
   self-contained `report.html` (the skill adds `annotated/*.png` and its own
   richer schema).
4. Serve the report per my environment's preview method: if headless, start a
   static server on `0.0.0.0` (never `127.0.0.1`), verify it returns 200, and
   hand me the URL to `report.html`; otherwise open it locally. Keep
   it running.
5. Summarize the top severity-ranked findings inline, then link the full report
   for the annotated detail.
