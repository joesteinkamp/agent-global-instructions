# Hooks

Guardrail hooks — shell commands that fire on tool events. One set of scripts
serves **Claude Code, Codex, Cursor, and Antigravity/Gemini**; `HOOK_PLATFORM`
(set by the installer in each wired command) makes them block in the right
dialect.

> **These are best-effort tripwires, not a security boundary.** They see only a
> tool's structured input (a command string, a file path) and match
> heuristically — obfuscated, variable-expanded, or unusual inputs can bypass
> them. Use them as seatbelts against fat-finger mistakes, not a sandbox.

Install with `../install-hooks.sh` (all tools) or `../install-hooks.sh claude codex cursor gemini`.

| Script | Fires on | Does |
|--------|----------|------|
| `guard-paths.sh` | edit tools (before) | **Blocks** edits to `build/ dist/ .next/ out/ coverage/ node_modules/ .git/`, `.env*`, lockfiles. |
| `guard-bash.sh`  | shell tool (before) | Trips on `rm -r` targeting root/home/parent **as a whole token** (so `rm -rf /tmp/build` and `rm -rf node_modules` pass), and on force-pushes — `--force`, a `-f` flag, or a `+refspec` (allows `--force-with-lease`). |
| `format-edited.sh` | edit tools (after) | Auto-formats the edited file with the project's Prettier/ESLint. Never blocks. |
| `log-tool.sh` | every tool (before + after) | **Observability** — appends one JSONL record per tool event to an audit log. Never blocks. |
| `improve-nudge.sh` | turn end (Stop) | When a turn ends with a **larger** diff (≥ `IMPROVE_MIN_FILES`/`IMPROVE_MIN_LINES`, default 8/200), nudges the agent to run `/improve`. Fires once (loop-guarded). Claude/Codex (exit-2 or `block`), Cursor (`followup_message`) — Gemini has no per-turn Stop event. |
| `changelog-nudge.sh` | turn end (Stop) | When a session ends with any uncommitted change, reminds the agent to **propose a Change Log entry and get your approval before writing it** (never auto-writes — the human-approval gate is preserved). Once per distinct diff. Claude/Codex/Cursor; Gemini has no Stop event. Pairs with the `changelog` instruction section in `template.md`. |
| `load-memory.sh` | session start | Injects a pointer to your **out-of-tool** memory stores (Hermes `~/.hermes/`, OpenClaw `~/.openclaw/workspace/`, project `MEMORY.md`/`memory/`) so the agent reads them before personal tasks. Lists only stores that exist; silent otherwise. Never blocks. Claude (`additionalContext`) + Cursor (`additional_context`) — the tools with SessionStart injection. Complements Claude's native auto-memory (`~/.claude/projects/<project>/memory/`), which it doesn't duplicate. |
| `precompact-archive.sh` | before compaction (PreCompact) | Copies the **raw transcript** to `<log-dir>/transcripts/` before Claude compacts (and silently drops detail), and logs a `PreCompact` audit record. The platform forbids context injection here, so it preserves the record on disk rather than curating it. Never blocks. Claude only. |
| `log-session-end.sh` | session end (SessionEnd) | Appends a `SessionEnd` audit record with the end reason (`clear`/`logout`/`prompt_input_exit`/`resume`/`other`), closing the trail the SessionStart loader opened. Output is ignored by the platform — pure observability. Claude only. |

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

`precompact-archive.sh` and `log-session-end.sh` write `PreCompact` / `SessionEnd`
records to the **same** log (so `audit.sh` shows a start-to-finish timeline), and
PreCompact also drops raw transcript copies in `<log-dir>/transcripts/` so an
auto-compaction never silently loses the full record. Those transcript copies are
**unredacted** (unlike the audit log) — written `0600` in a `0700` dir and capped
to the newest `AI_TRANSCRIPT_KEEP` (default 50).

Logs and transcript archives are gitignored — treat them as sensitive. Rotate/trim
them yourself if they grow large.

## Per-tool wiring

| Tool | Config file | Events | Block dialect |
|------|-------------|--------|---------------|
| **Claude Code** | `~/.claude/settings.json` | `SessionStart`, `PreToolUse` (`Edit\|Write\|MultiEdit\|NotebookEdit`, `Bash`), `PostToolUse`, `PreCompact`, `Stop`, `SessionEnd` | exit 2 + stderr |
| **Codex** | `~/.codex/hooks.json` | `PreToolUse` (`apply_patch\|Edit\|Write`, `Bash`), `PostToolUse`, `Stop` | exit 2 + stderr |
| **Cursor** | `~/.cursor/hooks.json` (`version: 1`) | `sessionStart`, `beforeShellExecution`, `beforeReadFile`, `afterFileEdit`, `stop` | stdout `{"permission":"deny"}` |
| **Gemini CLI** | `~/.gemini/settings.json` | `BeforeTool` (`run_shell_command`, `write_file\|replace`), `AfterTool` | stdout `{"decision":"deny","reason":…}` |

## Caveats

- **Codex** surfaces file edits via the **`apply_patch`** tool, whose
  `tool_input.command` carries the raw patch envelope (no `file_path` field), so
  `guard-paths`/`format-edited` parse the target paths from the
  `*** Add/Update/Delete File:` / `*** Move to:` lines. Both shell- and
  edit-guards are wired.
- **Cursor** has no blocking *pre-edit* event (only `afterFileEdit`, which can't
  veto a write), so `guard-paths` is wired to `beforeReadFile` (blocks reading
  secrets) and `afterFileEdit` (best-effort). Hard write-protection for `.env`,
  lockfiles, and build dirs comes from the **permissions layer**
  (`../install-settings.sh cursor`), not the hook. Cursor's `stop` nudge uses
  `followup_message` (auto-continue), and is local-only (not cloud agents).
- **Antigravity is NOT the Gemini CLI** — despite the shared `~/.gemini/` prefix,
  they're separate tools with separate config. The `gemini`/`antigravity` install
  target writes to the **Gemini CLI**'s `~/.gemini/settings.json`. Antigravity
  (CLI) keeps its own config under **`~/.gemini/antigravity-cli/`**
  (`settings.json` with `colorScheme`/`model`/`trustedWorkspaces` and, per its
  docs, a native `permissions.allow/deny` + `toolPermission` model) and does
  **not** read the Gemini CLI's `settings.json` hooks. So `antigravity` is
  currently just an alias for the Gemini-CLI target; Antigravity itself is **not
  yet wired**. Proper support would drive its native permission model (or a
  confirmed Antigravity hooks file) rather than the Gemini CLI hooks block —
  tracked as a follow-up once the schema is verified from official docs.
- `guard-bash.sh` anchors on the target operand, so targeted deletes
  (`rm -rf /tmp/build`) and most quoted/argument mentions of a dangerous string
  pass, while split/long flags and `/bin/rm` are caught. A bare catastrophic
  token anywhere in the line can still trip it (errs safe). Not exhaustive — see
  the boundary note at the top.
- Configure protected paths with `CLAUDE_PROTECTED_PATHS` (colon-separated globs).
  `guard-paths.sh` resolves relative paths against the tool's cwd and follows
  `..`/symlinks (via `realpath`/`readlink -m`) before matching.
- `install-hooks.sh` is idempotent and backs up each settings file before merging.
- Hooks are a safety net, not a sandbox — `guard-bash` only sees the shell tool.
