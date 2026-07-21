#!/usr/bin/env bash
# Stop hook — emit at most one conservative, non-blocking quality advisory for a
# materially changed code diff. It never auto-continues the agent and never asks
# the agent to run /verify or /improve automatically. Documentation-only and
# artifact-only diffs stay quiet.
#
# Default materiality gate (either threshold qualifies):
#   QUALITY_MIN_FILES=4 code files
#   QUALITY_MIN_LINES=120 changed code lines
# UI guidance is included only when the diff is material, has at least
# QUALITY_UI_MIN_LINES=80 changed code lines, touches UI/route-ish paths, and has
# no fresh verify report. Improve guidance is included at
# IMPROVE_MIN_FILES=8 or IMPROVE_MIN_LINES=200.
#
# State dir: $AI_NUDGE_STATE (default ~/.ai-logs). One advisory per distinct
# diff; `.nudge-skip-quality.<cwd-key>` suppresses and is consumed once.
set -u

PLATFORM="${HOOK_PLATFORM:-claude}"
input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

# Compatibility guard if a host invokes Stop again while handling a prior hook.
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // .stopHookActive // false')"
[ "$active" = "true" ] && exit 0

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"; [ -z "$cwd" ] && cwd="$PWD"
command -v git >/dev/null 2>&1 || exit 0
git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Keep generated evidence and prose-only work from creating quality pressure.
# A project can override this with QUALITY_EXCLUDE_RE.
exclude_re="${QUALITY_EXCLUDE_RE:-(^|/)(docs?|documentation|audits?|artifacts?|verify|screenshots?|reports?)/|(^|/)(README|CHANGELOG|CONTRIBUTING|CODE_OF_CONDUCT|SECURITY)(\.[^/]*)?$|\.(md|markdown|mdown|rst|txt|png|jpe?g|gif|webp|pdf)$}"
ui_re="${QUALITY_UI_RE:-\.(tsx?|jsx?|vue|svelte|astro|css|s[ac]ss|less|html?)$|(^|/)(components?|pages|routes|views|layouts|app|ui|styles?)/}"

# Changed tracked + untracked paths. Newline-bearing filenames are rare and not
# worth making this advisory hook complex enough to risk blocking a turn.
changed="$( { git -C "$cwd" diff --name-only HEAD 2>/dev/null; \
              git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null; } | sort -u )"
[ -z "$changed" ] && exit 0
code_files="$(printf '%s\n' "$changed" | grep -Eiv "$exclude_re" || true)"
[ -z "$code_files" ] && exit 0
files="$(printf '%s\n' "$code_files" | grep -c .)"

# Count tracked diff lines only for non-excluded paths, then add untracked file
# line counts. Binary numstat values are '-' and contribute zero lines.
lines=0
while IFS=$'\t' read -r add del path; do
  [ -n "$path" ] || continue
  printf '%s\n' "$path" | grep -Eiq "$exclude_re" && continue
  case "$add" in ''|-) add=0;; esac
  case "$del" in ''|-) del=0;; esac
  lines=$(( lines + add + del ))
done < <(git -C "$cwd" diff --numstat HEAD 2>/dev/null)
while IFS= read -r path; do
  [ -n "$path" ] || continue
  printf '%s\n' "$path" | grep -Eiq "$exclude_re" && continue
  [ -f "$cwd/$path" ] || continue
  n="$(wc -l < "$cwd/$path" 2>/dev/null | tr -d ' ')"; n="${n:-0}"
  lines=$(( lines + n ))
done < <(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null)

min_files="${QUALITY_MIN_FILES:-4}"
min_lines="${QUALITY_MIN_LINES:-120}"
if [ "$files" -lt "$min_files" ] && [ "$lines" -lt "$min_lines" ]; then exit 0; fi

state_dir="${AI_NUDGE_STATE:-$HOME/.ai-logs}"; mkdir -p "$state_dir" 2>/dev/null || true
key="$(printf '%s' "$cwd" | cksum | cut -d' ' -f1)"
skip="$state_dir/.nudge-skip-quality.$key"
[ -f "$skip" ] && { rm -f "$skip" 2>/dev/null || true; exit 0; }

# Include untracked names + checksums so a changing new file produces a new
# fingerprint even though it is absent from `git diff HEAD`.
fp="$( {
  git -C "$cwd" diff HEAD 2>/dev/null
  while IFS= read -r path; do
    [ -f "$cwd/$path" ] || continue
    printf '%s ' "$path"; cksum "$cwd/$path" 2>/dev/null || true
  done < <(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null)
} | cksum | tr -d ' ')-${files}-${lines}"
marker="$state_dir/.quality-nudge.$key"
[ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$fp" ] && exit 0
printf '%s' "$fp" > "$marker" 2>/dev/null || true

notes=""

# UI evidence is worth mentioning only for a substantial UI diff and only when
# a newer verify report does not already cover every changed UI file.
ui_min_lines="${QUALITY_UI_MIN_LINES:-80}"
ui_files="$(printf '%s\n' "$code_files" | grep -Ei "$ui_re" || true)"
if [ -n "$ui_files" ] && [ "$lines" -ge "$ui_min_lines" ]; then
  report=""
  for r in "$cwd"/verify/*/report.html; do
    [ -e "$r" ] || continue
    if [ -z "$report" ] || [ "$r" -nt "$report" ]; then report="$r"; fi
  done
  stale=1
  if [ -n "$report" ]; then
    stale=0
    while IFS= read -r f; do
      [ -n "$f" ] && [ -e "$cwd/$f" ] && [ "$cwd/$f" -nt "$report" ] && { stale=1; break; }
    done <<EOF
$ui_files
EOF
  fi
  [ "$stale" -eq 1 ] && notes="${notes} A product verification pass may be useful because material UI/route files changed without newer verify evidence."
fi

improve_files="${IMPROVE_MIN_FILES:-8}"
improve_lines="${IMPROVE_MIN_LINES:-200}"
if [ "$files" -ge "$improve_files" ] || [ "$lines" -ge "$improve_lines" ]; then
  notes="${notes} An improvement review may be useful because the code diff is large."
fi

reason="Advisory only: material code change detected (${files} files, ${lines} lines).${notes} The Change Log approval gate may also apply: a draft entry should capture the decision behind the change — the original ask, why this approach, and what was rejected — not just the diff. Do not auto-run \$verify or \$improve and do not continue the turn because of this hook; mention only relevant optional follow-ups in the handoff."

# Claude and Codex accept the common non-blocking Stop output shape. Cursor's stop
# hook injects via followup_message; install-hooks.sh wires loop_limit:1 and we
# honor loop_count so the advisory cannot chain into further auto-continues.
case "$PLATFORM" in
  claude|codex) jq -nc --arg m "$reason" '{continue:true,systemMessage:$m}';;
  cursor)
    loop_count="$(printf '%s' "$input" | jq -r '.loop_count // 0')"
    [ "$loop_count" -gt 0 ] && exit 0
    jq -nc --arg m "$reason" '{followup_message:$m}'
    ;;
  *)            printf '%s\n' "$reason" >&2;;
esac
exit 0
