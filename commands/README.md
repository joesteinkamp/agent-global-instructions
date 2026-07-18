# Commands

Portable workflow shortcuts. Each top-level `.md` file is the canonical
(Claude-dialect) prompt. It runs as `/<name>` in command-capable tools and as
`$<name>` in Codex. Install them with
`../install-commands.sh` (all tools) or `../install-commands.sh claude cursor …`.

| Command | What it does |
|---------|--------------|
| `/ship` | Tidy gate (format/lint/test, stop if broken) → stage → commit → push, and on a feature branch open + **merge** the PR/MR (squash, delete branch), then return to default. Works with GitHub (`gh`) or GitLab (`glab`). The all-in-one. |
| `/sync` | Fetch + rebase the current branch on the latest default branch. |
| `/worktrees` | Set up one git worktree per parallel agent (`ai/<agent>` branches) and converge them into a single integration tree a lone dev server watches — so several models' changes show up near-live. Pairs with `converge.sh`. |
| `/tidy` | Run the project's formatter / linter / tests and fix what's safe (no commit). |
| `/improve` | Spin up a multi-role review team (architect, back-end, front-end, +UI/UX) on the recent diff to surface prioritized improvement opportunities, then tee them up as a ready-to-apply plan and offer to make the changes on your go-ahead. Nothing is edited until you approve. |
| `/verify` | Prove the change is correct & true to spec: build/test, drive the route in a headless browser (responsive screenshots, console/a11y gates, visual regression), and check it against the project briefs (`PRODUCT`/`DESIGN`/`CODE.md`). Writes a served HTML report, then proposes a fix for every FAIL as a ready-to-apply plan and offers to apply it on your go-ahead. Nothing is edited until you approve. |
| `/audit` | *(design)* UX audit **from a screenshot**. On Claude Code with the [`ux-audit`](https://github.com/joesteinkamp/ux-audit-skill) skill installed it scores against 15 UX heuristic frameworks with annotated screenshots; on the other tools (no skill support) it runs the heuristic rubric inline. Writes + serves a self-contained HTML report. |
| `/handoff` | *(design)* Developer handoff for a screen/route — component states, tokens used, a11y notes, and acceptance criteria — as a served HTML artifact. |
| `/critique` | *(design)* Pre-pixel heuristic critique of a flow, spec, or idea (the complement to `/audit`=screenshot and `/verify`=running app). Severity-ranked findings with principle citations; served HTML. |
| `/flow` | *(design)* Generate a user-flow / sitemap / journey-map artifact from a task or spec — inline diagram + journey table, served as HTML. |

Most take optional arguments, e.g. `/ship fix login redirect` uses that as the
commit message / PR title. In Codex, write `$ship fix login redirect`.

**Command groups.** A command opts into a group with `group: <name>` in its
frontmatter (absent ⇒ `core`, always installed). The **`design`** group above
(`/audit`, `/handoff`, `/critique`, `/flow`) installs when you pass `--design` to
`../install-commands.sh`, or automatically when your persona / `INC_DESIGN` wants
it (it asks `customize.sh --design-group`); `--no-design` forces it off and prunes
any already installed, so flipping your persona self-heals. Ports are always
generated for every command — the group only decides what gets **installed**.

**Format:** the top-level `.md` files are Claude Code command files — frontmatter
(`description`, `argument-hint`, `allowed-tools`, optional `group`) plus a prompt
body that embeds shell output with `` !`cmd` `` and arguments with `$ARGUMENTS`.
They are the **single source of truth** — edit here only.

**Ports are generated, never hand-edited.** `../render-commands.sh` translates the
canonical files into each tool's dialect under `codex/`, `cursor/`, `gemini/`
(generated snapshots; `../install-commands.sh` re-renders on every install, so a
hand-edit to a port never reaches your tools):

- `codex/<name>/SKILL.md` → `~/.codex/skills/<name>/SKILL.md` (invoke
  `$<name>`); this uses Codex’s supported Skills mechanism. It rewrites
  `` !`cmd` `` → `` run `cmd` `` and passes any typed focus as request context.
- `cursor/*.md` → `~/.cursor/commands/`; plain Markdown (no frontmatter); same
  `` !`cmd` `` → `` run `cmd` `` rewrite, with a note about `$ARGUMENTS`.
- `gemini/*.toml` → `~/.gemini/commands/`; TOML `prompt`/`description`,
  `$ARGUMENTS` → `{{args}}`, `` !`cmd` `` → `!{cmd}` shell injection.

Add a command once as `<name>.md` and all four tools pick it up. `../test.sh`
checks render is idempotent, applies the dialect transforms, and yields a port
for every canonical command.
