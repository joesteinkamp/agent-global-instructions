# shellcheck shell=bash
# shellcheck disable=SC2034  # PV_ACTION / PV_SAVED are outputs the sourcing script reads
# lib/preserve.sh — the install ledger (PLAN-install-preservation.md).
#
# Sourced by the installers, never run. Every file an installer copies or
# deletes goes through pv_write / pv_delete, which can tell three cases apart
# that a plain `cmp new dest` cannot:
#
#   PINNED   the path is in pins: the installer never writes it
#   OURS     dest is byte-for-byte what this installer last wrote (the ledger)
#   SHIPPED  no ledger row yet, but dest is a version this repo once shipped
#            (its blob is in the source file's git history) — a stale install
#   KEPT     you chose to keep your version against exactly this new version
#   CUSTOM   anything else: someone edited it, or we can't prove we wrote it
#
# OURS and SHIPPED are exact-blob proofs, so they're overwritten quietly (the
# old bytes are recoverable from base/ or git). CUSTOM is decided: an
# unattended run replaces it (after a copy into preserved/, never rotated,
# unlike *.bak.*); an attended one parks it and asks once, at the end of the
# run. A symlinked dest is never written through: it might point into
# someone's dotfiles.
#
# "Canonical part": a playbook can carry an aigi:preserved block (your lines,
# appended by [a]) and model-routing.md a generated block (owned by
# /update-model-routing). Both are left out when comparing against the ledger,
# so editing inside them never makes the file look edited.
#
# State lives in ${AIGI_STATE_DIR:-~/.ai/install-state}:
#   manifest.tsv   path-id  path  class  canonical-blob  block-blob  kept-blob  kept-against  source  repo-commit  date
#   preserved.tsv  path-id  path  saved-as  reason  blob  date  class  base-saved  new-saved  status
#   base/<id>      the canonical bytes we last wrote (the append-merge's base)
#   preserved/     every CUSTOM version we replaced or deleted, with its base and
#                  the version that replaced it (<saved>.base, <saved>.new)
#   orig/<id>      the first original we displaced at a pointer path, kept forever
#   new/<id>       the new version you declined with [k]
#   pins           paths you own outright, one per line
#   last-run.json  what the last run did, for agents (see pv_write_last_run)
#   layers/        the personal layers of the last global render (my-context.env, …)
#   lock/          held while a process writes; pid + start time + host
#
# A run: install.sh exports AIGI_RUN_DIR (actions.tsv, parked.tsv, parked/),
# AIGI_UNATTENDED (1/0) and, for --plan, AIGI_PHASE=plan. A layer run on its
# own makes its own run dir and closes it with pv_finish.
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


# ---- run context ------------------------------------------------------------

PV_BEGIN='<!-- aigi:preserved begin'
PV_END='<!-- aigi:preserved end -->'

pv_planning() { [ "${AIGI_PHASE:-}" = plan ]; }

# Can anyone answer a question? install.sh decides once and exports
# AIGI_UNATTENDED; a layer run on its own works it out. /dev/tty must actually
# open: `[ -r /dev/tty ]` is true even when there's no terminal behind it.
pv_unattended() {
  case "${AIGI_UNATTENDED:-}" in 1) return 0;; 0) return 1;; esac
  if (: < "${AIGI_TTY:-/dev/tty}") 2>/dev/null; then return 1; fi
  return 0
}

# Where answers come from. Tests point AIGI_TTY at a file of answers.
pv_tty() { printf '%s\n' "${AIGI_TTY:-/dev/tty}"; }

# The run dir that collects this run's actions and parked files. install.sh
# makes one for all six layers; a layer run alone makes its own (PV_OWN_RUN)
# and must call pv_finish. A plan run's dir is a temp dir: --plan writes nothing.
pv_run_init() {
  [ -n "${AIGI_RUN_DIR:-}" ] && [ -d "$AIGI_RUN_DIR" ] && return 0
  if pv_planning; then
    AIGI_RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aigi_plan.XXXXXX")" || return 1
  else
    mkdir -p "$PV_STATE" || return 1
    AIGI_RUN_DIR="$(mktemp -d "$PV_STATE/run.XXXXXX")" || return 1
  fi
  PV_OWN_RUN=1
  export AIGI_RUN_DIR
}

# Where caches go: the state dir, except in a plan run (which writes nothing).
pv_cache_dir() { if pv_planning; then printf '%s\n' "$AIGI_RUN_DIR"; else printf '%s\n' "$PV_STATE"; fi; }

# One row per decision: path class verdict action saved-at ai. The report and
# last-run.json read the last row per path.
pv_log() {  # $1 = path  $2 = class
  [ -n "${AIGI_RUN_DIR:-}" ] || return 0
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "${PV_VERDICT:--}" "${PV_ACTION:--}" "${PV_SAVED:--}" "${PV_AI:--}" \
    >> "$AIGI_RUN_DIR/actions.tsv"
}

# What an unattended run does with an edited file: INSTALL_ON_CONFLICT in
# my-context.env or --on-conflict, exported by install.sh. D1: replace.
pv_policy() {
  case "${AIGI_ON_CONFLICT:-replace}" in append) echo append;; keep) echo keep;; *) echo replace;; esac
}

pv_pinned() {  # $1 = path
  [ -f "$PV_STATE/pins" ] && grep -qxF -- "$1" "$PV_STATE/pins"
}

# ---- canonical part ---------------------------------------------------------

# none | ok | damaged — the state of a file's aigi:preserved block. Exactly one
# begin, then exactly one end, each at the start of a line; anything else is
# damaged, and a damaged file is never guessed at: it's CUSTOM.
pv_block_state() {  # $1 = file
  awk -v b="$PV_BEGIN" -v e="$PV_END" '
    index($0, b) == 1 { nb++; if (!bl) bl = NR }
    $0 == e           { ne++; if (!el) el = NR }
    END {
      if (nb == 0 && ne == 0) print "none"
      else if (nb == 1 && ne == 1 && bl < el) print "ok"
      else print "damaged"
    }' "$1"
}

# Same test for model-routing.md's generated block.
pv_gen_ok() {  # $1 = file
  awk '/^<!-- generated:begin/ { nb++; if (!b) b = NR }
       /^<!-- generated:end/   { ne++; if (!e) e = NR }
       END { exit !(nb == 1 && ne == 1 && b < e) }' "$1"
}

