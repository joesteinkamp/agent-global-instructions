# The full guide

Everything beyond the [README](../README.md) quick start: how the render works,
every command, hook, and permission layer, and how to customize the wording.

## How it works

Three layers — a shared baseline, your personal answers, and the generated
output:

```
template.md       wording + which sections to include     (shared, committed)
      +
team-context.env  a team's shared answer baseline         (optional, committed by a fork)
my-context.env    your answers: name, env, autonomy …     (personal, gitignored — overrides team)
extras.local.md   personal sections spliced in verbatim   (personal, gitignored)
      │
      ▼   ./customize.sh
rendered files    CLAUDE.md / AGENTS.md                   (snapshots — generated)
```

**The rendered files are snapshots — never edit them directly.** Anything you
change there is overwritten on the next render. To change the output, edit
`template.md` (wording, which sections), `my-context.env` (your answers), or
`extras.local.md` (personal sections the shared template can't express — e.g.
machine-specific serving notes; spliced in after the "Output artifacts"
section). Re-run `./customize.sh` and every personal layer survives.

## The parts

Independent parts — use any subset; `./install.sh` wires them all:

1. **Instructions** (model-facing) — a customizable `template.md` rendered into
   per-tool instruction files. *Advice* the assistant should follow.
2. **Commands** — slash-command shortcuts (`/ship`, `/sync`, `/worktrees`,
   `/improve`, `/verify`, `/ux-audit`) for repeatable
   workflows.
3. **Guardrails & observability** (hooks) — auto-format, block edits to
   generated/sensitive paths, trip on catastrophic shell, log every tool call to
   JSONL, and surface your memory stores at session start. *Enforcement* the
   model can't skip.
4. **Validation & verification** — two complementary passes: a multi-role review
   team for *taste* (`/improve`, "could it be better?") and an evidence-based
   *verification* pass (`/verify`, "is it correct & true to spec?") that runs the
   change, drives it in a browser, and checks it against your project briefs.
   Both are explicit-only; one conservative Stop hook can mention them as
   optional follow-ups after a material code change, but never runs them.
5. **Settings** (per tool) — a client-enforced permissions layer mapped to each
   tool's native model (Claude & Cursor deny rules, Codex sandbox + approval)
   that backs up the guard hooks with rules the model can't bypass.

## What's here

