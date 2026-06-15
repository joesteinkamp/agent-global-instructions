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
    *)                  echo "$1" >&2; exit 2;;
  esac
}

# --- catastrophic recursive delete -------------------------------------------
# Trip only when an `rm` with a recursive flag targets a catastrophic path as a
# WHOLE token (root, root-glob, home, or parent) — so deeper paths like
# /tmp/build or ./dist are allowed. `rm` may be an absolute path (/bin/rm).
if [[ "$cmd" =~ (^|[^[:alnum:]_])rm[[:space:]] ]] \
   && { [[ "$cmd" =~ [[:space:]]-[[:alnum:]]*[rR][[:alnum:]]* ]] || [[ "$cmd" == *--recursive* ]]; } \
   && [[ "$cmd" =~ (^|[[:space:]])[\"\']?(/|/\*|~|~/|\$HOME|\.\.)[\"\']?([[:space:]]|\;|\&|\||$) ]]; then
  block "BLOCKED: 'rm -r' targeting a root/home/parent path: '$cmd'. Delete a specific subdirectory instead (or use 'trash'). [best-effort guard]"
fi

# --- force push --------------------------------------------------------------
# Allow the safe --force-with-lease; trip on --force, a -f flag, or a +refspec.
if [[ "$cmd" == *push* ]] && [[ "$cmd" != *--force-with-lease* ]]; then
  if [[ "$cmd" == *--force* ]] \
     || [[ "$cmd" =~ [[:space:]]-[[:alnum:]]*f[[:alnum:]]*([[:space:]]|$) ]] \
     || [[ "$cmd" =~ push[[:space:]]([^[:space:]]+[[:space:]]+)*\+[^[:space:]] ]]; then
    block "BLOCKED: force push detected: '$cmd'. Avoid force-pushing; use --force-with-lease if you must. [best-effort guard]"
  fi
fi

exit 0
