# Plan — make the cross-vendor delegates actually run

**Status: done (2026-10-10).** Cursor's own sandbox is deliberately left off (see step 3's closing note). All three vendors (codex, agy, Cursor) now return a verdict from a Claude Code session on this box. Written 2026-10-05 by Claude (Opus 5.5).
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

**Result, 2026-10-05: `userns-blocked`.** Joe ran the probe in a plain
terminal: `unshare: write failed /proc/self/uid_map: Operation not permitted`.
So the cause is **host policy, not Claude's sandbox nesting**. Ubuntu exempts
its own `/usr/bin/bwrap` with an AppArmor profile, but codex picks up
linuxbrew's `bwrap`, which has none.

**Chosen fix:** a profile for the linuxbrew binary only. AppArmor attaches by
the resolved path, so it targets the Cellar path, not the
`/home/linuxbrew/.linuxbrew/bin/bwrap` symlink. Joe applies it, since it needs
`sudo`:

```sh
sudo tee /etc/apparmor.d/bwrap-linuxbrew >/dev/null <<'EOF'
abi <abi/4.0>,
include <tunables/global>

profile bwrap-linuxbrew /home/linuxbrew/.linuxbrew/Cellar/bubblewrap/*/bin/bwrap flags=(unconfined) {
  userns,
  include if exists <local/bwrap-linuxbrew>
}
EOF
sudo apparmor_parser -r /etc/apparmor.d/bwrap-linuxbrew
```

- **Touches:** that one binary. The system-wide restriction stays on.
- **Undo:** `sudo apparmor_parser -R /etc/apparmor.d/bwrap-linuxbrew && sudo rm /etc/apparmor.d/bwrap-linuxbrew`
- **Check:** `bwrap --unshare-user --ro-bind / / true && echo ok`, then the
  codex smoke test from step 2.
- **Unverified:** that codex uses `bwrap` from `PATH` rather than a copy it
  ships with. If the check passes but codex still prints
  `bwrap: setting up uid map`, point the profile at codex's own `bwrap` path.
- **Portability:** this is a per-machine fix, not an installer change. Any
  Ubuntu 24.04+ host that gets `bwrap` from linuxbrew will hit the same wall.
  The playbook's F2 bullet already tells a session to drop codex and hand the
  user the host fix; a later pass could name this profile there.

