# shellcheck shell=bash
# shellcheck disable=SC2034  # PV_ACTION / PV_SAVED are outputs the sourcing script reads
# lib/preserve.sh — the install ledger (PLAN-install-preservation.md, phase 1).
#
# Sourced by the installers, never run. Every file an installer copies or
# deletes goes through pv_write / pv_delete, which can tell three cases apart
# that a plain `cmp new dest` cannot:
#
#   OURS     dest is byte-for-byte what this installer last wrote (the ledger)
#   SHIPPED  no ledger row yet, but dest is a version this repo once shipped
#            (its blob is in the source file's git history) — a stale install
#   CUSTOM   anything else: someone edited it, or we can't prove we wrote it
#
# OURS and SHIPPED are exact-blob proofs, so they're overwritten quietly (the
# old bytes are recoverable from base/ or git). CUSTOM is copied into
# preserved/ — never rotated, unlike *.bak.* — before it is replaced or
# deleted, and the run says so out loud. A symlinked dest is never written
# through: it might point into someone's dotfiles.
#
# State lives in ${AIGI_STATE_DIR:-~/.ai/install-state}:
#   manifest.tsv   path-id  path  class  canonical-blob  block-blob  kept-blob  kept-against  source  repo-commit  date
#   preserved.tsv  path-id  path  saved-as  reason  blob  date
#   base/<id>      the exact bytes we last wrote (phase 2's merge base)
#   preserved/     every CUSTOM version we replaced or deleted
#   lock/          held while a process writes; pid + start time + host
#
# Portable to bash 3.2 (macOS): no associative arrays, no mapfile, no ${x,,}.
# Callers must set DIR (the repo checkout) before sourcing. PV_REPO, the repo
# whose history counts as "shipped", defaults to it.

PV_STATE="${AIGI_STATE_DIR:-$HOME/.ai/install-state}"
PV_LOCKED=""

# ---- identity ---------------------------------------------------------------

# Blob id of a file. git's blob id is the same on every platform and is what
# git history already stores, which is what makes SHIPPED a set lookup. With
# no git, fall back to sha256 (SHIPPED is then simply never matched).
pv_blob() {  # $1 = file
  if command -v git >/dev/null 2>&1; then
    git hash-object --no-filters -- "$1" 2>/dev/null
  elif command -v sha256sum >/dev/null 2>&1; then
    printf 'sha256:%s\n' "$(sha256sum < "$1" | cut -d' ' -f1)"
  else
    printf 'sha256:%s\n' "$(shasum -a 256 < "$1" | cut -d' ' -f1)"
  fi
}

# A short, filename-safe id for a path. Encoding the path itself can blow
# past the 255-byte NAME_MAX on deep paths; the real path lives in the ledger.
pv_pathid() {  # $1 = path
  if command -v git >/dev/null 2>&1; then
    printf '%s' "$1" | git hash-object --stdin | cut -c1-16
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -c1-16
  else
    printf '%s' "$1" | shasum -a 256 | cut -c1-16
  fi
}

pv_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ---- lock -------------------------------------------------------------------

# A process's start time, used to tell a live lock holder from a reused pid.
# Empty where `ps -o lstart=` isn't supported (some minimal containers).
pv_proc_start() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' '; }

# Short, lower-case host name, so `macbook` and `MacBook.local` (a network
# change, a DHCP rename) still count as the same machine.
pv_host() { hostname 2>/dev/null | cut -d. -f1 | tr '[:upper:]' '[:lower:]'; }

# Is the recorded holder still running? kill -0 decides liveness. The start
# time only rules out a reused pid. If ps can't report start times, a live
# pid is trusted as the holder: when in doubt, fail closed, never take over.
pv_alive() {  # $1 = pid  $2 = recorded start time (may be empty)
  kill -0 "$1" 2>/dev/null || return 1
  local now; now="$(pv_proc_start "$1")"
  [ -z "$2" ] || [ -z "$now" ] || [ "$now" = "$2" ]
}

# True when a path was last modified more than $2 minutes ago (GNU and BSD find).
pv_older_than() { [ -n "$(find "$1" -maxdepth 0 -mmin +"$2" 2>/dev/null)" ]; }

