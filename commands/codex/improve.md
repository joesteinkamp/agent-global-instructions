<!-- Codex port. Canonical source: commands/improve.md (Claude dialect).
     Install location: ~/.codex/prompts/improve.md  ->  invoke as /prompts:improve
     Codex prompts have no !`cmd` shell-injection, so the diff-context lines are
     rewritten as a first step telling the agent to gather that context itself.
     Codex has no Task/subagent fan-out tool, so the review lenses run as
     sequential passes in one session. Args: $ARGUMENTS. -->
---
description: Run a multi-role review on recent changes to find improvement opportunities
argument-hint: FOCUS=<optional focus, e.g. "perf" or a path>
---

Run a **multi-role improvement review** on the recent changes (working tree vs
HEAD, plus the last few commits if the tree is clean). $ARGUMENTS

1. Gather the change context yourself by running:
   - `git --no-pager diff --stat HEAD`
   - `git --no-pager status --porcelain | grep '^??' || true`  (untracked)
   - `git --no-pager log --oneline -5`
   Scope the changes and decide whether they touch UI.
2. Review the change through each lens in turn — give each pass only the diff
   plus the relevant files, and collect concrete, prioritized **improvement
   opportunities** (not praise), each with `file:line` and a suggested change:
   - **Technical architect** — structure, coupling, boundaries, risk, missing abstractions.
   - **Back-end engineer** — correctness, data handling, error paths, performance.
   - **Front-end engineer** — component design, state, accessibility, UX edge cases.
   - **UI/UX** — *only if UI changed* — visual/interaction quality and consistency.
3. Collect findings, **dedupe**, group by theme, sort by impact.
4. Present a tight summary: top opportunities first (where + why + suggested
   fix). Call out any real bugs separately.
5. This is a review pass — **don't apply changes unless I ask.**
