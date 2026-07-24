#!/usr/bin/env bash
# render-commands.sh — generate the per-tool command ports from the canonical
# Claude-dialect commands in commands/*.md, so there is ONE source of truth and
# the ports can't drift. Mirrors how customize.sh renders the instruction files
# from template.md.
#
#   ./render-commands.sh         # regenerate commands/{codex,cursor}/
#
# The generated files are snapshots — NEVER hand-edit them (install-commands.sh
# re-renders on every install). To change a command, edit commands/<name>.md and
# re-render. The ports are gitignored (generated locally, never committed).
#
# Translation rules (canonical -> port):
#   - frontmatter: description kept everywhere; Codex receives skill-compatible
#     name/description metadata;
#     allowed-tools dropped (Claude-only — other tools govern tools elsewhere).
#   - $ARGUMENTS: translated to request context for Codex skills; kept (with a
#     note) for cursor (no placeholder — it appends typed input).
#   - !`cmd` shell-injection: -> run `cmd` for codex/cursor (no injection —
#     tell the agent to run it).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/commands"
[ -d "$SRC" ] || { echo "No commands/ dir at $SRC" >&2; exit 1; }

TMPFILES=()
trap '[ ${#TMPFILES[@]} -gt 0 ] && rm -f "${TMPFILES[@]}" || true' EXIT

# --- frontmatter / body extractors (CR-stripped so CRLF files parse) ---------
fm_field() {  # $1 = file, $2 = key  -> prints the trimmed value (empty if absent)
  awk -v key="$2" '
    { sub(/\r$/,"") }
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && $0 ~ ("^" key ":") {     # tolerate "key:value" as well as "key: value"
      v=$0; sub("^" key ":[[:space:]]*","",v); gsub(/[[:space:]]+$/,"",v); print v; exit
    }
  ' "$1"
}

fm_body() {  # $1 = file  -> body after the frontmatter (leading blanks trimmed).
             #               No frontmatter -> whole file.
  awk '
    { sub(/\r$/,"") }
    NR==1 && $0!="---" { plain=1 }
    plain { print; next }
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { infm=0; started=1; next }
    started && !body && $0 ~ /^[[:space:]]*$/ { next }
    started { body=1; print }
  ' "$1"
}

# --- body dialect transforms (single-quoted sed: backticks/$ are literal) ----
to_norun_body()  { sed -e 's/!`\([^`]*\)`/run `\1`/g'; }
to_codex_skill_body() { to_norun_body | sed 's/\$ARGUMENTS/Use any focus supplied in the user request./g'; }

dq_escape() { sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }         # for TOML/YAML "..." double-quoted strings

# Write stdin to a destination atomically (temp + mv) so a mid-render failure
# never leaves a truncated/empty port file. The temp goes in the destination's
# OWN dir so the mv is a same-filesystem (atomic) rename — and so mktemp gets the
# template argument BSD/macOS requires (a bare `mktemp` errors there, which would
# abort the whole render and, with the prune-after model below, leave the prior
# committed ports in place rather than wiping them).
emit() {  # $1 = destination path
  local t; t="$(mktemp "$(dirname "$1")/.cmd.XXXXXX")" || return 1
  # Clean the temp on any failure — emit runs in a pipe subshell, so the EXIT
  # trap above can't reach it (its TMPFILES+= would be lost to the subshell).
  if cat > "$t" && mv "$t" "$1"; then return 0; fi
  rm -f "$t"; return 1
}

mkdir -p "$SRC/codex" "$SRC/cursor"
# Sweep any orphaned temp from a previously-interrupted run (prune_dir only globs
# *.md/*.toml, so these hidden .cmd.* files would otherwise linger uncommitted).
rm -f "$SRC"/codex/.cmd.* "$SRC"/cursor/.cmd.* 2>/dev/null || true
# Codex used to receive flat custom-prompt files here. They are unsupported in
# current Codex; remove only these generated port artifacts during migration.
rm -f "$SRC"/codex/*.md
# Stale-port cleanup happens AFTER a successful render (prune_dir below), not
# before — so an aborted render can never empty the committed port dirs (that
# emptied codex/cursor and silently installed zero commands).
prune_dir() {  # $1 = dir, $2 = ext, $3 = space-delimited set of generated basenames
  local d="$1" ext="$2" set="$3" f base
  for f in "$d"/*."$ext"; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    case "$set" in *" $base "*) ;; *) rm -f "$f";; esac
  done
}

n=0
gen_codex=" "; gen_cursor=" "
for f in "$SRC"/*.md; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  [ "$base" = "README.md" ] && continue
  name="${base%.md}"
  title="$(printf '%s' "${name:0:1}" | tr '[:lower:]' '[:upper:]')${name:1}"
  desc="$(fm_field "$f" description)"
  body="$(fm_body "$f")"
  has_args=0; printf '%s\n' "$body" | grep -q '\$ARGUMENTS' && has_args=1

  # --- Codex: ~/.codex/skills/<name>/SKILL.md (invoke $<name>) ---
  mkdir -p "$SRC/codex/$name"
  {
    printf -- '---\n'
    printf 'name: "%s"\n' "$(printf '%s' "$name" | dq_escape)"
    printf 'description: "%s"\n' "$(printf '%s' "$desc" | dq_escape)"
    printf -- '---\n\n'
    printf '<!-- GENERATED from commands/%s by render-commands.sh — do not edit. Invoke as $%s. -->\n\n' "$base" "$name"
    printf '%s\n' "$body" | to_codex_skill_body
  } | emit "$SRC/codex/$name/SKILL.md"
  gen_codex="$gen_codex$name "

  # --- Cursor: ~/.cursor/commands/<name>.md (plain markdown, no frontmatter) ---
  {
    printf '<!-- GENERATED from commands/%s by render-commands.sh — do not edit. -->\n' "$base"
    printf '# %s\n\n' "$title"
    [ -n "$desc" ] && printf '%s\n\n' "$desc"
    [ "$has_args" = 1 ] && printf '> Cursor has no argument placeholder — type your input after `/%s` and it is appended to this prompt; treat any `$ARGUMENTS` below as that input.\n\n' "$name"
    printf '%s\n' "$body" | to_norun_body
  } | emit "$SRC/cursor/$base"
  gen_cursor="$gen_cursor$base "

  n=$((n+1))
done

# Now that every port rendered successfully, drop any stale port whose canonical
# command was removed/renamed (safe — only runs on a complete render).
# Codex skills are directories, unlike the flat Cursor/Gemini ports. Only remove
# a directory this script actually generated (marker check) — never rm -rf a
# hand-authored or WIP directory someone dropped under commands/codex/.
for d in "$SRC/codex"/*; do
  [ -d "$d" ] || continue
  base="$(basename "$d")"
  case "$gen_codex" in
    *" $base "*) ;;
    *)
      if [ -f "$d/SKILL.md" ] && grep -q '^<!-- GENERATED from commands/' "$d/SKILL.md" 2>/dev/null; then
        rm -rf "$d"
      else
        echo "render-commands: skipping non-generated commands/codex/$base/ (no GENERATED marker) — leaving it in place" >&2
      fi
      ;;
  esac
done
prune_dir "$SRC/cursor" md   "$gen_cursor"

echo "Rendered $n command(s) -> commands/{codex,cursor}/"
