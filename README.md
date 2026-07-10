# Portable AI harness

**Write your AI-assistant preferences once; use them in every tool.** Every
coding assistant — Claude Code, Codex, Gemini, Cursor — reads its
own `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` instruction file. Maintain them by
hand and you keep re-teaching each tool your name, your environment, and how you
like to work — and the files drift out of sync.

- **Without this:** you paste the same preferences into Claude, then Codex, then
  Gemini; you tweak one later; now three files disagree.
- **With this:** you edit one template, run one command, and every tool's
  instruction file is regenerated in sync. Nothing is hardcoded to any one person
  or machine.

## How it works

Three layers — a shared baseline, your personal answers, and the generated
output:

```
template.md      wording + which sections to include    (shared, committed)
      +
my-context.env   your answers: name, env, autonomy …    (personal, gitignored)
      │
      ▼   ./customize.sh
rendered files   CLAUDE.md / AGENTS.md / GEMINI.md       (snapshots — generated)
```

**The rendered files are snapshots — never edit them directly.** Anything you
change there is overwritten on the next render. To change the output, edit
`template.md` (wording, which sections) or `my-context.env` (your answers) and
re-run `./customize.sh`. When you pull updates to this repo, just re-render to
refresh the snapshots — your `my-context.env` is never touched.

## The parts

Independent parts — use any subset; `./install.sh` wires them all:

1. **Instructions** (model-facing) — a customizable `template.md` rendered into
   per-tool instruction files. *Advice* the assistant should follow.
2. **Commands** — slash-command shortcuts (`/ship`, `/sync`, `/worktrees`,
   `/tidy`, `/improve`, `/verify`, `/audit`) for repeatable workflows.
3. **Guardrails & observability** (hooks) — auto-format, block edits to
   generated/sensitive paths, trip on catastrophic shell, log every tool call to
   JSONL, and surface your memory stores at session start. *Enforcement* the
   model can't skip.
4. **Validation & verification** — two complementary passes: a multi-role review
   team for *taste* (`/improve`, "could it be better?") and an evidence-based
   *verification* pass (`/verify`, "is it correct & true to spec?") that runs the
   change, drives it in a browser, and checks it against your project briefs —
   each with a Stop hook that nudges you.
5. **Settings** (per tool) — a client-enforced permissions layer mapped to each
   tool's native model (Claude & Cursor deny rules, Codex sandbox + approval,
   Gemini Policy Engine) that backs up the guard hooks with rules the model
   can't bypass.

## What's here

| File | Purpose |
|------|---------|
| `template.md` | Source of truth for the instructions. Wording + `{{vars}}` + toggleable `<!--SECTION:x-->` blocks. |
| `customize.sh` | Asks questions (or reads `my-context.env`), fills the template, writes the finalized file(s). Also `--scan-mcp`. |
| `my-context.env.example` | Copy to `my-context.env` (gitignored) to save your answers. |
| `examples/` | Two finished sample renders + the `.env` inputs that reproduce them. |
| `install.sh` / `uninstall.sh` | One-shot installer for every layer, and its clean reverse (configs backed up; instruction files left in place). |
| `commands/` + `render-commands.sh` + `install-commands.sh` | Canonical commands (`commands/*.md`) → `render-commands.sh` generates per-tool ports (`commands/{codex,cursor,gemini}/`, committed snapshots so port diffs show up in review) → `install-commands.sh` installs each into its command dir (`~/.claude/commands`, `~/.codex/prompts`, `~/.cursor/commands`, `~/.gemini/commands`). |
| `hooks/` + `install-hooks.sh` | Guardrail + observability hooks → merged into each tool's config (Claude / Codex / Cursor / Gemini). |
| `*-permissions.snippet.*` + `policies/` + `install-settings.sh` | Per-tool permissions: Claude & Cursor `deny` JSON, Codex `config.toml` sandbox+approval, Gemini Policy Engine rules (idempotent, backed up). |
| `audit.sh` | Read back the tool-call audit log — timeline, stats, or live tail. |
| `converge.sh` | Daemon for the `/worktrees` flow: folds parallel agent branches (`ai/*`) into the integration branch as they advance, so one dev server sees every model's work near-live. |
| `sync.sh` | Mirror a rendered `AGENTS.md` to `CLAUDE.md` / `GEMINI.md` in this dir. |
| `sync-global.sh` | Keep the hand-maintained **global** files in sync (`~/.claude/CLAUDE.md` → the others), backing up differences. |
| `DESIGN.example.json` | Sample of the design-token contract the `design` instruction section points at and `/verify`'s "matches the design" lens reads (color/type/space/radius/shadow/breakpoints/motion). Copy into a project as `DESIGN.json` and fill in. |
| `CHANGELOG.md` | Human-readable log of AI-made changes — proposed by the assistant at session end, written only after you approve. `customize.sh --global` seeds a copy into `~/.claude/` (seed-only; never overwrites an accumulated one). |
| `.github/workflows/ci.yml` | CI: shellcheck every script + run `test.sh` on push / PR. |
| `test.sh` | Smoke tests: render engine, the `load_env` parser, example reproducibility, and installer/uninstaller smoke tests. |

