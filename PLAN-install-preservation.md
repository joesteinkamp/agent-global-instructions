# Plan — keep people's customizations in the files `install.sh` writes

**Status: PLAN ONLY (2026-10-11).** No product code yet; Joe asked for the plan
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
  manifest.tsv     path <TAB> class <TAB> blob-id-we-wrote <TAB> source <TAB> repo-commit <TAB> date
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
- **`<enc-path>`** is the `$HOME`-relative path with `/` replaced by `%2F`.
  Collision-free and readable.
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

The first rung that matches decides the outcome. Steps 1–6 are deterministic;
step 7 is the optional AI check (D2).

| # | Verdict | Test | Action |
|---|---|---|---|
| 1 | **PINNED** | path is in `pins` | Don't write. Report if upstream changed. |
| 2 | **ABSENT** | no file | Write it and record it. |
| 3 | **CURRENT** | blob(dest) == blob(new) | No-op. Record it if no record exists (adopts pre-ledger installs). |
| 4 | **OURS** | blob(dest) == manifest blob for this path | Safe overwrite, no prompt. Refresh `base/`. |
| 5 | **SHIPPED** | blob(dest) ∈ every blob this source ever had in git (`git log --format= --raw --no-abbrev -- <src>`) | Safe overwrite: an older version of ours. This is what makes migration work (§10). |
| 6 | **COVERED** | every non-blank line the user added is already present in the new content (or, for `~/AGENTS.md`, in `extras.local.md`) | Safe overwrite. The user's additions survive in the new file anyway. |
| 7 | **COVERED-AI** *(optional)* | the AI judge says the added lines' intent is already expressed in the new version (§7) | Treated as CUSTOM, with the verdict shown and a recommended action. **Never** a silent overwrite on its own. |
| 8 | **CUSTOM** | none of the above | Resolve per §5. |

"Lines the user added" is the line diff `base → dest` when a base exists, and
the line diff `new → dest` when one doesn't (pre-ledger), in both cases ignoring
whitespace-only changes. Lines the user *deleted* from our version are a
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
are: the manifest blob (4), the stored `.bak.*` renders this installer already
made (5′), and line coverage against the new render plus `extras.local.md` (6).

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
5. Record blob(new + block) in the manifest, so the next run sees the file as
   OURS-with-preserved-block, not CUSTOM.

**Where appending is unsafe, and what happens there instead:**

| File class | Why appending breaks it | What to do instead |
|---|---|---|
| `~/AGENTS.md` (rendered) | The next render wipes anything appended to the output | **Append to `extras.local.md` in the checkout instead.** It's the render's own sanctioned append point (`customize.sh:186`) and it's gitignored. Then re-render. The additions now survive every future install. |
| `~/.codex/AGENTS.md` (a real file about to become a symlink) | After the switch there's no separate file to append to: it *is* `~/AGENTS.md` | Same as above: the custom lines go to `extras.local.md`, so Codex still sees them through the symlink |
| **Role files** (all four tools) | The body must **open and close** with the `**Reminder:**` line, enforced at `render-roles.sh:117-119` because recency is what keeps a long agent run on its rules. A plain append pushes that line off the end. **No merge for roles** (Joe, D6). Only `[r]` replace with backup, `[k]` keep, or `[p]` pin, plus a diff. The `[a]` row shows "unavailable for role files — the reminder must stay last". |
| Markdown with YAML frontmatter (commands, skills) | A changed `model:`/`tools:` value can't be appended: a second frontmatter block is invalid | Body additions append as above. **Frontmatter changes** are merged key by key (the user's value wins for a key they changed; new keys from upstream are added). If that can't be done cleanly, the `[a]` option is withdrawn for that file. |
| Shell scripts (hooks, `worktree-sweep.sh`, `lm`, `timeout`) | Code appended after `exec`/`exit` is dead, and code before it runs twice | No append. `[r]` / `[k]` / `[p]`, plus a diff. The report suggests upstreaming the change (or, for hooks, a per-user hook entry pointing at their own script). |
| Key-merged JSON / managed TOML | Appended text is a parse error | Already field-merged today; "merge" there means the existing union. Add provenance instead (§9) to close G4. |
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
  explicit flags for follow-up, and stable exit codes (0 ok; 3 = ok, but custom
  files were replaced). The rendered instructions get a short pointer telling an
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
