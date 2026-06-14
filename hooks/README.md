# Hooks

Guardrail hooks — shell commands that fire on tool events to *enforce* rules
(the model can't skip them). One set of scripts serves **Claude Code, Codex, and
Antigravity/Gemini**; `HOOK_PLATFORM` (set by the installer in each wired
command) makes them block in the right dialect.

Install with `../install-hooks.sh` (all tools) or `../install-hooks.sh claude codex gemini`.

| Script | Fires on | Does |
|--------|----------|------|
| `guard-paths.sh` | edit tools (before) | **Blocks** edits to `build/ dist/ .next/ out/ coverage/ node_modules/ .git/`, `.env*`, lockfiles. |
| `guard-bash.sh`  | shell tool (before) | **Blocks** `rm -rf` on root/home/parent and force-pushes (allows `--force-with-lease`). Won't block `rm -rf node_modules`. |
| `format-edited.sh` | edit tools (after) | Auto-formats the edited file with the project's Prettier/ESLint. Never blocks. |

## Per-tool wiring

| Tool | Config file | Events | Block dialect |
|------|-------------|--------|---------------|
| **Claude Code** | `~/.claude/settings.json` | `PreToolUse` (`Edit\|Write\|MultiEdit\|NotebookEdit`, `Bash`), `PostToolUse` | exit 2 + stderr |
| **Codex** | `~/.codex/hooks.json` | `PreToolUse` (`Bash`) | exit 2 + stderr |
| **Antigravity / Gemini** | `~/.gemini/settings.json` | `BeforeTool` (`run_shell_command`, `write_file\|replace`), `AfterTool` | stdout `{"decision":"deny","reason":…}` |

## Caveats

- **Codex** currently only surfaces the **`Bash`** tool to hooks, so only the
  shell guard is wired there; path-guard/format will work once Codex exposes its
  edit tool to hooks.
- **Antigravity**'s schema is the Gemini CLI hooks format
  (`settings.json` → `hooks` → `BeforeTool`/`AfterTool`). If your Antigravity
  build reads hooks from a different path (e.g. `.agents/hooks.json`), copy the
  same `hooks` block there.
- `guard-bash.sh` matches the dangerous substring anywhere in the command, so a
  command that merely *contains* `rm -rf /` (e.g. inside an `echo`) is blocked
  too — erring safe. Adjust the patterns if that's too strict.
- Configure protected paths with `CLAUDE_PROTECTED_PATHS` (colon-separated globs).
- `install-hooks.sh` is idempotent and backs up each settings file before merging.
- Hooks are a safety net, not a sandbox — `guard-bash` only sees the shell tool.