| File | Purpose |
|------|---------|
| `template.md` | Source of truth for the instructions. Wording + `{{vars}}` + toggleable `<!--SECTION:x-->` blocks. |
| `customize.sh` | Asks a handful of questions (or reads `my-context.env`), fills the template, writes the finalized file(s). Also `--scan-mcp`. |
| `my-context.env.example` | Copy to `my-context.env` (gitignored) to save your answers. |
| `team-context.env` | Optional, committed by a team fork — shared answer baseline loaded before `my-context.env` (personal values win key by key). |
| `extras.local.md` | Optional, gitignored — personal Markdown sections spliced verbatim into every render at `{{EXTRAS}}`. |
| `examples/` | Two finished sample renders + the `.env` inputs that reproduce them. |
| `install.sh` / `uninstall.sh` | One-shot installer for every layer, and its clean reverse (configs backed up; instruction files left in place). |
| `commands/` + `render-commands.sh` + `install-commands.sh` | Canonical commands (`commands/*.md`) → `render-commands.sh` generates per-tool ports (`commands/{codex,cursor}/`, gitignored — regenerated on every install) → `install-commands.sh` installs Claude/Cursor commands and Codex skills (`~/.codex/skills/`); skill-backed commands symlink globally for Claude, Codex, and Cursor. |
| `.agents/skills/` (+ `.claude/skills/` + `.cursor/skills/` symlinks) + `skills-lock.json` | Third-party Skills vendored via [`npx skills`](https://skills.sh), project-scoped so they ship with the repo. `.agents/skills/` is the canonical Agent-Skills-standard tree; `.claude/skills/` and `.cursor/skills/` entries are symlinks into it. Currently: `grill-me` / `grill-with-docs` plus their primitives `grilling` and `domain-modeling`, and `ux-audit` (from [joesteinkamp/ux-audit-skill](https://github.com/joesteinkamp/ux-audit-skill); skill-backed — `install-commands.sh` symlinks it globally for Claude/Codex/Cursor in place of the `/ux-audit` wrapper). Re-sync with `npx skills update`; the lockfile pins each skill's upstream source + hash. `grill-me` is also promoted to a globally-installed command (see `commands/grill-me.md` below) so `/grill-me` works in any project, not just this repo's checkout. |
| `hooks/` + `install-hooks.sh` | Guardrail + observability hooks → merged into each tool's config (Claude / Codex / Cursor / Antigravity). |
| `*-permissions.snippet.*` + `install-settings.sh` | Per-tool permissions: Claude & Cursor `deny` JSON, Codex `config.toml` sandbox+approval (idempotent, backed up). |
| `audit.sh` | Read back the tool-call audit log — timeline, stats, or live tail. |
| `converge.sh` | Daemon for the `/worktrees` flow: folds parallel agent branches (`ai/*`) into the integration branch as they advance. |
| `MODEL-ROUTING.md` | Advisory, benchmark-derived table of which installed AI CLI is strongest per task type (hard coding, review, research, planning, UI, cheap fan-out, long-context). Mirrored to `~/.ai/model-routing.md` by `customize.sh --global` so the rendered instructions can point agents at it; refreshed on demand with `/update-model-routing`. |
| `CHANGELOG.md` | Human-readable decision history of AI-made changes — each entry records what changed, the original ask, why that approach, and what was rejected. Proposed by the assistant at session end, written only after you approve. `customize.sh --global` seeds a copy into `~/.claude/` (seed-only; never overwrites). |
| `.github/workflows/ci.yml` | CI: shellcheck every script + run `test.sh` on push / PR. |
| `test.sh` | Smoke tests: render engine, the `load_env` parser, example reproducibility, and installer/uninstaller smoke tests. |

Rendered output (`AGENTS.md`, `CLAUDE.md`), your `my-context.env`,
`extras.local.md`, `mcp-rules.local`, the generated command ports, and the
`verify/` + `audits/` artifacts are **gitignored** — they're personal or
generated; produce them locally. Want to see finished output first? Read
[`examples/aggressive-tailscale.md`](../examples/aggressive-tailscale.md)
(aggressive autonomy, Tailscale serving, all sections on) or
[`examples/balanced-local.md`](../examples/balanced-local.md) (balanced
autonomy, local serving, improve + tools + worktrees + orchestration off).

## 1. The instruction set

`customize.sh` asks (or reads from `my-context.env`):

- **Who you are** — name, pronouns, role, timezone.
- **How you preview/test web & HTML work** — Tailscale, local, or none. The
  HTML-artifact preference stays either way; only the *serving* method changes.

Then it offers the **recommended setup** (every section on, aggressive
autonomy) — press Enter and you're done. Choose "customize" instead to walk
every option:

- **About you** — what you care about; your environment (asked, never assumed).
- **How you like work done** — autonomy posture (aggressive/balanced); whether
  to encourage agent teams (and which roles); subagents for long work.
- **Where your memory lives** — a local file/db store (e.g. Hermes at
  `~/.hermes/`), a notes app over MCP (e.g. Notion, Obsidian), both, or
  generic. Set non-interactively with `MEM_KIND` + `MEM_PATH` / `MEM_TOOL` (or
  override the bullets via `MEM_BLOCK`).
- **Which sections to include** — memory-OS discovery, agent teams,
  parallel worktrees, **orchestrating other AI CLIs** (one session delegating
  headless subtasks to the other installed CLIs — `codex exec`, `agy -p`
  (Antigravity), `claude -p` — for parallel speed and cross-vendor review
  (a model never solely checks its own work). The install records the machine's
  CLI roster at `~/.ai/clis` so sessions read it instead of re-probing, and
  mirrors the advisory model-routing table to `~/.ai/model-routing.md` —
  benchmark-derived per-task-type vendor rankings agents consult when picking a
  delegate (refresh with `/update-model-routing`; other machines pick a
  refreshed table up on their next `git pull && ./install.sh --yes`).
  `~/.ai/` is the machine-level governance/contract layer; operational exhaust
  (logs, hook state) stays in `~/.ai-logs/`. Delegation is coordinated through
  a shared temporary context dir `~/.ai-context/<repo>-<task-slug>/`; set
  `INC_ORCHESTRATION=n` to opt out),
  **local models as delegates** (machines that serve local models — Ollama,
  llama.cpp's `llama-server`, MLX's `mlx_lm.server`, or a remote box over
  Tailscale — get them wired into the same delegation flow. All of these speak
  one OpenAI-compatible API, so the install probes for running servers
  (Ollama at `:11434`; the llama.cpp/MLX default `:8080`), writes the
  machine's registry to `~/.ai/local-models`
  (`name|backend|base_url|model|tier`, tier `strong`/`light` derived from the
  model's parameter count), and installs the `lm` shim to `~/.local/bin` —
  `lm -p "…"` fronts whichever endpoint matches, `lm list` shows health,
  `lm bench` measures tok/s into the registry. Endpoints the probe can't see
  (custom ports, an MLX Mac on the tailnet) are hand-registered via
  `LOCAL_MODELS` in `my-context.env`. A machine with no local models simply
  gets no registry file and every related instruction no-ops — nothing is ever
  installed or started to create one. Machine-specific quality/speed scores
  land in `~/.ai/model-routing.local.md` via `/update-model-routing`; set
  `INC_LOCAL_MODELS=n` to opt out of the bullets and the layer),
  improve-after-larger-changes, tools & MCP servers, output artifacts,
  **design system & UI** (build to the tokens, stay on the scales, WCAG AA,
  honor reduced-motion — **on by default for everyone**; set `INC_DESIGN=n` to
  opt out), project-specific instructions, docs-first, correction capture,
  change log.

## 2. Commands

Portable prompt shortcuts. `commands/*.md` is the **single source of truth**
(Claude dialect). `./render-commands.sh` translates each into the other tools'
dialects under `commands/{codex,cursor}/` — per-tool frontmatter, argument
tokens, and shell-injection (`` !`cmd` `` → "run `cmd`" for Codex/Cursor).
Those ports are **generated and gitignored** — `./install-commands.sh`
re-renders on every run. `./install-commands.sh [tool ...]` installs each into
the right place — Claude `~/.claude/commands/`, Codex skills under
`~/.codex/skills/` (invoked `$<name>`), Cursor `~/.cursor/commands/`. Add a
command once as `commands/<name>.md` and every tool picks it up.

| Command | Does |
|---------|------|
| `/ship` | Tidy gate (format/lint/test, stop if broken) → stage → commit → push, and on a feature branch open + **merge** the PR/MR (squash, delete branch), then return to default. Works with GitHub (`gh`) or GitLab (`glab`). The all-in-one. |
| `/sync` | Fetch + rebase the current branch on the latest default branch. |
| `/worktrees` | One worktree per parallel agent (`ai/<agent>`), converged into a single integration tree a lone dev server watches — several models, near-live. Pairs with `converge.sh`. |
| `/grill-me` | A relentless interview to sharpen a plan or design before you build it — one question at a time, recommended answers offered, environment facts looked up rather than asked, nothing acted on until we reach a shared understanding. |
| `/improve` | Spin up a multi-role review team on the recent diff (architect, back-end, front-end, +UI/UX) for prioritized improvement opportunities. |
| `/verify` | Prove the change is correct & true to spec — build/test, drive the route in a headless browser (responsive screenshots, console/a11y gates, visual regression), and check it against the project briefs (PRODUCT/DESIGN/CODE.md). Writes a served HTML report. |
| `/update-model-routing` | Deep-research current public model benchmarks (SWE-bench Verified, Terminal-Bench, LMArena, …) and refresh `MODEL-ROUTING.md` — the advisory per-task-type vendor rankings mirrored to `~/.ai/model-routing.md`. Shows the diff for approval before anything is kept. Runs in this repo's checkout only. |
| `/ux-audit` | *(design group, skill-backed)* UX audit **from a screenshot**. The full [`ux-audit`](https://github.com/joesteinkamp/ux-audit-skill) skill is vendored at `.agents/skills/ux-audit` and symlinked into `~/.claude/skills`, `~/.codex/skills`, and `~/.cursor/skills` at install — Claude/Codex/Cursor run the real engine (15 heuristic frameworks, 0–100 scores, annotated screenshots). Writes + serves a self-contained HTML report. |

**Command groups.** A command declares `group: <name>` in its frontmatter
(absent ⇒ `core`, always installed). The **`design`** group
(`/ux-audit`) installs **by default for everyone** — everyone should design
better; `--no-design` (or `INC_DESIGN=n`) forces it off and prunes any already
installed, so opting out self-heals. The design pack composes with the
external [project-starter-pack](https://github.com/joesteinkamp/project-starter-pack)
(briefs + `DESIGN.json`); the
[ux-audit skill](https://github.com/joesteinkamp/ux-audit-skill) itself is
**vendored in-repo** at `.agents/skills/ux-audit` (pinned in
`skills-lock.json`; re-sync with `npx skills update`) and this repo is its
installer — `install-commands.sh` symlinks it into `~/.claude/skills`,
`~/.codex/skills`, and `~/.cursor/skills`.

**Improving the ux-audit skill — one-way sync.** The skill is a **separate
project** developed in its own working checkout of the GitHub repo (e.g.
`~/projects/ux-audit-skill`); that checkout is not part of this harness and
nothing here reads from it. Improvements are made there and **pushed to
GitHub**; this repo then pulls the released state with `npx skills update`
(hash-pinned in `skills-lock.json`). Never edit `.agents/skills/ux-audit/`
in place — it's a synced vendor copy and the next update overwrites it.

## 3. Guardrails & observability (hooks)

One set of scripts serves **Claude Code, Codex, Cursor, and Antigravity** — a
`HOOK_PLATFORM` env var (set by the installer) makes each block in the right
dialect (exit-2 for Claude/Codex, `{"permission":"deny"}` for Cursor,
`{"allow_tool":false,"deny_reason":…}`+exit-0 for Antigravity).
`./install-hooks.sh [claude|codex|cursor|antigravity]` merges them into each
tool's config (idempotent, backs up first). Codex surfaces file edits via
`apply_patch`, so path-guard + auto-format are wired there too; Cursor has no
blocking pre-edit event, so its write-protection comes from the permissions
layer while the hook guards secret *reads*. **Antigravity** has its own hooks
schema and its config path lives under `~/.gemini/antigravity-cli/` for
historical reasons — it's in the **default target set**, installing where
present and skipping gracefully otherwise. Full detail in
[`hooks/README.md`](../hooks/README.md).

| Hook | Fires | Does |
|------|-------|------|
| `guard-paths` | before edits | Block edits to `build/ dist/ .next/ node_modules/ .git/`, `.env*`, lockfiles (resolves `..`/symlinks first). |
| `guard-bash` | before shell | Trip on catastrophic `rm -r` (root/home/parent) and force-pushes. Best-effort tripwire, not a sandbox. |
| `format-edited` | after edits | Auto-format the edited file with the project's Prettier/ESLint. |
| `log-tool` | every tool call | **Observability** — append one JSONL record per tool event (secrets redacted, log is `0600`). |
| `quality-nudge` | turn end | Emit at most one **non-blocking advisory** for a material code diff (default ≥4 files or ≥120 lines). Small, docs-only, and artifact-only diffs stay quiet. The note may mention relevant optional verification/review and the Change Log gate, but cannot auto-run a workflow or continue the turn. Claude + Codex + Cursor (Cursor: `followup_message` on `stop` with `loop_limit:1`). |
| `load-memory` | session start | Surface your out-of-tool memory stores (Hermes `~/.hermes/`, OpenClaw, project `MEMORY.md`/`memory/`) so the agent reads them first. Claude + Cursor; silent when none exist. |
| `precompact-archive` | before compaction | Archive the raw transcript to `~/.ai-logs/transcripts/` before Claude compacts, plus a `PreCompact` audit record. Claude only; never blocks. |
| `log-session-end` | session end | Append a `SessionEnd` record (with the end reason) to the audit log, closing the trail. Claude only. |
| `scorecard-enqueue` | session end | Queue a **scorecard survey** for a non-trivial session (marker expires after 2 h; `resume` and already-rated sessions skipped). Claude only. |
| `scorecard-survey` | session start | Offer the pending survey — rate the last session 1–5, why, what to do differently — recorded via `hooks/scorecard.sh`, lesson appended to the memoryOS (`~/.ai/memory-os` registry, written by `setup-memory-os.sh`) and re-injected by `load-memory` next session. Effortless dismissal; at most 2 offers; `AI_SCORECARD=0` disables. Claude + Cursor. |

Read the audit trail with `./audit.sh` (`--stats`, `--follow`, `-n N`). The log
lives at `~/.ai-logs/tool-calls.jsonl` (`$AI_TOOL_LOG`); set `AI_LOG_RESPONSES=0`
to drop tool responses.

### Permissions (client-enforced, per tool)

The guard hooks are a best-effort tripwire. `./install-settings.sh [tool ...]`
adds the **client-enforced** half, mapped to each tool's native model:

- **Claude** — a `permissions` block in `~/.claude/settings.json` whose `deny`
  rules (mirroring `guard-paths` — `.env*`, lockfiles, `build/ dist/
  node_modules/ .git/`) the model can't bypass, plus an `ask` gate (`sudo`).
  Tune via `settings-permissions.snippet.json`.
- **Cursor** — the same `deny` set in `~/.cursor/cli-config.json` (the CLI agent;
  the GUI agent is allowlist-only, so there the read-guard hook is the net).
  Tune via `settings-permissions.cursor.snippet.json`.
- **Codex** — `approval_policy = "on-request"` + `sandbox_mode = "workspace-write"`
  in `~/.codex/config.toml` (a managed, sentinel-delimited block; skipped if you
  already set those keys). Codex's sandbox is directory-scoped, so fine-grained
  path-deny stays with the `guard-paths` hook. Tune via `codex-permissions.snippet.toml`.

Merges are idempotent and backed up; `./uninstall.sh` removes exactly these.

## 4. Validation & verification

Two passes, deliberately different. **`/improve` is opinion** — "could this be
better?" — it reasons about the diff and needs no ground truth. **`/verify` is
evidence** — "is it correct & true to spec?" — it runs the change, drives it, and
diffs it against the design and the briefs, and it can *fail*. They compose:
verify proves it's right, improve asks whether it's good (verify first — no
point polishing a change that doesn't render).

- **`/improve`** spins up parallel subagents — technical architect, back-end,
  front-end, and a UI/UX lens when UI changed — each returning concrete,
  prioritized fixes with `file:line`, then deduped into one summary.
- **`/verify`** runs a lens stack, each emitting **PASS / FAIL / N/A** with
  evidence: ① builds & runs (detects the project's tooling); ② renders in a headless
  browser (`playwright-cli`) — responsive screenshots, console & network gates,
  axe-core a11y (required on touched routes — report rule ID, impact, selector); ③ visual regression vs the last run or the default branch;
  ④ matches the design (Figma via MCP, or `DESIGN.md` + `DESIGN.json` tokens);
  ⑤ conforms to the briefs (`PRODUCT.md`/`DESIGN.md`/`CODE.md` + guardrails —
  pairs with the [project-starter-pack](https://github.com/joesteinkamp/project-starter-pack));
  ⑥ does what it claimed (re-runs the PR/task acceptance criteria). It writes a
  self-contained `verify/<slug>-<date>/report.html` and serves it over your
  preview method — verdict + link inline, findings in the artifact.
- **`quality-nudge`** (Stop hook — Claude, Codex, Cursor) emits one advisory after a
  material code diff. It stays silent for small, documentation-only, and
  artifact-only work; never auto-runs either pass; and never blocks or continues
  a turn. On Cursor the advisory is injected via `followup_message` (`loop_limit:1`;
  the script honors `loop_count` so it cannot chain).

## Customize the wording

Edit `template.md` and re-run `customize.sh`.

- **Add an optional block:** wrap it in `<!--SECTION:name-->` …
  `<!--/SECTION:name-->` (one marker per line) and add a matching `keep` toggle
  in `customize.sh`'s `render()`. `test.sh` asserts every section is wired in.
- **Add an inline `{{VAR}}`:** reference it in the template and add its name to
  the `SUBST_VARS` list near the top of `customize.sh` (that one list drives the
  value passthrough and the substitution). Add it to `my-context.env.example`
  too if users should set it.
- **Add a multi-line block var** (like `{{MEMORY_PATHS}}` / `{{MCP_RULES}}` /
  `{{EXTRAS}}`): put the placeholder alone on its own line and handle it with a
  `line == "{{X}}"` branch in `render()`, not `SUBST_VARS`.

Run `./test.sh` after any change.

## The machine-wide layout

`customize.sh --global` (run by `install.sh`) renders **one** file,
`~/AGENTS.md`, and points each tool at it:

- `~/.codex/AGENTS.md` is a **symlink** — Codex only ever reads that file.
- `~/.claude/CLAUDE.md` is a small **real file** containing `@~/AGENTS.md`
  (Claude Code's documented import syntax) — not a symlink, because Claude
  appends `#` memories and `/memory` edits to this file; through a symlink
  those writes would mutate the shared `~/AGENTS.md` and be wiped by the next
  render. Anything you (or Claude) add below the import line survives
  re-renders untouched. Claude Code shows a one-time approval prompt per
  project for the external import — accept it.

It also maintains the `~/.ai/` governance layer: the CLI roster (`clis`), the
local-model registry (`local-models`) + the `~/.local/bin/lm` shim, and the
model-routing mirror (`model-routing.md`, plus the machine-local
`model-routing.local.md` that `/update-model-routing` writes for local models).

`uninstall.sh` reverses the pointers: each is restored from its newest backup
(taken when the pointer was first installed), or removed if none exists;
`~/AGENTS.md` itself is left in place. The `lm` shim is removed
(marker-checked); the regenerable `~/.ai/` metadata stays.

## Notes

- `my-context.env` (and `team-context.env`) are **parsed, not executed** — only
  known `KEY=VALUE` keys are read (no sourcing), so a stray command in them
  can't run. Values may be single/double quoted and span multiple quoted lines.
- **Precedence:** explicit shell environment variables outrank both context
  files (`INC_DESIGN=n ./customize.sh` wins over a file value), and
  `my-context.env` outranks `team-context.env` key by key.
- Renders and config merges are **atomic** (temp file + move) and back up an
  existing file before overwriting (keeping the 5 newest backups).
- The hooks are a **best-effort safety net, not a security boundary** — they see
  a tool's structured input and match heuristically. See `hooks/README.md`.
- Runs on **bash 3.2+**, so macOS' stock `/bin/bash` works. `jq` is required
  for the hook and settings installers.
