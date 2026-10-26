---
name: handoff
description: "Turn a prototype (a Figma link or node, a prototype URL, or files) into a spec engineers can build from: inventory, every state, tokens by name, responsive rules, motion, a11y, copy, edge cases and open questions. Use when a design is ready for engineering"
---

Project briefs: run `ls DESIGN.md DESIGN.json PRODUCT.md WRITING.md guardrails 2>/dev/null || true`
Token files: run `git ls-files 2>/dev/null | grep -iE '(tokens?|theme|variables)[^/]*\.(json|css|scss|ts|js)$|tailwind\.config' | head -20 || true`

**Handoff** turns a prototype into a spec an engineer can build from without coming back to ask what was
meant. The request names the source: a Figma link or node id, a prototype URL, or files (screenshots,
exported frames, HTML). Use any focus supplied in the user request, such as one flow or one component.

**An undesigned state is a question, not a guess.** When the source doesn't show a state, a breakpoint or
a behavior, the spec lists it under open questions with what's missing. It never fills the gap with an
invented design. You may offer a recommended answer, labeled as a recommendation, in the question itself.

**Seen or inferred, on every line.** Each item carries its provenance. *Seen* cites the source: node id,
URL plus breakpoint, or file name. *Inferred* gives the basis, e.g. "matches `space/4` by measured value".
Name tokens, never raw values where a token exists. A value with no token is a token gap, flagged for the
designer.

**Read-only.** This skill never edits the Figma file, the prototype or product code, and never posts the
spec anywhere. The artifact lives in the repo but is excluded from git (step 10).

### 1. Resolve the source and say which path runs
- **Figma.** From `figma.com/design/<fileKey>/<name>?node-id=12-345`, take the file key and node id
  `12:345`. Check whether this host has a Figma MCP server connected. Tool names vary by host, for example
  get design context, get variable defs, get screenshot, get metadata. Connected and the node loads: the
  **Figma path**. Otherwise don't start an authentication flow on my behalf. Fall back to the URL or files
  path and name what was missing.
- **URL.** Drive it with `playwright-cli` (read `playwright-cli --help` first; serving gotchas are in
  `~/.ai/web-preview.md`). This is also the fallback when Figma isn't available.
- **Files.** Read what was given. Screenshots show layout and copy, but not values, bindings or behavior,
  so most of those lines will be inferred or open.
- **Only a Figma link, no Figma access, and nothing else:** stop and ask for a prototype URL or exported
  frames. Don't build a spec from a link's name. On an unattended run (step 11) this ends the run with
  `path=blocked`.
- **The system.** `DESIGN.json`, the token structure and component library `DESIGN.md` names, the token
  files listed above, and `WRITING.md` for voice. Note which are missing.
- **State the path in one line**, e.g. "Figma path: 12:345 + DESIGN.json" or "Figma is not connected, so
  this works from <URL> screenshots. Tokens are matched by measured value, not by variable binding."

### 2. Gather the evidence
- **Figma path:** the node tree (metadata), design context and specs, bound variables, text styles, effects,
  component properties and variants, prototype connections where the tool exposes them, and a screenshot
  of every frame.
- **URL path:** `snapshot` for the structure and accessibility tree, `resize` + `screenshot` at each
  breakpoint, `eval` for computed styles of key elements, `hover` and `press Tab` to exercise states. Run
  axe-core through `run-code` as accessibility evidence. Then `playwright-cli close` and the process check
  from `~/.ai/web-preview.md`.

### 3. Inventory
List the screens, then the components on each, with their variants. Map each component to the one the
`DESIGN.md` library ships, e.g. "use the library `Button`, variant `primary`". Where the library has
nothing that fits, say so. That is a gap for the designer and engineer to settle, not a license to
hand-roll.

### 4. States
A matrix for every screen and interactive component: default, hover, focus, active, disabled, loading,
empty, error, success, first-run. Each cell is *Seen* (source), *Inferred* (basis), *N/A* (with why, e.g. a
static heading has no hover), or *Open question*. A blank cell is not allowed.

