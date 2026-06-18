#!/usr/bin/env bash
# SessionEnd hook — append a close record to the audit log so the trail shows
# when and why each session ended (clear/logout/prompt_input_exit/resume/other).
# The platform ignores SessionEnd output entirely, so this is pure observability:
# it closes the loop opened by the SessionStart memory loader and the per-tool
# log records, giving ./audit.sh a clean start-to-finish timeline.
#
# Audit log: $AI_TOOL_LOG (default ~/.ai-logs/tool-calls.jsonl) — same record
# shape as log-tool.sh. Claude only (others have no SessionEnd event).
set -u
umask 077

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
platform="${HOOK_PLATFORM:-claude}"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

LOG="${AI_TOOL_LOG:-$HOME/.ai-logs/tool-calls.jsonl}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0
chmod 700 "$(dirname "$LOG")" 2>/dev/null || true
[ -e "$LOG" ] || : > "$LOG" 2>/dev/null || true
chmod 600 "$LOG" 2>/dev/null || true

printf '%s' "$input" | jq -c --arg tool "$platform" --arg ts "$ts" '
  {ts:$ts, tool:$tool, session:(.session_id // .sessionId // .conversation_id // null),
   cwd:(.cwd // null), event:"SessionEnd",
   tool_name:(.reason // "other"), tool_use_id:null,
   input:("session ended: " + (.reason // "other")), response:null}' >> "$LOG" 2>/dev/null

exit 0