# Print a file's canonical part: what the ledger compares. A playbook's
# preserved block (and the one blank line the append put before it) and
# model-routing.md's generated block are left out; everything else is whole.
pv_canon() {  # $1 = file  $2 = class
  if [ "$2" = model-routing ] && pv_gen_ok "$1"; then
    awk '/^<!-- generated:begin/ { skip = 1; next }
         skip && /^<!-- generated:end/ { skip = 0; next }
         !skip { print }' "$1"
  elif [ "$2" = playbook ] && [ "$(pv_block_state "$1")" = ok ]; then
    awk -v b="$PV_BEGIN" -v e="$PV_END" '
      held { held = 0; if (index($0, b) != 1) print "" }
      index($0, b) == 1 { skip = 1; next }
      skip { if ($0 == e) skip = 0; next }
      $0 == "" { held = 1; next }
      { print }
      END { if (held) print "" }' "$1"
  else
    cat "$1"
  fi
}

# Print just the preserved block, markers included (nothing when there's none).
pv_block() {  # $1 = file
  [ "$(pv_block_state "$1")" = ok ] || return 0
  awk -v b="$PV_BEGIN" -v e="$PV_END" 'index($0, b) == 1 { on = 1 } on { print } on && $0 == e { exit }' "$1"
}

pv_canon_blob() {  # $1 = file  $2 = class
  local t b; t="$(mktemp "${TMPDIR:-/tmp}/aigi_canon.XXXXXX")" || return 1
  pv_canon "$1" "$2" > "$t"; b="$(pv_blob "$t")"; rm -f "$t"; printf '%s\n' "$b"
}

# The new content for dest: the source, plus dest's preserved block carried
# forward byte for byte (a playbook only). Prints the temp file's path.
pv_compose() {  # $1 = source  $2 = dest  $3 = class
  local out; out="$(mktemp "$AIGI_RUN_DIR/new.XXXXXX")" || return 1
  cat "$1" > "$out"
  if [ "$3" = playbook ] && [ -f "$2" ] && [ "$(pv_block_state "$2")" = ok ]; then
    printf '\n' >> "$out"; pv_block "$2" >> "$out"
  fi
  printf '%s\n' "$out"
}

# ---- ledger -----------------------------------------------------------------

# One manifest field for a path ($2 = column number), or nothing.
pv_field() {  # $1 = path  $2 = column
  local id; id="$(pv_pathid "$1")"
  [ -f "$PV_STATE/manifest.tsv" ] || return 0
  awk -F'\t' -v id="$id" -v n="$2" '$1 == id { v = $n } END { if (v != "" && v != "-") print v }' "$PV_STATE/manifest.tsv"
}

# The canonical blob we last recorded for a path, or nothing.
pv_recorded() { pv_field "$1" 4; }
pv_has_row() {  # $1 = path
  local id; id="$(pv_pathid "$1")"
  [ -f "$PV_STATE/manifest.tsv" ] && awk -F'\t' -v id="$id" '$1 == id { f = 1 } END { exit !f }' "$PV_STATE/manifest.tsv"
}

# Replace a path's manifest row (atomic: temp file in the same dir, renamed).
pv_put_row() {  # $1 = path  $2 = the full new row, or empty to drop it
  local id tmp; id="$(pv_pathid "$1")"
  tmp="$(mktemp "$PV_STATE/.manifest.XXXXXX")" || return 1
  { [ -f "$PV_STATE/manifest.tsv" ] && awk -F'\t' -v id="$id" '$1 != id' "$PV_STATE/manifest.tsv"
    [ -n "$2" ] && printf '%s\n' "$2"
  } > "$tmp"; mv "$tmp" "$PV_STATE/manifest.tsv"
}

# Record what is now at $1 as written by us: its canonical blob, its block's
# blob, and the canonical bytes in base/. Clears any [k] decision.
pv_record() {  # $1 = path  $2 = class  $3 = source label
  local p="$1" id canon block commit bt
  id="$(pv_pathid "$p")"
  mkdir -p "$PV_STATE/base"
  pv_canon "$p" "$2" > "$PV_STATE/base/$id" 2>/dev/null || true
  canon="$(pv_blob "$PV_STATE/base/$id")"
  block=-
  if [ "$2" = playbook ] && [ "$(pv_block_state "$p")" = ok ]; then
    bt="$(mktemp "${TMPDIR:-/tmp}/aigi_blk.XXXXXX")"; pv_block "$p" > "$bt"; block="$(pv_blob "$bt")"; rm -f "$bt"
  fi
  commit="$(git -C "${PV_REPO:-${DIR:-.}}" rev-parse --short HEAD 2>/dev/null || echo -)"
  pv_put_row "$p" "$(printf '%s\t%s\t%s\t%s\t%s\t-\t-\t%s\t%s\t%s' "$id" "$p" "$2" "$canon" "$block" "$3" "$commit" "$(pv_now)")"
}

# [k]: remember that you kept this version against this new one. The row
# keeps whatever we last wrote (or "-" if we never wrote it).
pv_mark_kept() {  # $1 = path  $2 = class  $3 = new content file  $4 = source label
  local p="$1" id row
  id="$(pv_pathid "$p")"
  row="$(awk -F'\t' -v id="$id" '$1 == id' "$PV_STATE/manifest.tsv" 2>/dev/null | tail -n 1)"
  [ -n "$row" ] || row="$(printf '%s\t%s\t%s\t-\t-\t-\t-\t%s\t-\t-' "$id" "$p" "$2" "${4:-generated}")"
  row="$(printf '%s\n' "$row" | awk -F'\t' -v OFS='\t' -v kb="$(pv_canon_blob "$p" "$2")" -v ka="$(pv_canon_blob "$3" "$2")" -v d="$(pv_now)" \
    '{ $6 = kb; $7 = ka; $10 = d; print }')"
  pv_put_row "$p" "$row"
}

pv_forget() {  # $1 = path — drop its ledger row (after a delete)
  local id; id="$(pv_pathid "$1")"
  [ -f "$PV_STATE/manifest.tsv" ] || return 0
  pv_put_row "$1" ""
  rm -f "$PV_STATE/base/$id"
}

