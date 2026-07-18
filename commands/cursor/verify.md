<!-- GENERATED from commands/verify.md by render-commands.sh — do not edit. -->
# Verify

Prove a change works and is true to spec — run it, drive it in a browser, check it against the project briefs

> Cursor has no argument placeholder — type your input after `/verify` and it is appended to this prompt; treat any `$ARGUMENTS` below as that input.

Changed files: run `git --no-pager diff --stat HEAD 2>/dev/null`
Untracked: run `git --no-pager status --porcelain 2>/dev/null | grep '^??' || true`
Project briefs: run `ls PRODUCT.md DESIGN.md DESIGN.json CODE.md AGENT.md guardrails 2>/dev/null || true`
Prior runs: run `ls -dt verify/*/ 2>/dev/null | head -3 || true`

**Verify** the recent change — don't review it for taste (that's `/improve`), **prove** it does what it
should and is true to the design and the briefs. This is evidence, not opinion: run it, drive it,
screenshot it, diff it. $ARGUMENTS

Run the lenses below. Each emits **PASS / FAIL / N/A** with attached evidence. A lens with no reference or
no capability is **N/A** — skip it, never block on it. For long or independent lenses, fan out with
subagents (Task) and integrate; otherwise run them in order.

1. **Builds & runs.** Detect the project's tooling (reuse `/tidy`'s detection — `package.json` scripts,
   prettier/eslint/ruff/go/Makefile…). Run build → typecheck → tests, then boot the app and confirm it
   comes up clean. If it doesn't build, stop here and report — nothing downstream is meaningful.
2. **Renders in a real browser.** For any UI/route change, serve it the way I preview web work (bind
   `0.0.0.0`, never `127.0.0.1`; verify 200) and drive the changed route(s) headless with Playwright
   (install it if absent; if it can't be installed here, mark this lens N/A — don't fake it).
   - Capture **console + network**; treat any uncaught error or 4xx/5xx as a FAIL.
   - **Responsive matrix** — screenshot each touched route at the project's breakpoints (from `DESIGN.json`'s
     `breakpoints` if present, else mobile 390px / tablet 768px / desktop 1280px); lay them out as a contact
     sheet in the report.
   - Run an **axe-core a11y** pass and a contrast check in the same session (skip if axe can't be loaded).
   - **Reduced motion** — re-render each touched route with `page.emulateMedia({ reducedMotion: 'reduce' })`; **FAIL if non-essential motion still plays** — this behavioral re-render is the authoritative test. Don't FAIL merely on a missing CSS `@media (prefers-reduced-motion: reduce)` block: JS/WAAPI, Framer Motion, and GSAP honor the preference via `matchMedia` without one. **N/A** when nothing on the route animates. Relates to WCAG 2.2.2 Pause/Stop/Hide (AA); the preference itself is named by SC 2.3.3 (AAA). axe won't catch this — it's a separate, deterministic check in the same session.
3. **Visual regression.** Diff this run's screenshots **pixel-by-pixel** (Playwright `toHaveScreenshot`,
   `pixelmatch`, or ImageMagick `compare`) against a baseline — the prior `verify/` run, or the same routes
   built from the default branch. Surface any unintended visual change (per-route, per breakpoint) with a
   before/after and the diff image. If there's no baseline yet, save these as the baseline and mark N/A.
   (The baseline is machine-local — `verify/` is gitignored — so cross-machine, the default-branch rebuild
   is the real reference.)
4. **Matches the design.** Compare the screenshots to the reference — Figma node (via MCP) or a
   `DESIGN.json` token file (with `DESIGN.md` for intent). Report drift as expected-vs-actual, not vibes.
   The `DESIGN.json` contract this lens reads (all keys optional; check whatever is present) —
   its canonical source is the [project-starter-pack](https://github.com/joesteinkamp/project-starter-pack),
   which generates `DESIGN.json` alongside the briefs:
   - `color` — named roles → hex/rgb (e.g. `bg`, `fg`, `primary`, `border`).
   - `type` — `family`, and named `size` / `leading` (line-height) / `weight` scales.
   - `space` — the spacing scale (e.g. `{ "1": "4px", "2": "8px", … }`).
   - `radius`, `shadow` — named scales.
   - `breakpoints` — named widths; **feed these to the responsive matrix in lens 2** instead of the 390/768/1280 defaults when present.
   - `motion` — `duration` and `easing` scales, and named `transition` specs (duration + easing).
   Drift = a rendered computed value (color, font-size, padding, radius, transition-duration/easing) that isn't on the corresponding scale.
5. **Conforms to the briefs.** Check the diff against `PRODUCT.md` / `DESIGN.md` / `CODE.md` and any
   `guardrails/` — stack & conventions, security, accessibility, and the anti-pattern registries. The
   brief is the contract; the diff is the claim.
6. **Does what it claimed.** Re-run the acceptance criteria from the task / PR / issue against the running
   app. Flag any “verified” step that wasn't actually exercised — the honesty gate.

**Report inline by default.** Give me the results directly in chat: the **PASS / FAIL / N/A table** with a
line of evidence per lens, FAILs called out with `file:line`, then the fix plan. Keep it tight — the table
plus the plan, not a screenshot dump.

**Offer the HTML artifact.** The visual evidence (responsive contact sheet, visual-regression before/afters,
design diffs, console logs) doesn't fit in chat — offer to write `verify/<slug>-YYYY-MM-DD/` (`report.html`,
self-contained, plus the raw `screenshots/`) and serve it per my preview method (headless → static server on
`0.0.0.0`, verify 200, hand me the URL; keep it running). Produce it only if I say yes, or right away if I
asked for the report up front.

This is a verification pass — **report what passed, what failed, and what was N/A.** Then **prepare to
act:** for every FAIL, propose a concrete fix (`file:line` + the change the evidence points to) and
assemble them into a prioritized, ready-to-apply plan. **Don't fix anything yet** — ask which items to
apply and, on my go-ahead, make exactly those changes and re-run the affected lenses to confirm the fix.
