#!/usr/bin/env bash
# render-commands.sh — generate the per-tool command ports from the canonical
# Claude-dialect commands in commands/*.md, so there is ONE source of truth and
# the ports can't drift. Mirrors how customize.sh renders the instruction files
# from template.md.
#
#   ./render-commands.sh         # regenerate commands/{codex,cursor,gemini}/
#
# The generated files are snapshots — NEVER hand-edit them (install-commands.sh
# re-renders on every install). To change a command, edit commands/<name>.md and
# re-render. The ports are committed so port diffs show up in review.
#
# Translation rules (canonical -> port):
#   - frontmatter: description kept everywhere; argument-hint kept for codex;
#     allowed-tools dropped (Claude-only — other tools govern tools elsewhere).
#   - $ARGUMENTS: kept for codex; -> {{args}} for gemini; kept (with a note) for
#     cursor (no placeholder — it appends typed input).
#   - !`cmd` shell-injection: -> !{cmd} for gemini (native); -> run `cmd` for
#     codex/cursor (no injection — tell the agent to run it).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/commands"
[ -d "$SRC" ] || { echo "No commands/ dir at $SRC" >&2; exit 1; }

TMPFILES=()
trap '[ ${#TMPFILES[@]} -gt 0 ] && rm -f "${TMPFILES[@]}" || true' EXIT

# --- frontmatter / body extractors (CR-stripped so CRLF files parse) ---------
fm_field() {  # $1 = file, $2 = key  -> prints the trimmed value (empty if absent)
  awk -v k="$2: " '
    { sub(/\r$/,"") }
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && index($0,k)==1 {
      v=$0; sub(/^[^:]*: /,"",v); gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); print v; exit
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
to_gemini_body() { sed -e 's/!`\([^`]*\)`/!{\1}/g' -e 's/\$ARGUMENTS/{{args}}/g'; }
to_norun_body()  { sed -e 's/!`\([^`]*\)`/run `\1`/g'; }   # codex + cursor: keep $ARGUMENTS

toml_escape() { sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }      # for TOML "..." basic strings

# Write stdin to a destination atomically (temp + mv) so a mid-render failure
# never leaves a truncated/empty port file.
emit() {  # $1 = destination path
  local t; t="$(mktemp)"; TMPFILES+=("$t")
  cat > "$t"
  mv "$t" "$1"
}

mkdir -p "$SRC/codex" "$SRC/cursor" "$SRC/gemini"
# Clear prior generated output so a removed/renamed canonical command leaves no
# stale port behind (the dirs are generated snapshots).
rm -f "$SRC"/codex/*.md "$SRC"/cursor/*.md "$SRC"/gemini/*.toml 2>/dev/null || true

n=0
for f in "$SRC"/*.md; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  [ "$base" = "README.md" ] && continue
  name="${base%.md}"
  title="$(printf '%s' "${name:0:1}" | tr '[:lower:]' '[:upper:]')${name:1}"
  desc="$(fm_field "$f" description)"
  arghint="$(fm_field "$f" argument-hint)"
  body="$(fm_body "$f")"
  has_args=0; printf '%s\n' "$body" | grep -q '\$ARGUMENTS' && has_args=1

  # TOML literal strings ('''...''') can't contain ''' and have no escape — fail
  # loudly rather than emit an unparseable Gemini command.
  case "$body" in
    *"'''"*) echo "render-commands: commands/$base body contains ''' — breaks the Gemini TOML literal string. Aborting." >&2; exit 1;;
  esac

  # --- Codex: ~/.codex/prompts/<name>.md (invoke /prompts:<name>) ---
  # Generated marker lives in the YAML frontmatter (a comment Codex ignores), so
  # it isn't sent to the model as body text.
  {
    printf -- '---\n'
    printf '# GENERATED from commands/%s by render-commands.sh — do not edit. Invoke as /prompts:%s\n' "$base" "$name"
    printf 'description: %s\n' "$desc"
    [ -n "$arghint" ] && printf 'argument-hint: %s\n' "$arghint"
    printf -- '---\n\n'
    printf '%s\n' "$body" | to_norun_body
  } | emit "$SRC/codex/$base"

  # --- Cursor: ~/.cursor/commands/<name>.md (plain markdown, no frontmatter) ---
  {
    printf '<!-- GENERATED from commands/%s by render-commands.sh — do not edit. -->\n' "$base"
    printf '# %s\n\n' "$title"
    [ -n "$desc" ] && printf '%s\n\n' "$desc"
    [ "$has_args" = 1 ] && printf '> Cursor has no argument placeholder — type your input after `/%s` and it is appended to this prompt; treat any `$ARGUMENTS` below as that input.\n\n' "$name"
    printf '%s\n' "$body" | to_norun_body
  } | emit "$SRC/cursor/$base"

  # --- Gemini: ~/.gemini/commands/<name>.toml ---
  {
    printf '# GENERATED from commands/%s by render-commands.sh — do not edit.\n' "$base"
    printf 'description = "%s"\n\n' "$(printf '%s' "$desc" | toml_escape)"
    printf "prompt = '''\n"
    printf '%s\n' "$body" | to_gemini_body
    printf "'''\n"
  } | emit "$SRC/gemini/$name.toml"

  n=$((n+1))
done

echo "Rendered $n command(s) -> commands/{codex,cursor,gemini}/"
