#!/usr/bin/env bash
# Write the memoryOS registry — ~/.ai/memory-os — naming where session-survey
# lessons land on THIS machine. The scorecard survey (hooks/scorecard-*.sh +
# hooks/scorecard.sh) appends lessons there and load-memory.sh reads them back
# at SessionStart. Lessons always go to a LESSONS.md this project owns; a
# store's own curated files (e.g. Hermes memories/MEMORY.md) are never touched.
#
#   ./setup-memory-os.sh            # detect, confirm interactively
#   ./setup-memory-os.sh --yes      # take the detected/default store, no prompt
#   ./setup-memory-os.sh --force    # reconfigure even if the registry exists
#
# Types: hermes (~/.hermes → memories/LESSONS.md) · markdown (any dir) ·
#        obsidian (a vault is a markdown dir) · notion (keeps a local markdown
#        mirror; an interactive agent syncs it to Notion via MCP — headless
#        shells can't authenticate to Notion).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=hooks/memory-os.sh
. "$DIR/hooks/memory-os.sh"

CFG="${AI_MEMORYOS_CONFIG:-$HOME/.ai/memory-os}"
yes=""; force=""
for a in "$@"; do
  case "$a" in
    --yes|-y) yes=1;;
    --force)  force=1;;
    *) echo "usage: setup-memory-os.sh [--yes] [--force]" >&2; exit 1;;
  esac
done

if [ -f "$CFG" ] && [ -z "$force" ]; then
  memoryos_load
  echo "memoryOS already configured: $MEMORYOS_TYPE at $MEMORYOS_PATH (lessons: $MEMORYOS_LESSONS)"
  echo "Re-run with --force to change it."
  exit 0
fi

# Detected default.
if [ -d "$HOME/.hermes" ]; then def_type="hermes"; def_path="$HOME/.hermes"
else def_type="markdown"; def_path="$HOME/.ai-memory"; fi

type="$def_type"; path="$def_path"
if [ -z "$yes" ] && [ -t 0 ]; then
  echo "Where should session-survey lessons live (the machine's memoryOS)?"
  echo "  1) $def_type at $def_path  (detected default)"
  echo "  2) markdown — a plain directory (default ~/.ai-memory)"
  echo "  3) obsidian — a vault directory"
  echo "  4) notion — local markdown mirror; agent syncs via Notion MCP"
  printf 'Choice [1]: '
  read -r choice || choice=""
  case "${choice:-1}" in
    1|"") ;;
    2) type="markdown"; printf 'Directory [~/.ai-memory]: '; read -r p || p=""; path="${p:-$HOME/.ai-memory}";;
    3) type="obsidian"; printf 'Vault path: '; read -r p || p=""
       [ -n "$p" ] || { echo "obsidian needs a vault path" >&2; exit 1; };  path="$p";;
    4) type="notion";   printf 'Local mirror dir [~/.ai-memory]: '; read -r p || p=""; path="${p:-$HOME/.ai-memory}";;
    *) echo "unknown choice: $choice" >&2; exit 1;;
  esac
fi
case "$path" in "~/"*) path="$HOME/${path#\~/}";; esac

mkdir -p "$(dirname "$CFG")"
{
  echo "# memoryOS registry — where session-survey lessons land on this machine."
  echo "# Written by agent-global-instructions/setup-memory-os.sh; edit or re-run --force to change."
  echo "# MEMORYOS_TYPE: hermes | markdown | obsidian | notion"
  echo "MEMORYOS_TYPE=$type"
  echo "MEMORYOS_PATH=$path"
} > "$CFG"
chmod 600 "$CFG" 2>/dev/null || true

memoryos_load
echo "memoryOS registry -> $CFG ($MEMORYOS_TYPE at $MEMORYOS_PATH)"
echo "Lessons will land in $MEMORYOS_LESSONS and be read back at session start."
