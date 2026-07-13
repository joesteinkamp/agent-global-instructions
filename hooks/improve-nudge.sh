#!/usr/bin/env bash
# Stop hook — when a turn ends with a LARGER change, nudge the agent to run the
# improvement review before finishing. Claude, Codex, and Cursor (each in its own
# Stop dialect); Gemini has no per-turn Stop event.
#
# Fires at most once per distinct diff: the diff fingerprint of the last nudge
# is remembered, so it does NOT re-fire every turn (incl. pure conversation)
# while a large uncommitted diff sits there. It nudges again only once the diff
# materially changes. (stop_hook_active still guards the same-turn continuation.)
#
# Thresholds: IMPROVE_MIN_FILES (default 8), IMPROVE_MIN_LINES (default 200).
# State dir: $AI_NUDGE_STATE (default ~/.ai-logs).
set -u

PLATFORM="${HOOK_PLATFORM:-claude}"
input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

# Loop guard: don't nudge again on the continuation we just caused.
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // .stopHookActive // false')"
[ "$active" = "true" ] && exit 0

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"; [ -z "$cwd" ] && cwd="$PWD"
command -v git >/dev/null 2>&1 || exit 0
git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

files="$(git -C "$cwd" status --porcelain 2>/dev/null | grep -c .)"
stat="$(git -C "$cwd" diff --shortstat HEAD 2>/dev/null)"
ins="$(printf '%s' "$stat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || true)"; ins="${ins:-0}"
del="$(printf '%s' "$stat" | grep -oE '[0-9]+ deletion'  | grep -oE '[0-9]+' || true)"; del="${del:-0}"
lines=$(( ins + del ))

minf="${IMPROVE_MIN_FILES:-8}"; minl="${IMPROVE_MIN_LINES:-200}"
if [ "${files:-0}" -lt "$minf" ] && [ "$lines" -lt "$minl" ]; then exit 0; fi

# De-dupe across turns: fingerprint the actual diff content (falls back to
# counts). If we already nudged for this exact diff, stay quiet until it changes.
fp="$(git -C "$cwd" diff HEAD 2>/dev/null | cksum | tr -d ' ')-${files}-${lines}"
state_dir="${AI_NUDGE_STATE:-$HOME/.ai-logs}"; mkdir -p "$state_dir" 2>/dev/null || true
key="$(printf '%s' "$cwd" | cksum | cut -d' ' -f1)"
marker="$state_dir/.improve-nudge.$key"
[ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$fp" ] && exit 0
printf '%s' "$fp" > "$marker" 2>/dev/null || true

# Codex invokes the ported workflow as a skill, not a slash command.
case "$PLATFORM" in codex) nudgecmd='$improve';; *) nudgecmd="/improve";; esac
reason="Larger change detected (${files} files, ${lines} lines vs HEAD). Before finishing, run the improvement review (${nudgecmd}) to surface improvement opportunities — or tell me you've intentionally skipped it."
case "$PLATFORM" in
  claude) jq -nc --arg r "$reason" '{decision:"block",reason:$r}'; exit 0;;
  cursor) jq -nc --arg r "$reason" '{followup_message:$r}'; exit 0;;
  *)      echo "$reason" >&2; exit 2;;
esac
