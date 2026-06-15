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

backed_up=0
for f in "$SRC"/*.md; do
  base="$(basename "$f")"
  [ "$base" = "README.md" ] && continue              # docs, not a command
  dst="$DEST/$base"
  # If an installed copy exists and differs, back it up before overwriting so a
  # hand-edited command is never silently lost.
  if [ -f "$dst" ] && ! cmp -s "$f" "$dst"; then
    cp "$dst" "$dst.bak.$(date +%s)"; backed_up=1   # timestamped: never clobber a prior backup
    echo "  backed up your edited $base -> $base.bak.<ts>"
  fi
  cp "$f" "$dst"
  echo "  installed /$(basename "$f" .md)"
done
echo "-> $DEST"
[ "$backed_up" = 1 ] && echo "(your prior versions were saved as *.bak)"
echo "Type / in Claude Code to see them."
