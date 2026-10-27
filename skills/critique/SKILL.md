---
name: critique
description: "Design crit on work in progress (a URL, route, screenshot, Figma link, or files): open feedback by default, meaning what's working, what to explore, and questions worth asking, with no scores. With --gate, or when asked for a review or gate, it becomes a severity-ranked review against the project's own PRODUCT/DESIGN/WRITING.md and guardrails ban IDs, ending in a pass / pass with issues / fail verdict. Use for \"crit this\", \"feedback on this design\", \"review this against our design system\", \"is this ready to ship\". Read-only; the deliverable is an HTML report."
---

Run these probes **from the project's root** (`cd` there first), not from wherever the session started.
Run from the wrong directory, they report every brief missing.

Project briefs: run `ls PRODUCT.md DESIGN.md DESIGN.json WRITING.md guardrails 2>/dev/null || true`
Guardrail registry: run `test -f guardrails/registry.json && echo "guardrails/registry.json, so cite bans by ID" || echo "none"`
Validate skill: run `ls -d ~/.claude/skills/validate ~/.codex/skills/validate ~/.cursor/skills/validate .agents/skills/validate 2>/dev/null || true`
Project state at start: run `git status --porcelain 2>/dev/null || true` and keep the output; the last step checks it again.

**Critique** looks at a piece of work in progress the way a good design crit does: specific, grounded in
what the work is trying to do, and useful to the person who made it. It has two modes. **Branch on the
request:** run **gate** mode only when the request contains `--gate` or explicitly asks for a review, a
gate, or a ready-to-ship check. Anything else runs **plain** mode, and plain mode never quietly turns into
a gate. If someone asks "is it good?" in plain mode, answer as a crit and offer `--gate`.

**Read-only, always.** Critique never edits, formats, builds, or installs anything in the project. Every
output (screenshots, ux-audit output, the report) goes in the project, the way `/verify`'s does:
`critique/<slug>-YYYY-MM-DD/` at the project root, with `-gate` appended to the slug in gate mode so the
two runs never share a directory. Before writing, add `/critique/` to the clone's exclude file if it isn't
there, through the shell:
`f="$(git rev-parse --git-path info/exclude 2>/dev/null)" && { mkdir -p "$(dirname "$f")"; grep -qxF '/critique/' "$f" 2>/dev/null || echo '/critique/' >> "$f"; }`
Edit tools are denied on anything under `.git/`, and `--git-path` also finds the file in a linked
worktree, where `.git` is a file. The exclude file is local and never committed, so the report can't show
up as a change or be committed by accident. Outside a git repo, use
`~/.ai-context/critique/<slug>-YYYY-MM-DD/` instead. `cd` into the report directory before running
`playwright-cli` or ux-audit, because both write working files to the current directory.

### 1. Get the artifact, and say what you couldn't get
Work from the thing itself, not a description of it. Find the work and the focus in the request.
- **URL or route.** Drive it with `playwright-cli`. Read `~/.ai/web-preview.md` first. Use a server that's
  already running. If nothing serves the route, you may serve existing build output statically
  (`python3 -m http.server PORT --bind 0.0.0.0 --directory dist`). Never run an install or a build in the
  project to get a screenshot: ask for a URL or a screenshot instead (unattended: step 4). Screenshot at
  the project's breakpoints (`DESIGN.json` `breakpoints` if it exists, else 390 / 768 / 1280) with
  `resize <width> 900` and then `screenshot`, and capture interactive states the request names. Before a full-page capture,
  scroll through the page so lazy-loaded and scroll-revealed content renders, then look at the image: a
  capture that's blank below the fold is false evidence, not a finding. **Run `playwright-cli close` once
  every browser-based measurement is done** (screenshots, computed styles, contrast probes), then run the
  process check from web-preview.md.
- **Figma link.** Use the Figma MCP server if one is connected in this session (read the node and its
  variables and export an image). If none is connected, ask for an exported frame and say the live Figma
  path didn't run.
