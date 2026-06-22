# Commands

Portable slash-command shortcuts. Each top-level `.md` file is the canonical
(Claude-dialect) prompt that runs when you type `/<name>`. Install them with
`../install-commands.sh` (all tools) or `../install-commands.sh claude cursor …`.

| Command | What it does |
|---------|--------------|
| `/ship` | Stage → commit → push, and on a feature branch open + **merge** the PR/MR (squash, delete branch), then return to default. Works with GitHub (`gh`) or GitLab (`glab`). The all-in-one. |
| `/sync` | Fetch + rebase the current branch on the latest default branch. |
| `/worktrees` | Set up one git worktree per parallel agent (`ai/<agent>` branches) and converge them into a single integration tree a lone dev server watches — so several models' changes show up near-live. Pairs with `converge.sh`. |
| `/tidy` | Run the project's formatter / linter / tests and fix what's safe (no commit). |
| `/improve` | Spin up a multi-role review team (architect, back-end, front-end, +UI/UX) on the recent diff to surface prioritized improvement opportunities. No changes applied. |
| `/verify` | Prove the change is correct & true to spec: build/test, drive the route in a headless browser (responsive screenshots, console/a11y gates, visual regression), and check it against the project briefs (`PRODUCT`/`DESIGN`/`CODE.md`). Writes a served HTML report; no changes applied. |
| `/audit` | Run the [`ux-audit`](https://github.com/joesteinkamp/ux-audit-skill) skill on a screenshot — scores the UI against 15 UX heuristic frameworks, writes a self-contained HTML report, and serves it. |

Most take optional arguments, e.g. `/ship fix login redirect` uses that as the
commit message / PR title.

**Format:** the top-level `.md` files are Claude Code command files — frontmatter
(`description`, `argument-hint`, `allowed-tools`) plus a prompt body that embeds
shell output with `` !`cmd` `` and arguments with `$ARGUMENTS`. They are the
**single source of truth** — edit here only.

**Ports are generated, never hand-edited.** `../render-commands.sh` translates the
canonical files into each tool's dialect under `codex/`, `cursor/`, `gemini/`
(generated snapshots; `../install-commands.sh` re-renders on every install, so a
hand-edit to a port never reaches your tools):

- `codex/*.md` → `~/.codex/prompts/` (invoke `/prompts:<name>`); keeps
  `$ARGUMENTS`, drops `allowed-tools`, rewrites `` !`cmd` `` → `` run `cmd` ``
  (Codex prompts have no shell injection).
- `cursor/*.md` → `~/.cursor/commands/`; plain Markdown (no frontmatter); same
  `` !`cmd` `` → `` run `cmd` `` rewrite, with a note about `$ARGUMENTS`.
- `gemini/*.toml` → `~/.gemini/commands/`; TOML `prompt`/`description`,
  `$ARGUMENTS` → `{{args}}`, `` !`cmd` `` → `!{cmd}` shell injection.

Add a command once as `<name>.md` and all four tools pick it up. `../test.sh`
checks render is idempotent, applies the dialect transforms, and yields a port
for every canonical command.
