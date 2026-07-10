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
# GUARD_SECRETS_ONLY=1 narrows the match to secret files (.env*) only — used for
# Cursor's beforeReadFile, where blocking reads of build/deps/lockfiles would
# break normal work; only secret reads should be denied there.
#
# Override the protected list with CLAUDE_PROTECTED_PATHS (colon-separated globs).
set -u

PLATFORM="${HOOK_PLATFORM:-claude}"
input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

block() {  # $1 = reason
  case "$PLATFORM" in
    gemini)             jq -nc --arg r "$1" '{decision:"deny",reason:$r}'; exit 0;;
    antigravity)        jq -nc --arg r "$1" '{allow_tool:false,deny_reason:$r}'; exit 0;;  # exit 0: non-zero = hook failure, not a block
    cursor)             jq -nc --arg r "$1" '{permission:"deny",user_message:$r,agent_message:$r}'; exit 0;;
    *)                  echo "$1" >&2; exit 2;;
  esac
}

SECRET_GLOBS='*/.env:*/.env.*:.env:.env.*'
GENERATED_GLOBS='*/build/*:*/dist/*:*/.next/*:*/out/*:*/coverage/*:*/node_modules/*:*/.git/*'

# Committed sample files (`.env.example`, `.env.template`, …) are meant to be
# edited and shipped, so they're exempt from the SECRET globs — without this,
# `*/.env.*` blocks editing the very file you give teammates.
is_template() {  # $1 = path
  case "$(basename "$1")" in
    *.example|*.sample|*.template|*.dist) return 0;;
  esac
  return 1
}

# Match $abs and $fp (both visible via bash dynamic scope) against a colon-
# separated glob set; block (which exits) on the first hit.
match_and_block() {  # $1 = colon-separated globs
  local g globs
  IFS=':' read -ra globs <<< "$1"
  for g in "${globs[@]}"; do
    # shellcheck disable=SC2254
    case "$abs" in
      $g) block "BLOCKED: '$fp' resolves to a protected path (matched '$g') — build output, a dependency, or sensitive. Override via CLAUDE_PROTECTED_PATHS if intentional.";;
    esac
    # shellcheck disable=SC2254
    case "$fp" in
      $g) block "BLOCKED: '$fp' is a protected path (matched '$g') — build output, a dependency, or sensitive. Override via CLAUDE_PROTECTED_PATHS if intentional.";;
    esac
  done
}

# Canonicalize so relative paths, ".." traversal, and symlinks can't slip past
# the globs (resolve against cwd, then realpath/readlink -m), and match BOTH the
# original and resolved path against the protected globs + lockfile names.
check_one() {  # $1 = file path
  local fp="$1" abs
  [ -z "$fp" ] && return 0
  abs="$fp"
  case "$fp" in /*) ;; *) [ -n "$cwd" ] && abs="$cwd/$fp";; esac
  if command -v realpath >/dev/null 2>&1; then
    abs="$(realpath -m "$abs" 2>/dev/null || printf '%s' "$abs")"
  elif command -v readlink >/dev/null 2>&1; then
    abs="$(readlink -m "$abs" 2>/dev/null || printf '%s' "$abs")"
  fi

  if [ "${GUARD_SECRETS_ONLY:-0}" = 1 ]; then
    is_template "$fp" && return 0     # never block reading a committed sample
    match_and_block "$SECRET_GLOBS"
    return 0
  fi

  if [ -n "${CLAUDE_PROTECTED_PATHS:-}" ]; then
    match_and_block "$CLAUDE_PROTECTED_PATHS"   # explicit override: exactly as set
  else
    match_and_block "$GENERATED_GLOBS"
    is_template "$fp" || match_and_block "$SECRET_GLOBS"
  fi

  case "$(basename "$fp")" in
    package-lock.json|pnpm-lock.yaml|yarn.lock|bun.lockb)
      block "BLOCKED: '$fp' is a lockfile — let the package manager update it, don't hand-edit.";;
  esac
  return 0
}

# Single explicit path (Claude/Codex-Edit/Gemini tool_input, or Cursor top-level).
fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.filePath // .tool_input.notebook_path // .file_path // .toolCall.args.TargetFile // empty' 2>/dev/null)"
# Antigravity delivers args as JSON-encoded strings — TargetFile can arrive wrapped
# in a literal quote pair; strip it so the protected-path globs actually match.
if [ "$PLATFORM" = antigravity ]; then fp="${fp#\"}"; fp="${fp%\"}"; fi
if [ -n "$fp" ]; then
  check_one "$fp"
elif [ "$PLATFORM" = "codex" ]; then
  # Codex apply_patch: extract every target path from the patch envelope and
  # guard each (a single patch can touch several files). Strip a trailing CR
  # (CRLF patches) and surrounding quotes before matching.
  cmdtext="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  if [ -n "$cmdtext" ]; then
    while IFS= read -r pf; do
      pf="${pf%$'\r'}"; pf="${pf#\"}"; pf="${pf%\"}"
      [ -n "$pf" ] && check_one "$pf"
    done < <(printf '%s\n' "$cmdtext" | sed -nE 's/^\*\*\* (Add File|Update File|Delete File|Move to): (.*)$/\2/p')
  fi
fi

exit 0
