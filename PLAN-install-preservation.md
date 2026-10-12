# Plan — keep people's customizations in the files `install.sh` writes

**Status: PLAN ONLY, revision 3 (2026-10-12).** Revision 1 was refuted by a same-family refuter (§15); revision 2 was refuted by a cross-family one (Antigravity, §16). This revision resolves both. No product code yet; Joe asked for the plan
first. Written by Claude (Opus 5.5). Rival drafts from other vendors are diffed
in §13.
**Lives on:** branch `ai/claude-install-preserve`, worktree
`../agent-global-instructions-install-preserve`.

---

## 1. The ask and the decisions already made

Joe: *keep custom writes to the files install.sh writes to, so a re-install
doesn't override things people want. Be smart: (1) detect when the existing file
was written by this installer, so overwriting is safe; (2) detect when the
existing content is already covered by this project, so replacing it is safe.
For anything else, decide how to handle it: ask, override, merge, or other.*

Settled in round 1 (2026-10-11):

| # | Question | Joe's answer |
|---|---|---|
| D1 | Real conflict, nobody can answer (`--yes`, no TTY, an agent via `!`) | **Take the new version, with a backup** |
| D2 | How smart is "already covered" detection | **Deterministic checks plus an optional AI semantic check** |
| D3 | What "merge" means | **Install the new file, then append the previously existing custom content to it** |
| D4 | Rollout | **Plan only for now** |

Settled in round 2 (2026-10-12):

| # | Question | Joe's answer |
|---|---|---|
| D5 | Where merged `~/AGENTS.md` (and `~/.codex/AGENTS.md`) customizations go | **Into `extras.local.md`**, then re-render |
| D6 | Merge for role files | **None.** Replace with backup, keep, or pin only |
| D7 | Can an AI "covered" verdict skip the prompt | **No, advisory only** |
| D8 | The plan file | **Commit on the branch, no PR** |

## 2. What install.sh writes today, and how it is protected

Read from the code at `423c48d`.

| Class | Paths | Writer | Protection today |
|---|---|---|---|
| Whole-file render | `~/AGENTS.md` | `customize.sh:561` → `render_to` (`:496`) | Skips if identical; otherwise `.bak.*` (5 newest kept), then overwrites |
| Pointer file | `~/.claude/CLAUDE.md` | `customize.sh:564-576` | Rewritten only when the `@~/AGENTS.md` import is missing; content below the import survives. Already safe. |
| Pointer symlink | `~/.codex/AGENTS.md` | `customize.sh:578-594` | A differing real file is backed up, then replaced by a symlink |
| Verbatim copy, backed up | Claude/Cursor commands; Codex skills; hook scripts | `install-commands.sh:273,311`; `install-hooks.sh:60` | A differing file is backed up, then overwritten |
| **Verbatim copy, NO backup** | role files (all four tools) | `install-roles.sh:53-54` | **Silently overwritten.** `uninstall.sh:168-171` says so. |
| **Verbatim copy, NO backup** | `~/.ai/{orchestration,agent-teams,quality-workflows,web-preview}.md` | `customize.sh:717-721` | **Silently overwritten**, and **deleted outright** when a section is toggled off (`:723`) |
| **Verbatim copy, NO backup** | `~/.ai/worktree-sweep.sh`, `~/.local/bin/lm`, `~/.local/bin/timeout` | `install-hooks.sh:303-305`; `customize.sh:610-613`; `install_timeout_shim` (`:400`) | **Silently overwritten** |
| Split ownership | `~/.ai/model-routing.md` | `customize.sh:660-703` | Generated block kept by marker; a file without markers goes to one fixed `.unmarked.bak.md` (overwritten each time) |
| **Generated, NO backup** | Antigravity `*.ag.sh` hook wrappers | `install-hooks.sh:265-269` | Overwritten every run with no `cmp`; no git history (rev 3, A4) |
| **Deletions, NO backup** | Codex skills (design group off: `install-commands.sh:305-306`; retired with the GENERATED marker: `:317-324`); `~/.codex/prompts/*.md` with the marker (`:325-328`); the timeout shim (`customize.sh:396`); `lm` when `INC_LOCAL_MODELS=n` (`:631-632`) | various | Removed outright (rev 3, A4) |
| **Overwrite of a foreign binary** | `~/.local/bin/lm` | `customize.sh:610-613` | No marker check, unlike the timeout shim at `:392-393` (rev 3, A4) |
| Other unbacked writes | Cursor hooks `.version` (`install-hooks.sh:228`); hook-script backups are never rotated (`install-hooks.sh:61`) | — | Rev 3, A4 |
| Seed-only | `~/.claude/loop.md`, `~/.claude/CHANGELOG.md`, `~/.ai/memory-os` config | `customize.sh:732-740`; `setup-memory-os.sh:36` | Never overwritten. Already safe. |
| Machine data | `~/.ai/clis`, `~/.ai/local-models` | `customize.sh:618-656` | Regenerated each run. Correct: nobody hand-edits these. |
| Key-merged JSON | `~/.claude/settings.json`, `~/.cursor/cli-config.json`, the Antigravity settings, hook JSON for each tool | `install-settings.sh:86-110`; `install-hooks.sh:75-93` | Union merge, so user keys survive; backed up when changed |
| Managed TOML block | `~/.codex/config.toml` | `install-settings.sh:249-306` | Marker block; the user's own top-level keys win |
| Skill symlinks | `~/.{claude,codex,cursor}/skills/*` | `install-commands.sh:170` | Ownership checked (`is_our_skill_link`). Already safe. |

