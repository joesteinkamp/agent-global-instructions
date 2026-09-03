# Orchestration playbook

On-demand contract, installed to `~/.ai/orchestration.md` by `customize.sh
--global`. The resident instructions (`~/AGENTS.md`) point here so the full
contract doesn't sit in every session's context. **Read this top to bottom
before the first team or delegation of a session, then follow it for every
wave.** The confirmation gates in the resident instructions apply unchanged.

This is the single entry point for distributing work across agents, whichever
side of a vendor boundary they sit on. Start with "choosing the shape" below to
decide *what* to spawn; `~/.ai/agent-teams.md` carries the per-tool mechanics of
spawning in-tool agents, and the rest of this file carries everything specific to
delegates in another CLI.

## One system: choosing the shape

Agent teams and cross-vendor delegates are not two systems. They are two
transports for the same thing — putting more than one lens on a problem — and
choosing between them is a routing decision made per task, not a standing
preference. Roles are the interface either way (next section); the transport is
an implementation detail you pick from the work in front of you.

**Default: an in-tool team.** Spawn same-vendor agents in the current tool for
almost everything multi-dimensional. They start in milliseconds, inherit the
project's instruction files, cost the least per lens, and their results land back
in one thread. Per-tool mechanics live in `~/.ai/agent-teams.md`.

**Escalate to cross-vendor when one model's blind spots are the risk.** Lenses
from a single vendor correlate — they tend to miss the same things and agree for
the same reasons, because they share a prior. Reach for another CLI when the work
trips any of these:

- **Breadth.** The change is app-wide or cross-cutting: architecture, the data
  model, an auth or routing layer, a dependency swap — anything touching most of
  the codebase rather than a corner of it.
- **Reversibility.** Getting it wrong is expensive to undo — a migration, a
  public API, a released artifact, a security boundary, or a decision the rest of
  the work will be built on.
- **Contested ground.** Competing explanations survive the first pass, or the
  in-tool team converged suspiciously fast on something nobody stress-tested.
- **Refutation that has to count.** A same-model refuter is a real check on the
  *agent* and a weak check on the *model*. When a claim has to survive being
  wrong, the refuter comes from a different vendor.

**Do both when the work earns it — the compound shape is the normal answer at the
top of that list, not an exotic case.** The in-tool team produces; the outside
vendors attack:

1. Spawn the in-tool team — roles derived from the task, disjoint scopes.
2. Fold their results into `STATE.md`. That summary is the brief the outside
   vendors read, so the cross-vendor wave costs one summary rather than a
   re-explanation of the whole task.
3. Launch cross-vendor delegates against it in the `refuter` role, prompted to
   break the conclusion rather than confirm it.
4. Reconcile in the main thread. Surface disagreements to the user; never
   silently pick a winner.

**Cost is why this is a ladder and not a default-everything.** Each rung
multiplies tokens and wall time, and the compound shape adds a context dir, a
summary, and a reconciliation pass on top. The ladder starts below the team: work
that is small, sequential, or concentrated in one file takes no agents at all.

## Roles are the interface

The same role palette applies to both transports, so `refuter` means the same
thing whether it is a subagent in this session or another vendor's CLI. That
shared meaning is the point of keeping roles in files at all.

- **In-tool:** reference the role by name and the host loads it itself, from
  `~/.claude/agents/<role>.md` or `~/.codex/agents/<role>.toml`.
- **Cross-vendor: the host cannot do this for you.** `codex exec` has no
  agent-selection flag, and `claude --agents` defines the roster a session may
  spawn — not the role its `-p` turn assumes. **A delegate is a generic agent
  unless you put the role in the prompt**, so pass the definition in:

      role=$(sed '1{/^---$/,/^---$/d}' ~/.claude/agents/refuter.md)
      timeout 900 claude -p "…" --append-system-prompt "$role" \
        < /dev/null > "$CTX/agents/refuter.log" 2>&1 &

  For a CLI with no system-prompt flag, put the same body at the top of the
  prompt instead. Name the delegate's output file after the role
  (`agents/refuter.md`) so the context dir records which lens produced which
  finding.

## Delegates & the roster