Rendered output (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`), your `my-context.env`,
`mcp-rules.local`, and the `verify/` + `audits/` artifacts are **gitignored** —
they're personal, generate them locally. Want to see finished output first? Read
[`examples/aggressive-tailscale.md`](examples/aggressive-tailscale.md) (aggressive
autonomy, Tailscale serving, all sections on) or
[`examples/balanced-local.md`](examples/balanced-local.md) (balanced autonomy,
local serving, improve + tools + worktrees off).

## Quick start

```bash
# 1. (optional) save your answers so re-running is zero-prompt
cp my-context.env.example my-context.env && $EDITOR my-context.env

# 2. (optional) detect your MCP servers and add per-server usage rules
./customize.sh --scan-mcp      # writes mcp-rules.local (gitignored)

# 3. preview, then install everything in one shot
./customize.sh --print         # see the instructions first — writes nothing
./install.sh                   # instructions + commands + hooks + settings
                               #   asks once to confirm the global render
                               #   (each file is backed up first); --yes skips it
```

`./install.sh` orchestrates the focused scripts so you don't have to remember the
order. Target specific tools and reverse it cleanly:

```bash
./install.sh --yes             # all tools (claude codex cursor gemini), no prompt
./install.sh claude            # just Claude Code (all layers)
./install.sh codex cursor      # instructions + commands + hooks + settings for those
./uninstall.sh                 # strip our hooks/permissions/commands (configs
                               #   backed up; instruction files left in place)
```

Prefer to run the pieces yourself, or render without installing:

```bash
./customize.sh                 # interactive: asks questions, then writes
./customize.sh --global        # render all four instruction files machine-wide
./customize.sh --project       # write AGENTS.md + CLAUDE.md + GEMINI.md here
./install-commands.sh          # /ship, /sync, /audit, ... in every tool
./install-hooks.sh             # guardrails + logging across all tools
./install-settings.sh          # per-tool permissions layer
```

All non-interactive modes read your saved `my-context.env`.

## 1. The instruction set

`customize.sh` asks (or reads from `my-context.env`):

- **Who you are** — name, pronouns, role, timezone.
- **Your environment** — asked, never assumed (headless server, laptop with a
  browser, …). Leave blank to omit the line.
- **How you preview/test web & HTML work** — Tailscale, local, or none. The
  HTML-artifact preference stays either way; only the *serving* method changes.
- **How you like work done** — a **primary focus** persona
  (`product-designer` / `engineer` / `generic`) that seeds sensible defaults
  without locking you in; autonomy posture (aggressive/balanced); whether to
  encourage agent teams (and which roles); subagents for long work.
- **Where your memory lives** — when the memory-OS section is on, it asks
  whether your memory is a local file/db store (e.g. Hermes at `~/.hermes/`), a
  notes app reached over MCP (e.g. Notion, Obsidian), both, or generic — and
  tailors what the agent is told to look for. Set non-interactively with
  `MEM_KIND` + `MEM_PATH` / `MEM_TOOL` (or override the bullets via `MEM_BLOCK`).
- **Which sections to include** — memory-OS discovery, agent teams,
  improve-after-larger-changes, tools & MCP servers, output artifacts,
  **design system & UI** (build to the tokens, stay on the scales, WCAG AA,
  honor reduced-motion — on by default under the `product-designer` persona),
  project-specific instructions, docs-first, correction capture, change log
  (propose an entry + get approval at session end). Leave `INC_DESIGN` blank to
  let the persona decide; set it `y`/`n` to override.

## 2. Commands

Portable prompt shortcuts. `commands/*.md` is the **single source of truth**
(Claude dialect). `./render-commands.sh` translates each into the other tools'
dialects under `commands/{codex,cursor,gemini}/` — per-tool frontmatter, argument
tokens (`$ARGUMENTS` → `{{args}}` for Gemini), and shell-injection (`` !`cmd` `` →
`!{cmd}` for Gemini, → "run `cmd`" for Codex/Cursor). Those ports are **generated
snapshots** — never hand-edit them; `./install-commands.sh` re-renders on every
run, so hand-edits never reach your tools. `./install-commands.sh [tool ...]` re-renders, then installs
each into the right place — Claude `~/.claude/commands/`, Codex `~/.codex/prompts/`
(invoked `/prompts:<name>`), Cursor `~/.cursor/commands/`, Gemini
`~/.gemini/commands/` (`.toml`). Add a command once as `commands/<name>.md` and
all four tools pick it up.

| Command | Does |
|---------|------|
| `/ship` | Stage → commit → push, and on a feature branch open + **merge** the PR/MR (squash, delete branch), then return to default. Works with GitHub (`gh`) or GitLab (`glab`). The all-in-one. |
| `/sync` | Fetch + rebase the current branch on the latest default branch. |
| `/worktrees` | One worktree per parallel agent (`ai/<agent>`), converged into a single integration tree a lone dev server watches — several models, near-live. Pairs with `converge.sh`. |
| `/tidy` | Run the project's formatter/linter/tests and fix what's safe. |
| `/improve` | Spin up a multi-role review team on the recent diff (architect, back-end, front-end, +UI/UX) for prioritized improvement opportunities. |
| `/verify` | Prove the change is correct & true to spec — build/test, drive the route in a headless browser (responsive screenshots, console/a11y gates, visual regression), and check it against the project briefs (PRODUCT/DESIGN/CODE.md). Writes a served HTML report. |
| `/audit` | Run the [`ux-audit`](https://github.com/joesteinkamp/ux-audit-skill) skill on a screenshot — scores against 15 UX heuristic frameworks, writes a self-contained HTML report, and serves it. |

## 3. Guardrails & observability (hooks)

One set of scripts serves **Claude Code, Codex, Cursor, Gemini (CLI), and
Antigravity** — a `HOOK_PLATFORM` env var (set by the installer) makes each block
in the right dialect (exit-2 for Claude/Codex, `{"decision":"deny"}` for Gemini,
`{"permission":"deny"}` for Cursor, `{"allow_tool":false,"deny_reason":…}`+exit-0
for Antigravity). `./install-hooks.sh [claude|codex|cursor|gemini|antigravity]`
merges them into each tool's config (idempotent, backs up first). Codex now
surfaces file edits via `apply_patch`, so path-guard + auto-format are wired
there too; Cursor has no blocking pre-edit event, so its write-protection comes
from the permissions layer while the hook guards secret *reads*. **Antigravity**
is a separate tool from the Gemini CLI with its own `~/.gemini/antigravity-cli/
hooks.json` schema — it's **opt-in** (`./install-hooks.sh antigravity`), not in
the default set. Full detail in [`hooks/README.md`](hooks/README.md).

| Hook | Fires | Does |
|------|-------|------|
| `guard-paths` | before edits | Block edits to `build/ dist/ .next/ node_modules/ .git/`, `.env*`, lockfiles (resolves `..`/symlinks first). |
| `guard-bash` | before shell | Trip on catastrophic `rm -r` (root/home/parent) and force-pushes. Best-effort tripwire, not a sandbox. |
| `format-edited` | after edits | Auto-format the edited file with the project's Prettier/ESLint. |
| `log-tool` | every tool call | **Observability** — append one JSONL record per tool event (secrets redacted, log is `0600`). |
| `improve-nudge` | turn end | When a turn ends with a large diff, nudge you to run `/improve` (once per distinct diff). |
| `verify-nudge` | turn end | When a turn ends with a UI/route change and no fresh `verify/` report, nudge you to run `/verify` (once per distinct diff; self-silences once verified). |
| `changelog-nudge` | turn end | When a session ends with changes, remind you to **propose a Change Log entry and approve it before it's written** (never auto-writes). Once per distinct diff. Pairs with the `changelog` instruction section. |
| `load-memory` | session start | Surface your out-of-tool memory stores (Hermes `~/.hermes/`, OpenClaw, project `MEMORY.md`/`memory/`) so the agent reads them first. Claude + Cursor (the tools with SessionStart context injection); silent when none exist. |
| `precompact-archive` | before compaction | Archive the raw transcript to `~/.ai-logs/transcripts/` before Claude compacts and drops detail, plus a `PreCompact` audit record. Claude only; never blocks. |
| `log-session-end` | session end | Append a `SessionEnd` record (with the end reason) to the audit log, closing the trail. Claude only; observability. |

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
- **Gemini** — Policy Engine `deny`/`ask_user` rules dropped at
  `~/.gemini/policies/gemini-guardrails.toml`, plus `folderTrust` enabled.

Merges are idempotent and backed up; `./uninstall.sh` removes exactly these.

## 4. Validation & verification

Two passes, deliberately different. **`/improve` is opinion** — "could this be
better?" — it reasons about the diff and needs no ground truth. **`/verify` is
evidence** — "is it correct & true to spec?" — it runs the change, drives it, and
diffs it against the design and the briefs, and it can *fail*. They compose: verify
proves it's right, improve asks whether it's good (verify first — no point polishing
a change that doesn't render).

- **`/improve`** spins up parallel subagents — technical architect, back-end,
  front-end, and a UI/UX lens when UI changed — each returning concrete,
  prioritized fixes with `file:line`, then deduped into one summary.
- **`/verify`** runs a lens stack, each emitting **PASS / FAIL / N/A** with
  evidence: ① builds & runs (reuses `/tidy` detection); ② renders in a headless
  browser (Playwright) — responsive screenshots (mobile/tablet/desktop), console
  & network gates, axe-core a11y; ③ visual regression vs the last run or the
  default branch; ④ matches the design (Figma via MCP, or `DESIGN.md` +
  `DESIGN.json` tokens); ⑤ conforms to the briefs (`PRODUCT.md`/`DESIGN.md`/
  `CODE.md` + guardrails — pairs with the [project-starter-pack](https://github.com/joesteinkamp/project-starter-pack));
  ⑥ does what it claimed (re-runs the PR/task acceptance criteria). It writes a
  self-contained `verify/<slug>-<date>/report.html` and serves it over your preview
  method — verdict + link inline, findings in the artifact.
- **`improve-nudge`** (Stop hook — Claude, Codex, Cursor) reminds you to run the
  review when a turn ends with a diff over `IMPROVE_MIN_FILES`/`IMPROVE_MIN_LINES`
  (default 8 files / 200 lines), firing once per distinct diff.
- **`verify-nudge`** (Stop hook — Claude, Codex, Cursor) reminds you to verify
  when a turn ends with a UI/route change (override the match with `VERIFY_UI_RE`)
  and no `verify/` report newer than the change exists. Fires once per distinct
  diff and self-silences once you've verified.

## Updating over time

Rendered files are snapshots. After you improve `template.md` (or pull this
repo), re-render — your answers live in `my-context.env`, so it's one command:

```bash
git pull
./install.sh --yes             # re-render + re-install every layer, zero prompts
```

## For teams

The committed `template.md` is the **shared baseline**; each person's gitignored
`my-context.env` is their **personal layer**. Fork the repo, edit `template.md`
to encode team norms, and everyone runs `./customize.sh --global` with their own
answers.

## Customize the wording

Edit `template.md` and re-run `customize.sh`.

- **Add an optional block:** wrap it in `<!--SECTION:name-->` …
  `<!--/SECTION:name-->` (one marker per line) and add a matching `keep` toggle
  in `customize.sh`'s `render()`. `test.sh` asserts every section is wired in.
- **Add an inline `{{VAR}}`:** reference it in the template and add its name to
  the `SUBST_VARS` list near the top of `customize.sh` (that one list drives the
  value passthrough and the substitution). Add it to `my-context.env.example`
  too if users should set it.
- **Add a multi-line block var** (like `{{MEMORY_PATHS}}` / `{{MCP_RULES}}`):
  put the placeholder alone on its own line and handle it with a
  `line == "{{X}}"` branch in `render()`, not `SUBST_VARS`.

Run `./test.sh` after any change.

## Notes

- `my-context.env` is **parsed, not executed** — only known `KEY=VALUE` keys are
  read (no sourcing), so a stray command in it can't run. Values may be
  single/double quoted and span multiple quoted lines.
- Renders and config merges are **atomic** (temp file + move) and back up an
  existing file before overwriting (keeping the 5 newest backups).
- The hooks are a **best-effort safety net, not a security boundary** — they see
  a tool's structured input and match heuristically. See `hooks/README.md`.
- Runs on **bash 3.2+**, so macOS' stock `/bin/bash` works — no `brew install
  bash` needed. `jq` is required for the hook and settings installers.

## License

[MIT](LICENSE) — copy it, fork it, make it yours.