**Gaps this plan has to close, beyond the ask itself:**

- **G1 — No backup at all** for roles, playbooks, the sweep CLI, `lm`, and the timeout shim.
- **G2 — The original is eventually lost.** Five-backup rotation means a user's
  pre-install `~/AGENTS.md` or `~/.codex/AGENTS.md` is pruned after five
  differing re-renders. So `uninstall.sh` "restore the newest backup" restores
  one of *our* old renders, not their original.
- **G3 — The core gap: "ours, stale" and "theirs, edited" look the same.** Every
  writer compares only against the *new* source (`cmp -s new dest`). A
  difference could be an older version this installer wrote (safe to replace)
  or a hand edit (not safe), and both get the same treatment.
- **G5 — `--yes` reaches only two of the six layers.** `install.sh:43,55`
  forwards it to `customize.sh` and `setup-memory-os.sh` only. Commands, roles,
  hooks and settings have no notion of attended vs unattended. (Found by the
  Codex rival draft, verified.)
- **G6 — Deletions are blind too.** Retired command names are removed after a
  backup (`install-commands.sh:223-228`), and a playbook whose section is toggled
  off is deleted with no backup at all (`customize.sh:723`). A user's customized
  copy is treated like a stale one either way.
- **G4 — Retiring a permission is blind to provenance.**
  `merge_perms_json`'s `$gone` subtraction (`install-settings.sh:97-100`)
  removes a retired rule even when the user added that exact rule themselves.

## 3. The core idea: an install ledger

Every write goes through one shared helper that records **what it wrote**.
Knowing what we last wrote is the only way to tell an old version of ours from
someone's edit.

```
~/.ai/install-state/
  manifest.tsv     path-id <TAB> path <TAB> class <TAB> canonical-blob <TAB> block-blob|- <TAB> kept-blob|- <TAB> kept-against|- <TAB> source <TAB> repo-commit <TAB> date
  settings.tsv     file <TAB> jq-path <TAB> value <TAB> added|declined  — per-entry provenance for JSON/TOML (A3)
  lock/            mkdir lock holding pid + host + start time (A1)
  base/<enc-path>  exact bytes we last wrote — the merge base, and proof of "ours"
  orig/<enc-path>  the first NON-ours content found at a path — kept forever, never rotated
  preserved/<enc-path>.<date>  every custom version we replaced — never rotated (fixes G2)
  last-run.json    machine-readable report of the last run (see §8)
  pins             paths the user owns outright; the installer never writes them
```

- **Identity is a git blob id** (`git hash-object --no-filters`). It's portable
  (same on macOS and Linux, no `sha256sum` vs `shasum` split), and it's the same
  id git already stores for every version of every committed source file. That
  makes "was this ever shipped?" a set lookup (§4, step 4).
- **`base/` stores bytes, not only hashes,** so a later step can compute exactly
  which lines the user added (the input to the append-merge, §6). The cost is
  small: a few hundred KB of text.
- **`<enc-path>` is replaced by a path-id:** the first 16 hex characters of the
  path's blob id, with the real path kept in `manifest.tsv`. Percent-encoding
  could exceed the 255-byte `NAME_MAX` on deep paths (A8).
- **Fallback when git or history is missing** (a tarball install, a shallow
  clone): `sha256sum`/`shasum -a 256` for identity, and step 5 (§4) is skipped,
  with a one-line note in the report. The ledger still works; only the
  migration convenience is lost.
- **One run, one decision pass, across six processes.** `install.sh` runs six
  separate scripts (`install.sh:43-58`), so "classify everything, then ask once"
  needs a shared run dir: `install.sh` exports `AIGI_RUN_DIR` and
  `AIGI_UNATTENDED`. Phase 1 runs every layer with `AIGI_PHASE=plan` (classify
  only, append rows to `$AIGI_RUN_DIR/plan.tsv`). One prompt pass then writes
  `decisions.tsv`, and phase 2 runs each layer with `AIGI_PHASE=apply`. A layer
  run on its own (no `AIGI_RUN_DIR`) does both phases itself. This fixes G5:
  every layer reads the same unattended flag.
- **One library, `lib/preserve.sh`, sourced by every installer.** It replaces
  the five copy-pasted `backup_file`/`backup_keep5` helpers. Writers stop
  calling `cp`/`mv` and call `preserve_write <class> <src-or-tmp> <dest>`.

## 4. Classification: the ladder each write climbs

**Rule above the ladder (R3, R11): every overwrite or delete of a file whose
bytes differ from the new version saves a copy to `preserved/` first, whatever
rung it matched.** A wrong "safe" verdict then costs a recovery, never data.

The first rung that matches decides the outcome. Steps 1–6 are deterministic;
step 7 is the optional AI check (D2).

