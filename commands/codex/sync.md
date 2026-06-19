---
# GENERATED from commands/sync.md by render-commands.sh — do not edit. Invoke as /prompts:sync
description: Update the default branch and rebase the current branch on it
---

Current state:
- Branch: run `git branch --show-current`
- Status: run `git status --short`

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
7. Report what changed (commits pulled in, current position).