# Take the ledger lock once per process. A lock is a directory (mkdir is
# atomic) holding an owner file: pid, start time, host, epoch seconds.
#
# install.sh runs its layers one after another, and no layer can rely on an
# EXIT trap the script already owns, so a finished layer leaves its lock
# behind. The next layer finds the holder dead and takes over. That's the
# normal path, not an error.
#
# Judging a lock stale and clearing it happen under a second, short-lived
# mutex (lock.reap). Without it, two runs could both judge one stale lock
# dead, and the slower one would clear the lock the faster one had just
# taken. Stale means:
#   - the holder is dead on this host;
#   - or the lock is on another host and over 2 hours old;
#   - or it has no owner file and is over a minute old (killed mid-acquire).
# A reaper that dies inside its few-millisecond window leaves lock.reap behind,
# and it's cleared after a minute. `install.sh --unlock` clears both by hand.
pv_lock() {
  [ -n "$PV_LOCKED" ] && return 0
  mkdir -p "$PV_STATE" || return 1
  local l="$PV_STATE/lock" r="$PV_STATE/lock.reap" tries=0 pid start host age stale
  while [ "$tries" -lt 10 ]; do
    tries=$((tries+1))
    if mkdir "$l" 2>/dev/null; then
      # Write the owner file whole, then rename it in, so no reader ever sees half of one.
      printf '%s\n%s\n%s\n%s\n' "$$" "$(pv_proc_start $$)" "$(pv_host)" "$(date +%s)" > "$l/.owner.$$" \
        && mv "$l/.owner.$$" "$l/owner"
      PV_LOCKED=1
      return 0
    fi
    if ! mkdir "$r" 2>/dev/null; then
      pv_older_than "$r" 1 && rm -rf "$r"
      sleep 1; continue
    fi
    pid="$(sed -n 1p "$l/owner" 2>/dev/null)"; start="$(sed -n 2p "$l/owner" 2>/dev/null)"
    host="$(sed -n 3p "$l/owner" 2>/dev/null)"; age="$(sed -n 4p "$l/owner" 2>/dev/null)"
    stale=""
    if [ ! -d "$l" ]; then
      stale=gone                                   # released while we waited
    elif [ -z "$pid" ]; then
      pv_older_than "$l" 1 && stale=yes            # killed mid-acquire
    elif [ "$host" = "$(pv_host)" ]; then
      pv_alive "$pid" "$start" || stale=yes
    elif [ $(( $(date +%s) - ${age:-0} )) -ge 7200 ]; then
      stale=yes
    fi
    if [ -z "$stale" ]; then
      rmdir "$r" 2>/dev/null
      if [ -z "$pid" ]; then sleep 1; continue; fi  # another run is mid-acquire
      if [ "$host" = "$(pv_host)" ]; then
        echo "  install-state is locked by a running install (pid $pid) — try again when it finishes" >&2
      else
        echo "  install-state is locked by host $host (under 2h old) — if that run is gone: ./install.sh --unlock" >&2
      fi
      return 1
    fi
    [ "$stale" = yes ] && rm -rf "$l"
    rmdir "$r" 2>/dev/null
  done
  echo "  could not take the install-state lock at $l — if no install is running: ./install.sh --unlock" >&2
  return 1
}

# ---- ledger -----------------------------------------------------------------

# The blob we last recorded for a path, or nothing.
pv_recorded() {  # $1 = path
  local id; id="$(pv_pathid "$1")"
  [ -f "$PV_STATE/manifest.tsv" ] || return 0
  awk -F'\t' -v id="$id" '$1 == id { b = $4 } END { if (b != "") print b }' "$PV_STATE/manifest.tsv"
}

# Record what is now at $1 as written by us: one row per path, replaced in
# place via a temp file in the same dir (atomic rename).
pv_record() {  # $1 = path  $2 = class  $3 = source label
  local p="$1" id blob tmp commit
  id="$(pv_pathid "$p")"; blob="$(pv_blob "$p")"
  commit="$(git -C "${PV_REPO:-${DIR:-.}}" rev-parse --short HEAD 2>/dev/null || echo -)"
  mkdir -p "$PV_STATE/base"
  cp -p "$p" "$PV_STATE/base/$id" 2>/dev/null || true
  tmp="$(mktemp "$PV_STATE/.manifest.XXXXXX")" || return 1
  { [ -f "$PV_STATE/manifest.tsv" ] && awk -F'\t' -v id="$id" '$1 != id' "$PV_STATE/manifest.tsv"
    printf '%s\t%s\t%s\t%s\t-\t-\t-\t%s\t%s\t%s\n' "$id" "$p" "$2" "$blob" "$3" "$commit" "$(pv_now)"
  } > "$tmp" && mv "$tmp" "$PV_STATE/manifest.tsv"
}

