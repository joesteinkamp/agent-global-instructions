#!/usr/bin/env bash
# SessionEnd hook — queue the just-ended session for a scorecard survey. The
# platform ignores SessionEnd output entirely, so this hook can only leave a
# pending marker on disk; scorecard-survey.sh offers the survey at the next
# SessionStart, and hooks/scorecard.sh records the answers.
#
# Only non-trivial sessions qualify (>= AI_SCORECARD_MIN_EVENTS audit-log
# records, default 20 ≈ 10 tool calls) and never `resume` ends (the session
# continues elsewhere). Already-answered or already-dismissed sessions are not
# re-queued. Markers expire after AI_SCORECARD_TTL seconds (default 7200 = 2h):
# a survey about a session you left hours ago is noise, not signal. Disable the
# whole survey loop with AI_SCORECARD=0. Claude only (the one platform with
# SessionEnd). Never blocks.
set -u
umask 077

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
[ "${AI_SCORECARD:-1}" = "0" ] && exit 0
[ "${HOOK_PLATFORM:-claude}" = "claude" ] || exit 0

sid="$(printf '%s' "$input" | jq -r '.session_id // .sessionId // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
reason="$(printf '%s' "$input" | jq -r '.reason // "other"')"
[ -n "$sid" ] || exit 0
[ "$reason" = "resume" ] && exit 0

LOG="${AI_TOOL_LOG:-$HOME/.ai-logs/tool-calls.jsonl}"
SCDIR="${AI_SCORECARD_DIR:-$(dirname "$LOG")/scorecards}"
ttl="${AI_SCORECARD_TTL:-7200}"
now_epoch="$(date +%s)"

# Housekeeping first so stale markers vanish even when this session is trivial.
for m in "$SCDIR/pending/"*.json; do
  [ -f "$m" ] || continue
  e="$(jq -r '.ended_epoch // 0' "$m" 2>/dev/null)"; e="${e:-0}"
  [ $(( now_epoch - e )) -gt "$ttl" ] && rm -f "$m" 2>/dev/null
done

# Materiality gate: enough audit-log records to be worth the user's 30 seconds.
min="${AI_SCORECARD_MIN_EVENTS:-20}"
records="$(grep -cF "\"session\":\"$sid\"" "$LOG" 2>/dev/null || true)"; records="${records:-0}"
[ "$records" -ge "$min" ] || exit 0

# Never re-ask about a session that was already rated or dismissed.
[ -f "$SCDIR/scorecards.jsonl" ] && grep -qF "\"session\":\"$sid\"" "$SCDIR/scorecards.jsonl" 2>/dev/null && exit 0

mkdir -p "$SCDIR/pending" 2>/dev/null || exit 0
chmod 700 "$SCDIR" "$SCDIR/pending" 2>/dev/null || true
marker="$SCDIR/pending/$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '_').json"
[ -f "$marker" ] && exit 0

jq -nc --arg s "$sid" --arg c "$cwd" --arg r "$reason" \
  --argjson e "$now_epoch" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson n "$records" \
  '{session:$s, cwd:$c, reason:$r, ended_epoch:$e, ended:$ts, records:$n, offered:0}' \
  > "$marker" 2>/dev/null || exit 0
chmod 600 "$marker" 2>/dev/null || true

# Audit-trail record (same shape as log-tool.sh, so audit.sh renders it).
jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg s "$sid" --arg c "$cwd" \
  --arg d "survey queued ($records records, reason: $reason)" \
  '{ts:$ts, tool:"claude", session:$s, cwd:$c, event:"Scorecard", tool_name:"enqueue",
    tool_use_id:null, input:$d, response:null}' >> "$LOG" 2>/dev/null

exit 0
