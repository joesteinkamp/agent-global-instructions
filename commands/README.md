# Commands

Portable slash-command shortcuts. Each top-level `.md` file is the canonical
(Claude-dialect) prompt that runs when you type `/<name>`. Install them with
`../install-commands.sh` (all tools) or `../install-commands.sh claude cursor …`.

| Command | What it does |
|---------|--------------|
| `/ship` | Stage → commit → push, and on a feature branch open + **merge** the PR/MR (squash, delete branch), then return to default. Works with GitHub (`gh`) or GitLab (`glab`). The all-in-one. |
| `/sync` | Fetch + rebase the current branch on the latest default branch. |
| `/tidy` | Run the project's formatter / linter / tests and fix what's safe (no commit). |
| `/improve` | Spin up a multi-role review team (architect, back-end, front-end, +UI/UX) on the recent diff to surface prioritized improvement opportunities. No changes applied. |
| `/audit` | Run the [`ux-audit`](https://github.com/joesteinkamp/ux-audit-skill) skill on a screenshot — scores the UI against 15 UX heuristic frameworks, writes a self-contained HTML report, and serves it. |

Most take optional arguments, e.g. `/ship fix login redirect` uses that as the
commit message / PR title.

**Format & ports:** the top-level `.md` files are Claude Code command files —
frontmatter (`description`, `argument-hint`, `allowed-tools`) plus a prompt body
that embeds shell output with `` !`cmd` `` and arguments with `$ARGUMENTS`. They
are the **source of truth**. The subdirectories hold dialect ports translated
from them, installed to each tool's own location:

- `codex/*.md` → `~/.codex/prompts/` (invoke `/prompts:<name>`); keeps
  `$ARGUMENTS`, drops `allowed-tools`, rewrites `` !`cmd` `` into a "run these
  yourself" step (Codex prompts have no shell injection).
- `cursor/*.md` → `~/.cursor/commands/`; plain Markdown (no frontmatter), the
  `` !`cmd` `` lines become explicit instructions.
- `gemini/*.toml` → `~/.gemini/commands/`; TOML with `prompt`/`description`,
  `$ARGUMENTS` → `{{args}}`, `` !`cmd` `` → `!{cmd}` shell injection.

Keep ports in sync with the canonical file when you edit a command;
`../test.sh` asserts every canonical command has a port in each tool dir.
