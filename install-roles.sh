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
#   cursor  roles/cursor/*.md   -> ~/.cursor/agents/   (project: ./.cursor/agents/)
#   antigravity roles/antigravity/*.md -> ~/.gemini/config/agents/ (project: ./.agents/agents/)
#
# roles/*.md is the canonical source of truth; roles/{codex,cursor,antigravity}/
# are GENERATED from it
# by render-roles.sh (run here automatically) — never hand-edit the port.
# Reverse with ./uninstall.sh.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/roles"
[ -d "$SRC" ] || { echo "No roles/ dir at $SRC" >&2; exit 1; }
# shellcheck source=lib/preserve.sh
. "$DIR/lib/preserve.sh"

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

# Always re-render the ports so they can't drift from the canonical files.
"$DIR/render-roles.sh" >/dev/null

# Each role goes through the install ledger (lib/preserve.sh): a role you
# edited is saved to ~/.ai/install-state/preserved/ before it's replaced,
# instead of being overwritten silently as it was before.
install_dir() {  # $1 = src dir  $2 = ext  $3 = dest dir  $4 = label  [$5 = repo-relative src dir, or render:roles for a port]
  local src="$1" ext="$2" dest="$3" label="$4" rel="${5:-}" f base n=0
  pv_planning || mkdir -p "$dest"
  for f in "$src"/*."$ext"; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    [ "$base" = "README.$ext" ] && continue
    case "$rel" in
      render:*) pv_write role "$f" "$dest/$base" "$rel" || return 1;;
      *)        pv_write role "$f" "$dest/$base" "${rel:+$rel/$base}" || return 1;;
    esac
    case "$PV_ACTION" in created|updated|replaced-custom) n=$((n+1));; esac
  done
  if [ "$n" -gt 0 ]; then echo "  $label: wrote $n role file(s) -> $dest"
  else echo "  $label: roles already current -> $dest"; fi
}

echo "== roles =="
for t in "${targets[@]}"; do
  case "$t" in
    claude)
      if [ "$PROJECT" = 1 ]; then install_dir "$SRC" md "$DIR/.claude/agents" claude roles
      else install_dir "$SRC" md "$HOME/.claude/agents" claude roles; fi
      ;;
    codex)
      # Codex reads project agents from ./.codex/agents/ and personal ones from
      # ~/.codex/agents/; unlike its skills, custom agents DO have a project scope.
      if [ "$PROJECT" = 1 ]; then install_dir "$SRC/codex" toml "$DIR/.codex/agents" codex render:roles
      else install_dir "$SRC/codex" toml "$HOME/.codex/agents" codex render:roles; fi
      ;;
    cursor)
      # Cursor also reads ~/.claude/agents and ~/.codex/agents, but a .cursor/
      # definition wins and only this port carries Cursor's `readonly` flag.
      if [ "$PROJECT" = 1 ]; then install_dir "$SRC/cursor" md "$DIR/.cursor/agents" cursor render:roles
      else install_dir "$SRC/cursor" md "$HOME/.cursor/agents" cursor render:roles; fi
      ;;
    antigravity)
      if [ "$PROJECT" = 1 ]; then install_dir "$SRC/antigravity" md "$DIR/.agents/agents" antigravity render:roles
      else install_dir "$SRC/antigravity" md "$HOME/.gemini/config/agents" antigravity render:roles; fi
      ;;
  esac
done
# Run on its own (not under install.sh): ask about anything parked, report.
pv_finish
