#!/usr/bin/env bash
# One-shot installer — render the instructions and install every layer in one
# go. Wraps the focused scripts so you don't have to remember the sequence.
#
#   ./install.sh                 # all tools: instructions + commands + hooks + settings
#   ./install.sh --yes           # same, but don't prompt to confirm the global render
#   ./install.sh claude          # just Claude Code (incl. the Claude-only settings layer)
#   ./install.sh codex gemini    # instructions + hooks for Codex / Gemini
#
# Layers by tool:
#   - instructions (customize.sh --global): all tools, always — the portable core.
#   - commands (install-commands.sh):       Claude only (lives in ~/.claude/commands).
#   - hooks (install-hooks.sh):             whichever targets you name.
#   - settings/permissions (install-settings.sh): Claude only (client-enforced).
#
# Reverse it all with ./uninstall.sh.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

# Split args into flags and tool targets.
yes_flag=""
targets=()
for a in "$@"; do
  case "$a" in
    --yes|-y) yes_flag="--yes";;
    claude|codex|gemini|antigravity) targets+=("$a");;
    *) echo "unknown arg: $a (use: --yes | claude | codex | gemini)" >&2; exit 1;;
  esac
done
[ ${#targets[@]} -eq 0 ] && targets=(claude codex gemini)

has_target() { local t; for t in "${targets[@]}"; do [ "$t" = "$1" ] && return 0; done; return 1; }

echo "== instructions =="
# Portable core — renders every tool's instruction file from template.md.
"$DIR/customize.sh" --global $yes_flag

if has_target claude; then
  echo "== commands =="
  "$DIR/install-commands.sh"
fi

echo "== hooks =="
"$DIR/install-hooks.sh" "${targets[@]}"

if has_target claude; then
  echo "== settings (Claude-only permissions) =="
  "$DIR/install-settings.sh"
fi

echo "Done. Reverse with ./uninstall.sh."
