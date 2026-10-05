# Plan — put `/sync` on a token diet by extracting a script

**Status: STOPPED at step 0.5 (2026-10-05).** The usage gate failed: one
`/sync` invocation in 268 logged Claude sessions (2026-06-14 → 2026-10-05), and
zero typed in the 73 retained transcripts. The cross-vendor refuter (agy,
inline tier) returned SMALL FIX, putting the ~6.5k tokens of overhead over 16
weeks against an estimated 250k–500k tokens to build. The small fix shipped
instead: description 32 → 16 words, `git worktree list` injection dropped. The
full record is in §8. Revisit only if `/sync` usage rises once #55 is
installed. Everything below is kept as the record of the plan.

Written 2026-10-02 by Claude (Opus 5), after PR #55.
Revised 2026-10-03 by Claude (Opus 5.5) after a review of this plan against
`46ff387`: teardown ownership, the install owner, forge proof for the current
tree, a 1-round-trip target, a usage gate, and the output contract.
**Lives on:** branch `ai/sync-script`, worktree
`../agent-global-instructions-sync-script` (step 0 is already done).
**Owner on execution:** a fresh Claude Code session, run interactively.
**Read this whole file before doing anything.** Steps 0–4 are not optional
preamble; step 5 is the only step that writes product code.

---

## 1. Why this exists

PR #55 (`46ff387`, merged 2026-10-02) taught `/sync` to recognise a worktree,
fold work back toward the primary checkout, offer a gated teardown, and nudge
about the remote. The behaviour is right and is **not** in question here.

What is in question is its cost. A Claude Code slash command is a **prompt, not
a program**: the `` !`cmd` `` lines in the frontmatter execute and their output
is pasted into the model's context, then the numbered steps are *read* by the
model, which carries them out through individual Bash calls. Nothing in the file
self-executes. Measured on `46ff387`:

| | Before #55 (`cd5e0f2`) | After #55 (`46ff387`) |
|---|---|---|
| `commands/sync.md` prompt body | 198 words / 1,313 bytes | **1,205 words / 7,635 bytes** |
| Injected state per invocation | ~5 bytes | **~627 bytes** |

That is roughly **6× the per-invocation prompt cost**, paid on every run —
including the common case of running in the primary checkout, where the three
new steps (8, 9, 12) evaluate to no-ops. Of the injected bytes, `git worktree
list` alone is 572.

Joe's ask, verbatim: *"I want it to be as token efficient as possible, ideally
using none."*

**Zero is unreachable for a slash command** — a command *is* tokens. It is
reachable for the *logic*, because almost all of `/sync` is deterministic:
fetch, default-branch lookup, stash/rebase/pop, worktree detection, the
primary's fast-forward, the `origin/<default>..HEAD` range, the divergence
count, the upstream probe, `ls-remote`, and the whole teardown ordering. None of
that needs a language model; it needs `if` statements.

**The precedent is already in this repo.** `/sync` does not describe worktree
reaping in prose — it calls `~/.ai/worktree-sweep.sh` (32,660 bytes of shell
with its own documented safety model) in one line. That line costs ~15 tokens
and does more careful work than 300 tokens of instructions could. This plan
applies that same pattern to the rest of `/sync`.

**Target:** `commands/sync.md` from ~1,205 words to **≤200 words** (frontmatter
plus body, as `wc -w` counts it), and the per-run Bash round-trips from a
dozen-plus to **one** on the primary-checkout path.

**The cost that is always on is the description, not the body.** The body
loads only when `/sync` runs. The frontmatter `description` is loaded into the
skill listing of *every* session, and #55 roughly doubled it (~19 → ~40 words,
adding "— folding the work back and offering teardown…"). If `/sync` is rarely
run, that is the larger cost. Target: **description ≤20 words**.

**Nothing here is live yet on this machine.** `~/.claude/commands/sync.md` is a
regular 1,313-byte file dated 2026-09-28: the pre-#55 version. Commands install
by **copy**, not symlink, so neither #55 nor this plan reaches a session until
Joe re-runs the installer.

---

## 2. What the model must still decide

Keep this list honest — it is the boundary between script and prompt, and
scope creep across it is how the token win gets given back.