# Blob ids of every role port (roles/{codex,cursor,antigravity}/*) that
# render-roles.sh produced at the last 30 commits touching the roles. Ports are
# generated, never committed, so their history has to be re-rendered. Built
# lazily, only when a port differs from the new one and has no ledger row
# (that is, at bootstrap). Cached per HEAD. Prints the cache file's path.
pv_port_blobs() {
  local repo="${PV_REPO:-${DIR:-.}}" head cache c d f cd_
  head="$(git -C "$repo" rev-parse --short HEAD 2>/dev/null)" || return 1
  cd_="$(pv_cache_dir)"; cache="$cd_/.shipped-ports.$head"
  if [ ! -s "$cache" ]; then
    mkdir -p "$cd_" || return 1
    rm -f "$cd_"/.shipped-ports.* 2>/dev/null
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

# Blob ids of ~/AGENTS.md as rendered at the last 30 commits touching the
# template or the renderer, each with TODAY's personal layers (my-context.env,
# extras.local.md, …, from PV_LAYERS_DIR). ~/AGENTS.md is a personal render,
# so its history isn't in git; re-rendering it is (measured at 4.3 s for 30
# commits, PLAN §17). A clean environment keeps the render deterministic.
# Cached per HEAD and layers. Prints the cache file's path.
pv_render_blobs() {
  local repo="${PV_REPO:-${DIR:-.}}" layers="${PV_LAYERS_DIR:-${DIR:-.}}" head key cache c d f cd_
  head="$(git -C "$repo" rev-parse --short HEAD 2>/dev/null)" || return 1
  key="$(cat "$layers"/my-context.env "$layers"/team-context.env "$layers"/extras.local.md "$layers"/mcp-rules.local 2>/dev/null \
         | git hash-object --stdin | cut -c1-12)"
  cd_="$(pv_cache_dir)"; cache="$cd_/.shipped-render.$head.$key"
  if [ ! -s "$cache" ]; then
    mkdir -p "$cd_" || return 1
    rm -f "$cd_"/.shipped-render.* 2>/dev/null
    : > "$cache.tmp.$$"
    for c in $(git -C "$repo" log -n 30 --format=%h -- template.md customize.sh 2>/dev/null); do
      d="$(mktemp -d "${TMPDIR:-/tmp}/aigi_render.XXXXXX")" || continue
      if git -C "$repo" archive "$c" 2>/dev/null | tar -x -C "$d" 2>/dev/null && [ -x "$d/customize.sh" ]; then
        for f in my-context.env team-context.env extras.local.md mcp-rules.local; do
          [ -f "$layers/$f" ] && cp "$layers/$f" "$d/$f"
        done
        (cd "$d" && env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" ./customize.sh --print 2>/dev/null) \
          > "$d/.render" && pv_blob "$d/.render" >> "$cache.tmp.$$"
      fi
      rm -rf "$d"
    done
    sort -u "$cache.tmp.$$" > "$cache" && rm -f "$cache.tmp.$$"
  fi
  printf '%s\n' "$cache"
}

# True when dest's canonical part is a version the repo once shipped. -m
# includes merge commits, so a blob that only ever landed via a merge still
# counts. "render:roles" is a role port, "render:agents" is ~/AGENTS.md, and
# model-routing.md is compared outside its generated block on both sides.
# Empty src = a generated file with no history.
pv_shipped() {  # $1 = dest  $2 = repo-relative source path, render:*, or empty  $3 = class
  [ -n "${2:-}" ] || return 1
  command -v git >/dev/null 2>&1 || return 1
  local b cache repo="${PV_REPO:-${DIR:-.}}" h t
  b="$(pv_canon_blob "$1" "${3:-}")"
  case "$2" in
    render:roles)  cache="$(pv_port_blobs)" || return 1;   grep -qxF "$b" "$cache"; return;;
    render:agents) cache="$(pv_render_blobs)" || return 1; grep -qxF "$b" "$cache"; return;;
  esac
  if [ "${3:-}" = model-routing ]; then
    t="$(mktemp "${TMPDIR:-/tmp}/aigi_hist.XXXXXX")" || return 1
    for h in $(git -C "$repo" log --all -m --format= --raw --no-abbrev -- "$2" 2>/dev/null | awk '{print $4}' | sort -u); do
      case "$h" in 0000000000000000000000000000000000000000) continue;; esac
      git -C "$repo" cat-file blob "$h" > "$t" 2>/dev/null || continue
      [ "$(pv_canon_blob "$t" model-routing)" = "$b" ] && { rm -f "$t"; return 0; }
    done
    rm -f "$t"; return 1
  fi
  git -C "$repo" log --all -m --format= --raw --no-abbrev -- "$2" 2>/dev/null \
    | awk -v b="$b" '$3 == b || $4 == b { f = 1 } END { exit !f }'
}

# Classify an existing dest that differs from the new content ($4).
pv_classify() {  # $1 = dest  $2 = repo-relative source (or empty)  [$3 = class  $4 = new content file]
  local class="${3:-}" cb
  if [ "$class" = playbook ] && [ "$(pv_block_state "$1")" = damaged ]; then echo CUSTOM; return 0; fi
  cb="$(pv_canon_blob "$1" "$class")"
  if [ -n "${4:-}" ] && [ -n "$(pv_field "$1" 6)" ] \
     && [ "$(pv_field "$1" 6)" = "$cb" ] && [ "$(pv_field "$1" 7)" = "$(pv_canon_blob "$4" "$class")" ]; then
    echo KEPT; return 0
  fi
  if pv_has_row "$1"; then
    # With a ledger row, only an exact match is ours. Anything else was
    # changed after we wrote it — even a deliberate revert to an old version.
    if [ "$(pv_recorded "$1")" = "$cb" ]; then echo OURS; else echo CUSTOM; fi
    return 0
  fi
  if pv_shipped "$1" "${2:-}" "$class"; then echo SHIPPED; else echo CUSTOM; fi
}

# Copy a file into preserved/ (never rotated) and log it. With a class and the
# new version, the copy is a triple: yours, the base it diverged from
# (<saved>.base), and what replaced it (<saved>.new), which is what
# `install.sh --resolve` needs to re-apply a decision later.
pv_preserve() {  # $1 = path  $2 = reason  [$3 = class  $4 = new content file]
  local id saved base=- new=-
  id="$(pv_pathid "$1")"
  mkdir -p "$PV_STATE/preserved" || return 1
  saved="$(mktemp "$PV_STATE/preserved/$id.$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")" || return 1
  cp -p "$1" "$saved" || return 1
  if [ -f "$PV_STATE/base/$id" ]; then cp "$PV_STATE/base/$id" "$saved.base" && base="$saved.base"; fi
  if [ -n "${4:-}" ] && [ -f "$4" ]; then cp "$4" "$saved.new" && new="$saved.new"; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$1" "$saved" "$2" "$(pv_blob "$1")" "$(pv_now)" \
    "${3:--}" "$base" "$new" open >> "$PV_STATE/preserved.tsv"
  PV_SAVED="$saved"
}

