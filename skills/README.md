# Skills

Portable workflow shortcuts. Each `<name>/SKILL.md` is the single source of
truth: it runs as `/<name>` in Claude Code and Cursor and as `$<name>` in Codex.
Install them with `../install-skills.sh` (all tools) or
`../install-skills.sh claude cursor …`, which symlinks each directory into
`~/.claude/skills`, `~/.codex/skills`, and `~/.cursor/skills`.

| Skill | What it does |
|---------|--------------|
| `/ship` | Tidy gate (format/lint/test, stop if broken) → move off the default branch if that's where the work sits (**it never pushes the default directly**) → stage → commit → push → open the PR/MR, then **merge only on your explicit go-ahead** (squash, delete branch, return to default), then reap the merged local branch and the worktree it lived in. Works with GitHub (`gh`) or GitLab (`glab`). The all-in-one. |
| `/sync` | Fetch + rebase the current branch on the latest default branch, then sweep the worktrees whose branches that fetch just proved merged. |
| `/worktrees` | Set up one git worktree per parallel agent (`ai/<agent>` branches) and converge them into a single integration tree a lone dev server watches — so several models' changes show up near-live. Pairs with `converge.sh`. Tears each tree down once its branch is **proven merged** — dirty, unmerged, locked and current trees are reported, never forced; `~/.ai/worktree-sweep.sh --sweep` does the same machine-wide (dry run; `--apply` to act). |
| `/grill-me` | A relentless interview to sharpen a plan or design before you build it — asked in rounds rather than one at a time, recommended answers offered, facts looked up rather than asked, nothing acted on until we reach a shared understanding. |
| `/improve` | Spin up a multi-role review team (architect, back-end, front-end, +UI/UX) on the recent diff to surface prioritized improvement opportunities, then tee them up as a ready-to-apply plan and offer to make the changes on your go-ahead. **Runs in the background by default**, pinned to a snapshot taken at invocation — findings land as a completion notification plus a durable `findings.md` stamped with the snapshot SHA (HTML report on request). Nothing is edited until you approve. |
| `/verify` | Product-grade evaluation of the recent work: prove it runs (build/test, headless browser with console/a11y/visual-regression evidence), then **grade how well it serves this session's goal** across goal-fit, experience quality, design/a11y, and product fit. Holds the briefs (`PRODUCT`/`DESIGN`/`CODE.md`) as reference — not gospel. **Synchronous by default** — it's a handoff gate; `--bg` defers it behind a done-condition the handoff waits on. Nothing is edited until you approve. |
| `/update-model-routing` | Regenerate this machine's routing data in `~/.ai/model-routing.md`: probe which models each CLI can actually reach, price them, place each model in a tier from web-researched benchmarks, and refresh the vendor-by-task picks. Shows the diff for approval; nothing it writes is committed. |
| `/ux-audit` | *(design group)* UX audit **from a screenshot**. Not in this directory: the full [`ux-audit`](https://github.com/joesteinkamp/ux-audit-skill) skill is vendored at `../.agents/skills/ux-audit` and linked by the same installer. Improve it upstream and sync with `npx skills update`; never edit the vendored copy. |

Most take optional input, e.g. `/ship fix login redirect` uses that as the
commit message / PR title. In Codex, write `$ship fix login redirect`.

**The design group** (`/ux-audit`) installs by default for everyone;
`--no-design` (or `INC_DESIGN=n`, asked of `customize.sh --design-group`) forces
it off and prunes an installed link, so opting out self-heals.

**Format — one dialect for every tool.** Frontmatter carries only `name` and
`description`. The body must work unchanged in Claude Code, Codex, and Cursor,
so it never uses Claude-only features: no `` !`cmd` `` injection (write "run
`cmd`" and let the agent run it), no `$ARGUMENTS` (refer to "the request"), no
`allowed-tools`.

**Why skills only.** Cursor reads `~/.claude/skills` and `~/.codex/skills` as
well as `~/.cursor/skills`, and lists a command file and a skill of the same
name as two entries. One symlinked directory per skill gives each tool one
entry, with identical content wherever Cursor finds it.
