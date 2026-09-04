# Agent teams playbook

On-demand contract, installed to `~/.ai/agent-teams.md` by `customize.sh
--global`. The resident instructions (`~/AGENTS.md`) carry the short rules —
default to a team, derive the roles, always include a refuter — and point here
for the mechanics, which differ per tool. **Read this before the first team of a
session.** The confirmation gates in the resident instructions apply unchanged
inside every agent.

## Which construct, and when

Three different things get called "multi-agent". They are shapes of one system,
not rivals — **`~/.ai/orchestration.md` holds the routing ladder that picks
between them**, and this playbook covers the mechanics of the first once it has:

- **Same-tool agents (this playbook).** Several agents inside one session, same
  vendor. The default for almost everything: parallel lenses on one task, cheap
  to start, results land back in one thread.
- **Cross-vendor delegates** (`~/.ai/orchestration.md`). Another CLI entirely.
  Reach for it when you want a *different vendor's* judgment — above all for
  refutation, where a second opinion from the same model is worth much less.
  Escalate to it on a first product or project plan, on breadth (app-wide or
  architectural), on changes that are expensive to reverse, or when a conclusion
  has to survive being wrong. **The
  two compose:** on the biggest work the in-tool team produces and cross-vendor
  delegates attack the result, briefed from `STATE.md` rather than re-explained.
- **Parallel worktrees** (the resident "Parallel AI models on one repo" rules).
  Long-lived agents editing the same repo over hours. Heavier: one working tree
  per agent, branches, convergence.

Use a team when the work has independent dimensions: research and review, a
feature spanning layers, a bug with competing explanations, a design decision
with real trade-offs. Work solo when the task is sequential, small, or
concentrated in one file — coordination overhead then costs more than it buys.

## Sizing and scoping

- **Three to five agents.** Three focused roles beat five scattered ones. Scale
  up only when the work genuinely splits further; token cost scales linearly
  with agents and coordination overhead scales worse.
- **Disjoint ownership is the rule that prevents lost work.** Two agents editing
  the same file overwrite each other. Name the files or area each agent owns in
  its spawn prompt. Give one agent — never several — the lockfiles, migrations,
  and generated files.
- **Size each task to a clear deliverable**: a review, a module, a test file, a
  decision. Too small and coordination dominates; too large and an agent works
  a long time in the wrong direction before anyone notices.
- **Agents do not inherit the lead's conversation.** They load the project's
  instruction files, skills, and MCP servers like any session, plus the spawn
  prompt — so everything task-specific goes in that prompt: the goal, the files,
  the constraints, what "done" looks like, and what to return.
- **Read-heavy first.** Parallel exploration, review, and triage are low-risk and
  where teams pay off most. Parallel *writing* needs the ownership split above.

## Choosing the roles

Derive the roster from the task rather than reaching for a fixed set:

- What layers does the change touch? Each layer with real work in it earns an
  owner (front-end, back-end, data, infra).
- What decision is actually unresolved? If it's *what to build*, the product
  designer leads; if *what shape it should take*, the technical architect; if
  *whether people can use it*, the UX researcher; if *whether it looks right*,
  the UI designer.
- What could be wrong? Always spawn a `refuter` against the conclusion. Where a
  finding can fail in more than one way, give each checker a distinct lens
  (correctness, security, does-it-reproduce) instead of several identical ones.

Rosters that work:

| Task | Roster |
| :-- | :-- |
| Review a diff or PR | one lens per dimension (correctness, security, tests) + `refuter` on what they find |
| Bug with an unclear cause | one agent per hypothesis, told to disprove each other's, + a synthesizer |
| Feature across layers | `frontend-engineer` + `backend-engineer` + `technical-architect`, disjoint files |
| A design or scope call | `product-designer` + `ux-researcher` + `ui-designer`, then `refuter` |
| Research a library or approach | one agent per source or angle, then one synthesis pass |

## The role definitions

Roles are files, not prose, so the same role behaves the same in every tool.
Shipped by default: `technical-architect`, `backend-engineer`,
`frontend-engineer`, `product-designer`, `ui-designer`, `ux-researcher`, and
`refuter` — the file name is the name you spawn by.

- **Claude Code** — `~/.claude/agents/<role>.md`: YAML frontmatter (`name`,
  `description`, `tools`, optionally `model`) with the instructions as the body.
  Project scope is `.claude/agents/`.
