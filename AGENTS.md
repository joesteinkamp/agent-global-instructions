# agent-global-instructions — project instructions

This repo *authors* the global AI instruction set. Your global rules already
apply; these are only the things that are true **here** and nowhere else.

## The one rule that matters most

**`template.md` is the only editable instruction surface.** Everything that
looks like instructions — `~/AGENTS.md`, `~/.claude/CLAUDE.md`, `examples/*.md`
— is rendered output. Hand-editing a render is silently discarded on the next
`./customize.sh`.

**Never render the globals into this checkout.** `customize.sh --project`
refuses to, by design: a render here is loaded a second time alongside
`~/AGENTS.md`, so every session in this repo would pay for the same ~5,500 words
twice. The file you are reading is the project instruction file, and it is
committed.

## Build, render, test

```sh
./customize.sh --print          # render to stdout (defaults + my-context.env)
AIGI_NO_USER_ENV=1 ./customize.sh --print   # reproducible render, no personal layer
./install.sh                    # writes the machine-wide files (--global only)
```

**After any `template.md` change, regenerate the committed examples or CI fails:**

```sh
for ex in examples/*.env; do b=$(basename "$ex" .env)
  ( set -a; . "$ex"; set +a; AIGI_NO_USER_ENV=1 ./customize.sh --print ) > "examples/$b.md"; done
```

The full CI matrix, runnable locally and in this order:

```sh
shellcheck --shell=bash ./*.sh hooks/*.sh evals/*.sh
./test.sh          # structure + pinned instruction text
./evals/run.sh     # every behaviour in evals/behaviours.md still has an anchor
./verify-skills.sh # vendored skill trees haven't drifted
```

## What a cut or reword will break

`test.sh` pins **exact strings** from the render, and `evals/run.sh` greps one
anchor per behaviour in `evals/behaviours.md`. Every pinned string is a rule
*headline* — the bolded opening clause of a bullet. Rewording the prose under a
headline is cheap; changing a headline fails by name. Before removing a rule,
check `evals/behaviours.md` for its `origin:` field: several rules are long
because a terser version already failed in production, and the reason is
recorded there or in `CHANGELOG.md` rather than in the template.

Green CI is **not** proof that a cut was safe — the largest sections are the
least anchored. If you delete a rule, anchor it first or say plainly that it is
unprotected.

## Generated and personal files — never commit, never hand-author

| Path | Who writes it |
|---|---|
| `commands/codex/`, `commands/cursor/` | `render-commands.sh` on every install |
| `roles/codex/` | `render-roles.sh` on every install |
| `commands/gemini/` | nobody — Gemini is retired, Antigravity (`agy`) replaced it |
| `my-context.env`, `extras.local.md`, `mcp-rules.local` | the person, locally |

Only `commands/*.md` and `roles/*.md` (the canonical Claude dialect) are
committed; the ports are regenerated.

## Skills

Vendored skill trees under `.agents/skills/` come from their own upstream repos
— improve them there and pull the update, never edit the vendored copy.
`install-commands.sh` installs skills by **symlink into the checkout it runs
from**, so a skill bump is only really installed once it lands on `main`; never
install from a temporary worktree.
