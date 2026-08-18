---
description: Product-grade evaluation of recent work — prove it runs, then grade how well it serves this session's goal, briefs held as reference (and flag docs the code has outgrown)
argument-hint: [optional route/url, the goal, or a focus; --bg to run deferred in the background]
allowed-tools: Bash, Read, Grep, Glob, Skill, Task
---

Changed files: !`git --no-pager diff --stat HEAD 2>/dev/null`
Untracked: !`git --no-pager status --porcelain 2>/dev/null | grep '^??' || true`
Recent commits: !`git --no-pager log --oneline -10 2>/dev/null`
Project briefs: !`ls PRODUCT.md DESIGN.md DESIGN.json CODE.md AGENT.md guardrails 2>/dev/null || true`
Prior runs: !`ls -dt verify/*/ 2>/dev/null | head -3 || true`

**Verify** grades the recent work as a **product increment** — not "does the diff compile" (that's the
floor) and not code taste (that's `/improve`), but *how well does this actually serve the user's goal for
this session?* Evidence is the foundation, the briefs are reference, and the honest yardstick is the goal
this piece of work set out to hit. $ARGUMENTS

**Synchronous by default — verify is a handoff gate, not a report.** Its whole value is blocking "done":
work isn't verified until this pass finishes, so run it inline and don't hand off around it. The **`--bg`**
escape hatch exists for long runs (big suites, multi-route browser sweeps) when there is genuinely
independent work to overlap — it makes verify *deferred*, never fire-and-forget. **Branch on the flag:**
only run the deferred mode below when the arguments contain `--bg`; any other invocation runs inline top
to bottom, and `--bg` is never implied.

- **Pin a snapshot and materialize it.** Pin exactly as `/improve` does (`git stash create` /
  `git rev-parse HEAD` + frozen `diff.patch` and untracked copies in `~/.ai-context/<repo>-verify/`) —
  then, because this pass *builds, boots, and browses* code, give it a real tree at that SHA:
  `git worktree add --detach <tmp-dir> "$SNAP"` (re-apply the untracked copies on top), run every
  build/test/browser step **in that temp worktree, never the live tree** (which keeps moving), and
  `git worktree remove` it when grading ends. Stamp the report with `$SNAP`.
- **Leave a durable open-gate marker.** Before detaching, write
  `~/.ai-context/<repo>-verify/PENDING.md` — the goal, `$SNAP`, and the done-condition — and delete it
  when the scorecard is delivered. `/ship` checks for this file, so the gate survives the session dying:
  a fresh session finds the marker and knows a verify is still owed.
- **State the done-condition before detaching** — "done when this verify reports its grade" — and hold it:
  the session must not call the work verified, hand it off, or ship it until the background run reports.
  Deliver the scorecard when the completion notification arrives, and flag any file that changed since the
  snapshot.
- **Don't fight the live dev server.** One dev server rule applies: if the session's server is already up,
  drive it read-only; otherwise boot on a **different port** and shut it down when grading ends.
- If the host has no background tasks, `--bg` degrades to a normal inline run — say so.

This project is built **bit by bit across sessions**, and the code often runs ahead of the docs — briefs
get updated *after* the code lands. Treat the briefs as context, not gospel: where the work diverges from
them, decide whether it's **intentional evolution** (the docs need to catch up) or **drift** (a real
regression) — never blindly fail against stale documentation.

### 1. Establish the goal for this session
Reconstruct what this increment was *supposed* to achieve — from the task/PR/issue and my request (the
arguments above), the acceptance criteria, and the recent commits. Read `PRODUCT.md` / `DESIGN.md` /
`CODE.md` and `guardrails/` for the product's intent and standards, holding them as supporting context that
may lag the code. **State the goal in a line or two before grading** — that's the yardstick everything else
is measured against.

### 2. Prove it runs (the floor — evidence, not opinion)
This gates everything: a great idea that doesn't run isn't a product.
- **Builds & runs.** Detect the tooling (`package.json` scripts,
  prettier/eslint/ruff/go/Makefile…). Run build → typecheck → tests, then boot the app and confirm it comes
  up clean. If it doesn't build, stop and report — the grade is blocked until it runs.
- **Renders in a real browser.** For any UI/route change, serve it the way I preview web work (bind
  `0.0.0.0`, never `127.0.0.1`; verify 200) and drive the changed route(s) with **`playwright-cli`**
  (`open`/`goto`, `screenshot`, `console`, `requests`; `run-code` when a grading step needs Playwright
  APIs — read `playwright-cli --help` first). If `playwright-cli` isn't available, say so and grade the UX
  from the code instead — don't fake evidence. Any uncaught console error or 4xx/5xx request is a real
  defect that drags the grade down. **Close the browser (`playwright-cli close`) once the evidence is
  captured** — a leaked session outlives the run and takes over my real Chrome; see `~/.ai/web-preview.md`.