# The first real file we displace at a path, kept forever in orig/ so an
# uninstall can put back what was there before us (not one of our own old
# renders, which is all a rotated .bak.* may hold after five installs).
pv_orig() {  # $1 = path  [$2 = file to keep instead of $1]
  local id; id="$(pv_pathid "$1")"
  pv_planning && return 0
  [ -e "$PV_STATE/orig/$id" ] && return 0
  [ -f "${2:-$1}" ] || return 0
  mkdir -p "$PV_STATE/orig" || return 1
  cp -p "${2:-$1}" "$PV_STATE/orig/$id" && printf '%s\t%s\t%s\n' "$id" "$1" "$(pv_now)" >> "$PV_STATE/orig.tsv"
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

# ---- the append-merge (D3) --------------------------------------------------

# Why [a] isn't offered for a class, or nothing when it is. Roles must end on
# their reminder line (D6), code can't take appended text, and model-routing
# is rebuilt outside its generated block on every install (A10).
pv_no_append() {  # $1 = class
  case "$1" in
    playbook|render) ;;
    role)          echo "role files — the closing reminder must stay last";;
    model-routing) echo "model-routing.md — everything outside the generated block is rebuilt";;
    *)             echo "scripts and generated files — see the diff instead";;
  esac
}

# The lines you added: "> " lines of a normal diff from the base to yours,
# canonical parts only, in order, with a blank line between separate runs.
# Normal diff output is POSIX, so this works with BSD diff too.
pv_added() {  # $1 = base file  $2 = your file  $3 = class
  local a b; a="$(mktemp "${TMPDIR:-/tmp}/aigi_a.XXXXXX")"; b="$(mktemp "${TMPDIR:-/tmp}/aigi_b.XXXXXX")"
  pv_canon "$1" "$3" > "$a"; pv_canon "$2" "$3" > "$b"
  diff "$a" "$b" | awk '/^[0-9]/ { if (n) gap = 1; next } /^> / { if (gap) { print ""; gap = 0 } print substr($0, 3); n++ }'
  rm -f "$a" "$b"
}

# +added/-removed line counts, base → yours.
pv_counts() {  # $1 = base file  $2 = your file  $3 = class
  local a b; a="$(mktemp "${TMPDIR:-/tmp}/aigi_a.XXXXXX")"; b="$(mktemp "${TMPDIR:-/tmp}/aigi_b.XXXXXX")"
  pv_canon "$1" "$3" > "$a"; pv_canon "$2" "$3" > "$b"
  diff "$a" "$b" | awk '/^> / { p++ } /^< / { m++ } END { printf "+%d/-%d\n", p, m }'
  rm -f "$a" "$b"
}

# The base to diff your file against: what we last wrote, or (no ledger row)
# the new version — the plan's pre-ledger fallback.
pv_base_for() {  # $1 = dest  $2 = new content file
  local id; id="$(pv_pathid "$1")"
  if [ -f "$PV_STATE/base/$id" ]; then printf '%s\n' "$PV_STATE/base/$id"; else printf '%s\n' "$2"; fi
}

# The checkout whose extras.local.md receives lines routed from ~/AGENTS.md:
# the primary checkout, never a linked worktree that may be reaped (A6).
pv_extras_file() {
  local p; p="$(git -C "${DIR:-.}" worktree list --porcelain 2>/dev/null | awk 'NR == 1 { print substr($0, 10) }')"
  printf '%s/extras.local.md\n' "${p:-${DIR:-.}}"
}

# Is [a] available for this file right now? Prints why not.
pv_append_blocked() {  # $1 = class  $2 = dest  $3 = new content file
  local why n total base
  why="$(pv_no_append "$1")"; [ -n "$why" ] && { echo "$why"; return 0; }
  base="$(pv_base_for "$2" "$3")"
  n="$(pv_added "$base" "$2" "$1" | grep -c .)"
  [ "$n" -eq 0 ] && { echo "you only removed lines — there's nothing to append"; return 0; }
  # A file that's mostly yours isn't "ours plus a few lines" (R7).
  total="$(grep -c . < "$3")"
  [ "$n" -gt $(( total / 2 )) ] && { echo "most of the file is yours — keep, pin or replace it instead"; return 0; }
  return 0
}

# Warn when a rule headline you're keeping also appears, reworded, in the new
# version: both would then be in force and could disagree (§6's known risk).
pv_contradictions() {  # $1 = added-lines file  $2 = new content file
  local h
  sed -n 's/^[[:space:]]*[-*] \*\*\([^*]*\)\*\*.*/\1/p' "$1" | while IFS= read -r h; do
    [ -n "$h" ] || continue
    if grep -qF -- "**$h**" "$2" && ! grep -qxF -- "$(grep -F -- "**$h**" "$1" | head -n 1)" "$2"; then
      echo "  check: your kept rule \"$h\" also appears in the new version — make sure they agree" >&2
    fi
  done
}

# Build dest's appended version into $4: the new content with your added lines
# inside its preserved block (an existing block grows; it's never nested).
pv_build_append() {  # $1 = new content file  $2 = added-lines file  $3 = class  $4 = out
  if [ "$(pv_block_state "$1")" = ok ]; then
    awk -v e="$PV_END" -v f="$2" '$0 == e { while ((getline l < f) > 0) print l } { print }' "$1" > "$4"
  else
    { cat "$1"; printf '\n%s — your additions from before the %s install; edit freely -->\n' "$PV_BEGIN" "$(date +%Y-%m-%d)"
      cat "$2"; printf '%s\n' "$PV_END"; } > "$4"
  fi
}

# ~/AGENTS.md can't carry an appended block: the next render would wipe it.
# Its additions go where they survive every render — extras.local.md in the
# primary checkout, under a dated heading, minus lines already there (D5).
# Then the render is redone with them. Prints the new render's path.
pv_route_extras() {  # $1 = added-lines file
  local xf out add l; xf="$(pv_extras_file)"
  add="$(mktemp "$AIGI_RUN_DIR/extras.XXXXXX")" || return 1
  { [ -s "$xf" ] && printf '\n'
    printf '## Preserved from ~/AGENTS.md (%s)\n\n' "$(date +%Y-%m-%d)"
    while IFS= read -r l || [ -n "$l" ]; do
      if [ -n "$l" ] && [ -f "$xf" ] && grep -qxF -- "$l" "$xf"; then continue; fi
      printf '%s\n' "$l"
    done < "$1"
  } > "$add"
  cat "$add" >> "$xf" || return 1
  echo "  moved your ~/AGENTS.md additions into $xf (the render's personal layer)" >&2
  out="$(mktemp "$AIGI_RUN_DIR/render.XXXXXX")" || return 1
  AIGI_GLOBAL_RENDER=1 "${DIR:-.}/customize.sh" --print < /dev/null > "$out" || return 1
  printf '%s\n' "$out"
}

