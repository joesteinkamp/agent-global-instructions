# Commands

Portable slash-command shortcuts. Each `.md` file is the prompt that runs when
you type `/<name>`. Install them with `../install-commands.sh`.

| Command | What it does |
|---------|--------------|
| `/ship` | Stage → commit → push, and on a feature branch open + **merge** the PR (squash, delete branch), then return to default. The all-in-one. |
| `/save` | Quick checkpoint: commit + push, no PR. |
| `/pr`   | Open a PR with a generated title/body — stops before merge. |
| `/sync` | Fetch + rebase the current branch on the latest default branch. |
| `/tidy` | Run the project's formatter / linter / tests and fix what's safe (no commit). |
| `/improve` | Spin up a multi-role review team (architect, back-end, front-end, +UI/UX) on the recent diff to surface prioritized improvement opportunities. No changes applied. |

Most take optional arguments, e.g. `/ship fix login redirect` uses that as the
commit message / PR title.

**Format:** Claude Code command files — frontmatter (`description`,
`argument-hint`, `allowed-tools`) plus a prompt body that can embed shell output
with `` !`cmd` `` and arguments with `$ARGUMENTS`. Codex/Cursor have their own
command locations; the bodies are plain enough to reuse there.