- **Hand subtasks to the other installed AI CLIs in headless one-shot mode** — e.g. `codex exec "…" --json`, `claude -p "…" --output-format json`, `agy -p "…"` (Antigravity, Gemini CLI's successor; text output only), or `agent -p "…"` (Cursor's CLI). The installer records the roster at `~/.ai/clis` (bare names, one per line — including the tool you are running as: exclude yourself when delegating) — read that file instead of re-probing every session (fall back to `command -v codex agy claude agent …` only if it's missing). Run delegates as background shell jobs so they proceed in parallel — but launch them in the hardened form below, never bare.
- **Launch every delegate in the hardened form.** A bare `claude -p "…" &` is the single most common way a wave dies silently:

      timeout 900 claude -p "…" < /dev/null > "$CTX/agents/<name>.log" 2>&1 &

  Each part earns its place. `timeout` bounds a delegate that will never return on its own — **a starved agent CLI does not exit non-zero, it retries in place until something kills it**, so with no bound the orchestrator waits forever. `< /dev/null` closes stdin, which these CLIs otherwise read as extra prompt input when they are not on a TTY. Redirecting both streams to a file makes the failure legible: stdout alone is lossy, and a backgrounded job's stderr goes nowhere. **`wait` on each job and check its exit status** — 124 is the timeout, and any non-zero means read the log before you trust the wave. A delegate that produced no `agents/<name>.md` is a failure to investigate, never a delegate that had nothing to say.
- **A silent wave is a sandbox problem until proven otherwise.** If delegates hang or return nothing, check the host's sandbox network policy before anything else: Codex's `workspace-write` disables network by default, and every delegate is a network client. `codex exec` prints the answer in its own header — `(network access enabled)` is what you want to see. The installer sets `sandbox_workspace_write = { network_access = true }`; a machine that predates that, or a hand-edited config, silently starves every delegate it launches.
- **React to failing delegates.** If one errors at runtime — quota exhausted, auth expired, binary gone — drop it for the rest of the session, redistribute its work across the remaining vendors, note the failure in `STATE.md`, and tell the user.
- **Delegate for two reasons.** *Speed:* fan disjoint subtasks out across agents — but prefer the host tool's native subagents for same-vendor fan-out; reach for another CLI when you want a different vendor's judgment or the host has no subagents. *Quality:* **a model must never be the sole checker of its own work** — route review through a different vendor's model, prompted to refute ("find what's wrong"), not to confirm. Surface disagreements to the user; don't silently pick a winner.

## Routing

- **Route by strength — advisory.** When picking which CLI gets a subtask, consult `~/.ai/model-routing.md` — a benchmark-derived, per-task-type ranking of the installed vendors (hard coding, review/refutation, research, planning, UI, cheap fan-out, long-context). It's reference, not law: availability, cost, and your own observed results on this task outrank it, and the user's explicit choice always wins. If the file is absent, choose freely and skip the mention.
- **Say when it's stale.** The table's `Last updated` header dates it; if that's older than ~2 months, still use it but note the staleness and offer `/update-model-routing` to refresh.

## Local models (behind `lm`)

- **Local models are roster delegates too.** If `~/.ai/local-models` exists (one endpoint per line: `name|backend|base_url|model|tier[|tok/s]` — Ollama, llama.cpp, MLX, or a remote box, all speaking the same OpenAI-compatible API), the `lm` shim runs them: `lm -p "…"` (`--model`/`--tier` to pick; `lm list` for health). If the file or shim is absent, this machine has no local models — skip silently, and never install or start one to get some.
- **Route local by tier.** `light` models take only cheap mechanical fan-out and privacy-sensitive content that shouldn't leave the machine; `strong` models may also serve as an extra review lens or synthesis pass. Machine-specific scores live in `~/.ai/model-routing.local.md` (written by `/update-model-routing`) — consult it alongside the main table. Either tier: never the sole checker of anything.
- **Local delegates are one-shot text only.** No agentic editing — hand them read-only work (summarize, classify, draft, refute) and have their output land in the context dir like any read-only delegate; they never get a worktree. A down endpoint is a failing delegate: drop it, redistribute to cloud vendors, tell the user.

## The shared context dir

- **One level only.** Delegates never spawn further delegates. If your prompt points you at an existing `~/.ai-context/` dir, you *are* the delegate: read the brief, do your piece, write your file, stop.
- **Centralized temporary context is the contract.** (A single one-shot delegation — e.g. one cross-vendor review — may skip the `TASK.md`/`STATE.md` ceremony, but still gets the dir: every delegate writes its full output to a file there, because stdout alone is lossy.) Before the first delegation, create a shared context dir — `~/.ai-context/<repo>-<task-slug>/` — write `TASK.md` (goal, constraints, key repo paths, acceptance criteria) and seed an empty `STATE.md`. Every delegate prompt must name that dir, open with "read `TASK.md` and `STATE.md` first," and close with "write your full results to `agents/<your-name>.md`."
- **Layout & ownership:** `TASK.md` (the brief) · `STATE.md` (rolling summary — done, decided, remaining) · `agents/<name>.md` (one per delegate) · `artifacts/` (reports, patches, JSON from read-only delegates). **One writer per file:** the orchestrator owns `TASK.md`/`STATE.md`; each delegate writes only its own file. Fold results into `STATE.md` after each wave so later delegates inherit everything learned so far.
- **stdout is a status line; files are the record.** Delegate output can truncate or interleave — durable detail belongs in the context dir. Grant sandboxed delegates write access to it the way their tool expects: `--add-dir` (Claude, Antigravity, Codex), `--include-directories` (legacy Gemini CLI).
- **Temporary means temporary.** The dir is scoped to one task: never commit it, don't treat it as memory (durable facts go to the memory store), and tell the user where it is — or clean it up — when the task ends.

## Isolation & sandboxing

- **Delegates that edit files never share a working tree.** Editing delegates follow the parallel-worktree conventions — one sibling worktree per agent (`../<repo>-<agent>`, branch `ai/<agent>`) — and their work integrates via those branches (WIP commits on `ai/*` branches are part of that flow, not gated sends). Read-only delegates (research, review) may share the main tree.
- **Sandbox, don't bypass — and scope the writes.** Run each delegate in its tool's sandboxed autonomous mode with write access limited to what it owns: an editing delegate gets its worktree + the context dir; a reviewer gets the context dir as its **only** writable root — simplest is to run it with the context dir as its workspace (e.g. `codex exec --sandbox workspace-write --cd <ctx-dir>`, `agy --mode accept-edits --add-dir <ctx-dir>`) so the repo stays read-only to it. Never launch a delegate with full-bypass flags (`--dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`, `--yolo`) unless the user explicitly says so.
- **The user's gates still apply.** Delegates inherit every confirmation gate from the resident instructions (external sends, spending, destructive actions); never delegate an action you'd need the user's approval to take yourself.