# ---- the AI check (optional, advisory: PLAN §7) ------------------------------

# Ask a model whether your added lines are already said by the new version.
# Off unless INSTALL_AI_CHECK=local|command. Markdown classes only, 60 s per
# file, 300 s per run, strict JSON. It only ever changes a recommendation.
pv_ai_check() {  # $1 = dest  $2 = new content file  $3 = class
  PV_AI=""
  case "${AIGI_AI_CHECK:-off}" in local|command) ;; *) return 0;; esac
  case "$3" in playbook|role|render) ;; *) return 0;; esac
  local spent start cmd out tmo base
  spent="$(cat "$AIGI_RUN_DIR/ai.spent" 2>/dev/null || echo 0)"
  [ "$spent" -ge 300 ] && { PV_AI="skipped: 300 s budget used"; return 0; }
  if [ "$AIGI_AI_CHECK" = local ]; then
    command -v lm >/dev/null 2>&1 || { PV_AI="skipped: no lm shim"; return 0; }
    cmd='lm -p "$(cat)"'
  else
    cmd="${AIGI_AI_CHECK_CMD:-}"; [ -n "$cmd" ] || { PV_AI="skipped: INSTALL_AI_CHECK_CMD is empty"; return 0; }
  fi
  tmo="${DIR:-.}/portable-timeout"; command -v timeout >/dev/null 2>&1 && tmo=timeout
  base="$(pv_base_for "$1" "$2")"
  start="$(date +%s)"
  out="$({ printf '%s\n' 'You judge whether a person'"'"'s edits to an instruction file are already expressed in its new version.' \
            'Reply with ONLY a JSON object: {"covered": true|false, "uncovered": [lines], "contradicts": [{"yours": "...", "new": "..."}], "reason": "..."}' \
            '--- LINES THE PERSON ADDED ---'
          pv_added "$base" "$1" "$3"
          echo '--- NEW VERSION ---'; cat "$2"; } | "$tmo" 60 sh -c "$cmd" 2>/dev/null)" || true
  echo $(( spent + $(date +%s) - start )) > "$AIGI_RUN_DIR/ai.spent"
  out="$(printf '%s\n' "$out" | sed -n '/^[[:space:]]*{/,/}[[:space:]]*$/p')"
  if command -v jq >/dev/null 2>&1 && printf '%s' "$out" | jq -e '(.covered | type) == "boolean"' >/dev/null 2>&1; then
    if [ "$(printf '%s' "$out" | jq -r .covered)" = true ]; then PV_AI="covered: $(printf '%s' "$out" | jq -r '.reason // ""')"
    else PV_AI="not covered: $(printf '%s' "$out" | jq -r '.reason // ""')"; fi
  else
    PV_AI="skipped: no valid verdict"
  fi
  PV_AI="$(printf '%s' "$PV_AI" | tr '\t\n' '  ')"
}

# ---- decisions --------------------------------------------------------------

# [r]: replace yours, after saving it (with its base and the new version).
pv_do_replace() {  # $1 = class  $2 = new content file  $3 = dest  $4 = rel
  local known=""
  { pv_has_row "$3" || [ -n "${4:-}" ]; } && known=1
  pv_preserve "$3" "replaced by install" "$1" "$2" || { echo "  could not preserve $3 — left unchanged" >&2; return 1; }
  pv_put "$2" "$3" || return 1
  pv_record "$3" "$1" "${4:-generated}"
  PV_ACTION=replaced-custom
  if [ -n "$known" ]; then
    echo "  replaced your edited $3 — your version: $PV_SAVED" >&2
  else
    echo "  replaced $3 (couldn't prove it was unedited) — previous version: $PV_SAVED" >&2
  fi
}

# [a]: the new version plus your added lines in a preserved block (a
# playbook), or routed into extras.local.md and re-rendered (~/AGENTS.md).
pv_do_append() {  # $1 = class  $2 = new content file  $3 = dest  $4 = rel
  local why added out base
  why="$(pv_append_blocked "$1" "$3" "$2")"
  if [ -n "$why" ]; then echo "  can't append to $3 ($why) — replacing instead" >&2; pv_do_replace "$@"; return; fi
  base="$(pv_base_for "$3" "$2")"
  added="$(mktemp "$AIGI_RUN_DIR/added.XXXXXX")"; pv_added "$base" "$3" "$1" > "$added"
  pv_preserve "$3" "replaced by install" "$1" "$2" || { echo "  could not preserve $3 — left unchanged" >&2; return 1; }
  if [ "$1" = render ]; then
    out="$(pv_route_extras "$added")" || { echo "  could not update extras.local.md — $3 left unchanged" >&2; return 1; }
  else
    out="$(mktemp "$AIGI_RUN_DIR/appended.XXXXXX")"; pv_build_append "$2" "$added" "$1" "$out"
    echo "  kept your additions to $3 in its preserved block — your full version: $PV_SAVED" >&2
  fi
  pv_contradictions "$added" "$2"
  pv_put "$out" "$3" || return 1
  pv_record "$3" "$1" "${4:-generated}"
  PV_ACTION=appended
}

# [k]: leave yours; the new version waits in new/ until you want it.
pv_do_keep() {  # $1 = class  $2 = new content file  $3 = dest  $4 = rel
  local id; id="$(pv_pathid "$3")"
  mkdir -p "$PV_STATE/new" && cp "$2" "$PV_STATE/new/$id"
  pv_mark_kept "$3" "$1" "$2" "${4:-generated}"
  PV_ACTION=kept-custom
  echo "  kept your $3 — the new version is at $PV_STATE/new/$id" >&2
}

pv_do_pin() {  # $1 = path
  mkdir -p "$PV_STATE" && { pv_pinned "$1" || printf '%s\n' "$1" >> "$PV_STATE/pins"; }
  PV_ACTION=pinned
  echo "  pinned $1 — the installer won't write it again (./install.sh --unpin $1)" >&2
}

# An attended run doesn't decide alone: park the file, untouched, and ask at
# the end of the run with everything else that needs you.
pv_park() {  # $1 = class  $2 = new content file  $3 = dest  $4 = rel
  local id; id="$(pv_pathid "$3")"
  mkdir -p "$AIGI_RUN_DIR/parked" || return 1
  cp "$2" "$AIGI_RUN_DIR/parked/$id" || return 1
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$3" "$1" "${4:--}" "$(pv_blob "$3")" "${PV_AI:--}" >> "$AIGI_RUN_DIR/parked.tsv"
  PV_ACTION=parked
  echo "  you've edited $3 — left as is; you'll be asked at the end of the run" >&2
}

