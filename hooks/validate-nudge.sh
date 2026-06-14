#!/usr/bin/env bash
# Stop hook — when a turn ends with a LARGER change, nudge the agent to run the
# validation review team (/validate) before finishing. Fires once (loop-guarded
# via stop_hook_active). Claude + Codex only (Gemini has no per-turn Stop event).
#
# Thresholds: VALIDATE_MIN_FILES (default 8), VALIDATE_MIN_LINES (default 200).
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

minf="${VALIDATE_MIN_FILES:-8}"; minl="${VALIDATE_MIN_LINES:-200}"
if [ "${files:-0}" -lt "$minf" ] && [ "$lines" -lt "$minl" ]; then exit 0; fi

reason="Larger change detected (${files} files, ${lines} lines vs HEAD). Before finishing, run the validation review team (/validate) to surface improvement opportunities — or tell me you've intentionally skipped it."
case "$PLATFORM" in
  claude) jq -nc --arg r "$reason" '{decision:"block",reason:$r}'; exit 0;;
  *)      echo "$reason" >&2; exit 2;;
esac
