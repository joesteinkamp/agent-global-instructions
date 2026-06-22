---
description: Commit, push, and (on a feature branch) merge the PR/MR — all in one go
argument-hint: [optional commit message / PR title]
allowed-tools: Bash(git:*), Bash(gh:*), Bash(glab:*)
---

Current state:
- Branch: !`git branch --show-current`
- Status: !`git status --short`
- Diff (staged + unstaged): !`git --no-pager diff HEAD --stat`
- Remote: !`git remote get-url origin 2>/dev/null`

Ship the current work in one shot. $ARGUMENTS

First, figure out which forge this repo lives on, from the `origin` remote URL above:
- **github.com** (or a GitHub Enterprise host) → use the `gh` CLI; the change is a **PR**.
- **gitlab.com** (or a self-hosted GitLab) → use the `glab` CLI; the change is a **MR** (merge request).
- If the host is ambiguous, prefer whichever of `gh` / `glab` is installed (`command -v`). If neither is available, do steps 1–4 (commit + push) and stop, telling me to open the PR/MR manually.

Steps:
1. If there are no changes and nothing unpushed, say so and stop.
2. Stage everything (`git add -A`).
3. Commit with a concise message that follows this repo's existing convention
   (check `git log --oneline -5`). If I passed text in $ARGUMENTS, use it as the
   message/title; otherwise generate one from the diff.
4. Push, setting upstream if the branch has none.
5. Figure out the default branch. Prefer a forge-independent lookup so this works
   anywhere: `git symbolic-ref --short refs/remotes/origin/HEAD` (strip the
   `origin/` prefix), falling back to `git remote show origin` ("HEAD branch").
   - **If the current branch IS the default branch:** stop here — committed and pushed.
   - **If it's a feature branch:** open the change (reuse the existing one if there
     is one) with a generated title/body, then merge it:
     - GitHub: `gh pr create …`, then `gh pr merge --squash --delete-branch`.
     - GitLab: `glab mr create …`, then `glab mr merge --squash --remove-source-branch`.
     After merge, `git checkout` the default branch and `git pull`.
6. If the merge is blocked (failing checks, conflicts, branch protection), stop
   and report exactly what blocked it — do not force anything.
7. Report what happened: commit hash, push, PR/MR URL, merge result.
