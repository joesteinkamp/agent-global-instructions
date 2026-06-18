#!/usr/bin/env bash
# PreToolUse / BeforeTool guard: block edits to generated or sensitive paths
# (build output, deps, lockfiles, .env). Works across Claude Code, Codex, Cursor,
# and Antigravity/Gemini — install-hooks.sh sets HOOK_PLATFORM so this blocks in
# the right dialect (exit 2 + stderr for claude/codex; stdout decision JSON for
# gemini/antigravity; stdout permission JSON for cursor).
#
# Path sources differ by tool: most pass a single tool_input.file_path; Cursor's
# beforeReadFile/afterFileEdit put file_path at the top level; Codex's apply_patch
# passes the raw patch envelope in tool_input.command (no path field) — the
# targets live inside as `*** Add/Update/Delete File:` / `*** Move to:` lines.
#
# Override the protected list with CLAUDE_PROTECTED_PATHS (colon-separated globs).
set -u

PLATFORM="${HOOK_PLATFORM:-claude}"
input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"

block() {  # $1 = reason
  case "$PLATFORM" in
    gemini|antigravity) jq -nc --arg r "$1" '{decision:"deny",reason:$r}'; exit 0;;
    cursor)             jq -nc --arg r "$1" '{permission:"deny",user_message:$r,agent_message:$r}'; exit 0;;
    *)                  echo "$1" >&2; exit 2;;
  esac
}

# Canonicalize so relative paths, ".." traversal, and symlinks can't slip past
# the globs (resolve against cwd, then realpath/readlink -m), and match BOTH the
# original and resolved path against the protected globs + lockfile names.
check_one() {  # $1 = file path
  local fp="$1" abs g globs
  [ -z "$fp" ] && return 0
  abs="$fp"
  case "$fp" in /*) ;; *) [ -n "$cwd" ] && abs="$cwd/$fp";; esac
  if command -v realpath >/dev/null 2>&1; then
    abs="$(realpath -m "$abs" 2>/dev/null || printf '%s' "$abs")"
  elif command -v readlink >/dev/null 2>&1; then
    abs="$(readlink -m "$abs" 2>/dev/null || printf '%s' "$abs")"
  fi

  local default_globs='*/build/*:*/dist/*:*/.next/*:*/out/*:*/coverage/*:*/node_modules/*:*/.git/*:*/.env:*/.env.*:.env:.env.*'
  IFS=':' read -ra globs <<< "${CLAUDE_PROTECTED_PATHS:-$default_globs}"
  for g in "${globs[@]}"; do
    # shellcheck disable=SC2254
    case "$abs" in
      $g) block "BLOCKED: '$fp' resolves to a protected/generated path (matched '$g'). Don't edit it — it's build output, a dependency, or sensitive. Override via CLAUDE_PROTECTED_PATHS if intentional.";;
    esac
    # shellcheck disable=SC2254
    case "$fp" in
      $g) block "BLOCKED: '$fp' is a protected/generated path (matched '$g'). Don't edit it — it's build output, a dependency, or sensitive. Override via CLAUDE_PROTECTED_PATHS if intentional.";;
    esac
  done

  case "$(basename "$fp")" in
    package-lock.json|pnpm-lock.yaml|yarn.lock|bun.lockb)
      block "BLOCKED: '$fp' is a lockfile — let the package manager update it, don't hand-edit.";;
  esac
  return 0
}

# Single explicit path (Claude/Codex-Edit/Gemini tool_input, or Cursor top-level).
fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.filePath // .file_path // empty')"
if [ -n "$fp" ]; then
  check_one "$fp"
elif [ "$PLATFORM" = "codex" ]; then
  # Codex apply_patch: extract every target path from the patch envelope and
  # guard each (a single patch can touch several files).
  cmdtext="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
  if [ -n "$cmdtext" ]; then
    while IFS= read -r pf; do
      [ -n "$pf" ] && check_one "$pf"
    done < <(printf '%s\n' "$cmdtext" | sed -nE 's/^\*\*\* (Add File|Update File|Delete File|Move to): (.*)$/\2/p')
  fi
fi

exit 0
