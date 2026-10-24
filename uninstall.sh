#!/usr/bin/env bash
# Reverse what install.sh added — strip exactly our entries from each tool's
# config, never touching hand-added rules or your instruction files.
#
#   ./uninstall.sh                # all tools (global)
#   ./uninstall.sh claude         # just Claude Code
#   ./uninstall.sh codex cursor
#   ./uninstall.sh --project      # remove only the in-repo (./.claude, …) command
#                                 #   files an `install-commands.sh --project` wrote
#
# Removes, per tool: our hook entries (matched by hook-script name), the
# permissions we added (Claude/Cursor JSON rules subtracted; Codex managed TOML
# block removed), and the installed command files. Each config is backed up
# first. The per-tool instruction POINTER that customize.sh --global installed
# (Claude's @import file, Codex's symlink) is restored from its newest backup
# (or removed if none). The rendered ~/AGENTS.md itself is LEFT IN PLACE.
#
# Files the install ledger tracks (roles, the lm shim, the sweep CLI) are
# removed through it: one still holding what we installed goes quietly, one you
# edited is saved to ~/.ai/install-state/preserved/ first. A pointer path gets
# back the first original we displaced (install-state/orig/), not merely the
# newest .bak.*. The state dir itself stays — it's your recovery store:
#
#   ./uninstall.sh --purge        # also delete ~/.ai/install-state (asks you to type "purge")
#
# `gemini` is accepted only to clean up artifacts from a pre-retirement install
# (the Gemini CLI itself is no longer a supported target — see CHANGELOG).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }
# shellcheck source=lib/preserve.sh
. "$DIR/lib/preserve.sh"
# Permission rules come off by provenance: only the ones settings.tsv says we
# added (G4); a file from before the ledger falls back to the whole snippet.
# shellcheck source=lib/settings-ledger.sh
. "$DIR/lib/settings-ledger.sh"

# Derive the hook-script set from the actual files so it can't drift from the
# installer. HOOK_RE matches /<our-script>.sh on the dir slash.
HOOK_NAMES=()
for f in "$DIR"/hooks/*.sh; do HOOK_NAMES+=("$(basename "$f" .sh)"); done
# Also remove entries from the pre-quality-nudge installer if uninstall runs on
# a machine that has not yet performed the upgrade install.
HOOK_NAMES+=(improve-nudge verify-nudge changelog-nudge)
# The session rating survey was removed on 2026-09-06; its scripts no longer
# exist in hooks/, so name them here or an uninstall leaves them installed.
HOOK_NAMES+=(scorecard scorecard-enqueue scorecard-survey)
# Pattern segment starts with / and groups name alternatives; callers add
# the literal hooks directory and pathname token boundaries.
HOOK_RE="/($(IFS='|'; echo "${HOOK_NAMES[*]}"))\\.sh"

TMPFILES=()
trap '[ ${#TMPFILES[@]} -gt 0 ] && rm -f "${TMPFILES[@]}" || true' EXIT

backup_file() {  # $1 = file to back up, keep 5 newest
  cp "$1" "$(mktemp "$1.bak.XXXXXX")"
  local n=0 b
  while IFS= read -r b; do n=$((n+1)); if [ "$n" -gt 5 ]; then rm -f -- "$b"; fi; done \
    < <(ls -1t -- "$1".bak.* 2>/dev/null)
  return 0
}

# Reverse a global instruction pointer that customize.sh --global installed.
# Handles both shapes: the Codex symlink to ~/AGENTS.md and Claude's
# generated @import pointer file — anything else at the path is left alone.
# The current pointer file is backed up first (it may carry hand additions
# below the import), then the newest PRE-EXISTING backup of the original is
# restored; with no backup the pointer is simply removed.
restore_global_pointer() {  # $1 = pointer path
  local f="$1" bak
  if [ -L "$f" ]; then
    [ "$(readlink "$f")" = "$HOME/AGENTS.md" ] || return 0
  elif [ -f "$f" ]; then
    # Our pointer file, or the copy install makes where symlinks fail.
    { grep -qF '@~/AGENTS.md' "$f" && grep -qF 'agent-global-instructions' "$f"; } \
      || cmp -s "$f" "$HOME/AGENTS.md" || return 0
  else
    return 0
  fi
  # The first original we displaced beats the newest backup, which after a
  # few installs is only ever one of our own old pointers (G2).
  local orig; orig="$PV_STATE/orig/$(pv_pathid "$f")"
  # shellcheck disable=SC2012  # newest-first by mtime; names are mktemp-safe
  bak="$(ls -1t -- "$f".bak.* 2>/dev/null | head -n 1 || true)"
  if [ -f "$f" ] && [ ! -L "$f" ]; then backup_file "$f"; fi
  rm -f "$f"
  if [ -f "$orig" ]; then
    # Handed back, so it's consumed: if you change this file and install
    # again, that version becomes the original the next uninstall restores.
    cp "$orig" "$f" && echo "  restored $f to the original it had before the install" && rm -f "$orig"
  elif [ -n "$bak" ]; then
    cp "$bak" "$f" && echo "  restored $f from ${bak##*/}"
  else
    echo "  removed pointer $f (no prior backup to restore)"
  fi
}

