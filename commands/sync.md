---
description: Update the default branch, rebase the current branch on it, and sweep worktrees whose branches are now merged
allowed-tools: Bash(git:*), Bash(~/.ai/worktree-sweep.sh:*)
---

Current state:
- Branch: !`git branch --show-current`
- Status: !`git status --short`

Bring my branch up to date with the latest default branch.

Steps:
1. `git fetch --all --prune`.
2. Find the default branch with a forge-independent lookup so this works on any
   provider: `git symbolic-ref --short refs/remotes/origin/HEAD` (strip the
   `origin/` prefix), falling back to `git remote show origin` ("HEAD branch").
3. If the working tree is dirty, stash first (note that you did), so the rebase
   is clean.
4. If I'm ON the default branch: `git pull --rebase`.
   Otherwise: rebase the current branch onto `origin/<default>`.
5. If you stashed, pop it back.
6. If there are rebase conflicts, stop and report them — don't guess resolutions.
7. **Sweep merged worktrees.** The fetch in step 1 is what makes trees
   reapable, so run `~/.ai/worktree-sweep.sh --sweep` here — it writes nothing —
   then `--apply` to remove the proven-merged ones. Report what it left standing
   and why. Skip the step if the script isn't installed.
8. Report what changed (commits pulled in, current position, anything reaped).
