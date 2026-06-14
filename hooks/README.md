# Hooks

Claude Code hooks — shell commands that fire on tool events to *enforce*
guardrails (the model can't skip them). Install with `../install-hooks.sh`.

| Script | Event | Does |
|--------|-------|------|
| `guard-paths.sh` | `PreToolUse(Edit\|Write\|MultiEdit\|NotebookEdit)` | **Blocks** edits to generated/sensitive paths: `build/ dist/ .next/ out/ coverage/ node_modules/ .git/`, `.env*`, and lockfiles. Exit 2 stops the edit. |
| `guard-bash.sh` | `PreToolUse(Bash)` | **Blocks** catastrophic commands: `rm -rf` on root/home/parent, force-pushes (allows `--force-with-lease`). Conservative — won't block `rm -rf node_modules`. |
| `format-edited.sh` | `PostToolUse(Edit\|Write\|MultiEdit)` | Auto-formats the edited file with the **project's** Prettier or ESLint, if present. Never blocks. |

## Configure

- **Protected paths:** set `CLAUDE_PROTECTED_PATHS` (colon-separated globs) to
  override `guard-paths.sh`'s defaults.
- **Formatter:** `format-edited.sh` uses the nearest `node_modules/.bin/prettier`
  (then `eslint --fix`). No project tooling → it does nothing.

## Notes

- These are **Claude Code** hooks (`settings.json`). Codex/Gemini have no
  equivalent — they're a no-op there.
- `install-hooks.sh` is idempotent and backs up `settings.json` before merging.
- `guard-bash.sh` only sees the `Bash` tool; it can't sandbox the whole shell,
  so treat it as a safety net, not a security boundary.