| # | Verdict | Test | Action |
|---|---|---|---|
| 1 | **PINNED** | path is in `pins` | Don't write. Report if upstream changed. |
| 2 | **ABSENT** | no file | Write it and record it. |
| 3 | **CURRENT** | blob(dest) == blob(new) | No-op. Record it if no record exists (adopts pre-ledger installs). |
| 4 | **OURS** | a manifest record exists AND blob(canonical part of dest) == the recorded blob | Overwrite, no prompt. Refresh `base/`. **If a record exists and this rung fails, skip straight to 8.** Someone changed the file after we wrote it, which is exactly G3, so rungs 5 and 6 never get a say (R2). |
| 5 | **SHIPPED** *(bootstrap only: no manifest record)* | blob(dest) ∈ every blob the source ever had (`git log --all -m --format= --raw --no-abbrev -- <src>`). For `~/AGENTS.md`: blob(dest) ∈ renders of the last 30 commits touching `template.md`/`customize.sh`, re-rendered with today's personal layers (R1, R6) | Overwrite, no prompt. **Never matched against `.bak.*` files**, which hold user content (R1). |
| 6 | ~~COVERED~~ **removed in rev 3 (A2)** | Without a base, "upstream added lines" and "you deleted lines" are the same diff, so no deterministic test can tell them apart | — Falls through to the AI check, then CUSTOM. Unattended, D1 still replaces it, with a `preserved/` copy. |
| 7 | **COVERED-AI** *(optional)* | the AI judge says the added lines' intent is already expressed in the new version (§7) | Treated as CUSTOM, with the verdict shown and a recommended action. **Never** a silent overwrite on its own. |
| 7b | **KEPT** | dest blob == the blob the user chose `[k]` for, and the new version is the one they kept it against | Don't write; re-report "you kept this". When upstream changes again, it's CUSTOM again, and unattended runs follow D1 (A5) |
| 8 | **CUSTOM** | none of the above | Resolve per §5. |

"Lines the user added" is the line diff `base → dest` when a base exists, and
the line diff `new → dest` when one doesn't (pre-ledger). Only trailing
whitespace is ignored, because indentation carries meaning in YAML and in
Markdown code blocks (R3). Preserved-block marker lines are never counted as
added lines (R4). Lines the user *deleted* from our version are a
customization too. The COVERED test can't see them, so a file with deletions is
never COVERED. It goes to CUSTOM, and the prompt says "you removed N lines we
ship."

**Generated ports** (`commands/codex`, `commands/cursor`, `roles/{codex,cursor,antigravity}`)
aren't committed, so step 5 has no history for them. Two ways to fix that,
preferred first: (a) render each port at the historical commits in a temporary
dir on demand, only when a port is CUSTOM and has no manifest record (a one-time
migration cost); or (b) skip step 5 for ports and rely on steps 4 and 6. Pick at
build time, after measuring (a).

**Deletions climb the same ladder (G6).** Removing a retired command, a
retired hook script, or a toggled-off playbook is a write too. OURS, SHIPPED, or
COVERED → delete (with a backup in `preserved/`). CUSTOM → prompt, or
unattended: back up to `preserved/`, then delete, and report it.

**`~/AGENTS.md`** is a *personal* render (template + `my-context.env` +
`extras.local.md`), so its historical blobs aren't in git either. Its steps 4–6
are: the manifest blob (4); a bounded one-time re-render of recent historical
commits with today's personal layers (5); and no rung 6, because the
subsequence test still treats upstream additions as user deletions (R6). If
the personal layers changed since that render, the file falls to CUSTOM. That's
noisy but safe, given the `preserved/` rule. **Its `.bak.*` files are never
evidence of ownership** (R1). The oldest surviving `~/AGENTS.md.bak.*` is copied
to `orig/` once at bootstrap, as the best available pre-install original (R1
knock-on).

## 5. Resolving a CUSTOM file

### Interactive (a TTY, no `--yes`)

The run classifies everything first and writes nothing. Then it asks once per
CUSTOM file, after a summary of how many files are OURS/SHIPPED/COVERED and will
update silently:

```
~/.claude/agents/refuter.md — you've changed this file (+6 lines, −1 line vs what we installed)
  AI check: NOT covered — "always cite file:line" isn't in the new version   [only if enabled]
  [r] replace with the new version (yours saved to ~/.ai/install-state/preserved/…)
  [a] replace, then append your added lines below a preserved marker      ← recommended when AI says not covered
  [k] keep yours this time (the new version is saved as refuter.md.aigi-new)
  [p] pin: keep yours, never ask again
  [d] show the diff        [R/A/K] same answer for every remaining file
  [x] abort — nothing has been written yet
```

- The default (Enter) is `[r]`, so a session that's just mashing Enter gets the
  same result as an unattended one (D1). The recommendation marker moves to `[a]`
  when the AI check says the added content isn't covered.
- `[a]` appears only where the append-merge is safe (§6). Elsewhere the menu
  shows `[a] unavailable for shell scripts — see diff` instead of silently
  dropping the option.

### Unattended (`--yes`, no TTY, or an agent)

Per D1: **replace with the new version, after saving a backup**, and:

- **The backup goes to `preserved/` and is never rotated** (fixes G2), unlike
  routine `.bak.*` files.
- **The run's last lines list every CUSTOM file that was replaced,** with the
  exact command that recovers it:
  `./install.sh --resolve ~/.claude/agents/refuter.md --append`.
- **`last-run.json` records the same list,** so an agent that ran the install
  can read the result and act without parsing human text (§8).
- **What counts as unattended:** `--yes`, no readable `/dev/tty`, or
  `AIGI_UNATTENDED=1`. An agent should pass `--yes` explicitly rather than rely
  on TTY detection.
- **Overriding D1 per run or per machine:** `--on-conflict=replace|append|keep`,
  or `INSTALL_ON_CONFLICT=` in `my-context.env`. `replace` is the default.

