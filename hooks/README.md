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
| `worktree-reap.sh` | turn end (Stop) · CLI | Removes worktrees whose branch is **provably merged** (git ancestry, or a forge-merged PR whose head SHA matches this tip) and prunes registrations whose directory is already gone, then emits one **non-blocking advisory** naming what it reaped and what it left and why. A fresh branch, a tree holding ignored files it cannot regenerate, and anything inside the cooling window are never touched. Rate-limited per repo (`WORKTREE_REAP_MIN_INTERVAL`, default 900s). Also the sweep CLI installed at `~/.ai/worktree-sweep.sh` (`--sweep [--apply] [--all <dir>] [--json]`). Claude + Codex (`systemMessage`); Cursor (`followup_message` on `stop`, `loop_limit:1`). See the safety model below. |
| `load-memory.sh` | session start | Injects a pointer to your **out-of-tool** memory stores (Hermes `~/.hermes/`, OpenClaw `~/.openclaw/workspace/`, project `MEMORY.md`/`memory/`) so the agent reads them before personal tasks. Lists only stores that exist; silent otherwise. Never blocks. Claude and Codex (`hookSpecificOutput.additionalContext` — the same wire shape) + Cursor (`additional_context`); Antigravity has no SessionStart event. Complements Claude's native auto-memory (`~/.claude/projects/<project>/memory/`), which it doesn't duplicate. |
| `precompact-archive.sh` | before compaction (PreCompact) | Copies the **raw transcript** to `<log-dir>/transcripts/` before Claude compacts (and silently drops detail), and logs a `PreCompact` audit record. The platform forbids context injection here, so it preserves the record on disk rather than curating it. Never blocks. Claude only. |
| `log-session-end.sh` | session end (SessionEnd) | Appends a `SessionEnd` audit record with the end reason (`clear`/`logout`/`prompt_input_exit`/`resume`/`other`), closing the trail the SessionStart loader opened. Output is ignored by the platform — pure observability. Claude only. |
| `autonomy-reminder.sh` | session start | Injects a one-paragraph reminder that the tool supports both `/goal <condition>` (keeps taking turns until an evaluator judges the condition met — the right one when the work has a verifiable end state) and `/loop` (a recurring check on a cadence), so ongoing requests (watch, babysit, keep-green) get the right one with an explicit done-condition instead of a dead-end handoff. Advisory context only — never starts anything, and the rendered instructions carry the full rules (gates apply inside every iteration and every goal turn). Wired **only under the aggressive autonomy posture** (`install-hooks.sh` asks `customize.sh --autonomy`; flipping to balanced prunes it on re-install). Claude and Codex (`hookSpecificOutput.additionalContext` — the same wire shape) + Cursor (`additional_context`); Antigravity has no SessionStart injection and the hook exits silently there. Codex matters most here: `/goal` is stable and on by default in it. |
| `memory-os.sh` | *(sourced library)* | Resolves the machine's **memoryOS** from the `~/.ai/memory-os` registry (Hermes → `~/.hermes/memories/LESSONS.md`; markdown/Obsidian dir → `<dir>/LESSONS.md`; fallback `~/.ai-memory/`) and appends lessons to it. |

### Session lessons (the feedback loop)

A session rating survey used to feed this: it queued a marker at SessionEnd and
offered a 1–5 survey at the next SessionStart. **It was removed on 2026-09-06**
— across six weeks it produced 23 records, 22 of them `dismissed:true` and one
completed lesson. An instrument with a 4% response rate is not collecting
evidence, it is only asking.

What survives is the half that worked: **the memoryOS lesson store**.
`load-memory.sh` reads the most recent lines from it at SessionStart and injects
them, so what the user asked for after past sessions reaches the next one.
Lessons are now written when the user corrects the agent in-session — a
correction is more specific, more actionable, and free to collect — per the
resident instructions' "When I say you did something wrong" rule. The store's
location is resolved by `memory-os.sh` from the `~/.ai/memory-os` registry that
`setup-memory-os.sh` writes.

`uninstall.sh` removes the hooks but leaves `LESSONS.md` and
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

### Worktree reaping — the two-arm safety model

`worktree-reap.sh` deletes directories, so it is built around one rule: **only
proof of merge authorises a removal, and a likelihood never does.** Four things
that look like proof and are not are listed below, because each one of them
deleted real work in testing before it was closed.

