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
| `/grill-me` | A relentless interview to sharpen a plan or design before you build it — one question at a time, recommended answers offered, facts looked up rather than asked, nothing acted on until we reach a shared understanding. |
| `/improve` | Spin up a multi-role review team (architect, back-end, front-end, +UI/UX) on the recent diff to surface prioritized improvement opportunities inline (HTML report on request), then tee them up as a ready-to-apply plan and offer to make the changes on your go-ahead. Nothing is edited until you approve. |
| `/verify` | Product-grade evaluation of the recent work: prove it runs (build/test, headless browser with console/a11y/visual-regression evidence), then **grade how well it serves this session's goal** across goal-fit, experience quality, design/a11y, and product fit. Holds the briefs (`PRODUCT`/`DESIGN`/`CODE.md`) as reference — not gospel — and separates intentional evolution (docs to update) from real regressions as the code outruns the docs. Inline scorecard by default (HTML report on request), then a ready-to-apply fix plan on your go-ahead. Nothing is edited until you approve. |
| `/ux-audit` | *(design)* UX audit **from a screenshot**. On Claude Code with the [`ux-audit`](https://github.com/joesteinkamp/ux-audit-skill) skill installed it scores against 15 UX heuristic frameworks with annotated screenshots; on the other tools (no skill support) it runs the heuristic rubric inline. Writes + serves a self-contained HTML report. |

Most take optional arguments, e.g. `/ship fix login redirect` uses that as the
commit message / PR title. In Codex, write `$ship fix login redirect`.

**Command groups.** A command opts into a group with `group: <name>` in its
frontmatter (absent ⇒ `core`, always installed). The **`design`** group above
(`/ux-audit`) installs **by default for everyone** — everyone should
design better; `--no-design` (or `INC_DESIGN=n`, asked of `customize.sh
--design-group`) forces it off and prunes any already installed, so opting out
self-heals. Ports are always generated for every command — the group only
decides what gets **installed**.

**Format:** the top-level `.md` files are Claude Code command files — frontmatter
(`description`, `argument-hint`, `allowed-tools`, optional `group`) plus a prompt
body that embeds shell output with `` !`cmd` `` and arguments with `$ARGUMENTS`.
They are the **single source of truth** — edit here only.

**Ports are generated, never committed or hand-edited.** `../render-commands.sh`
translates the canonical files into each tool's dialect under `codex/`, `cursor/`,
`gemini/` (gitignored; `../install-commands.sh` re-renders on every install, so a
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
