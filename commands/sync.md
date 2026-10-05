---
description: Update the default branch, rebase onto it, and sweep merged worktrees — worktree-aware, with gated teardown
allowed-tools: Bash(git:*), Bash(cd:*), Bash(~/.ai/worktree-sweep.sh:*)
---

Current state:
- Branch: !`git branch --show-current`
- Status: !`git status --short`
- This tree: !`git rev-parse --show-toplevel`

Bring my branch up to date with the latest default branch.

Steps:
1. `git fetch --all --prune`.
2. Find the default branch with a forge-independent lookup so this works on any
   provider: `git symbolic-ref --short refs/remotes/origin/HEAD` (strip the
   `origin/` prefix), falling back to `git remote show origin` ("HEAD branch").
3. **Work out whether I'm standing in a linked worktree**, because steps 8 and 9
   only exist for that case. `git rev-parse --git-dir` and `git rev-parse
   --git-common-dir` return the same path in the primary checkout and different
   ones in a linked worktree (where the git dir becomes
   `<common>/worktrees/<name>`). The primary checkout is the **first** `worktree`
   line of `git worktree list --porcelain`. Call it `<primary>`, and call the
   branch checked out there `<base>` (`git -C <primary> branch --show-current`).
   If this IS the primary checkout, skip steps 8 and 9 and sync as usual.
4. If the working tree is dirty, stash first (note that you did), so the rebase
   is clean.
5. If I'm ON the default branch: `git pull --rebase`.
   Otherwise: rebase the current branch onto `origin/<default>`.
6. If you stashed, pop it back.
7. If there are rebase conflicts, stop and report them — don't guess resolutions.
8. **In a worktree: sync the work back toward `<primary>`.** You can drive the
   primary from in here with `git -C` — you cannot `switch` or `checkout`
   `<base>` from a worktree at all (`fatal: '<base>' is already used by worktree
   at …`), so never try.
   - If `<base>` is the default branch, bring it forward:
     `git -C <primary> merge --ff-only origin/<default>`. Never rebase, force,
     or reset it — it's the integration tree. If that refuses because the
     primary is dirty, report it and move on: uncommitted work in a tree I
     didn't open is untouchable, so don't stash or commit it to clear the way.
     If `<base>` is something else (or the primary is detached), leave it alone
     and just report where it sits.
   - Then ask what this branch still carries: `git log --oneline
     origin/<default>..HEAD`.
     - **Empty** → the work already landed; there is nothing to fold.
     - **Commits, but the branch is proven merged anyway** → also nothing to
       fold. A squash merge is not an ancestor of the default branch, so the
       range stays non-empty forever; the proof is the forge reporting a merged
       PR/MR whose head SHA equals *this* branch's tip, judged exactly the way
       `~/.ai/worktree-sweep.sh` judges it. A branch *name* proves nothing —
       `ai/<agent>` has merged PRs behind it forever.
     - **Commits that genuinely haven't landed** → do **not** merge them into
       `<base>` on your own initiative. Unreviewed work arriving in the
       integration tree by a local merge is the thing `/ship` exists to prevent.
       Name the unmerged commits and offer `/ship` instead. Only if I say fold
       it anyway: `git -C <primary> merge --ff-only <branch>`, and stop if that
       isn't a fast-forward — writing a merge commit into the integration tree
       is my call, not yours.
9. **In a worktree: ask whether to tear it down.** This is a confirmation gate —
   never delete on your own initiative, and put the ask last in your report so I
   can answer it in one read. Name exactly what goes: the directory, the branch,
   and anything still living in either.
   Only offer it once step 8 settled — the branch's work is in
   `origin/<default>` or in `<base>`. If it isn't, don't offer teardown at all:
   say the tree stays and why.
   **If I say yes, the order below is load-bearing — two of these steps fail, or
   take the session with them, if you get it wrong:**
   a. `cd <primary>` **first**. `git worktree remove` does *not* refuse to
      delete the tree you're standing in — it deletes it, and every command
      after that dies with `getcwd: cannot access parent directories`. Running
      it as `git -C <primary> …` doesn't save you: it's the shell's directory
      that vanishes, not git's.
   b. `git -C <primary> worktree remove <path>` — never `--force`. A refusal
      (dirty, untracked, locked) is the answer, not an obstacle: report it and
      leave the tree standing.
   c. `git -C <primary> branch -d <branch>` — never `-D`, and only **after** the
      removal: while the tree still exists git refuses with `cannot delete
      branch '<branch>' used by worktree at …`. A `-d` refusal after a squash
      merge is expected, and `-D` is warranted only when the forge confirms that
      exact tip merged.
   d. `git -C <primary> worktree prune`.
   Then tell me my shell is now in `<primary>`, because the directory I ran this
   from no longer exists.
10. **Sweep the other merged worktrees.** The fetch in step 1 is what makes trees
   reapable, so run `~/.ai/worktree-sweep.sh --sweep` here — it writes nothing —
   then `--apply` to remove the proven-merged ones. It reports the tree this
   session is standing in as `CURRENT` and will never reap it, whatever its
   state — that tree is step 9's job, not the sweep's. Report what it left
   standing and why. Skip the step if the script isn't installed.
11. Report what changed: commits pulled in, current position, anything reaped —
    and when I'm in a worktree, where `<primary>` now sits, and what was folded
    back or left unmerged.
12. **Then nudge me about the remote — everything above this line is local.**
    `/sync` fetches and never pushes, so finish by asking whether to sync the
    remote too. Never push on your own initiative, and fold this into the **same
    single ask** as step 9's teardown question rather than sending a second
    message. Raise only what actually applies:
    - **The rebase moved this branch off its remote counterpart.** If the branch
      has an upstream at all (`git rev-parse --abbrev-ref @{upstream}`; a
      `fatal: no upstream configured for branch …` means it was never pushed, so
      there's nothing to sync and nothing to raise) and `git rev-list
      --left-right --count @{upstream}...HEAD` reports a non-zero **left** count,
      the histories diverged and a plain `git push` will be rejected as a
      non-fast-forward. Offer `git push --force-with-lease` — never a plain
      `--force`. The lease is the whole safety margin when another agent has
      pushed to the same branch, so a refusal from it is the signal to report,
      not to escalate past.
    - **`<primary>` moving forward is not a push.** Step 8's fast-forward came
      *from* `origin/<default>`, so the remote is already at or ahead of it.
      Don't offer to push the default branch.
    - **A reaped branch outliving its remote head.** Once step 9 has actually
      deleted the local branch, `git ls-remote --heads origin <branch>` says
      whether the remote still carries it; if it does, offer `git push origin
      --delete <branch>`. Step 9 only runs after I approve it, so this one
      belongs to that later turn, not to the first ask.
    If none of them apply, say in one line that the remote needs nothing — a
    nudge with nothing behind it is noise.
