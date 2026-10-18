# The AI harness for design teams

**For designers, design engineers, and design managers.** One install gives
every AI coding tool you use — Claude Code, Codex, Antigravity, and Cursor —
the same instructions and the same agent roles, rendered from one template,
plus the same skills in Claude Code, Codex and Cursor (Antigravity has no
skill install yet). You edit one file, run one command, and every tool is
regenerated in sync.

It is one harness for everyone on the team, engineering tooling included:
worktrees, `/ship`, cross-vendor review and model routing come with it for a
designer as much as for an engineer. The one thing your role changes is the
agent team you start from — set `PERSONA` to `designer`, `design-engineer`, or
`design-manager` and the instructions open each team with that role's lenses.
Everything else renders the same.

## Design-team skills

Six skills built for design work, in Claude Code, Codex (`$<name>`), and
Cursor. Each says which inputs and sources it found and which it didn't, and
its main output is an HTML report:

- **`/critique`** — open feedback on work in progress: what's working, what to
  explore. `/critique --gate` reviews it against whichever briefs and
  `guardrails/` the project has.
- **`/figma-parity`** — a built screen against its Figma node and the tokens →
  a drift report.
- **`/handoff`** — a prototype → a spec engineers can build from: states,
  tokens, edge cases, a11y.
- **`/research-synthesis`** — notes and transcripts → themes, each backed by
  evidence.
- **`/one-on-one`** — 1:1 and feedback prep from your connected sources. Read
  only apart from an optional Gmail draft; never sends.
- **`/team-digest`** — what shipped, what's blocked, and what's next, from your
  connected sources. Read only.

## Quick start

Requirements: git, bash 3.2+ (macOS' stock bash works), and `jq` (for the
hook and settings installers).

```bash
git clone <this repo> && cd agent-global-instructions
cp my-context.env.example my-context.env && $EDITOR my-context.env
                               # your answers — every render and re-run reads them
./install.sh                   # instructions + roles + hooks + settings for all
                               #   four tools (Claude, Codex, Cursor, Antigravity),
                               #   skills for the first three (asks once; --yes skips)
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
- **Skills** — the same workflow skills in Claude Code, Codex, and Cursor:
  the six design-team skills above, plus `/ship`, `/sync`, `/worktrees`,
  `/grill-me`, `/improve`, `/verify`, `/update-model-routing`, and `/ux-audit`.
  The full list is in [`skills/README.md`](skills/README.md).
- **Agent teams** — the instructions make a **team of specialized agents the
  default** for anything with more than one dimension, with the roster derived
  from the task, a starting set of lenses picked by your `PERSONA`, and a
  `refuter` lens on every conclusion. A `design-manager` role (feedback
  quality, review rigor, staffing) ships alongside the design and engineering
  roles. The roles ship as real
  definitions in each tool's own format (`~/.claude/agents`, `~/.codex/agents`,
  `~/.cursor/agents`, `~/.gemini/config/agents`) from one canonical source, so a role behaves the same in every tool — and the
  install turns Claude Code's team construct on, since it's off by default.
- **Local models** — machines serving local models (Ollama, llama.cpp,
  MLX, or a remote box over your tailnet — all one OpenAI-compatible contract)
  get them auto-registered at `~/.ai/local-models` and wired into cross-tool
  delegation behind the `lm` shim; machines without any get a clean no-op.
- **Guardrails** — hooks that block edits to generated/sensitive paths, trip on
  catastrophic shell, auto-format edits, log every tool call, and reap the
  worktrees whose branches are provably merged (never the dirty, unmerged,
  locked or current ones).
- **Long autonomy** (aggressive posture) — the instructions teach every tool to
  keep long work alive with the right primitive for its stopping rule: `/goal
  <condition>` when the work has a verifiable end state (Claude Code and Codex;
  Cursor is still rolling it out), `/loop` when it is only a recurring check
  (Claude Code, Cursor) — both behind an explicit done-condition. The install
  seeds `~/.claude/loop.md` (bare `/loop`'s default maintenance prompt) and a
  session-start reminder hook. Confirmation gates apply unchanged inside every
  iteration and every goal turn.
- **Session lessons** — corrections you make in-session are written to your
  memoryOS (Hermes, Obsidian, or plain markdown — `setup-memory-os.sh`) and read
  back at every session start, so a correction lands once and holds.
- **Permissions and actionable notifications** — each tool's native enforcement
  backs the hooks with rules the model can't bypass. On Codex, native TUI alerts
  cover real approval prompts when an enabled Warp integration is detected;
  Warp continues to announce completed turns without its premature pre-routing
  permission toast.

Full detail on every layer: **[docs/GUIDE.md](docs/GUIDE.md)**. Finished sample
renders: [`examples/`](examples/). Where this is going next:
**[docs/ROADMAP.md](docs/ROADMAP.md)**.

## Your three personal layers

All gitignored; all survive every re-render and `git pull`:

| File | Holds |
|------|-------|
| `my-context.env` | Your answers (name, role, `PERSONA`, preview method, section toggles). Copy from `my-context.env.example`. |
| `extras.local.md` | Personal Markdown sections the shared template can't express (e.g. machine-specific serving notes) — spliced into every render. |
| `mcp-rules.local` | Per-MCP-server "when to use" rules; generate with `./customize.sh --scan-mcp`. |

**Never edit the rendered files** (`CLAUDE.md`, `AGENTS.md` in this repo, or
the machine-wide `~/AGENTS.md` and its per-tool pointers) —
they're snapshots. The installer catches a hand edit and saves it rather than
losing it, and asks what to do when you're at a terminal
([details](docs/GUIDE.md#when-youve-edited-an-installed-file)), but the
durable place for a change is the template or one of the layers above.

## For your team

This is how you bake the harness into everyone's process:

1. **Fork the repo** and edit `template.md` to encode team norms.
2. **Commit a `team-context.env`** — the shared answer baseline (preview
   method, section defaults, team roles).
3. Everyone clones, answers the handful of personal questions
   (`./customize.sh`), and runs `./install.sh`. Personal `my-context.env`
   values override the team baseline key by key.

Onboarding a new designer, design engineer, or design manager is: clone, set
`PERSONA`, answer a handful of questions, done.

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
