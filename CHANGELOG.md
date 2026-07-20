# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Entries are proposed by the AI assistant at the end of a session and written
only after human approval (see the `changelog` instruction section and the
`changelog-nudge` hook).

## [Unreleased]

### Added
- **Cross-tool orchestration: one session can delegate to the machine's other
  AI CLIs (2026-07-20, Claude).** New `cross-tool-orchestration` template
  section (toggle `INC_ORCHESTRATION`, on by default) teaching any host tool
  to hand subtasks to the other installed CLIs headless (`codex exec`,
  `agy -p`, `claude -p`, `agent -p`) — for parallel speed and for
  cross-vendor review, since a model must never be the sole checker of its
  own work. Delegation is coordinated through a shared temp context dir
  (`~/.ai-context/<repo>-<task-slug>/`: `TASK.md` / `STATE.md` /
  `agents/<name>.md`), with one-writer-per-file ownership, sandboxed
  never-bypass execution, one-level-only delegation, and all confirmation
  gates inherited. `customize.sh --global` now also records the installed-CLI
  roster at `~/.ai-logs/ai-clis` so sessions read a file instead of
  re-probing. `/improve` and `/verify` gained a cross-vendor pass that
  spreads review lenses / second-opinion grading across the other vendors,
  reading their full findings from the context dir rather than stdout.
  Examples and GUIDE regenerated; suite 104 → 107.

### Changed
- **Verify/improve are now nudge-only (2026-07-20, Claude).** The "When to
  verify & improve" template section no longer tells agents to auto-run
  `/verify`/`/improve` on large asks or ask about mid-size ones — models were
  running full review passes on trivial changes (Codex especially). The Stop
  hooks (`verify-nudge`/`improve-nudge`) are now the sole trigger, with their
  existing size/UI thresholds; explicit user requests still work at any size.
  Also removed the Design section's standalone "run `/verify` before handoff"
  (a second auto-run trigger) and updated the installer prompt wording.
  Examples re-rendered.