pv_forget() {  # $1 = path — drop its ledger row (after a delete)
  local id tmp; id="$(pv_pathid "$1")"
  [ -f "$PV_STATE/manifest.tsv" ] || return 0
  tmp="$(mktemp "$PV_STATE/.manifest.XXXXXX")" || return 1
  awk -F'\t' -v id="$id" '$1 != id' "$PV_STATE/manifest.tsv" > "$tmp" && mv "$tmp" "$PV_STATE/manifest.tsv"
  rm -f "$PV_STATE/base/$id"
}

# Blob ids of every role port (roles/{codex,cursor,antigravity}/*) that
# render-roles.sh produced at the last 30 commits touching the roles. Ports are
# generated, never committed, so their history has to be re-rendered. Built
# lazily, only when a port differs from the new one and has no ledger row
# (that is, at bootstrap). Cached per HEAD. Prints the cache file's path.
pv_port_blobs() {
  local repo="${PV_REPO:-${DIR:-.}}" head cache c d f
  head="$(git -C "$repo" rev-parse --short HEAD 2>/dev/null)" || return 1
  cache="$PV_STATE/.shipped-ports.$head"
  if [ ! -s "$cache" ]; then
    mkdir -p "$PV_STATE" || return 1
    rm -f "$PV_STATE"/.shipped-ports.* 2>/dev/null
    : > "$cache.tmp.$$"
    for c in $(git -C "$repo" log -n 30 --format=%h -- roles render-roles.sh 2>/dev/null); do
      d="$(mktemp -d "${TMPDIR:-/tmp}/aigi_ports.XXXXXX")" || continue
      if git -C "$repo" archive "$c" 2>/dev/null | tar -x -C "$d" 2>/dev/null \
         && [ -x "$d/render-roles.sh" ] && (cd "$d" && ./render-roles.sh >/dev/null 2>&1); then
        for f in "$d"/roles/codex/* "$d"/roles/cursor/* "$d"/roles/antigravity/*; do
          [ -f "$f" ] && pv_blob "$f" >> "$cache.tmp.$$"
        done
      fi
      rm -rf "$d"
    done
    sort -u "$cache.tmp.$$" > "$cache" && rm -f "$cache.tmp.$$"
  fi
  printf '%s\n' "$cache"
}

# True when dest's blob appears anywhere in the history of the repo file that
# produced it. -m includes merge commits, so a blob that only ever landed via
# a merge still counts. "render:roles" means a role port (see pv_port_blobs).
# Empty src = a generated file with no history.
pv_shipped() {  # $1 = dest  $2 = repo-relative source path, "render:roles", or empty
  [ -n "${2:-}" ] || return 1
  command -v git >/dev/null 2>&1 || return 1
  local b cache; b="$(pv_blob "$1")"
  if [ "$2" = "render:roles" ]; then
    cache="$(pv_port_blobs)" || return 1
    grep -qxF "$b" "$cache"
    return
  fi
  git -C "${PV_REPO:-${DIR:-.}}" log --all -m --format= --raw --no-abbrev -- "$2" 2>/dev/null \
    | awk -v b="$b" '$3 == b || $4 == b { f = 1 } END { exit !f }'
}

# Classify an existing dest that differs from the new content.
pv_classify() {  # $1 = dest  $2 = repo-relative source (or empty)
  local rec; rec="$(pv_recorded "$1")"
  if [ -n "$rec" ]; then
    # With a ledger row, only an exact match is ours. Anything else was
    # changed after we wrote it — even a deliberate revert to an old version.
    if [ "$rec" = "$(pv_blob "$1")" ]; then echo OURS; else echo CUSTOM; fi
    return 0
  fi
  if pv_shipped "$1" "${2:-}"; then echo SHIPPED; else echo CUSTOM; fi
}

# Copy a file into preserved/ (never rotated) and log it.
pv_preserve() {  # $1 = path  $2 = reason
  local id saved
  id="$(pv_pathid "$1")"
  mkdir -p "$PV_STATE/preserved" || return 1
  saved="$(mktemp "$PV_STATE/preserved/$id.$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")" || return 1
  cp -p "$1" "$saved" || return 1
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$1" "$saved" "$2" "$(pv_blob "$1")" "$(pv_now)" \
    >> "$PV_STATE/preserved.tsv"
  PV_SAVED="$saved"
}

# Put $1's bytes at $2 by writing a temp file in the same directory and
# renaming it over the destination. A rename replaces the directory entry
# itself, so it can never write through a symlink, even one that appeared
# after our check. An existing destination keeps its permission bits.
pv_put() {  # $1 = source file  $2 = dest
  local tmp; tmp="$(mktemp "$(dirname "$2")/.aigi.XXXXXX")" || return 1
  if [ -f "$2" ] && [ ! -L "$2" ]; then cp -p "$2" "$tmp" && cat "$1" > "$tmp"; else cp "$1" "$tmp"; fi \
    && mv -f "$tmp" "$2" || { rm -f "$tmp"; return 1; }
}

# ---- the two verbs -----------------------------------------------------------

# Install $2 at $3. Returns 0 when dest now holds the new content (or was
# deliberately left alone), 1 on a real failure. Sets PV_ACTION to one of
# created | current | updated | replaced-custom | skipped-symlink, so callers
# can count and report. $4 = repo-relative source for the SHIPPED check
# ("render:roles" for a role port; omit for other generated files).
#
# What gets a copy in preserved/: CUSTOM always, and SHIPPED too. A SHIPPED
# file is either a stale install or a deliberate revert to an old version, and
# without a ledger row nothing can tell those apart, so it's kept. That happens
# once per file, on the first ledger run. OURS is never copied: it's
# byte-for-byte what base/ already holds, and copying it would save every old
# role and playbook on every upgrade.
pv_write() {  # $1 = class  $2 = new content file  $3 = dest  [$4 = repo-relative source]
  local class="$1" src="$2" dest="$3" rel="${4:-}" verdict
  PV_ACTION=""; PV_SAVED=""
  pv_lock || return 1
  if [ -L "$dest" ]; then
    echo "  note: $dest is a symlink — left alone (never written through); the new version is at $src" >&2
    PV_ACTION=skipped-symlink; return 0
  fi
  mkdir -p "$(dirname "$dest")" || return 1
  if [ ! -e "$dest" ]; then
    pv_put "$src" "$dest" || return 1
    pv_record "$dest" "$class" "${rel:-generated}"; PV_ACTION=created; return 0
  fi
  if cmp -s "$src" "$dest"; then
    # Identical: no write. Adopt it into the ledger if it isn't there yet,
    # which is how a machine installed before the ledger gets its rows.
    [ -n "$(pv_recorded "$dest")" ] || pv_record "$dest" "$class" "${rel:-generated}"
    PV_ACTION=current; return 0
  fi
  verdict="$(pv_classify "$dest" "$rel")"
  case "$verdict" in
    CUSTOM)
      pv_preserve "$dest" "replaced by install" || { echo "  could not preserve $dest — left unchanged" >&2; return 1; }
      PV_ACTION=replaced-custom
      if [ -n "$(pv_recorded "$dest")" ] || [ -n "$rel" ]; then
        echo "  replaced your edited $dest — your version: $PV_SAVED" >&2
      else
        echo "  replaced $dest (couldn't prove it was unedited) — previous version: $PV_SAVED" >&2
      fi;;
    SHIPPED)
      pv_preserve "$dest" "older shipped version, first ledger run" \
        || { echo "  could not preserve $dest — left unchanged" >&2; return 1; }
      PV_ACTION=updated;;
    *) PV_ACTION=updated;;
  esac
  pv_put "$src" "$dest" || return 1
  pv_record "$dest" "$class" "${rel:-generated}"
}

# Delete dest because the installer no longer ships it (a toggle, a rename).
# OURS goes quietly; SHIPPED and CUSTOM are preserved first (as in pv_write).
# A symlink is left alone.
pv_delete() {  # $1 = dest  $2 = reason  [$3 = repo-relative source]
  local dest="$1" verdict
  PV_ACTION=""; PV_SAVED=""
  [ -e "$dest" ] || [ -L "$dest" ] || { PV_ACTION=absent; return 0; }
  pv_lock || return 1
  if [ -L "$dest" ]; then echo "  note: $dest is a symlink — not removed" >&2; PV_ACTION=skipped-symlink; return 0; fi
  verdict="$(pv_classify "$dest" "${3:-}")"
  if [ "$verdict" != OURS ]; then
    pv_preserve "$dest" "$2" || { echo "  could not preserve $dest — not removed" >&2; return 1; }
    [ "$verdict" = CUSTOM ] && echo "  removed $dest ($2) — your version: $PV_SAVED" >&2
  fi
  rm -f "$dest" || return 1
  pv_forget "$dest"; PV_ACTION=removed
}