### 5. Tokens
Per component: color, type, space, radius, shadow and motion, by token name. On the Figma path use the
bound variables. On the URL path match each measured value against the token tables. A match is
*Inferred*, because the value lines up but the binding is unknown. A value off the scale is a token gap.

### 6. Responsive behavior
For each breakpoint (`DESIGN.json` `breakpoints`, else the design's frame widths, else 390 / 768 / 1280),
give the layout, what reflows, hides, stacks or truncates, and the min and max widths. A breakpoint with no
frame is an open question.

### 7. Interactions and motion
For each interaction: the trigger, the result, the transition, and its duration and easing as motion
tokens. Give the reduced-motion behavior for every animation (what replaces it, usually an instant change
or an opacity-only fade). If the source doesn't design reduced motion, it's an open question.

### 8. Accessibility
Per component: semantic element or role, accessible name and labels, focus order, visible focus style,
keyboard behavior (Tab, Enter, Space, Escape, arrows), how loading and error states are announced, contrast
of each text and UI color pair against WCAG 2.2 AA (4.5:1 for text, 3:1 for large text and UI parts), and
target size (at least 24×24 CSS px). Report contrast only from measured or resolved values.

### 9. Content and edge cases
- **Content:** every string verbatim, where it appears, and its truncation rule. Flag placeholder and
  lorem text. Where `WRITING.md` exists it governs voice. Cite it, don't rewrite the copy.
- **Edge cases:** the longest realistic text, zero, one and many items, slow network and timeouts,
  offline, missing or partial data, no permission or read-only access, and recovery from each error. Each
  is *Seen*, *Inferred* or an open question.

### 10. Open questions and the artifact
Close the spec with numbered open questions. Each one states what's missing, what it blocks, and a
recommended answer. Write a self-contained HTML artifact to
`handoff/<slug>-YYYY-MM-DD/spec.html` at the project root, the way `/verify` keeps its reports, with
`screenshots/` beside it. First add `/handoff/` to the clone's exclude file if it isn't there, through the
shell: `f="$(git rev-parse --git-path info/exclude)"; mkdir -p "$(dirname "$f")"; grep -qxF '/handoff/' "$f" || echo '/handoff/' >> "$f"`
Edit tools are denied on anything under `.git/`, and `--git-path` also
finds the file in a linked worktree, where `.git` is a file. The exclude file is local and never
committed, so the spec never shows as a change. Outside a git repo, use
`~/.ai-context/handoff/<slug>-YYYY-MM-DD/`. It holds the header (path ran, inputs found and missing), inventory, state
matrix, tokens, responsive, motion, a11y, content, edge cases, then the open questions last. Serve it per
my preview method (headless: a static server on `0.0.0.0`, verify the URL you hand me returns 200, keep it
running, unless the run is unattended). Inline, give the path that ran, counts of screens, components and
open questions, and the link.
Then **offer a Markdown copy** for an issue or PR body. Write it only if I say yes, and never post it
anywhere without my go-ahead.

### 11. Unattended runs and the result line
**An unattended run finishes; it doesn't wait.** A run is unattended when nobody can answer mid-run: a
`/goal` or `/loop` turn, a scheduled or headless run, or a request that says so. Wherever this skill says
ask, an unattended run takes the fallback the step names (the URL or files path when Figma is
unavailable), marks it *assumed* in the report and lists it under open questions, then finishes. An
undesigned state is still an open question, never a guess, so unattended runs add open questions rather
than fill cells. It starts no server either: it writes the file and gives its path, because a loop that
serves every run leaves a server behind each time.

**End the chat summary with one result line**, in exactly this shape, so a `/goal` checker, which reads
only the conversation, can test it:
`HANDOFF path=figma|url|files|blocked screens=N components=N blank-cells=N token-gaps=N open-questions=N`
A spec is complete at `blank-cells=0`. Open questions are counted, never a pass condition: answering them
is the designer's job, and a goal that waits on them waits on me.
