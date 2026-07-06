#!/usr/bin/env bash
# Install the portable commands into each tool's command/prompt directory so they
# work as /ship, /sync, /tidy, /improve, /audit everywhere.
#
#   ./install-commands.sh                     # all tools, global
#   ./install-commands.sh --project           # all tools, into ./ (this repo)
#   ./install-commands.sh claude cursor       # just these tools, global
#   ./install-commands.sh --project cursor gemini
#
# Per-tool source + destination:
#   claude  commands/*.md          -> ~/.claude/commands/   (project: ./.claude/commands/)
#   codex   commands/codex/*.md    -> ~/.codex/prompts/     (global only; invoke /prompts:<name>)
#   cursor  commands/cursor/*.md   -> ~/.cursor/commands/   (project: ./.cursor/commands/)
#   gemini  commands/gemini/*.toml -> ~/.gemini/commands/   (project: ./.gemini/commands/)
#   antigravity                    -> skipped (separate tool; hooks-only, see install-hooks.sh)
#
# commands/*.md (top level) is the canonical Claude-dialect source of truth; the
# commands/<tool>/ files are GENERATED from it by render-commands.sh (run here
# automatically) — never hand-edit them, edit the canonical file and re-render.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/commands"
[ -d "$SRC" ] || { echo "No commands/ dir at $SRC" >&2; exit 1; }

PROJECT=0
targets=()
for a in "$@"; do
  case "$a" in
    --project) PROJECT=1;;
    claude|codex|cursor|gemini|antigravity) targets+=("$a");;
    *) echo "unknown arg: $a (use: --project | claude codex cursor gemini antigravity)" >&2; exit 1;;
  esac
done
[ ${#targets[@]} -eq 0 ] && targets=(claude codex cursor gemini)

# Regenerate the per-tool ports from the canonical commands/*.md first, so what
# gets installed always reflects the current canonical (hand-edits to a generated
# port are overwritten here — edit commands/<name>.md instead). Abort on failure
# rather than installing from a half-rendered port dir (a swallowed render error
# is how codex/cursor/gemini once silently got zero commands).
if [ -x "$DIR/render-commands.sh" ]; then
  "$DIR/render-commands.sh" >/dev/null \
    || { echo "render-commands.sh failed — aborting before install (ports may be stale)" >&2; exit 1; }
fi

# Command basenames we've renamed/dropped. Pruned on every install (per tool, in
# that tool's extension) so a rename self-heals across `git pull && install`.
RETIRED="validate"

# Back up to a collision-free name (mktemp), keeping only the 5 newest backups.
backup_file() {  # $1 = file to back up
  cp "$1" "$(mktemp "$1.bak.XXXXXX")"
  local n=0 b
  while IFS= read -r b; do n=$((n+1)); if [ "$n" -gt 5 ]; then rm -f -- "$b"; fi; done \
    < <(ls -1t -- "$1".bak.* 2>/dev/null)
  return 0   # prune's last test is usually false; don't let the fn return 1 under set -e
}

# Copy every <src>/*.<ext> into <dest>, backing up a differing prior copy first,
# skipping README and pruning retired names.
install_dir() {  # $1=label  $2=src dir  $3=ext  $4=dest dir
  local label="$1" src="$2" ext="$3" dest="$4" f base dst n=0 old
  if [ ! -d "$src" ]; then echo "  $label: no $src (skipped)"; return 0; fi
  mkdir -p "$dest"
  for old in $RETIRED; do
    if [ -f "$dest/$old.$ext" ]; then rm -f "$dest/$old.$ext"; echo "  removed retired /$old"; fi
  done
  for f in "$src"/*."$ext"; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    [ "$base" = "README.$ext" ] && continue
    dst="$dest/$base"
    if [ -f "$dst" ] && ! cmp -s "$f" "$dst"; then backup_file "$dst"; echo "  backed up your edited $base"; fi
    cp "$f" "$dst"; n=$((n+1))
  done
  echo "  $label -> $dest ($n command(s))"
}

for t in "${targets[@]}"; do
  case "$t" in
    claude)
      if [ "$PROJECT" = 1 ]; then d="$DIR/.claude/commands"; else d="$HOME/.claude/commands"; fi
      install_dir claude "$SRC" md "$d";;
    codex)
      install_dir codex "$SRC/codex" md "$HOME/.codex/prompts"
      [ "$PROJECT" = 1 ] && echo "  (codex prompts are global; --project has no effect for codex)";;
    cursor)
      if [ "$PROJECT" = 1 ]; then d="$DIR/.cursor/commands"; else d="$HOME/.cursor/commands"; fi
      install_dir cursor "$SRC/cursor" md "$d";;
    gemini)
      if [ "$PROJECT" = 1 ]; then d="$DIR/.gemini/commands"; else d="$HOME/.gemini/commands"; fi
      install_dir gemini "$SRC/gemini" toml "$d";;
    antigravity)
      echo "  antigravity: command install not supported here (Antigravity CLI is a separate tool); skipped — its hooks are wired by install-hooks.sh";;
  esac
done
echo "Done. Type / in each tool to see the commands (Codex: /prompts:<name>)."
