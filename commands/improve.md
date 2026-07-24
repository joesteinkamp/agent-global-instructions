---
description: Run a multi-role review team on recent changes to find improvement opportunities
argument-hint: [optional focus, e.g. "perf" or a path]
allowed-tools: Bash(git:*), Bash(command:*), Bash(codex:*), Bash(agy:*), Bash(claude:*), Bash(agent:*), Bash(cursor-agent:*), Bash(lm:*), Task, Read, Grep, Glob
---

Changed files: !`git --no-pager diff --stat HEAD 2>/dev/null`
Untracked: !`git --no-pager status --porcelain 2>/dev/null | grep '^??' || true`
Recent commits: !`git --no-pager log --oneline -5 2>/dev/null`
Other AI CLIs installed: !`cat "$HOME/.ai/clis" 2>/dev/null || command -v codex agy claude agent cursor-agent 2>/dev/null | sed 's|.*/||'`
Local models registered: !`cat "$HOME/.ai/local-models" 2>/dev/null || true`

Run a **multi-role improvement review** on the recent changes (working tree vs HEAD, plus the last few commits if the tree is clean). $ARGUMENTS

1. Scope the changes and decide whether they touch UI.
2. Spin up the review team **in parallel** — one subagent per lens (Task/Agent tool):
   - **Technical architect** — structure, coupling, boundaries, risk, missing abstractions.
   - **Back-end engineer** — correctness, data handling, error paths, performance.
   - **Front-end engineer** — component design, state, accessibility, UX edge cases.
   - **UI/UX** — *only if UI changed* — judge visual & interaction quality against a concrete rubric, not vibes:
     - **Nielsen's 10 heuristics** — status visibility, match to the real world, user control/undo, consistency & standards, error prevention, recognition over recall, flexibility, minimalist design, error recovery, help.
     - **Accessibility (WCAG 2.2 AA)** — contrast, visible focus, labels/roles, and adequate target size.
     - **Visual hierarchy & copy** — Gestalt grouping, alignment, scannability, and clear copy/microcopy; is the primary action obvious?
     - **Fitts's / Hick's law** — target size & distance for key actions; choice load kept low.
     - **Design-system consistency** — stays on the type/spacing/color scales and existing tokens/components; no one-off values.
     - **Responsive & motion** — holds up at mobile/tablet/desktop; animation honors `prefers-reduced-motion`.
   Give each only the diff + the relevant files. Ask each for concrete, prioritized **improvement opportunities** (not praise), each with `file:line` and a suggested change.
3. **Cross-vendor check — a model must not be the sole checker of its own work.** The changes under review were likely authored by the model running this command. The probe above lists every installed AI CLI; excluding the one you are running as, **spread the review lenses across all of the others — more independent vendors is better**, with at least one lens cross-vendor. Run each headless, with writes scoped to a context dir it reports into (the repo stays read-only to it): `mkdir -p ~/.ai-context/<repo>-improve/agents`, then e.g. `codex exec "…" --sandbox workspace-write --cd ~/.ai-context/<repo>-improve` or `agy -p "…" --mode accept-edits --add-dir ~/.ai-context/<repo>-improve`. Give it the same diff + files, ask it to **refute** the work (not confirm it), and have it write full findings to `agents/<vendor>.md` — read that file, not just stdout, which can truncate. Attribute its findings in the summary; if no other vendor is installed, say so.
   **Local models:** if the local-models probe above lists a `strong`-tier entry, add it as one more independent lens — `lm -p "…" --tier strong` with the same diff, prompted to refute; its findings go to `agents/lm.md` (pipe the output there yourself — `lm` is one-shot text, it writes no files). `light`-tier models don't join review panels, and a local model is never the only cross-check.
4. Collect findings, **dedupe**, group by theme, sort by impact.
5. Present a tight summary **inline**: top opportunities first (where + why + suggested fix). Call out any real bugs separately. Offer to also write this up as a self-contained HTML report (served on `0.0.0.0` per my preview method) if I want a shareable artifact — produce it only if I say yes or asked for it up front.
6. **Prepare to act.** Turn the findings into a prioritized, ready-to-apply plan — each item with `file:line`, the concrete change, and its expected impact — ordered so I can approve all or cherry-pick. This is still a review pass: **don't edit anything yet.** Then ask which items to apply and, on my go-ahead, make exactly those changes (nothing more).