Genuinely needs judgment:

1. **Whether unlanded commits should be folded or routed to `/ship`.** Shipping
   unreviewed work into the integration tree is the thing `/ship` exists to
   prevent, so this stays a proposal to Joe, never an action.
2. **Composing the single closing ask** (teardown + remote), because Joe's
   instructions require one bundled ask with the decision last.
3. **Reporting a rebase conflict** in terms of what actually collided.

Everything else is mechanical and belongs in the script.

---

## 3. Facts already established — do not re-derive these

Verified empirically on **git 2.43.0** during PR #55. Re-testing them is wasted
work; they are the reason several instructions are worded as they are.

| Fact | Why it matters |
|---|---|
| `git worktree remove .` from *inside* the tree **succeeds** — git does not refuse | The shell's cwd is destroyed; every later command dies with `getcwd: cannot access parent directories`. `cd <primary>` must come first, and `git -C` does **not** help — it is the shell's cwd that vanishes, not git's |
| `git branch -d` refuses while the branch is checked out (`cannot delete branch '<b>' used by worktree at …`) | Tree removal must precede branch deletion |
| `git -C <primary> merge --ff-only <branch>` works from inside a worktree | The fold-back needs no `cd` |
| `git switch <base>` from a worktree always fails (`already used by worktree at …`) | Drive the primary with `git -C` only |
| Unforced `git worktree remove` **silently deletes ignored files** | git gives no protection here; `worktree-sweep.sh`'s stricter gate does. Relevant because `test.sh` regenerates `commands/codex/`, `commands/cursor/`, `roles/codex/` into whatever tree it runs in, which makes that tree look `DIRTY` to the sweep |
| Post-rebase: `git rev-list --left-right --count @{upstream}...HEAD` → non-zero **left**; plain `git push` rejected `non-fast-forward`; `--force-with-lease` succeeds | The divergence test and the safe push form |
| A never-pushed branch: `git rev-parse --abbrev-ref @{upstream}` → `fatal: no upstream configured for branch …` | Nothing to sync; raise nothing |
| `gh pr merge` run from a worktree aborts its own cleanup with `fatal: 'main' is already used by worktree at …` **and still exits 0** | Confirm merges against the forge, never by exit code. Hit for real on PR #55 |

Added 2026-10-03, each read from the repo or the machine rather than re-tested:

| Fact | Why it matters |
|---|---|
| A script's `cd` cannot move its caller's shell. Claude's Bash tool keeps a persistent cwd across calls | Moving teardown into the script does **not** carry the "`cd <primary>` first" rule with it. The caller is still left inside a deleted directory. The script must refuse when its inherited `$PWD` is inside the target, so the only form that works is `cd <primary> && ~/.ai/sync.sh --teardown <path>` |
| `hooks/worktree-reap.sh:380–382` assigns `CURRENT` **before** any merge-proof logic runs | The sweep never judges the branch of the tree you stand in. `sync.sh` cannot get forge proof for its own branch from the sweep as it is today |
| `install-hooks.sh:21` exits with `jq is required.` when jq is missing | A script installed only by `install-hooks.sh` can be absent while the command that calls it is installed. The sweep CLI already has this flaw |
| `render-commands.sh:56` rewrites each `` !`cmd` `` into "run `cmd`" for the Codex and Cursor ports | Each injection costs a full round-trip on the ports. Fewer injections save more there than on Claude |
| `customize.sh:31–35` supports **bash 3.2** (macOS system bash) | `sync.sh` must too: no associative arrays, no `mapfile`, no `${v,,}`. The git facts above were seen on 2.43 only, so tests should assert the property relied on, not the version |

### The install precedent, with line numbers

`~/.ai/worktree-sweep.sh` is the model to copy, **except for which installer
owns it** (see Q1):

- **Source in repo:** `hooks/worktree-reap.sh` (it lives in `hooks/` because it
  is dual-mode — a Stop hook *and* a sweep CLI).
- **Installed by:** `install-hooks.sh:273–285` — `cp` + `chmod +x` to
  `$HOME/.ai/worktree-sweep.sh`, with an `cmp -s` up-to-date short-circuit.
