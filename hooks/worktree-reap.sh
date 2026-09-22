#!/usr/bin/env bash
# Worktree reaper — one script, two modes, one safety model.
#
#   HOOK MODE (hook JSON on stdin, no args) — fires on Stop. Resolves the repo
#     from .cwd, rate-limits per repo, auto-removes ONLY worktrees whose branch
#     is provably merged, then emits one non-blocking advisory naming what it
#     reaped and what it left and why. Never blocks, never continues a turn.
#   CLI MODE — the tool-agnostic entry point the commands call:
#     worktree-reap.sh --sweep [--apply] [--all <dir>] [--json] [repo...]
#     Default is a DRY RUN report; --apply performs the safe removals.
#
# Two arms, and only one of them acts:
#   AUTO-DELETE requires PROOF of merge — either
#     `git merge-base --is-ancestor <branch> <default>` (a fast-forward or a
#     merge commit landed), or a forge saying so with a SHA that matches: a
#     merged PR/MR whose base is the default branch AND whose head commit is
#     exactly this branch's tip. The forge arm is load-bearing — a SQUASH merge
#     is not an ancestor of the default branch, so an ancestry-only check reaps
#     nothing in a squash-merge flow — but a branch NAME is not evidence:
#     `ai/<agent>` is recreated for every run and has merged PRs behind it
#     forever, so only the head-SHA comparison makes the answer about THIS tree.
#   ADVISE-ONLY is likelihood, never action — an upstream marked `gone` (what
#     `--delete-branch` leaves behind) only suggests the branch was merged. It
#     is reported with the exact command to run, and never run.
#
# Never touched by either arm:
#   · the main/primary worktree, and the worktree the caller is standing in
#     (compared as physical paths, so a symlinked /tmp cannot defeat it)
#   · a `locked` worktree (the lock is honoured as-is; a pid-liveness check is
#     unsound — a lock outlives the process that took it)
#   · a tree with uncommitted or untracked changes, OR one holding IGNORED files
#     that are not obviously regenerable. `git status --porcelain` alone is
#     blind to `.env`, `*.sqlite`, `my-context.env` and friends, and so is
#     `git worktree remove` — so ignored paths are inspected, and only an
#     all-regenerable set (node_modules/, dist/, .venv/, …) clears the gate.
#   · a branch that never carried a commit of its own (UNSTARTED). Ancestry is
#     reflexive: `git worktree add -b ai/<agent>` branches AT the default tip,
#     so a brand-new agent tree is "merged" from birth. Branch reflog evidence
#     is what separates "finished" from "never started".
#   · anything younger than WORKTREE_REAP_MIN_AGE (COOLING). Agents are told to
#     commit WIP often, which manufactures a clean, merged-looking sample
#     seconds after every commit; the cooling window is what keeps a live
#     sibling tree out of reach.
#   · anything matching WORKTREE_REAP_KEEP_RE (a malformed pattern ABORTS the
#     sweep — a keep-list that fails open protects nothing).
# Removal uses `git worktree remove` WITHOUT --force and `git branch -d` (not
# -D). A refusal from `git branch -d` is a VETO, not a reason to escalate: -D is
# used only when a forge-merged PR's head SHA still equals this branch's tip.
# `git worktree prune` drops registrations whose directory is already gone. It
# is not free — the admin dir it deletes carries that worktree's HEAD reflog and
# refs/worktree/* — so it runs only under --apply, never during a dry run.
#
# Env knobs:
#   WORKTREE_REAP=auto|advise|off    default auto. Hook arm only: `advise`
#                                    reports without deleting, `off` silences
#                                    the hook entirely.
#   WORKTREE_REAP_MIN_INTERVAL=900   seconds between hook runs per repo.
#   WORKTREE_REAP_MIN_AGE=86400      cooling window, in seconds, before a merged
#                                    tree may be removed. 0 disables it — which
#                                    is what a command that just merged the
#                                    branch itself (e.g. /ship) should pass.
#   WORKTREE_REAP_KEEP_RE            ERE of worktree paths to never touch.
#   AI_NUDGE_STATE                   state dir for the rate limit (~/.ai-logs).
#
# Status vocabulary (text report and --json alike):
#   REAPABLE CURRENT MAIN LOCKED DIRTY UNMERGED LIKELY-MERGED PRUNABLE KEEP
#   UNSTARTED COOLING
set -u

PLATFORM="${HOOK_PLATFORM:-claude}"
KEEP_RE="${WORKTREE_REAP_KEEP_RE:-}"
MIN_AGE="${WORKTREE_REAP_MIN_AGE:-86400}"
case "$MIN_AGE" in ''|*[!0-9]*) MIN_AGE=86400;; esac

