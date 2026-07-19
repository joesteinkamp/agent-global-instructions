#!/usr/bin/env bash
# Stop hook — when a turn ends with a UI/route change that hasn't been verified,
# nudge the agent to run /verify (prove it renders + matches the design/briefs)
# before finishing. Claude, Codex, and Cursor (each in its own Stop dialect);
# Gemini has no per-turn Stop event.
#
# Complements improve-nudge: improve-nudge fires on diff SIZE (is it worth a
# review?); verify-nudge fires on diff KIND (did UI change, and is there evidence
# it works?). On a big UI change both may fire — that's intended: verify it, then
# review it. verify-nudge stays quiet once a verify/<slug>/report.html exists that
# is newer than every changed UI file (i.e. you already verified this work).
#
# Gate: at least one changed/untracked file matches the UI pattern (override with
# VERIFY_UI_RE) AND no fresh report. Fires at most once per distinct diff.
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

# Changed (vs HEAD) + untracked files, filtered to UI/route-ish paths.
ui_re="${VERIFY_UI_RE:-\.(tsx?|jsx?|vue|svelte|astro|css|s[ac]ss|less|html?|mdx)\$|(^|/)(components?|pages|routes|views|layouts|app|ui|styles?)/}"
changed="$( { git -C "$cwd" diff --name-only HEAD 2>/dev/null; \
              git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null; } | sort -u )"
ui_files="$(printf '%s\n' "$changed" | grep -Ei "$ui_re" || true)"
[ -z "$ui_files" ] && exit 0
nfiles="$(printf '%s\n' "$ui_files" | grep -c .)"

# Already verified? A report newer than every changed UI file means this work was
# verified after it was written — stay quiet. Pick the newest report by mtime
# (glob loop, not `ls`, to stay shellcheck-clean and handle odd names).
report=""
for r in "$cwd"/verify/*/report.html; do
  [ -e "$r" ] || continue
  if [ -z "$report" ] || [ "$r" -nt "$report" ]; then report="$r"; fi
done
if [ -n "$report" ]; then
  stale=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -e "$cwd/$f" ] && [ "$cwd/$f" -nt "$report" ] && { stale=1; break; }
  done <<EOF
$ui_files
EOF
  [ "$stale" -eq 0 ] && exit 0
fi

# De-dupe across turns: fingerprint the diff + the UI file set. If we already
# nudged for this exact state, stay quiet until it changes.
fp="$(git -C "$cwd" diff HEAD 2>/dev/null | cksum | tr -d ' ')-$(printf '%s' "$ui_files" | cksum | tr -d ' ')"
state_dir="${AI_NUDGE_STATE:-$HOME/.ai-logs}"; mkdir -p "$state_dir" 2>/dev/null || true
key="$(printf '%s' "$cwd" | cksum | cut -d' ' -f1)"
# Suppression: the agent drops this marker when applying changes I already
# approved (a prior review's fixes), so the backstop doesn't re-nag. Consume-once.
skip="$state_dir/.nudge-skip-verify.$key"
[ -f "$skip" ] && { rm -f "$skip" 2>/dev/null || true; exit 0; }
marker="$state_dir/.verify-nudge.$key"
[ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$fp" ] && exit 0
printf '%s' "$fp" > "$marker" 2>/dev/null || true

# Codex invokes the ported workflow as a skill, not a slash command.
case "$PLATFORM" in codex) nudgecmd='$verify';; *) nudgecmd="/verify";; esac
reason="UI/route change detected (${nfiles} file(s)) with no fresh verify report. Before finishing, run ${nudgecmd} to prove it renders and matches the design/briefs — or tell me you've intentionally skipped it."
case "$PLATFORM" in
  claude) jq -nc --arg r "$reason" '{decision:"block",reason:$r}'; exit 0;;
  cursor) jq -nc --arg r "$reason" '{followup_message:$r}'; exit 0;;
  *)      echo "$reason" >&2; exit 2;;
esac
