---
description: Quick checkpoint — commit and push, no PR
argument-hint: [optional commit message]
allowed-tools: Bash(git:*)
---

Current state:
- Branch: !`git branch --show-current`
- Status: !`git status --short`

Save my work so I don't lose it. $ARGUMENTS

Steps:
1. If there's nothing to commit and nothing unpushed, say so and stop.
2. Stage everything (`git add -A`).
3. Commit. Use $ARGUMENTS as the message if given; otherwise write a short
   message summarizing the change (a `wip:`/`checkpoint:` prefix is fine).
4. Push, setting upstream if needed.
5. Do NOT open or merge a PR. Report the commit hash and that it's pushed.
