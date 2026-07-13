---
name: "handoff"
description: "Developer handoff for a screen/route — states, tokens, a11y, and acceptance criteria"
---

<!-- GENERATED from commands/handoff.md by render-commands.sh — do not edit. Invoke as $handoff. -->

Changed files: run `git --no-pager diff --stat HEAD 2>/dev/null`
Design refs: run `ls DESIGN.json DESIGN.md PRODUCT.md 2>/dev/null || true`

Build a **developer handoff** for the screen/component in Use any focus supplied in the user request. — the spec a
front-end engineer implements against. Not a review (that's `/improve`) and not a
QA pass (that's `/verify`): this is the *contract*. Pull from real references when
they exist and mark anything unavailable **N/A** — never invent.

1. **Resolve the target.** A route/URL, a Figma node (via MCP if connected), or the
   changed component(s) from the diff. State what you're documenting.
2. **Pull the reference.** Read `DESIGN.json` tokens (color/type/space/radius/shadow/
   breakpoints/motion) and `DESIGN.md`/`PRODUCT.md` intent if present; a Figma node if
   MCP is connected. Everything below cites these — don't invent hex/px/copy.
3. **Assemble the handoff:**
   - **Layout & redlines** — structure, spacing, sizing, and alignment expressed in
     tokens/scale steps (not raw px where a token exists), at each breakpoint.
   - **Component states** — default, hover, focus, active, disabled, loading, error,
     empty — what each looks like and when it applies.
   - **Tokens used** — the exact color/type/space/radius/shadow/motion tokens, by name.
   - **Interaction & motion** — transitions (duration/easing from tokens), and the
     `prefers-reduced-motion` behavior.
   - **Accessibility** — roles/landmarks, keyboard order & focus, contrast pass/fail,
     and target sizes.
   - **Acceptance criteria** — the checklist the implementation must satisfy, drawn
     from the task/PR/issue and the briefs.
4. If the route is running and Playwright is available, capture a screenshot per state
   into the report (bind `0.0.0.0`, never `127.0.0.1`); otherwise skip — don't fake it.

**Output is an artifact.** Write `handoff/<slug>-YYYY-MM-DD/report.html` (self-contained:
the state matrix, token table, a11y notes, redlines, acceptance checklist). Serve it per
my preview method (headless → static server on `0.0.0.0`, verify 200, hand me the URL;
keep it running). Inline, give me only a one-line summary + the link — don't dump the
handoff in chat.
