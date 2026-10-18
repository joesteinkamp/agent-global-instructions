# shellcheck shell=bash
# shellcheck disable=SC2034  # SL_ROWS / SL_DECLINED are outputs the sourcing script reads
# lib/settings-ledger.sh — per-rule provenance for the JSON permission merges
# (PLAN-install-preservation.md §9 G4, §16 A3, §15 R13, §18).
#
# Sourced by install-settings.sh and uninstall.sh, never run. A union merge on
# its own can't answer two questions, so this ledger does:
#
#   whose rule is this?   Retiring a rule, or uninstalling, removes a rule only
#                         if this installer added it. The user's own copy of
#                         the same string survives (G4).
#   did they remove it?   A rule we added that's since gone was deleted on
#                         purpose: it's marked declined and never re-added.
#                         A new upstream rule is still added (A3).
#
# One row per rule, in ${AIGI_STATE_DIR:-~/.ai/install-state}/settings.tsv:
#   file  key  value  added|declined  date
# key is the permissions array (allow, deny, ask); value is the rule, exactly.
#
# A settings file with no rows at all predates the ledger. Its first run adopts
# every present rule that matches the snippet as ours, and retired rules are
# subtracted as they always were (R13: on such a file, a rule the user added
# can't be told from ours — a stated limitation). Once a file has rows, a
# present rule with no row is the user's and is never recorded.
#
# Portable to bash 3.2 (macOS): no associative arrays, no mapfile, no ${x,,}.
# Callers must set DIR (the repo checkout) before sourcing; lib/preserve.sh
# (the state dir and its lock) is sourced here if the caller hasn't already.

if ! command -v pv_lock >/dev/null 2>&1; then
  # shellcheck source=lib/preserve.sh
  . "$DIR/lib/preserve.sh"
fi
SL_LEDGER="$PV_STATE/settings.tsv"
SL_ROWS='[]'
SL_DECLINED=0