**Applied and verified 2026-10-10.** The linuxbrew-only profile above was
replaced by one that covers both copies, because it was unclear which `bwrap`
codex runs (recent codex prefers `/usr/bin/bwrap` when present, per
openai/codex#14963). Joe ran this over SSH, since `sudo` needs a password,
which a `!` command can't supply:

```sh
sudo apt-get install -y bubblewrap
sudo tee /etc/apparmor.d/bwrap-codex >/dev/null <<'EOF'
abi <abi/4.0>,
include <tunables/global>

profile bwrap-system /usr/bin/bwrap flags=(unconfined) {
  userns,
}

profile bwrap-linuxbrew /home/linuxbrew/.linuxbrew/Cellar/bubblewrap/*/bin/bwrap flags=(unconfined) {
  userns,
}
EOF
sudo apparmor_parser -r /etc/apparmor.d/bwrap-codex
```

Undo: `sudo apparmor_parser -R /etc/apparmor.d/bwrap-codex && sudo rm
/etc/apparmor.d/bwrap-codex`.

Result: both `bwrap` copies pass `--unshare-user` **from inside Claude Code's
sandbox**, so Claude's sandbox does not block the nested namespace. The codex
smoke test, `codex exec --skip-git-repo-check --sandbox workspace-write --cd
<ctx>`, ran `git log -1 --oneline` in the repo with network on, wrote the right
commit to `agents/codex.md`, and left the repo clean.

**Cursor's `--sandbox enabled` still fails** with the same AppArmor message, so
it doesn't use either `bwrap`. Its troubleshooting docs
(cursor.com/docs/agent/terminal) are the next stop if enforced read-only for
Cursor is ever wanted. Until then the non-sandbox reviewer form in the playbook
works.

**Closed 2026-10-10: Cursor's sandbox is not fixed on the host.** Cursor's
official fix is a `cursor-sandbox-apparmor` package whose profile targets the
desktop app (`/usr/share/cursor/...`). This box has only the standalone CLI,
whose sandbox binary is `~/.local/share/cursor-agent/versions/*/cursorsandbox`.
A `userns` profile on that path was drafted and **not applied**. The path is
user-writable, so the exemption would extend to any process running as Joe,
which is exactly what Ubuntu's restriction exists to deny, and all it would buy
is enforced read-only for one optional vendor. The non-sandbox form stays the
documented one, and no install ever needs a host AppArmor change.

The same reasoning applies to the linuxbrew half of `/etc/apparmor.d/bwrap-codex`
above, because `/home/linuxbrew/...` is not root-owned. Recent codex prefers
`/usr/bin/bwrap`, which is now installed, so that profile is probably
unnecessary. Whether codex keeps working without it is untested. The playbook
now says to exempt only root-owned paths.

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

**Done 2026-10-08.** Docs read:
[Antigravity permissions](https://antigravity.google/docs/permissions/).
The grammar is `action(target)` in `allow`/`ask`/`deny` arrays, with precedence
deny > ask > allow. `command()` matches by token prefix (`regex:` for anchored
per-token regexes). A line with redirection, substitution or similar must match
exactly. Headless runs honour `settings.json` permissions since agy 1.1.5 (from
`agy changelog`); this machine has 1.2.17. Upstream issue
[#548](https://github.com/google-antigravity/antigravity-cli/issues/548)
reports headless ignoring `permissions.allow` on Windows. It is still open, and
untested here.

Decision taken (Joe asked for steps 4–5 to be done): **wire it**.
`settings-permissions.antigravity.snippet.json` holds the list, and
`install-settings.sh antigravity` unions it in through the same
`merge_perms_json` as Cursor. `uninstall.sh antigravity` subtracts it through
`strip_permissions_json`. A `test.sh` case checks that the user's rules and
other settings survive, that a re-run is idempotent, that uninstall takes back
only ours, and that nothing writing or executing rides in.

The list changed from the draft above. `rg` is out (`--pre` runs a program),
`sed -n` is out (`-i` writes), `find` was never in (`-exec`/`-delete`).
`git blame`, `git rev-parse` and `git ls-files` were added.

- **Known gap:** `git log|show|diff --output=<file>` writes a file, and the
  token prefix covers it. A per-token `regex:` deny might close it, but its
  matching against extra tokens isn't documented well enough to rely on
  without a live test. Recorded rather than guessed.
- **Not yet verified live:** applying it means running
  `install-settings.sh antigravity`, which is Joe's to run. Then re-run the
  step 2 smoke test with agy.

**Verified 2026-10-10.** Joe ran `./install-settings.sh antigravity` on this
box (`srv1350107`). The first smoke test got through the allowlist, but agy ran
`git log` outside the repo (`fatal: not a git repository`). The form that works
is `agy -p "…" --mode accept-edits --add-dir <repo> --add-dir <ctx-dir>`, with
the working directory named in the prompt. It wrote the right commit to
`agents/agy.md`, and the repo stayed clean. The playbook, `/verify` and
`/improve` now document that form.

### Step 5 — Cursor `agent`

Untested. Run the step 2 smoke test once and record the result in the
playbook's host table. If it fails, add its exact error to step 2's list.

**Result 2026-10-08: fails from inside Claude Code.** `agent -p --trust
--workspace <ctx>` (no `--force`/`--yolo`) exits 1 with
`Error: Authentication required. Please run 'agent login' first, or set
CURSOR_API_KEY environment variable.`, while `agent status` prints
`Logged in (unable to fetch user details)`. The credential exists, but the CLI
can't reach Cursor's API. The likely cause is the network policy of Claude
Code's sandbox (codex and agy reach their APIs from the same shell), but that
is inferred, not tested. The error string is now in the playbook's failure
list. To settle it, Joe runs the same probe in a plain terminal:

```sh
agent -p --trust "reply with the word ok" < /dev/null
```

`ok` means the sandbox is the cause: Cursor can't be a delegate from a
sandboxed Claude session unless its API host is allowed. An auth error means
re-run `agent login`.

**Result 2026-10-10: it was the login, not the sandbox.** Joe's own `!` run
printed the same `Authentication required`. `NO_OPEN_BROWSER=1 agent login`,
which prints a URL to approve from any device, fixed it.

- **`--sandbox enabled` fails on this host:** `Sandbox mode is enabled but not
  available on this system … possibly due to AppArmor configuration`. That is
  the same root cause as codex in step 3.
- **The repo must not be the workspace.** Run as
  `agent -p --trust --workspace <repo>`, it did the task but also wrote
  `tmp-cursor-smoke.txt`, a stray `agents/cursor.md` and a junk directory into
  the primary checkout. Those were removed once their timestamps placed them
  inside that run.
- **Working form:** `agent -p --trust --workspace <ctx-dir> --add-dir <repo>`,
  launched from the context dir. It wrote the right commit to
  `agents/cursor.md`, and the repo stayed clean. Without its sandbox nothing
  *enforces* read-only, so the playbook says to tell it to create no other
  files and to check `git status` afterwards.

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