# ---- the two verbs -----------------------------------------------------------

# Install $2 at $3. Returns 0 when dest now holds the new content or was
# deliberately left alone, 1 on a real failure. Sets PV_ACTION to one of
# created | current | updated | replaced-custom | appended | kept-custom |
# kept | pinned | parked | skipped-symlink, or would-* in a plan run, and
# PV_VERDICT to the rung that decided. $4 = repo-relative source for the
# SHIPPED check (render:roles, render:agents; omit for other generated files).
#
# What gets a copy in preserved/: CUSTOM always, and SHIPPED too. A SHIPPED
# file is either a stale install or a deliberate revert to an old version, and
# without a ledger row nothing can tell those apart, so it's kept. That happens
# once per file, on the first ledger run. OURS is never copied: it's
# byte-for-byte what base/ already holds.
pv_write() {  # $1 = class  $2 = new content file  $3 = dest  [$4 = repo-relative source]
  local class="$1" src="$2" dest="$3" rel="${4:-}" new
  PV_ACTION=""; PV_SAVED=""; PV_VERDICT=""; PV_AI=""
  pv_planning || pv_lock || return 1
  pv_run_init || return 1
  if [ -L "$dest" ]; then
    pv_planning || echo "  note: $dest is a symlink — left alone (never written through); the new version is at $src" >&2
    PV_VERDICT=SYMLINK; PV_ACTION=skipped-symlink; pv_log "$dest" "$class"; return 0
  fi
  if pv_pinned "$dest"; then
    PV_VERDICT=PINNED; PV_ACTION=pinned
    if ! pv_planning && [ -e "$dest" ] && ! cmp -s "$src" "$dest"; then
      echo "  pinned: $dest left as yours (upstream differs — ./install.sh --unpin $dest to take it)" >&2
    fi
    pv_log "$dest" "$class"; return 0
  fi
  if [ ! -e "$dest" ]; then
    PV_VERDICT=ABSENT
    if pv_planning; then PV_ACTION=would-create; pv_log "$dest" "$class"; return 0; fi
    mkdir -p "$(dirname "$dest")" || return 1
    pv_put "$src" "$dest" || return 1
    pv_record "$dest" "$class" "${rel:-generated}"; PV_ACTION=created; pv_log "$dest" "$class"; return 0
  fi
  new="$(pv_compose "$src" "$dest" "$class")" || return 1
  if cmp -s "$new" "$dest"; then
    # Identical: no write. Adopt it into the ledger if the row is missing or
    # stale, which is how a machine installed before the ledger gets its rows.
    PV_VERDICT=CURRENT; PV_ACTION=current
    if ! pv_planning && [ "$(pv_recorded "$dest")" != "$(pv_canon_blob "$dest" "$class")" ]; then
      pv_record "$dest" "$class" "${rel:-generated}"
    fi
    pv_log "$dest" "$class"; return 0
  fi
  PV_VERDICT="$(pv_classify "$dest" "$rel" "$class" "$new")"
  if pv_planning; then
    case "$PV_VERDICT" in
      OURS|SHIPPED) PV_ACTION=would-update;;
      KEPT)         PV_ACTION=would-keep;;
      *) if pv_unattended; then PV_ACTION="would-$(pv_policy)"; else PV_ACTION=would-ask; fi;;
    esac
    pv_log "$dest" "$class"; return 0
  fi
  case "$PV_VERDICT" in
    OURS)
      pv_put "$new" "$dest" || return 1; pv_record "$dest" "$class" "${rel:-generated}"; PV_ACTION=updated;;
    SHIPPED)
      pv_preserve "$dest" "older shipped version, first ledger run" "$class" "$new" \
        || { echo "  could not preserve $dest — left unchanged" >&2; return 1; }
      pv_put "$new" "$dest" || return 1; pv_record "$dest" "$class" "${rel:-generated}"; PV_ACTION=updated;;
    KEPT)
      PV_ACTION=kept;;
    *)
      pv_ai_check "$dest" "$new" "$class"
      if ! pv_unattended; then pv_park "$class" "$new" "$dest" "$rel" || return 1
      else
        case "$(pv_policy)" in
          keep)   pv_do_keep "$class" "$new" "$dest" "$rel";;
          append) pv_do_append "$class" "$new" "$dest" "$rel" || return 1;;
          *)      pv_do_replace "$class" "$new" "$dest" "$rel" || return 1;;
        esac
      fi;;
  esac
  pv_log "$dest" "$class"
}

# Delete dest because the installer no longer ships it (a toggle, a rename,
# an uninstall). OURS goes quietly; SHIPPED and CUSTOM are preserved first (as
# in pv_write). A pinned path and a symlink are left alone. Deletes never
# park: the only alternative to removing a file is keeping it, which a pin
# already expresses.
pv_delete() {  # $1 = dest  $2 = reason  [$3 = repo-relative source  $4 = class]
  local dest="$1" class="${4:-}"
  PV_ACTION=""; PV_SAVED=""; PV_VERDICT=""; PV_AI=""
  [ -e "$dest" ] || [ -L "$dest" ] || { PV_ACTION=absent; return 0; }
  pv_planning || pv_lock || return 1
  pv_run_init || return 1
  if [ -L "$dest" ]; then
    pv_planning || echo "  note: $dest is a symlink — not removed" >&2
    PV_VERDICT=SYMLINK; PV_ACTION=skipped-symlink; pv_log "$dest" "$class"; return 0
  fi
  if pv_pinned "$dest"; then PV_VERDICT=PINNED; PV_ACTION=pinned; pv_log "$dest" "$class"; return 0; fi
  PV_VERDICT="$(pv_classify "$dest" "${3:-}" "$class")"
  if pv_planning; then PV_ACTION=would-remove; pv_log "$dest" "$class"; return 0; fi
  if [ "$PV_VERDICT" != OURS ]; then
    pv_preserve "$dest" "$2" "$class" || { echo "  could not preserve $dest — not removed" >&2; return 1; }
    [ "$PV_VERDICT" = CUSTOM ] && echo "  removed $dest ($2) — your version: $PV_SAVED" >&2
  fi
  rm -f "$dest" || return 1
  pv_forget "$dest"; PV_ACTION=removed; pv_log "$dest" "$class"
}

# ---- the end of a run ---------------------------------------------------------