# Ignored paths that a worktree can lose without losing anything: every one of
# them is rebuilt by a command. Anything else that is ignored is, by definition,
# a file someone decided not to commit — which is the definition of precious.
IGNORE_OK_RE='(^|/)(node_modules|\.venv|venv|\.tox|\.bundle|vendor/bundle|dist|build|out|\.next|\.nuxt|\.svelte-kit|\.astro|__pycache__|\.pytest_cache|\.mypy_cache|\.ruff_cache|target|\.gradle|\.turbo|\.parcel-cache|\.cache|coverage|\.DS_Store)/?$'
IGNORE_PRECIOUS_RE='(^|/)\.env([^/]*)?$|\.sqlite[^/]*$|\.db$|\.local$|\.key$|\.pem$|(^|/)my-context\.env$'

# At most this many forge lookups per sweep. Each one is a network round trip at
# turn end; an unbounded loop over candidates is how a Stop hook becomes a stall.
FORGE_BUDGET=3
FORGE_TIMEOUT=10

# Probing another agent's worktree must not write to it: `--no-optional-locks`
# keeps `git status` from refreshing and rewriting that tree's index (which would
# also destroy the very mtime this script reads as a liveness signal). Older git
# does not know the flag, so it is probed once rather than assumed.
GIT_RO=(git)
git --no-optional-locks --version >/dev/null 2>&1 && GIT_RO=(git --no-optional-locks)

TMPD=""
cleanup() { [ -n "$TMPD" ] && rm -rf "$TMPD" 2>/dev/null; return 0; }
trap cleanup EXIT
# Lazily make one scratch dir per invocation and leave it in $TMPD. Deliberately
# NOT a command substitution: that runs in a subshell, where the assignment to
# TMPD would be lost and every call would leak another directory.
scratch() {
  if [ -z "$TMPD" ]; then TMPD="$(mktemp -d "${TMPDIR:-/tmp}/wtreap.XXXXXX" 2>/dev/null)" || TMPD=""; fi
  [ -n "$TMPD" ] || return 1
  return 0
}

# Physical path, so /tmp-vs-/private/tmp style symlinks can't defeat the
# "never touch the current worktree" comparison. A path whose directory is gone
# (a prunable registration) passes through unchanged.
abspath() {
  [ -n "${1:-}" ] || return 0
  if [ -d "$1" ]; then ( cd "$1" 2>/dev/null && pwd -P ) || printf '%s\n' "$1"
  else printf '%s\n' "$1"; fi
}

# A keep-list that fails open is worse than none: `grep -E` exits 2 on a bad
# pattern, which reads as "no match" to a naive caller and silently protects
# nothing. Validate once, up front, and refuse to sweep at all.
keep_re_valid() {
  local rc
  [ -n "$KEEP_RE" ] || return 0
  grep -E "$KEEP_RE" </dev/null >/dev/null 2>&1; rc=$?
  [ "$rc" -lt 2 ]
}

# Portable mtime. GNU and BSD `date -r` agree on this form; the stat fallbacks
# cover the systems where it does not exist.
mtime_epoch() {  # $1 = path
  local v
  v="$(date -r "$1" +%s 2>/dev/null)" || v=""
  case "$v" in ''|*[!0-9]*) v="";; esac
  [ -n "$v" ] && { printf '%s\n' "$v"; return 0; }
  v="$(stat -c %Y "$1" 2>/dev/null)" || v=""
  case "$v" in ''|*[!0-9]*) v="";; esac
  [ -n "$v" ] && { printf '%s\n' "$v"; return 0; }
  v="$(stat -f %m "$1" 2>/dev/null)" || v=""
  case "$v" in ''|*[!0-9]*) v="";; esac
  [ -n "$v" ] && { printf '%s\n' "$v"; return 0; }
  return 1
}

# One line per worktree: path <TAB> branch-ref <TAB> comma-joined flags.
# (Paths containing a tab or newline are not handled — the same stance the
# other hooks take on exotic filenames, and never at the cost of a removal:
# a mangled record simply fails to classify as REAPABLE.)
wt_list() {  # $1 = any dir inside the repo
  git -C "$1" worktree list --porcelain 2>/dev/null | awk '
    function flush() { if (p != "") printf "%s\t%s\t%s\n", p, b, f; p=""; b=""; f="" }
    /^worktree /  { flush(); p = substr($0, 10); next }
    /^branch /    { b = substr($0, 8); next }
    /^detached/   { f = f "detached,"; next }
    /^bare/       { f = f "bare,"; next }
    /^locked/     { f = f "locked,"; next }
    /^prunable/   { f = f "prunable,"; next }
    END { flush() }
  '
}

