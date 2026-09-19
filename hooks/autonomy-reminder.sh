#!/usr/bin/env bash
# SessionStart hook — remind the agent that the host tool has two long-run
# primitives, so ongoing work gets one of them with a done-condition instead of
# a dead-end "next steps" handoff: /goal for a terminal end state (the session
# keeps taking turns until an evaluator judges the condition met) and /loop for
# a recurring check on a cadence. Advisory context only: it never starts
# anything itself, and the rendered instructions carry the full rules (gates
# still apply inside every iteration and every goal turn).
#
# Wired only when the autonomy posture is aggressive (install-hooks.sh asks
# customize.sh --autonomy), and only for Claude + Cursor — the tools whose
# SessionStart can inject context. Codex has no SessionStart hook; it learns
# /goal from the rendered instructions instead. Cursor ships both as well,
# though /goal there is still a gated rollout — hence "if your build has it".
set -u

PLATFORM="${HOOK_PLATFORM:-claude}"
cat > /dev/null   # drain stdin; nothing in the payload changes the message
command -v jq >/dev/null 2>&1 || exit 0
case "$PLATFORM" in claude|cursor) ;; *) exit 0;; esac

ctx='Long-autonomy: this tool has two primitives for work that outlives the turn, and the stopping rule picks between them. Work with a verifiable end state gets `/goal <condition>` — it keeps taking turns until the condition is judged met, so it stops itself rather than on a clock. Work that is only a recurring check gets `/loop` (`/loop <prompt>` self-paces; `/loop 10m <prompt>` fixes the interval; bare `/loop` runs ~/.claude/loop.md) — the tell is the word *every*. Who starts which: `/goal` is a user command you cannot invoke, so write the exact line for the user to paste, with the condition already filled in (state it as something your own output can demonstrate, e.g. `npm test exits 0`); a `/loop` you can start yourself. If the request is ongoing (watch, babysit, keep-green, converge), offer or start the right one with an explicit done-condition instead of ending with next steps, and end it yourself once that condition is met. Confirmation gates apply unchanged inside every iteration and every goal turn.'

if [ "$PLATFORM" = "cursor" ]; then
  jq -nc --arg c "$ctx" '{additional_context:$c}'
else
  jq -nc --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
fi
exit 0
