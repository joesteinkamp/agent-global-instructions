#!/usr/bin/env bash
# Install the portable command files into Claude Code's command directory so
# they work as /ship, /sync, /tidy, /improve, /audit everywhere.
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

# Commands we've renamed or dropped. A plain copy never deletes the old name, so
# a machine that once had /validate would keep it forever alongside /improve.
# Prune them on every install so `git pull && ./install-commands.sh` self-heals.
#   old-name -> new-name (new-name is informational, shown in the message)
RETIRED="validate.md:improve.md"
for entry in $RETIRED; do
  old="${entry%%:*}"; new="${entry#*:}"
  if [ -f "$DEST/$old" ]; then
    rm -f "$DEST/$old"
    echo "  removed retired /${old%.md} (now /${new%.md})"
  fi
done

# Back up to a collision-free name (mktemp) and keep only the 5 newest backups.
backup_file() {  # $1 = file to back up
  cp "$1" "$(mktemp "$1.bak.XXXXXX")"
  local n=0 b
  while IFS= read -r b; do n=$((n+1)); if [ "$n" -gt 5 ]; then rm -f -- "$b"; fi; done \
    < <(ls -1t -- "$1".bak.* 2>/dev/null)
  return 0   # prune's last test is usually false; don't let the fn return 1 under set -e
}

backed_up=0
for f in "$SRC"/*.md; do
  base="$(basename "$f")"
  [ "$base" = "README.md" ] && continue              # docs, not a command
  dst="$DEST/$base"
  # If an installed copy exists and differs, back it up before overwriting so a
  # hand-edited command is never silently lost.
  if [ -f "$dst" ] && ! cmp -s "$f" "$dst"; then
    backup_file "$dst"; backed_up=1
    echo "  backed up your edited $base"
  fi
  cp "$f" "$dst"
  echo "  installed /$(basename "$f" .md)"
done
echo "-> $DEST"
[ "$backed_up" = 1 ] && echo "(your prior versions were saved as *.bak)"
echo "Type / in Claude Code to see them."
