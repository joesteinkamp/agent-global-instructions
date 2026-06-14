#!/usr/bin/env bash
# PostToolUse / AfterTool — auto-format the file just edited using the PROJECT's
# Prettier or ESLint, if present. Cross-tool (Claude Code, Codex, Antigravity/
# Gemini); needs no platform dialect since it never blocks: always exits 0.
set -u

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.filePath // empty')"
[ -z "$fp" ] && exit 0
[ -f "$fp" ] || exit 0

case "$fp" in
  *.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.css|*.scss|*.less|*.html|*.json|*.md|*.mdx|*.vue|*.svelte) ;;
  *) exit 0 ;;
esac

# Walk up from the file to the nearest package.json (project root).
dir="$(cd "$(dirname "$fp")" 2>/dev/null && pwd)" || exit 0
root="$dir"
while [ "$root" != "/" ] && [ ! -f "$root/package.json" ]; do root="$(dirname "$root")"; done
[ -f "$root/package.json" ] || exit 0

if [ -x "$root/node_modules/.bin/prettier" ]; then
  "$root/node_modules/.bin/prettier" --write "$fp" >/dev/null 2>&1
elif [ -x "$root/node_modules/.bin/eslint" ]; then
  "$root/node_modules/.bin/eslint" --fix "$fp" >/dev/null 2>&1
fi

exit 0