### Later: `install.sh --resolve`

`./install.sh --resolve [<path>…] [--replace|--append|--keep|--pin]` re-applies a
decision to files a previous run replaced. The inputs come from `preserved/`
and `last-run.json`, so this works even when the person isn't at a terminal
during the install. With no path given, it walks every unresolved entry
interactively.

## 6. The append-merge (D3), and where it is NOT safe

**Mechanics, where it's safe:**

1. Write the new version.
2. Compute the user's added lines as contiguous blocks (§4), in their original order.
3. Append them inside an ownership marker in the file's comment syntax:
   ```
   <!-- aigi:preserved begin — your additions from before the 2026-10-11 install; edit freely -->
   …your lines…
   <!-- aigi:preserved end -->
   ```
4. **From then on the preserved block is user-owned territory**, the same rule
   that already protects content below the import line in `~/.claude/CLAUDE.md`.
   Later installs carry the block forward byte-for-byte and never append it
   twice. A run that finds its own markers damaged (not exactly one begin before
   one end, the same test `model-routing.md` uses at `customize.sh:671-674`)
   treats the file as CUSTOM instead of guessing.
5. Record the **canonical blob** (the file minus the block) and the **block
   blob** in separate manifest columns (§3). Rung 4 compares the canonical part
   only, so editing inside the block never makes the file CUSTOM (R4/A7).

**Where appending is unsafe, and what happens there instead:**

| File class | Why appending breaks it | What to do instead |
|---|---|---|
| `~/AGENTS.md` (rendered) | The next render wipes anything appended to the output | **Append to `extras.local.md` in the checkout instead.** It's the render's own sanctioned append point (`customize.sh:186`) and it's gitignored. Then re-render. The additions now survive every future install. |
| `~/.codex/AGENTS.md` (a real file about to become a symlink) | After the switch there's no separate file to append to: it *is* `~/AGENTS.md` | Same as above: the custom lines go to `extras.local.md`, so Codex still sees them through the symlink |
| **Role files** (all four tools) | The body must **open and close** with the `**Reminder:**` line, enforced at `render-roles.sh:117-119` because recency is what keeps a long agent run on its rules. A plain append pushes that line off the end. **No merge for roles** (Joe, D6). Only `[r]` replace with backup, `[k]` keep, or `[p]` pin, plus a diff. The `[a]` row shows "unavailable for role files — the reminder must stay last". |
| Markdown with YAML frontmatter (commands, skills) | A changed `model:`/`tools:` value can't be appended: a second frontmatter block is invalid | Body additions append as above. **Frontmatter changes** are merged key by key (the user's value wins for a key they changed; new keys from upstream are added). If that can't be done cleanly, the `[a]` option is withdrawn for that file. |
| Shell scripts (hooks, `worktree-sweep.sh`, `lm`, `timeout`) | Code appended after `exec`/`exit` is dead, and code before it runs twice | No append. `[r]` / `[k]` / `[p]`, plus a diff. The report suggests upstreaming the change (or, for hooks, a per-user hook entry pointing at their own script). |
| Key-merged JSON / managed TOML | Appended text is a parse error | Already field-merged today; "merge" there means the existing union. Add provenance instead (§9) to close G4. |
| `~/.ai/model-routing.md` (split ownership) | Each install splices everything outside the generated markers from the repo copy, so an appended block is discarded (A10) | No `[a]`. Replace (with a `preserved/` copy), keep, or pin |
| Seed-only, machine data, symlinks | — | Unchanged. They already behave correctly. |

**A known risk of appending:** a preserved block can contradict the new version.
The user kept "always X", and upstream now says "never X". Appending preserves
both, and an agent then reads conflicting rules. The AI check (§7) is the place
to catch this. With it off, the deterministic fallback flags any preserved line
that shares a bolded rule headline with a changed line in the new version.

## 7. The AI semantic check: what it may and may not do

- **Opt-in:** `INSTALL_AI_CHECK=off|local|any` in `my-context.env`, default
  `off`. `local` uses only the `lm` shim. `any` may use a CLI from `~/.ai/clis`
  (excluding the tool running the install).
- **Markdown only.** Shell scripts, JSON/TOML, symlinks and registries never go
  to the model. "Is this script change covered?" is not a question a one-shot
  judge answers reliably, and those classes can't append anyway.
- **It runs only on files that are CUSTOM after steps 1–6,** so it costs one
  call per genuinely customized file, not one per installed file.
- **Input:** the user's added and removed lines plus the new version of the file.
  Never the whole home directory.
- **Output:** strict JSON, `{"covered": bool, "uncovered": [lines], "contradicts": [{"yours":…, "new":…}], "reason": "…"}`,
  validated with `jq`. Anything malformed counts as "no verdict".
- **What it may do:** set the interactive recommendation; add its reasoning
  to the prompt, the summary, and `last-run.json`; flag contradictions after an append.
- **What it may NOT do:** authorise a write without a backup; promote a file to
  COVERED and skip the prompt; block the install. Every AI verdict is advice on
  top of the deterministic result. The backup always exists either way, so a
  wrong verdict is recoverable.
- **Bounds:** `timeout 60` per file and a 5-minute budget per run. A timeout,
  an offline machine, or a missing CLI each produces `"ai": "skipped: <reason>"`
  and the run carries on.
