#!/usr/bin/env bash
# Sourced library (not an event hook) — resolves where this machine's "memoryOS"
# lives and appends session-survey lessons to it. The registry is a small
# KEY=VALUE file at ~/.ai/memory-os written by setup-memory-os.sh; when absent,
# detection falls back to Hermes (~/.hermes) and finally a plain markdown store
# at ~/.ai-memory. Lessons always land in a file WE own (LESSONS.md) — never
# appended into a store's own curated files (e.g. Hermes memories/MEMORY.md),
# so its writer/lock conventions are left alone.
#
# Exposes after memoryos_load:
#   MEMORYOS_TYPE     hermes | markdown | obsidian | notion
#   MEMORYOS_PATH     store root
#   MEMORYOS_LESSONS  the lessons file lessons append to / are read from
#
# Override the registry path with AI_MEMORYOS_CONFIG (tests do).

memoryos_load() {
  MEMORYOS_TYPE=""; MEMORYOS_PATH=""; MEMORYOS_LESSONS=""
  local cfg="${AI_MEMORYOS_CONFIG:-$HOME/.ai/memory-os}"
  if [ -f "$cfg" ]; then
    MEMORYOS_TYPE="$(sed -n 's/^MEMORYOS_TYPE=//p' "$cfg" | head -1)"
    MEMORYOS_PATH="$(sed -n 's/^MEMORYOS_PATH=//p' "$cfg" | head -1)"
  fi
  # Detection fallback when the registry is missing or incomplete.
  if [ -z "$MEMORYOS_TYPE" ] || [ -z "$MEMORYOS_PATH" ]; then
    if [ -d "$HOME/.hermes" ]; then
      MEMORYOS_TYPE="hermes"; MEMORYOS_PATH="$HOME/.hermes"
    else
      MEMORYOS_TYPE="markdown"; MEMORYOS_PATH="$HOME/.ai-memory"
    fi
  fi
  case "$MEMORYOS_PATH" in "~/"*) MEMORYOS_PATH="$HOME/${MEMORYOS_PATH#\~/}";; esac
  case "$MEMORYOS_TYPE" in
    hermes) MEMORYOS_LESSONS="$MEMORYOS_PATH/memories/LESSONS.md";;
    *)      MEMORYOS_LESSONS="$MEMORYOS_PATH/LESSONS.md";;
  esac
  return 0
}

# memoryos_append_lesson <text> [meta]  — one line per lesson, newest last, so
# readers can `tail` the most recent. Appends under flock for parallel agents.
memoryos_append_lesson() {
  local text="${1:-}" meta="${2:-}"
  [ -n "$text" ] || return 0
  memoryos_load
  mkdir -p "$(dirname "$MEMORYOS_LESSONS")" 2>/dev/null || return 0
  if [ ! -f "$MEMORYOS_LESSONS" ]; then
    printf '# Session lessons\n\nAppended by the session scorecard survey (agent-global-instructions).\nOne line per lesson; newest last. Safe to curate by hand — the survey only appends.\n\n' \
      > "$MEMORYOS_LESSONS" 2>/dev/null || return 0
  fi
  {
    flock 9
    printf -- '- %s · %s — %s\n' "$(date +%F)" "${meta:-session survey}" "$text" >&9
  } 9>>"$MEMORYOS_LESSONS" 2>/dev/null || true
  return 0
}
