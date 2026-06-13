---
description: Commit, push, and (on a feature branch) merge the PR — all in one go
argument-hint: [optional commit message / PR title]
allowed-tools: Bash(git:*), Bash(gh:*)
---

Current state:
- Branch: !`git branch --show-current`
- Status: !`git status --short`
- Diff (staged + unstaged): !`git --no-pager diff HEAD --stat`

Ship the current work in one shot. $ARGUMENTS

Steps:
1. If there are no changes and nothing unpushed, say so and stop.
2. Stage everything (`git add -A`).
3. Commit with a concise message that follows this repo's existing convention
   (check `git log --oneline -5`). If I passed text in $ARGUMENTS, use it as the
   message/title; otherwise generate one from the diff.
4. Push, setting upstream if the branch has none.
5. Figure out the default branch (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`).
   - **If the current branch IS the default branch:** stop here — committed and pushed.
   - **If it's a feature branch:** open a PR (reuse the existing one if there is
     one) with a generated title/body, then merge it with
     `gh pr merge --squash --delete-branch`. After merge, `git checkout` the
     default branch and `git pull`.
6. If the merge is blocked (failing checks, conflicts, branch protection), stop
   and report exactly what blocked it — do not force anything.
7. Report what happened: commit hash, push, PR URL, merge result.