- **Removed by:** `uninstall.sh:375–378`, guarded by a **content grep**
  (`grep -q 'Worktree reaper'`) so it never deletes a file it did not write.
- **Tested by:** `test.sh:1968–1975` — asserts installed-and-executable,
  byte-identical to the repo source, and gone after uninstall.

Other root-level command-backing scripts already exist: `converge.sh` (called
by `/worktrees` as `./converge.sh`), `audit.sh`, `lm`. Note the distinction:
`converge.sh` is run **from the checkout**, but `/sync` must work in *any* repo
on the machine, so its script has to be installed machine-wide under `~/.ai/`.

### Repo rules that will bite

- **`template.md` is the only editable instruction surface** — but this plan
  touches `commands/sync.md`, not the globals, so no render is involved. Do
  **not** render globals into this checkout (`customize.sh --project` refuses
  by design).
- If `template.md` *does* end up changed, regenerate `examples/*.md` or CI
  fails (loop in `AGENTS.md`).
- Full CI, in this order:
  ```sh
  shellcheck --shell=bash ./*.sh hooks/*.sh evals/*.sh
  ./test.sh          # 258 passing on 46ff387
  ./evals/run.sh     # 14 behaviours instructed, 0 broken
  ./verify-skills.sh # 5 trees, 0 problems
  ```
- **`shellcheck` covers `./*.sh` and `hooks/*.sh`.** A new script in either
  location is linted automatically — a new *directory* (e.g. `bin/`) would not
  be, and would need the CI glob widened.
- Command ports (`commands/codex/`, `commands/cursor/`) are **generated** by
  `render-commands.sh` and gitignored. Never hand-author them. A thin wrapper
  command ports *better* than a long one.
- **Installers are blocked as self-modification in auto mode.** Do not run
  `install-hooks.sh` or `install-commands.sh`; hand Joe the command to run
  himself. This is why a live `/sync` run cannot be part of the agent's own
  done-condition (see §5).

---

## 4. Execution steps

### Step 0 — Workspace safety preflight (before the first write)

This repo routinely has concurrent agents. The primary checkout is
**integration-only**.

```sh
git -C /home/jsteinka/projects/agent-global-instructions rev-parse --show-toplevel
git -C /home/jsteinka/projects/agent-global-instructions status --short
git -C /home/jsteinka/projects/agent-global-instructions worktree list --porcelain
ls -d /home/jsteinka/projects/agent-global-instructions-* 2>/dev/null
```

Then create an isolated sibling worktree and do **all** writes there:

```sh
git -C /home/jsteinka/projects/agent-global-instructions fetch --all --prune
git -C /home/jsteinka/projects/agent-global-instructions worktree add \
  -b ai/sync-script ../agent-global-instructions-sync-script main
```

**Done 2026-10-03.** The worktree exists and this plan is committed on
`ai/sync-script` (first commit `99f0853`, the plan as originally written; the
revision follows it). A stray untracked copy may still sit in the primary
checkout; removing it is Joe's call. Re-run the four inventory commands above
anyway before the first write, since another agent may have appeared.

Known at the time of writing — leave both alone, neither is yours:

- `../agent-global-instructions-claude` (`ai/claude`) — one unmerged changelog
  commit from another session; flagged `DIRTY` by the sweep.
- two `.claude/worktrees/bridge-cse_*` trees, one `locked`.

### Step 0.5 — Measure usage, and let the refuter decide whether to go on

The last falsifier in §5 ("if `/sync` is run rarely…") can be checked now, so
check it before spending anything on steps 1–5.

1. Count real `/sync` invocations: transcripts under
   `~/.claude/projects/*/*.jsonl` (match the command invocation, not any
   mention of the word) plus `~/.ai-logs/tool-calls.jsonl`. A rough grep on
   2026-10-03 matched only 3 transcript files. That was a loose pattern match,
   not a count, so redo it properly.
2. Compute: invocations × per-invocation tokens (body + injections) against
   sessions × description tokens (the always-on cost from §1).
3. Hand both numbers to the refuter (step 3) **first**. If its case for leaving
   `/sync` alone survives those numbers, stop here and recommend the small fix
   instead: shrink the description and drop the `git worktree list` injection.

