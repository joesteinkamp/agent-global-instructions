# Hooks

Guardrail hooks — shell commands that fire on tool events. One set of scripts
serves **Claude Code, Codex, and Antigravity/Gemini**; `HOOK_PLATFORM` (set by
the installer in each wired command) makes them block in the right dialect.

> **These are best-effort tripwires, not a security boundary.** They see only a
> tool's structured input (a command string, a file path) and match
> heuristically — obfuscated, variable-expanded, or unusual inputs can bypass
> them. Use them as seatbelts against fat-finger mistakes, not a sandbox.

Install with `../install-hooks.sh` (all tools) or `../install-hooks.sh claude codex gemini`.

| Script | Fires on | Does |
|--------|----------|------|
| `guard-paths.sh` | edit tools (before) | **Blocks** edits to `build/ dist/ .next/ out/ coverage/ node_modules/ .git/`, `.env*`, lockfiles. |
| `guard-bash.sh`  | shell tool (before) | Trips on `rm -r` targeting root/home/parent **as a whole token** (so `rm -rf /tmp/build` and `rm -rf node_modules` pass), and on force-pushes — `--force`, a `-f` flag, or a `+refspec` (allows `--force-with-lease`). |
| `format-edited.sh` | edit tools (after) | Auto-formats the edited file with the project's Prettier/ESLint. Never blocks. |
| `log-tool.sh` | every tool (before + after) | **Observability** — appends one JSONL record per tool event to an audit log. Never blocks. |
| `validate-nudge.sh` | turn end (Stop) | When a turn ends with a **larger** diff (≥ `VALIDATE_MIN_FILES`/`VALIDATE_MIN_LINES`, default 8/200), nudges the agent to run `/validate`. Fires once (loop-guarded). Claude + Codex only — Gemini has no per-turn Stop event. |

## Observability

`log-tool.sh` records every tool call to `$AI_TOOL_LOG` (default
`~/.ai-logs/tool-calls.jsonl`) — timestamp, harness, session, event,
tool name, and truncated input/response. Wired to the before- and after-tool
events of every tool, so a long unattended run leaves a full audit trail.

Read it back with `../audit.sh`:

```
./audit.sh            # readable timeline (last 50)
./audit.sh -n 200     # last 200
./audit.sh --stats    # counts by harness / tool / event
./audit.sh --follow   # live tail while a run is in progress
```

Logs are gitignored. Rotate/trim the file yourself if it grows large.

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
- `guard-bash.sh` anchors on the target operand, so it allows targeted deletes
  (`rm -rf /tmp/build`) and commands that merely *mention* a bomb (e.g. inside an
  `echo`), while still catching split/long flags and `/bin/rm`. It is not
  exhaustive — see the boundary note at the top.
- Configure protected paths with `CLAUDE_PROTECTED_PATHS` (colon-separated globs).
  Note: `guard-paths.sh` matches the raw path and does not resolve `..`/symlinks.
- `install-hooks.sh` is idempotent and backs up each settings file before merging.
- Hooks are a safety net, not a sandbox — `guard-bash` only sees the shell tool.