DEFAULT_BRANCH=""; DEFAULT_REF_LOCAL=""; DEFAULT_REF_REMOTE=""; DEFAULT_CONFIDENT=0
resolve_default() {  # $1 = repo dir, $2 = main worktree's branch
  local repo="$1" fallback="${2:-}" d c found=""
  DEFAULT_BRANCH=""; DEFAULT_REF_LOCAL=""; DEFAULT_REF_REMOTE=""; DEFAULT_CONFIDENT=0
  d="$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  d="${d#origin/}"
  if [ -n "$d" ]; then
    DEFAULT_CONFIDENT=1            # written by clone / `remote set-head`: an answer, not a guess
  else
    # No origin/HEAD (only clone writes it) — fall back to the conventional
    # names, but call it confident ONLY when exactly one of them exists and it
    # is what the primary worktree has checked out. Anything less is a guess,
    # and a guess must not authorise a deletion.
    for c in main master trunk; do
      git -C "$repo" show-ref --verify --quiet "refs/heads/$c" 2>/dev/null && found="$found $c"
    done
    # shellcheck disable=SC2086  # deliberate split: $found is a space-joined list of branch names
    set -- $found
    if [ "$#" -eq 1 ] && [ "$1" = "$fallback" ]; then
      d="$1"; DEFAULT_CONFIDENT=1
    elif [ -n "$fallback" ]; then
      # Ambiguous: report against what the primary worktree is actually on, so
      # the reasons are true, and leave DEFAULT_CONFIDENT=0 so nothing deletes.
      d="$fallback"
    elif [ "$#" -ge 1 ]; then
      d="$1"
    fi
  fi
  [ -n "$d" ] || return 1
  DEFAULT_BRANCH="$d"
  git -C "$repo" show-ref --verify --quiet "refs/heads/$d" 2>/dev/null && DEFAULT_REF_LOCAL="refs/heads/$d"
  git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$d" 2>/dev/null && DEFAULT_REF_REMOTE="refs/remotes/origin/$d"
  [ -n "$DEFAULT_REF_LOCAL" ] || [ -n "$DEFAULT_REF_REMOTE" ]
}

# Did this branch ever carry a commit of its own? `git worktree add -b ai/x`
# creates the branch AT the default tip, so ancestry says "merged" before any
# work exists. The branch's own reflog is the discriminator; a tip that is still
# exactly the default tip, with no commit in its reflog, never started.
branch_started() {  # $1 = repo dir, $2 = branch, $3 = branch tip sha
  local repo="$1" b="$2" tip="$3" rl r dtip
  rl="$(git -C "$repo" reflog show --format='%gs' "refs/heads/$b" 2>/dev/null)"
  if [ -n "$rl" ]; then
    # Reflogs work in this repo, so their silence is evidence: a branch that
    # only ever recorded `branch: Created from HEAD` never committed anything.
    printf '%s\n' "$rl" | grep -Eq '^commit' && return 0
    return 1
  fi
  # No reflog at all (core.logAllRefUpdates off, or an old enough ref) — fall
  # back to the weaker signal: a tip still sitting exactly on the default tip
  # cannot have work of its own.
  for r in "$DEFAULT_REF_LOCAL" "$DEFAULT_REF_REMOTE"; do
    [ -n "$r" ] || continue
    dtip="$(git -C "$repo" rev-parse --verify --quiet "$r" 2>/dev/null)"
    [ -n "$dtip" ] && [ "$dtip" = "$tip" ] && return 1
  done
  return 0
}

# What is in this tree that a removal would destroy? Sets WT_HOLD_REASON to ""
# when the tree holds nothing but tracked, committed files and regenerable
# ignored ones.
WT_HOLD_REASON=""
worktree_hold_reason() {  # $1 = worktree dir
  WT_HOLD_REASON=""
  [ -d "$1" ] || return 0
  local st line path bad=""
  st="$("${GIT_RO[@]}" -C "$1" status --porcelain --ignored 2>/dev/null)"
  [ -n "$st" ] || return 0
  if printf '%s\n' "$st" | grep -qv '^!! '; then
    WT_HOLD_REASON="uncommitted or untracked changes"; return 0
  fi
  while IFS= read -r line; do
    case "$line" in '!! '*) path="${line#!! }";; *) continue;; esac
    if printf '%s\n' "$path" | grep -Eq "$IGNORE_PRECIOUS_RE" 2>/dev/null; then bad="$bad $path"; continue; fi
    printf '%s\n' "$path" | grep -Eq "$IGNORE_OK_RE" 2>/dev/null || bad="$bad $path"
  done <<IGNORED_EOF
$st
IGNORED_EOF
  [ -n "$bad" ] && WT_HOLD_REASON="holds ignored files that are not obviously regenerable:${bad}"
  return 0
}

# Is this tree younger than the cooling window? A sibling worktree another agent
# is working in looks exactly like a finished one in the seconds after a WIP
# commit — the clock is what tells them apart.
# Youngest evidence of activity in a worktree: the directory's own mtime and the
# per-worktree index, which every checkout/add in that tree touches. MEASURED
# BEFORE this script probes the tree — a `git status` that refreshes the index
# would otherwise reset the clock we are trying to read.
worktree_activity() {  # $1 = worktree path -> echoes an epoch, or nothing
  local p="$1" best="" mt gd
  mt="$(mtime_epoch "$p" 2>/dev/null)" || mt=""
  case "$mt" in ''|*[!0-9]*) ;; *) best="$mt";; esac
  gd="$("${GIT_RO[@]}" -C "$p" rev-parse --absolute-git-dir 2>/dev/null)" || gd=""
  if [ -n "$gd" ] && [ -f "$gd/index" ]; then
    mt="$(mtime_epoch "$gd/index" 2>/dev/null)" || mt=""
    case "$mt" in ''|*[!0-9]*) ;; *) { [ -z "$best" ] || [ "$mt" -gt "$best" ]; } && best="$mt";; esac
  fi
  [ -n "$best" ] && printf '%s\n' "$best"
  return 0
}