### Step 1 — `/grill-me` (do this *before* writing any code)

This is an architecture change to a command every session can invoke, so it is
foundational by Joe's rules: grill first, and **ask in rounds — every question
whose prerequisites are settled goes in the same round, numbered, each with a
recommended answer.** The ten below are all answerable now, so they are
**one round**, not ten messages.

1. **Where does the script live, and which installer copies it?**
   *Recommend:* source at repo root as `sync.sh` (beside `converge.sh` and
   `audit.sh`, so existing `shellcheck ./*.sh` covers it), installed to
   `~/.ai/sync.sh` by **`install-commands.sh`**, because that installer ships
   the command that calls it. `install-hooks.sh` exits early without jq
   (`:21`), which would leave a thin `/sync` with no script behind it. Reuse
   the *shape* of the sweep helper at `install-hooks.sh:273–285` (`cmp -s`
   short-circuit, `cp` + `chmod +x`), not its location. Record the sweep CLI's
   own install-owner flaw as a follow-up, not something to fix in this pass.
   *Alternative:* `hooks/sync.sh` — also shellchecked, but semantically wrong
   since it is not a hook.
2. **What is the script's stdout contract?** This is the single most important
   design artifact in this plan: it is what the model reads instead of running
   twelve commands.
   *Recommend:* the default output is written **for the agent**: a fixed set of
   `key: value` lines (state, what `--apply` would do or did, a status word
   from a stable vocabulary), ending in `ask:` lines. Each `ask:` line names one
   of the three §2 judgment calls that is open, with the facts it needs on the
   same line. No `ask:` lines means there is nothing to decide. `--json` exists
   for `test.sh` and other programs, not for the model: JSON's quotes, braces
   and repeated keys cost tokens and give the model nothing. This inverts the
   sweep, whose `--json` is the machine path, deliberately.
   **Plus an exit-code table, written into this plan before step 5**, with a
   reason string for each code. At minimum: rebase conflict (rebase left in
   progress), stash-pop conflict after a clean rebase, `--ff-only` refused in
   the primary, primary dirty, teardown refused (dirty / locked / unmerged),
   and teardown refused because the caller stands inside the target.
3. **Dry-run by default, or act by default?**
   *Recommend:* exactly the sweep's split — default reports and writes nothing;
   `--apply` performs the safe mutations. **Teardown and any push stay out of
   `--apply` entirely.** Push is never in the script. Teardown is its own
   subcommand (Q8), run only after Joe says yes.
4. **Does the rebase itself move into the script?** It mutates the working tree,
   which is more than the sweep ever does.
   *Recommend:* yes, under `--apply`, including stash/pop, because the whole
   token win evaporates if the model still drives six git calls. Conflicts →
   non-zero exit plus a reason from the Q2 table, and the script stops.
5. **What happens when `~/.ai/sync.sh` is not installed?** A thin wrapper that
   assumes it becomes a broken command on a fresh machine (this repo is a
   portable installer — it must work on *any* machine).
   *Recommend:* the command keeps a ~3-line prose fallback (fetch + rebase +
   "tell Joe to run `install-commands.sh`"), and nothing more. The fallback
   never offers teardown.
6. **What do the frontmatter injections become?**
   *Recommend:* replace all four with **one**: the dry run itself,
   `` !`~/.ai/sync.sh 2>/dev/null || echo "sync.sh: not installed"` ``.
   The model sees the full state before it acts, so the primary-checkout path
   is a single `--apply` call, and a missing script shows up with no tool call
   at all. Mutation stays a real tool call, so `allowed-tools` still gates it.
   This also cuts the Codex and Cursor ports from four round-trips to one
   (`render-commands.sh:56`).
7. **Does the dry run fetch?**
   *Recommend:* no. Fetching at prompt expansion slows every invocation and
   hits the network before the model has seen anything. The dry run reports
   local state, labelled `as of last fetch: <time>`, and `--apply` fetches
   first, then re-derives everything it acts on.
