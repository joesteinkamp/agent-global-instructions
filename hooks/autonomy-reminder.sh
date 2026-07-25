#!/usr/bin/env bash
# SessionStart hook — remind the agent that the host tool has a long-run
# primitive (/loop), so ongoing work gets a loop with a done-condition instead
# of a dead-end "next steps" handoff. Advisory context only: it never starts
# anything itself, and the rendered instructions carry the full rules (gates
# still apply inside iterations, etc.).
#
# Wired only when the autonomy posture is aggressive (install-hooks.sh asks
# customize.sh --autonomy), and only for Claude + Cursor — the tools whose
# SessionStart can inject context and whose CLIs ship /loop. Codex has no
# SessionStart hook; it learns /goal from the rendered instructions instead.
set -u

PLATFORM="${HOOK_PLATFORM:-claude}"
cat > /dev/null   # drain stdin; nothing in the payload changes the message
command -v jq >/dev/null 2>&1 || exit 0
case "$PLATFORM" in claude|cursor) ;; *) exit 0;; esac

ctx='Long-autonomy: this tool supports `/loop` (`/loop <prompt>` self-paces; `/loop 10m <prompt>` fixes the interval; bare `/loop` runs ~/.claude/loop.md). If the request is ongoing (watch, babysit, keep-green, converge) or the work will outlive this turn, offer or start a loop with an explicit done-condition instead of ending with next steps — and stop it yourself once that condition is met. Confirmation gates apply unchanged inside every iteration.'

if [ "$PLATFORM" = "cursor" ]; then
  jq -nc --arg c "$ctx" '{additional_context:$c}'
else
  jq -nc --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
fi
exit 0