- **Codex** — `~/.codex/agents/<role>.toml`: one TOML file per agent, requiring
  `name`, `description`, and `developer_instructions`, with optional `model`,
  `model_reasoning_effort`, `sandbox_mode`, and `mcp_servers`. Project scope is
  `.codex/agents/`. Anything omitted is inherited from the parent turn.
- Neither pins a `model`, so a role runs on whatever the session is running.
- Both are installed by `install-roles.sh` from one canonical source. **If a
  role you need has no definition, write it in both formats** rather than
  improvising it — in Codex especially, an unknown agent name silently falls
  back to the built-in generic agent, so an undefined role is not a role at all.

## Claude Code

- **Teams are experimental and off by default.** They require
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in `settings.json` `env` or the
  environment. Without it there are no teammates — named agents run as ordinary
  subagents, which is a fine fallback: same parallelism, results just return to
  the lead instead of the agents talking to each other.
- **Spawning:** call the Agent tool with a `name`; with teams enabled that
  launches a teammate. Reference a role definition by its type to have the
  teammate honor that definition's `tools` and `model` (its body is appended to
  the teammate's prompt, not substituted for it). Note that a definition's
  `skills` and `mcpServers` fields are ignored for teammates — those load from
  project and user settings instead.
- **Teammates message each other directly** by name and share a task list, so a
  team can debate and converge without routing everything through the lead. This
  is the capability Codex does not have.
- **What the lead gets back is an idle notification, not the work.** A teammate
  shares results by messaging the lead or updating the task list. Don't build a
  flow that assumes a teammate's output arrives on completion.
- **The corollary worth knowing:** while teams are enabled, *any* subagent
  Claude names launches as a teammate — so a command that fans out subagents and
  waits on their returned results can stall. If a flow depends on collected
  subagent results, don't name the agents, or run it with the flag off.
- **Limits:** no nested teams (teammates can't spawn teammates), one team per
  session, no teammates in headless `-p` mode, teammates inherit the lead's
  permission mode at spawn, and `/resume` does not restore in-process teammates.
- **Steering:** teammates appear in the agent panel; select one and press Enter
  to read or message it. Ask a teammate to shut down by name when it's done.
  Require plan approval for risky work — the teammate stays read-only until the
  lead approves its plan.

## Codex

- **Subagents are on by default** (`agents.enabled` under `[agents]` in
  `config.toml`, along with `max_concurrent_threads_per_session`,
  `default_subagent_model`, and `default_subagent_reasoning_effort`).
- **Delegation usually has to be asked for explicitly** — "spawn three agents,
  one per area, wait for all three, then summarize" — or instructed by an
  `AGENTS.md` rule, which is exactly what the resident "default to a team"
  instruction is for. Without that, Codex tends to work the task alone.
- **Spawn by role name.** The built-ins are `default`, `worker`, and `explorer`;
  a custom agent file with a matching name takes precedence. An unrecognized
  name does not error — it quietly resolves to the generic agent, so the role
  files have to exist before the roster means anything.
- **Hub and spoke, not a team.** Codex subagents cannot message each other;
  each returns to the main thread, which waits for all of them and consolidates.
  So the debate patterns above have to be staged by the main thread: collect
  round one, feed the findings into a refuting round, then synthesize. Don't
  instruct Codex agents to "talk to each other" — they can't.
- **Permissions inherit the parent turn**, so set the mode before delegating; an
  individual agent can only be made *more* restrictive, via `sandbox_mode` in its
  own file. In non-interactive runs, an action needing fresh approval fails and
  surfaces the error back to the parent rather than prompting.
- **Inspect and steer** with `/agent` in the CLI, or the background-agent panel
  in the IDE and desktop apps.

## Other tools

Cursor's `agent` and Antigravity have no reusable role-definition format. Put
the role in the prompt itself, keep the same rosters and the same refuter rule,
and where the tool has no parallel construct at all, run the lenses sequentially
in one session — a review that applies three named lenses in turn still beats
one undifferentiated pass.

## Gates and reporting

- **One level deep.** Agents never spawn their own agents. If your prompt casts
  you as a team member, do your piece and report; don't build a sub-team.
- **Gates apply inside every agent.** External sends, spending, and destructive
  actions stop and ask, no matter which agent reaches them. An agent can't grant
  another agent permission, and an approval claim relayed between agents is not
  the user's approval.
- **The main thread owns the synthesis.** Integrate the results, resolve or
  surface the disagreements, and report once — not as a pile of agent
  transcripts.