cooling_hold() {  # $1 = repo dir, $2 = branch, $3 = pre-measured activity epoch
  local repo="$1" b="$2" act="$3" now ct age
  [ "$MIN_AGE" -gt 0 ] || return 1
  now="$(date +%s 2>/dev/null)"; case "$now" in ''|*[!0-9]*) return 0;; esac
  ct="$(git -C "$repo" log -1 --format=%ct "refs/heads/$b" 2>/dev/null)"
  case "$ct" in ''|*[!0-9]*) return 0;; esac      # no readable commit time: hold
  age=$((now - ct))
  case "$act" in ''|*[!0-9]*) ;; *) [ $((now - act)) -lt "$age" ] && age=$((now - act));; esac
  [ "$age" -lt "$MIN_AGE" ]
}

# The forge arm. A merged PR/MR counts ONLY when its base is the default branch
# and its head commit is exactly this branch's tip — a branch name proves
# nothing, least of all `ai/<agent>`, which is recreated every run and has a
# trail of merged PRs behind it. Sets FORGE_TIP to the SHA that matched.
FORGE_TIP=""
forge_says_merged() {  # $1 = repo dir, $2 = branch, $3 = branch tip sha
  local repo="$1" b="$2" tip="$3" url out
  FORGE_TIP=""
  [ -n "$tip" ] || return 1
  [ "$FORGE_BUDGET" -gt 0 ] || return 1
  # Without a `timeout` binary a degraded network turns this into a multi-minute
  # stall at turn end. Degrade to ancestor-only + advise instead.
  command -v timeout >/dev/null 2>&1 || return 1
  url="$(git -C "$repo" config --get remote.origin.url 2>/dev/null)"
  [ -n "$url" ] || return 1
  case "$url" in
    *github.com*)
      command -v gh >/dev/null 2>&1 || return 1
      FORGE_BUDGET=$((FORGE_BUDGET - 1))
      out="$( cd "$repo" 2>/dev/null && timeout "$FORGE_TIMEOUT" gh pr list --state merged \
              --head "$b" --base "$DEFAULT_BRANCH" --limit 20 --json headRefOid \
              --jq '.[].headRefOid' 2>/dev/null )"
      printf '%s\n' "$out" | grep -qx "$tip" || return 1
      FORGE_TIP="$tip"; return 0
      ;;
    *gitlab*)
      command -v glab >/dev/null 2>&1 || return 1
      command -v jq >/dev/null 2>&1 || return 1
      FORGE_BUDGET=$((FORGE_BUDGET - 1))
      out="$( cd "$repo" 2>/dev/null && timeout "$FORGE_TIMEOUT" glab mr list --state merged \
              --source-branch "$b" --target-branch "$DEFAULT_BRANCH" -F json 2>/dev/null )"
      printf '%s' "$out" | jq -e --arg tip "$tip" \
        'map(select((.sha // .merge_commit_sha // "") == $tip)) | length > 0' >/dev/null 2>&1 || return 1
      FORGE_TIP="$tip"; return 0
      ;;
    *) return 1;;
  esac
}

# Sets PROOF to ancestor|forge and returns 0, or clears it and returns 1.
# Nothing else may authorise a removal. Not a command substitution on purpose:
# the forge budget it spends has to survive the call.
PROOF=""
proof_of_merge() {  # $1 = repo dir, $2 = branch, $3 = branch tip sha
  local repo="$1" b="$2" tip="$3"
  PROOF=""
  if [ -n "$DEFAULT_REF_LOCAL" ] \
     && git -C "$repo" merge-base --is-ancestor "refs/heads/$b" "$DEFAULT_REF_LOCAL" 2>/dev/null; then
    PROOF="ancestor"; return 0
  fi
  if [ -n "$DEFAULT_REF_REMOTE" ] \
     && git -C "$repo" merge-base --is-ancestor "refs/heads/$b" "$DEFAULT_REF_REMOTE" 2>/dev/null; then
    PROOF="ancestor"; return 0
  fi
  if forge_says_merged "$repo" "$b" "$tip"; then PROOF="forge"; return 0; fi
  return 1
}

# `[gone]` upstream — what a `--delete-branch` / a forge's auto-delete leaves
# behind. Suggestive only; this never authorises a removal.
upstream_gone() {  # $1 = repo dir, $2 = branch
  git -C "$1" for-each-ref --format='%(upstream:track)' "refs/heads/$2" 2>/dev/null | grep -q 'gone'
}

