---
# GENERATED from commands/worktrees.md by render-commands.sh — do not edit. Invoke as /prompts:worktrees
description: Set up parallel-agent git worktrees and converge them into one live dev tree
argument-hint: [agent names, e.g. "claude codex gemini"]
---

Current state:
- Repo root: run `git rev-parse --show-toplevel 2>/dev/null`
- Current branch: run `git branch --show-current`
- Existing worktrees: run `git worktree list`

Set up isolated worktrees so several AI agents can work this repo in parallel,
then converge their branches into a single **integration** tree that one dev
server watches — so I see everyone's changes near-live. $ARGUMENTS are the agent
names (default: `claude codex gemini`).

Steps:
1. **Pick the integration tree.** The current checkout is it. If I'm on a
   throwaway/feature branch, suggest creating or switching to `integration`
   (`git switch -c integration`) so merges land somewhere stable.
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
