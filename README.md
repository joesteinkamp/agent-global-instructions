# Portable AI harness

**Write your AI-assistant preferences once; use them in every tool.** Claude
Code, Codex, Antigravity, and Cursor each read their own `CLAUDE.md` /
`AGENTS.md` instruction file — maintain them by hand and you re-teach every
tool your name, your environment, and how you like to work, and the files
drift out of sync. Here you edit one template, run one command, and every
tool is regenerated in sync.

## Quick start

Requirements: git, bash 3.2+ (macOS' stock bash works), and `jq` (for the
hook and settings installers).

```bash
git clone <this repo> && cd agent-global-instructions
cp my-context.env.example my-context.env && $EDITOR my-context.env
                               # your answers — every render and re-run reads them
./install.sh                   # instructions + commands + hooks + settings,
                               #   for all four tools: Claude, Codex, Cursor,
                               #   Antigravity (asks once; --yes skips)
```

That's it. Prefer answering questions to editing a file? `./customize.sh` runs
an interactive interview (a handful of questions; Enter accepts the recommended
setup) — note its answers apply to that render only, so save durable ones in
`my-context.env`. Preview first with `./customize.sh --print` (writes nothing).
Undo everything with `./uninstall.sh` (configs backed up; instruction files
left in place).

## What you get

- **Instructions** — one `template.md` rendered into every tool's instruction
  file: who you are, how you like to work, design standards (on for everyone),
  memory, artifacts.
- **Commands** — the same slash commands in all four tools: `/ship`, `/sync`,
  `/worktrees`, `/grill-me`, `/improve`, `/verify`, `/update-model-routing`,
  `/ux-audit`.
- **Guardrails** — hooks that block edits to generated/sensitive paths, trip on
  catastrophic shell, auto-format edits, and log every tool call.
- **Session scorecard** — after a real session ends, the next session opens with
  a 30-second survey (rate it 1–5, why, what to do differently); lessons land in
  your memoryOS (Hermes, Obsidian, or plain markdown — `setup-memory-os.sh`)
  and are read back at every session start.
- **Permissions** — each tool's native enforcement (deny rules, sandbox,
  policy engine) backing the hooks with rules the model can't bypass.

Full detail on every layer: **[docs/GUIDE.md](docs/GUIDE.md)**. Finished sample
renders: [`examples/`](examples/).

## Your three personal layers

All gitignored; all survive every re-render and `git pull`:

| File | Holds |
|------|-------|
| `my-context.env` | Your answers (name, role, preview method, section toggles). Copy from `my-context.env.example`. |
| `extras.local.md` | Personal Markdown sections the shared template can't express (e.g. machine-specific serving notes) — spliced into every render. |
| `mcp-rules.local` | Per-MCP-server "when to use" rules; generate with `./customize.sh --scan-mcp`. |

**Never edit the rendered files** (`CLAUDE.md`, `AGENTS.md` in this repo, or
the machine-wide `~/AGENTS.md` and its per-tool pointers) —
they're snapshots, overwritten on the next render. Put the change in the
template or one of the layers above instead.

## For your team

This is how you bake the harness into everyone's process:

1. **Fork the repo** and edit `template.md` to encode team norms.
2. **Commit a `team-context.env`** — the shared answer baseline (preview
   method, section defaults, team roles).
3. Everyone clones, answers the handful of personal questions
   (`./customize.sh`), and runs `./install.sh`. Personal `my-context.env`
   values override the team baseline key by key.

Onboarding a new designer or knowledge worker is: clone, answer a handful of
questions, done.

## Updating over time

Rendered files are snapshots. After you improve `template.md` (or pull this
repo), re-render — your answers and extras are separate files, so it's one
command:

```bash
git pull
./install.sh --yes             # re-render + re-install every layer, zero prompts
```

## License

[MIT](LICENSE) — copy it, fork it, make it yours.
