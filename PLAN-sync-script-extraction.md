# Plan — put `/sync` on a token diet by extracting a script

**Status:** not started. Written 2026-10-02 by Claude (Opus 5), after PR #55.
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

**Target:** `commands/sync.md` from ~1,205 words to **≤200 words**, and the
per-run Bash round-trips from a dozen-plus to **one or two**.

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

### The install precedent, with line numbers

`~/.ai/worktree-sweep.sh` is the model to copy:

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
  `install-hooks.sh`; hand Joe the command to run himself.

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

Known at the time of writing — leave both alone, neither is yours:

- `../agent-global-instructions-claude` (`ai/claude`) — one unmerged changelog
  commit from another session; flagged `DIRTY` by the sweep.
- two `.claude/worktrees/bridge-cse_*` trees, one `locked`.

### Step 1 — `/grill-me` (do this *before* writing any code)

This is an architecture change to a command every session can invoke, so it is
foundational by Joe's rules: grill first, and **ask in rounds — every question
whose prerequisites are settled goes in the same round, numbered, each with a
recommended answer.** The seven below are all answerable now, so they are
**one round**, not seven messages.

1. **Where does the script live, and which installer copies it?**
   *Recommend:* source at repo root as `sync.sh` (beside `converge.sh` and
   `audit.sh`, so existing `shellcheck ./*.sh` covers it), installed to
   `~/.ai/sync.sh` by `install-hooks.sh` reusing the helper at `:273–285`.
   *Alternative:* `hooks/sync.sh` — also shellchecked, but semantically wrong
   since it is not a hook.
2. **What is the script's stdout contract?** This is the single most important
   design artifact in this plan: it is what the model reads instead of running
   twelve commands.
   *Recommend:* mirror `worktree-sweep.sh` — a short human-readable report by
   default plus a `--json` mode, with a stable status vocabulary (the sweep's
   own is `REAPABLE CURRENT MAIN LOCKED DIRTY UNMERGED …`). The command consumes
   `--json`; a human running it by hand gets the text.
3. **Dry-run by default, or act by default?**
   *Recommend:* exactly the sweep's split — default reports and writes nothing;
   `--apply` performs the safe mutations. **Teardown and any push stay out of
   `--apply` entirely**; they are gated on Joe and happen in a later turn.
4. **Does the rebase itself move into the script?** It mutates the working tree,
   which is more than the sweep ever does.
   *Recommend:* yes, under `--apply`, including stash/pop, because the whole
   token win evaporates if the model still drives six git calls. Conflicts →
   non-zero exit plus a machine-readable reason, and the script stops.
5. **What happens when `~/.ai/sync.sh` is not installed?** A thin wrapper that
   assumes it becomes a broken command on a fresh machine (this repo is a
   portable installer — it must work on *any* machine).
   *Recommend:* the command keeps a ~3-line prose fallback (fetch + rebase +
   "tell Joe to run `install-hooks.sh`"), and nothing more.
6. **Do the frontmatter injections shrink?**
   *Recommend:* drop `` !`git worktree list` `` (572 of 627 bytes) and
   `` !`git rev-parse --show-toplevel` ``; the script reports both. Keep
   `branch` and `status --short` — they are ~5 bytes and orient the model when
   the script is missing.
7. **Scope: `/sync` only, or also `/ship` and `/worktrees`?** All three
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
an illegible summary is a product defect. Concretely: can the model act on one
block of script output without re-running anything to interpret it?

### Step 3 — Rival draft (cross-vendor)

Architectural and expensive to reverse, so it trips the cross-vendor escalation
in `~/.ai/orchestration.md` (read it first). Available delegates, all verified
present: `codex`, `agy`, `agent`.

Send the **same brief** to one other vendor and ask for *its own* draft of the
script/prompt split — not a review of this one — then diff the two. Grilling
attacks Joe's assumptions; a rival draft attacks the author's.

### Step 4 — Agent team

Spawn 3–4 roles in parallel with disjoint scope (see `~/.ai/agent-teams.md`):

- **`technical-architect`** — the script/prompt boundary and the stdout contract.
- **`harness-steward`** — installer, uninstaller, `test.sh` coverage, the ports.
- **`backend-engineer`** — the shell itself: quoting, `set -u`, exit codes,
  worktree edge cases.
- **`refuter`** — mandatory. Its job is to **break** the conclusion that this
  extraction is worth it, not to confirm it. Give it the strongest case for
  *leaving `/sync` alone* and let it argue. No agent may be the sole checker of
  its own work.

### Step 5 — Implementation

1. `sync.sh` (location per Q1) implementing everything in §2's "mechanical"
   list, with the §3 facts honoured and cited in comments.
2. Rewrite `commands/sync.md` to a thin wrapper — target **≤200 words** —
   keeping only the three judgment calls from §2 and the minimal fallback.
3. Wire the installer (`install-hooks.sh`), the uninstaller (`uninstall.sh`,
   content-grep guarded), mirroring `:273–285` / `:375–378`.
4. Add `test.sh` coverage modelled on `:1968–1975`, **plus** behavioural tests
   in throwaway repos for the §3 facts the script now depends on.
5. **Add an eval anchor.** PR #55 shipped these steps **unanchored** —
   `evals/behaviours.md` pins nothing about them, so a future bloat pass could
   delete them without failing CI by name. This repo's own `AGENTS.md` warns
   that green CI is not proof a cut was safe. Fix that here: anchor the
   worktree-awareness behaviour and the gated-teardown behaviour with an
   `origin:` field pointing at PR #55.
6. Run the full CI matrix from §3, in order.
7. `/ship` it.

---

## 5. Done-condition and falsifier

**Done when all of:**

- `commands/sync.md` is ≤200 words (`wc -w commands/sync.md`), down from 1,205.
- A primary-checkout `/sync` run costs **≤2 Bash round-trips**.
- `shellcheck` clean; `./test.sh` ≥258 passing, 0 failed; `./evals/run.sh` 0
  broken with ≥15 behaviours (the new anchor); `./verify-skills.sh` 0 problems.
- Every behaviour PR #55 added still happens — verified by *running* `/sync`
  from inside a throwaway worktree, not by reading the script.
- `git status` clean on the branch; PR open.

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
- The refuter's case for leaving `/sync` alone survives contact with the
  measurements. If `/sync` is run rarely, 1,205 words of a 200k window may
  simply not be worth a new installed script and its test surface.

---

## 6. Gates — stop and ask

These override the autonomy posture, and hold inside every iteration:

- **Do not run `install-hooks.sh` or any installer.** Blocked as
  self-modification; hand Joe the command.
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
