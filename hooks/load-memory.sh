#!/usr/bin/env bash
# SessionStart hook — surface the memory stores that live OUTSIDE the tool so the
# agent reads them before anything personal. Claude Code already auto-loads its
# own project memory (~/.claude/projects/<project>/memory/MEMORY.md); this hook
# points at the cross-tool stores it otherwise wouldn't know about — a Hermes
# memory OS, an OpenClaw workspace, or a project-level MEMORY.md / memory/ dir.
#
# Only stores that actually exist are mentioned. If none are found, it stays
# silent. Never blocks (always exits 0). Wired for the tools whose SessionStart
# can inject context: Claude (hookSpecificOutput.additionalContext) and Cursor
# (additional_context). Other tools have no equivalent — no-op there.
set -u

PLATFORM="${HOOK_PLATFORM:-claude}"
input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

# Only Claude + Cursor support SessionStart context injection today.
case "$PLATFORM" in claude|cursor) ;; *) exit 0;; esac

cwd="$(printf '%s' "$input" | jq -r '.cwd // .workspace_roots[0]? // empty' 2>/dev/null)"; [ -z "$cwd" ] && cwd="$PWD"

found=""
add() { found="$found
$1"; }

# Hermes-style memory OS.
if [ -d "$HOME/.hermes" ]; then
  add "- **Hermes memory OS** at \`~/.hermes/\` — read \`SOUL.md\` (identity/values), \`memories/USER.md\` + \`memories/MEMORY.md\` (curated facts), \`rulebook.md\` (operating protocol), and any per-agent \`profiles/<name>/\` store."
fi

# OpenClaw workspace.
if [ -d "$HOME/.openclaw/workspace" ]; then
  add "- **OpenClaw workspace** at \`~/.openclaw/workspace/\` — read it for prior context."
fi

# Project-level memory in the working directory.
if [ -f "$cwd/MEMORY.md" ]; then
  add "- **Project memory** at \`$cwd/MEMORY.md\` — project-specific facts and decisions."
fi
if [ -d "$cwd/memory" ]; then
  add "- **Project memory dir** at \`$cwd/memory/\` — read \`MEMORY.md\` there as the index."
fi

[ -z "$found" ] && exit 0

ctx="Memory stores detected on this machine. Before any personal task, read the relevant one — it reflects who the user is and prior decisions, so you don't re-ask. Different systems keep different files; prefer the one for the system you're running as.
$found
- **Write durable facts back** to the right file (and say where)."

if [ "$PLATFORM" = "cursor" ]; then
  jq -nc --arg c "$ctx" '{additional_context:$c}'
else
  jq -nc --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
fi
exit 0
