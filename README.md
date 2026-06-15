# Portable AI instruction set

A single, tool-agnostic instruction set for any AI coding assistant — Claude
Code, Codex, Gemini, Cursor, and anything else that reads a `CLAUDE.md` /
`AGENTS.md` / `GEMINI.md` style file. Write your preferences once; use them
everywhere.

It's a **template + a customizer**. The template holds the wording; a short
script asks you a few questions and renders finalized file(s) for your context.
Nothing is hardcoded to any one person or machine.

Three layers, all optional and independent — pick what you want:

- **Instructions** (model-facing) — *advice* the assistant should follow.
- **Commands** (`/ship`, `/save`, …) — *shortcuts* for repeatable workflows.
- **Hooks** (auto-format, path/shell guards, audit log) — *enforcement* the tool
  can't skip, plus observability.

## What's here

| File | Purpose |
|------|---------|
| `template.md` | Source of truth. Wording + `{{vars}}` + toggleable `<!--SECTION:x-->` blocks. |
| `customize.sh` | Asks questions, fills the template, writes the finalized file(s). |
| `my-context.env.example` | Copy to `my-context.env` (gitignored) to save your answers. |
| `examples/` | Two finished sample renders so you can see the output without running anything. |
| `sync.sh` | Mirror a rendered `AGENTS.md` to `CLAUDE.md` / `GEMINI.md` in this dir. |
| `sync-global.sh` | Keep the hand-maintained **global** files in sync — copy `~/.claude/CLAUDE.md` to `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`, `~/AGENTS.md` (backs up differences). |
| `commands/` + `install-commands.sh` | Slash-command shortcuts (`/ship`, `/save`, `/pr`, `/sync`, `/tidy`, `/validate`) → `~/.claude/commands/`. |
| `hooks/` + `install-hooks.sh` | Guardrail hooks (auto-format, block protected paths, block dangerous shell) + **observability** (log every tool call to JSONL) for **Claude Code, Codex, and Antigravity/Gemini** → merged into each tool's config. |
| `audit.sh` | Read back the tool-call audit log — timeline, stats, or live tail. |
| `test.sh` | Smoke tests for the render engine. |

Rendered output (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`), your `my-context.env`,
and `mcp-rules.local` are **gitignored** — they're personal, generate them
locally. Want to see what a finished file looks like first? Read
[`examples/aggressive-tailscale.md`](examples/aggressive-tailscale.md) (aggressive
autonomy, Tailscale serving, all sections on) or
[`examples/balanced-local.md`](examples/balanced-local.md) (balanced autonomy,
local serving, validate + tools sections off) — generated samples, not personal.

## Quick start

```bash
# 1. (optional) save your answers so re-running is zero-prompt
cp my-context.env.example my-context.env && $EDITOR my-context.env

# 2. (optional) detect your MCP servers and add per-server usage rules.
#    Writes mcp-rules.local (gitignored); the rules render only when the
#    "tools & MCP servers" section is included.
./customize.sh --scan-mcp

# 3. generate and install your instructions machine-wide
./customize.sh --global        # writes ~/.claude/CLAUDE.md, ~/AGENTS.md,
                               # ~/.codex/AGENTS.md, ~/.gemini/GEMINI.md
```

Prefer to drive it interactively, or write somewhere else?

```bash
./customize.sh                 # interactive: asks questions, then writes
./customize.sh --print         # render to stdout (don't write anything)
./customize.sh --project       # write AGENTS.md + CLAUDE.md + GEMINI.md here
```

`--global`, `--project`, `--print`, and `--scan-mcp` are all non-interactive and
read your saved `my-context.env`. The interactive run also offers a "custom file
path" target.

## Updating over time

Your rendered files are snapshots. When you improve `template.md` (or pull a new
version of this repo), re-render to pick up the changes:

```bash
git pull
./customize.sh --global        # zero prompts when my-context.env exists
```

Because your answers live in `my-context.env`, that's a one-command refresh.

## For teams

The split is designed for it: the committed `template.md` is your **shared
baseline**, and each person's gitignored `my-context.env` is their **personal
layer**. Fork the repo, edit `template.md` to encode team norms, and everyone
runs `./customize.sh --global` with their own answers.

## What it asks

- **Who you are** — name, pronouns, role, timezone.
- **Your environment** — asked, never assumed (headless server, laptop with a
  browser, whatever you describe). Leave it blank and the line is omitted.
- **How you preview/test web & HTML work** — Tailscale, local, or none. The
  HTML-artifact preference stays either way; only the *serving* method changes.
- **How you like work done** — autonomy posture; whether to encourage agent
  teams (and which roles you draw from); subagents for long, decomposable work.
- **Which sections to include** — memory-OS discovery, agent teams,
  validate-after-larger-changes, tools & MCP servers, output artifacts,
  project-specific instructions, docs-first, correction capture.

## Customize the wording

Edit `template.md` and re-run `customize.sh`.

- **Add an optional block:** wrap it in `<!--SECTION:name-->` …
  `<!--/SECTION:name-->` (name = letters, digits, `-`, `_`, one marker per line)
  and add a matching `keep` toggle in `customize.sh`'s `render()`. `test.sh`
  asserts every section is wired in.
- **Add an inline `{{VAR}}`:** reference it in the template and add its name to
  the `SUBST_VARS` list near the top of `customize.sh` — that one list drives
  both the value passed to `awk` and the substitution. Add it to
  `my-context.env.example` too if users should set it.
- **Add a multi-line block var** (like `{{MEMORY_PATHS}}` / `{{MCP_RULES}}`):
  these are different — put the placeholder alone on its own line and handle it
  with a `line == "{{X}}"` branch in `render()`, not `SUBST_VARS`.

Run `./test.sh` after any change to confirm nothing leaks and the lists agree.

## Notes

- `my-context.env` is **parsed, not executed** — only known `KEY=VALUE` keys are
  read, so a stray command in it can't run. Unrecognized or misspelled keys are
  silently ignored. Values may be single/double quoted and span multiple lines
  while quoted (the closing quote should end its line).
- Renders are written **atomically** (temp file in the destination dir + move),
  so a failed render never truncates or partially writes an existing file.
- `./customize.sh --global` overwrites the four machine-wide files without
  prompting (by design, so re-renders are scriptable) — it prints the paths
  first. Needs bash 4+ (macOS ships 3.2: `brew install bash`).

## License

[MIT](LICENSE) — copy it, fork it, make it yours.
