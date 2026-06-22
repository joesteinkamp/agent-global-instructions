# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Entries are proposed by the AI assistant at the end of a session and written
only after human approval (see the `changelog` instruction section and the
`changelog-nudge` hook).

## [Unreleased]

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