# Ask about every parked file, once, in one pass. Enter is [r] — the same
# result as an unattended run (D1) — so mashing Enter is never worse than
# not being there. [x] stops and leaves this file and the rest untouched.
pv_resolve_parked() {
  local pf="$AIGI_RUN_DIR/parked.tsv" id dest class rel blob ai new all="" ans why base n
  [ -s "$pf" ] || return 0
  pv_lock || return 1
  n="$(grep -c . < "$pf")"
  exec 9< "$(pv_tty)" || { echo "  can't ask about $n edited file(s) (no terminal) — left as they are" >&2; return 0; }
  echo "" >&2
  echo "== $n file(s) you edited — what should the installer do? ==" >&2
  while IFS="$(printf '\t')" read -r id dest class rel blob ai; do
    new="$AIGI_RUN_DIR/parked/$id"; [ "$rel" = - ] && rel=""
    PV_VERDICT=CUSTOM; PV_SAVED=""; PV_AI="$ai"; [ "$ai" = - ] && PV_AI=""
    if [ ! -f "$dest" ] || [ "$(pv_blob "$dest")" != "$blob" ]; then
      echo "  $dest changed while the install ran — left alone; run ./install.sh again" >&2
      PV_ACTION=left; pv_log "$dest" "$class"; continue
    fi
    base="$(pv_base_for "$dest" "$new")"
    why="$(pv_append_blocked "$class" "$dest" "$new")"
    ans="$all"
    while [ -z "$ans" ]; do
      echo "" >&2
      echo "$dest — you've changed this file ($(pv_counts "$base" "$dest" "$class") lines vs what we installed)" >&2
      [ -n "$PV_AI" ] && echo "  AI check: $PV_AI" >&2
      echo "  [r] replace with the new version (yours is saved)       ← Enter" >&2
      if [ -z "$why" ]; then
        case "$PV_AI" in "not covered"*) echo "  [a] replace, then keep your added lines   ← recommended: the AI check says they're not covered" >&2;;
          *) echo "  [a] replace, then keep your added lines" >&2;; esac
      else echo "  [a] unavailable: $why" >&2; fi
      echo "  [k] keep yours this time   [p] pin: keep yours, never ask again   [d] show the diff" >&2
      echo "  [R/A/K] same answer for every remaining file   [x] stop — leave this and the rest as they are" >&2
      printf '  choice [r]: ' >&2
      IFS= read -r ans <&9 || ans=x
      case "$ans" in
        ''|r) ans=r;; a|k|p|x) ;;
        R|A|K) all="$(printf '%s' "$ans" | tr 'RAK' 'rak')"; ans="$all";;
        d) diff -u "$dest" "$new" >&2; ans="";;
        *) echo "  (not an option)" >&2; ans="";;
      esac
      if [ "$ans" = a ] && [ -n "$why" ]; then
        if [ -n "$all" ]; then ans=r; else echo "  [a] isn't available here: $why" >&2; ans=""; fi
      fi
    done
    case "$ans" in
      r) pv_do_replace "$class" "$new" "$dest" "$rel";;
      a) pv_do_append "$class" "$new" "$dest" "$rel";;
      k) pv_do_keep "$class" "$new" "$dest" "$rel";;
      p) pv_do_pin "$dest";;
      x) echo "  stopped — $dest and every file after it are left as they are" >&2
         PV_ACTION=left; pv_log "$dest" "$class"
         while IFS="$(printf '\t')" read -r id dest class rel blob ai; do PV_ACTION=left; pv_log "$dest" "$class"; done
         break;;
    esac
    pv_log "$dest" "$class"
  done < "$pf"
  exec 9<&-
  : > "$pf"
}

# A JSON string, escaped (no jq dependency for the report).
pv_json_str() { printf '%s' "$1" | awk 'BEGIN { ORS = "" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); if (NR > 1) print "\\n"; print }'; }

# last-run.json: one entry per ledgered path (its last action this run), so an
# agent that ran the install reads the outcome instead of scraping output.
# Every replaced edit carries the command that recovers it. Exit codes stay 0
# on success either way (A9).
pv_write_last_run() {
  local af="$AIGI_RUN_DIR/actions.tsv" out tmp first=1 path class verdict action saved ai recover
  [ -f "$af" ] || return 0
  pv_planning && return 0
  mkdir -p "$PV_STATE" || return 1
  out="$PV_STATE/last-run.json"; tmp="$(mktemp "$PV_STATE/.last-run.XXXXXX")" || return 1
  {
    printf '{\n  "version": 1,\n  "date": "%s",\n  "repo": "%s",\n  "commit": "%s",\n  "unattended": %s,\n  "files": [' \
      "$(pv_now)" "$(pv_json_str "${DIR:-}")" "$(git -C "${DIR:-.}" rev-parse --short HEAD 2>/dev/null || echo -)" \
      "$(pv_unattended && echo true || echo false)"
    awk -F'\t' '!($1 in last) { order[++n] = $1 } { last[$1] = $0 } END { for (i = 1; i <= n; i++) print last[order[i]] }' "$af" \
      | while IFS="$(printf '\t')" read -r path class verdict action saved ai; do
          recover=""
          case "$action" in
            replaced-custom)
              if [ -z "$(pv_no_append "$class")" ]; then recover="./install.sh --resolve $path --append"
              else recover="./install.sh --resolve $path --keep"; fi;;
            left) recover="./install.sh";;
          esac
          [ "$first" = 1 ] && first=0 || printf ','
          printf '\n    {"path": "%s", "class": "%s", "verdict": "%s", "action": "%s", "preserved_at": %s, "ai": %s, "recover": %s}' \
            "$(pv_json_str "$path")" "$class" "$verdict" "$action" \
            "$([ "$saved" = - ] && echo null || printf '"%s"' "$(pv_json_str "$saved")")" \
            "$([ "$ai" = - ] && echo null || printf '"%s"' "$(pv_json_str "$ai")")" \
            "$([ -z "$recover" ] && echo null || printf '"%s"' "$(pv_json_str "$recover")")"
        done
    printf '\n  ]\n}\n'
  } > "$tmp" && mv "$tmp" "$out"
}

