# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Entries are proposed by the AI assistant at the end of a session and written
only after human approval (see the `changelog` instruction section and the
`changelog-nudge` hook).

## [Unreleased]

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