# Apply a jq program to a settings file in place (backup + atomic), no-op if
# nothing changed or the file is absent.
edit_json() {  # $1 = file, $2 = jq program, $3.. = extra jq args
  local f="$1" prog="$2"; shift 2
  [ -f "$f" ] || return 0
  local tmp; tmp="$(mktemp "$(dirname "$f")/.aigi.XXXXXX")"; TMPFILES+=("$tmp")  # same-dir: atomic mv + valid BSD template
  jq "$@" "$prog" "$f" > "$tmp" || { echo "  edit failed for $f (left unchanged)" >&2; return 0; }
  if cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
  backup_file "$f"; mv "$tmp" "$f"; echo "  cleaned $f"
}

# Drop only matching handlers, preserving third-party handlers and metadata in
# shared Claude/Codex groups. Cursor flat entries are removed individually.
strip_hooks() {  # $1 = settings file
  # Scope names to this tool directory; escape regex metacharacters literally.
  local owned_pat
  owned_pat="$(jq -nr --arg dir "$(dirname "$1")/hooks" --arg names "$HOOK_RE" \
    '$dir | explode | map(. as $c | if ([92,46,94,36,124,63,42,43,40,41,91,93,123,125] | index($c)) != null then [92,$c] else [$c] end) | flatten | implode | . as $escaped | ([34,39] | implode) as $quotes | "(^|[[:space:]" + $quotes + "])" + $escaped + $names + "($|[[:space:]" + $quotes + "])"')"
  edit_json "$1" '
    if .hooks then
      .hooks |= with_entries(.value |= map(
        if has("hooks") then
          if ((.hooks // []) | any((.command // "") | test($pat))) then
            .hooks = (.hooks | map(select(
              ((.command // "") | test($pat)) | not
            )))
            | select((.hooks | length) > 0)
          else . end
        else
          select(((.command // "") | test($pat)) | not)
        end
      ))
      | .hooks |= with_entries(select((.value | length) > 0))
      | if (.hooks == {}) then del(.hooks) else . end
    else . end
  ' --arg pat "$owned_pat"
}

# Subtract the permission arrays in a JSON snippet from a settings file.
# Reverse enable_agent_teams. Only removes the value WE write ("1") — any other
# value is the user's own choice and stays. Drops an .env object that this leaves
# empty, so uninstalling doesn't leave a bare key behind.
disable_agent_teams() {  # $1 = claude settings.json
  local sf="$1" cur tmp
  [ -f "$sf" ] || return 0
  cur="$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS // empty' "$sf" 2>/dev/null)" || return 0
  [ "$cur" = "1" ] || return 0
  tmp="$(mktemp "$(dirname "$sf")/.aigi.XXXXXX")"
  if jq 'del(.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS)
         | if (.env | type) == "object" and (.env | length) == 0 then del(.env) else . end' \
       "$sf" > "$tmp" 2>/dev/null; then
    backup_file "$sf"; mv "$tmp" "$sf"
    echo "  removed CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS from $sf"
  else
    rm -f "$tmp"
  fi
  return 0
}

# Reverse seed_advisor_model. Only removes the value WE write ("opus").
unseed_advisor_model() {  # $1 = claude settings.json
  local sf="$1" cur tmp
  [ -f "$sf" ] || return 0
  cur="$(jq -r '.advisorModel // empty' "$sf" 2>/dev/null)" || return 0
  [ "$cur" = "opus" ] || return 0
  tmp="$(mktemp "$(dirname "$sf")/.aigi.XXXXXX")"
  if jq 'del(.advisorModel)' "$sf" > "$tmp" 2>/dev/null; then
    backup_file "$sf"; mv "$tmp" "$sf"
    echo "  removed advisorModel from $sf"
  else
    rm -f "$tmp"
  fi
  return 0
}

# Remove our managed permissions block from Codex's config.toml (between sentinels).
strip_codex_block() {  # $1 = config.toml
  local f="$1"
  [ -f "$f" ] || return 0
  local begin="# >>> agent-global-instructions (codex permissions) >>>"
  local end="# <<< agent-global-instructions (codex permissions) <<<"
  grep -qF "$begin" "$f" || return 0
  local tmp; tmp="$(mktemp "$(dirname "$f")/.aigi.XXXXXX")"; TMPFILES+=("$tmp")
  awk -v b="$begin" -v e="$end" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$f" > "$tmp"
  if cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
  backup_file "$f"; mv "$tmp" "$f"; echo "  cleaned $f (removed codex permissions block)"
}

# Remove only notification keys installed by install-settings.sh. Empty table
# headers may remain; removing a header could re-scope user keys added later.
strip_codex_notification_defaults() {  # $1 = config.toml
  local f="$1" marker="# agent-global-instructions: codex notification defaults"
  [ -f "$f" ] || return 0
  grep -qF "$marker" "$f" || return 0
  local tmp; tmp="$(mktemp "$(dirname "$f")/.aigi.XXXXXX")"; TMPFILES+=("$tmp")
  grep -vF "$marker" "$f" > "$tmp" || true
  if cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
  backup_file "$f"; mv "$tmp" "$f"; echo "  cleaned $f (removed codex notification defaults)"
}

# Remove the team-role definitions we installed (~/.claude/agents/<role>.md,
# ~/.codex/agents/<role>.toml). Basenames come from the canonical roles/*.md, so
# this works whether or not the generated Codex port is present locally. A dest
# file that no longer matches ours has been hand-tuned — back it up before
# removing, since install-roles.sh would have overwritten it silently.
remove_roles_dir() {  # $1 = dest dir  $2 = ext  [$3 = rendered src dir, for the compare]
  local dest="$1" ext="$2" src="${3:-}" f base n=0
  [ -d "$dest" ] || return 0
  [ -d "$DIR/roles" ] || return 0
  for f in "$DIR/roles"/*.md; do
    [ -e "$f" ] || continue
    base="$(basename "$f" .md)"
    [ "$base" = "README" ] && continue
    [ -f "$dest/$base.$ext" ] || continue
    # Through the ledger: ours goes quietly, an edited one is preserved first.
    if [ -n "$src" ]; then pv_delete "$dest/$base.$ext" uninstall render:roles role || continue
    else pv_delete "$dest/$base.$ext" uninstall "roles/$base.md" role || continue; fi
    [ "$PV_ACTION" = removed ] && n=$((n+1))
  done
  [ "$n" -gt 0 ] && echo "  removed $n role file(s) from $dest"
  return 0
}

# Legacy cleanup: remove the command files earlier versions installed under a
# skill's name (and their backups), plus retired names — never touching the
# user's own commands.
remove_commands_dir() {  # $1 = dest dir
  local dest="$1" d f n=0 old
  [ -d "$dest" ] || return 0
  for d in "$DIR/skills"/*/ "$DIR/.agents/skills/ux-audit/"; do
    [ -d "$d" ] || continue
    # Through the ledger: a command file with a skill's name may be your own,
    # so one we never shipped (and every old .bak.*) is saved before removal.
    for f in "$dest/$(basename "$d").md" "$dest/$(basename "$d").md".bak.*; do
      [ -f "$f" ] || continue
      case "$f" in *.bak.*) pv_delete "$f" "legacy command backup" "" command || continue;;
        *) pv_delete "$f" "legacy command" "commands/$(basename "$f")" command || continue;; esac
      [ "$PV_ACTION" = removed ] && n=$((n+1))
    done
  done
  local retired="validate handoff flow tidy critique audit"   # space-separated; keep in sync with install-skills.sh RETIRED
  for old in $retired; do
    # Backed up first: a retired name is generic enough (e.g. "audit") that the
    # file could be the user's own, not our stale install.
    if [ -f "$dest/$old.md" ] && pv_delete "$dest/$old.md" "retired command" "commands/$old.md" command \
       && [ "$PV_ACTION" = removed ]; then n=$((n+1)); fi
  done
  [ "$n" -gt 0 ] && echo "  removed $n command file(s) from $dest"
  return 0
}

# Legacy-cleanup helper: remove every file under $1 that carries our GENERATED
# marker, without diffing against a source dir (the render no longer
# generates a gemini port, so there is nothing current to compare against).
remove_generated_toml() {  # $1 = dest dir
  local dest="$1" f n=0
  [ -d "$dest" ] || return 0
  for f in "$dest"/*.toml; do
    [ -f "$f" ] || continue
    grep -q '^# GENERATED from commands/' "$f" 2>/dev/null && { rm -f "$f"; n=$((n+1)); }
  done
  [ "$n" -gt 0 ] && echo "  removed $n legacy command file(s) from $dest"
  return 0
}

# Legacy cleanup: Codex skills earlier versions COPIED in carry the render
# marker; a user's own skill never does.
remove_codex_skills() {  # $1 = destination skills dir
  local dest="$1" d n=0
  [ -d "$dest" ] || return 0
  for d in "$dest"/*/; do
    d="${d%/}"
    [ -L "$d" ] && continue   # symlinked skill — remove_skill_links owns it
    grep -q '^<!-- GENERATED from commands/' "$d/SKILL.md" 2>/dev/null || continue
    rm -rf "$d"; n=$((n+1))
  done
  [ "$n" -gt 0 ] && echo "  removed $n copied Codex skill(s) from $dest"
  return 0
}

# Is $1 a symlink install-skills.sh created — one resolving into THIS repo's
# skills/ or .agents/skills/ tree? Prefix match, so it also covers dangling
# links whose skill was since renamed/dropped. Keep in sync with
# install-skills.sh's copy.
is_our_skill_link() {  # $1 = path
  [ -L "$1" ] || return 1
  case "$(readlink "$1")" in "$DIR/skills/"*|"$DIR/.agents/skills/"*) return 0;; *) return 1;; esac
}

# Remove the skill symlinks install-skills.sh created (including
# dangling ones); a user's own skill (real dir, or a symlink to somewhere
# else) is never touched.
remove_skill_links() {  # $1 = destination skills dir
  local dest="$1" link n=0
  [ -d "$dest" ] || return 0
  for link in "$dest"/*; do
    is_our_skill_link "$link" || continue
    rm -f "$link"; n=$((n+1))
  done
  [ "$n" -gt 0 ] && echo "  removed $n skill symlink(s) from $dest"
  return 0
}

# Cursor stores a top-level "version":1 beside .hooks; once our hooks are stripped
# and no user hooks remain, drop it too (and delete an emptied file) so uninstall
# fully reverses install rather than leaving {"version":1} behind.
cursor_hooks_cleanup() {  # $1 = hooks.json
  local f="$1"
  [ -f "$f" ] || return 0
  edit_json "$f" 'if ((.hooks // {}) | length) == 0 then del(.version) else . end'
  if [ -f "$f" ] && [ "$(jq -c . "$f" 2>/dev/null)" = '{}' ]; then rm -f "$f"; echo "  removed empty $f"; fi
}

# Antigravity's hooks.json is a flat map of top-level named hooks; drop exactly the
# ones we added (the aigi-* keys), preserving any the user wrote, and delete the
# file if it ends up empty. (Copied hook scripts/wrappers are left in place, like
# every other tool's uninstall leaves its ~/.<tool>/hooks scripts.)
strip_antigravity_hooks() {  # $1 = hooks.json
  local f="$1"
  [ -f "$f" ] || return 0
  edit_json "$f" '(to_entries | map(select(.key | startswith("aigi-") | not)) | from_entries)'
  if [ -f "$f" ] && [ "$(jq -c . "$f" 2>/dev/null)" = '{}' ]; then rm -f "$f"; echo "  removed empty $f"; fi
}

PROJECT=0
PURGE=0
targets=()
for a in "$@"; do
  case "$a" in
    --project) PROJECT=1;;
    --purge) PURGE=1;;
    claude|codex|cursor|antigravity) targets+=("$a");;
    gemini) targets+=("$a");;  # legacy cleanup only — see header comment
    *) echo "  unknown arg: $a (use: --project | claude codex cursor antigravity | gemini for legacy cleanup)" >&2; exit 1;;
  esac
done
[ ${#targets[@]} -eq 0 ] && targets=(claude codex cursor antigravity)

# --project: strip ONLY in-repo command files an older `install-commands.sh
# --project` wrote; global hooks/permissions aren't installed per-project, so leave
# them alone.
if [ "$PROJECT" = 1 ]; then
  for t in "${targets[@]}"; do
    case "$t" in
      claude)      remove_commands_dir "$DIR/.claude/commands"
                   remove_roles_dir "$DIR/.claude/agents" md;;
      codex)       echo "  Codex skills are global; --project has no effect for codex"
                   remove_roles_dir "$DIR/.codex/agents" toml "$DIR/roles/codex";;
      cursor)      remove_commands_dir "$DIR/.cursor/commands"
                   remove_roles_dir "$DIR/.cursor/agents" md "$DIR/roles/cursor";;
      gemini)      remove_generated_toml "$DIR/.gemini/commands";;
      antigravity) remove_roles_dir "$DIR/.agents/agents" md "$DIR/roles/antigravity";;
      *) echo "  unknown target: $t (use: claude codex cursor antigravity | gemini for legacy cleanup)" >&2;;
    esac
  done
  pv_finish
  echo "Done. Removed in-repo (--project) command and role files only."
  exit 0
fi

for t in "${targets[@]}"; do
  case "$t" in
    claude)
      remove_commands_dir "$HOME/.claude/commands"
      remove_roles_dir "$HOME/.claude/agents" md
      remove_skill_links "$HOME/.claude/skills"
      strip_hooks "$HOME/.claude/settings.json"
      sl_strip_perms "$HOME/.claude/settings.json" "$DIR/settings-permissions.snippet.json"
      [ -f "$DIR/settings-permissions.local.json" ] && sl_strip_perms "$HOME/.claude/settings.json" "$DIR/settings-permissions.local.json"
      disable_agent_teams "$HOME/.claude/settings.json"
      unseed_advisor_model "$HOME/.claude/settings.json"
      restore_global_pointer "$HOME/.claude/CLAUDE.md"
      ;;
    codex)
      remove_codex_skills "$HOME/.codex/skills"
      remove_roles_dir "$HOME/.codex/agents" toml "$DIR/roles/codex"
      remove_skill_links "$HOME/.codex/skills"
      strip_hooks "$HOME/.codex/hooks.json"
      strip_codex_block "$HOME/.codex/config.toml"
      strip_codex_notification_defaults "$HOME/.codex/config.toml"
      restore_global_pointer "$HOME/.codex/AGENTS.md"
      ;;
    cursor)
      remove_commands_dir "$HOME/.cursor/commands"
      remove_roles_dir "$HOME/.cursor/agents" md "$DIR/roles/cursor"
      remove_skill_links "$HOME/.cursor/skills"
      strip_hooks "$HOME/.cursor/hooks.json"
      cursor_hooks_cleanup "$HOME/.cursor/hooks.json"
      sl_strip_perms "$HOME/.cursor/cli-config.json" "$DIR/settings-permissions.cursor.snippet.json"
      ;;
    gemini)
      # Legacy cleanup only — the Gemini CLI is retired, so this strips whatever
      # a pre-retirement install left behind rather than diffing against a
      # source dir that no longer exists.
      remove_generated_toml "$HOME/.gemini/commands"
      strip_hooks "$HOME/.gemini/settings.json"
      restore_global_pointer "$HOME/.gemini/GEMINI.md"
      if [ -f "$HOME/.gemini/policies/gemini-guardrails.toml" ]; then
        rm -f "$HOME/.gemini/policies/gemini-guardrails.toml"
        echo "  removed $HOME/.gemini/policies/gemini-guardrails.toml"
      fi
      ;;
    antigravity)
      strip_antigravity_hooks "$HOME/.gemini/antigravity-cli/hooks.json"
      remove_roles_dir "$HOME/.gemini/config/agents" md "$DIR/roles/antigravity"
      # Fill in @HOME@ exactly as install-settings.sh did, so the subtraction matches.
      ag_snip="$(mktemp)"; TMPFILES+=("$ag_snip")
      jq --arg h "$HOME" '.permissions |= with_entries(.value |= map(gsub("@HOME@"; $h)))' \
        "$DIR/settings-permissions.antigravity.snippet.json" > "$ag_snip" \
        && sl_strip_perms "$HOME/.gemini/antigravity-cli/settings.json" "$ag_snip"
      ;;
    *) echo "  unknown target: $t (use: claude codex cursor antigravity | gemini for legacy cleanup)" >&2;;
  esac
done
# Machine-wide (not per-tool): the local-model shim customize.sh --global
# installed. Marker-checked so a foreign `lm` binary is never touched. The
# ~/.ai/ registry files (clis, local-models, model-routing, playbooks) are
# regenerable metadata and stay in place, like the roster.
if [ -f "$HOME/.local/bin/lm" ] && grep -q 'agent-global-instructions' "$HOME/.local/bin/lm" 2>/dev/null; then
  pv_delete "$HOME/.local/bin/lm" uninstall lm shim \
    && [ "$PV_ACTION" = removed ] && echo "  removed $HOME/.local/bin/lm (local-model shim)"
fi
# Same for the portable `timeout` shim (only ever installed where none existed).
if [ -f "$HOME/.local/bin/timeout" ] && grep -q 'agent-global-instructions' "$HOME/.local/bin/timeout" 2>/dev/null; then
  rm -f "$HOME/.local/bin/timeout"
  echo "  removed $HOME/.local/bin/timeout (portable timeout shim)"
fi
# The tool-agnostic worktree sweep CLI install-hooks.sh copied out of hooks/.
# Content-checked against our own header, so a foreign file parked at that path
# is never removed. (The hook wiring and the copies under each tool's hooks dir
# are handled by strip_hooks / the HOOK_NAMES matcher above.) The per-repo
# rate-limit stamps in ~/.ai-logs are logs and stay, like every other log.
if [ -f "$HOME/.ai/worktree-sweep.sh" ] \
   && grep -q 'Worktree reaper' "$HOME/.ai/worktree-sweep.sh" 2>/dev/null; then
  pv_delete "$HOME/.ai/worktree-sweep.sh" uninstall hooks/worktree-reap.sh sweep-cli \
    && [ "$PV_ACTION" = removed ] && echo "  removed $HOME/.ai/worktree-sweep.sh (worktree sweep CLI)"
fi
pv_finish

# --purge: the state dir holds every edit the installer ever saved for you, so
# deleting it is the one irreversible step here — typed confirmation only.
if [ "$PURGE" = 1 ] && [ -d "$PV_STATE" ]; then
  echo "This deletes $PV_STATE, including every edited file the installer saved for you in preserved/."
  ans=""; read -r -p 'Type "purge" to confirm: ' ans </dev/tty 2>/dev/null || true
  if [ "$ans" = purge ]; then rm -rf "$PV_STATE"; echo "  removed $PV_STATE"
  else echo "  kept $PV_STATE (not confirmed)"; fi
fi

echo "Done. Backups saved next to each file. ~/AGENTS.md left in place;"
echo "per-tool instruction pointers were restored from their newest backup where one existed."
