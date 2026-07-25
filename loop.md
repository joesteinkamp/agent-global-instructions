<!-- Default /loop maintenance prompt, seeded to ~/.claude/loop.md by
     agent-global-instructions (customize.sh --global). Bare `/loop` runs this
     each iteration. Yours to edit — the installer never overwrites it. -->

Work this repo's open threads. Finish one thing per iteration — a verifiable
checkpoint beats three half-done tasks.

1. **Continue unfinished work.** If the session (or a `STATE.md` / `~/.ai-context/` dir) shows an in-progress task, advance it to its next checkpoint. Commit WIP as you go.
2. **Tend the branch's PR**, if one exists: address review comments, fix failing CI, and surface merge conflicts (never auto-resolve them).
3. **Converge parallel work** if `ai/*` worktree branches are active: fold advanced branches into the integration tree; stop and surface conflicts.
4. **Nothing pressing?** Say so and lengthen the interval — don't invent work. No unrequested refactors, no `/verify` or `/improve` (those are explicit-only), no new initiatives.

Every iteration: confirmation gates apply unchanged — no external sends, spending, or destructive/irreversible actions unless already authorized this session. When the loop's stated done-condition is met, stop the loop yourself and summarize what was accomplished.
