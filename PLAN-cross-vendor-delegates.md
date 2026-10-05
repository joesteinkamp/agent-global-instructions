# Plan — make the cross-vendor delegates actually run

**Status:** steps 1–2 done (in-repo docs + test); steps 3–5 open and need Joe or a docs read. Written 2026-10-05 by Claude (Opus 5.5).
**Lives on:** branch `ai/delegate-fix`, worktree
`../agent-global-instructions-delegate-fix`.
**Scope:** the documented delegate invocations (`playbooks/orchestration.md`,
`commands/verify.md`, `commands/improve.md`) and the host setup they depend on.
Not in scope: routing (`model-routing.md`), roles, or the team construct.

---

## 1. What broke, observed 2026-10-05

During step 0.5 of `PLAN-sync-script-extraction.md`, one refuter brief was sent
across vendors from a Claude Code session on this machine (Ubuntu, kernel
6.8.0-136, codex-cli 0.144.1). Every documented form failed. Only a degraded
fallback produced a verdict.

| # | Delegate and form | Exact failure | Cause |
|---|---|---|---|
| F1 | `codex exec --sandbox workspace-write --cd <ctx-dir>` (the form at `orchestration.md:187`, `verify.md:113`, `improve.md:63`) | `Not inside a trusted directory and --skip-git-repo-check was not specified.` Exit 1, no output | **Certain.** The context dir is not a git repo, and codex refuses untrusted non-repo dirs. The documented form fails on every machine, every time |
| F2 | Same, with `--skip-git-repo-check` added | Starts, then every shell call dies: `bwrap: setting up uid map: Permission denied`. The `apply_patch` write to `agents/refuter.md` also fails. Exit **0** with no output file | **Partly known.** `kernel.apparmor_restrict_unprivileged_userns = 1` on this host. `bwrap` is linuxbrew's (`/home/linuxbrew/.linuxbrew/bin/bwrap` → bubblewrap 0.11.2), not `/usr/bin/bwrap`. `unshare -Ur true` fails inside Claude Code's sandboxed shell. **Not known:** whether it also fails outside Claude's sandbox. That probe was denied in auto mode, so the cause is either host AppArmor policy or Claude's sandbox nesting, and the fix differs (§3, step 3) |
| F3 | `agy -p … --mode accept-edits --add-dir <ctx> --add-dir <repo>` | `jetski: no output produced — a tool required the "command" permission that headless mode cannot prompt for, so it was auto-denied.` Exit **0** | **Certain.** Headless `agy` cannot prompt, and nothing on this machine allows shell commands. `install-settings.sh:305` deliberately leaves Antigravity's permission model unwired |
| ✓ | `agy -p` with the brief and plan excerpts **pasted into the prompt**, no tools needed, stdout captured to `agents/refuter.md` | Worked: 1,316-word verdict | A degraded mode. The delegate cannot read the repo, so it cannot cite `file:line`. The refuter rubric's Grounding axis caps at 1 |

`agent` (Cursor CLI) was not tried.

**Two of the three failures exit 0.** The playbook's "wait on each job and check
its exit status" would pass both. Only "a delegate that produced no
`agents/<name>.md` is a failure" caught them, so that rule is load-bearing.

---

## 2. Done-condition and falsifier

**Done when:**

- Every documented `codex exec` delegate form includes `--skip-git-repo-check`
  (F1), and `test.sh` pins that so it cannot drift back.
- The playbook names F2 and F3 by their exact error text, says what each means,
  and gives a one-line smoke test to run before a wave, so the next session
  diagnoses them in one step rather than three.
- The inlined-context fallback is documented as the last tier, with its
  grounding cost stated.
- CI green: `shellcheck`, `./test.sh`, `./evals/run.sh`, `./verify-skills.sh`.
- **Joe's part (gated, host-level):** F2 and F3 are fixed on this machine, so a
  codex reviewer and an agy reviewer each write `agents/<name>.md` with
  `file:line` citations from a Claude Code session.

**Falsifier:**

- After the doc fixes, a fresh session following the playbook still cannot get
  one tool-using cross-vendor verdict on this machine. Then documentation was
  not the bottleneck; the host fix is, and should have gone first.
- An F3 fix that grants `agy` anything beyond read-only commands. That turns a
  reviewer into an editor and breaks "the repo stays read-only to it"
  (`orchestration.md:187`).
