# Plan — routing when the lead is below T1

## Problem

Model routing silently never fired. Joe saw no errors, just every agent running
on the lead's model. Three causes:

1. Routing answers "which tier does the task need" but never "is the lead at
   that tier". A Sonnet lead does T1 judgment itself.
2. Every in-tool spawn inherits the lead's model (`model: inherit` in Cursor
   roles, no `model:` in Claude roles), so subagents are clones of a T2 lead.
3. The `agent` launch form in `orchestration.md` hard-codes `--model auto`
   (free-plan advice), while this machine's plan reaches named models. Every
   pick through Cursor collapsed to `auto` (T3 at most, unknown family).

Target pattern: a T2 lead (Sonnet) as executor, with T1 brought in at judgment
points, which is Claude Code's `/advisor` pattern generalized across hosts.

## Decisions (Joe, 2026-10-15)

| Question | Answer |
|---|---|
| Claude Code advisor | Seed `advisorModel: "opus"` when unset (seed-only, like agent teams) |
| Escalation strength | Advisory, like the rest of the routing file |
| Sonnet 5.5's tier | Pin to T2 in this machine's table |
| Cursor subagent model | The instructions count as the standing explicit request; try the subagent tool's model param first, fall back to a CLI |

## Changes

- `MODEL-ROUTING.md` (stable method): new section *When the lead is below the
  tier*: know your own tier, escalate judgment up per host (advisor → T1
  subagent → T1 delegate), delegate down not sideways, advisor fixes tier not
  independence. Plan-aware `agent` gotcha. A *Pinned tiers* line the generator
  must carry forward.
- `playbooks/orchestration.md`: `agent` launch form takes the routed slug;
  `auto` only where the account note says the plan is free.
- `template.md`: one teams bullet, "Pick each agent's model; don't inherit by
  default", which doubles as the standing model request. Fix the stale "vendor
  rankings" pointer.
- `install-settings.sh` / `uninstall.sh` / `test.sh`: seed and reverse
  `advisorModel`, same shape as agent teams.
- `skills/update-model-routing/SKILL.md`: carry `Pinned tiers` forward.
- Machine copy `~/.ai/model-routing.md` (not committed): Sonnet 5.5 → T2,
  pinned.

## Done when

`shellcheck`, `./test.sh`, `./evals/run.sh`, `./verify-skills.sh` all pass;
examples regenerated; PR open.

## Falsifier

If Cursor's subagent tool still refuses a non-`inherit` model with the standing
request in place, the Cursor path is CLI-only, and the bullet must say so
rather than promise the param. That can only be checked in a fresh session
after install.

## Three lenses

- **UX:** no new commands; the advisor is on after one install.
- **DX:** seed-only settings, reversible by uninstall; pins survive regeneration.
- **AX:** the lead gets one table lookup and one ordered escalation ladder per
  host instead of a two-hop pointer chain it rarely followed.
