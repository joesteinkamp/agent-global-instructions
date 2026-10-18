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
| `/critique` | Design crit on work in progress (a URL, route, screenshot, Figma link, or files). Plain: open feedback — what's working, what to explore, questions worth asking — with no pass/fail. `--gate`: a severity-ranked review against whichever of `PRODUCT`/`DESIGN`/`WRITING.md` and `guardrails/` exist, citing ban IDs and naming the briefs that are missing. Read-only; the deliverable is an HTML report. |
| `/figma-parity` | A built screen (URL or route) against its Figma node and the project's tokens → a drift report on spacing, type, color, states and missing variants. Without Figma it falls back to the `DESIGN.md`/`DESIGN.json` tokens and says so. |
| `/handoff` | A prototype (Figma or a URL) → a spec engineers can build from: every state, tokens by name, edge cases, a11y, and open questions for anything the design doesn't show. |
| `/research-synthesis` | Notes, transcripts, survey exports or tickets → themes, each backed by verbatim quotes with their source, plus contradicting evidence, confidence, and open questions. Never invents participants or quotes. Read-only; a private HTML artifact. |
| `/one-on-one` | 1:1 and feedback prep for a named report from whatever sources are connected: context since the last 1:1, talking points, and specific, evidence-backed feedback. Read-only apart from an optional Gmail draft; never sends or messages anyone. |
| `/team-digest` | What shipped, what's blocked and what's next across connected sources for a date range (default: the last 7 days), saying which sources it couldn't read. Read-only; a paste-ready summary it never posts. |
| `/ux-audit` | *(design group)* UX audit **from a screenshot**. Not in this directory: the full [`ux-audit`](https://github.com/joesteinkamp/ux-audit-skill) skill is vendored at `../.agents/skills/ux-audit` and linked by the same installer. Improve it upstream and sync with `npx skills update`; never edit the vendored copy. |

The six design-team skills (`/critique` through `/team-digest`) are ordinary
skills in this directory: they install for everyone, not with the design group
below, and each one names the inputs and connected sources it found and the
ones it didn't.

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
