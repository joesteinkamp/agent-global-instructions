#!/usr/bin/env bash
# Install the portable command files into Claude Code's command directory so
# they work as /ship, /save, /pr, /sync, /tidy everywhere.
#
#   ./install-commands.sh            -> ~/.claude/commands/   (global, default)
#   ./install-commands.sh --project  -> ./.claude/commands/   (this repo only)
#
# Other tools: Codex and Cursor have their own command/prompt locations — point
# them at ./commands/*.md or copy the bodies in.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/commands"
[ -d "$SRC" ] || { echo "No commands/ dir at $SRC" >&2; exit 1; }

if [ "${1:-}" = "--project" ]; then DEST="$DIR/.claude/commands"; else DEST="$HOME/.claude/commands"; fi
mkdir -p "$DEST"

for f in "$SRC"/*.md; do
  [ "$(basename "$f")" = "README.md" ] && continue   # docs, not a command
  cp "$f" "$DEST/"
  echo "  installed /$(basename "$f" .md)"
done
echo "-> $DEST"
echo "Type / in Claude Code to see them."