- **Privacy:** under `any`, the user's instruction text goes to an external
  vendor. The first run with `any` prints that once. `local` is the
  recommended setting where `~/.ai/local-models` exists.
- **Tests:** `AIGI_AI_CHECK_CMD` points at a stub script, so `test.sh` runs
  deterministically with no network.

## 8. The three lenses

- **UX (the person installing):** one batched set of questions after a silent
  classification pass, never a prompt per file; Enter does the safe thing; every
  replaced edit is named with a one-line recovery command; `pins` gives a
  permanent "this file is mine." **Trade-off:** D1 means an unattended run still
  takes edited files out of the live path. The plan makes that loud and
  recoverable, not silent.
- **DX (maintaining this repo):** one `lib/preserve.sh` instead of five
  `backup_file` copies; every writer calls one function, so a new installed file
  is protected by default rather than by remembering to add a `cmp`;
  `./install.sh --plan` prints each path's classification and writes nothing,
  which is also the debugging tool.
- **AX (agents run this installer, usually through a `!` line Joe pastes):** an
  agent can't answer a TTY prompt, so the non-interactive path is a primary
  path, not a fallback. `last-run.json` (`{path, class, verdict, action,
  preserved_at, ai}` per file), `--plan` for a dry run, `--resolve` with
  explicit flags for follow-up, and **exit 0 on success, even when custom files
  were replaced** (A9). Replaced files are reported in `last-run.json` and the
  summary, not through the exit code, because `set -e` callers treat any
  non-zero code as a failure. The rendered instructions get a short pointer telling an
  agent to read `~/.ai/install-state/last-run.json` after an install, rather
  than scraping output.

## 9. `uninstall.sh`, the JSON provenance gap, and doc drift

- **Docs that this change makes false:** `README.md:84-87` and
  `docs/GUIDE.md:22-27` both say a hand edit to a rendered file is simply
  overwritten. After this change it's detected, backed up, and offered actions.
  The guidance stays "prefer the layers" (`template.md`, `my-context.env`,
  `extras.local.md`), and the docs have to describe the new safety net
  accurately.
- **In-checkout ports** (`commands/cursor/*.md`) are pruned by basename with no
  marker (`render-commands.sh:150`, via `prune_dir`). They're gitignored and
  generated, so out of scope here, but they're the same bug class. Noted, not
  planned.

- **Files:** remove a path only when it's OURS (its blob matches the manifest).
  A path with a preserved block or a CUSTOM verdict is backed up into
  `preserved/` before removal, as `remove_roles_dir` already tries to do. Where
  `orig/` holds a pre-install original, **restore that**, not the newest `.bak.*`
  (fixes G2).
- **JSON/TOML (G4):** record in the manifest each permission rule and hook entry
  *this installer added* (`settings:<file>:<jq-path>:<value>`). The retired-rule
  subtraction and the uninstaller then remove only entries we added. A rule that
  was already present before we first installed is the user's, and survives.
- **The state dir itself** (`~/.ai/install-state/`) is left in place by
  uninstall, the same as `~/.ai/clis`. It's the user's recovery store; an
  `--purge` flag removes it.

## 10. Migration: machines installed before the ledger existed

The first run on an existing install has no manifest. It is a **bootstrap run**:

