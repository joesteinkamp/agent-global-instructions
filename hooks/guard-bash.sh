#!/usr/bin/env bash
# PreToolUse(Bash) — block clearly catastrophic commands. Exit 2 blocks and
# feeds the reason back to the model. Kept conservative on purpose: it does NOT
# block routine cleanup like `rm -rf node_modules` or `rm -rf dist`.
set -u

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0

deny() { echo "BLOCKED: $1" >&2; exit 2; }

# Catastrophic recursive deletes (root, home, parent dir).
case "$cmd" in
  *"rm -rf /"*|*"rm -fr /"*|*"rm -rf ~"*|*'rm -rf $HOME'*|*"rm -rf .."*|*"rm -rf /*"*)
    deny "destructive 'rm -rf' on a root/home/parent path: '$cmd'. Use a specific subdirectory (or 'trash')." ;;
esac

# Force pushes (allow the safer --force-with-lease).
case "$cmd" in
  *push*--force-with-lease*) : ;;
  *push*--force*|*push*" -f"*)
    deny "force push detected: '$cmd'. Avoid force-pushing; use --force-with-lease if you must." ;;
esac

exit 0
