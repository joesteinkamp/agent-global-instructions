#!/usr/bin/env bash
# Stop hook — when a session ends with code changes, remind the agent to PROPOSE
# a Change Log entry (what changed + why) and get the human's approval before
# writing it. It only nudges: the model still asks, so the human-approval gate is
# preserved — never auto-write or auto-commit the changelog. Claude, Codex, and
# Cursor (each Stop dialect); Gemini has no per-turn Stop event.
#
# Fires once per distinct diff (fingerprint remembered), so it doesn't re-nudge
# every turn while the same uncommitted diff sits there. Caveat: it sees the
# working tree vs HEAD, so changes already committed/pushed this session won't
# trip it — the saved memory + model behavior cover that case.
#
# Threshold: CHANGELOG_MIN_FILES changed/untracked files (default 1 — any change).
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
minf="${CHANGELOG_MIN_FILES:-1}"
[ "${files:-0}" -lt "$minf" ] && exit 0

# De-dupe across turns: fingerprint the diff; nudge once until it changes.
fp="$(git -C "$cwd" diff HEAD 2>/dev/null | cksum | tr -d ' ')-${files}"
state_dir="${AI_NUDGE_STATE:-$HOME/.ai-logs}"; mkdir -p "$state_dir" 2>/dev/null || true
key="$(printf '%s' "$cwd" | cksum | cut -d' ' -f1)"
marker="$state_dir/.changelog-nudge.$key"
[ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$fp" ] && exit 0
printf '%s' "$fp" > "$marker" 2>/dev/null || true

reason="This session changed ${files} file(s). Before finishing, PROPOSE a Change Log entry (what changed + why) and ask me to approve or edit it before writing — do not write or commit the changelog without my approval."
case "$PLATFORM" in
  claude) jq -nc --arg r "$reason" '{decision:"block",reason:$r}'; exit 0;;
  cursor) jq -nc --arg r "$reason" '{followup_message:$r}'; exit 0;;
  *)      echo "$reason" >&2; exit 2;;
esac
