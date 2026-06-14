#!/usr/bin/env bash
# Observability — append one JSONL record per tool event to an audit log, so a
# long unattended run can be reviewed afterward. Wired to the before- and after-
# tool events of every tool. Never blocks: always exits 0.
#
# Log path: $AI_TOOL_LOG (default ~/.ai-logs/tool-calls.jsonl). Cross-tool: the
# `tool` field comes from HOOK_PLATFORM (claude|codex|gemini).
set -u

LOG="${AI_TOOL_LOG:-$HOME/.ai-logs/tool-calls.jsonl}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
platform="${HOOK_PLATFORM:-claude}"

# Read the hook payload from stdin and write a compact, truncated record.
jq -c --arg tool "$platform" --arg ts "$ts" '
  {
    ts: $ts,
    tool: $tool,
    session: (.session_id // .sessionId // null),
    cwd: (.cwd // null),
    event: (.hook_event_name // .hookEventName // null),
    tool_name: (.tool_name // .toolName // null),
    tool_use_id: (.tool_use_id // .toolUseId // null),
    input: ((.tool_input // .toolInput) | if . == null then null else tojson end),
    response: ((.tool_response // .toolResponse) | if . == null then null else tojson end)
  }
  | .input    |= (if . == null then null else .[0:2000] end)
  | .response |= (if . == null then null else .[0:2000] end)
' >> "$LOG" 2>/dev/null

exit 0
