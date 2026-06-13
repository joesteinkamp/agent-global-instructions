---
description: Open a pull request with a generated title and body (no merge)
argument-hint: [optional PR title]
allowed-tools: Bash(git:*), Bash(gh:*)
---

Current state:
- Branch: !`git branch --show-current`
- Status: !`git status --short`
- Commits vs default: !`git --no-pager log --oneline @{u}.. 2>/dev/null || git --no-pager log --oneline -10`

Open a PR for this branch. $ARGUMENTS

Steps:
1. If I'm on the default branch, stop and tell me to make a feature branch first.
2. Make sure work is committed and pushed (commit/push if there are pending
   changes, following the repo's commit convention).
3. Create the PR with `gh pr create`. Use $ARGUMENTS as the title if given;
   otherwise generate a clear title and a body summarizing the changes
   (what + why, with a short bullet list).
4. Do NOT merge. Report the PR URL.
