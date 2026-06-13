#!/usr/bin/env bash
# Project-local sync. Propagates the canonical AGENTS.md to the other
# instruction filenames *inside this project directory only* — so whichever
# tool opens this project (Claude Code, Gemini, Codex, Cursor) finds the file
# it looks for. It NEVER writes outside this directory / to global config.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/AGENTS.md"

# Filename aliases, all kept within this project directory.
TARGETS=(
  "$DIR/CLAUDE.md"   # Claude Code (project-level)
  "$DIR/GEMINI.md"   # Gemini CLI (project-level)
)

for t in "${TARGETS[@]}"; do
  cp "$SRC" "$t"
  echo "  -> $t"
done

echo "Synced within project: $DIR"
echo "(Global config on this machine is intentionally NOT touched.)"
