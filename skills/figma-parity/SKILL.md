---
name: figma-parity
description: "Check a built screen against its Figma node and the project's tokens. Measured drift in spacing, type, color, radius, layout, states and content, in a side-by-side HTML report. Use when asked whether the build matches the design"
---

Project briefs: run `ls DESIGN.md DESIGN.json PRODUCT.md WRITING.md guardrails 2>/dev/null || true`
Token files: run `git ls-files 2>/dev/null | grep -iE '(tokens?|theme|variables)[^/]*\.(json|css|scss|ts|js)$|tailwind\.config' | head -20 || true`
Dev scripts: run `grep -E '"(dev|start|preview)":' package.json 2>/dev/null || true`
Snapshot: run `git rev-parse --short HEAD 2>/dev/null || true`

**Figma parity** answers one question: does the built screen match its design, and where it doesn't, which
side moved? The request names a screen (a URL or a route) and its Figma node (a link or a node id). Use any
focus supplied in the user request, such as one component, one breakpoint, or one state.

**No numeric match without a measured value.** Every "matches" or "off by N" cell cites a number you
actually read: a Figma variable or spec value on one side, a computed style or bounding box on the other.
Two screenshots that look alike are a visual note, never a numeric claim. Where a value couldn't be
measured, the cell says "not measured" and why.

**Read-only on product code.** This skill measures and reports. It never edits components, styles, tokens
or the Figma file, and the project's `git status` is the same when it ends as when it began. The report
lives in the repo but is excluded from git (step 6). Fixes are suggestions, applied only on my go-ahead.

### 1. Resolve the inputs and say which path runs
- **The screen.** A full URL is used as-is. A route needs the app running. If the integration tree's dev
  server is already up, drive it read-only. Otherwise start the project's dev script bound `0.0.0.0` per
  `~/.ai/web-preview.md` (the Vite/Astro unknown-Host 403 is covered there), require a 200 on the exact
  URL, and stop that server when the run ends. Never start a second server for a tree another agent serves.
- **The node.** From `figma.com/design/<fileKey>/<name>?node-id=12-345`, take the file key and node id
  `12:345`. A bare node id also needs the file key. If neither the request nor `DESIGN.md` has it, ask; on
  an unattended run (step 7), take the tokens-only path and say why.
- **Figma access.** Check whether this host has a Figma MCP server connected. Tool names vary by host,
  for example get design context, get variable defs, get screenshot, get metadata. Connected and the
  node loads: the **live path**. Not connected, not authenticated, or the node fetch fails: the
  **tokens-only path**. Don't start an authentication flow on my behalf. Name it as missing.
- **The tokens.** `DESIGN.json` (contract keys `color`, `type`, `space`, `radius`, `shadow`,
  `breakpoints`, `motion`, all optional), the token structure `DESIGN.md` articulates (its own or one
  adopted from an imported system), its named component library, and the token files listed above.
- **State the path in one line before measuring.** For example "Live: Figma 12:345 + DESIGN.json" or
  "Tokens-only: Figma is not connected, so the Figma comparison will not run." With no Figma and no token
  source there is nothing to compare against: say so, offer to draft a `DESIGN.md` token section from what
  the code already does, and stop.

### 2. Get the design
- **Live:** fetch the node screenshot, the variables and styles bound to it (name plus resolved value),
  layout specs (auto-layout direction, gap, padding, sizing), text styles, effects, and the node's
  variants and states (component properties, sibling frames such as hover, disabled or error). Record each
  value with its source, e.g. `Figma 12:345 › Button/Primary › padding = space/4 (16px)`.
- **Tokens-only:** the token tables are the expected values, and the components and states `DESIGN.md`
  describes are the expected inventory. There is no design screenshot.

### 3. Get the build
Drive it with `playwright-cli` (read `playwright-cli --help` first).
- **Breakpoints.** `DESIGN.json` `breakpoints`, else the Figma frame widths, else 390 / 768 / 1280. At
  each one, `resize` then `screenshot`, full page and the element the node maps to.
- **Key elements.** The ones the node contains: containers, headings, body text, buttons, inputs, icons,
  cards. For each, read with `eval` or `run-code`: `getComputedStyle` for font-family, font-size,
  font-weight, line-height, letter-spacing, color, background, border, padding, margin, gap, border-radius,
  box-shadow; `getBoundingClientRect` for size and the space between siblings. Record selector, property,
  value and breakpoint.
- **Token or raw.** For each value, find out whether it comes from a token (`var(--…)`, a theme key, a
  utility class on the scale) or a raw literal. Grep the source read-only for where it's set.
- **States.** `hover`, focus via `press Tab`, and any state reachable without writing data. A state you
  can't reach is "not reached", not assumed to match.
