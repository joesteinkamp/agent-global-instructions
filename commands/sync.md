---
description: Update the default branch and rebase the current branch on it
allowed-tools: Bash(git:*), Bash(gh:*)
---

Current state:
- Branch: !`git branch --show-current`
- Status: !`git status --short`

Bring my branch up to date with the latest default branch.

Steps:
1. `git fetch --all --prune`.
2. Find the default branch (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`,
   fall back to `origin/HEAD`).
3. If the working tree is dirty, stash first (note that you did), so the rebase
   is clean.
4. If I'm ON the default branch: `git pull --rebase`.
   Otherwise: rebase the current branch onto `origin/<default>`.
5. If you stashed, pop it back.
6. If there are rebase conflicts, stop and report them — don't guess resolutions.
7. Report what changed (commits pulled in, current position).
