#!/usr/bin/env bash
# PreCompact hook — fires right before Claude compacts the context (which
# silently drops detail). The platform does NOT let a PreCompact hook inject
# context or curate memory, so this does the one thing it can: preserve the RAW
# transcript on disk before it's compacted away, and drop a marker in the audit
# log. Never blocks compaction (always exits 0).
#
# Model-curated "write durable facts back" still comes from the instructions +
# the SessionStart memory loader; this is the safety net that guarantees the full
# pre-compaction record survives so nothing is ever truly lost.
#
# SENSITIVE: the archived transcript is the RAW, UNREDACTED conversation (unlike
# log-tool.sh, which redacts) — it can hold secrets and tool I/O. It's written
# 0600 in a 0700 dir, and the archive is capped to the newest AI_TRANSCRIPT_KEEP
# (default 50). Treat the dir as private.
#
# Archive dir: <audit-log-dir>/transcripts/. Audit log: $AI_TOOL_LOG
# (default ~/.ai-logs/tool-calls.jsonl) — same record shape as log-tool.sh, so
# ./audit.sh shows these events for free. Claude only (others have no PreCompact).
set -u
umask 077

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
platform="${HOOK_PLATFORM:-claude}"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fts="$(date -u +%Y%m%dT%H%M%SZ)"

LOG="${AI_TOOL_LOG:-$HOME/.ai-logs/tool-calls.jsonl}"
ARCHIVE_DIR="$(dirname "$LOG")/transcripts"
mkdir -p "$ARCHIVE_DIR" 2>/dev/null || exit 0
chmod 700 "$(dirname "$LOG")" 2>/dev/null || true
chmod 700 "$ARCHIVE_DIR" 2>/dev/null || true

tp="$(printf '%s' "$input"  | jq -r '.transcript_path // .transcriptPath // empty' 2>/dev/null)"
sid="$(printf '%s' "$input" | jq -r '.session_id // .sessionId // "nosession"'      2>/dev/null)"
trig="$(printf '%s' "$input" | jq -r '.trigger // .matcher // "compact"'            2>/dev/null)"
# Never let an odd/hostile session id escape the archive dir (e.g. a '/' or '..').
sid="$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '_')"

# Archive the transcript if we were handed a readable path.
dest=""
if [ -n "$tp" ] && [ -f "$tp" ]; then
  dest="$ARCHIVE_DIR/${sid}-${fts}-precompact.jsonl"
  if cp "$tp" "$dest" 2>/dev/null; then chmod 600 "$dest" 2>/dev/null || true; else dest=""; fi
  # Cap growth: keep only the newest AI_TRANSCRIPT_KEEP (default 50) archives.
  keep="${AI_TRANSCRIPT_KEEP:-50}"; n=0
  while IFS= read -r f; do n=$((n+1)); [ "$n" -gt "$keep" ] && rm -f -- "$f"; done \
    < <(ls -1t -- "$ARCHIVE_DIR"/*-precompact.jsonl 2>/dev/null)
fi

# Append an audit marker shaped like log-tool.sh's records so audit.sh renders it.
[ -e "$LOG" ] || : > "$LOG" 2>/dev/null || true
chmod 600 "$LOG" 2>/dev/null || true
printf '%s' "$input" | jq -c --arg tool "$platform" --arg ts "$ts" --arg trig "$trig" --arg dest "$dest" '
  {ts:$ts, tool:$tool, session:(.session_id // .sessionId // .conversation_id // null),
   cwd:(.cwd // null), event:"PreCompact", tool_name:$trig, tool_use_id:null,
   input:(if $dest=="" then "transcript not archived" else "archived -> " + $dest end),
   response:null}' >> "$LOG" 2>/dev/null

exit 0