# jq helpers shared by both programs. $rows is this file's ledger rows.
SL_JQ_DEFS='
  def row($k; $v): [$rows[] | select(.key == $k and .value == $v)] | .[0];
  def has_rule($p; $k; $v): ($p[$k] | type) == "array" and any($p[$k][]; . == $v);
  def pairs($o): ($o // {}) | to_entries[] | .key as $k
    | .value | if type == "array" then .[] else empty end | {k: $k, v: .};
'

# The ledger rows for one settings file, as a compact JSON array of
# {key, value, status, date}. Malformed lines are skipped. A "known" row
# (key and value "-") marks a file the ledger has seen even when it holds no
# rule rows, e.g. after an uninstall, so a reinstall never treats it as
# pre-ledger and adopts your own rules as ours.
sl_rows() {  # $1 = settings file
  [ -f "$SL_LEDGER" ] || { echo '[]'; return 0; }
  jq -R -s -c --arg f "$1" '
    split("\n") | map(split("\t") | select(length >= 5 and .[0] == $f
      and (.[3] == "added" or .[3] == "declined" or .[3] == "known"))
      | {key: .[1], value: .[2], status: .[3], date: .[4]})
  ' "$SL_LEDGER"
}

# Replace one settings file's rows. The rest of the ledger keeps its order, and
# an unchanged set writes nothing, so an idempotent run leaves the file alone.
# Same-dir temp file + mv; the caller holds pv_lock.
sl_save() {  # $1 = settings file  $2 = its rows (JSON array)
  local tmp new
  new="$(printf '%s' "$2" | jq -c 'sort_by([.key, .value])')" || return 1
  [ "$new" = "$(sl_rows "$1" | jq -c 'sort_by([.key, .value])')" ] && return 0
  mkdir -p "$PV_STATE" || return 1
  tmp="$(mktemp "$PV_STATE/.settings.XXXXXX")" || return 1
  { if [ -f "$SL_LEDGER" ]; then
      jq -R -r --arg f "$1" 'select(length > 0 and (split("\t") | .[0]) != $f)' "$SL_LEDGER"
    fi
    printf '%s' "$new" | jq -r --arg f "$1" '.[] | [$f, .key, .value, .status, .date] | join("\t")'
  } > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$SL_LEDGER"
}

# The merge: subtract retired rules we added, then union the snippet's rules,
# skipping any we added before that are gone now (declined). Rules carrying a
# tab or newline can't be stored in a TSV row, so they're merged but never
# recorded (no shipped rule has one).
SL_MERGE_JQ="$SL_JQ_DEFS"'
  def shipped($k; $v): any(pairs($add); .k == $k and .v == $v);
  ($rows | length == 0) as $legacy
  | . as $orig
  | ($orig.permissions // {}) as $before
  | .permissions = $before
  # A rule both retired and still shipped stays: it is not subtracted at all.
  | reduce pairs($gone) as $g (.;
      if has_rule(.permissions; $g.k; $g.v) and (shipped($g.k; $g.v) | not)
         and ($legacy or row($g.k; $g.v).status == "added")
      then .permissions[$g.k] -= [$g.v] else . end)
  | reduce pairs($add) as $a (.;
      if has_rule(.permissions; $a.k; $a.v) or row($a.k; $a.v) != null then .
      else .permissions[$a.k] = ((.permissions[$a.k] // []) + [$a.v]) end)
  | .permissions |= with_entries(select((.value | type) != "array" or (.value | length) > 0))
  | if .permissions == {} and ($orig | has("permissions") | not) then del(.permissions) else . end
  | . as $after
  | [ pairs($add) | . as $a | row($a.k; $a.v) as $r | has_rule($before; $a.k; $a.v) as $was
      | if $r == null then
          if $was and ($legacy | not) then empty
          else {key: $a.k, value: $a.v, status: "added", date: $now} end
        elif $r.status == "added" and ($was | not) then
          $r + {status: "declined", date: $now, declined_now: true}
        else $r end ] as $snip
  | [ $rows[] | . as $r
      | select($r.status == "known"
          or (((shipped($r.key; $r.value) or any(pairs($gone); .k == $r.key and .v == $r.value)) | not)
              and has_rule($after.permissions // {}; $r.key; $r.value))) ] as $kept
  | { settings: $after,
      declined: ([$snip[] | select(.declined_now)] | length),
      rows: ($snip + $kept | unique_by([.key, .value])
             | map(select((.value | test("[\t\n]")) | not) | {key, value, status, date})) }
'

# Merge a snippet's .permissions into a settings file, writing the result to
# $4 and setting SL_ROWS (the file's new ledger rows) and SL_DECLINED (rules
# newly found deleted this run). Writes neither the settings file nor the
# ledger: the caller compares, backs up, moves, then calls sl_save — in that
# order, so a crash between the two can't mark a rule declined that was never
# written. $5 set means the settings file didn't exist before this run, so any
# rows for it are stale and it starts over as new.
sl_merge_perms() {  # $1 = settings file  $2 = snippet .permissions JSON  $3 = retired JSON  $4 = out  [$5 = new]
  local rows='[]' res
  [ -n "${5:-}" ] || rows="$(sl_rows "$1")" || return 1
  res="$(jq -c --argjson add "$2" --argjson gone "$3" --argjson rows "$rows" --arg now "$(pv_now)" \
    "$SL_MERGE_JQ" "$1")" || return 1
  printf '%s' "$res" | jq '.settings' > "$4" || return 1
  SL_ROWS="$(printf '%s' "$res" | jq -c '.rows')" || return 1
  SL_DECLINED="$(printf '%s' "$res" | jq '.declined')" || return 1
}

# Uninstall's subtraction: remove only the snippet rules recorded as added for
# this file, and drop their rows. Declined rows stay, so a reinstall still
# leaves those rules out. A file with no rows predates the ledger and gets the
# old behaviour: subtract the whole snippet (R13).
SL_STRIP_JQ="$SL_JQ_DEFS"'
  ($rows | length == 0) as $legacy
  | (.permissions // {}) as $before
  | [ pairs($add) | select(has_rule($before; .k; .v)
        and ($legacy or row(.k; .v).status == "added")) ] as $gone
  | { settings: (if .permissions then
        reduce $gone[] as $g (.; .permissions[$g.k] -= [$g.v])
        | .permissions |= with_entries(select((.value | length) > 0))
        | if (.permissions == {}) then del(.permissions) else . end
      else . end),
      rows: ([ $rows[] | . as $r | select(any($gone[]; .k == $r.key and .v == $r.value) | not) ]
             + (if $legacy then [] else [{key: "-", value: "-", status: "known", date: $now}] end)
             | unique_by([.key, .value])) }
'

sl_strip_perms() {  # $1 = settings file  $2 = snippet file
  local sf="$1" rows res tmp
  [ -f "$sf" ] || return 0
  [ -f "$2" ] || return 0
  pv_lock || return 1
  rows="$(sl_rows "$sf")" || return 1
  res="$(jq -c --argjson add "$(jq '.permissions' "$2")" --argjson rows "$rows" --arg now "$(pv_now)" "$SL_STRIP_JQ" "$sf")" \
    || { echo "  edit failed for $sf (left unchanged)" >&2; return 0; }
  tmp="$(mktemp "$(dirname "$sf")/.aigi.XXXXXX")" || return 1
  TMPFILES+=("$tmp")
  printf '%s' "$res" | jq '.settings' > "$tmp" || { rm -f "$tmp"; return 1; }
  if cmp -s "$tmp" "$sf"; then
    rm -f "$tmp"
  else
    if declare -F backup_file >/dev/null; then backup_file "$sf"; fi
    mv "$tmp" "$sf"; echo "  cleaned $sf"
  fi
  sl_save "$sf" "$(printf '%s' "$res" | jq -c '.rows')" \
    || echo "  could not update $SL_LEDGER for $sf" >&2
  return 0
}