- **`/ux-audit` merged with its skill; this repo is now the installer
  (2026-07-19, Claude).** Vendored
  [joesteinkamp/ux-audit-skill](https://github.com/joesteinkamp/ux-audit-skill)
  at `.agents/skills/ux-audit` (pinned in `skills-lock.json`, re-sync via
  `npx skills update`). New opt-in `skill-backed: true` frontmatter:
  `install-commands.sh` symlinks the real skill into `~/.claude/skills` +
  `~/.codex/skills` instead of the wrapper command — one `/ux-audit`, no
  duplicate menu entry; Cursor/Gemini keep the wrapper's inline fallback.
  Uninstall removes the links; retired names `audit`/`critique` now self-heal
  on other machines (pruned **with a backup**, since a user could own an
  identically-named command). Fixed a write-through-symlink clobber found
  during the work and the SC2043 shellcheck warning that had CI red since the
  `/critique` removal. A post-change multi-role review then hardened the
  mechanism: dangling skill links of ours (skill renamed/dropped upstream) are
  now pruned by both install and uninstall, the "is this symlink ours" safety
  predicate is a single shared helper (`is_our_skill_link`, prefix-matched) in
  both scripts, and the `commands/README.md` wording was corrected to match
  the opt-in (not name-matched) design. Suite 100 → 104, including new
  data-safety regression tests (user-owned skill dirs/links never touched,
  vendored source never clobbered). Documented the one-way sync: the skill is
  developed in its own checkout of the GitHub repo and flows GitHub → here via
  `npx skills update`; the vendored copy is never edited in place.

### Added
- **`/grill-me` promoted to a globally-installed command (2026-07-19, Claude).** Previously only worked as a project-scoped Skill inside this repo's own checkout (`.agents/skills/grill-me`, vendored via `npx skills`). Added `commands/grill-me.md` — a self-contained canonical command (inlines the `grilling` interview instructions rather than delegating to the `grilling` skill, since the per-tool render pipeline has no cross-skill invocation) — so `/grill-me` (`$grill-me` on Codex) now installs and works in any project via `render-commands.sh` + `install-commands.sh`, same as `/ship`/`/improve`. Documented in `commands/README.md`, `README.md`'s "What you get", and `docs/GUIDE.md`. The vendored project-scoped Skill is left in place (still `npx skills`-synced, still used by `grill-with-docs`) — note this means the interview wording now has two copies that could drift if upstream updates the vendored one.

### Changed
- **Rename `/audit` → `/ux-audit` (2026-07-19, Claude).** Clearer name for the
  screenshot UX audit command; design group is now `/ux-audit`. Docs,
  `install-commands.sh` comments, and `test.sh` updated; ports re-rendered and
  reinstalled across all four tools. Note: in Claude Code the name now matches
  the `ux-audit` skill the command delegates to — intentional overlap.

### Removed
- **`/critique` (2026-07-19, Claude).** Dropped the pre-pixel critique command
  (`commands/critique.md`) and its generated ports (Codex skill, Cursor,
  Gemini) plus the installed copies in all four tools' global dirs. The design
  command group is now just `/audit`. Updated docs (`README.md`,
  `commands/README.md`, `docs/GUIDE.md`), `install-commands.sh` comments,
  `.gitignore` (`/critiques/` entry), and `test.sh` (design-group counts 2→1,
  prune-safety test now uses `audit.md`). Reason: per Joe's request — command
  removed from the harness.

### Added
- **Personal layers that survive every render (2026-07-17/18, Claude).**
  `extras.local.md` (gitignored) is spliced verbatim into every render at a new
  `{{EXTRAS}}` placeholder — personal sections the shared template can't
  express (e.g. machine-specific serving notes) no longer live as hand-edits
  in rendered output. A committed `team-context.env` loads before
  `my-context.env` (personal values win key by key) as a team fork's shared
  answer baseline. Explicit shell env vars now outrank both context files.
- **Recommended-setup quick path.** The interactive interview asks a handful
  of identity/preview questions, then one "use the recommended setup?" prompt
  (Enter accepts); "customize" drops into the full question-by-question flow.
- Tests for the extras splice, env-var precedence, skills-tree parity, the
  global-pointer layout (including render-failure and uninstall-restore
  paths) — suite grew 92 → 97.

### Changed
- **Global install collapsed to one rendered `~/AGENTS.md` + per-tool
  pointers.** `~/.codex/AGENTS.md` and `~/.gemini/GEMINI.md` are symlinks;
  `~/.claude/CLAUDE.md` is a real pointer file holding `@~/AGENTS.md` (Claude
  Code's documented import) so `#` memories and Claude-only additions
  accumulate below the import instead of mutating the shared file. A failed
  render never touches the pointers, and `uninstall.sh` restores each pointer
  from its newest backup (or removes it). Verified against Claude Code,
  Gemini CLI, and Codex docs.
- **Design is on for everyone.** The "Design system & UI" section and the
  design command group (`/audit`, `/critique`) now default on regardless of
  persona (`INC_DESIGN=n` / `--no-design` opts out); `PERSONA` is accepted for
  back-compat but no longer changes any default.
- **`.claude/skills/` deduped to symlinks** into the canonical
  `.agents/skills/` tree; CI asserts the links.
- **Generated command ports untracked.** `commands/{codex,cursor,gemini}/` are
  gitignored and re-rendered on every install (and before uninstall), so a
  command change is a one-file diff.
- **README split into a short pitch + `docs/GUIDE.md`**, with a promoted team
  onboarding story; quick start now leads with `my-context.env` (the
  interactive interview doesn't persist answers) and lists the `jq`
  prerequisite. Examples re-rendered with the design section.

### Removed
- `sync.sh` and `sync-global.sh` — with the template as single source of truth
  plus the extras layer and pointer layout, there is nothing left to hand-sync.

### Added
- **Ask-aware triggering for `/verify` and `/improve`, with consume-once skip
  markers.** Rewrote `template.md`'s improve section (now **"When to verify &
  improve"**) so the decision keys off the *ask*, not just the resulting diff:
  large/greenfield asks (setup, a new feature, a big refactor) **auto-run** both
  `/verify` and `/improve` and hand back a ready-to-apply plan; applying changes
  I already approved **skips** them (re-running loops); mid-size iteration
  **asks up front**; trivial does neither. The `improve-nudge` / `verify-nudge`
  Stop hooks stay as the diff-size backstop and now honor a consume-once skip
  file in `$AI_NUDGE_STATE` — `.nudge-skip-{improve,verify}.<key>` — so applying
  an already-reviewed change doesn't re-nag. Documented `verify-nudge` in the
  hooks README (previously undocumented) plus the skip protocol; updated the
  `customize.sh` section prompt; added hook tests.
- **Vendored `grill-me` / `grill-with-docs` Skills across all 4 tools.** Installed
  [mattpocock/skills.sh](https://skills.sh)'s `grill-me` and `grill-with-docs`
  (pre-build "grilling" interviews that stress-test a plan one question at a
  time) plus their required primitives `grilling` and `domain-modeling` via
  `npx skills`, project-scoped so they ship with the repo: `.claude/skills/`
  for Claude Code, and the shared Agent-Skills-standard `.agents/skills/` for
  Codex, Cursor, and Gemini CLI — 4-way parity, matching the existing
  `commands/` convention. `grill-me` is stateless (nothing persists past the
  conversation); `grill-with-docs` runs the same interview but writes durable
  ADRs and a glossary via `domain-modeling`. One `skills-lock.json` pins each
  skill's upstream source path + content hash; re-sync anytime with
  `npx skills update` from the repo root. Documented in README's "What's
  here" table.

### Changed
- **Reshape `/verify` into a product-grade evaluation.** It was a binary
  PASS/FAIL/N/A evidence gate on the diff; now it grades the work as a product
  increment — establishes the session's goal as the yardstick, keeps the
  build/run/browser evidence as the floor, then grades A–F across goal fit,
  experience quality, design/a11y, and product fit, and reconciles divergence
  from the briefs as *intentional evolution* (docs to update) vs *drift*
  (regression) so it never fails against stale docs.
- **`/verify` and `/improve` report inline and prepare to act.** Both were
  report-only; they now turn findings into a prioritized, ready-to-apply plan
  and apply on my go-ahead (nothing edited until I approve). Both report inline
  by default, with the self-contained HTML report offered on request (verify
  was previously artifact-mandatory). Re-rendered the Codex/Cursor/Gemini ports
  and updated `commands/README.md`.
- **Fold `/tidy` into `/ship`'s pre-commit gate.** Added a tidy step (format →
  lint → test, stop if broken) as step 2 of `/ship`, so the lint/test gate runs
  automatically before every commit instead of requiring a separate `/tidy`
  invocation to remember. Re-rendered the Codex/Cursor/Gemini ports and updated
  `commands/README.md`'s `/ship` description to match. Motivated by a review of
  which of the 10 slash commands actually need to be memorized vs. run
  automatically — `/verify` and `/improve` already self-trigger via Stop-hook
  nudges; `/tidy` was the one gap.
- Clarify the prompt for the "improve after larger changes" section in [customize.sh](file:///home/jsteinka/projects/agent-global-instructions/customize.sh) by rewriting it to "Include 'auto run improve command after larger changes' section?".
- In [customize.sh](file:///home/jsteinka/projects/agent-global-instructions/customize.sh): Clarified other section prompts by adding descriptive/explanatory details for "design system & UI", "project-specific instructions", "documentation first", "when I say you did wrong", and "change log".

### Fixed
- **Completed the Codex slash-commands → Skills migration.** Codex doesn't
  support custom slash commands like Claude Code does — only Skills (a
  directory per skill: `SKILL.md`, invoked `$<name>`). Finished the in-progress
  port: `render-commands.sh` generates `commands/codex/<name>/SKILL.md`,
  `install-commands.sh`/`uninstall.sh` install/remove them at
  `~/.codex/skills/<name>/`, and the `verify`/`improve` nudge hooks point at
  `$verify`/`$improve`. Fixed a `.gitignore` bug where unanchored `verify/` and
  `handoff/` patterns (meant for local generated review-artifact dirs) were
  silently excluding the new `commands/codex/verify/` and
  `commands/codex/handoff/` skill directories from git — anchored those
  patterns (and `ports/`) to the repo root. A follow-up review then found the
  new directory-based install/uninstall logic had reused file-oriented
  cleanup code that didn't fully account for directories: retired/renamed
  skills never got uninstalled (self-heals now, mirroring how the other three
  tools prune `RETIRED` names); the repo-side prune loop did an unguarded
  `rm -rf` on any non-generated directory dropped under `commands/codex/`
  (now gated on the `GENERATED` marker); uninstall/prune left an empty skill
  directory behind (now `rmdir`'d); and a skill description containing a
  `"` would have silently corrupted the generated YAML frontmatter (now
  escaped, matching the existing Gemini/TOML handling). 89 tests still pass;
  +1 assertion locks in the empty-dir cleanup.

- **/audit portable fallback + design-group prune hardening.** `/audit` now runs
  an inline heuristic audit (Nielsen, Gestalt, WCAG 2.2 AA, Fitts/Hick/Miller,
  dark patterns; view-the-image guard so a vision-less tool stops instead of
  guessing) on tools without skill support — it was effectively dead on
  Codex/Cursor/Gemini, whose ports delegated to the Claude-only `ux-audit`
  skill. A persona-resolver *error* on `install-commands.sh`'s auto path now
  warns and leaves installed design commands in place instead of silently
  pruning them (a real "n" still prunes); prune/reinstall messages point at the
  hand-edit backups they create, so a persona toggle can't silently orphan your
  edits. +4 tests locking in prune-safety, the auto-resolve path, gemini `.toml`
  gating, and `install.sh` flag forwarding (89 total).

### Added
- **Design command pack (persona-gated group).** A command opts into a group via
  a `group:` frontmatter key; the new **`design`** group installs only when your
  persona / `INC_DESIGN` wants it (`install-commands.sh --design` / `--no-design`,
  auto-resolved via `customize.sh --design-group`) and prunes when turned off, so
  switching personas self-heals. Ships three gap commands that *compose with, not
  duplicate,* the external `project-starter-pack` (briefs + `DESIGN.json`) and
  `ux-audit` (screenshot audits): **`/handoff`** (developer handoff — states,
  tokens, a11y, acceptance), **`/critique`** (pre-pixel heuristic review of a
  flow/spec/idea), **`/flow`** (user-flow / journey-map artifact); moved `/audit`
  into the group. Ports are still generated for every command — the group only
  gates what's installed, keeping engineers' set clean.
- **Persona-aware, design-leaning harness (P0 #1–#4).** New `PERSONA` preset
  (`product-designer` / `engineer` / `generic`, default `generic`) that seeds an
  optional, toggleable **"Design system & UI"** instruction section
  (`INC_DESIGN`, off by default; an explicit `y`/`n` always overrides the
  persona). Filled the previously-empty `/improve` **UI/UX lens** with a concrete
  heuristics rubric (Nielsen, WCAG 2.2 AA, Gestalt, Fitts/Hick, design-system
  consistency, responsive + reduced-motion). Defined the `DESIGN.json` **token
  contract** that `/verify`'s "matches the design" lens reads (its canonical
  source is the external `project-starter-pack`); added a `prefers-reduced-motion`
  a11y gate to `/verify` and made its responsive matrix honor `DESIGN.json`
  breakpoints. The
  general substrate stays neutral for engineers; it leans product-designer only
  when opted in.
- **Real Antigravity hook support** (opt-in target). Antigravity is a *separate*
  tool from the Gemini CLI — it reads its own `~/.gemini/antigravity-cli/hooks.json`,
  which the previous `antigravity` alias (writing the Gemini CLI's
  `~/.gemini/settings.json`) never reached. `./install-hooks.sh antigravity` now
  wires the real thing, verified against the `agy` binary (proto + embedded docs;
  `agy` loads our generated `hooks.json` — "loaded 4 named hooks"):
  - New `HOOK_PLATFORM=antigravity` block dialect — stdout
    `{"allow_tool":false,"deny_reason":…}` with **exit 0** (a non-zero exit is a
    hook *failure*, not a block).
  - `guard-bash`/`guard-paths`/`format-edited`/`log-tool` read the Antigravity
    input shape (`toolCall.args.CommandLine` / `.TargetFile`).
  - Installer writes top-level **named hooks** with tool-name matchers
    (`run_command`; `write_to_file|replace_file_content|multi_replace_file_content`)
    and drops `*.ag.sh` wrappers that set `HOOK_PLATFORM` (agy invokes hooks by
    absolute path). Idempotent; `uninstall.sh antigravity` strips exactly the
    `aigi-*` named hooks, preserving user hooks. Opt-in — not in the default set;
    skips gracefully if `~/.gemini/antigravity-cli` is absent.
  - `install-commands.sh`/`install-settings.sh` no longer alias `antigravity` to
    the Gemini CLI — they skip it with a note (Antigravity has its own command &
    `permissions.allow/deny` models).
  - Caveat: schema and hook-script output are verified, but live deny-firing must
    be confirmed in an interactive `agy` session (print mode bypasses the
    interactive hook path). See `hooks/README.md`.

### Fixed
- Commands now install on Codex/Cursor/Gemini on macOS. `render-commands.sh`
  deleted the committed ports *before* regenerating, and the bare `mktemp` in
  `emit()` errors on macOS (BSD requires a template) — so the render aborted with
  the port dirs already emptied and zero commands installed (Claude survived; it
  installs from the never-deleted top-level `commands/*.md`). `emit()` now uses a
  same-dir `mktemp` template (atomic + BSD-valid), render **generates-then-prunes**
  (a failed render can no longer empty the dirs), and `install-commands.sh`
  **aborts** on render failure instead of installing from a half-rendered dir.
- The same macOS-breaking bare `mktemp` is fixed across `install-hooks.sh`,
  `install-settings.sh`, `uninstall.sh`, and `test.sh` (8 call sites) — the
  hooks/settings/uninstall layers would otherwise fail the same way on macOS.
- `install-settings.sh` codex block is idempotent again — it grew one blank line
  (and wrote a fresh backup) on every re-run.
- `hooks/guard-bash.sh` matches per command **segment**: `rm -rf dist && cd /`
  is no longer misread as `rm … /`, while wrapped catastrophic deletes
  (`sudo rm -rf /`, `/usr/bin/rm -rf /`) are still blocked. Force-push detection
  is per-segment too (a chained `tar -xf …` no longer false-trips), and a
  `+refspec`/`-f` force is caught even alongside `--force-with-lease`.
- `hooks/guard-paths.sh` stops blocking committed `.env.example`/`.template`
  samples and now guards `NotebookEdit` (`notebook_path`); `format-edited.sh` too.
- `hooks/log-tool.sh` redaction covers `sk_live_`/`sk_test_`, `Authorization:
  Basic`, Slack/Google/GitHub-PAT tokens, and PEM private keys (PEM masked before
  the key/value rule so its marker survives); appends under `flock` to avoid
  interleaved records; `basic` matcher tightened so ordinary prose is not masked.
- `audit.sh` tolerates a malformed/interleaved log line instead of aborting, and
  `-n` as the final argument no longer crashes under `set -e`.
- `customize.sh` registers render temps so the cleanup trap fires, and skips
  rewriting an unchanged file. Dropped the dead `TS_IP` var (prompted but never
  rendered).
- `uninstall.sh` gained `--project` (reverses project command installs) and
  clears Cursor's leftover `{"version":1}`. Installers skip backing up a config
  they just seeded empty.
- `sync-global.sh` writes via atomic temp+rename. `converge.sh` can fold
  remote-only `ai/*` (`CONVERGE_REMOTE`) and its conflict markers are gitignored.

### Changed
- `test.sh` asserts every `SUBST_VAR` is referenced in `template.md` (the gap
  that hid the dead `TS_IP`) and adds guard-bash regression tests for the
  catastrophic-rm / force-push behavior. README corrected: command ports are
  committed (not gitignored), and `jq` is for the hook/settings installers (not
  the MCP scanner).

### Added
- Change Log workflow: `changelog-nudge` Stop hook + a `changelog` section in
  `template.md` (`INC_CHANGELOG`). At session end the agent proposes a Change Log
  entry and requires human approval before writing it.
- Session-lifecycle hooks: `precompact-archive` (archives the raw transcript
  before context compaction) and `log-session-end` (writes a `SessionEnd`
  record); both Claude-only, surfaced via `audit.sh`.

### Changed
- `install-hooks.sh` wires the new Stop/PreCompact/SessionEnd hooks; `customize.sh`,
  `my-context.env.example`, and the examples updated for the new section.
- `/verify` lenses sharpened: lens 2 marks Playwright/axe **N/A** when they can't
  be installed instead of faking a result; lens 3 names a concrete pixel-diff tool
  (`toHaveScreenshot`/`pixelmatch`/ImageMagick `compare`); the report slug is
  pinned to `YYYY-MM-DD`. The `verify-nudge` hook no longer trips on doc-only
  (`.md`) edits. Per-tool ports regenerated from the canonical command.
- `customize.sh --global` seeds `CHANGELOG.md` into `~/.claude/` (seed-only —
  never overwrites an existing global changelog, so entries accumulate).