**The auto-delete arm acts only on proof.** A branch qualifies when
`git merge-base --is-ancestor <branch> <default>` is true (a fast-forward or a
real merge commit landed), or when a forge reports a merged PR/MR **into the
default branch whose head commit is exactly this branch's tip** — `gh pr list
--state merged --head <branch> --base <default> --json headRefOid`, and the
`glab` equivalent. The forge arm is load-bearing rather than a nicety:
**a squash merge is not an ancestor of the default branch**, so an ancestry-only
check reaps nothing at all in a squash-merge flow, which is the failure this
hook exists to avoid. The SHA comparison is what keeps it honest — `ai/<agent>`
is a standing branch name that is recreated every run, so "a PR with this name
was merged once" says nothing about the tree in front of you.

**The advise-only arm never acts.** An upstream marked `gone` (what a
`--delete-branch` or a forge's auto-delete leaves behind) is reported as
`LIKELY-MERGED` with the exact command to run, and the command is never run —
a deleted upstream is also what an abandoned branch looks like.

**Never touched by either arm:**

- the main/primary worktree, and the worktree the caller is standing in
  (compared as physical paths, so a symlinked `/tmp` cannot defeat it);
- a `locked` worktree — the lock is honoured as recorded, with no pid-liveness
  check, because a lock legitimately outlives the process that took it;
- a tree with uncommitted or untracked changes, **or one holding ignored files
  it cannot regenerate**. `git status --porcelain` is blind to `.env`,
  `*.sqlite`, `my-context.env` and friends — and so is `git worktree remove`,
  which is why "let git refuse" is not sufficient on its own. Ignored paths are
  inspected: an all-regenerable set (`node_modules/`, `dist/`, `.venv/`,
  `__pycache__/`, …) clears the gate, anything else is `DIRTY` and the paths are
  named;
- a branch that never carried a commit of its own (`UNSTARTED`). Ancestry is
  reflexive: `git worktree add -b ai/<agent>` creates the branch **at** the
  default tip, so a brand-new agent tree is "merged" before any work exists.
  The branch's own reflog is the discriminator — `branch: Created from HEAD`
  with no `commit:` entry means it never began;
- anything younger than `WORKTREE_REAP_MIN_AGE` (`COOLING`). Agents are told to
  commit WIP often, which manufactures a clean, merged-looking sample seconds
  after every commit; the clock is what separates a live sibling tree from a
  finished one. The age is the newer of the branch tip's commit time and the
  tree's own activity, measured **before** this script probes the tree (a
  `git status` that refreshes the index would otherwise reset the clock it
  reads — hence `--no-optional-locks`, which also keeps the probe from writing
  into another agent's worktree);
- anything matching `WORKTREE_REAP_KEEP_RE`. A malformed pattern **aborts the
  whole sweep** (`grep -E` exits 2 on a bad pattern, which a naive caller reads
  as "no match" — a keep-list that fails open protects nothing);
- anything at all, in any repo whose default branch had to be guessed. Only
  `origin/HEAD` — or exactly one of `main`/`master`/`trunk` that is also what
  the primary worktree has checked out — counts as resolved; otherwise the
  sweep reports and deletes nothing.

Removal uses `git worktree remove` **without** `--force` and `git branch -d`
(not `-D`) so git itself is a second net. A refusal from `git branch -d` is a
**veto**, not a reason to escalate: `-D` runs only when a forge-merged PR's head
SHA still equals this branch's tip, which is the one case `-d` cannot recognise
(a squash). `git worktree prune` clears registrations whose directory is already
gone — not free, since the admin dir it drops carries that worktree's HEAD
reflog and `refs/worktree/*`, so it runs only under `--apply` and never during a
dry run.

Statuses, used verbatim in both the report and `--json`: `REAPABLE` `CURRENT`
`MAIN` `LOCKED` `DIRTY` `UNMERGED` `LIKELY-MERGED` `PRUNABLE` `KEEP`
`UNSTARTED` `COOLING`.

Knobs: `WORKTREE_REAP=auto|advise|off` (default `auto`; `advise` reports without
deleting, `off` silences the hook), `WORKTREE_REAP_MIN_INTERVAL` (seconds
between hook runs per repo, default 900), `WORKTREE_REAP_MIN_AGE` (cooling
window in seconds, default 86400 — **pass `0` from a command that just merged
the branch itself**, such as `/ship`), `WORKTREE_REAP_KEEP_RE` (ERE of worktree
paths to never touch). The rate-limit stamp lives in `$AI_NUDGE_STATE` (default
`~/.ai-logs`) as `.worktree-reap.<key>`, keyed on the repo's shared git dir so
every worktree of one repo shares one budget; where `flock` exists it also
serialises two agents ending a turn in the same repo at once. A repeated
identical advisory is suppressed.

The forge lookup is capped: at most 3 per sweep, 10s each, and **only where a
`timeout` binary exists** — without one, a degraded network would turn a Stop
hook into a multi-minute stall, so the forge arm is skipped entirely and the
result degrades to ancestry plus advice.

The same script is the CLI the commands call:

```
~/.ai/worktree-sweep.sh --sweep                 # dry-run report for this repo
~/.ai/worktree-sweep.sh --sweep --apply         # perform the safe removals
~/.ai/worktree-sweep.sh --sweep --all ~/projects --json
```

`--sweep` on its own writes nothing — `--apply` is what acts. `install-hooks.sh`
installs that copy; `uninstall.sh` removes it.

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
