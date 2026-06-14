#!/usr/bin/env bash
# Install the guardrail hooks into Claude Code's settings.json (and copy the
# scripts into the hooks dir). Idempotent — re-running replaces our entries
# rather than duplicating them. A timestamped settings backup is made first.
#
#   ./install-hooks.sh             -> ~/.claude/   (global, default)
#   ./install-hooks.sh --project   -> ./.claude/   (this repo only)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/hooks"
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }

if [ "${1:-}" = "--project" ]; then BASE="$DIR/.claude"; else BASE="$HOME/.claude"; fi
HOOKDIR="$BASE/hooks"; SETTINGS="$BASE/settings.json"
mkdir -p "$HOOKDIR"

for s in guard-paths guard-bash format-edited; do
  cp "$SRC/$s.sh" "$HOOKDIR/$s.sh"; chmod +x "$HOOKDIR/$s.sh"
  echo "  installed $HOOKDIR/$s.sh"
done

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.backup.$(date +%s)"

add="$(jq -n --arg hd "$HOOKDIR" '{
  PreToolUse: [
    { matcher: "Edit|Write|MultiEdit|NotebookEdit", hooks: [ { type: "command", command: ($hd + "/guard-paths.sh") } ] },
    { matcher: "Bash", hooks: [ { type: "command", command: ($hd + "/guard-bash.sh") } ] }
  ],
  PostToolUse: [
    { matcher: "Edit|Write|MultiEdit", hooks: [ { type: "command", command: ($hd + "/format-edited.sh") } ] }
  ]
}')"

tmp="$(mktemp)"
jq --argjson add "$add" '
  .hooks = (.hooks // {})
  # drop any previously-installed copies of our hooks (idempotency)
  | .hooks |= with_entries(
      .value |= map(select(
        ((.hooks // []) | map(.command) | any(test("/(guard-paths|guard-bash|format-edited)\\.sh$"))) | not
      ))
    )
  # append ours
  | reduce ($add | to_entries[]) as $e (.;
      .hooks[$e.key] = ((.hooks[$e.key] // []) + $e.value))
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "Merged hooks into $SETTINGS (backup saved alongside it)."
echo "Active: auto-format (Prettier/ESLint), guard protected paths, guard dangerous shell."
