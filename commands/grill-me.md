---
description: A relentless interview to sharpen a plan or design, asked in rounds, until we reach a shared understanding
argument-hint: [the plan, decision, or idea to grill — defaults to whatever we were just discussing]
allowed-tools: Bash, Read, Grep, Glob
---

Interview me relentlessly about the plan, decision, or idea below — or, if
nothing follows, whatever we were just discussing — until we reach a shared
understanding. $ARGUMENTS

Map it as a **design tree**: every decision branches into the decisions that
hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose
prerequisites are already settled — the questions you can ask *now* without
guessing at answers you haven't heard yet. Ask the whole frontier in one round:
number each question and give your recommended answer. Then wait.

Only a question whose wording genuinely changes based on an answer still open in
this round belongs to a later round. A question you could have asked now and
held back is a round trip you charged me for nothing. Where this tool has a
native multi-question prompt, use it.

Each round of answers reshapes the tree: settled decisions push the frontier
outward and unblock what depended on them. Recompute and ask the next round.

If a *fact* can be found by exploring the environment (filesystem, tools, etc.),
look it up rather than asking me — dispatch a sub-agent where that's available.
Don't block on it: a running lookup is an unsettled prerequisite, so only the
questions downstream of it wait. Ask the rest of the frontier now. The
*decisions* are mine — put each one to me and wait for my answer.

Done when the frontier is empty: every branch visited, nothing left silently
assumed. Do not act on it until I confirm we have reached a shared
understanding.
