# Portable AI instruction set

A single, tool-agnostic instruction set for any AI coding assistant — Claude
Code, Codex, Gemini, Cursor, and anything else that reads a `CLAUDE.md` /
`AGENTS.md` / `GEMINI.md` style file. Write your preferences once; use them
everywhere.

It's a **template + a customizer**. The template holds the wording; a short
script asks you a few questions and renders finalized file(s) for your context.
Nothing is hardcoded to any one person or machine.

## What's here

| File | Purpose |
|------|---------|
| `template.md` | Source of truth. Wording + `{{vars}}` + toggleable `<!--SECTION:x-->` blocks. |
| `customize.sh` | Asks questions, fills the template, writes the finalized file(s). |
| `my-context.env.example` | Copy to `my-context.env` (gitignored) to save your answers. |
| `sync.sh` | Mirror a rendered `AGENTS.md` to `CLAUDE.md` / `GEMINI.md` in this dir. |
| `commands/` + `install-commands.sh` | Slash-command shortcuts (`/ship`, `/save`, `/pr`, `/sync`, `/tidy`) → `~/.claude/commands/`. |
| `hooks/` + `install-hooks.sh` | Claude Code guardrail hooks (auto-format, block protected paths, block dangerous shell) → merged into `settings.json`. |

Rendered output (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`), your `my-context.env`,
and `mcp-rules.local` are **gitignored** — they're personal, generate them locally.

The three pieces are independent: instructions (model-facing), commands (prompt
shortcuts), and hooks (deterministic enforcement). Install whichever you want.

## Quick start

```bash
# 1. (optional) save your answers so you don't retype them
cp my-context.env.example my-context.env && $EDITOR my-context.env

# 2. generate your instructions
./customize.sh                 # interactive: asks questions, then writes files
# or, non-interactive:
./customize.sh --print         # render to stdout
./customize.sh --project       # write AGENTS.md + CLAUDE.md + GEMINI.md here
```

Then point your tools at the result — copy the file in, or choose the
"global config" output target to write `~/.claude/CLAUDE.md`, `~/AGENTS.md`,
`~/.codex/AGENTS.md`, and `~/.gemini/GEMINI.md`.

## What it asks

- **Who you are** — name, pronouns, role, timezone.
- **Your environment** — asked, never assumed (headless server, laptop with a
  browser, whatever you describe).
- **How you preview/test web & HTML work** — Tailscale, local, or none. The
  HTML-artifact preference stays either way; only the *serving* method changes.
- **How you like work done** — autonomy posture; whether to encourage agent
  teams (and which roles you draw from); subagents for long, decomposable work.
- **Which sections to include** — memory-OS discovery, output artifacts,
  encouraging project-specific instructions, docs-first, correction capture.

## Customize the wording

Edit `template.md` and re-run `customize.sh`. Add a new optional block by
wrapping it in `<!--SECTION:name-->` … `<!--/SECTION:name-->` and adding a
matching toggle in `customize.sh`.
