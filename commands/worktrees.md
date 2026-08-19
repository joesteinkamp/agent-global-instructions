---
description: Set up parallel-agent git worktrees and converge them into one live dev tree
argument-hint: [agent names, e.g. "claude codex antigravity"]
allowed-tools: Bash(git:*), Bash(./converge.sh:*)
---

Current state:
- Repo root: !`git rev-parse --show-toplevel 2>/dev/null`
- Current branch: !`git branch --show-current`
- Existing worktrees: !`git worktree list`

Set up isolated worktrees so several AI agents can work this repo in parallel,
then converge their branches into a single **integration** tree that one dev
server watches — so I see everyone's changes near-live. $ARGUMENTS are the agent
names (default: `claude codex antigravity`).

Steps:
0. **Validate the workspace before changing anything.** Run
   `git worktree list --porcelain` and check the working-tree status. If this
   isn't a Git repository, `git init` and make a root commit so worktrees are
   possible — don't stop to ask for that. Do stop and ask when ownership is
   ambiguous: the tree holds work you didn't create, `HEAD` won't resolve, or
   another agent may own it. If a requested agent worktree or branch already
   exists, inspect and reuse it — never overwrite it.
1. **Pick the integration tree.** Identify the primary checkout from
   `git worktree list --porcelain`; don't assume the current checkout is
   integration. If I'm on a throwaway/feature branch, suggest creating or
   switching to `integration` (`git switch -c integration`) so merges land
   somewhere stable.
2. **Spin a worktree per agent** as a sibling dir, each on its own branch — skip
   any that already exist:
   `git worktree add ../<repo>-<agent> -b ai/<agent>`.
3. **Ensure the converge helper is present** in the integration tree. If
   `converge.sh` isn't here, write it (it ships with my harness repo; here's the
   loop it runs):
   ```bash
   # converge.sh — fold agent branches into the integration branch as they advance.
   # Run from the integration tree; auto-discovers ai/* branches, skips a dirty tree.
   set -uo pipefail
   git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 1
   INT="${CONVERGE_INTERVAL:-3}"
   while true; do
     git diff --quiet && git diff --cached --quiet || { sleep "$INT"; continue; }
     for b in $(git for-each-ref --format='%(refname:short)' 'refs/heads/ai/*'); do
       git merge-base --is-ancestor "$b" HEAD 2>/dev/null && continue
       if git merge --no-edit "$b" >/dev/null 2>&1; then echo "merged $b"
       else echo "CONFLICT $b"; git merge --abort 2>/dev/null || true
            : > ".converge-conflict-${b//\//-}"; fi
     done; sleep "$INT"
   done
   ```
4. **Hand me the two commands to run from the integration tree:**
   - the dev server bound to `0.0.0.0` (the way I preview web work), and its URL;
   - `./converge.sh` to fold each `ai/*` branch in as it advances (it auto-discovers them).
   Offer to start the converge daemon in the background; leave the dev server to me.
5. **Remind me of the rules that keep it live:** scope each agent to a disjoint
   area, commit WIP often (liveness = commit cadence), and that conflicts are
   flagged via `.converge-conflict-*` markers rather than auto-resolved.
6. **Teardown, when I ask:** `git worktree remove ../<repo>-<agent>` and delete
   the `ai/<agent>` branch once merged.
