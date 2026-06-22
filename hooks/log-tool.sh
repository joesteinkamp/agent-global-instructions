#!/usr/bin/env bash
# Observability — append one JSONL record per tool event to an audit log, so a
# long unattended run can be reviewed afterward. Wired to the before- and after-
# tool events of every tool. Never blocks: always exits 0.
#
# Log path: $AI_TOOL_LOG (default ~/.ai-logs/tool-calls.jsonl). Cross-tool: the
# `tool` field comes from HOOK_PLATFORM (claude|codex|gemini).
#
# Secrets: tool input/response can contain credentials, tokens, .env contents,
# and MCP responses (email, account data). This log is a durable sink, so:
#   - it is created 0600 in a 0700 dir (umask 077 + explicit chmod),
#   - common secret shapes are redacted before writing,
#   - set AI_LOG_RESPONSES=0 to drop tool_response entirely (input is usually
#     enough for an audit trail and is lower-risk).
# Redaction is best-effort pattern matching, not a guarantee — treat the log as
# sensitive regardless.
set -u
umask 077

LOG="${AI_TOOL_LOG:-$HOME/.ai-logs/tool-calls.jsonl}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0
chmod 700 "$(dirname "$LOG")" 2>/dev/null || true
[ -e "$LOG" ] || : > "$LOG" 2>/dev/null || true
chmod 600 "$LOG" 2>/dev/null || true
command -v jq >/dev/null 2>&1 || exit 0

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
platform="${HOOK_PLATFORM:-claude}"
log_resp="${AI_LOG_RESPONSES:-1}"

# Read the hook payload from stdin and write a compact, truncated, redacted record.
jq -c --arg tool "$platform" --arg ts "$ts" --arg logresp "$log_resp" '
  # mask common secret shapes in a string (best-effort)
  def redact:
    gsub("(?i)bearer\\s+[A-Za-z0-9._\\-]+"; "bearer ***")
    | gsub("(?i)(?<k>authorization|api[_-]?key|secret|password|passwd|token|access[_-]?key)(?<s>\"?\\s*[:=]\\s*\"?)[^\\s\"'"'"',;]+"; "\(.k)\(.s)***")
    | gsub("(?i)(?<sch>postgres|postgresql|mysql|mongodb|redis|amqp)://[^:@/\\s]+:[^@/\\s]+@"; "\(.sch)://***:***@")
    | gsub("AKIA[0-9A-Z]{16}"; "AKIA****************")
    | gsub("(?<p>gh[pousr]_)[A-Za-z0-9]{20,}"; "\(.p)***")
    | gsub("sk-[A-Za-z0-9]{20,}"; "sk-***");
  {
    ts: $ts,
    tool: $tool,
    session: (.session_id // .sessionId // .conversation_id // null),
    cwd: (.cwd // null),
    event: (.hook_event_name // .hookEventName // null),
    tool_name: (.tool_name // .toolName // null),
    tool_use_id: (.tool_use_id // .toolUseId // null),
    input: ((.tool_input // .toolInput //
             (if (.command != null or .file_path != null)
              then {command: .command, file_path: .file_path} else null end))
            | if . == null then null else tojson end),
    response: (if $logresp == "0" then null else ((.tool_response // .toolResponse) | if . == null then null else tojson end) end)
  }
  | .input    |= (if . == null then null else (.[0:2000] | redact) end)
  | .response |= (if . == null then null else (.[0:2000] | redact) end)
' >> "$LOG" 2>/dev/null

exit 0
