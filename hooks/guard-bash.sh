#!/usr/bin/env bash
# PreToolUse / BeforeTool guard: trip on clearly catastrophic shell commands.
# Cross-tool (Claude Code, Codex, Antigravity/Gemini) via HOOK_PLATFORM.
#
# BEST-EFFORT TRIPWIRE, NOT A SECURITY BOUNDARY. It only sees the shell tool's
# command string and matches heuristically — obfuscated, variable-expanded, or
# unusual spellings can bypass it. Treat it as a seatbelt against fat-finger
# mistakes, not a sandbox. It deliberately allows routine cleanup like
# `rm -rf node_modules` or `rm -rf dist`.
set -u

PLATFORM="${HOOK_PLATFORM:-claude}"
input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // .tool_input.cmd // .command // empty')"
[ -z "$cmd" ] && exit 0

block() {  # $1 = reason
  case "$PLATFORM" in
    gemini|antigravity) jq -nc --arg r "$1" '{decision:"deny",reason:$r}'; exit 0;;
    cursor)             jq -nc --arg r "$1" '{permission:"deny",user_message:$r,agent_message:$r}'; exit 0;;
    *)                  echo "$1" >&2; exit 2;;
  esac
}

# --- catastrophic recursive delete -------------------------------------------
# Trip only when an `rm` with a recursive flag targets a catastrophic path as a
# WHOLE token (root, root-glob, home, or parent) — so deeper paths like
# /tmp/build or ./dist are allowed. `rm` may be an absolute path (/bin/rm).
#
# Match per COMMAND SEGMENT, not across the whole string: a benign `rm -rf dist`
# chained with an unrelated `&& cd /` must not be read as `rm … /`. Split on the
# shell operators (;, &&, ||, |, &) via bash replacement (portable; GNU/BSD sed
# disagree on \n), then only a segment whose first word is `rm` is eligible.
# `rm` need not be the segment's first word — `sudo rm`, `/usr/bin/rm`, `time rm`,
# `FOO=bar rm` are all catastrophic. Match `rm` as a whole token preceded by start,
# whitespace, or a path prefix (so `confirm`/`xrm` don't trip).
seg_is_catastrophic_rm() {  # $1 = one segment
  local seg="$1"
  [[ "$seg" =~ (^|[[:space:]])([^[:space:]]*/)?rm([[:space:]]|$) ]] || return 1
  { [[ "$seg" =~ [[:space:]]-[[:alnum:]]*[rR][[:alnum:]]* ]] || [[ "$seg" == *--recursive* ]]; } || return 1
  [[ "$seg" =~ (^|[[:space:]])[\"\']?(/|/\*|~|~/|\$HOME|\$HOME/|\.\.)[\"\']?([[:space:]]|$) ]]
}

# Allow the safe --force-with-lease; trip on --force, a -f flag, or a +refspec.
# Evaluated PER SEGMENT (like rm) so a chained `tar -xf …` after a normal push
# isn't misread as a force-push. --force-with-lease excuses only the bare
# `--force` spelling — a `+refspec`/`-f` still forces regardless of the lease.
seg_is_force_push() {  # $1 = one segment
  local seg="$1"
  [[ "$seg" == *push* ]] || return 1
  { [[ "$seg" == *--force* ]] && [[ "$seg" != *--force-with-lease* ]]; } && return 0
  [[ "$seg" =~ (^|[[:space:]])-[[:alnum:]]*f[[:alnum:]]*([[:space:]]|$) ]] && return 0
  [[ "$seg" =~ push[[:space:]]([^[:space:]]+[[:space:]]+)*\+[^[:space:]] ]] && return 0
  return 1
}

_segs="$cmd"
_segs="${_segs//&&/$'\n'}"; _segs="${_segs//||/$'\n'}"
_segs="${_segs//|/$'\n'}";  _segs="${_segs//;/$'\n'}"; _segs="${_segs//&/$'\n'}"
while IFS= read -r _seg; do
  [ -n "$_seg" ] || continue
  seg_is_catastrophic_rm "$_seg" \
    && block "BLOCKED: 'rm -r' targeting a root/home/parent path: '$cmd'. Delete a specific subdirectory instead (or use 'trash'). [best-effort guard]"
  seg_is_force_push "$_seg" \
    && block "BLOCKED: force push detected: '$cmd'. Avoid force-pushing; use --force-with-lease if you must. [best-effort guard]"
done <<< "$_segs"

exit 0
