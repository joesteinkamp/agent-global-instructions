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
pv_proc_start() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' '; }

# Take the ledger lock once per process. A holder that is dead (or whose pid
# was reused by another process) on this host is taken over silently — that is
# the normal case, since install.sh runs its layers one after another and no
# layer can rely on an EXIT trap the script already owns. A lock older than
# two hours is stale on any host. Takeover renames the old lock first: rename
# is atomic, so two runs racing for one stale lock can't both win.
pv_lock() {
  [ -n "$PV_LOCKED" ] && return 0
  mkdir -p "$PV_STATE" || return 1
  local l="$PV_STATE/lock" tries=0 pid start host age
  while [ "$tries" -lt 3 ]; do
    tries=$((tries+1))
    if mkdir "$l" 2>/dev/null; then
      printf '%s\n%s\n%s\n%s\n' "$$" "$(pv_proc_start $$)" "$(hostname 2>/dev/null)" "$(date +%s)" > "$l/owner"
      PV_LOCKED=1
      return 0
    fi
    pid="$(sed -n 1p "$l/owner" 2>/dev/null)"; start="$(sed -n 2p "$l/owner" 2>/dev/null)"
    host="$(sed -n 3p "$l/owner" 2>/dev/null)"; age="$(sed -n 4p "$l/owner" 2>/dev/null)"
    # owner not written yet: another run is mid-acquire. Give it a moment.
    if [ -z "$pid" ]; then sleep 1; continue; fi
    if [ "$host" = "$(hostname 2>/dev/null)" ] && [ -n "$(pv_proc_start "$pid")" ] \
       && [ "$(pv_proc_start "$pid")" = "$start" ]; then
      echo "  install-state is locked by a running install (pid $pid) — try again when it finishes" >&2
      return 1
    fi
    if [ "$host" != "$(hostname 2>/dev/null)" ] && [ $(( $(date +%s) - ${age:-0} )) -lt 7200 ]; then
      echo "  install-state is locked by host $host (under 2h old); remove $l if that run is gone" >&2
      return 1
    fi
    mv "$l" "$l.stale.$$" 2>/dev/null && rm -rf "$l.stale.$$"
  done
  echo "  could not take the install-state lock at $l" >&2
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

# True when dest's blob appears anywhere in the history of the repo file that
# produced it. -m includes merge commits, so a blob that only ever landed via
# a merge still counts. Empty src = a generated file with no history.
pv_shipped() {  # $1 = dest  $2 = repo-relative source path (or empty)
  [ -n "${2:-}" ] || return 1
  command -v git >/dev/null 2>&1 || return 1
  local b; b="$(pv_blob "$1")"
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

# Copy a CUSTOM file into preserved/ (never rotated) and log it.
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

# ---- the two verbs -----------------------------------------------------------

# Install $2 at $3. Returns 0 when dest now holds the new content (or was
# deliberately left alone), 1 on a real failure. Sets PV_ACTION to one of
# created | current | updated | replaced-custom | skipped-symlink, so callers
# can count and report. $4 = repo-relative source for the SHIPPED check
# (omit for generated files).
pv_write() {  # $1 = class  $2 = new content file  $3 = dest  [$4 = repo-relative source]
  local class="$1" src="$2" dest="$3" rel="${4:-}" verdict
  PV_ACTION=""; PV_SAVED=""
  if [ -L "$dest" ]; then
    echo "  note: $dest is a symlink — left alone (never written through); the new version is at $src" >&2
    PV_ACTION=skipped-symlink; return 0
  fi
  pv_lock || return 1
  mkdir -p "$(dirname "$dest")" || return 1
  if [ ! -e "$dest" ]; then
    cp "$src" "$dest" || return 1
    pv_record "$dest" "$class" "${rel:-generated}"; PV_ACTION=created; return 0
  fi
  if cmp -s "$src" "$dest"; then
    # Identical: no write. Adopt it into the ledger if it isn't there yet,
    # which is how a machine installed before the ledger gets its rows.
    [ -n "$(pv_recorded "$dest")" ] || pv_record "$dest" "$class" "${rel:-generated}"
    PV_ACTION=current; return 0
  fi
  verdict="$(pv_classify "$dest" "$rel")"
  if [ "$verdict" = CUSTOM ]; then
    pv_preserve "$dest" "replaced by install" || { echo "  could not preserve $dest — left unchanged" >&2; return 1; }
    PV_ACTION=replaced-custom
    if [ -n "$(pv_recorded "$dest")" ] || [ -n "$rel" ]; then
      echo "  replaced your edited $dest — your version: $PV_SAVED" >&2
    else
      echo "  replaced $dest (couldn't prove it was unedited) — previous version: $PV_SAVED" >&2
    fi
  else
    PV_ACTION=updated
  fi
  cp "$src" "$dest" || return 1
  pv_record "$dest" "$class" "${rel:-generated}"
}

# Delete dest because the installer no longer ships it (a toggle, a rename).
# OURS/SHIPPED go quietly; CUSTOM is preserved first. A symlink is left alone.
pv_delete() {  # $1 = dest  $2 = reason  [$3 = repo-relative source]
  local dest="$1" verdict
  PV_ACTION=""; PV_SAVED=""
  [ -e "$dest" ] || [ -L "$dest" ] || { PV_ACTION=absent; return 0; }
  if [ -L "$dest" ]; then echo "  note: $dest is a symlink — not removed" >&2; PV_ACTION=skipped-symlink; return 0; fi
  pv_lock || return 1
  verdict="$(pv_classify "$dest" "${3:-}")"
  if [ "$verdict" = CUSTOM ]; then
    pv_preserve "$dest" "$2" || { echo "  could not preserve $dest — not removed" >&2; return 1; }
    echo "  removed $dest ($2) — your version: $PV_SAVED" >&2
  fi
  rm -f "$dest" || return 1
  pv_forget "$dest"; PV_ACTION=removed
}