- Any fix that reaches for a full-bypass flag. The gates forbid it, and the
  error text for F3 suggests one.

---

## 3. Steps

### Step 1 — F1: add `--skip-git-repo-check` everywhere codex is documented (in-repo, ungated)

Sites: `playbooks/orchestration.md:187`, `commands/verify.md:113`,
`commands/improve.md:63`. The flag is a trust check, not a sandbox bypass:
codex's own error names it as the fix, and the sandbox mode is unchanged.
Add a `test.sh` assertion that every `codex exec` example under `commands/`
and `playbooks/` that uses `--cd` also carries the flag.

### Step 2 — Playbook: name the failures and add a smoke test (in-repo, ungated)

In `playbooks/orchestration.md` ("A silent wave is a sandbox problem…"),
broaden the bullet from network-only to the three failures in §1, by exact
error text:

- `Not inside a trusted directory` → F1, add the flag.
- `bwrap: setting up uid map: Permission denied` → the Linux host cannot give
  codex a user namespace. Codex runs but every command fails, and it **exits
  0**. Drop codex for the session and tell the user. The host fix is theirs.
- `headless mode cannot prompt … auto-denied` → agy has no allow rule for
  shell commands. Drop agy, or use the inline tier. Never take the
  `--dangerously-skip-permissions` suggestion in the error text.

Add a pre-wave smoke test, one line per vendor, that runs a trivial command
and greps for the failure strings. A failed probe costs seconds; a failed wave
costs a full timeout.

Add the **inline tier** to "React to failing delegates": when no delegate can
use tools, paste the brief and the relevant excerpts into the prompt, capture
stdout to `agents/<name>.md`, and say in the report that the verdict could not
check the repo itself.

### Step 3 — F2: fix codex's sandbox on this host (Joe, gated)

First, one probe settles the open cause. Run it in a plain terminal, **not**
through Claude:

```sh
unshare -Ur true && echo userns-ok || echo userns-blocked
```

- **`userns-blocked`** → host policy (Ubuntu's AppArmor userns restriction).
  Options, all needing `sudo`, so Joe's call:
  - an AppArmor profile granting `userns` to the linuxbrew `bwrap` path,
    mirroring the distro's own `bwrap` profile;
  - or check codex's docs for a Linux sandbox that does not need user
    namespaces. Read the docs first; don't guess a config key.
  - Relaxing `kernel.apparmor_restrict_unprivileged_userns` system-wide works
    but widens attack surface for every process. Not recommended.
- **`userns-ok`** → Claude Code's own sandbox is what blocks the nested
  namespace. Check Claude Code's sandbox settings docs for a way to exclude
  `codex` from Claude's sandbox. Codex then runs under its *own* sandbox,
  which is the "sandbox, don't bypass" posture. That is a `settings.json`
  change: self-modification, so Joe applies it.

Then re-run the smoke test from step 2.

### Step 4 — F3: give headless agy a read-only allowlist (needs docs, then Joe)

The error points at `permissions.allow` with `command(<target>)` rules in
Antigravity's `settings.json` (`~/.gemini/antigravity-cli/settings.json` per
`install-settings.sh:305`).

1. Read Antigravity's docs for the exact rule grammar. Don't infer it from the
   error message alone.
2. Propose a **read-only** list: `git log`, `git show`, `git diff`,
   `git status`, `ls`, `cat`, `rg`, `grep`, `sed -n`, `wc`, `head`, `tail`.
   Nothing that writes, deletes, or reaches the network.
3. Decide with Joe whether `install-settings.sh antigravity` should merge it,
   replacing the current "not wired here" line, or whether it stays a
   documented manual step. Wiring it is the portable answer; it also changes
   the installer's contract for every machine.

### Step 5 — Cursor `agent`

Untested. Run the step 2 smoke test once and record the result in the
playbook's host table. If it fails, add its exact error to step 2's list.

### Step 6 — Ship

CI matrix, then `/ship` for the in-repo steps (1, 2). Steps 3–4 hand Joe
pasteable commands. A changelog entry is proposed at the end and not written
until approved.

---

## 4. Gates

- No full-bypass flags on any delegate, including as a "temporary" fix.
- Host changes (AppArmor, sysctl, `~/.claude/settings.json`, Antigravity
  settings, any installer run) are Joe's to apply.
- Changelog: propose, never write unapproved.
