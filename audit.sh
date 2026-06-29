#!/usr/bin/env bash
# Audit the tool-call log written by hooks/log-tool.sh.
#
#   ./audit.sh             # readable timeline of the last 50 events
#   ./audit.sh -n 200      # last 200
#   ./audit.sh --stats     # counts by harness / tool / event
#   ./audit.sh --follow    # live tail
#   ./audit.sh --path      # print the log file path
set -euo pipefail

LOG="${AI_TOOL_LOG:-$HOME/.ai-logs/tool-calls.jsonl}"
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }

N=50; MODE=timeline
while [ $# -gt 0 ]; do
  case "$1" in
    -n) N="${2:-50}"; if [ $# -ge 2 ]; then shift 2; else shift; fi;;
    --stats) MODE=stats; shift;;
    --follow|-f) MODE=follow; shift;;
    --path) echo "$LOG"; exit 0;;
    *) echo "usage: audit.sh [-n N] [--stats] [--follow] [--path]"; exit 1;;
  esac
done

[ -f "$LOG" ] || { echo "No log yet at $LOG"; exit 0; }
# Parse each line tolerantly (`-R` + `fromjson? // empty`): a single truncated or
# interleaved line — possible when many agents append at once — is skipped rather
# than aborting the whole render under `set -e`.
fmt='"\(.ts)  [\(.tool)] \(.event // "?")  \(.tool_name // "?")  \((.input // "")[0:140])"'

case "$MODE" in
  timeline) tail -n "$N" "$LOG" | jq -R -r "fromjson? // empty | $fmt";;
  follow)   tail -n 0 -f "$LOG" | jq -R -r --unbuffered "fromjson? // empty | $fmt";;
  stats)
    echo "Log: $LOG"
    echo "Entries: $(wc -l < "$LOG" | tr -d ' ')"
    echo ""; echo "By harness:"; jq -R -r 'fromjson? // empty | .tool // "?"'      "$LOG" | sort | uniq -c | sort -rn
    echo ""; echo "By tool:";    jq -R -r 'fromjson? // empty | .tool_name // "?"' "$LOG" | sort | uniq -c | sort -rn
    echo ""; echo "By event:";   jq -R -r 'fromjson? // empty | .event // "?"'     "$LOG" | sort | uniq -c | sort -rn;;
esac
