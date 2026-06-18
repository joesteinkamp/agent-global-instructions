<!-- Canonical source: commands/improve.md (Claude dialect). This is the Cursor port.
     Cursor commands are plain-Markdown prompt templates in .cursor/commands/*.md —
     NO YAML frontmatter, NO shell injection, NO $ARGUMENTS placeholder. The Claude
     frontmatter and the `!`cmd`` context lines are folded into prose below; anything
     I type after `/improve` is the optional focus (e.g. "perf" or a path). -->

# Improve

Run a multi-role review team on recent changes to find improvement opportunities. Anything I type after `/improve` is an optional focus.

First gather the change context by running these yourself:
- Changed files: `git --no-pager diff --stat HEAD 2>/dev/null`
- Untracked: `git --no-pager status --porcelain 2>/dev/null | grep '^??' || true`
- Recent commits: `git --no-pager log --oneline -5 2>/dev/null`

Run a **multi-role improvement review** on the recent changes (working tree vs HEAD, plus the last few commits if the tree is clean).

1. Scope the changes and decide whether they touch UI.
2. Spin up the review team **in parallel** — one subagent per lens (use Cursor
   background/subagents if available; otherwise review each lens sequentially yourself):
   - **Technical architect** — structure, coupling, boundaries, risk, missing abstractions.
   - **Back-end engineer** — correctness, data handling, error paths, performance.
   - **Front-end engineer** — component design, state, accessibility, UX edge cases.
   - **UI/UX** — *only if UI changed* — visual/interaction quality and consistency.
   Give each only the diff + the relevant files. Ask each for concrete, prioritized **improvement opportunities** (not praise), each with `file:line` and a suggested change.
3. Collect findings, **dedupe**, group by theme, sort by impact.
4. Present a tight summary: top opportunities first (where + why + suggested fix). Call out any real bugs separately.
5. This is a review pass — **don't apply changes unless I ask.**
