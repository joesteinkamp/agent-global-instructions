#!/usr/bin/env bash
# PreToolUse / BeforeTool guard: block edits to generated or sensitive paths
# (build output, deps, lockfiles, .env). Works across Claude Code, Codex, and
# Antigravity/Gemini — the install-hooks.sh sets HOOK_PLATFORM so this blocks in
# the right dialect (exit 2 + stderr for claude/codex; stdout decision JSON for
# gemini/antigravity).
#
# Override the protected list with CLAUDE_PROTECTED_PATHS (colon-separated globs).
set -u

PLATFORM="${HOOK_PLATFORM:-claude}"
input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.filePath // empty')"
[ -z "$fp" ] && exit 0

block() {  # $1 = reason
  case "$PLATFORM" in
    gemini|antigravity) jq -nc --arg r "$1" '{decision:"deny",reason:$r}'; exit 0;;
    *)                  echo "$1" >&2; exit 2;;
  esac
}

default_globs='*/build/*:*/dist/*:*/.next/*:*/out/*:*/coverage/*:*/node_modules/*:*/.git/*:*/.env:*/.env.*:.env:.env.*'
IFS=':' read -ra globs <<< "${CLAUDE_PROTECTED_PATHS:-$default_globs}"
for g in "${globs[@]}"; do
  # shellcheck disable=SC2254
  case "$fp" in
    $g) block "BLOCKED: '$fp' is a protected/generated path (matched '$g'). Don't edit it — it's build output, a dependency, or sensitive. Override via CLAUDE_PROTECTED_PATHS if intentional.";;
  esac
done

case "$(basename "$fp")" in
  package-lock.json|pnpm-lock.yaml|yarn.lock|bun.lockb)
    block "BLOCKED: '$fp' is a lockfile — let the package manager update it, don't hand-edit.";;
esac

exit 0