# The run's last lines: every edited file that was replaced or left, with the
# exact command that recovers it.
pv_summary() {
  local af="$AIGI_RUN_DIR/actions.tsv"
  [ -f "$af" ] || return 0
  awk -F'\t' '!($1 in last) { order[++n] = $1 } { last[$1] = $0 } END { for (i = 1; i <= n; i++) print last[order[i]] }' "$af" \
    | awk -F'\t' -v st="$PV_STATE" '
        $4 == "replaced-custom" { r[++nr] = $1; rm[nr] = ($2 == "playbook" || $2 == "render") ? "--append" : "--keep" }
        $4 == "appended"        { a[++na] = $1 }
        $4 == "kept-custom" || $4 == "pinned" { k[++nk] = $1 }
        $4 == "left"            { l[++nl] = $1 }
        END {
          if (nr) { print ""; print "Replaced " nr " file(s) you had edited (your versions are in " st "/preserved/):"
                    for (i = 1; i <= nr; i++) print "  " r[i] "   recover: ./install.sh --resolve " r[i] " " rm[i] }
          if (na) { print ""; print "Kept your additions in " na " file(s):"; for (i = 1; i <= na; i++) print "  " a[i] }
          if (nk) { print ""; print "Left " nk " file(s) as yours (kept or pinned):"; for (i = 1; i <= nk; i++) print "  " k[i] }
          if (nl) { print ""; print "Not decided (left untouched; run ./install.sh again):"; for (i = 1; i <= nl; i++) print "  " l[i] }
          if (nr || na || nk || nl) print "Details for agents: " st "/last-run.json"
        }'
}

# Close a run this process opened (a layer run on its own): ask, report, tidy.
# Under install.sh the run belongs to install.sh, which does this at the end.
pv_finish() {
  [ -n "${PV_OWN_RUN:-}" ] || return 0
  [ -n "${AIGI_RUN_DIR:-}" ] && [ -d "$AIGI_RUN_DIR" ] || return 0
  pv_resolve_parked || true
  pv_write_last_run || true
  pv_summary
  rm -rf "$AIGI_RUN_DIR"; PV_OWN_RUN=""
}

# ---- install.sh --resolve -----------------------------------------------------

# Re-apply a decision to a file an earlier run replaced, from its preserved/
# triple: yours, the base it diverged from, and what replaced it (R5). With no
# path, every open entry; with no mode, ask (a terminal is needed).
pv_resolve_cmd() {  # $1 = mode (replace|append|keep|pin|ask)  $2.. = paths (empty = all open)
  local mode="$1" rows path saved class base new cur ans why added out n=0; shift
  [ -f "$PV_STATE/preserved.tsv" ] || { echo "Nothing to resolve: no file has been replaced yet."; return 0; }
  pv_lock || return 1
  pv_run_init || return 1
  # The newest open "replaced by install" entry per path, newest first.
  rows="$(awk -F'\t' -v OFS='\t' '$4 == "replaced by install" && $10 != "resolved" { last[$2] = $0 }
          END { for (p in last) print last[p] }' "$PV_STATE/preserved.tsv")"
  [ -n "$rows" ] || { echo "Nothing to resolve: every replaced file has been decided."; return 0; }
  [ "$mode" = ask ] && { exec 9< "$(pv_tty)" || { echo "--resolve needs a terminal, or one of --replace --append --keep --pin" >&2; return 1; }; }
  while IFS="$(printf '\t')" read -r _ path saved _ _ _ class base new _; do
    if [ $# -gt 0 ]; then
      local want="" p; for p in "$@"; do [ "$p" = "$path" ] && want=1; done
      [ -n "$want" ] || continue
    fi
    n=$((n+1))
    [ -n "$class" ] && [ "$class" != - ] || class="$(pv_field "$path" 3)"
    [ "$base" = - ] || [ -z "$base" ] && base="$new"
    [ "$base" = - ] || [ -z "$base" ] && base="$path"
    cur="$(pv_canon_blob "$path" "$class" 2>/dev/null)"
    if [ ! -f "$path" ] || { pv_has_row "$path" && [ "$(pv_recorded "$path")" != "$cur" ]; }; then
      echo "  $path changed since it was replaced — resolve it by hand (yours: $saved)" >&2; continue
    fi
    ans="$mode"
    while [ "$ans" = ask ]; do
      echo "$path — replaced by an install; yours is $saved ($(pv_counts "$base" "$saved" "$class") lines)" >&2
      echo "  [r] leave the new version   [a] add your lines back   [k] put yours back   [p] put yours back and pin it   [d] diff   [s] skip" >&2
      printf '  choice [s]: ' >&2; IFS= read -r ans <&9 || ans=s
      case "$ans" in r) ans=replace;; a) ans=append;; k) ans=keep;; p) ans=pin;; d) diff -u "$path" "$saved" >&2; ans=ask;; *) ans=skip;; esac
    done
    PV_VERDICT=RESOLVE; PV_SAVED="$saved"; PV_AI=""
    case "$ans" in
      skip) continue;;
      replace) PV_ACTION=resolved-replace;;
      keep|pin)
        cp "$path" "$AIGI_RUN_DIR/cur.$n"
        pv_put "$saved" "$path" || return 1
        if [ "$ans" = pin ]; then pv_do_pin "$path"; PV_ACTION=resolved-pin
        else pv_mark_kept "$path" "$class" "$AIGI_RUN_DIR/cur.$n"; PV_ACTION=resolved-keep; echo "  put your version back at $path" >&2; fi;;
      append)
        why="$(pv_no_append "$class")"
        if [ -n "$why" ]; then echo "  can't append to $path ($why) — use --keep or --pin" >&2; continue; fi
        added="$AIGI_RUN_DIR/added.$n"; pv_added "$base" "$saved" "$class" > "$added"
        if ! grep -q . "$added"; then echo "  $path: your version only removed lines — nothing to add back" >&2; continue; fi
        if [ "$class" = render ]; then out="$(pv_route_extras "$added")" || return 1
        else out="$AIGI_RUN_DIR/out.$n"; pv_build_append "$path" "$added" "$class" "$out"; fi
        pv_contradictions "$added" "$path"
        pv_put "$out" "$path" || return 1
        pv_record "$path" "$class" "$(pv_field "$path" 8)"
        PV_ACTION=resolved-append; echo "  added your lines back to $path" >&2;;
    esac
    pv_log "$path" "$class"
    awk -F'\t' -v OFS='\t' -v s="$saved" '$3 == s { $10 = "resolved" } { print }' "$PV_STATE/preserved.tsv" > "$PV_STATE/.preserved.tmp" \
      && mv "$PV_STATE/.preserved.tmp" "$PV_STATE/preserved.tsv"
  done <<EOF
$rows
EOF
  [ "$mode" = ask ] && exec 9<&-
  [ "$n" -gt 0 ] || echo "Nothing to resolve for: $*"
  pv_write_last_run || true
  rm -rf "$AIGI_RUN_DIR"; PV_OWN_RUN=""
  return 0
}
