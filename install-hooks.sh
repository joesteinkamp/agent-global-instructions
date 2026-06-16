#!/usr/bin/env bash
# Install the guardrail hooks into one or more AI tools. Each tool gets the
# hook scripts copied into its own dir and its config merged (idempotent, with a
# timestamped backup). The same scripts serve all tools — HOOK_PLATFORM (set in
# the wired command) makes them block in each tool's dialect.
#
#   ./install-hooks.sh             # all detected tools
#   ./install-hooks.sh claude      # just Claude Code
#   ./install-hooks.sh codex gemini
#
# Tools: claude (~/.claude/settings.json) · codex (~/.codex/hooks.json) ·
#        gemini / antigravity (~/.gemini/settings.json)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/hooks"
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }

# Single source of truth for the hook scripts. Drives the copy loop AND the jq
# idempotency filter, so they can't drift. HOOK_RE matches /<our-script>.sh
# (anchored on the dir slash so it won't match an unrelated user hook that just
# mentions the bare name; not end-anchored since wired commands end in .sh").
HOOK_SCRIPTS=(guard-paths guard-bash format-edited log-tool improve-nudge)
HOOK_RE="/($(IFS='|'; echo "${HOOK_SCRIPTS[*]}"))\\.sh"

# Clean up any temp file left behind if jq fails or we're interrupted.
TMPFILES=()
trap '[ ${#TMPFILES[@]} -gt 0 ] && rm -f "${TMPFILES[@]}" || true' EXIT

# Back up a file to a collision-free name, keeping only the 5 newest backups.
backup_file() {  # $1 = file to back up — uses the same .bak. suffix as the other scripts
  cp "$1" "$(mktemp "$1.bak.XXXXXX")"
  local n=0 b
  while IFS= read -r b; do n=$((n+1)); if [ "$n" -gt 5 ]; then rm -f -- "$b"; fi; done \
    < <(ls -1t -- "$1".bak.* 2>/dev/null)
  return 0   # prune's last test is usually false; don't let the fn return 1 under set -e
}

copy_scripts() {  # $1 = hooks dir
  mkdir -p "$1"
  local s
  for s in "${HOOK_SCRIPTS[@]}"; do
    # Back up a hand-edited hook script before replacing it with the canonical one.
    if [ -f "$1/$s.sh" ] && ! cmp -s "$SRC/$s.sh" "$1/$s.sh"; then
      cp "$1/$s.sh" "$(mktemp "$1/$s.sh.bak.XXXXXX")"
      echo "  backed up your edited $s.sh"
    fi
    cp "$SRC/$s.sh" "$1/$s.sh"; chmod +x "$1/$s.sh"
  done
}

# Merge a hooks object ($2) into a JSON settings file ($1), replacing any of our
# previously-installed entries so re-runs don't duplicate.
merge_json() {  # $1 = settings file, $2 = hooks object json
  local f="$1" add="$2" tmp
  [ -f "$f" ] || echo '{}' > "$f"
  tmp="$(mktemp)"; TMPFILES+=("$tmp")
  jq --argjson add "$add" --arg pat "$HOOK_RE" '
    .hooks = (.hooks // {})
    | .hooks |= with_entries(.value |= map(select(
        ((.hooks // []) | map(.command) | any(test($pat)))  | not
      )))
    | reduce ($add | to_entries[]) as $e (.;
        .hooks[$e.key] = ((.hooks[$e.key] // []) + $e.value))
  ' "$f" > "$tmp" || { echo "  merge failed for $f (left unchanged)" >&2; return 1; }
  if cmp -s "$tmp" "$f"; then return 0; fi          # no change: no write, no backup
  backup_file "$f"; mv "$tmp" "$f"
}

cmd() { printf 'env HOOK_PLATFORM=%s "%s/%s.sh"' "$1" "$2" "$3"; }  # platform, hookdir, script

install_claude() {
  local hd="$HOME/.claude/hooks" sf="$HOME/.claude/settings.json"
  copy_scripts "$hd"
  merge_json "$sf" "$(jq -n --arg gp "$(cmd claude "$hd" guard-paths)" --arg gb "$(cmd claude "$hd" guard-bash)" --arg fm "$(cmd claude "$hd" format-edited)" --arg lg "$(cmd claude "$hd" log-tool)" --arg vn "$(cmd claude "$hd" improve-nudge)" '{
    PreToolUse: [
      {matcher:"*", hooks:[{type:"command",command:$lg}]},
      {matcher:"Edit|Write|MultiEdit|NotebookEdit", hooks:[{type:"command",command:$gp}]},
      {matcher:"Bash", hooks:[{type:"command",command:$gb}]}
    ],
    PostToolUse: [
      {matcher:"*", hooks:[{type:"command",command:$lg}]},
      {matcher:"Edit|Write|MultiEdit", hooks:[{type:"command",command:$fm}]}
    ],
    Stop: [ {hooks:[{type:"command",command:$vn}]} ]
  }')"
  echo "  claude  -> $sf (log, auto-format, guard paths, guard bash, improve-nudge)"
}

install_codex() {
  local hd="$HOME/.codex/hooks" sf="$HOME/.codex/hooks.json"
  copy_scripts "$hd"
  # Codex currently surfaces only the Bash tool to hooks, so wire the shell guard + logging.
  merge_json "$sf" "$(jq -n --arg gb "$(cmd codex "$hd" guard-bash)" --arg lg "$(cmd codex "$hd" log-tool)" --arg vn "$(cmd codex "$hd" improve-nudge)" '{
    PreToolUse: [
      {matcher:".*", hooks:[{type:"command",command:$lg,timeout:30}]},
      {matcher:"Bash", hooks:[{type:"command",command:$gb,timeout:30}]}
    ],
    PostToolUse: [ {matcher:".*", hooks:[{type:"command",command:$lg,timeout:30}]} ],
    Stop: [ {hooks:[{type:"command",command:$vn,timeout:30}]} ]
  }')"
  echo "  codex   -> $sf (log, guard bash, improve-nudge; path-guard/format pending Codex edit-tool hooks)"
}

install_gemini() {
  local hd="$HOME/.gemini/hooks" sf="$HOME/.gemini/settings.json"
  copy_scripts "$hd"
  merge_json "$sf" "$(jq -n --arg gp "$(cmd gemini "$hd" guard-paths)" --arg gb "$(cmd gemini "$hd" guard-bash)" --arg fm "$(cmd gemini "$hd" format-edited)" --arg lg "$(cmd gemini "$hd" log-tool)" '{
    BeforeTool: [
      {matcher:".*", hooks:[{type:"command",command:$lg}]},
      {matcher:"run_shell_command", hooks:[{type:"command",command:$gb}]},
      {matcher:"write_file|replace", hooks:[{type:"command",command:$gp}]}
    ],
    AfterTool: [
      {matcher:".*", hooks:[{type:"command",command:$lg}]},
      {matcher:"write_file|replace", hooks:[{type:"command",command:$fm}]}
    ]
  }')"
  echo "  gemini  -> $sf (log, auto-format, guard paths, guard bash) — also used by Antigravity"
}

targets=("$@"); [ ${#targets[@]} -eq 0 ] && targets=(claude codex gemini)
for t in "${targets[@]}"; do
  case "$t" in
    claude)             install_claude;;
    codex)              install_codex;;
    gemini|antigravity) install_gemini;;
    *) echo "  unknown target: $t (use: claude codex gemini)" >&2;;
  esac
done
echo "Done. Backups saved next to each settings file."