# Counters + collected lines, shared by the report and the hook advisory.
N_REAPED=0; N_PRUNED=0; N_LIKELY=0; N_LEFT=0
C_DIRTY=0; C_UNMERGED=0; C_LOCKED=0; C_KEEP=0; C_CURRENT=0; C_REAPABLE_LEFT=0
C_UNSTARTED=0; C_COOLING=0
REAPED_LINES=""; LIKELY_LINES=""; READY_LINES=""

CUR_TOP=""   # the worktree the caller is standing in — never touched

sweep_repo() {  # $1 = dir inside repo, $2 = apply(1|0), $3 = records file
  local start="$1" apply="$2" out="$3"
  local list main_line main_wt main_branch p b flags status reason action tip prune_rc act

  command -v git >/dev/null 2>&1 || return 1
  git -C "$start" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  scratch || return 1
  list="$TMPD/wt"
  wt_list "$start" > "$list" 2>/dev/null
  [ -s "$list" ] || return 1

  main_line="$(head -n 1 "$list")"
  main_wt="$(abspath "$(printf '%s\n' "$main_line" | cut -f1)")"
  main_branch="$(printf '%s\n' "$main_line" | cut -f2)"; main_branch="${main_branch#refs/heads/}"
  resolve_default "$start" "$main_branch" || return 1
  # A guessed default branch may report, but it may never delete.
  [ "$DEFAULT_CONFIDENT" = 1 ] || apply=0

  # Registrations whose directory is already gone. This deletes the worktree's
  # admin dir (its HEAD reflog, refs/worktree/*), so it is an --apply action,
  # never something a dry run does behind the caller's back.
  prune_rc=1
  if [ "$apply" = 1 ] && grep -q 'prunable' "$list"; then
    git -C "$start" worktree prune >/dev/null 2>&1 && prune_rc=0
  fi

  while IFS="$(printf '\t')" read -r p b flags; do
    [ -n "$p" ] || continue
    p="$(abspath "$p")"
    b="${b#refs/heads/}"
    status=""; reason=""; action="none"; PROOF=""; tip=""
    act="$(worktree_activity "$p")"   # before anything here touches the tree

    case ",$flags" in *,bare,*) status="MAIN"; reason="bare repository";; esac
    if [ -z "$status" ] && [ "$p" = "$main_wt" ]; then
      status="MAIN"; reason="primary/integration worktree — never removed"
    fi
    if [ -z "$status" ] && [ -n "$CUR_TOP" ] && [ "$p" = "$CUR_TOP" ]; then
      status="CURRENT"; reason="the worktree this session is standing in"
    fi
    if [ -z "$status" ]; then
      case ",$flags" in *,prunable,*)
        status="PRUNABLE"; reason="registration points at a directory that is already gone"
        if [ "$apply" = 1 ]; then
          if [ "$prune_rc" = 0 ]; then action="pruned"; N_PRUNED=$((N_PRUNED+1)); else action="prune failed"; fi
        fi
      ;; esac
    fi
    if [ -z "$status" ]; then
      case ",$flags" in *,locked,*) status="LOCKED"; reason="locked — another session claims it";; esac
    fi
    if [ -z "$status" ] && [ -n "$KEEP_RE" ] && printf '%s\n' "$p" | grep -Eq "$KEEP_RE" 2>/dev/null; then
      status="KEEP"; reason="matches WORKTREE_REAP_KEEP_RE"
    fi
    if [ -z "$status" ]; then
      worktree_hold_reason "$p"
      [ -n "$WT_HOLD_REASON" ] && { status="DIRTY"; reason="$WT_HOLD_REASON"; }
    fi
    if [ -z "$status" ] && [ -z "$b" ]; then
      status="UNMERGED"; reason="detached HEAD — no branch whose merge could be proven"
    fi
    if [ -z "$status" ] && [ "$b" = "$DEFAULT_BRANCH" ]; then
      status="KEEP"; reason="checked out on the default branch ($DEFAULT_BRANCH)"
    fi
    if [ -z "$status" ]; then
      tip="$(git -C "$start" rev-parse --verify --quiet "refs/heads/$b" 2>/dev/null)"
      if [ -z "$tip" ]; then
        status="UNMERGED"; reason="branch tip could not be resolved"
      elif ! branch_started "$start" "$b" "$tip"; then
        status="UNSTARTED"
        reason="branch was created at the default tip and never committed — 'merged' here is ancestry being reflexive, not work being done"
      fi
    fi
    if [ -z "$status" ]; then
      if proof_of_merge "$start" "$b" "$tip"; then
        if cooling_hold "$start" "$b" "$act"; then
          status="COOLING"
          reason="merged (proof: $PROOF) but younger than WORKTREE_REAP_MIN_AGE=${MIN_AGE}s — another agent may still be in it; re-run with WORKTREE_REAP_MIN_AGE=0 to remove it now"
        else
          status="REAPABLE"; reason="branch merged into $DEFAULT_BRANCH (proof: $PROOF)"
        fi
      elif upstream_gone "$start" "$b"; then
        status="LIKELY-MERGED"
        reason="upstream is gone, which a squash merge leaves behind — likely, not proven"
      else
        status="UNMERGED"; reason="not merged into $DEFAULT_BRANCH"
      fi
    fi
    if [ "$DEFAULT_CONFIDENT" != 1 ] && [ "$status" = "REAPABLE" ]; then
      reason="$reason — but the default branch could not be resolved confidently (no origin/HEAD), so nothing is deleted"
    fi

    if [ "$status" = "REAPABLE" ] && [ "$apply" = 1 ]; then
      # No --force: git refuses a dirty or otherwise unsafe tree even if the
      # classification above somehow missed it.
      if git -C "$start" worktree remove "$p" >/dev/null 2>&1; then
        if git -C "$start" branch -d "$b" >/dev/null 2>&1; then
          action="removed; branch deleted"
        elif [ "$PROOF" = "forge" ] && [ -n "$FORGE_TIP" ] && [ "$FORGE_TIP" = "$tip" ] \
             && [ "$(git -C "$start" rev-parse --verify --quiet "refs/heads/$b" 2>/dev/null)" = "$tip" ] \
             && git -C "$start" branch -D "$b" >/dev/null 2>&1; then
          # -D only here: a merged PR into the default branch whose head SHA is
          # still exactly this tip. `git branch -d` cannot see a squash merge,
          # so its refusal is expected — but it is never itself the trigger.
          action="removed; branch deleted (-D — a merged PR's head SHA equals this exact tip)"
        else
          action="removed; branch KEPT (git refused -d and nothing proves forcing is safe)"
        fi
        N_REAPED=$((N_REAPED+1))
        REAPED_LINES="${REAPED_LINES}${p} (${b}) — ${action}
