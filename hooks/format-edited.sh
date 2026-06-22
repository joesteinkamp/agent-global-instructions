#!/usr/bin/env bash
# PostToolUse / AfterTool — auto-format the file just edited using the PROJECT's
# Prettier or ESLint, if present. Cross-tool (Claude Code, Codex, Cursor,
# Antigravity/Gemini); needs no block dialect since it never blocks: always
# exits 0. Path sources mirror guard-paths.sh (single tool_input.file_path,
# Cursor top-level file_path, or Codex apply_patch envelope paths).
set -u

PLATFORM="${HOOK_PLATFORM:-claude}"
input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

format_one() {  # $1 = file path
  local fp="$1" dir root
  [ -z "$fp" ] && return 0
  [ -f "$fp" ] || return 0
  case "$fp" in
    *.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.css|*.scss|*.less|*.html|*.json|*.md|*.mdx|*.vue|*.svelte) ;;
    *) return 0 ;;
  esac
  # Walk up from the file to the nearest package.json (project root).
  dir="$(cd "$(dirname "$fp")" 2>/dev/null && pwd)" || return 0
  root="$dir"
  while [ "$root" != "/" ] && [ ! -f "$root/package.json" ]; do root="$(dirname "$root")"; done
  [ -f "$root/package.json" ] || return 0
  if [ -x "$root/node_modules/.bin/prettier" ]; then
    "$root/node_modules/.bin/prettier" --write "$fp" >/dev/null 2>&1
  elif [ -x "$root/node_modules/.bin/eslint" ]; then
    "$root/node_modules/.bin/eslint" --fix "$fp" >/dev/null 2>&1
  fi
  return 0
}

fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.filePath // .file_path // empty' 2>/dev/null)"
if [ -n "$fp" ]; then
  format_one "$fp"
elif [ "$PLATFORM" = "codex" ]; then
  # Codex apply_patch: format every file the patch adds/updates/moves (not deletes).
  cmdtext="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  if [ -n "$cmdtext" ]; then
    while IFS= read -r pf; do
      pf="${pf%$'\r'}"; pf="${pf#\"}"; pf="${pf%\"}"
      [ -n "$pf" ] && format_one "$pf"
    done < <(printf '%s\n' "$cmdtext" | sed -nE 's/^\*\*\* (Add File|Update File|Move to): (.*)$/\2/p')
  fi
fi

exit 0
