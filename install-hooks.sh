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
#        cursor (~/.cursor/hooks.json) · gemini (~/.gemini/settings.json) ·
#        antigravity (~/.gemini/antigravity-cli/hooks.json — a SEPARATE tool from
#        the Gemini CLI, with its own hooks schema; opt-in, not in the default set)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/hooks"
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }

# Single source of truth for the hook scripts. Drives the copy loop AND the jq
# idempotency filter, so they can't drift. HOOK_RE matches /<our-script>.sh
# (anchored on the dir slash so it won't match an unrelated user hook that just
# mentions the bare name; not end-anchored since wired commands end in .sh").
HOOK_SCRIPTS=(guard-paths guard-bash format-edited log-tool improve-nudge verify-nudge changelog-nudge load-memory precompact-archive log-session-end)
HOOK_RE="/($(IFS='|'; echo "${HOOK_SCRIPTS[*]}"))\\.sh"

# Clean up any temp file left behind if jq fails or we're interrupted.
TMPFILES=()
trap '[ ${#TMPFILES[@]} -gt 0 ] && rm -f "${TMPFILES[@]}" || true' EXIT

# Back up a file to a collision-free name, keeping only the 5 newest backups.
backup_file() {  # $1 = file to back up — uses the same .bak. suffix as the other scripts
  # Skip a file we just seeded empty this run (nothing to preserve) so first
  # installs don't litter a *.bak of `{}` / `{"version":1}`.
  case "$(tr -d ' \n\t' < "$1" 2>/dev/null)" in ''|'{}'|'{"version":1}') return 0;; esac
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
  tmp="$(mktemp "$(dirname "$f")/.aigi.XXXXXX")"; TMPFILES+=("$tmp")  # same-dir: atomic mv + valid BSD template
  jq --argjson add "$add" --arg pat "$HOOK_RE" '
    .hooks = (.hooks // {})
    # Drop any of our prior entries so re-runs do not duplicate. Handle BOTH
    # shapes: Claude/Codex/Gemini nest commands under .hooks[]; Cursor uses a
    # flat { "command": ... } per entry.
    | .hooks |= with_entries(.value |= map(select(
        ([ .command ] + ((.hooks // []) | map(.command))
         | map(select(. != null)) | any(test($pat))) | not
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
  merge_json "$sf" "$(jq -n --arg gp "$(cmd claude "$hd" guard-paths)" --arg gb "$(cmd claude "$hd" guard-bash)" --arg fm "$(cmd claude "$hd" format-edited)" --arg lg "$(cmd claude "$hd" log-tool)" --arg vn "$(cmd claude "$hd" improve-nudge)" --arg vfn "$(cmd claude "$hd" verify-nudge)" --arg cn "$(cmd claude "$hd" changelog-nudge)" --arg lm "$(cmd claude "$hd" load-memory)" --arg pc "$(cmd claude "$hd" precompact-archive)" --arg se "$(cmd claude "$hd" log-session-end)" '{
    SessionStart: [ {matcher:"startup|resume|clear|compact", hooks:[{type:"command",command:$lm}]} ],
    PreToolUse: [
      {matcher:"*", hooks:[{type:"command",command:$lg}]},
      {matcher:"Edit|Write|MultiEdit|NotebookEdit", hooks:[{type:"command",command:$gp}]},
      {matcher:"Bash", hooks:[{type:"command",command:$gb}]}
    ],
    PostToolUse: [
      {matcher:"*", hooks:[{type:"command",command:$lg}]},
      {matcher:"Edit|Write|MultiEdit", hooks:[{type:"command",command:$fm}]}
    ],
    PreCompact: [ {matcher:"manual|auto", hooks:[{type:"command",command:$pc}]} ],
    Stop: [ {hooks:[{type:"command",command:$vfn},{type:"command",command:$vn},{type:"command",command:$cn}]} ],
    SessionEnd: [ {matcher:"clear|logout|prompt_input_exit|resume|other", hooks:[{type:"command",command:$se}]} ]
  }')"
  echo "  claude  -> $sf (memory-load, log, auto-format, guard paths, guard bash, improve-nudge, verify-nudge, changelog-nudge, precompact-archive, session-end)"
}

install_codex() {
  local hd="$HOME/.codex/hooks" sf="$HOME/.codex/hooks.json"
  copy_scripts "$hd"
  # Codex now surfaces file edits to hooks via the apply_patch tool (matched as
  # apply_patch, with Write/Edit aliases), so path-guard + auto-format wire up
  # alongside the shell guard and logging. guard-paths/format-edited extract the
  # edited paths from the apply_patch envelope (tool_input.command).
  merge_json "$sf" "$(jq -n \
    --arg gp "$(cmd codex "$hd" guard-paths)" \
    --arg gb "$(cmd codex "$hd" guard-bash)" \
    --arg fm "$(cmd codex "$hd" format-edited)" \
    --arg lg "$(cmd codex "$hd" log-tool)" \
    --arg vn "$(cmd codex "$hd" improve-nudge)" \
    --arg vfn "$(cmd codex "$hd" verify-nudge)" \
    --arg cn "$(cmd codex "$hd" changelog-nudge)" '{
    PreToolUse: [
      {matcher:".*", hooks:[{type:"command",command:$lg,timeout:30}]},
      {matcher:"apply_patch|Edit|Write", hooks:[{type:"command",command:$gp,timeout:30}]},
      {matcher:"Bash", hooks:[{type:"command",command:$gb,timeout:30}]}
    ],
    PostToolUse: [
      {matcher:".*", hooks:[{type:"command",command:$lg,timeout:30}]},
      {matcher:"apply_patch|Edit|Write", hooks:[{type:"command",command:$fm,timeout:30}]}
    ],
    Stop: [ {hooks:[{type:"command",command:$vfn,timeout:30},{type:"command",command:$vn,timeout:30},{type:"command",command:$cn,timeout:30}]} ]
  }')"
  echo "  codex   -> $sf (log, guard paths, guard bash, auto-format, improve-nudge, verify-nudge, changelog-nudge)"
}

install_cursor() {
  local hd="$HOME/.cursor/hooks" sf="$HOME/.cursor/hooks.json"
  copy_scripts "$hd"
  # Cursor's hooks.json needs a top-level "version": 1 and uses flat
  # { "command": ... } entries (no per-entry "hooks" array). merge_json only
  # touches .hooks, so set version separately first (idempotent, no backup —
  # merge_json backs up before it changes .hooks). Cursor has no blocking
  # pre-edit event (only afterFileEdit, which can't block), so guard-paths is
  # wired to beforeReadFile (blocks reading secrets) + afterFileEdit (best-effort
  # warn); hard write-blocking lives in the native permissions layer.
  [ -f "$sf" ] || echo '{}' > "$sf"
  local vtmp; vtmp="$(mktemp "$(dirname "$sf")/.aigi.XXXXXX")"; TMPFILES+=("$vtmp")
  jq '.version = 1' "$sf" > "$vtmp" && { cmp -s "$vtmp" "$sf" || mv "$vtmp" "$sf"; }
  # beforeReadFile uses GUARD_SECRETS_ONLY so it blocks reading .env* only — not
  # build/deps/lockfiles, which agents legitimately read. Hard write-protection
  # for those lives in the permissions layer (afterFileEdit can't veto a write).
  local gpr; gpr="$(printf 'env HOOK_PLATFORM=cursor GUARD_SECRETS_ONLY=1 "%s/guard-paths.sh"' "$hd")"
  merge_json "$sf" "$(jq -n \
    --arg gp "$(cmd cursor "$hd" guard-paths)" \
    --arg gpr "$gpr" \
    --arg gb "$(cmd cursor "$hd" guard-bash)" \
    --arg fm "$(cmd cursor "$hd" format-edited)" \
    --arg lg "$(cmd cursor "$hd" log-tool)" \
    --arg vn "$(cmd cursor "$hd" improve-nudge)" \
    --arg vfn "$(cmd cursor "$hd" verify-nudge)" \
    --arg cn "$(cmd cursor "$hd" changelog-nudge)" \
    --arg lm "$(cmd cursor "$hd" load-memory)" '{
    sessionStart: [ {command:$lm} ],
    beforeShellExecution: [ {command:$lg}, {command:$gb} ],
    beforeReadFile: [ {command:$gpr} ],
    afterFileEdit: [ {command:$lg}, {command:$gp}, {command:$fm} ],
    stop: [ {command:$vfn}, {command:$vn}, {command:$cn} ]
  }')"
  echo "  cursor  -> $sf (memory-load, log, guard-bash, guard-read-paths, format, improve-nudge, verify-nudge, changelog-nudge; write-block via permissions)"
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
  echo "  gemini  -> $sf (log, auto-format, guard paths, guard bash) — Gemini CLI (Antigravity is a separate target)"
}

# Antigravity is NOT the Gemini CLI — it reads its own ~/.gemini/antigravity-cli/
# hooks.json with a different schema: top-level named hooks, PreToolUse/PostToolUse
# events, tool-name matchers (run_command, write_to_file|replace_file_content|…),
# stdin under toolCall.args, and a stdout deny of {"allow_tool":false,"deny_reason":…}
# with exit 0 (verified against the agy binary). agy invokes the hook by absolute
# path, so we wire tiny wrappers that set HOOK_PLATFORM=antigravity.
install_antigravity() {
  local base="$HOME/.gemini/antigravity-cli" hd="$HOME/.gemini/antigravity-cli/hooks"
  local hj="$base/hooks.json"
  [ -d "$base" ] || { echo "  antigravity: ~/.gemini/antigravity-cli not found — is the Antigravity CLI (agy) installed? (skipped)"; return 0; }
  copy_scripts "$hd"
  local s
  for s in guard-bash guard-paths log-tool format-edited; do
    printf '#!/usr/bin/env bash\nexport HOOK_PLATFORM=antigravity\nexec "%s/%s.sh"\n' "$hd" "$s" > "$hd/$s.ag.sh"
    chmod +x "$hd/$s.ag.sh"
  done
  [ -f "$hj" ] || echo '{}' > "$hj"
  local add tmp
  add="$(jq -n \
    --arg gb "$hd/guard-bash.ag.sh" --arg gp "$hd/guard-paths.ag.sh" \
    --arg lg "$hd/log-tool.ag.sh"  --arg fm "$hd/format-edited.ag.sh" '{
    "aigi-log": {
      PreToolUse:  [ {matcher:"*", hooks:[{type:"command",command:$lg,timeout:30}]} ],
      PostToolUse: [ {matcher:"*", hooks:[{type:"command",command:$lg,timeout:30}]} ]
    },
    "aigi-guard-bash":  { PreToolUse:  [ {matcher:"run_command", hooks:[{type:"command",command:$gb,timeout:30}]} ] },
    "aigi-guard-paths": { PreToolUse:  [ {matcher:"write_to_file|replace_file_content|multi_replace_file_content", hooks:[{type:"command",command:$gp,timeout:30}]} ] },
    "aigi-format":      { PostToolUse: [ {matcher:"write_to_file|replace_file_content|multi_replace_file_content", hooks:[{type:"command",command:$fm,timeout:30}]} ] }
  }')"
  tmp="$(mktemp "$(dirname "$hj")/.aigi.XXXXXX")"; TMPFILES+=("$tmp")
  # Named hooks live at the top level; drop any prior aigi-* first so re-runs never
  # duplicate, then merge ours back (preserving the user's own named hooks).
  jq --argjson add "$add" '
    (to_entries | map(select(.key | startswith("aigi-") | not)) | from_entries) + $add
  ' "$hj" > "$tmp" || { echo "  merge failed for $hj (left unchanged)" >&2; return 1; }
  if cmp -s "$tmp" "$hj"; then echo "  antigravity -> $hj (already current)"; return 0; fi
  backup_file "$hj"; mv "$tmp" "$hj"
  echo "  antigravity -> $hj (log, guard paths, guard bash, format via ~/.gemini/antigravity-cli/hooks/)"
}

targets=("$@"); [ ${#targets[@]} -eq 0 ] && targets=(claude codex cursor gemini)
# Guard each install so a single tool's merge failure (bad jq, missing file)
# doesn't abort the whole run under `set -e` — the others still install.
for t in "${targets[@]}"; do
  case "$t" in
    claude)      install_claude      || echo "  claude: skipped (error above)" >&2;;
    codex)       install_codex       || echo "  codex: skipped (error above)" >&2;;
    cursor)      install_cursor      || echo "  cursor: skipped (error above)" >&2;;
    gemini)      install_gemini      || echo "  gemini: skipped (error above)" >&2;;
    antigravity) install_antigravity || echo "  antigravity: skipped (error above)" >&2;;
    *) echo "  unknown target: $t (use: claude codex cursor gemini antigravity)" >&2;;
  esac
done
echo "Done. Backups saved next to each settings file."
