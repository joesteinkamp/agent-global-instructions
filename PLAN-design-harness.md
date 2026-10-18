# Plan — a harness for design teams

## Problem

The harness has spent months staying agnostic of who its user is. A first try
at role gating (#16, a persona-gated `design` command group) was reversed when
design was switched on for everyone. `PERSONA` was kept for back-compat but
changes nothing (`customize.sh:83`), and `/critique` was later removed with no
recorded reason (6b105e3). What's left is an engineering-workflow harness with a
design section bolted on: `/ship`, `/sync`, `/worktrees`, model routing and
delegates, plus `ux-audit` and three design roles. Nothing serves a design
manager.

Goal: **the AI harness for design teams** (designers, design engineers, and
design managers), with Joe as user #1 and the reference config.

## Decisions (Joe, /grill-me, 2026-10-18)

| # | Question | Answer |
|---|---|---|
| 1 | Audience | Design teams, Joe first. Portable stays portable. |
| 2 | Role model | **One harness, the same for everyone.** No per-role renders. |
| 3 | Engineering machinery | Keep for everyone, unchanged. |
| 4 | Other layers | `project-starter-pack` and `design-craft` left as they are. |
| 5 | Managers | Design managers: people and craft. |
| 6 | Hosts | Terminal required for now. Non-terminal reach is a later phase. |
| 7 | Team default | By role: the **only** thing role changes. |
| 8 | Falsifier | Per-role evals plus one real install. |
| 9 | Role knob | Revive `PERSONA` = `designer` \| `design-engineer` \| `design-manager`. Map `product-designer`→`designer`, `engineer`→`design-engineer`. `ROLE` stays free text. |
| 10 | New role | `roles/design-manager.md`, a people-and-craft lens. |
| 11 | Skills | Six, all in wave 1, lightweight, in this repo's `skills/`. |
| 12 | Critique vs review | **One skill, two modes:** `/critique` (feedback) and `/critique --gate` (review against the briefs). |
| 13 | Sources | Use whatever MCP servers are connected, name what was missing, read only. |
| 14 | People data | Publishing as a private artifact is OK. |
| 15 | Template | **Additive only.** No existing words change. |
| 16 | README | Rewrite the pitch for design teams. The repo name stays. |
| 17 | Shipping | One big PR. |
| 18 | Test bed | `~/projects/joesteinkamp-com`, gated against its `DESIGN.md` only. That repo is not modified. |
| 19 | Figma | Open the PR with the live Figma path marked unverified. Joe connects Figma, the live run happens, then Joe merges. |
| 20 | Real install | A design engineer, after wave 1. Person and date TBD (Joe). |

## Changes

### Foundation (one owner: harness-steward)

- `customize.sh`:
  - Revive `PERSONA` with the three values and the old-value mapping. Unknown
    values warn and fall back to `designer`.
  - Derive a new substitution var, `TEAM_DEFAULT`: the lenses a team starts
    from, by persona.
    - designer → `product-designer, ux-researcher, ui-designer`
    - design-engineer → `frontend-engineer, ui-designer`
    - design-manager → `design-manager, product-designer, ux-researcher`
  - `refuter` is always added. `PERSONA` must change nothing else in the render.
- `template.md`, agent-teams section: one **new** bullet (additive),
  "**Start from your role's lenses.**", rendering `{{TEAM_DEFAULT}}`. It is
  still overridden by what the task needs.
- `my-context.env.example`: document `PERSONA`.
- `roles/design-manager.md`: same shape as the other roles (frontmatter,
  reminder, Hard rules, Guidance, Do not report, Return). People-and-craft
  lens: team health, feedback quality, review rigor, staffing and sequencing.
  Writes documents only. Then `render-roles.sh`.
- `playbooks/agent-teams.md`: a `design-manager` row in the role table, plus
  design-team rosters (crit, design review, 1:1 prep).
- README + `docs/GUIDE.md`: lead with "the AI harness for design teams" and
  list the six skills.
- `skills/README.md`: rows for the six skills.

### Skills (portable dialect: `name` + `description` frontmatter only; no `!`cmd``, `$ARGUMENTS` or `allowed-tools`)

Each skill composes existing pieces and never re-implements them: `ux-audit`,
the starter-pack `validate`, Figma MCP, `playwright-cli`, connected MCP
servers. Each one says which inputs it found and which it didn't, and its
primary output is an HTML artifact, per the harness's output rules.

1. `skills/critique/SKILL.md`
   - **Plain:** open feedback on work in progress (what's working, what to
     explore). No pass/fail.
   - **`--gate`:** a review against whichever of PRODUCT/DESIGN/WRITING.md and
     `guardrails/` exist, citing ban IDs, with findings ranked by severity.
     It uses ux-audit for screenshots and names the briefs that are missing.
2. `skills/figma-parity/SKILL.md`: a built screen (URL or route) against a
   Figma node and the tokens. Drift report covering spacing, type, color,
   states and missing variants. Without Figma it falls back to
   DESIGN.md/DESIGN.json tokens and says so.
3. `skills/handoff/SKILL.md`: a prototype (Figma or a URL) → a spec engineers
   can build from: states, tokens, edge cases, a11y, open questions.
4. `skills/research-synthesis/SKILL.md`: notes and transcripts → themes, each
   backed by evidence (quote + source), plus open questions and confidence.
   Never invents participants or quotes.
5. `skills/one-on-one/SKILL.md`: 1:1 and feedback prep for a named report,
   from connected sources (Notion work, Calendar, Gmail, GitHub). Talking
   points and specific, evidence-backed feedback. Read only; may publish as a
   private artifact; never sends.
6. `skills/team-digest/SKILL.md`: what shipped, what's blocked and what's next
   across connected sources for a date range (default: the last 7 days).
   Read only.

### Evals and tests

- `evals/behaviours.md`: BEH-19 through BEH-26. One per skill, plus the
  PERSONA team default and the design-manager role.
- `test.sh`:
  - PERSONA maps and normalizes.
  - Each persona's render differs from the others **only** in the
    TEAM_DEFAULT line.
  - Six skill dirs exist with valid frontmatter in the portable dialect.
  - The role count includes design-manager.
- Regenerate `examples/*.md`.

## Done when

1. `shellcheck --shell=bash ./*.sh hooks/*.sh evals/*.sh`, `./test.sh`,
   `./evals/run.sh` and `./verify-skills.sh` all pass, with examples
   regenerated.
2. `/critique` (both modes) has been run on joesteinkamp-com against its
   `DESIGN.md`, with the output artifact produced and that repo's
   `git status` unchanged.
3. A cross-vendor refuter has reviewed the diff, and its findings are folded
   in or listed as disagreements.
4. One PR is open whose body states that the live Figma path of
   `/figma-parity` and `/handoff` has not run.
5. A Change Log entry is **proposed**, not written.

## Falsifier

- **CI level:** a missing eval anchor for any skill, or any render difference
  between personas outside the TEAM_DEFAULT line.
- **Real level:** a design engineer installs it after wave 1, works a day, and
  hits engineering-only friction, or nothing reads as built for their role. If
  so, decision 2 (one harness for everyone) gets reopened.

## Three lenses

- **UX:** six skills a designer would actually type, and one setting
  (`PERSONA`). Traded away on purpose: managers still load the engineering
  prose (decision 2).
- **DX:** additive template, no renames, existing headlines untouched, so
  pinned tests keep passing. Cost: one big PR to review (decision 17).
- **AX:** named skills with stated inputs and fallbacks, and a role-ordered
  team default. The agent no longer has to infer "this person is a designer".

## Execution

- Worktree: `../agent-global-instructions-design-harness`, branch
  `ai/claude-design-harness`.
- Builders write disjoint files: the foundation owner owns every shared file
  (customize.sh, template.md, test.sh, evals, README, GUIDE, skills/README,
  examples). Each skill builder owns only its `skills/<name>/` directory.
- Rival plan draft: one other vendor, medium effort, before the build lands.
  Divergences are surfaced to Joe.
- Progress: `STATE.md`-style notes in `~/.ai-context/agent-global-instructions-design-harness/`.

## Open (Joe)

- The real-install design engineer: name and date.
- Connect Figma (`mcp__claude_ai_Figma__authenticate`) for the live run.