"
      else
        action="git refused to remove it — left in place"
      fi
    fi

    case "$status" in
      REAPABLE)
        if [ "$apply" != 1 ]; then
          C_REAPABLE_LEFT=$((C_REAPABLE_LEFT+1)); N_LEFT=$((N_LEFT+1))
          READY_LINES="${READY_LINES}${p} (${b}) — ${reason}
"
        fi
        ;;
      LIKELY-MERGED)
        N_LIKELY=$((N_LIKELY+1)); N_LEFT=$((N_LEFT+1))
        LIKELY_LINES="${LIKELY_LINES}${p} (${b}): git -C '${main_wt}' worktree remove '${p}' && git -C '${main_wt}' branch -d '${b}'
"
        ;;
      DIRTY)     C_DIRTY=$((C_DIRTY+1));         N_LEFT=$((N_LEFT+1));;
      UNMERGED)  C_UNMERGED=$((C_UNMERGED+1));   N_LEFT=$((N_LEFT+1));;
      LOCKED)    C_LOCKED=$((C_LOCKED+1));       N_LEFT=$((N_LEFT+1));;
      UNSTARTED) C_UNSTARTED=$((C_UNSTARTED+1)); N_LEFT=$((N_LEFT+1));;
      COOLING)   C_COOLING=$((C_COOLING+1));     N_LEFT=$((N_LEFT+1));;
      KEEP)      C_KEEP=$((C_KEEP+1));;
      CURRENT)   C_CURRENT=$((C_CURRENT+1));;
    esac

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$main_wt" "$p" "$b" "$status" "$reason" "$action" >> "$out"
  done < "$list"
  return 0
}

# ---------- hook mode ----------

emit_advisory() {  # $1 = message, $2 = raw hook input (for Cursor's loop_count)
  local msg="$1" input="${2:-}" loop_count
  case "$PLATFORM" in
    claude|codex) jq -nc --arg m "$msg" '{continue:true,systemMessage:$m}';;
    cursor)
      loop_count="$(printf '%s' "$input" | jq -r '.loop_count // 0' 2>/dev/null)"
      case "$loop_count" in ''|*[!0-9]*) loop_count=0;; esac
      [ "$loop_count" -gt 0 ] && return 0
      jq -nc --arg m "$msg" '{followup_message:$m}'
      ;;
    *) printf '%s\n' "$msg" >&2;;
  esac
  return 0
}