- **Close.** `playwright-cli close`, then run the process check from `~/.ai/web-preview.md`.

### 4. Compare
Compare every element on each dimension that applies, at each breakpoint:
- **Spacing:** padding, gap and margins, against the space scale.
- **Type:** family, size, weight, line-height, and letter-spacing where the design sets it.
- **Color:** the value, and whether the build uses the token or a raw value (`DES-03` where `guardrails/`
  ships it; cite the ban ID for any guardrail you flag).
- **Radius and shadow.**
- **Layout:** alignment, order, sizing and wrapping at each breakpoint.
- **States and variants:** every state and variant in the design exists in the build. A missing one is
  drift, not a pass.
- **Content:** copy, truncation, icons and imagery.
Say what tolerance you used before reporting. Sub-pixel rounding (0.5px or less) counts as a match.
Anything beyond that is drift, reported with its delta.

### 5. Classify every drift
- **Build drifted.** The design and the tokens agree and the build differs. The suggested fix names the
  selector or `file:line` and the token it should use.
- **Design and tokens disagree.** The Figma value is off the token scale, or a Figma variable resolves to
  something different from `DESIGN.json`. The build can't satisfy both, so don't pick a winner. This is a
  question for the designer: which one is the source of truth, and do the tokens/`DESIGN.md` or the Figma
  file change?
- **Unverified.** The tokens-only path couldn't check it against the design, or a side wasn't measured.
**Severity:** *high* for a missing state or variant, a broken layout at a breakpoint, a wrong semantic
color, or a contrast failure under WCAG 2.2 AA. *medium* for a visible off-scale value or raw value where
a token exists. *low* for an on-scale value that is the wrong step, or a small offset with no visual effect.

### 6. Report
Write a self-contained HTML artifact to `figma-parity/<slug>-YYYY-MM-DD/report.html` at the project root,
the way `/verify` keeps its reports, with its `screenshots/` beside it. First add `/figma-parity/` to the
clone's exclude file if it isn't there, through the shell:
`f="$(git rev-parse --git-path info/exclude 2>/dev/null)" && { mkdir -p "$(dirname "$f")"; grep -qxF '/figma-parity/' "$f" 2>/dev/null || echo '/figma-parity/' >> "$f"; }`
Edit tools are denied on anything under `.git/`, and `--git-path` also finds the file in a linked
worktree, where `.git` is a file. The exclude file is local and never committed, so the report never
shows as a change. Outside a git repo, use `~/.ai-context/figma-parity/<slug>-YYYY-MM-DD/`. It contains:
- **Header:** which path ran, every input found and missing, node id and link, URL, breakpoints, the
  snapshot SHA, and the tolerance.
- **Side by side, per breakpoint:** Figma on the left, build on the right. On the tokens-only path the
  left panel says "Figma comparison did not run" and why.
- **Drift table:** dimension, element (selector), expected (source + token name + value), actual
  (measured value + breakpoint), delta, class, severity, suggested fix. Sort by severity.
- **Questions for the designer:** every "design and tokens disagree" row, phrased as a decision.
- **Not measured / not reached:** what couldn't be checked and why.
Serve it per my preview method (headless: a static server on `0.0.0.0`, verify the URL you hand me
returns 200, keep it running, unless the run is unattended). Inline, give only the path that ran, drift
counts by severity and class, the top three drifts, and the link.

### 7. Unattended runs and the result line
**An unattended run finishes; it doesn't wait.** A run is unattended when nobody can answer mid-run: a
`/goal` or `/loop` turn, a scheduled or headless run, or a request that says so. Wherever this skill says
ask, an unattended run takes the fallback the step names (the tokens-only path, the breakpoints
`DESIGN.json` gives), marks it *assumed* in the report and lists it under open questions, then finishes.
With no screen it can reach and nothing to compare against, it ends with `path=blocked` and names what it
needed. It starts no preview server either: it writes the file and gives its path, because a loop that serves
every run leaves a server behind each time.

**End the chat summary with one result line**, in exactly this shape, so a `/goal` checker, which reads
only the conversation, can test it:
`PARITY path=live|tokens-only|blocked build-drifted=N design-vs-token=N unverified=N high=N medium=N low=N`

**A goal that fixes the build is done at `build-drifted=0`**, plus `path=live` when the claim is fidelity
to Figma, because the tokens-only path can't show that. `design-vs-token` rows are the designer's
decision, so they never go in a done-condition: a goal that waits on them waits on me. When drift is in
code this session can fix, offer the line with the condition already written, e.g.
`/goal the PARITY line shows build-drifted=0, unverified=0 and path=live; or stop after 15 turns`.
`unverified=0` is there because a drift moved to *unverified* leaves `build-drifted` at zero without a
fix.
