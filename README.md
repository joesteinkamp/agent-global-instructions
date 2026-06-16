# Portable AI harness

A tool-agnostic harness for any AI coding assistant — Claude Code, Codex,
Antigravity/Gemini, Cursor, and anything else that reads a `CLAUDE.md` /
`AGENTS.md` / `GEMINI.md` style file. Write your preferences once; use them
everywhere. Nothing is hardcoded to any one person or machine.

It comes in four independent parts — use any subset:

1. **Instructions** (model-facing) — a customizable `template.md` rendered into
   per-tool instruction files. *Advice* the assistant should follow.
2. **Commands** — slash-command shortcuts (`/ship`, `/save`, `/pr`, `/sync`,
   `/tidy`, `/improve`) for repeatable workflows.
3. **Guardrails & observability** (hooks) — auto-format, block edits to
   generated/sensitive paths, trip on catastrophic shell, and log every tool
   call to JSONL. *Enforcement* the model can't skip.
4. **Validation** — a multi-role review team you run after big changes
   (`/improve`), plus a Stop hook that nudges you to run it.

## What's here

| File | Purpose |
|------|---------|
| `template.md` | Source of truth for the instructions. Wording + `{{vars}}` + toggleable `<!--SECTION:x-->` blocks. |
| `customize.sh` | Asks questions (or reads `my-context.env`), fills the template, writes the finalized file(s). Also `--scan-mcp`. |
| `my-context.env.example` | Copy to `my-context.env` (gitignored) to save your answers. |
| `examples/` | Two finished sample renders + the `.env` inputs that reproduce them. |
| `commands/` + `install-commands.sh` | Slash commands → `~/.claude/commands/`. |
| `hooks/` + `install-hooks.sh` | Guardrail + observability hooks → merged into each tool's config (Claude / Codex / Gemini). |
| `audit.sh` | Read back the tool-call audit log — timeline, stats, or live tail. |
| `sync.sh` | Mirror a rendered `AGENTS.md` to `CLAUDE.md` / `GEMINI.md` in this dir. |
| `sync-global.sh` | Keep the hand-maintained **global** files in sync (`~/.claude/CLAUDE.md` → the others), backing up differences. |
| `test.sh` | 30 smoke tests: render engine, the `load_env` parser, example reproducibility, and installer smoke tests. |