hook_mode() {
  local input mode active cwd common key state_dir stamp now last lastfp interval
  local apply records msg fp summary

  mode="${WORKTREE_REAP:-auto}"
  [ "$mode" = "off" ] && exit 0

  input="$(cat)"
  command -v jq >/dev/null 2>&1 || exit 0
  command -v git >/dev/null 2>&1 || exit 0

  # Compatibility guard if a host invokes Stop again while handling a prior hook.
  active="$(printf '%s' "$input" | jq -r '.stop_hook_active // .stopHookActive // false' 2>/dev/null)"
  [ "$active" = "true" ] && exit 0

  if ! keep_re_valid; then
    emit_advisory "Worktree reap: WORKTREE_REAP_KEEP_RE is not a valid extended regular expression, so the keep-list cannot be honoured and NO sweep ran. Fix or unset it." "$input"
    exit 0
  fi

  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"; [ -z "$cwd" ] && cwd="$PWD"
  [ -d "$cwd" ] || exit 0
  git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

  # Rate-limit per repository, not per worktree: the shared git dir is the key.
  common="$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null)"
  case "$common" in /*) ;; *) common="$(abspath "$cwd")/$common";; esac
  state_dir="${AI_NUDGE_STATE:-$HOME/.ai-logs}"; mkdir -p "$state_dir" 2>/dev/null || true
  key="$(printf '%s' "$common" | cksum | cut -d' ' -f1)"
  stamp="$state_dir/.worktree-reap.$key"
  # Two agents ending a turn in the same repo at the same moment would otherwise
  # both read a stale stamp and both sweep. Where flock exists the loser simply
  # skips this turn; where it does not, the rate limit still bounds the overlap.
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$stamp.lock" 2>/dev/null || true
    flock -n 9 2>/dev/null || exit 0
  fi
  interval="${WORKTREE_REAP_MIN_INTERVAL:-900}"
  case "$interval" in ''|*[!0-9]*) interval=900;; esac
  now="$(date +%s 2>/dev/null)"; case "$now" in ''|*[!0-9]*) now=0;; esac
  last=0; lastfp=""
  if [ -f "$stamp" ]; then
    last="$(sed -n 1p "$stamp" 2>/dev/null)"; lastfp="$(sed -n 2p "$stamp" 2>/dev/null)"
    case "$last" in ''|*[!0-9]*) last=0;; esac
  fi
  if [ "$now" -gt 0 ] && [ "$((now - last))" -lt "$interval" ]; then exit 0; fi

  CUR_TOP="$(abspath "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)")"
  apply=1; [ "$mode" = "advise" ] && apply=0

  scratch || exit 0
  records="$TMPD/records"; : > "$records"
  sweep_repo "$cwd" "$apply" "$records" || exit 0

  # Nothing reaped and nothing worth naming: stay quiet, but keep the stamp so
  # the next turn does no git work either.
  if [ "$N_REAPED" = 0 ] && [ "$N_PRUNED" = 0 ] && [ "$N_LIKELY" = 0 ] && [ "$C_REAPABLE_LEFT" = 0 ]; then
    printf '%s\n\n' "$now" > "$stamp" 2>/dev/null || true
    exit 0
  fi

  msg="Worktree reap (advisory)."
  if [ "$N_REAPED" -gt 0 ]; then
    msg="$msg Removed $N_REAPED provably-merged worktree(s): $(printf '%s' "$REAPED_LINES" | tr '\n' ';' | sed 's/;$//')."
  fi
  [ "$N_PRUNED" -gt 0 ] && msg="$msg Pruned $N_PRUNED stale registration(s) whose directory was already gone."
  if [ "$C_REAPABLE_LEFT" -gt 0 ]; then
    msg="$msg $C_REAPABLE_LEFT worktree(s) are provably merged and ready to remove, but nothing was deleted: $(printf '%s' "$READY_LINES" | tr '\n' ';' | sed 's/;$//')."
  fi
  summary=""
  [ "$C_DIRTY" -gt 0 ]     && summary="$summary $C_DIRTY holding uncommitted or non-regenerable files,"
  [ "$C_UNMERGED" -gt 0 ]  && summary="$summary $C_UNMERGED unmerged,"
  [ "$C_UNSTARTED" -gt 0 ] && summary="$summary $C_UNSTARTED never-started,"
  [ "$C_COOLING" -gt 0 ]   && summary="$summary $C_COOLING merged but inside the cooling window,"
  [ "$C_LOCKED" -gt 0 ]    && summary="$summary $C_LOCKED locked,"
  [ -n "$summary" ] && msg="$msg Left alone:${summary%,}."
  if [ "$N_LIKELY" -gt 0 ]; then
    msg="$msg $N_LIKELY likely merged but UNPROVEN (upstream gone — what a squash merge leaves behind); never auto-removed. Confirm the work is in the default branch, then run: $(printf '%s' "$LIKELY_LINES" | tr '\n' ';' | sed 's/;$//')."
  fi
  msg="$msg Only provably-merged trees are ever auto-removed, never with --force. Advisory only: report this in the handoff; do not continue the turn because of it."

  fp="$(printf '%s' "$msg" | cksum | tr -d ' ')"
  printf '%s\n%s\n' "$now" "$fp" > "$stamp" 2>/dev/null || true
  [ -n "$lastfp" ] && [ "$fp" = "$lastfp" ] && exit 0

  emit_advisory "$msg" "$input"
  exit 0
}

# ---------- CLI mode ----------

usage() {
  cat <<'USAGE'
worktree-reap.sh --sweep [--apply] [--all <dir>] [--json] [repo...]

  --sweep        report every registered worktree and its disposition (default:
                 a DRY RUN — nothing is removed)
  --apply        perform the safe removals: provably-merged worktrees (and their
                 branches) plus stale registrations
  --all <dir>    sweep every git repo found under <dir> (depth 3)
  --json         machine-readable records instead of the text report

Statuses: REAPABLE CURRENT MAIN LOCKED DIRTY UNMERGED LIKELY-MERGED PRUNABLE
          KEEP UNSTARTED COOLING
Only REAPABLE (proven merged, past the cooling window) is ever removed, and only
with --apply. WORKTREE_REAP_MIN_AGE=0 waives the cooling window — the right
thing for a command that just merged the branch itself.
USAGE
}

cli_mode() {
  local apply=0 json=0 alldir="" a
  local repos_file records seen key d

  while [ $# -gt 0 ]; do
    a="$1"
    case "$a" in
      --sweep)  ;;
      --apply)  apply=1;;
      --json)   json=1;;
      --all)    shift; alldir="${1:-}"; [ -n "$alldir" ] || { echo "--all needs a directory" >&2; exit 2; };;
      -h|--help) usage; exit 0;;
      -*)       echo "unknown option: $a" >&2; usage >&2; exit 2;;
      *)        REPO_ARGS="${REPO_ARGS}$a
";;
    esac
    shift
  done

  command -v git >/dev/null 2>&1 || { echo "git is required." >&2; exit 2; }
  keep_re_valid || { echo "WORKTREE_REAP_KEEP_RE is not a valid extended regular expression — refusing to sweep." >&2; exit 2; }
  scratch || { echo "could not create a scratch dir." >&2; exit 2; }
  repos_file="$TMPD/repos"; : > "$repos_file"
  records="$TMPD/records"; : > "$records"
  seen="$TMPD/seen"; : > "$seen"

  if [ -n "$alldir" ]; then
    find "$alldir" -maxdepth 3 -name .git 2>/dev/null | while IFS= read -r d; do
      [ -n "$d" ] && dirname "$d"
    done >> "$repos_file"
  fi
  printf '%s' "$REPO_ARGS" >> "$repos_file"
  [ -s "$repos_file" ] || printf '%s\n' "$PWD" > "$repos_file"

  CUR_TOP="$(abspath "$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)")"

  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -d "$d" ] || continue
    key="$(git -C "$d" rev-parse --git-common-dir 2>/dev/null)" || continue
    [ -n "$key" ] || continue
    case "$key" in /*) ;; *) key="$(abspath "$d")/$key";; esac
    grep -qxF "$key" "$seen" 2>/dev/null && continue
    printf '%s\n' "$key" >> "$seen"
    sweep_repo "$d" "$apply" "$records" || true
  done < "$repos_file"

  if [ "$json" = 1 ]; then
    if command -v jq >/dev/null 2>&1; then
      jq -R -s 'split("\n") | map(select(length > 0)) | map(split("\t"))
                | map({repo:.[0], worktree:.[1], branch:.[2], status:.[3], reason:.[4], action:.[5]})' \
        < "$records"
    else
      echo "jq is required for --json." >&2; exit 2
    fi
    return 0
  fi

  local repo p b status reason action last_repo=""
  while IFS="$(printf '\t')" read -r repo p b status reason action; do
    [ -n "$repo" ] || continue
    if [ "$repo" != "$last_repo" ]; then printf '== %s\n' "$repo"; last_repo="$repo"; fi
    if [ "$action" = "none" ]; then
      printf '  %-14s %s (%s) — %s\n' "$status" "$p" "${b:-detached}" "$reason"
    else
      printf '  %-14s %s (%s) — %s [%s]\n' "$status" "$p" "${b:-detached}" "$reason" "$action"
    fi
  done < "$records"

  if [ "$apply" = 1 ]; then
    printf 'Removed %s worktree(s); pruned %s stale registration(s); left %s.\n' "$N_REAPED" "$N_PRUNED" "$N_LEFT"
  else
    printf 'DRY RUN — nothing was removed. %s ready to reap; %s likely-merged but unproven; %s left.\n' \
      "$C_REAPABLE_LEFT" "$N_LIKELY" "$N_LEFT"
    printf 'Re-run with --apply to remove the REAPABLE ones (proven merged only).\n'
  fi
  if [ "$N_LIKELY" -gt 0 ]; then
    printf 'Likely merged, never auto-removed — confirm the work landed, then run:\n'
    printf '%s' "$LIKELY_LINES" | sed 's/^/  /'
  fi
  return 0
}

REPO_ARGS=""
if [ $# -eq 0 ]; then
  if [ -t 0 ]; then usage; exit 0; fi
  hook_mode
fi
cli_mode "$@"