### 3. Grade the increment as a product
Score each dimension that applies (skip N/A) with the **evidence** behind it and the **gap to the next grade
up**. Grade A–F; an **A** means you'd ship it proudly, not merely that it works.
- **Goal fit** *(heaviest weight)* — does it accomplish what this session set out to do, end to end? Re-run
  the acceptance criteria against the running app; flag any "done" step that wasn't actually exercised (the
  honesty gate).
- **Experience quality** — the real user journey: friction, clarity, and the states that get skipped —
  empty, loading, error, first-run, no-permission, long-content. Would the user it's for get their job done
  without confusion?
- **Design & accessibility** — where a reference exists, check the code against it. `DESIGN.md` is where
  the design system is articulated — read it for the token structure (its own, or one adopted from an
  imported design system) and the component library in use (imported or built locally) — then verify both
  functionally:
  - **Token usage** — compare rendered computed values against the articulated tokens: `DESIGN.json` (or a
    Figma node via MCP) when present, else the token structure `DESIGN.md` describes. Drift = a computed
    value (color, type, spacing, radius, motion) off the articulated scale.
  - **Component usage** — where `DESIGN.md` names a design system or component library, confirm the touched
    UI uses its components as much as possible: a hand-rolled equivalent of a component the system already
    provides is drift, same as an off-scale value. Report each with `file:line` and the component it should
    have used; a justified, documented divergence isn't a defect — say why.
  - **Missing articulation** — if there's no `DESIGN.md`, or it doesn't articulate a token structure or
    component system, don't silently skip: mark these sub-checks N/A, flag the gap in the report, and
    prompt me to add the articulation — offer to draft that `DESIGN.md` section from what the code
    already does.

  Screenshot the touched routes at the project's breakpoints (`DESIGN.json` `breakpoints` if present, else
  390 / 768 / 1280) via `playwright-cli resize` + `screenshot`. **Run axe-core on every touched route** —
  it's the primary automated a11y gate; drive it through `playwright-cli run-code`, report each violation
  with rule ID, impact, and selector, and treat serious/critical findings as defects — don't substitute a
  visual skim. Also verify **contrast** with computed values, and run a **reduced-motion** behavioral
  re-render (`playwright-cli run-code` with `page.emulateMedia({ reducedMotion: 'reduce' })` — non-essential
  motion still playing is a defect; JS/WAAPI/Framer/GSAP honor the preference without a CSS `@media` block,
  so test the behavior, not the stylesheet). *(`DESIGN.json` contract — all keys optional — is generated by the
  [project-starter-pack](https://github.com/joesteinkamp/project-starter-pack): `color`, `type`, `space`,
  `radius`, `shadow`, `breakpoints`, `motion`.)*
- **Product fit** — does it cohere with the rest of the product and hold to `CODE.md` / `guardrails`
  conventions? Confirm it didn't **regress adjacent flows**: pixel-diff the screenshots against a baseline
  (prior `verify/` run, or the same routes rebuilt from the default branch) and surface any unintended change
  with a before/after.

**Second opinion — a model must not solely grade its own work.** Read the installed-CLI roster
(`~/.ai/clis`, else `command -v codex agy claude agent cursor-agent`), drop the one you are running
as, and have each of the others — the more independent vendors the better — take the stated goal + the diff
and independently
grade **Goal fit** headless, with writes scoped to a context dir it reports into — the repo stays read-only
to it (e.g. `codex exec "…" --sandbox workspace-write --cd ~/.ai-context/<repo>-verify`, `agy -p "…" --mode
accept-edits --add-dir ~/.ai-context/<repo>-verify`; read its full verdict from the file it writes there,
not just stdout), prompted to find where the
work falls short. Where its grade differs from yours, report both and say why — don't average the
disagreement away. A `strong`-tier local model (`~/.ai/local-models` + the `lm` shim, if present) may add
one more independent Goal-fit verdict — `lm -p "…"` with the goal + diff, output piped to the context dir —
but never counts as the only second opinion.

### 4. Reconcile with the docs
List where the work **diverges from the briefs**, and for each call it: **intentional evolution** (the code
advanced past the docs → name the doc + section to update) or **drift** (an unintended regression against
still-valid intent → a defect). This is how the project stays honest as code outruns documentation.

### 5. Report inline, offer the artifact
Inline by default: the **overall product grade**, the per-dimension grades each with one line of evidence,
the top gaps holding the grade down, and the docs-to-update list. Keep it tight — the scorecard, not a
screenshot dump.
Offer the **HTML artifact** — the visual evidence (responsive contact sheet, visual-regression
before/afters, design diffs, console logs) doesn't fit in chat, so offer to write
`verify/<slug>-YYYY-MM-DD/` (`report.html`, self-contained, plus the raw `screenshots/`) and serve it per my
preview method (headless → static server on `0.0.0.0`, verify 200, hand me the URL; keep it running).
Produce it only if I say yes, or right away if I asked for the report up front.

### 6. Prepare to act
Turn the gaps into a prioritized, ready-to-apply plan — each with `file:line` (or the doc to update), the
concrete change, and which grade it lifts. **Don't edit anything yet** — ask which items to apply and, on my
go-ahead, make exactly those changes and re-grade the affected dimensions to confirm.
