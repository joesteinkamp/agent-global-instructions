#!/usr/bin/env bash
# One-shot installer — render the instructions and install every layer in one
# go. Wraps the focused scripts so you don't have to remember the sequence.
#
#   ./install.sh                 # all tools: instructions + commands + hooks + settings
#   ./install.sh --yes           # same, but don't prompt to confirm the global render
#   ./install.sh claude          # just Claude Code
#   ./install.sh codex cursor    # instructions + commands + hooks + settings for those
#
# Layers (each applied to whichever targets you name):
#   - instructions (customize.sh --global): all tools, always — the portable core.
#   - commands (install-commands.sh):       per tool (~/.claude, ~/.codex/prompts, ~/.cursor, ~/.gemini).
#   - hooks (install-hooks.sh):             per tool.
#   - settings/permissions (install-settings.sh): per tool (native model differs; see that script).
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
    claude|codex|cursor|gemini|antigravity) targets+=("$a");;
    *) echo "unknown arg: $a (use: --yes | claude | codex | cursor | gemini | antigravity)" >&2; exit 1;;
  esac
done
[ ${#targets[@]} -eq 0 ] && targets=(claude codex cursor gemini)

echo "== instructions =="
# Portable core — renders every tool's instruction file from template.md.
if [ -n "$yes_flag" ]; then "$DIR/customize.sh" --global --yes; else "$DIR/customize.sh" --global; fi

echo "== commands =="
"$DIR/install-commands.sh" "${targets[@]}"

echo "== hooks =="
"$DIR/install-hooks.sh" "${targets[@]}"

echo "== settings (per-tool permissions) =="
"$DIR/install-settings.sh" "${targets[@]}"

echo "Done. Reverse with ./uninstall.sh."