- **Screenshots.** Read them directly.
- **Files (code, markup).** Read them. Code alone can't show you rendered layout, color, or motion. Say
  which judgments that rules out, or get a screenshot.
- Write down every input you were asked for or needed but couldn't get. It goes at the top of the report.

### 2a. Plain mode: the crit
Start with what the work is for: the user's goal, the stage (sketch, hi-fi, live), and the feedback the
maker wants. Take these from the request. If the request doesn't say, read `PRODUCT.md` as context; if it
still isn't clear, ask once. On an unattended run, where nobody can answer, state the goal you assumed at
the top of the report and mark it assumed. Then give, for each screen or flow:
- **What's working.** Name the specific choice and why it serves the goal. "Nice layout" isn't feedback.
- **Worth exploring.** Directions, not fixes: "what if the primary action led the card?" Give the reason,
  and where it fits, an alternative worth sketching.
- **Questions worth asking.** The assumptions the work rests on, states it doesn't show yet (empty, error,
  first-run, long content), and choices that look like defaults rather than decisions.
No pass/fail, no severity, no scores, no ban IDs. Briefs can inform the crit, but plain mode doesn't grade
against them. Don't run ux-audit in this mode, because its scores and severities aren't crit feedback.
Pitch the crit at the stage: a wireframe gets questions about the structure, not about pixels.

### 2b. Gate mode: the review
**--gate judges only against briefs that exist.** A missing brief removes what you can judge. It never
licenses a standard you made up.
1. **Inventory the briefs.** Read every brief the probe found, in full, plus `guardrails/registry.json` if
   it exists. Write a table of each brief, present or missing, and what being missing rules out:
   - no `DESIGN.md` / `DESIGN.json`: no token or component findings
   - no `WRITING.md`: no voice or terminology findings
   - no `PRODUCT.md`: goal-fit is judged only against the goal stated in the request
   - no `guardrails/`: no ban IDs, so cite brief lines instead
2. **Judge against each brief that exists.** Each finding gives:
   - where it is in the work (screen and element, or source `file:line`)
   - the standard it breaks, either a brief's `file:line` or a ban ID such as `DES-03` (when a ban covers
     the rule, cite the ban rather than restating it)
   - the evidence, either a computed value, a measurement, or a screenshot region
   - the fix
   A note with no standard behind it isn't a gate finding. Put it in the report's "outside the briefs"
   section, unranked.
3. **Screenshot heuristics: compose ux-audit, don't re-implement it.** When you have a screenshot, run the
   `ux-audit` skill. Pre-answer its intake (goal, persona, platform, stage) from the request and
   `PRODUCT.md`, so it only asks what neither one answers. Run it with the report directory as its working
   directory so its `audits/` output lands there. Fold its findings in with their principle IDs and
   severities. Carry over its candidate funnel and any `issue_overflow`, because its capped list isn't the
   whole picture. **If ux-audit isn't installed or can't run** (for example its Python environment isn't
   set up), list it under inputs unavailable and put "ux-audit not run" in the verdict line. Never install
   or bootstrap it, or anything else outside the project, without a go-ahead.
4. **Validate.** If the probe found the starter-pack `validate` skill, read its SKILL.md and run it. If it
   would write to the project, skip it and say so. When the project has its own `guardrails/`, report its
   results by the project's ban IDs and count them toward the verdict. When it doesn't, validate cites the
   starter pack's own registry: report those IDs in a separate section labelled "starter-pack bans, not
   this project's standard", and keep them out of the verdict.
5. **Rank.** Use ux-audit's scale so the findings merge cleanly. Where the registry carries a severity for
   a ban, use it. Otherwise rate with this rubric and mark the rating as yours:
   - **critical**: blocks the user's goal, breaks a project ban, or fails WCAG 2.2 AA with a measured value
   - **high**: breaks a brief rule, with evidence, in a way a user would notice
   - **medium**: a visible deviation from a brief with little user impact, or an inferred failure
   - **low**: cosmetic, or a value off-scale but not visibly so When the same element breaks the same rule, list it once and cite every source. A divergence
   that looks deliberate is still a finding: flag it as "the brief may be stale" and don't pass it
   silently.
