#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit|NotebookEdit) — block edits to generated or
# sensitive paths (build output, deps, lockfiles, .env). Exit 2 blocks the call
# and feeds the message back to the model.
#
# Override the protected list with CLAUDE_PROTECTED_PATHS (colon-separated
# globs matched against the full file path).
set -u

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
[ -z "$fp" ] && exit 0

default_globs='*/build/*:*/dist/*:*/.next/*:*/out/*:*/coverage/*:*/node_modules/*:*/.git/*:*/.env:*/.env.*:.env:.env.*'
IFS=':' read -ra globs <<< "${CLAUDE_PROTECTED_PATHS:-$default_globs}"
for g in "${globs[@]}"; do
  # shellcheck disable=SC2254
  case "$fp" in
    $g) echo "BLOCKED: '$fp' is a protected/generated path (matched '$g'). Don't edit it — it's build output, a dependency, or sensitive. If this is intentional, the rule is in ~/.claude/hooks/guard-paths.sh (CLAUDE_PROTECTED_PATHS)." >&2; exit 2;;
  esac
done

case "$(basename "$fp")" in
  package-lock.json|pnpm-lock.yaml|yarn.lock|bun.lockb)
    echo "BLOCKED: '$fp' is a lockfile — let the package manager update it, don't hand-edit." >&2; exit 2;;
esac

exit 0
