# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Entries are proposed by the AI assistant at the end of a session and written
only after human approval (see the `changelog` instruction section and the
`quality-nudge` hook). Each entry records the decision behind the change —
the original ask, why this approach, and what was considered and rejected —
so the log reads as the project's decision history, not just a list of diffs.

## [Unreleased]

### Changed
- **Teach agents the host's full autonomy surface, and plan before running
  (2026-09-04, Claude Opus 5).** The ask: Joe asked that agents use the most
  useful tools each vendor offers so they run more autonomously, and nudge him
  toward capabilities he isn't using; then that they do more initial planning,
  with the `grill-me` command as the way in. What changed: `template.md` gains
  an autonomy-surface bullet, a gated pointer to the per-tool map, a nudge rule
  bounded to one per handoff, a definition of *handoff* at first use in both
  autonomy variants, and a new "Plan before you run" block placed outside both
  autonomy sections so it applies under either posture;
  `playbooks/orchestration.md` gains "Running longer than a turn" with a
  per-host capability table, and states why the rival-draft pattern depends on
  the plan being a file. Why this approach: naming only `/loop` and `/goal` left
  the rest of each vendor's unattended-execution surface unused, and an agent
  assumes absent what it has not used before. Autonomy does not end when an
  agent runs out of capability — it ends when it hits a question nobody
  answered, so front-loading questions is what buys unattended runtime, and that
  is what ties planning to autonomy rather than trading against it. The planning
  trigger reuses the existing foundational-framing condition instead of
  inventing new vocabulary, and the block states outright that applying it to
  ordinary tasks is the failure mode, because a planning gate that fires on
  small fixes gets switched off within a week. The plan-is-a-file rule is
  load-bearing for the rival-draft pattern committed earlier: three plans living
  in three transcripts cannot be diffed. *handoff* was defined because seven
  rules depended on it — including the hard gate "don't call work done, hand it
  off, or ship while a verify is pending" — and reading it as "every turn"
  rather than "the end of a task" would have made the nudge rule fire
  constantly and the verify gate block mid-task work. The falsifier rule was
  earned in the same session: a cross-CLI delegation failure was misdiagnosed as
  an Ubuntu bubblewrap problem, and stating the constraint "any root cause must
  also explain macOS" up front would have killed that hypothesis immediately
  rather than after a system-level recommendation. Considered and rejected:
  naming Codex `browser_use` and `computer_use`, which are task tools and would
  contradict the existing `playwright-cli` rule; naming `/code-review ultra`, a
  billed, Claude-specific command that does not belong in a portable template;
  asserting an Antigravity long-run primitive that could not be verified, so
  that row of the table says to check `agy --help` instead; a general "restate
  the task before acting" rule, as ceremony on top of existing
  assumption-reporting; and making plan-mode a hard gate on broad changes, too
  blunt next to a trigger-based rule.
- **Give each `test.sh` run its own scratch directory
  (2026-09-03, Claude Opus 5).** The ask: concurrent runs of the suite produced
  spurious example-reproducibility failures that vanished on retry and pointed
  at nothing. What changed: four fixed paths (`/tmp/aigi_test.out`, `.err`,
  `/tmp/aigi_ex.out`, `/tmp/aigi_pwned`) replaced with a per-run `mktemp -d`
  directory removed by an `EXIT` trap; the code-injection canary's path is now
  written with a single-quoted `printf` format so it reaches the fixture
  unexpanded. Why this approach: the paths were shared state between runs in
  *different* checkouts, which is the realistic case here — parallel agents each
  work in their own worktree, and this was hit with another agent running the
  suite from a sibling worktree during the orchestration work. The canary needed
  the `printf` because its line sits inside a quoted heredoc: substituting the
  path any other way fires the `$(touch …)` while writing the fixture instead of
  while parsing it, silently inverting what the test proves. Verified with two
  independent checkouts running concurrently, both reporting 168 passed.
  Considered and rejected: redirecting the `render-commands` and
  `install-commands` tests away from the repo's real `commands/` port
  directories, which would also make same-checkout concurrency safe — those
  tests exist to verify the real render against the real output paths, so the
  limitation is documented instead and concurrent suites run from separate
  checkouts.
- **Unify agent teams and cross-vendor delegates into one orchestration system
  (2026-09-03, Claude Opus 5).** The ask: Joe asked for a single orchestration
  and delegation system that intelligently designates in-tool subagents,
  cross-vendor agents, or both — prompted by confirming that
  `playbooks/orchestration.md` never defined agent roles during delegation, and
  extended to cover initial product and project plans. What changed:
  `playbooks/orchestration.md` becomes the single entry point and gains "One
  system: choosing the shape" — an in-tool team is the default, escalating to
  cross-vendor on foundational framing (a first product or project plan),
  breadth (app-wide or architectural), reversibility, contested explanations, or
  refutation that has to count, with the compound shape (in-tool team produces,
  outside vendors attack a `STATE.md` summary, main thread reconciles)
  documented as the normal answer for the largest work. A second new section,
  "Roles are the interface", closes the delegation gap; a third pattern, "on a
  plan, ask for a rival — not a review", covers the planning case.
  `playbooks/agent-teams.md`'s "Which construct, and when" now defers to that
  ladder instead of presenting three rival constructs, and `template.md` gains a
  resident ladder bullet gated behind `INC_ORCHESTRATION`; examples re-rendered.
  Why this approach: the two constructs were already one idea — more lenses on a
  problem — split across two playbooks with no router between them, and roles
  were the natural shared interface. Making them one closed a real defect: the
  playbook routed purely by vendor strength, so a cross-vendor delegate was a
  generic agent and the `refuter` role went unused at exactly the point the
  "never the sole checker of its own work" rule is enforced across vendors.
  Neither CLI can select a role by name across the boundary (`codex exec` has no
  agent-selection flag; `claude --agents` defines a spawnable roster, not the
  role the `-p` turn assumes), so the role definition is passed in via
  `--append-system-prompt`. Routing on concrete triggers rather than judgment
  keeps the decision checkable, cost is named explicitly so the ladder does not
  read as permission to parallelize everything, and gating the resident bullet
  keeps cross-vendor advice off machines with no second CLI. Considered and
  rejected: putting the router in `agent-teams.md` — the shape has to be chosen
  before you know which playbook applies; leaving the two playbooks independent
  with cross-references, which is the status quo that produced the gap; making
  cross-vendor the default, which most work does not need and every rung of
  which multiplies tokens and wall time; and folding initial plans under the
  reversibility trigger, which would have routed them to refutation — the wrong
  shape for work that has no conclusion to attack yet, where independent rival
  drafts diffed against each other are what surface the implicit decisions.
