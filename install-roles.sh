#!/usr/bin/env bash
# install-roles.sh — install the team roles into each tool's agent-definition
# directory, so "spawn a UX researcher" resolves to a real, consistent role
# instead of a generic agent.
#
#   ./install-roles.sh                 # all tools, global
#   ./install-roles.sh --project       # into ./ (this repo)
#   ./install-roles.sh claude codex    # just these tools
#
# Why this layer exists: both tools support reusable role definitions, but only
# from files on disk. Claude Code can improvise a teammate from a prompt, so
# there the files buy consistency; Codex CANNOT — an unknown agent name falls
# back to its built-in `default`, so without these files every Codex "role" is
# the same generic agent wearing a different label. That is the gap this closes.
#
# Per-tool source + destination:
#   claude  roles/*.md          -> ~/.claude/agents/   (project: ./.claude/agents/)
#   codex   roles/codex/*.toml  -> ~/.codex/agents/    (project: ./.codex/agents/)
#   cursor                      -> skipped (no reusable agent-definition format;
#                                  its CLI takes roles inline in the prompt)
#   antigravity                 -> skipped (same)
#
# roles/*.md is the canonical source of truth; roles/codex/ is GENERATED from it
# by render-roles.sh (run here automatically) — never hand-edit the port.
# Reverse with ./uninstall.sh.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/roles"
[ -d "$SRC" ] || { echo "No roles/ dir at $SRC" >&2; exit 1; }

PROJECT=0
targets=()
for a in "$@"; do
  case "$a" in
    --project) PROJECT=1;;
    claude|codex|cursor|antigravity) targets+=("$a");;
    *) echo "unknown arg: $a (use: --project | claude codex cursor antigravity)" >&2; exit 1;;
  esac
done
[ ${#targets[@]} -eq 0 ] && targets=(claude codex cursor antigravity)

# Always re-render the Codex port so it can't drift from the canonical files.
"$DIR/render-roles.sh" >/dev/null

install_dir() {  # $1 = src dir  $2 = ext  $3 = dest dir  $4 = label
  local src="$1" ext="$2" dest="$3" label="$4" f base n=0
  mkdir -p "$dest"
  for f in "$src"/*."$ext"; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    [ "$base" = "README.$ext" ] && continue
    if cmp -s "$f" "$dest/$base"; then continue; fi
    cp "$f" "$dest/$base" && n=$((n+1))
  done
  if [ "$n" -gt 0 ]; then echo "  $label: wrote $n role file(s) -> $dest"
  else echo "  $label: roles already current -> $dest"; fi
}

echo "== roles =="
for t in "${targets[@]}"; do
  case "$t" in
    claude)
      if [ "$PROJECT" = 1 ]; then install_dir "$SRC" md "$DIR/.claude/agents" claude
      else install_dir "$SRC" md "$HOME/.claude/agents" claude; fi
      ;;
    codex)
      # Codex reads project agents from ./.codex/agents/ and personal ones from
      # ~/.codex/agents/; unlike its skills, custom agents DO have a project scope.
      if [ "$PROJECT" = 1 ]; then install_dir "$SRC/codex" toml "$DIR/.codex/agents" codex
      else install_dir "$SRC/codex" toml "$HOME/.codex/agents" codex; fi
      ;;
    cursor|antigravity)
      echo "  $t: skipped (no reusable agent-definition format — roles go inline in the prompt)"
      ;;
  esac
done
