#!/usr/bin/env bash
# SessionStart hook — if the previous session in this directory ended with a
# pending scorecard marker (queued by scorecard-enqueue.sh), inject a short
# survey ask: rating 1-5, why, and what to do differently. The user's answers —
# recorded via hooks/scorecard.sh — are what train the next session, so the ask
# is deliberately effortless to dismiss and disappears on its own:
#   - markers older than AI_SCORECARD_TTL (default 7200s = 2h) are deleted, not offered
#   - a marker is offered at most AI_SCORECARD_MAX_OFFERS times (default 2), then dropped
#   - only markers whose cwd matches this session's cwd are offered
#   - never offered on a `compact` restart (mid-work), and AI_SCORECARD=0 disables all of it
# Claude (hookSpecificOutput.additionalContext) + Cursor (additional_context);
# no-op elsewhere. Never blocks.
set -u
umask 077

PLATFORM="${HOOK_PLATFORM:-claude}"
input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
[ "${AI_SCORECARD:-1}" = "0" ] && exit 0
case "$PLATFORM" in claude|cursor) ;; *) exit 0;; esac

source_ev="$(printf '%s' "$input" | jq -r '.source // empty')"
[ "$source_ev" = "compact" ] && exit 0
cwd="$(printf '%s' "$input" | jq -r '.cwd // .workspace_roots[0]? // empty')"; [ -z "$cwd" ] && cwd="$PWD"

LOG="${AI_TOOL_LOG:-$HOME/.ai-logs/tool-calls.jsonl}"
SCDIR="${AI_SCORECARD_DIR:-$(dirname "$LOG")/scorecards}"
ttl="${AI_SCORECARD_TTL:-7200}"
max_offers="${AI_SCORECARD_MAX_OFFERS:-2}"
now_epoch="$(date +%s)"

best=""; best_epoch=-1
for m in "$SCDIR/pending/"*.json; do
  [ -f "$m" ] || continue
  e="$(jq -r '.ended_epoch // 0' "$m" 2>/dev/null)"; e="${e:-0}"
  if [ $(( now_epoch - e )) -gt "$ttl" ]; then rm -f "$m" 2>/dev/null; continue; fi
  [ "$(jq -r '.cwd // empty' "$m" 2>/dev/null)" = "$cwd" ] || continue
  offered="$(jq -r '.offered // 0' "$m" 2>/dev/null)"; offered="${offered:-0}"
  if [ "$offered" -ge "$max_offers" ]; then rm -f "$m" 2>/dev/null; continue; fi
  if [ "$e" -gt "$best_epoch" ]; then best="$m"; best_epoch="$e"; fi
done
[ -n "$best" ] || exit 0

sid="$(jq -r '.session // empty' "$best" 2>/dev/null)"
ended="$(jq -r '.ended // "?"' "$best" 2>/dev/null)"
reason="$(jq -r '.reason // "?"' "$best" 2>/dev/null)"
records="$(jq -r '.records // "?"' "$best" 2>/dev/null)"
[ -n "$sid" ] || exit 0

# Count this offer so an ignored survey stops appearing after max_offers.
tmp="$(mktemp "$SCDIR/pending/.offer.XXXXXX" 2>/dev/null)" || tmp=""
if [ -n "$tmp" ]; then
  jq '.offered = ((.offered // 0) + 1)' "$best" > "$tmp" 2>/dev/null && mv "$tmp" "$best" || rm -f "$tmp"
fi

rec="$(cd "$(dirname "$0")" && pwd)/scorecard.sh"
ctx="Session survey pending: the previous session in this directory (id \`$sid\`, ended $ended, reason: $reason, $records logged tool events) has not been scored. This feedback trains future sessions.

Before other work, offer the user this 30-second survey (one quick round — a question tool with a first-class \"Skip\" option is ideal, plain conversation is fine):
1. Rate that session 1-5.
2. Why that rating?
3. What should the AI do differently next time? (recorded as a lesson future sessions read)

Then record: \`\"$rec\" record --session $sid --rating N --why \"...\" --lesson \"...\"\` (omit --lesson if none was given).

Dismissal must be effortless: if the user picks Skip, says anything like \"skip\"/\"not now\", or simply starts on their own request, run \`\"$rec\" dismiss --session $sid\`, drop the topic without comment, and proceed with what they asked. Never argue for the survey or re-ask."

if [ "$PLATFORM" = "cursor" ]; then
  jq -nc --arg c "$ctx" '{additional_context:$c}'
else
  jq -nc --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
fi
exit 0