- **Fix cross-CLI orchestration: the sandbox starved every delegate
  (2026-09-03, Claude Opus 5).** The ask: on a fully-installed machine, Codex
  tried to orchestrate Claude and Cursor and the delegates never responded —
  on macOS and Linux alike — and separately, only Codex ever attempted
  orchestration at all. What changed: `codex-permissions.snippet.toml` now
  ships `sandbox_workspace_write = { network_access = true }`;
  `playbooks/orchestration.md` requires a hardened delegate launch
  (`timeout … < /dev/null > "$CTX/agents/<name>.log" 2>&1`, then `wait` and
  check the exit status) and names a starved sandbox as the first thing to
  check when a wave returns nothing; `template.md`'s agent-teams section now
  states the team default as an explicit standing request rather than a
  preference; examples re-rendered. Why this approach: `sandbox_mode =
  "workspace-write"` — which this installer sets — disables network for every
  sandboxed command on every platform, and a network-starved agent CLI does
  not exit non-zero, it retries in place until something kills it (reproduced:
  `claude -p` returned nothing and ran until a 90s timeout, versus 11s with
  network). Headless `codex exec` runs at `approval=never`, so the
  per-command escalation path cannot recover it either. The installer was
  forbidding the cross-CLI delegation its own orchestration playbook mandates,
  which is why the failure survived a correct install. The inline-table TOML
  form is deliberate: a `[sandbox_workspace_write]` section would swallow any
  bare top-level key following the managed block in a user's config. The
  template change addresses a separate cause found in the same session —
  Claude Code carries a server-delivered policy (`tengu_heron_brook`, cached
  in `~/.claude.json`) not to spawn agents unless the user requested it, which
  outranks the rendered instructions and is why only Codex, which carries no
  such policy, ever tried. Considered and rejected: an OS-level fix
  (`kernel.apparmor_restrict_unprivileged_userns=0`) — this was first
  misdiagnosed as Ubuntu 24.04 blocking bubblewrap; that defect is real on the
  Linux box and does break Codex's sandbox there, but it is Linux-only and
  cannot explain the macOS failure, so it was the wrong root cause and is
  tracked separately. Also rejected: `--sandbox danger-full-access` for
  delegates, which bypasses the sandbox rather than fixing it; deleting the
  cached `tengu_heron_brook` value, which is refetched from the server (the
  file was rewritten five times in thirty-five minutes); and a
  `UserPromptSubmit` hook to restate the standing request every turn, which
  the permission classifier blocked as harness self-modification — Claude
  Code's supported `--append-system-prompt` flag reaches the same tier without
  a hook.
- **Port prompt-rigor mechanics from `intent-hq/intent`'s specialist set, and
  make the product designer a writer (2026-09-03, Claude Opus 5).** The ask:
  review Intent's built-in agent roster against ours and recommend, then apply
  what's worth taking. What changed: every role in `roles/` split into Hard
  rules and Guidance; each `Return:` line replaced by a named field list with
  mandatory `file:line` citation; read-only roles given a `Do not report` list
  and a confidence floor (inverted for the `refuter`, deliberately); a
  `reminder:` frontmatter key restated at the top and bottom of each body and
  verified by `render-roles.sh`; a role source contract asserted in `test.sh`;
  `product-designer` given `Edit`/`Write` plus the ownership rule; a new
  `harness-steward` role; a task-brief schema in `playbooks/agent-teams.md`; a
  new `Proposals, asks, and decisions` section in `template.md` behind
  `INC_PROPOSALS`. Why this approach:
  Intent's role files are better written than ours but decompose by workflow
  stage and assume their daemon's runtime, so we kept our discipline-lens axis
  and took only the mechanics that survive being portable. The reminder rides
  inside `developer_instructions` rather than a new TOML key because Codex
  documents no reminder field and an unknown key fails silently into the
  generic agent — the exact failure the role layer exists to prevent.
  `product-designer`'s `sandbox: read-only` (from #29) was wrong: four of the
  five read-only roles critique an artifact someone else authored, but a
  product designer authors one, and returning a flow as text forces the lead to
  re-type the deliverable. Considered and rejected: adopting Intent's roster
  wholesale, which loses the `refuter` — their nine specialists carry no
  adversarial lens at all — along with the four lenses their pipeline assumes
  are already answered; a spawnable `coordinator`, which is a second lead and
  only works by spawning agents, breaking one-level-deep delegation, so its
  spec schema went into the playbook instead; a spawnable `chief-of-staff`,
  whose value is output-shape rules that belong in `template.md` plus a
  tooling-subject agent that became `harness-steward`; their grep-the-codebase
  design-system discovery, which reopens the settled decision that `DESIGN.md`
  is the articulation point, so the `ui-designer` now hard-rules against
  inferring a system when one is declared; and their harness-versioning
  machinery, overkill for a file installer — the golden-test half is what we
  took. A `security-reviewer` adapted from their `vulnerability-scanner`
  remains open.
- **Make Codex approval notifications actionable
  (2026-08-25, Codex + Claude Opus 5).** The ask: suppress Warp notifications
  for permission requests that Codex automatically approves, without disabling
  `warp@codex-warp` or hiding genuine approval waits. What changed:
  `install-settings.sh` now preserves Warp's completion notifier, disables only
  its premature pre-routing `PermissionRequest` handler, and seeds native,
  unfocused-only `approval-requested` notifications. The installer resolves the
  handler from Codex's active Warp marketplace manifest, preserves explicit
  settings and sibling hook state, fails closed when discovery or native
  approval coverage is ambiguous, and marks owned keys for precise uninstall;
  tests and documentation cover the behavior. Why this approach: Warp's hook
  fires before approval routing, while the native event is the appropriate
  surface for approvals that actually reach the user; keeping Warp's `Stop`
  hook also avoids losing completion alerts. Considered and rejected: disabling
  Warp entirely; enabling native `agent-turn-complete`, which would duplicate
  Warp's completion toast; hard-coding hook indices or trust hashes; resolving
  from stale versioned caches; patching Warp's installed files; and static TOML
  insertion, which risks duplicate tables and overwriting user configuration.
