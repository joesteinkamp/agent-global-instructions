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
#
# Runs inside a hard shutdown deadline. Claude Code aborts the SessionEnd batch
# on `max(1500ms, min(largest declared SessionEnd hook timeout, 60s))`, and an
# abort is user-visible ("Hook cancelled"). install-hooks.sh declares a 10s
# timeout to widen that window; this hook holds up its end by keeping its cost
# flat as the audit log grows (a bounded tail scan, not a full-file grep) and by
# leaving no half-written state if it is killed anyway — the marker it creates
# lands via an atomic rename.
set -u
umask 077

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
[ "${AI_SCORECARD:-1}" = "0" ] && exit 0
[ "${HOOK_PLATFORM:-claude}" = "claude" ] || exit 0

# Parsed field by field on purpose: a single line-oriented read of all three
# would desync if cwd ever contained a newline, and the two saved jq spawns are
# noise against the hook's timeout budget.
sid="$(printf '%s' "$input" | jq -r '.session_id // .sessionId // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
reason="$(printf '%s' "$input" | jq -r '.reason // "other"')"
[ -n "$sid" ] || exit 0
[ "$reason" = "resume" ] && exit 0

LOG="${AI_TOOL_LOG:-$HOME/.ai-logs/tool-calls.jsonl}"
SCDIR="${AI_SCORECARD_DIR:-$(dirname "$LOG")/scorecards}"
ttl="${AI_SCORECARD_TTL:-7200}"
# One date call for both representations the marker and the audit record need.
{ read -r now_epoch; read -r now_iso; } <<EOF
$(date -u +'%s
%Y-%m-%dT%H:%M:%SZ')
EOF

# Housekeeping first so stale markers vanish even when this session is trivial.
for m in "$SCDIR/pending/"*.json; do
  [ -f "$m" ] || continue
  e="$(jq -r '.ended_epoch // 0' "$m" 2>/dev/null)"; e="${e:-0}"
  [ $(( now_epoch - e )) -gt "$ttl" ] && rm -f "$m" 2>/dev/null
done

# Materiality gate: enough audit-log records to be worth the user's 30 seconds.
# Only the tail of the audit log is scanned (AI_SCORECARD_SCAN_BYTES, default
# 8MB): the log grows without bound, and this runs against a shutdown deadline,
# so the cost must not scale with a year of history. The records of the session
# that just ended are the newest ones in the file, so the window only undercounts
# when other sessions logged megabytes since — and an undercount just skips the
# survey. Set AI_SCORECARD_SCAN_BYTES=0 to scan the whole log.
min="${AI_SCORECARD_MIN_EVENTS:-20}"
scan="${AI_SCORECARD_SCAN_BYTES:-8388608}"
if [ "$scan" -gt 0 ] 2>/dev/null; then
  records="$(tail -c "$scan" "$LOG" 2>/dev/null | grep -cF "\"session\":\"$sid\"" || true)"
else
  records="$(grep -cF "\"session\":\"$sid\"" "$LOG" 2>/dev/null || true)"
fi
records="${records:-0}"
[ "$records" -ge "$min" ] || exit 0

# Never re-ask about a session that was already rated or dismissed.
[ -f "$SCDIR/scorecards.jsonl" ] && grep -qF "\"session\":\"$sid\"" "$SCDIR/scorecards.jsonl" 2>/dev/null && exit 0

mkdir -p "$SCDIR/pending" 2>/dev/null || exit 0
chmod 700 "$SCDIR" "$SCDIR/pending" 2>/dev/null || true
marker="$SCDIR/pending/$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '_').json"
[ -f "$marker" ] && exit 0

# Written via a temp file and renamed into place: a shutdown abort partway
# through the write would otherwise leave a truncated marker that every later
# SessionStart tries — and fails — to parse.
tmp="$(mktemp "$SCDIR/pending/.enqueue.XXXXXX" 2>/dev/null)" || exit 0
jq -nc --arg s "$sid" --arg c "$cwd" --arg r "$reason" \
  --argjson e "$now_epoch" --arg ts "$now_iso" --argjson n "$records" \
  '{session:$s, cwd:$c, reason:$r, ended_epoch:$e, ended:$ts, records:$n, offered:0}' \
  > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; exit 0; }
chmod 600 "$tmp" 2>/dev/null || true
mv "$tmp" "$marker" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; exit 0; }

# Audit-trail record (same shape as log-tool.sh, so audit.sh renders it).
jq -nc --arg ts "$now_iso" --arg s "$sid" --arg c "$cwd" \
  --arg d "survey queued ($records records, reason: $reason)" \
  '{ts:$ts, tool:"claude", session:$s, cwd:$c, event:"Scorecard", tool_name:"enqueue",
    tool_use_id:null, input:$d, response:null}' >> "$LOG" 2>/dev/null

exit 0
