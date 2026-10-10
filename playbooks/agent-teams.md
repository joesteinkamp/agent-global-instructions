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

Which role, when — the lens each one owns, so the roster can be derived instead
of guessed. A Claude Code lead also sees each role's `description`; a Codex lead
may only see the name, so this table is what routes there.

| Role | Spawn when the question is… | Writes? |
| :-- | :-- | :-- |
| `product-designer` | what should exist and why: scope, user value, the flow, what to cut | documents only |
| `ux-researcher` | what we actually know about users versus what we're guessing | no |
| `ui-designer` | whether the rendered result matches the design system and reads well | no |
| `technical-architect` | what shape a cross-module change, dependency, or data flow should take | no |
| `backend-engineer` | server, data, API, migrations, auth — correctness under failure | yes |
| `frontend-engineer` | client code, state, routing, and the accessibility of what renders | yes |
| `qa-engineer` | whether it actually runs: tests, reproducing a bug, every state and breakpoint | tests only |
| `security-reviewer` | how the code can be made to misbehave: trust boundaries, injection, auth, secrets | no |
| `refuter` | whether a finding, plan, or claim survives an attempt to break it | no |
| `harness-steward` | the AI harness itself: instruction files, roles, hooks, installers | yes |

Rosters that work:

| Task | Roster |
| :-- | :-- |
| Review a diff or PR | `security-reviewer` + `qa-engineer` + a correctness lens, then `refuter` on what they find |
| Bug with an unclear cause | one agent per hypothesis, told to disprove each other's, + a synthesizer |
| Feature across layers | `frontend-engineer` + `backend-engineer` + `technical-architect`, disjoint files |
| A design or scope call | `product-designer` + `ux-researcher` + `ui-designer`, then `refuter` |
| Research a library or approach | one agent per source or angle, then one synthesis pass |

## The brief you write first

Sizing and roles are decisions; this is the artifact that records them. Write it
before the first spawn, in a file the team can read — not only into the spawn
prompts, which evaporate when the session ends. It is also what a `/loop`, a
fresh session, or another tool needs to pick the work up mid-flight.

- **Goal** — one sentence, the user-visible outcome.
- **Roster** — the roles you spawned and the one-line reason each earned a seat,
  including the refuter and what it is arguing against.
- **Ownership** — the files or area each agent owns, and who owns the lockfiles,
  migrations, and generated files. This is the line that prevents lost work.
- **Acceptance criteria** — testable, no vague language. "Feels faster" is not a
  criterion; "p95 under 200ms on the seeded dataset" is.
- **Non-goals** — what is explicitly out of scope, so an agent that finds
  adjacent work reports it instead of quietly doing it.
- **Assumptions** — mark the uncertain ones "(confirm?)" rather than burying them
  in prose.
- **Verification plan** — the exact commands, and who runs them.
- **Rollback plan** — how to revert safely, where the change is hard to undo.

Keep it current as the work moves. It is the source of truth for what "done"
means, and an agent reporting against a stale brief is worse than one reporting
against no brief at all.

## The role definitions

Roles are files, not prose, so the same role behaves the same in every tool.
All ten in the table above ship by default, and the file name is the name you
spawn by. `harness-steward` is in the palette like the rest, but its subject is
the tooling itself, not the product — spawn it when that is the work, never as
a lens on a product task.

`roles/*.md` is the one source. `render-roles.sh` generates a port per tool and
`install-roles.sh` installs all four:

- **Claude Code** — `~/.claude/agents/<role>.md`: YAML frontmatter (`name`,
  `description`, `tools`, optionally `model`) with the instructions as the body.
  Project scope is `.claude/agents/`.
- **Codex** — `~/.codex/agents/<role>.toml`: one TOML file per agent, requiring
  `name`, `description`, and `developer_instructions`, with optional `model`,
  `model_reasoning_effort`, `sandbox_mode`, and `mcp_servers`. Project scope is
  `.codex/agents/`. Anything omitted is inherited from the parent turn.
- **Cursor** — `~/.cursor/agents/<role>.md`: frontmatter `name`, `description`,
  `model`, `readonly`, with the description read to decide delegation. Cursor
  also reads `~/.claude/agents` and `~/.codex/agents`; within one scope a
  `.cursor/` copy wins, and only it carries `readonly`. A project-scope role
  beats a user one, though, so a project `.claude/agents/<role>.md` (from
  `install-roles.sh --project claude`) shadows `~/.cursor/agents/<role>.md` and
  drops `readonly`. Project scope is `.cursor/agents/`.
- **Antigravity** — `~/.gemini/config/agents/<role>.md`: frontmatter `name`,
  `description`, and `tools` in its own tool names; its planner reads the
  description to delegate through `invoke_subagent`. Project scope is
  `.agents/agents/`, which agy's changelog says also loads under headless `-p`.
  It has no read-only switch: a read-only role is rendered without the file-write
  tools, but it keeps `run_command`, so its shell can still write — bounded only
  by agy's command policy and permissions allowlist, not by the role.
- **One convention on top of all four** — every canonical `roles/*.md` also carries a
  `reminder:` key holding the role's hard rules in one line. Neither host has a
  per-turn reminder field, so it reaches the agent the only way it can: as the
  line the body opens and closes with, and `render-roles.sh` fails the render if
  the three copies disagree. Each role also separates **Hard rules** from
  guidance, ends with a named **Return** contract, and — where it is read-only —
  states what *not* to report and the floor a finding has to clear. Every role
  also works with no lead at all — a cron job or a headless one-shot: an
  **Unattended runs** rule has it state the reading it took and finish without
  asking, stopping at any gate rather than crossing it, and its Return opens
  with **Status** (done, partial, or blocked) so a wrapper script can grep one
  line for the outcome.
- None pins a `model`, so a role runs on whatever the session is running.
- **How read-only each tool really is.** Codex enforces `sandbox_mode`. Cursor
  has `readonly` (see the scope caveat above). Antigravity drops the file-write
  tools but keeps a shell. **Claude Code does not enforce it for the roles that
  carry Bash** (`refuter`, `security-reviewer`, `technical-architect`): it
  ignores `sandbox:`, and ignores a subagent's `permissionMode` while the lead
  runs in auto or acceptEdits mode, so only the role's own hard rules stop a
  shell write. `ui-designer` and `ux-researcher` are read-only for real, because
  their `tools` has no Bash, `Edit`, or `Write`, and a teammate honors `tools`.
  Where read-only has to hold in Claude Code, give the claim to one of those.
- **If a role you need has no definition, add it to `roles/` and re-render**
  rather than improvising it — in Codex especially, an unknown agent name
  silently falls back to the built-in generic agent, so an undefined role is not
  a role at all.

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

Cursor and Antigravity both load the installed roles (above) and delegate to
them by description. agy's changelog says project agents in `.agents/agents/`
load under headless `agy -p`; whether `agent -p` (Cursor) loads
`~/.cursor/agents` headless is not documented and has not been tested here. For
a headless Cursor delegate, put the role in the prompt itself (strip the
frontmatter first, as `orchestration.md` does). Where a tool has no parallel
construct at all, run the lenses sequentially in one session — a review that
applies three named lenses in turn still beats one undifferentiated pass.

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
