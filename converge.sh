#!/usr/bin/env bash
# converge.sh — continuously fold parallel agent branches into the integration
# branch so a single dev server (running in THIS worktree) shows every agent's
# work near-live. Liveness tracks commit cadence: tell agents to commit WIP often.
#
# Run from your INTEGRATION worktree (the one the dev server watches):
#   ./converge.sh                       # auto-discover & fold every ai/* branch
#   ./converge.sh ai/claude ai/codex    # only these branches
#   CONVERGE_INTERVAL=2 ./converge.sh   # poll faster (default 3s)
#   CONVERGE_REMOTE=1 ./converge.sh     # also fetch the remote each cycle
#
# On a real conflict (or a dirty integration tree) it leaves integration at the
# last clean commit, never guesses a resolution, and drops a
# .converge-conflict-<branch> marker for you (or an integrator agent) to resolve.
set -uo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "converge: not inside a git repo" >&2; exit 1; }
here="$(git branch --show-current)"
[ -n "$here" ] \
  || { echo "converge: integration tree is on a detached HEAD — check out an integration branch first" >&2; exit 1; }

INTERVAL="${CONVERGE_INTERVAL:-3}"
# Auto-discover local ai/* branches; with CONVERGE_REMOTE=1 also fold remote-only
# ai/* (refs/remotes/*/ai/*) so a teammate's pushed branch converges without
# needing a local tracking branch first.
discover() {
  git for-each-ref --format='%(refname:short)' 'refs/heads/ai/*'
  [ "${CONVERGE_REMOTE:-0}" = "1" ] && git for-each-ref --format='%(refname:short)' 'refs/remotes/*/ai/*'
  return 0
}

# Explicit branch args win; otherwise (or for a literal 'ai/*') auto-discover.
PINNED=1
if [ "$#" -eq 0 ] || [ "$*" = "ai/*" ]; then PINNED=0; fi

trap 'echo; echo "converge: stopped"; exit 0' INT TERM
echo "converge: folding ${*:-all ai/* branches} into '${here}' every ${INTERVAL}s (Ctrl-C to stop)"

while true; do
  if [ "$PINNED" = 1 ]; then BRANCHES=("$@"); else
    # shellcheck disable=SC2207
    BRANCHES=($(discover))
  fi
  [ "${CONVERGE_REMOTE:-0}" = "1" ] && git fetch --quiet --all --prune 2>/dev/null

  # A dirty integration tree blocks a merge before it starts — skip the cycle
  # rather than churn failed merges (which can't be --abort'ed and would spam).
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "$(date +%H:%M:%S)  skip — integration tree dirty; commit or stash to resume"
    sleep "$INTERVAL"; continue
  fi

  for b in "${BRANCHES[@]:-}"; do
    [ -n "$b" ] || continue
    git rev-parse --verify --quiet "$b" >/dev/null 2>&1 || continue
    git merge-base --is-ancestor "$b" HEAD 2>/dev/null && continue   # already merged
    if git merge --no-edit "$b" >/dev/null 2>&1; then
      echo "$(date +%H:%M:%S)  merged  $b"
      rm -f ".converge-conflict-${b//\//-}"
    else
      echo "$(date +%H:%M:%S)  CONFLICT $b — kept last-good, flagged for manual resolve"
      git merge --abort 2>/dev/null || git reset --merge >/dev/null 2>&1 || true
      : > ".converge-conflict-${b//\//-}"
    fi
  done
  sleep "$INTERVAL"
done
