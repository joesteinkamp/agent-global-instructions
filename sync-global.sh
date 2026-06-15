#!/usr/bin/env bash
# Global sync — the counterpart to ./sync.sh (which is project-only and never
# touches global config). This script does the opposite: it ONLY writes to the
# hand-maintained GLOBAL instruction files on this machine, keeping all of them
# byte-identical so every tool (Claude Code, Codex, Gemini) reads the same rules.
#
# These global files are intentionally decoupled from this repo — they carry
# Joe's customizations (e.g. the Tailscale dev/preview section). So the source
# of truth here is a global file, NOT the repo's AGENTS.md. Edit one global file
# (default: ~/.claude/CLAUDE.md), then run this to propagate it to the rest.
#
#   ./sync-global.sh                 # copy ~/.claude/CLAUDE.md -> the others
#   ./sync-global.sh path/to/src.md  # use a different file as the source
set -euo pipefail

SRC="${1:-$HOME/.claude/CLAUDE.md}"
[ -f "$SRC" ] || { echo "Source not found: $SRC" >&2; exit 1; }

# The global instruction files this machine reads, by tool.
TARGETS=(
  "$HOME/.claude/CLAUDE.md"   # Claude Code
  "$HOME/.codex/AGENTS.md"    # Codex
  "$HOME/.gemini/GEMINI.md"   # Gemini / Antigravity
  "$HOME/AGENTS.md"           # second AGENTS copy
)

# Back up to a collision-free name (mktemp) and keep only the 5 newest backups.
backup_file() {  # $1 = file to back up
  cp "$1" "$(mktemp "$1.bak.XXXXXX")"
  local n=0 b
  while IFS= read -r b; do n=$((n+1)); [ "$n" -gt 5 ] && rm -f -- "$b"; done \
    < <(ls -1t -- "$1".bak.* 2>/dev/null)
}

changed=0
for t in "${TARGETS[@]}"; do
  [ "$t" = "$SRC" ] && continue                  # don't copy onto the source
  if [ -f "$t" ] && cmp -s "$SRC" "$t"; then
    echo "  ok (already in sync) $t"
    continue
  fi
  mkdir -p "$(dirname "$t")"
  [ -f "$t" ] && { backup_file "$t"; echo "  backed up your prior $t"; }
  cp "$SRC" "$t"
  echo "  -> $t"
  changed=1
done

echo "Source: $SRC"
[ "$changed" = 1 ] && echo "(prior versions saved as *.bak)" || echo "Nothing to do — all global files already match."
echo "(This touched GLOBAL config only — project files are untouched.)"
