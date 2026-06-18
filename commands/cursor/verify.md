<!-- Canonical source: commands/verify.md (Claude dialect). This is the Cursor port.
     Cursor commands are plain-Markdown prompt templates in .cursor/commands/*.md —
     NO YAML frontmatter, NO shell injection, NO $ARGUMENTS placeholder. The Claude
     frontmatter and the `!`cmd`` context lines are folded into prose below; anything
     I type after `/verify` is the optional route/focus/acceptance note. -->

# Verify

Prove a change works and is true to spec. Don't review it for taste (that's `/improve`) — **prove** it does
what it should and is true to the design and the briefs. This is evidence, not opinion: run it, drive it,
screenshot it, diff it. Anything I type after `/verify` is an optional route/url, focus, or acceptance note.

First gather context by running these yourself:
- Changed files: `git --no-pager diff --stat HEAD 2>/dev/null`
- Untracked: `git --no-pager status --porcelain 2>/dev/null | grep '^??' || true`
- Project briefs: `ls PRODUCT.md DESIGN.md DESIGN.json CODE.md AGENT.md guardrails 2>/dev/null || true`
- Prior runs / baseline: `ls -dt verify/*/ 2>/dev/null | head -3 || true`

Run the lenses below. Each emits **PASS / FAIL / N/A** with attached evidence. A lens with no reference or
no capability is **N/A** — skip it, never block on it. Use Cursor background/subagents to parallelize the
independent lenses if available; otherwise run each in turn.

1. **Builds & runs.** Detect the project's tooling (`package.json` scripts, prettier/eslint/ruff/go/
   Makefile…). Run build → typecheck → tests, then boot the app and confirm it comes up clean. If it
   doesn't build, stop here and report.
2. **Renders in a real browser.** For any UI/route change, serve it the way I preview web work (bind
   `0.0.0.0`, never `127.0.0.1`; verify 200) and drive the changed route(s) headless with Playwright.
   - Capture **console + network**; any uncaught error or 4xx/5xx is a FAIL.
   - **Responsive matrix** — screenshot each touched route at mobile (390px), tablet (768px), desktop
     (1280px); lay them out as a contact sheet in the report.
   - Run an **axe-core a11y** pass and a contrast check in the same session.
3. **Visual regression.** Diff this run's screenshots against a baseline — the prior `verify/` run, or the
   same routes from the default branch. Surface unintended visual change with a before/after. No baseline
   yet → save these as the baseline and mark N/A.
4. **Matches the design.** Compare the screenshots to the reference — Figma node (via MCP) or `DESIGN.md` +
   `DESIGN.json` tokens (color, type, spacing, radius, motion). Report drift as expected-vs-actual.
5. **Conforms to the briefs.** Check the diff against `PRODUCT.md` / `DESIGN.md` / `CODE.md` and any
   `guardrails/` — stack & conventions, security, accessibility, anti-pattern registries.
6. **Does what it claimed.** Re-run the acceptance criteria from the task / PR / issue against the running
   app. Flag any “verified” step that wasn't actually exercised.

**Output is an artifact.** Write `verify/<slug>-<date>/` — `report.html` (self-contained: pass/fail table,
responsive contact sheet, visual-regression before/afters, design diffs, console logs) plus the raw
`screenshots/`. Serve the report per my preview method (headless → static server on `0.0.0.0`, verify 200,
hand me the URL; keep it running). Inline, give me only the **verdict + the link**.

This is a verification pass — **report what passed, what failed, and what was N/A.** Don't fix things
unless I ask; if something failed, point at `file:line` and what the evidence shows.
