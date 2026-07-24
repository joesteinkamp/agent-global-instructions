# Hooks

Guardrail hooks — shell commands that fire on tool events. One set of scripts
serves **Claude Code, Codex, Cursor, and Antigravity**; `HOOK_PLATFORM`
(set by the installer in each wired command) makes them block in the right
dialect.

> **These are best-effort tripwires, not a security boundary.** They see only a
> tool's structured input (a command string, a file path) and match
> heuristically — obfuscated, variable-expanded, or unusual inputs can bypass
> them. Use them as seatbelts against fat-finger mistakes, not a sandbox.

Install with `../install-hooks.sh` (all tools) or `../install-hooks.sh claude codex cursor`.

| Script | Fires on | Does |
|--------|----------|------|
| `guard-paths.sh` | edit tools (before) | **Blocks** edits to `build/ dist/ .next/ out/ coverage/ node_modules/ .git/`, `.env*`, lockfiles. |
| `guard-bash.sh`  | shell tool (before) | Trips on `rm -r` targeting root/home/parent **as a whole token** (so `rm -rf /tmp/build` and `rm -rf node_modules` pass), and on force-pushes — `--force`, a `-f` flag, or a `+refspec` (allows `--force-with-lease`). |
| `format-edited.sh` | edit tools (after) | Auto-formats the edited file with the project's Prettier/ESLint. Never blocks. |
| `log-tool.sh` | every tool (before + after) | **Observability** — appends one JSONL record per tool event to an audit log. Never blocks. |
| `quality-nudge.sh` | turn end (Stop) | Emits one **non-blocking advisory** after a material code diff (default: ≥4 code files or ≥120 code lines). Documentation/artifact-only and small diffs stay quiet. The note may mention verification for a substantial UI diff, improvement review for a large diff, and the Change Log approval gate—but explicitly forbids auto-running `/verify` or `/improve`. Claude + Codex (`systemMessage`); Cursor (`followup_message` on `stop`, `loop_limit:1`). |
| `load-memory.sh` | session start | Injects a pointer to your **out-of-tool** memory stores (Hermes `~/.hermes/`, OpenClaw `~/.openclaw/workspace/`, project `MEMORY.md`/`memory/`) so the agent reads them before personal tasks. Lists only stores that exist; silent otherwise. Never blocks. Claude (`additionalContext`) + Cursor (`additional_context`) — the tools with SessionStart injection. Complements Claude's native auto-memory (`~/.claude/projects/<project>/memory/`), which it doesn't duplicate. |
| `precompact-archive.sh` | before compaction (PreCompact) | Copies the **raw transcript** to `<log-dir>/transcripts/` before Claude compacts (and silently drops detail), and logs a `PreCompact` audit record. The platform forbids context injection here, so it preserves the record on disk rather than curating it. Never blocks. Claude only. |
| `log-session-end.sh` | session end (SessionEnd) | Appends a `SessionEnd` audit record with the end reason (`clear`/`logout`/`prompt_input_exit`/`resume`/`other`), closing the trail the SessionStart loader opened. Output is ignored by the platform — pure observability. Claude only. |
| `scorecard-enqueue.sh` | session end (SessionEnd) | Queues the just-ended session for a **scorecard survey** — only non-trivial sessions (≥`AI_SCORECARD_MIN_EVENTS`, default 20 audit records), never `resume` ends, never sessions already rated or dismissed. Markers expire after `AI_SCORECARD_TTL` (default 2 h). Claude only; never blocks. |
| `scorecard-survey.sh` | session start | If a fresh (< 2 h), unanswered marker matches this cwd, injects a 30-second survey ask: **rating 1–5, why, what to do differently**. Dismissal is effortless (skip or just start working) and an ignored survey stops appearing after `AI_SCORECARD_MAX_OFFERS` (default 2). Claude + Cursor. |
| `scorecard.sh` | *(not event-wired — run by the agent)* | Records the survey answers: rating → `<log-dir>/scorecards/scorecards.jsonl`, lesson → the memoryOS `LESSONS.md` (see below), plus a `Scorecard` audit record. Also `dismiss`, `pending`, `stats`, `path`. |
| `memory-os.sh` | *(sourced library)* | Resolves the machine's **memoryOS** from the `~/.ai/memory-os` registry (Hermes → `~/.hermes/memories/LESSONS.md`; markdown/Obsidian dir → `<dir>/LESSONS.md`; fallback `~/.ai-memory/`) and appends lessons to it. |

### Session scorecard survey (the feedback loop)

Capture → evaluate → feed back, with **you** as the evaluator — no LLM calls,
no background jobs:

1. **SessionEnd** — `scorecard-enqueue.sh` drops a pending marker for a
   non-trivial session under `<log-dir>/scorecards/pending/`.
2. **Next SessionStart** (in the same directory, within 2 hours) —
   `scorecard-survey.sh` asks the agent to run a basic survey: rate the previous
   session 1–5, why, and what to do differently. Skipping is one word; two
   ignored offers and the marker deletes itself.