1. Classify with steps 3, 5, and 6 only (no manifest yet, so step 4 can't match).
   On a typical install almost everything is CURRENT or SHIPPED, because it came
   straight from some past commit of this repo.
2. A file that's CURRENT or SHIPPED is adopted: a manifest row plus `base/` is written.
3. A file that's CUSTOM goes through §5 as normal. Its pre-existing `.bak.*`
   files are listed in the prompt ("you also have 3 older backups") rather than
   ignored.
4. A real pre-existing file at a pointer path is copied to `orig/` once, so the
   uninstaller can restore it (G2).

**Pre-ledger renders of `~/AGENTS.md`** have no history to match. Step 6 handles
them: lines present in the new render or `extras.local.md` are covered.
Anything else, such as the hand-added Tailscale section that
`global-claudemd-divergence` recalls happening, is CUSTOM, and the `[a]` path
moves it into `extras.local.md`. That is exactly where it should have lived.

## 11. Tests and evals

- **`test.sh`:** a fixture `$HOME` in a temp dir, one case per verdict
  (PINNED…CUSTOM) per file class; append-merge idempotence (two installs append
  once); damaged-marker → CUSTOM; frontmatter key merge; `--yes` replaces and
  writes `preserved/` and `last-run.json`; `--plan` writes nothing (checked by
  listing the fixture tree before and after); an uninstall restores `orig/`; G4
  (a user-added copy of a retired rule survives); the AI stub's `covered`,
  `uncovered`, and malformed paths. All of it runs on bash 3.2 (the existing CI matrix).
- **`evals/behaviours.md`:** one new entry for the agent-facing pointer ("read
  `last-run.json` after an install"), with its anchor in the template.
  `test.sh` pins its headline.
- **shellcheck** covers `lib/preserve.sh` (extend the glob in CI and in `AGENTS.md`).

## 12. What would prove this plan wrong

- **Step 5 misses more than it catches.** If a bootstrap run on this machine
  classifies more than a handful of known-pristine installed files as CUSTOM,
  blob matching against history is the wrong tool. The likely cause is the
  install pipeline transforming files (e.g. `render-roles.sh` output, permission
  bits, line endings). **Check before building:** run a read-only spike that
  classifies today's `~` against git history.
  **Spike run 2026-10-11 (read-only):** 35 installed files checked (10 roles, 7
  commands, 12 hooks, 4 playbooks, sweep CLI, `lm`); all 35 CURRENT, byte-identical
  to source. So the copy pipeline doesn't transform files. Weak evidence: this
  machine was freshly installed, so the SHIPPED rung wasn't exercised, and a
  machine a few releases behind is still the real test.
- **People hand-edit `~/AGENTS.md` more than anything else.** If so, the
  `extras.local.md` redirect is the whole feature, and the general machinery is
  overbuilt. The spike's CUSTOM list answers this too.
- **The appended blocks pile up into contradictions.** If the contradiction
  flag (§6) fires on most appends in testing, append-by-default is the wrong
  recommendation, and `[r]` + the `preserved/` copy should be the only
  suggestion.
- **Ledger drift.** If anything else writes these paths (a tool's own `/memory`
  writes, another installer), every such write becomes CUSTOM forever, and the
  prompts become noise. `~/.claude/CLAUDE.md` is known to be written by Claude
  Code, which is why it stays in its own region-preserving class and is not
  ledger-managed.

**Done-condition for the build (later):** `./install.sh --plan` on this
machine classifies every installed path; a second `./install.sh --yes` writes
nothing (all CURRENT); every fixture case in §11 passes in `test.sh` on bash
3.2 and Linux; shellcheck is clean.

## 13. Rival drafts: what came back and how they differ

Both drafts got the same brief independently, with the round-1 decisions as
constraints and neither one able to see this plan. The brief and the Codex draft
are in `~/.ai-context/install-preserve-20261011/`.

- **Codex (GPT-5.6 Terra, xhigh): returned a full draft.** That's a T2
  cross-family check. No non-Anthropic T1 model is reachable from this machine
  (`~/.ai/model-routing.md`).
- **Antigravity (Gemini 3.8 Flash): no draft.** Run 1 had its `read_file` tool
  auto-denied in headless mode. Run 2 (inline tier, source pasted in, told it
  had no tools) still called a shell tool, was denied, and exited 0 with empty
  output. Dropped for the session.

**Where the two drafts agree.** They converged independently, which is the
strongest signal available this early:
- A machine-local ownership ledger is the missing piece. Both drafts name the
  same root cause (G3).
- One shared preservation module, with uniform backups. Both independently found
  the unbacked role overwrite at `install-roles.sh:53`.
- One batched decision pass, not prompts spread across six layers.
- Append only for Markdown, inside a delimited block that later runs carry
  forward. Never for shell scripts, JSON/TOML, symlinks, or registries.
- The AI check is opt-in and advisory, never removes the backup requirement, and
  treats a timeout or bad output as "no verdict".
- Uninstall restores the original first-displaced baseline, not the newest
  `.bak.*`. JSON/TOML removal relies on per-entry provenance.

**Adopted from Codex** (each verified against the code first): G5 (`--yes` not
forwarded), the two-phase run across six processes (§3), deletions on the same
ladder (G6), `AIGI_UNATTENDED=1`, `[x] abort`, Markdown-only AI checks, the
`~/.codex/AGENTS.md` symlink case, the doc drift in `README.md` and `GUIDE.md`,
and the role-reminder constraint.

**Divergences.** Three are surfaced to Joe in §14, not silently resolved:

| # | Topic | This plan | Codex | Status |
|---|---|---|---|---|
| V1 | Where `~/AGENTS.md` customizations go on merge | Move them into `extras.local.md`, the render's own personal layer, and re-render | Append inside a delimited tail in `~/AGENTS.md` and carry the tail through every future render | **Decided D5: this plan** |
| V2 | Role files | Insert the preserved block just before the closing reminder line | No append for roles at all: replace + backup, or keep | **Decided D6: Codex** |
| V3 | Can an AI "covered" verdict skip the prompt | Never. It only sets the recommendation. | On legacy Markdown, yes (still backed up) | **Decided D7: this plan** |
| V4 | Recognizing old-but-pristine installs | Git blob ids against every shipped version (step 5) | Exact candidate, markers, links, sentinels only | **Decided: this plan.** Without step 5, the first upgrade turns every stale-but-pristine file into a conflict, so prompts interactively and noise backups unattended. Codex's SHA-256 path is kept as the fallback when there's no git history. |
| V5 | Hash | Git blob id | SHA-256 with a `cksum` fallback | **Decided: blob id**, because it's what makes V4 a set lookup. SHA-256 is the no-git fallback. |

**Still owed after §14 is answered:** a `refuter` from a different family
(Codex, prompted to break the plan, not improve it) on the reconciled version,
plus a re-run of the §12 spike on a machine a few releases behind.

## 14. Open questions

None blocking. Round 2 was answered on 2026-10-12 (D5–D8, §1). Before any code
is written: the cross-family refuter pass on this reconciled plan (§13), and the
§12 spike re-run on a machine a few releases behind.

## 15. Refuter pass on revision 1 → revision 2

**Who reviewed it:** an in-tool `refuter` (Claude, the same family as the
author). The planned cross-family refuter (Codex) ran out of quota partway
through (`usage limit … try again at Nov 4th, 2026`), and Antigravity was
already dropped (§13). **So this is a same-family check: it tests the reasoning,
not the model's blind spots.** A cross-family refuter is still owed before
building.

**Verdict on revision 1: refuted.** Two findings were reproduced mechanically
(R3, R6). Every finding is accepted. How each one is resolved:

| # | Finding (severity order) | Resolution in revision 2 |
|---|---|---|
| R1 | Rung 5′ matched `~/AGENTS.md.bak.*`, but those hold the *user's* content, so a restored edit was silently overwritten | 5′ deleted. `~/AGENTS.md` SHIPPED = re-render of recent commits with today's layers (§4). The oldest `.bak.*` goes to `orig/` at bootstrap |
| R2 | SHIPPED still applied with a manifest record, so a deliberate revert to an old version was silently overwritten | Rungs 5–6 are **bootstrap-only**. With a record, any mismatch → CUSTOM (§4) |
| R3 | COVERED was a position-blind set test that also applied to scripts. An inserted `exit 0` that disables a hook counted as "covered". Whitespace-only edits were vacuously covered | Order-preserving subsequence test, Markdown only, bootstrap only, trailing whitespace only. **Plus: every overwrite of differing bytes saves to `preserved/`, whatever the rung** (§4) |
| R4 | Preserved block "user-owned" vs a whole-file ledger blob: editing the block → CUSTOM → replaced. Second merges and no-base merges nest markers | The ledger records the blob of the **canonical part** (file minus block) and the block separately. Rung 4 compares the canonical part only. The block is carried verbatim. A later `[a]` appends *inside* the existing block. Marker lines are never "added lines". Damaged markers → CUSTOM, never re-wrapped |
| R5 | `--resolve --append` diffed against the wrong base, so upstream rewording was appended as "your lines" | Each `preserved/` entry stores a triple: the user's version, the base it diverged from, the new version that replaced it. `--resolve` diffs base → user |
| R6 | `~/AGENTS.md` bootstrap came out CUSTOM one template change behind (repro: 843b2f4 vs 423c48d, 9 false "deletions") | Fixed by the historical re-render in rung 5. Rung 6 doesn't apply to `~/AGENTS.md`. Generated ports use option (a), re-rendering at historical commits; option (b) is withdrawn |
| R7 | The `extras.local.md` routing isn't durable: a second checkout or worktree renders without it, and the result reads as OURS → silent loss. No backup of extras, no dedupe, position lost, a hand-written Codex file gets dumped wholesale | Ledger records the **checkout path + blob of `extras.local.md` and `my-context.env`** used for the render. An install whose layers differ from the recorded ones treats `~/AGENTS.md` as CUSTOM (prompt; unattended: proceed, save to `preserved/`, report "rendered without your personal layers from <path>"). `extras.local.md` is snapshotted into `install-state/` whenever it changes. Routed lines go under a dated `## Preserved from ~/AGENTS.md (<date>)` heading, deduped against existing extras. `[a]` is withdrawn when added lines exceed half the file (a wholly custom file → keep/pin/replace only) |
| R8 | Two-phase run: no re-check at apply (TOCTOU), a partial death orphans state, no lock, exit 3 under `set -e` aborts later layers | Apply re-checks blob(dest) against what phase 1 saw; a mismatch → re-classify, never write. `last-run.json` is journaled one row per action, before the action. A `mkdir`-based lock on `install-state/` (portable, atomic) refuses a concurrent run. Layers always exit 0 on success; only `install.sh` computes exit 3, at the very end |
| R9 | Three conflicting "unattended" definitions; `[ -r /dev/tty ]` is true even with no terminal | One helper `aigi_unattended`: `--yes`, or `AIGI_UNATTENDED=1`, or `/dev/tty` **fails to open** (an open test, not `-r`). `install.sh` decides once and exports it. **Behaviour change, flagged:** a no-TTY run without `--yes` today aborts only the global render (`customize.sh:777-779`). Under D1 it now renders. That is the literal reading of D1, and Joe should confirm it before build |
| R10 | Inventory missed: the Antigravity `*.ag.sh` wrappers; Codex skill deletions (design-group off, retired, `~/.codex/prompts`) with no backup; timeout/`lm` removals; `lm` overwriting a foreign binary; user edits outside the `model-routing.md` markers; hook-backup rotation; Cursor `.version` | All added to §2 and routed through `preserve_write`/`preserve_delete`. `lm` gets the timeout shim's marker check (a foreign `lm` → CUSTOM, never replaced unattended). `model-routing.md` is ledgered **outside the markers only**, because `/update-model-routing` owns the inside |
| R11 | "Already safe" rows weren't: any symlink at `~/.claude/CLAUDE.md` or a skill path is replaced; `cp` writes *through* a symlinked dest into a dotfiles target | `preserve_write` rule: a dest that is a symlink not recognized as ours → CUSTOM, never written through, never silently replaced. Its target is recorded in `preserved/`. The `CLAUDE.md` symlink removal is narrowed to links that point at `~/AGENTS.md` (the legacy layout) |
| R12 | Unsupported verification claims: CI is ubuntu-only (no bash 3.2), a shallow checkout disables SHIPPED, "second install writes nothing" is false (`clis`, ports), `--plan` still re-renders ports and seeds `{}` | Add a `macos-latest` CI job (bash 3.2, BSD `diff`/`mktemp`). Tests build a **synthetic fixture repo** with history, so they're independent of checkout depth. Done-condition reworded: "a second `--yes` changes no **ledgered** file" (machine-data files excluded by class). `--plan` renders ports into a temp dir and seeds nothing |
| R13 | G4 can't be closed on pre-ledger machines | Accepted as a stated limitation. At bootstrap, rules present that match our snippet are adopted as ours (so uninstall leaves nothing behind). Exact provenance only applies to rules added after the ledger exists |
| R14 | Minor: `%2F` encoding collides; day-granular `preserved/` names collide; G2 overstated for uninstall; §9 self-contradiction; `--purge` ungated; frontmatter merge undefined without a base; AI `timeout` before the shim exists on macOS; merge-only blobs | Escape `%` → `%25` first. Use `mktemp` suffixes in `preserved/`. §9 reads: "remove when OURS; otherwise save to `preserved/`, then remove". `--purge` asks for a typed confirmation. No frontmatter merge without a base (→ CUSTOM). The AI check calls the repo's `portable-timeout` directly. `git log --all -m` is in rung 5; still to be verified with a fixture merge commit |

**Still unverified** (the refuter couldn't check these either): BSD `diff` on
current macOS lacks GNU `--*-line-format`, so the line splitter must use `awk`
over `diff` normal output or `cmp`-free logic (a portability requirement for
build, not a design gap); what Claude Code does when a `!` command opens
`/dev/tty`; whether Cursor or Antigravity rewrite their own agent files (ledger
drift).

**§12 spike commands** (missing in revision 1): the classification loop used on
2026-10-11 is reproduced here so it can be re-run on an older machine:

```sh
check(){ d=$(git hash-object --no-filters "$2") n=$(git hash-object --no-filters "$1")
  [ "$d" = "$n" ] && { echo "CURRENT  $2"; return; }
  git log --all -m --format= --raw --no-abbrev -- "$1" | awk '{print $3; print $4}' \
    | grep -qx "$d" && echo "SHIPPED  $2" || echo "CUSTOM?  $2"; }
for f in roles/*.md; do check "$f" ~/.claude/agents/"$(basename "$f")"; done   # likewise commands/, hooks/, playbooks/
```

## 16. Cross-family refuter on revision 2 → revision 3

**Who reviewed it:** Antigravity, Gemini 3.8 Flash, running in the newly fixed
headless form (branch `ai/claude-delegate-fixes`). It's a **different family,
but T2**: no non-Anthropic T1 model is reachable from this machine. Cursor was
launched alongside it as an extra voice and hit its free-plan usage limit.
The full report is at
`~/.ai-context/install-preserve-20261011/agents/refuter-agy.md`.

**Verdict on revision 2: refuted** (8 confirmed, 2 plausible). All ten were
checked against the plan and accepted. Two were the author's own edit
failures: §15 claimed §2 and §6 had been updated, and they hadn't been.

| # | Finding | Resolution in revision 3 |
|---|---|---|
| A1 | The bare `mkdir` lock wedges every future run after a kill or OOM | The lock dir holds `pid`, `host`, and start time. A run that finds a lock whose pid is dead on the same host takes it over and says so. A lock older than 2 hours is stale on any host. `install.sh --unlock` removes it explicitly |
| A2 | Rung 6 silently undid user deletions, and contradicted "a file with deletions is never COVERED" | **Rung 6 removed.** Without a base, an upstream addition and a user deletion are the same diff, so no deterministic test can tell them apart. Those files go to CUSTOM, where D1 still replaces them unattended, with a `preserved/` copy |
| A3 | Rules the user deleted from JSON/TOML are re-added on every run by the union merge (`install-settings.sh:101-104`) | `settings.tsv` records each entry we added. On a later run, an entry we added that's now **absent** is marked `declined` and is never re-added. A **new** upstream entry is still added. Pre-ledger machines can't tell a deletion from never-installed, so the first run adds as today (a stated limitation, the same as R13) |
| A4 | §15 R10 claimed §2 had been updated; it hadn't | The §2 rows are now actually added |
| A5 | `[k]` didn't persist: the next unattended run replaced the kept file | New rung 7b, KEPT: `kept-blob` and `kept-against` columns. A kept file is skipped until upstream changes again. Then it's CUSTOM, and D1 applies unattended (the owner's rule) |
| A6 | Routing to `extras.local.md` in a worktree that's later reaped loses the content from future renders | Route into the **primary checkout's** `extras.local.md` (the main worktree from `git worktree list`), never a linked worktree. That matches the existing rule to never install from a temporary worktree. When the rendering checkout lacks extras but `install-state/` has a snapshot, the snapshot is used as the extras input and the run says so |
| A7 | §6 step 5 still recorded a whole-file blob, and the §3 schema had no block column | §6 step 5 and the §3 schema fixed (`canonical-blob`, `block-blob`) |
| A8 | Percent-encoded names can exceed the 255-byte `NAME_MAX` | Path-id (a 16-hex prefix of the path's hash) instead, with the path kept in the manifest |
| A9 | Exit 3 breaks `set -e` callers | Exit 0 on success. Replacements are reported in `last-run.json` and the summary |
| A10 | An appended block in `model-routing.md` is discarded by the marker splice | No `[a]` for `model-routing.md` |

**Survived attack** (per the refuter): blob lookup in git history on full
checkouts, damaged-marker detection, the additive JSON union, and the ban on
appending to scripts.

**Remaining before build:** none of the reviews so far was a T1 cross-family
review (none is reachable from this machine). The BSD `diff` splitter and the
cost of 30 historical re-renders are still unmeasured.
