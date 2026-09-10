# Verify & improve playbook

On-demand mechanics, installed to `~/.ai/quality-workflows.md` by
`customize.sh --global`. The resident instructions (`~/AGENTS.md`) keep the
gates — explicit-only, verify blocks handoff — and point here for how the
workflows actually run. **Read this before running `/verify` or `/improve`,
or before suppressing a `quality-nudge` advisory.**

## The review itself (`/improve`)

Default panel — technical architect, back-end engineer, front-end engineer, plus a UI/UX lens when UI changed. Run them in parallel as subagents; each returns concrete, prioritized suggestions (`file:line` + fix). Whichever tool is running the review, spread the lenses across the *other* installed AI CLIs as delegates (per the orchestration playbook) — more independent vendors is better, and a model checking its own work is not a check. Then dedupe and summarize, top impact first. It's a review pass — surface opportunities and any real bugs; don't apply changes unless the user says so.

**`/improve` runs in the background by default.** It's advisory and read-only, so it must not block the session: pin the review to a snapshot at invocation (`git stash create`, else `HEAD`, plus the frozen diff *and copies of untracked files* in the context dir — the frozen evidence, not the live tree, is what gets reviewed), run the panel against that SHA while work continues, and land findings both as a completion notification and a durable `findings.md` stamped with the SHA. Explicit-only still applies — backgrounding changes how it runs, never when it may start. On hosts without background tasks it runs inline.

## `/verify` is synchronous

**`/verify` is a handoff gate.** Don't call work done, hand it off, or ship while a verify is pending. `/verify --bg` is the deliberate exception for long runs: snapshot-pinned like `/improve` but materialized in a disposable worktree at that SHA (verify *runs* code, so it needs a real frozen tree), marked by a durable `PENDING.md` open-gate file that `/ship` checks, and tied to an explicit done-condition ("done when this verify reports its grade") that the handoff waits on — deferred, never fire-and-forget.

## The `quality-nudge` advisory

- **When an advisory appears:** mention only the relevant option in the handoff. Don't run it, block completion, or make the user dismiss it. A quiet hook is not something to second-guess.
- **Applying changes the user already approved** — the fixes/improvements from a prior verify or improve pass ("yes, do those"): just make them and confirm. **Don't re-run** verify/improve on the result — that review already happened, and re-running loops. Suppress the one advisory turn with the marker below.
- **Skip marker:** `d="${AI_NUDGE_STATE:-$HOME/.ai-logs}"; k="$(printf '%s' "$PWD" | cksum | cut -d' ' -f1)"; mkdir -p "$d"; touch "$d/.nudge-skip-quality.$k"`

## The refuter runs pre-emit, and it scores

`/verify` and `/improve` are explicit-only: they run when the user asks, never on
the agent's initiative. The `refuter` role is **not** one of them and must not
become one — it runs **pre-emit**, before a claim reaches a handoff, as part of
producing the work rather than as a review of it. Spawning a refuter is not
starting a quality workflow, and it never needs the user's ask.

What that means in practice:

- **Any claim that matters gets refuted before it is stated, not after.** A
  finding, a root cause, a plan, a "this is fixed" — the refutation happens while
  the work is still yours to change.
- **It returns a verdict and a score** on the five axes in `roles/refuter.md`
  (grounding, scope match, failure case, assumption load, reproducibility). The
  score exists so two runs on the same claim are comparable; a verdict alone
  drifts between sessions.
- **The threshold is an action, not a note.** Below `holds`, the claim does not go
  into a handoff as settled — it goes with its gaps named, or it doesn't go. `Scope
  match` at 2 is required for `holds` on purpose: the most common way a wrong claim
  survives is being true of the case that was checked and asserted of one that
  wasn't.
- **A refuter finding is not a `/verify` result.** Don't report it as one, and
  don't let a clean refutation stand in for a verify the user asked for.