3. **Record** — the agent runs `scorecard.sh record …`. The rating lands in
   `scorecards.jsonl` (`scorecard.sh stats` for trends); the lesson is appended
   to the memoryOS **`LESSONS.md`** named by the `~/.ai/memory-os` registry
   (written by `../setup-memory-os.sh`; auto-detects Hermes, falls back to a
   plain markdown store at `~/.ai-memory/`). Lessons live in a file this
   project owns — a store's own curated files (e.g. Hermes
   `memories/MEMORY.md`) are never written.
4. **Feed back** — `load-memory.sh` injects the most recent lessons
   (`AI_LESSONS_INJECT`, default 8) at every SessionStart, so what you asked
   for after past sessions reaches the next one.

Disable the whole loop with `AI_SCORECARD=0`. Survey data is user data:
`uninstall.sh` removes the hooks but leaves `scorecards/`, `LESSONS.md`, and
the `~/.ai/memory-os` registry in place.

### Skip marker (suppressing the advisory)

The quality advisory honors one **consume-once** skip file in `$AI_NUDGE_STATE`
(default `~/.ai-logs`): `.nudge-skip-quality.<key>`, where `<key>` is
`printf '%s' "$cwd" | cksum | cut -d' ' -f1`. The agent drops it when applying
changes already approved from a prior review, so that work does not produce a
redundant quality note. The one-liner lives in the `template.md` **"When to
verify & improve"** section:

```
d="${AI_NUDGE_STATE:-$HOME/.ai-logs}"; k="$(printf '%s' "$PWD" | cksum | cut -d' ' -f1)"
mkdir -p "$d"; touch "$d/.nudge-skip-quality.$k"
```

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
| **Claude Code** | `~/.claude/settings.json` | `SessionStart`, `PreToolUse` (`Edit\|Write\|MultiEdit\|NotebookEdit`, `Bash`), `PostToolUse`, `PreCompact`, advisory `Stop`, `SessionEnd` | guards: exit 2 + stderr; advisory: `continue:true` + `systemMessage` |
| **Codex** | `~/.codex/hooks.json` | `PreToolUse` (`apply_patch\|Edit\|Write`, `Bash`), `PostToolUse`, advisory `Stop` | guards: exit 2 + stderr; advisory: `continue:true` + `systemMessage` |
| **Cursor** | `~/.cursor/hooks.json` (`version: 1`) | `sessionStart`, `beforeShellExecution`, `beforeReadFile`, `afterFileEdit`, advisory `stop` | stdout `{"permission":"deny"}` for guards; advisory: `followup_message` on `stop` (`loop_limit:1`) |
| **Antigravity** | `~/.gemini/antigravity-cli/hooks.json` | `PreToolUse` (`run_command`, `write_to_file\|replace_file_content\|multi_replace_file_content`), `PostToolUse` | stdout `{"allow_tool":false,"deny_reason":…}` + **exit 0** |

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
  (`../install-settings.sh cursor`), not the hook. Cursor's quality Stop hook uses
  `followup_message` with `loop_limit:1`; the script also honors `loop_count` so
  the advisory cannot chain into further auto-continues.
- **Antigravity**'s config lives at `~/.gemini/antigravity-cli/hooks.json` — the
  `~/.gemini/` prefix is a historical artifact of the retired Gemini CLI sharing
  that vendor directory; Antigravity is a separate tool with its own schema.
  `antigravity` is in the **default target set**, and
  `./install-hooks.sh antigravity` skips gracefully if `~/.gemini/antigravity-cli`
  isn't present. Its schema (verified against the `agy` binary's proto + embedded
  docs) differs from every other tool: top-level **named hooks**, `PreToolUse`/
  `PostToolUse` events, **tool-name matchers** (`run_command`, and the edit trio
  `write_to_file|replace_file_content|multi_replace_file_content`), tool input
  under **`toolCall.args`** (`CommandLine`/`TargetFile`), and a stdout deny of
  **`{"allow_tool":false,"deny_reason":…}` with exit 0** (a non-zero exit is a hook
  *failure*, not a block). Because `agy` invokes each hook by absolute path, the
  installer drops tiny `*.ag.sh` wrappers that set `HOOK_PLATFORM=antigravity`.
  The commands/permissions layers don't apply (Antigravity has its own
  slash-command and `permissions.allow/deny` models), so `install-commands.sh`/
  `install-settings.sh` skip it with a note. **Note:** the schema and the hook
  scripts' output are verified, but live deny-firing must be confirmed in an
  interactive `agy` session — headless `agy -p` (print mode) does not invoke the
  interactive hook path, so it can't demonstrate a block. Two `agy`-specific
  details are handled: tool args arrive as JSON-encoded strings (so a wrapped
  quote pair is stripped before matching), and the `*.ag.sh` wrappers resolve the
  real script via `$0` rather than embedding `$HOME` (safe with spaces/quotes in
  the path). As with every guard here it is **fail-open on error** — a missing
  `jq`, unparseable input, or a script crash lets the tool through (exit 0 / no
  deny), never fail-closed; it's a best-effort tripwire, not a boundary.
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