Rendered output (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`), your `my-context.env`,
`mcp-rules.local`, and `review/` artifacts are **gitignored** — they're personal,
generate them locally. Want to see finished output first? Read
[`examples/aggressive-tailscale.md`](examples/aggressive-tailscale.md) (aggressive
autonomy, Tailscale serving, all sections on) or
[`examples/balanced-local.md`](examples/balanced-local.md) (balanced autonomy,
local serving, validate + tools off).

## Quick start

```bash
# 1. (optional) save your answers so re-running is zero-prompt
cp my-context.env.example my-context.env && $EDITOR my-context.env

# 2. (optional) detect your MCP servers and add per-server usage rules
./customize.sh --scan-mcp      # writes mcp-rules.local (gitignored)

# 3. generate + install the instructions machine-wide
./customize.sh --global        # ~/.claude/CLAUDE.md, ~/AGENTS.md,
                               # ~/.codex/AGENTS.md, ~/.gemini/GEMINI.md

# 4. (optional) install the commands and hooks
./install-commands.sh          # /ship, /save, ... in Claude Code
./install-hooks.sh             # guardrails + logging across all tools
```

Other render targets:

```bash
./customize.sh                 # interactive: asks questions, then writes
./customize.sh --print         # render to stdout (writes nothing)
./customize.sh --project       # write AGENTS.md + CLAUDE.md + GEMINI.md here
```

All non-interactive modes read your saved `my-context.env`.

## 1. The instruction set

`customize.sh` asks (or reads from `my-context.env`):

- **Who you are** — name, pronouns, role, timezone.
- **Your environment** — asked, never assumed (headless server, laptop with a
  browser, …). Leave blank to omit the line.
- **How you preview/test web & HTML work** — Tailscale, local, or none. The
  HTML-artifact preference stays either way; only the *serving* method changes.
- **How you like work done** — autonomy posture (aggressive/balanced); whether
  to encourage agent teams (and which roles); subagents for long work.
- **Which sections to include** — memory-OS discovery, agent teams,
  validate-after-larger-changes, tools & MCP servers, output artifacts,
  project-specific instructions, docs-first, correction capture.

## 2. Commands

Portable prompt shortcuts. `./install-commands.sh` copies them to
`~/.claude/commands/`; the bodies are plain enough to reuse in Codex/Cursor.

| Command | Does |
|---------|------|
| `/ship` | Stage → commit → push, and on a feature branch open + **merge** the PR (squash, delete branch), then return to default. The all-in-one. |
| `/save` | Quick checkpoint: commit + push, no PR. |
| `/pr` | Open a PR with a generated title/body — stops before merge. |
| `/sync` | Fetch + rebase the current branch on the latest default branch. |
| `/tidy` | Run the project's formatter/linter/tests and fix what's safe. |
| `/improve` | Spin up a multi-role review team on the recent diff (architect, back-end, front-end, +UI/UX) for prioritized improvement opportunities. |

## 3. Guardrails & observability (hooks)

One set of scripts serves **Claude Code, Codex, and Antigravity/Gemini** — a
`HOOK_PLATFORM` env var (set by the installer) makes each block in the right
dialect (exit-2 for Claude/Codex, a `{"decision":"deny"}` JSON for Gemini).
`./install-hooks.sh [claude|codex|gemini]` merges them into each tool's config
(idempotent, backs up first). Full detail in [`hooks/README.md`](hooks/README.md).

| Hook | Fires | Does |
|------|-------|------|
| `guard-paths` | before edits | Block edits to `build/ dist/ .next/ node_modules/ .git/`, `.env*`, lockfiles (resolves `..`/symlinks first). |
| `guard-bash` | before shell | Trip on catastrophic `rm -r` (root/home/parent) and force-pushes. Best-effort tripwire, not a sandbox. |
| `format-edited` | after edits | Auto-format the edited file with the project's Prettier/ESLint. |
| `log-tool` | every tool call | **Observability** — append one JSONL record per tool event (secrets redacted, log is `0600`). |
| `validate-nudge` | turn end | When a turn ends with a large diff, nudge you to run `/improve` (once per distinct diff). |

Read the audit trail with `./audit.sh` (`--stats`, `--follow`, `-n N`). The log
lives at `~/.ai-logs/tool-calls.jsonl` (`$AI_TOOL_LOG`); set `AI_LOG_RESPONSES=0`
to drop tool responses.

## 4. Validation

After a larger change, run a review team to find improvement opportunities
before calling the work done:

- **`/improve`** spins up parallel subagents — technical architect, back-end,
  front-end, and a UI/UX lens when UI changed — each returning concrete,
  prioritized fixes with `file:line`, then deduped into one summary.
- **`validate-nudge`** (Stop hook, Claude + Codex) reminds you to run it when a
  turn ends with a diff over `VALIDATE_MIN_FILES`/`VALIDATE_MIN_LINES`
  (default 8 files / 200 lines), firing once per distinct diff.

## Updating over time

Rendered files are snapshots. After you improve `template.md` (or pull this
repo), re-render — your answers live in `my-context.env`, so it's one command:

```bash
git pull
./customize.sh --global        # zero prompts when my-context.env exists
./install-commands.sh && ./install-hooks.sh   # if the scripts changed
```

## For teams

The committed `template.md` is the **shared baseline**; each person's gitignored
`my-context.env` is their **personal layer**. Fork the repo, edit `template.md`
to encode team norms, and everyone runs `./customize.sh --global` with their own
answers.

## Customize the wording

Edit `template.md` and re-run `customize.sh`.

- **Add an optional block:** wrap it in `<!--SECTION:name-->` …
  `<!--/SECTION:name-->` (one marker per line) and add a matching `keep` toggle
  in `customize.sh`'s `render()`. `test.sh` asserts every section is wired in.
- **Add an inline `{{VAR}}`:** reference it in the template and add its name to
  the `SUBST_VARS` list near the top of `customize.sh` (that one list drives the
  value passthrough and the substitution). Add it to `my-context.env.example`
  too if users should set it.
- **Add a multi-line block var** (like `{{MEMORY_PATHS}}` / `{{MCP_RULES}}`):
  put the placeholder alone on its own line and handle it with a
  `line == "{{X}}"` branch in `render()`, not `SUBST_VARS`.

Run `./test.sh` after any change.

## Notes

- `my-context.env` is **parsed, not executed** — only known `KEY=VALUE` keys are
  read (no sourcing), so a stray command in it can't run. Values may be
  single/double quoted and span multiple quoted lines.
- Renders and config merges are **atomic** (temp file + move) and back up an
  existing file before overwriting (keeping the 5 newest backups).
- The hooks are a **best-effort safety net, not a security boundary** — they see
  a tool's structured input and match heuristically. See `hooks/README.md`.
- Needs **bash 4+** (macOS ships 3.2: `brew install bash`) and `jq` for the MCP
  scanner and the hook installers.

## License

[MIT](LICENSE) — copy it, fork it, make it yours.
