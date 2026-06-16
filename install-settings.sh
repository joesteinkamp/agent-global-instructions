#!/usr/bin/env bash
# Install the client-enforced permissions layer into Claude Code's settings.
# This is the Claude-only counterpart to install-hooks.sh: it unions the
# permission rules from settings-permissions.snippet.json into
# ~/.claude/settings.json (idempotent, order-preserving, with a timestamped
# backup). deny rules mirror guard-paths.sh but are enforced by the client, not
# a best-effort hook. uninstall.sh subtracts exactly the same rules.
#
#   ./install-settings.sh          # -> ~/.claude/settings.json
#
# Codex / Gemini have their own permission models and are intentionally not
# touched here.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SNIPPET="$DIR/settings-permissions.snippet.json"
SF="$HOME/.claude/settings.json"
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }
[ -f "$SNIPPET" ] || { echo "No snippet at $SNIPPET" >&2; exit 1; }

TMPFILES=()
trap '[ ${#TMPFILES[@]} -gt 0 ] && rm -f "${TMPFILES[@]}" || true' EXIT

# Back up a file to a collision-free name, keeping only the 5 newest backups.
backup_file() {  # $1 = file to back up
  cp "$1" "$(mktemp "$1.bak.XXXXXX")"
  local n=0 b
  while IFS= read -r b; do n=$((n+1)); if [ "$n" -gt 5 ]; then rm -f -- "$b"; fi; done \
    < <(ls -1t -- "$1".bak.* 2>/dev/null)
  return 0   # prune's last test is usually false; don't let the fn return 1 under set -e
}

mkdir -p "$(dirname "$SF")"
[ -f "$SF" ] || echo '{}' > "$SF"

perms="$(jq '.permissions' "$SNIPPET")"
tmp="$(mktemp)"; TMPFILES+=("$tmp")
# For each of allow/deny/ask in the snippet, append our rules that aren't already
# present (order-preserving union → idempotent, never duplicates a re-run).
jq --argjson add "$perms" '
  .permissions = (.permissions // {})
  | reduce ($add | to_entries[]) as $e (.;
      .permissions[$e.key] =
        ((.permissions[$e.key] // []) as $cur
         | $cur + ($e.value - $cur)))
' "$SF" > "$tmp" || { echo "merge failed for $SF (left unchanged)" >&2; exit 1; }

if cmp -s "$tmp" "$SF"; then
  echo "  claude  -> $SF (permissions already current, no change)"
else
  backup_file "$SF"; mv "$tmp" "$SF"
  echo "  claude  -> $SF (permissions deny/ask merged)"
fi
