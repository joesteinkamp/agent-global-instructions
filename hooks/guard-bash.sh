#!/usr/bin/env bash
# PreToolUse / BeforeTool guard: block clearly catastrophic shell commands.
# Cross-tool (Claude Code, Codex, Antigravity/Gemini) via HOOK_PLATFORM.
# Conservative — does NOT block routine cleanup like `rm -rf node_modules`.
set -u

PLATFORM="${HOOK_PLATFORM:-claude}"
input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // .tool_input.cmd // .command // empty')"
[ -z "$cmd" ] && exit 0

block() {  # $1 = reason
  case "$PLATFORM" in
    gemini|antigravity) jq -nc --arg r "$1" '{decision:"deny",reason:$r}'; exit 0;;
    *)                  echo "$1" >&2; exit 2;;
  esac
}

# Catastrophic recursive deletes (root, home, parent dir).
case "$cmd" in
  *"rm -rf /"*|*"rm -fr /"*|*"rm -rf ~"*|*'rm -rf $HOME'*|*"rm -rf .."*|*"rm -rf /*"*)
    block "BLOCKED: destructive 'rm -rf' on a root/home/parent path: '$cmd'. Use a specific subdirectory (or 'trash').";;
esac

# Force pushes (allow the safer --force-with-lease).
case "$cmd" in
  *push*--force-with-lease*) : ;;
  *push*--force*|*push*" -f"*)
    block "BLOCKED: force push detected: '$cmd'. Avoid force-pushing; use --force-with-lease if you must.";;
esac

exit 0
