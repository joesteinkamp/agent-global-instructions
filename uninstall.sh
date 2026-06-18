#!/usr/bin/env bash
# Reverse what install.sh added — strip exactly our entries from each tool's
# config, never touching hand-added rules or your instruction files.
#
#   ./uninstall.sh                # all tools
#   ./uninstall.sh claude         # just Claude Code
#   ./uninstall.sh codex cursor
#
# Removes, per tool: our hook entries (matched by hook-script name), the
# permissions we added (Claude/Cursor JSON rules subtracted; Codex managed TOML
# block removed; Gemini policy file deleted), and the installed command files.
# Each config is backed up first. Rendered instruction files (~/.claude/CLAUDE.md,
# etc.) and Gemini's folderTrust setting are LEFT IN PLACE.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }

# Derive the hook-script set from the actual files so it can't drift from the
# installer. HOOK_RE matches /<our-script>.sh on the dir slash.
HOOK_NAMES=()
for f in "$DIR"/hooks/*.sh; do HOOK_NAMES+=("$(basename "$f" .sh)"); done
HOOK_RE="/($(IFS='|'; echo "${HOOK_NAMES[*]}"))\\.sh"

TMPFILES=()
trap '[ ${#TMPFILES[@]} -gt 0 ] && rm -f "${TMPFILES[@]}" || true' EXIT

backup_file() {  # $1 = file to back up, keep 5 newest
  cp "$1" "$(mktemp "$1.bak.XXXXXX")"
  local n=0 b
  while IFS= read -r b; do n=$((n+1)); if [ "$n" -gt 5 ]; then rm -f -- "$b"; fi; done \
    < <(ls -1t -- "$1".bak.* 2>/dev/null)
  return 0
}

# Apply a jq program to a settings file in place (backup + atomic), no-op if
# nothing changed or the file is absent.
edit_json() {  # $1 = file, $2 = jq program, $3.. = extra jq args
  local f="$1" prog="$2"; shift 2
  [ -f "$f" ] || return 0
  local tmp; tmp="$(mktemp)"; TMPFILES+=("$tmp")
  jq "$@" "$prog" "$f" > "$tmp" || { echo "  edit failed for $f (left unchanged)" >&2; return 0; }
  if cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
  backup_file "$f"; mv "$tmp" "$f"; echo "  cleaned $f"
}

# Drop our hook entries. Handles BOTH shapes: nested .hooks[].command
# (Claude/Codex/Gemini) and flat .command (Cursor).
strip_hooks() {  # $1 = settings file
  edit_json "$1" '
    if .hooks then
      .hooks |= with_entries(.value |= map(select(
        ([ .command ] + ((.hooks // []) | map(.command))
         | map(select(. != null)) | any(test($pat))) | not)))
      | .hooks |= with_entries(select((.value | length) > 0))
      | if (.hooks == {}) then del(.hooks) else . end
    else . end
  ' --arg pat "$HOOK_RE"
}

# Subtract the permission arrays in a JSON snippet from a settings file.
strip_permissions_json() {  # $1 = settings file  $2 = snippet file
  [ -f "$2" ] || return 0
  local perms; perms="$(jq '.permissions' "$2")"
  edit_json "$1" '
    if .permissions then
      reduce ($add | to_entries[]) as $e (.;
        .permissions[$e.key] = ((.permissions[$e.key] // []) - $e.value))
      | .permissions |= with_entries(select((.value | length) > 0))
      | if (.permissions == {}) then del(.permissions) else . end
    else . end
  ' --argjson add "$perms"
}

# Remove our managed permissions block from Codex's config.toml (between sentinels).
strip_codex_block() {  # $1 = config.toml
  local f="$1"
  [ -f "$f" ] || return 0
  local begin="# >>> agent-global-instructions (codex permissions) >>>"
  local end="# <<< agent-global-instructions (codex permissions) <<<"
  grep -qF "$begin" "$f" || return 0
  local tmp; tmp="$(mktemp)"; TMPFILES+=("$tmp")
  awk -v b="$begin" -v e="$end" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$f" > "$tmp"
  if cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
  backup_file "$f"; mv "$tmp" "$f"; echo "  cleaned $f (removed codex permissions block)"
}

# Remove the command files WE installed for a tool (by basename, from our source),
# plus retired names — never touching the user's own commands.
remove_commands_dir() {  # $1 = dest dir  $2 = src dir  $3 = ext
  local dest="$1" src="$2" ext="$3" f base n=0 old
  [ -d "$dest" ] || return 0
  if [ -d "$src" ]; then
    for f in "$src"/*."$ext"; do
      [ -e "$f" ] || continue
      base="$(basename "$f")"
      [ "$base" = "README.$ext" ] && continue
      [ -f "$dest/$base" ] && { rm -f "$dest/$base"; n=$((n+1)); }
    done
  fi
  local retired="validate"   # space-separated; keep in sync with install-commands.sh RETIRED
  for old in $retired; do
    [ -f "$dest/$old.$ext" ] && { rm -f "$dest/$old.$ext"; n=$((n+1)); }
  done
  [ "$n" -gt 0 ] && echo "  removed $n command file(s) from $dest"
  return 0
}

targets=("$@"); [ ${#targets[@]} -eq 0 ] && targets=(claude codex cursor gemini)
for t in "${targets[@]}"; do
  case "$t" in
    claude)
      remove_commands_dir "$HOME/.claude/commands" "$DIR/commands" md
      strip_hooks "$HOME/.claude/settings.json"
      strip_permissions_json "$HOME/.claude/settings.json" "$DIR/settings-permissions.snippet.json"
      ;;
    codex)
      remove_commands_dir "$HOME/.codex/prompts" "$DIR/commands/codex" md
      strip_hooks "$HOME/.codex/hooks.json"
      strip_codex_block "$HOME/.codex/config.toml"
      ;;
    cursor)
      remove_commands_dir "$HOME/.cursor/commands" "$DIR/commands/cursor" md
      strip_hooks "$HOME/.cursor/hooks.json"
      strip_permissions_json "$HOME/.cursor/cli-config.json" "$DIR/settings-permissions.cursor.snippet.json"
      ;;
    gemini|antigravity)
      remove_commands_dir "$HOME/.gemini/commands" "$DIR/commands/gemini" toml
      strip_hooks "$HOME/.gemini/settings.json"
      if [ -f "$HOME/.gemini/policies/gemini-guardrails.toml" ]; then
        rm -f "$HOME/.gemini/policies/gemini-guardrails.toml"
        echo "  removed $HOME/.gemini/policies/gemini-guardrails.toml"
      fi
      ;;
    *) echo "  unknown target: $t (use: claude codex cursor gemini)" >&2;;
  esac
done
echo "Done. Backups saved next to each file. Instruction files (and Gemini folderTrust) left in place."