- **Gitignored-only changes no longer earn a Change Log entry
  (2026-08-18, Claude Opus 5).** The ask: Joe wanted the instruction set to
  stop proposing changelog entries for work that only touched gitignored
  files, since those are local, temporary artifacts. What changed: one bullet
  in `template.md`'s `changelog` section scoping the log to tracked files, and
  telling the agent to log only the tracked part of a mixed change; the
  committed examples re-rendered. Why this approach: the rule is a scoping
  clause on an existing gate, so it belongs as a bullet inside the section it
  qualifies rather than a new section — and putting it in `template.md` means
  every render (global, project, examples) inherits it. Considered and
  rejected: teaching `hooks/quality-nudge.sh` to skip ignored files —
  unnecessary, it already counts via `git diff HEAD` plus `ls-files --others
  --exclude-standard`, so ignored paths never reach the thresholds; and
  wording it as "untracked files" — too broad, a new tracked-to-be file is
  real work that should be logged.
- **Closing the browser is now a resident rule, not playbook trivia
  (2026-08-17, Claude Opus 5).** The ask: on Joe's Mac, `playwright-cli` left
  a headless instance running that made Chrome unusable — a session found
  alive after three days. Mechanism (from that machine's diagnosis):
  `playwright-cli` drives the real `Google Chrome.app` binary, whose headless
  instance registers with LaunchServices under `bundleID="com.google.Chrome"`;
  macOS permits one instance per bundle ID, so clicking Chrome in the Dock
  *activates* the headless process instead of launching a browser, and
  `--no-startup-window` means no window ever appears. Chrome looks broken
  until it is force-quit. What changed: a full section in
  `playbooks/web-preview.md` (macOS + Linux diagnosis, "not a profile lock",
  "`list` is not proof", "`kill-all` leaves browsers behind", the `$TMPDIR`
  sweep, and `close-all` — which is in `--help` but was missing from the
  original notes); a resident one-liner in `template.md`; and a closing step
  in `/verify`, the heaviest browser driver we ship. Why this approach: the
  playbook is loaded on demand, so a rule that only lived there would be read
  *after* the browser was already open — but the failure damages the user's
  own machine and outlives the session, so the "always close" half has to be
  resident while the diagnostic detail stays on demand. Considered and
  rejected: (a) playbook-only, for the reason above; (b) a hook or wrapper
  that reaps sessions automatically — the leak is cross-tool (any CLI can
  drive `playwright-cli`) and a reaper cannot tell a live session's browser
  from an abandoned one, which is exactly the mistake made while
  investigating this: five `@playwright/mcp` processes on the Linux box were
  first read as orphans and were in fact MCP servers of still-running Claude
  sessions. Only the stale `$TMPDIR` dirs were genuinely leaked. Note: the
  "`playwright-cli list` reports `(no browsers)` while sessions are alive"
  claim rests on the macOS diagnosis; the attempt to corroborate it on Linux
  was that same false positive.
- **/ship never pushes the default branch directly (2026-08-13, Claude).** The
  ask: Joe asked whether `/ship` / `$ship` always create a PR/MR before
  merging — merges already did (the only merge path is `gh pr merge` /
  `glab mr merge` behind a confirmation gate), but shipping *from* the default
  branch committed and pushed straight to it with no PR, conflicting with the
  no-default-branch-edits rule (#22). What changed: the default-branch check
  moved ahead of commit/push as a new step 3 — work found on the default is
  moved to an `ai/<slug>` feature branch (uncommitted changes and any unpushed
  local commits ride along; local default reset to `origin/<default>`), so
  every ship lands as a PR/MR; stale `/ship` rows in the commands README and
  GUIDE (which still claimed auto-merge) refreshed. Why this approach:
  branching before the commit exists means the default branch never even
  receives the commit locally, and the rest of the flow needs no changes.
  Considered and rejected: refusing to ship from the default and telling the
  user to branch manually — safe but leaves mechanical work the command can do
  itself, against the repo's bias-to-action stance.
- **Remove the unintentionally committed Gemini command ports
  (2026-08-13, Claude).** The ask: a PR merge surfaced commit `64c083d`,
  which had landed 8 hand-authored `commands/gemini/*.toml` ports directly on
  `main` — no PR, no changelog entry; Joe confirmed it was unintentional.
  What changed: `commands/gemini/` deleted and gitignored alongside the other
  per-tool port dirs. Why this approach: Gemini is retired (Antigravity
  replaced it) and `render-commands.sh` has no gemini support, so the files
  were dead weight nothing generates or consumes; the gitignore guard makes
  the mistake unrepeatable rather than just reverted. Considered and
  rejected: keeping the ports and adding gemini support to
  `render-commands.sh` — it would revive a retired integration the installer
  deliberately no longer targets.
- **Changelog entries now require a date + authoring-model stamp
  (2026-08-12, Claude).** The ask: Joe asked whether the changelog
  instructions require timestamping entries — they didn't, even though every
  entry in this repo's own CHANGELOG.md already carries a
  `(2026-08-01, Claude)` style stamp by convention. What changed: a new
  bullet in the template's `changelog` section requiring the stamp and
  resolving the date against the user's timezone; examples re-rendered. Why
  this approach: codifying the emergent convention in the one section that
  defines entry format keeps it portable — a fresh session on any machine now
  produces dated, attributed entries without having seen this repo's log.
  Considered and rejected: leaving it as convention-by-example — only works
  in repos whose changelog already models the format.
- **Add a no-editing-on-the-default-branch rule to both autonomy variants
  (2026-08-01, Claude).** The ask: Joe noticed the globals only encourage
  worktrees in the multi-agent context ("Parallel AI models on one repo"), so
  solo sessions could legitimately edit `main` directly. What changed: a new
  bullet in both `autonomy-aggressive` and `autonomy-balanced` — "Never edit on
  the default branch. Create a feature branch (or a worktree) before changing
  files — even when working solo" — with examples re-rendered. Why this
  approach: placing it inside both variants keeps each variant self-contained
  and guarantees the rule renders under any configuration. Considered and
  rejected: adding it only to the `parallel-worktrees` section — it wouldn't
  cover solo work and disappears entirely when that section is toggled off.
- **`/verify` checks token and component usage against the design system
  `DESIGN.md` articulates (2026-07-31, Claude).** The ask: Joe wanted `/verify`
  to go beyond `DESIGN.json`/Figma — verify token structure pulled from an
  imported design system, and check that touched UI adheres to the project's
  component library (imported or built locally). What changed: the Design &
  accessibility dimension now reads `DESIGN.md` as the articulation of the
  system and verifies **Token usage** and **Component usage** as named
  sub-checks (hand-rolled duplicates of provided components are drift, same as
  off-scale values); a **Missing articulation** sub-check prompts the user when
  `DESIGN.md` is absent or silent on tokens/components, offering to draft the
  section from the code; the template's "Build to the system" bullet states the
  matching build-time contract; GUIDE lens ④ and the commands README refreshed;
  ports and examples re-rendered. Why this approach: one declaration point
  keeps the check deterministic and portable — the command grades against what
  the project says its system is, not what a heuristic guesses, and a missing
  declaration becomes a visible gap instead of a silent skip. Considered and
  rejected: auto-detecting design systems via config probes and `package.json`
  greps (first draft) — Joe rejected it; detection logic doesn't belong in the
  command when `DESIGN.md` should articulate the system.
- **Scale artifact verification to the artifact — no Playwright/axe on simple
  read-only artifacts (2026-07-28, Claude).** The ask: Joe reported agents were
  over-verifying simple internal HTML reports and comparisons with full
  Playwright/axe runs, and brought suggested carve-out wording from another
  agent. What changed: a new bullet in the template's Output artifacts section
  ("Scale verification to the artifact" — lightweight structural checks for
  read-only artifacts; full browser verification only on request, real
  interaction complexity, or product UI changes) plus a matching **Scope** note
  in `playbooks/web-preview.md`, since that playbook is what agents read right
  before driving a browser and previously implied Playwright for all "UI work".
  Examples re-rendered to match. Why this approach: the blanket
  "playwright-cli, never curl-only" rule had no lower bound; a carve-out at the
  point of the rule (and in the playbook) fixes the over-checking without
  weakening verification for real product UI. Considered and rejected: the
  suggesting agent's verbatim wording — restyled to the template's bold-lead
  bullet convention, same meaning.

### Fixed
- **SessionEnd hooks no longer lose a 1.5-second shutdown race
  (2026-08-17, Claude Opus 5).** The ask: Joe hit a recurring machine error,
  `SessionEnd hook [env HOOK_PLATFORM=claude ".../scorecard-enqueue.sh"]
  failed: Hook cancelled`. Root cause, read out of the Claude Code 2.1.234
  binary rather than inferred: shutdown aborts the whole SessionEnd batch on
  `AbortSignal.timeout(max(1500ms, min(largest declared SessionEnd hook
  timeout, 60s)))`, and an `ABORT_ERR` surfaces as "Hook cancelled". The
  Claude block in `install-hooks.sh` was the only one declaring no `timeout`
  (Codex/Cursor already used 30), so both SessionEnd hooks — seven `jq`
  spawns plus a ~60ms shell-snapshot source each — had to finish inside 1.5s
  of a shutdown already awaiting other teardown, on a 2-core box running
  several AI CLIs. Intermittent by construction. What changed: `timeout: 10`
  on both SessionEnd hooks (widening the batch window to 10s), plus two
  robustness fixes in `scorecard-enqueue.sh` — the materiality scan now reads
  only the audit log's last 8MB (`AI_SCORECARD_SCAN_BYTES`, 0 = full file),
  and the pending marker lands via an atomic rename. A regression test asserts
  every Claude SessionEnd hook declares a timeout. Why this approach: the hook
  was never slow — it measured ~0.1s before and after, so optimizing it would
  have narrowed the race without closing it; only the declared timeout changes
  the deadline itself. The scan bound matters independently: the log was
  already 39MB and grows without limit, so a full-file grep inside a shutdown
  deadline degrades every month (verified the bounded scan returns an
  identical count, 75 = 75, on the real log). The atomic write closes the
  failure the abort could still cause — a truncated marker that every later
  SessionStart would fail to parse. Considered and rejected: (a) moving the
  materiality gate to the SessionStart survey hook so the shutdown path does
  no work at all — architecturally cleaner, but it changes two hooks and the
  marker schema for a window that is now 10s; (b) collapsing three `jq` parses
  into one line-oriented read — actually written, then reverted, because it
  desyncs if `cwd` contains a newline and the saved spawns were unmeasurable.
- **Cursor permission merge and the macOS scorecard loop
  (2026-08-13, Claude Opus 5).** The ask: Joe asked to install the latest
  instructions on this machine; `./install.sh --yes` failed the Cursor settings
  step, and the test suite showed 5 pre-existing failures. What changed:
  (a) `merge_perms_json`'s retired-rules default `"${4:-{\}}"` kept the
  backslash literally, so `jq --argjson gone` rejected `{\}` as invalid JSON —
  every Cursor install had silently skipped its deny layer since the
  retired-rules parameter was added, while Claude passed `$4` explicitly and
  never hit it; the default now sits on its own line. (b) `scorecard.sh` and
  `memory-os.sh` called `flock` unguarded, which stock macOS lacks —
  `scorecard.sh record` died at exit 127, so no rating was stored and no lesson
  reached the memoryOS, making the advertised session-scorecard feedback loop a
  no-op on every Mac. Both now use the `command -v flock` guard `log-tool.sh`
  already carried. Why this approach: `log-tool.sh` had solved the flock
  portability problem in-repo already, so mirroring its idiom keeps one pattern
  instead of two; the shell-default fix is the minimal change that keeps the
  same call signature. Considered and rejected: requiring `flock` via
  `brew install util-linux` — pushes a dependency onto every macOS user for
  best-effort append locking the log layer already treats as optional; and
  quoting the default as `'{}'` inline, which reads as working but repeats the
  same brace-escaping trap the next editor would hit.
- **Finish the permission-rule cleanup: drop the redundant `./` read rules and
  prune retired rules from existing installs (2026-07-28, Claude).** The ask:
  Joe reported his global Claude settings had needed hand-fixing, with a defect
  report naming two installer bugs. Issue 1 (dead `Write(...)` rules causing
  startup warnings) was already fixed — see the earlier "Remove redundant
  `Write(...)` deny rules" entry below. Issue 2 was not:
  `settings-permissions.snippet.json` emitted both `Read(./.env)` and
  `Read(**/.env)` (same for `.env.*`), where the docs confirm bare filenames
  follow gitignore semantics and match at any depth — `Read(.env)` and
  `Read(**/.env)` are equivalent — so the `./` form is fully subsumed. Removed
  both, and rewrote the snippet's `_comment` into an explicit generation rule:
  only `Read`/`Edit` are matched for files, `Edit(...)` covers Edit + Write +
  NotebookEdit (so never emit `Write(...)`/`NotebookEdit(...)`/`Glob(...)`),
  one rule per pattern, and the cwd-relative anchoring is *intended* for a
  user-level file — a `//**/` prefix would extend the block to the whole
  filesystem.

  Why this approach: the deeper problem was that dropping a rule from a snippet
  doesn't clean existing installs. `uninstall.sh` subtracts exactly what the
  snippet holds *today*, so a retired rule orphans in `~/.claude/settings.json`
  forever — which is precisely why the earlier `Write(...)` fix had to be
  hand-applied to the live file. Added `CLAUDE_RETIRED_PERMS` to
  `install-settings.sh` (the 15 dead `Write(...)` rules plus the 2 `./` dupes),
  subtracted before the union so a re-run heals an old install, mirroring
  `remove_commands_dir`'s retired-command-names pattern. Three regression tests
  pin all of it: no `Write`/`NotebookEdit`/`Glob` rules in the snippet, no
  `./` + `**/` pairs, and retired rules actually pruned from a pre-existing
  file. Deny rules 17 → 15, functional coverage unchanged; verified with a
  clean `claude --debug -p` run (zero warnings) and 144/144 tests.

  Considered and rejected: removing the rules from the snippet only (leaves
  every existing install carrying the orphans, repeating the manual-fix cycle
  that prompted this report); converting the `Write(...)` rules to `Edit(...)`
  rather than deleting them (the `Edit(...)` twins already exist — conversion
  would just recreate duplicates); rewriting the relative patterns to `//**/`
  (over-broadens a user-level rule from "the current project" to every
  directory on the machine — explicitly called out as a non-fix); dropping the
  `Edit(.env)` rules as redundant with the `Read` deny (true on v2.1.208+, but
  keeping them is harmless, clearer about intent, and works on older
  versions); applying the same dedup to
  `settings-permissions.cursor.snippet.json` (a different engine whose matcher
  the Claude Code docs don't govern, and whose `Write(...)` rules have no
  `Edit(...)` counterparts — converting blind would risk dropping real
  protection; left for a separate pass against Cursor's own docs).

### Added
- **Encourage long autonomy: /loop and /goal as first-class primitives
  (2026-07-25, Claude).** Added a `long-autonomy` template section (rendered
  only under the aggressive posture) that teaches every tool its own long-run
  primitive — `/loop` in Claude Code and Cursor's `agent`, `/goal <objective>`
  in Codex — behind four rules: offer *or start* the loop when work outlives
  the turn, write a testable done-condition first, confirmation gates apply
  unchanged inside every iteration, and leave a file trail (WIP commits,
  `STATE.md`) so a fresh session can resume. `customize.sh --global` now seeds
  `~/.claude/loop.md` (bare `/loop`'s default maintenance prompt: continue
  unfinished work → tend the PR → converge `ai/*` worktrees → otherwise report
  "nothing to do"; seed-only, never overwritten), and a new `autonomy-reminder`
  SessionStart hook (Claude + Cursor) injects a one-paragraph advisory that
  `/loop` exists — wired only when the new `customize.sh --autonomy` query
  resolves to aggressive, and pruned on re-install if the posture flips to
  balanced.

  Original ask: plan how this harness can encourage longer autonomy — sessions
  ended with "next steps" lists instead of staying alive on ongoing work; use
  `/loop` for claude and agent, `/goal` for codex.

  Why this approach: prose in the one rendered `~/AGENTS.md` reaches all four
  tools at once; gating on the existing aggressive/balanced posture reuses a
  toggle that already means "keep going without me" instead of adding a new
  interview question; and the hook mirrors `load-memory`'s advisory contract —
  it reminds, never auto-starts anything, so the established "hooks never
  auto-continue" stance holds.

  Rejected: a Stop-hook "keep going" nudge (would invert the anti-auto-continue
  contract `quality-nudge` deliberately enforces); writing `[features]
  goals = true` into `~/.codex/config.toml` (duplicate-table risk could corrupt
  a user config, and goals is default-on since codex 0.133 — the prose instead
  suggests `codex features enable goals` when `/goal` is missing); shipping an
  external while-loop wrapper for Cursor (its `/loop` is treated as native per
  Joe, though current Cursor docs don't list it — revisit if a session reports
  it unknown).

- **Local models as first-class delegates (2026-07-24, Claude).** Added a
  machine-local registry (`~/.ai/local-models`, written by
  `customize.sh --global`: probes a running Ollama at `:11434` and the
  llama.cpp/MLX default `:8080`, plus hand-registered `LOCAL_MODELS` lines in
  `my-context.env` for custom ports and remote tailnet boxes) and an `lm` shim
  (installed to `~/.local/bin`; `-p` one-shot completion, `list` health,
  `bench` measured tok/s) so any machine serving local models — Ollama,
  llama.cpp, MLX, or a remote box — gets them wired into cross-tool
  delegation, the `/improve` and `/verify` review lenses, and routing
  (`/update-model-routing` now scores registered models into a machine-local
  `~/.ai/model-routing.local.md`). Registry entries carry a `strong`/`light`
  capability tier (derived from parameter count) that gates what work they
  receive; machines without local models get no registry file and every
  related instruction no-ops — nothing is ever installed or started to create
  one.

  Original ask: make the orchestration instructions and skills in this
  installer work with local models however they're installed per machine —
  explicitly **not** a setup of any one box.

  Why this approach: all three runtimes expose the same OpenAI-compatible
  HTTP API, so the harness integrates one contract (registry + shim) rather
  than three runtimes; install method stops mattering because everything
  resolves to a URL in the registry. Machine-specific truths (tiers, measured
  tok/s, benchmark scores for whatever happens to be pulled) live in
  machine-local files, keeping the committed template and routing table
  portable.

  Rejected: per-runtime integration (3× the surface, breaks on install-method
  variance); putting local models directly in the `~/.ai/clis` roster as bare
  entries (different invocation and failure contract would pollute the
  pure-names roster — instead `lm` joins the roster as one delegate);
  scoring local models in the committed `MODEL-ROUTING.md` (machine-specific
  results don't belong in a shared file — it gets only a generic pointer
  note).

### Changed
- **Slim the resident instructions ~31% by extracting workflow mechanics into
  on-demand playbooks (2026-07-26, Claude).** New `playbooks/` directory —
  `orchestration.md` (full cross-tool delegation contract), `quality-workflows.md`
  (`/improve` panel + background-snapshot mechanics, `/verify --bg`, the advisory
  skip marker), `web-preview.md` (`playwright-cli` flows, the Vite/Astro
  unknown-Host 403) — mirrored to `~/.ai/<name>.md` by `customize.sh --global`
  (same cmp-guarded pattern as `MODEL-ROUTING.md`; removed, not left stale,
  when a playbook's section is toggled off). The template's orchestration,
  verify/improve, and artifacts sections now keep only always-relevant policy —
  confirmation gates, the sole-checker rule, the "you *are* the delegate"
  trigger, never-bypass-flags — plus a read-this-first pointer at the playbook.
  Rendered `~/AGENTS.md` drops from 144 lines / ~3,100 words to 127 / ~2,100.

  Original ask: Joe asked whether the 144-line render was too long, given the
  "cut your CLAUDE.md by 80%" discourse.

  Why this approach: the real cost of a long instruction file is attention
  dilution, not tokens — and the fat was mid-task mechanics resident on every
  turn. Moving mechanics behind pointers keeps every gate always-loaded while
  detail loads only when actually delegating, reviewing, or serving.

  Rejected: chasing an 80% cut (this file is behavioral policy, not `/init`
  bloat — compressing that far would delete gates); relying on the
  improve/verify skills alone to carry the mechanics (other tools read the
  rendered instructions without those skills installed, so the playbooks keep
  the contract tool-agnostic).

- **Verify-pass hardening of the async quality contracts (2026-07-26,
  Claude).** A cross-vendor `/verify` of the async-quality-passes commit
  (Antigravity D, Cursor C, own grade B−) confirmed three contract holes,
  fixed here: `/verify --bg` claimed to grade a pinned snapshot but ran
  whatever tree it was in — it now materializes the SHA in a disposable
  worktree (`git worktree add --detach`, untracked copies re-applied, removed
  after grading) and branches explicitly on the `--bg` flag; the deferred gate
  was honor-system — a durable `PENDING.md` marker (goal, SNAP,
  done-condition) now survives session death and `/ship` checks it (new step
  0); and the `/improve` snapshot recipe mis-landed `diff.patch` in the repo
  CWD, ignored untracked-only WIP (where `$SNAP` falls back to a HEAD that
  never contained the change), and never named an authoritative artifact —
  all specified now, with the frozen evidence declared to win over both
  `$SNAP` and the live tree. `commands/README.md` descriptions refreshed;
  template/GUIDE aligned to the same contract.

  Refuted and not acted on: delegate claims that the diff "missed the
  generated ports" (they are gitignored renders by design, regenerated on
  every install) and that verify prose inside `SECTION:improve` breaks
  parsing (the section's established "When to verify & improve" shape,
  covered by the section-wiring test). Codex could not grade — usage quota
  exhausted until 2026-08-11 — so the second opinion ran on two vendors.

  Rejected: enforcing the open gate via a hook (prose + the `/ship` step-0
  check keeps enforcement in the same layer as the rest of the contract).

- **`/improve` backgrounds by default; `/verify` gains `--bg`
  (2026-07-26, Claude).** `/improve` now runs its review panel as one
  background task pinned to a snapshot taken at invocation (`git stash
  create`, else `HEAD`, plus the frozen `diff.patch` and untracked copies in
  the context dir), returning control immediately and landing findings as a
  completion notification plus a durable
  `~/.ai-context/<repo>-improve/findings.md` stamped with the snapshot SHA —
  with staleness flags for files that changed since. Explicit-only invocation
  is unchanged (backgrounding changes *how it runs*, never *when it may
  start*), and hosts without background tasks (the Codex port) degrade to
  inline. `/verify` is now explicitly **synchronous by default** — it's a
  handoff gate, and a gate that hasn't finished can't gate — with a new
  `--bg` deferred mode: snapshot-pinned the same way, tied to an explicit
  done-condition ("done when this verify reports its grade") that handoff
  waits on, and forbidden from colliding with the live dev server. Template
  `improve` section, `docs/GUIDE.md`, the codex/cursor ports, and the
  `aggressive-tailscale` example render updated to match.

  Original ask: Joe asked whether hook-style background correction could run
  without blocking work linearly; discussion converged on making the quality
  passes themselves async where that's sound.

  Why this approach: the two commands differ in kind — `/improve` is advisory
  and read-only, so blocking the session is pure cost, while `/verify`'s
  whole value is blocking "done." Snapshot pinning solves the moving-target
  problem (findings' `file:line` referencing code that no longer exists once
  the main thread keeps editing); durable findings files survive the session
  ending before the notification is read.

  Rejected: backgrounding both symmetrically (an async verify is a report you
  might ignore — it either breaks the gate or saves nothing); fire-and-forget
  `--bg` for verify (deferred-with-done-condition keeps the handoff honest);
  hook-triggered auto-runs of either pass (would violate the explicit-only
  rule the `quality-nudge` contract enforces).

- **Model routing refresh — hard coding & long-context now split at the top
  (2026-07-24, Claude).** Re-researched all 7 categories against current
  public benchmarks. Two real changes, driven by GPT-5.6 Sol's independent
  Terminal-Bench 2.1 and MRCR v2 entries landing since the 2026-07-21 seed:
  **Hard coding & refactoring** moves from clean claude-then-codex to a
  genuine **#1 tie** — tbench.ai's native-harness board still favors Claude
  Fable 5 (83.8%), but vals.ai's neutral-harness board now has GPT-5.6 Sol
  ahead (85.77%), and the two disagree. **Long-context analysis** softens
  similarly — Sol's new MRCR score is a near-tie with Claude Opus 4.6 at true
  1M-token depth, though Claude still leads at shallower depths. The other
  five categories (code review, deep research, planning, UI/frontend, cheap
  fan-out) were re-verified and are unchanged, with minor citation refreshes
  (e.g. a new Martian Code Review Bench noted as ranking products, not
  vendors, so it doesn't resolve that category's tie). Also trimmed the file
  from 101 to 90 lines to honor its own stated "~90 lines" budget, a gap an
  earlier review had flagged. Mirrored to `~/.ai/model-routing.md`.

  Why this approach: research was fanned out to 7 parallel subagents (one per
  category) per the command's own instructions, each independently
  re-verifying primary sources rather than trusting the prior seed — this
  caught both real changes and confirmed the other five hadn't silently
  drifted. Rejected: nothing — this is the routine refresh workflow the
  command exists for.

### Added
- **Session scorecard survey + memoryOS registry (2026-07-24, Claude).** A
  human-feedback loop that evaluates each session and feeds lessons into the
  next one: `hooks/scorecard-enqueue.sh` (SessionEnd, Claude) queues a pending
  marker for non-trivial sessions (≥`AI_SCORECARD_MIN_EVENTS`=20 audit
  records, never `resume` ends, never already-rated sessions);
  `hooks/scorecard-survey.sh` (SessionStart, Claude + Cursor) offers a
  3-question survey — rate the last session 1–5, why, what to do differently;
  `hooks/scorecard.sh` (agent-run CLI, not event-wired) records answers to
  `<log-dir>/scorecards/scorecards.jsonl` (`stats`/`pending`/`dismiss`) and
  appends the lesson to the machine's memoryOS; `load-memory.sh` now injects
  the most recent lessons (`AI_LESSONS_INJECT`=8) at every SessionStart —
  that injection is what closes the loop. Where lessons land is a new
  machine-wide registry, `~/.ai/memory-os`, written by `setup-memory-os.sh`
  (new `install.sh` layer): detects Hermes (`~/.hermes/memories/LESSONS.md`),
  supports markdown/Obsidian dirs and a Notion local-mirror mode, falls back
  to `~/.ai-memory/`. Suite 106 → 114; docs rows in hooks/README, GUIDE §3,
  README bullet.

  The ask: Joe wanted a component that scorecards each AI agent session and
  feeds results back into memoryOS to improve the next session — with an
  easy-to-dismiss survey and no ask more than 2 hours after the session ends.
  Why this approach: SessionEnd hooks cannot prompt (the platform ignores
  their output and the session is over), so the ask is deferred to the next
  SessionStart in the same cwd — which after `/clear` appears immediately, so
  it *feels* end-of-session; the user is the evaluator, making the signal
  direct and the cost zero (no LLM calls, no cron, no background jobs).
  Dismissal is deliberately frictionless: one word (or just starting real
  work) dismisses, markers self-expire after `AI_SCORECARD_TTL`=7200s, an
  ignored survey stops after `AI_SCORECARD_MAX_OFFERS`=2, and
  `AI_SCORECARD=0` kills the loop. Lessons go to a project-owned `LESSONS.md`
  inside the chosen store — never appended into a store's own curated files
  (e.g. Hermes `memories/MEMORY.md`) — to respect one-writer-per-file and
  Hermes' lock conventions. Rejected: the first design's cross-vendor
  headless LLM graders with a rubric plus a daily cron sweep and a
  `/scorecard` command (Joe cut it: costly, and a basic human rating with
  "why" questions is more informative for training); surveying via a
  terminal prompt at SessionEnd (unsupported — would fight the TUI for the
  tty); writing lessons straight into Hermes `MEMORY.md` (clutters a curated
  personal-facts store and races its writer).
- **Gemini CLI support removed entirely (2026-07-24, Claude).** No more
  opt-in: `WIRE_GEMINI` is gone, and `gemini` is no longer accepted by any
  install script (`install.sh`/`install-commands.sh`/`install-hooks.sh`/
  `install-settings.sh` now error on it as an unknown target).
  `render-commands.sh` no longer generates a gemini command port;
  `policies/gemini-guardrails.toml` is deleted. `uninstall.sh gemini` is kept
  as a **legacy-cleanup-only** target — since the generated port it used to
  diff against no longer exists, it now identifies our own artifacts by their
  GENERATED marker instead, so machines with a pre-retirement install still
  have a clean removal path. Scrubbed gemini mentions from README/GUIDE/
  hooks-README/commands-README/command templates/examples/hook-script
  comments; corrected two stale doc claims found in the process (Antigravity
  described as opt-in when it's the default; Cursor described as lacking
  skill support). test.sh: removed ~15 gemini-specific assertions, added one
  covering the legacy-cleanup path. Suite 108 → 106.

  The ask: Joe asked to remove Gemini completely now that Antigravity has
  replaced it, rather than continue carrying it as an opt-in escape hatch.
  Why this approach: a legacy-cleanup-only uninstall target costs nothing to
  keep and prevents stranding any pre-existing install with no
  repo-provided removal path — that's teardown tooling, not gemini
  "support." Rejected: keeping `WIRE_GEMINI` as a permanent opt-in (exactly
  the interim state the prior entry set up, which Joe is now closing out);
  dropping the uninstall cleanup path too (would leave earlier installs with
  orphaned artifacts and no fix). Supersedes the 2026-07-23 "Gemini fully
  retired from the global render and delegate roster" entry (removes the
  `WIRE_GEMINI=y` escape hatch it introduced) and completes the retirement
  started in the 2026-07-22 "Default install targets: Antigravity replaces
  the legacy Gemini CLI" entry (gemini is no longer an installable target at
  all, only a legacy-cleanup one).

### Fixed
- **Remove redundant `Write(...)` deny rules from the Claude permissions
  snippet.** `settings-permissions.snippet.json` listed both an `Edit(...)`
  and a `Write(...)` deny rule for every protected path (`.env`, `build/`,
  `dist/`, `.next/`, `out/`, `coverage/`, `node_modules/`, `.git/`) — 9
  duplicate pairs. The original ask: Joe reported "a lot of errors when
  claude loads." Root cause: Claude Code's permission engine only matches
  file writes against `Edit(path)` rules (they cover Write/Edit/MultiEdit/
  NotebookEdit collectively) and doesn't recognize `Write(...)` as its own
  matchable rule type, so each redundant rule printed a "not matched by file
  permission checks" warning on every startup — installed via
  `install-settings.sh`, which unions this snippet into
  `~/.claude/settings.json`. Removed the 9 `Write(...)` lines, keeping only
  `Edit(...)`; verified with a clean `claude --debug -p` run (zero warnings)
  after applying the same fix to the live `~/.claude/settings.json`. Why this
  approach: delete the dead rules rather than suppress the warning, since the
  `Edit(...)` rules already fully cover the intended protection — no
  functional loss. Considered and rejected: none — this was a
  straightforward dead-code removal once the warning pointed at the exact
  redundant lines. The separate Cursor snippet
  (`settings-permissions.cursor.snippet.json`) only ever used `Write(...)`
  rules with no `Edit(...)` counterpart, so it isn't affected and was left
  alone.

### Added
- **Benchmark-informed model routing + the `~/.ai/` governance layer
  (2026-07-21, Claude).** New `MODEL-ROUTING.md` — an advisory, per-task-type
  ranking of the installed AI CLIs (7 categories, every claim cited with
  source + retrieval date), seeded from live benchmark research and mirrored
  to `~/.ai/model-routing.md` at install. Two new orchestration bullets tell
  agents to consult it (reference, not law) and to flag staleness past ~2
  months. New `/update-model-routing` command re-researches and rewrites it
  behind a show-the-diff approval gate. The machine-level layout also
  changed: `~/.ai/` is now the governance/contract layer — the CLI roster
  moved from `~/.ai-logs/ai-clis` to `~/.ai/clis` (installer removes the
  legacy file; old renders fall back to `command -v`) — while logs and hook
  state stay in `~/.ai-logs/`. The ask: orchestration should reference the
  latest public tests on which models perform best at which tasks, as
  governance for model-per-task delegation. Why this approach: on-demand
  refresh command (fits the repo's manual-update ethos; no cron infra),
  repo-committed table + machine-local mirror (volatile data stays out of
  the rendered instructions; updates don't force a re-render), advisory-only
  strictness (Joe's call — availability, cost, and observed results outrank
  benchmarks). The `~/.ai/` split was Joe's architecture call mid-review:
  `~/.ai-logs` had drifted into a grab-bag, and contract data agents are
  instructed to read shouldn't live under a "logs" name. Rejected: scheduled
  auto-refresh (new infrastructure, weaker human oversight), live benchmark
  lookup at delegation time (slow, token-heavy, non-deterministic), baking
  the table into `template.md` (bloats every session and couples benchmark
  churn to re-renders), keeping everything in `~/.ai-logs/` (the misnaming
  this change exists to fix). Supersedes the roster-location decision in the
  2026-07-20 cross-tool orchestration entry. Examples and GUIDE regenerated;
  suite 107 green.
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
- **Gemini fully retired from the global render and delegate roster
  (2026-07-23, Claude).** `customize.sh --global` no longer wires the
  `~/.gemini/GEMINI.md` pointer and no longer includes `gemini` in the
  `~/.ai/clis` roster probe; both return with `WIRE_GEMINI=y`. On this
  machine the installed gemini layers (commands, hooks, guardrails,
  pointer) were stripped via `uninstall.sh gemini`. The ask: follow-through
  on the 2026-07-22 default-target swap — Joe confirmed Antigravity has
  replaced the Gemini CLI, so its layers and roster entry should go, not
  just the install default. Why this approach: an env toggle keeps the
  template usable on machines still running the legacy CLI while making
  retirement the default; the roster probe and pointer share one switch so
  "legacy gemini support" is a single knob. Rejected: deleting gemini
  support outright (breaks template users on the old CLI) and
  auto-detecting the binary (it's still installed here, so detection can't
  express "installed but retired"). Extends the 2026-07-22 entry. Suite
  107 → 108.
- **Default install targets: Antigravity replaces the legacy Gemini CLI
  (2026-07-22, Claude).** `install.sh`, `install-commands.sh`,
  `install-hooks.sh`, `install-settings.sh`, and `uninstall.sh` now default
  to `claude codex cursor antigravity`; gemini remains a supported target
  you must name explicitly. Tests that relied on the old default now
  exercise the gemini port explicitly. The ask: Joe corrected a default
  install that wired layers for gemini — "it's not gemini anymore, it's
  agy." Why this approach: the scripts already supported `antigravity` as a
  named target, so swapping the default changes only the no-args path while
  leaving every layer's behavior intact. Rejected: auto-detecting installed
  binaries (both `gemini` and `agy` exist on this box, so detection would
  still include the retired tool) and removing gemini support entirely
  (kept as explicit opt-in for machines still on the legacy CLI).
  Supersedes the implicit gemini-by-default target set carried since the
  original installer. Suite 107 green.
- **Changelog entries now record decision history, not just diffs
  (2026-07-21, Claude).** Joe asked that the changelog nudge and writer
  capture the original decision and its rationale so the log explains how
  the project evolved. The `changelog` template section now requires each
  entry to record what changed, the original ask, why this approach, and
  rejected alternatives — and supersessions must name the decision they
  replace; the `quality-nudge` advisory echoes the same expectation. Chose
  to encode this in the existing section + advisory sentence rather than a
  new hook or entry template file, keeping the one-advisory-per-diff design
  intact. Also fixed CHANGELOG.md's stale `changelog-nudge` reference
  (retired hook; it's `quality-nudge` now). Examples, root renders, and
  `~/AGENTS.md` re-rendered; suite green.
- **`/ship` no longer auto-merges (2026-07-20, Claude).** The feature-branch
  path went straight from `gh pr create` to `gh pr merge --squash` in one
  shot. It now opens the PR/MR, hands over the URL, and stops to ask before
  merging — an explicit confirmation gate (invoking `/ship` is not merge
  approval). Ports re-rendered and reinstalled for all four tools.
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
