#!/usr/bin/env bash
# Session scorecard recorder/viewer — a small CLI invoked BY THE AGENT while it
# administers the end-of-session survey (it is copied next to the hooks but is
# not wired to any event). scorecard-enqueue.sh queues a pending marker at
# SessionEnd; scorecard-survey.sh injects the survey ask at the next
# SessionStart; the agent records the user's answers here.
#
#   scorecard.sh record --session <id> --rating 1..5 [--why "..."] [--lesson "..."] [--cwd <dir>]
#   scorecard.sh dismiss --session <id>     # user skipped — drop the marker, no nagging
#   scorecard.sh pending                    # list queued surveys
#   scorecard.sh stats                      # response rate + average rating
#   scorecard.sh path                       # print the scorecards file path
#
# Data: $AI_SCORECARD_DIR (default <log-dir>/scorecards) — scorecards.jsonl plus
# pending/<session>.json markers. A --lesson also lands in the memoryOS lessons
# file (see memory-os.sh), which load-memory.sh reads back at SessionStart —
# that is the feedback loop. Every record/dismiss appends an event:"Scorecard"
# record to the audit log so audit.sh shows it in the timeline.
set -euo pipefail
umask 077

command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=hooks/memory-os.sh
[ -f "$HERE/memory-os.sh" ] && . "$HERE/memory-os.sh"

LOG="${AI_TOOL_LOG:-$HOME/.ai-logs/tool-calls.jsonl}"
SCDIR="${AI_SCORECARD_DIR:-$(dirname "$LOG")/scorecards}"
FILE="$SCDIR/scorecards.jsonl"

audit() {  # $1 = action (record/dismiss), $2 = session, $3 = detail
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || return 0
  jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg s "$2" --arg a "$1" --arg d "$3" \
    '{ts:$ts, tool:"claude", session:$s, cwd:null, event:"Scorecard",
      tool_name:$a, tool_use_id:null, input:$d, response:null}' >> "$LOG" 2>/dev/null || true
}

append_row() {  # $1 = jsonl row
  mkdir -p "$SCDIR" 2>/dev/null
  { flock 9; printf '%s\n' "$1" >&9; } 9>>"$FILE"
}

marker_for() {  # $1 = session id -> sanitized marker path
  printf '%s/pending/%s.json' "$SCDIR" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"
}

mode="${1:-}"; if [ $# -gt 0 ]; then shift; fi
case "$mode" in
  record)
    session="" rating="" why="" lesson="" cwd=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --session) session="${2:-}"; shift 2;;
        --rating)  rating="${2:-}";  shift 2;;
        --why)     why="${2:-}";     shift 2;;
        --lesson)  lesson="${2:-}";  shift 2;;
        --cwd)     cwd="${2:-}";     shift 2;;
        *) echo "unknown arg: $1" >&2; exit 1;;
      esac
    done
    [ -n "$session" ] || { echo "record needs --session" >&2; exit 1; }
    case "$rating" in 1|2|3|4|5) ;; *) echo "record needs --rating 1..5" >&2; exit 1;; esac
    m="$(marker_for "$session")"
    [ -z "$cwd" ] && [ -f "$m" ] && cwd="$(jq -r '.cwd // empty' "$m" 2>/dev/null)"
    append_row "$(jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg s "$session" \
      --arg c "$cwd" --argjson r "$rating" --arg w "$why" --arg l "$lesson" \
      '{ts:$ts, session:$s, cwd:(if $c=="" then null else $c end), rating:$r,
        why:(if $w=="" then null else $w end), lesson:(if $l=="" then null else $l end),
        dismissed:false}')"
    rm -f "$m" 2>/dev/null || true
    if [ -n "$lesson" ] && command -v memoryos_append_lesson >/dev/null 2>&1; then
      memoryos_append_lesson "$lesson" "rated $rating/5 · $(basename "${cwd:-unknown}")"
      echo "Recorded $rating/5; lesson appended to $MEMORYOS_LESSONS"
    else
      echo "Recorded $rating/5"
    fi
    audit record "$session" "survey: rated $rating/5${lesson:+; lesson captured}"
    ;;
  dismiss)
    session=""
    while [ $# -gt 0 ]; do
      case "$1" in --session) session="${2:-}"; shift 2;; *) echo "unknown arg: $1" >&2; exit 1;; esac
    done
    [ -n "$session" ] || { echo "dismiss needs --session" >&2; exit 1; }
    # Record the dismissal so the session is never re-queued or re-asked.
    append_row "$(jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg s "$session" \
      '{ts:$ts, session:$s, dismissed:true}')"
    rm -f "$(marker_for "$session")" 2>/dev/null || true
    audit dismiss "$session" "survey dismissed"
    echo "Survey dismissed."
    ;;
  pending)
    found=0
    for m in "$SCDIR/pending/"*.json; do
      [ -f "$m" ] || continue
      found=1
      jq -r '"\(.session)  ended \(.ended // "?")  \(.cwd // "?")  (\(.records // "?") records, offered \(.offered // 0)x)"' "$m" 2>/dev/null
    done
    [ "$found" = 0 ] && echo "No pending surveys."
    ;;
  stats)
    [ -s "$FILE" ] || { echo "No scorecards yet at $FILE"; exit 0; }
    jq -sr '
      [.[] | select(.dismissed | not)] as $done | [.[] | select(.dismissed)] as $skip |
      "Surveys answered: \($done | length)   dismissed: \($skip | length)",
      (if ($done | length) > 0
       then "Average rating:  \(($done | map(.rating) | add / length * 10 | round / 10))/5"
       else empty end),
      "", "Recent:",
      ($done[-5:][] | "  \(.ts)  \(.rating)/5  \(.why // "-")")
    ' "$FILE"
    ;;
  path) echo "$FILE";;
  *) echo "usage: scorecard.sh record|dismiss|pending|stats|path (see header)" >&2; exit 1;;
esac
