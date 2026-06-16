#!/usr/bin/env bash
# Reverse what install.sh added — strip exactly our entries from each tool's
# config, never touching hand-added rules or your instruction files.
#
#   ./uninstall.sh                # all tools
#   ./uninstall.sh claude         # just Claude Code
#   ./uninstall.sh codex gemini
#
# Removes: our hook entries (matched by hook-script name), the Claude-only
# permissions rules (subtracted using settings-permissions.snippet.json), and the
# installed command files. Each config is backed up first. Rendered instruction
# files (~/.claude/CLAUDE.md, etc.) are LEFT IN PLACE — they're yours; delete
# them by hand if you want them gone.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }

# Derive the hook-script set from the actual files, so it can't drift from the
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

strip_hooks() {  # $1 = settings file
  edit_json "$1" '
    if .hooks then
      .hooks |= with_entries(.value |= map(select(
        ((.hooks // []) | map(.command) | any(test($pat))) | not)))
      | .hooks |= with_entries(select((.value | length) > 0))
      | if (.hooks == {}) then del(.hooks) else . end
    else . end
  ' --arg pat "$HOOK_RE"
}

strip_permissions() {  # $1 = settings file
  local perms; perms="$(jq '.permissions' "$DIR/settings-permissions.snippet.json")"
  edit_json "$1" '
    if .permissions then
      reduce ($add | to_entries[]) as $e (.;
        .permissions[$e.key] = ((.permissions[$e.key] // []) - $e.value))
      | .permissions |= with_entries(select((.value | length) > 0))
      | if (.permissions == {}) then del(.permissions) else . end
    else . end
  ' --argjson add "$perms"
}

remove_commands() {
  local d="$HOME/.claude/commands" base n=0
  [ -d "$d" ] || return 0
  for f in "$DIR"/commands/*.md; do
    base="$(basename "$f")"
    [ "$base" = "README.md" ] && continue
    if [ -f "$d/$base" ]; then rm -f "$d/$base"; n=$((n+1)); fi
  done
  [ "$n" -gt 0 ] && echo "  removed $n command file(s) from $d"
  return 0
}

targets=("$@"); [ ${#targets[@]} -eq 0 ] && targets=(claude codex gemini)
for t in "${targets[@]}"; do
  case "$t" in
    claude)
      remove_commands
      strip_hooks "$HOME/.claude/settings.json"
      strip_permissions "$HOME/.claude/settings.json"
      ;;
    codex)              strip_hooks "$HOME/.codex/hooks.json";;
    gemini|antigravity) strip_hooks "$HOME/.gemini/settings.json";;
    *) echo "  unknown target: $t (use: claude codex gemini)" >&2;;
  esac
done
echo "Done. Backups saved next to each file. Instruction files left in place."