8. **Who runs the teardown once the prose is gone?** If it stays in prose,
   steps 9a–c (~250 words) stay and the ≤200 target fails. If it moves into the
   script, the §3 cwd fact no longer protects the caller (a script's `cd`
   cannot move its caller's shell).
   *Recommend:* a separate `sync.sh --teardown <path>`: tree removal, then
   `branch -d`, never `--force` or `-D`. It refuses, with its own exit code,
   when its inherited `$PWD` is inside `<path>`, so the only form that works is
   `cd <primary> && ~/.ai/sync.sh --teardown <path>`. The dry run prints that
   exact line in its `ask:` output for the model to copy after Joe says yes.
9. **Where does forge proof for the current branch come from?** The sweep
   marks the caller's tree `CURRENT` before judging merges
   (`hooks/worktree-reap.sh:380–382`), so it cannot answer today.
   *Recommend:* add a single-branch mode to the sweep (e.g.
   `--proof <branch>`, reporting merged / unmerged and the evidence) and have
   `sync.sh` call it. Copying the forge logic into `sync.sh` is the route that
   drifts. This puts `hooks/worktree-reap.sh` in scope.
10. **Scope: `/sync` only, or also `/ship` and `/worktrees`?** All three
   restate default-branch lookup, merge-proof and teardown logic in prose.
   *Recommend:* `/sync` only in this pass, but have the script expose
   subcommands general enough that `/ship` can adopt them next, and record the
   duplication rather than fixing it blind.

Stop grilling when the answers stop changing the plan, not when the questions
run out.

### Step 2 — The three-lens question

Before building, answer explicitly: **across UX, DX and AX, what would improve
this plan?** Answer all three or state which is being traded away.

AX is not a courtesy here — the consumer of `commands/sync.md` *is* an agent, so
the stdout contract from question 2 is an agent-experience design problem, and
an illegible summary is a product defect. The test: **can the model act on one
block of dry-run output without re-running anything to interpret it?** The
`ask:` lines in Q2 are the concrete answer; check them against that test.

### Step 3 — Cross-vendor refuter (replaces the separate rival draft)

Architectural and expensive to reverse, so it trips the cross-vendor escalation
in `~/.ai/orchestration.md` (read it first). Available delegates, all verified
present on 2026-10-02: `codex`, `agy`, `agent`.

A separate rival draft and a same-model refuter do overlapping jobs for a
script this size. Use **one** delegate for both: send `codex` the refuter brief
plus the step 0.5 numbers. Ask it to argue for leaving `/sync` alone, and, if
it concedes, to give *its own* script/prompt split rather than a review of this
one. Diff that split against this plan. A cross-vendor refuter checks the model,
not just the agent, so this one call satisfies both the sole-checker rule and
the rival-draft rule.

If Joe wants the full escalation anyway, because the command runs in every
repo, restore the separate rival draft. That is his call.

### Step 4 — Agent team

Spawn 3 in-tool roles in parallel with disjoint scope (see
`~/.ai/agent-teams.md`). The refuter is the step 3 delegate:

- **`technical-architect`** — the script/prompt boundary, the stdout contract,
  and the exit-code table.
- **`harness-steward`** — `install-commands.sh`, `uninstall.sh`, `test.sh`
  coverage, the ports, and the sweep's new `--proof` mode in
  `hooks/worktree-reap.sh`.
- **`backend-engineer`** — the shell itself: quoting, `set -u`, bash 3.2,
  exit codes, the `--teardown` cwd refusal, worktree edge cases.

### Step 5 — Implementation

1. **Anchor first.** PR #55 shipped these steps **unanchored** —
   `evals/behaviours.md` pins nothing about them, so a future bloat pass could
   delete them without failing CI by name. This repo's own `AGENTS.md` warns
   that green CI is not proof a cut was safe. Write the anchors *before* the
   rewrite, so the rewrite is forced to keep them. `evals/run.sh:15–19`
   supports `file:`, as BEH-13 already does for `commands/ship.md`:
   - **BEH-15** — the gated teardown ask, `file: commands/sync.md` (that
     judgment stays in the prompt).
   - **BEH-16** — teardown refuses while the caller stands inside the tree,
     `file: sync.sh`.
   Both with `origin:` pointing at PR #55 and this plan.
2. **The sweep's `--proof <branch>` mode** in `hooks/worktree-reap.sh` (Q9),
   with its own `test.sh` case, before `sync.sh` depends on it.
3. `sync.sh` (location per Q1) implementing everything in §2's "mechanical"
   list plus `--teardown` (Q8), honouring the §3 facts with each cited in a
   comment. Bash 3.2 compatible. Output and exit codes exactly as the Q2
   contract and table say.
4. Rewrite `commands/sync.md` to a thin wrapper — target **≤200 words** —
   keeping only the three judgment calls from §2, the single dry-run injection
   (Q6), and the minimal fallback (Q5). Shrink the `description` to **≤20
   words**. Update `allowed-tools`: add `Bash(~/.ai/sync.sh:*)`, keep
   `Bash(git:*)` for the fallback and `Bash(cd:*)` for the teardown line.
   Without the new entry every script call prompts for permission.
5. Wire the installer (**`install-commands.sh`**, per Q1) and the uninstaller
   (`uninstall.sh`, content-grep guarded), mirroring the shape of
   `install-hooks.sh:273–285` / `uninstall.sh:375–378`.
6. Add `test.sh` coverage modelled on `:1968–1975` (installed, executable,
   byte-identical, gone after uninstall), **plus** behavioural tests in
   throwaway repos that run `./sync.sh` from the repo, not `~/.ai/sync.sh`:
   one case per row of the exit-code table, the worktree fold-back, and the
   `--teardown` cwd refusal. Assert the git behaviour each relies on, not the
   git version.
7. Run the full CI matrix from §3, in order.
8. `/ship` it. In the PR body, hand Joe the post-merge install command and the
   live check from §5 as one pasteable block.

---

## 5. Done-condition and falsifier

**Done when all of:**

The agent can prove these itself, before the PR:

- `commands/sync.md` is ≤200 words (`wc -w commands/sync.md`), down from 1,205,
  and its `description` is ≤20 words.
- A primary-checkout `/sync` costs **≤1 Bash round-trip**: the one `--apply`
  call. Measured by counting Bash tool calls in a transcript of a
  primary-checkout run. Since the installed command is not this one (§1), the
  check runs the rewritten prompt against `./sync.sh`, not via the slash
  command.
- `shellcheck` clean; `./test.sh` ≥258 passing, 0 failed; `./evals/run.sh` 0
  broken with ≥16 behaviours (BEH-15, BEH-16); `./verify-skills.sh` 0 problems.
- Every behaviour PR #55 added still happens — proven by the `test.sh`
  behavioural cases *running* `./sync.sh` in throwaway repos and worktrees,
  not by reading the script.
- `git status` clean on the branch; PR open.

Joe's part, after merge, which the agent cannot do (installers are gated):

- Run `./install-commands.sh` from the primary checkout on `main`, then run
  `/sync` once from inside a throwaway worktree. The PR body carries both
  lines, ready to paste.

**Falsifier — what would prove this plan wrong:**

- The script's summary cannot be acted on without the model re-running git
  commands to interpret it. Then the work moved tokens rather than removing
  them, and the extraction failed.
- The rewritten command needs *more* round-trips than today on the common
  primary-checkout path.
- The script's safety gates end up weaker than the prose they replaced —
  particularly: a teardown that runs without Joe's approval, a `--force` or
  `-D` reachable without forge proof, or a push the script performs itself.
  Any one of those means **abandon the extraction and keep the prose.** Prose
  degrades gracefully; a script fails silently.
- `--teardown` succeeds when invoked from inside the tree it removes. That
  means the cwd refusal is broken, and the caller's shell would be left in a
  deleted directory.
- `sync.sh` judges a squash merge differently from the sweep. That means the
  forge logic was copied rather than shared through `--proof`.
- The refuter's case for leaving `/sync` alone survives contact with the
  measurements. If `/sync` is run rarely, 1,205 words of a 200k window may
  simply not be worth a new installed script and its test surface.

---

## 6. Gates — stop and ask

These override the autonomy posture, and hold inside every iteration:

- **Do not run `install-hooks.sh`, `install-commands.sh`, or any installer.**
  Blocked as self-modification; hand Joe the command.
- **The changelog entry is a confirmation gate.** Propose it at session end;
  never write or commit `CHANGELOG.md` unapproved. (Note: PR #55's own
  changelog entry is **still outstanding** — draft below.)
- **Merging is a confirmation gate.** `/ship` opens the PR and stops; "ship"
  alone is not a merge go-ahead.
- **Worktree teardown** needs Joe's yes, and the §3 ordering.
- No full-bypass flags on any delegate.

### Do **not** run this as an unattended `/goal`

Step 1 is a round of questions *to Joe*, and §6 is four confirmation gates.
Asking inside a goal just ends the turn and starts another, so a goal aimed at
this plan would burn turns waiting for answers nobody is there to give. Run it
**interactively**. If a long-running primitive is wanted, it belongs only around
step 5 once every question in step 1 is answered.

---

## 7. Outstanding from PR #55 — carry this forward

The changelog entry for #55 was proposed and **never approved or written**.
Draft, for Joe to approve or edit:

> **Taught `/sync` it may be standing in a worktree** (2026-10-02, Claude).
> *The ask:* `/sync` should know when it is in a worktree, sync back to the
> local branch, and offer to clean up the tree and branch; then a closing nudge
> about syncing the remote. *What changed:* worktree detection via git-dir vs
> git-common-dir; a fold-back toward the primary checkout driven by `git -C`; a
> gated teardown with a verified step order; a remote nudge offering
> `--force-with-lease` when the rebase left the branch diverged, bundled into
> the same single ask as the teardown question. *Why this approach:* the closing
> sweep marks the current tree `CURRENT` and never reaps it, so the tree you ran
> `/sync` from could never be cleaned up by the command itself; and `/sync`
> fetches but never pushes, so its own rebase left the branch diverged with
> nothing pointing at the cause. *Considered and rejected:* auto-merging
> unlanded commits into the integration tree (routes unreviewed work around
> `/ship`); having the sweep reap its own caller (removing the tree you stand in
> kills the shell's cwd — confirmed on git 2.43, which deletes rather than
> refuses); and pushing as part of the sync (an external send, and
> force-pushing a branch another agent may share is what the gate exists for).
> *Not done:* the new steps shipped unanchored in `evals/behaviours.md`.
> *Known cost:* grew the command 198 → 1,205 words, which
> `PLAN-sync-script-extraction.md` exists to undo.

---

## 8. Step 0.5 result — 2026-10-05, Claude (Opus 5.5)

**Measured:**

- `~/.ai-logs/tool-calls.jsonl`, Claude, 2026-06-14 → 2026-10-05: 268 distinct
  sessions. Skill calls with `skill=sync`: **one** invocation (a
  Pre/PostToolUse pair, 2026-07-21, started by the model). For scale, `ship`
  has 46 log lines.
- `~/.claude/projects/**/*.jsonl`, 73 retained transcripts (2026-08-12 →
  2026-10-05, excluding the measuring session): **zero** user-typed
  `<command-name>/sync</command-name>`.
- Not measured: typed use before 2026-08-12 (those transcripts are gone, and
  typed commands are not in the tool log), and Codex, Cursor and agy port usage.

**Cost** (estimated at ~1.3 tokens/word): description +14 words × 268 sessions
≈ 5k tokens; body and injections ≈ +1.5k per run × 1 run. That is about 6.5k
tokens over 16 weeks, and none of it was actually paid, since the installed
copy is pre-#55.

**Refuter verdict: SMALL FIX** (`~/.ai-context/agent-global-instructions-sync-usage/agents/refuter.md`).
Codex and agy-with-tools both failed to run; see `PLAN-cross-vendor-delegates.md`
on `ai/delegate-fix`. The verdict came from agy with the brief inlined, so it
could not check the repo itself. Its strongest counterpoint, recorded here so it
is not lost: usage was measured against the **pre-#55** command, so low use of
worktree syncing is partly because nobody had it. Re-measure after #55 is
installed before reopening this plan.

**Shipped instead:** description 32 → 16 words; `` !`git worktree list` ``
injection removed (572 of 627 injected bytes). Step 3 of the body already runs
`git worktree list --porcelain` itself when it needs it.