6. **Verdict, with the threshold printed beside it.**
   - **fail**: any critical
   - **pass with issues**: no critical, at least one high
   - **pass**: nothing above medium
   A verdict reached with major briefs missing, or with ux-audit or validate not run, says so in the same
   line ("pass, judged against DESIGN.md only; ux-audit not run").
7. **Second opinion when it's your own work.** If this session, or the model you're running as, built the
   work you're gating, have another vendor's CLI give a verdict independently (read
   `~/.ai/orchestration.md`; the delegate gets read access to the project and write access only to the
   context dir). Report both verdicts and never average them. A delegated or QA run gating someone else's
   work marks this step "not applicable" and says why.

### 3. Report
**Findings are never trimmed.** Every finding goes in the report, ranked. Ranking is the filter. The
primary deliverable is a self-contained `report.html` in the report directory:
- inputs used and inputs unavailable
- the brief inventory (gate mode)
- the screenshots with findings or crit notes keyed to regions
- the ranked findings, or the crit
- the verdict and its threshold (gate mode)

Every claim says how you know it: measured, seen in a screenshot, read in a file, or inferred. Serve the
directory per the preview rules (bind `0.0.0.0`, curl until you get a 200, hand over the
`http://<host>.ts.net:PORT/report.html` URL) and keep it running unless the caller says otherwise or the
run is unattended (step 4). Report its port and PID so whoever is done with it can stop it.

In chat, keep it short: the mode, the verdict and threshold (gate) or the two or three most useful crit
points (plain), counts by severity, missing briefs and inputs, and the URL.

### 4. Unattended runs and the result line
**An unattended run finishes; it doesn't wait.** A run is unattended when nobody can answer mid-run: a
`/goal` or `/loop` turn, a scheduled or headless run, or a request that says so. Wherever this skill says
ask, an unattended run takes the best guess the step names (the goal from `PRODUCT.md`, the inputs that
are reachable), marks it *assumed* in the report and lists it under open questions, then finishes. When
there is nothing to work from (no URL, screenshot, frame or file reachable), it ends with
`verdict=blocked` and names what it needed, rather than critiquing a description of the work. It starts no
preview server either (one it needs only to measure, it stops when done): it writes the file and gives its path, because a loop that serves every run leaves a server
behind each time.

**End the chat summary with one result line**, in exactly this shape, so a `/goal` checker, which reads
only the conversation, can test it:
`CRITIQUE mode=gate verdict=pass|with-issues|fail|blocked critical=N high=N medium=N low=N rerated=N briefs-missing=<names|none> ux-audit=run|not-run second-opinion=agree|disagree|not-run|n/a`
`with-issues` is the "pass with issues" verdict, spelled so that no other value contains `pass`. Plain
mode prints only `CRITIQUE mode=plain report=<path>` (or `verdict=blocked`), because a crit has no
verdict to check. `rerated` counts findings rated lower than in the earlier gate runs of the same work (the
other `critique/<slug>-*-gate/` reports), each listed in the report with its reason. A first run has
no baseline, so its ratings are what the second opinion checks. Lowering a severity is the easiest way for a loop to reach
"pass", so the count sits where the checker can see it.

**A gate on work you're fixing is done only on independent agreement.** When a gate fails on work this
session can fix, offer the goal line with the condition already written, e.g.
`/goal the CRITIQUE line shows verdict=pass, second-opinion=agree and rerated=0; or stop after 15 turns`
`verdict=pass` alone is the agent grading its own fixes; the second opinion (gate step 7) is the check.
When no other vendor's CLI is reachable, `second-opinion=not-run` can't change, so don't offer the goal:
say the independent check is missing and leave the re-gate to me.

### 5. Leave the project as you found it
Re-run `git status --porcelain` in the project and compare it with the start. If anything changed, say
exactly what changed. Don't clean it up. Then offer next steps: a gate after a crit, a re-gate after
fixes, or drafting a missing brief section from what the work already does. Don't apply anything.
