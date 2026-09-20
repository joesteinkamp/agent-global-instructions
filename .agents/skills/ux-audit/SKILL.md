---
name: ux-audit
description: >
  Audit UI screenshots against 15 published UX heuristics frameworks (Nielsen, Gestalt,
  WCAG, Fitts/Hick/Miller, Cialdini dark patterns, and more). Produces severity-rated
  findings with principle citations, 0-100 scores, annotated screenshots, and an HTML
  report. Use when the user asks to audit/review/critique a design, screenshot, mockup,
  or UI flow ("audit this design", "UX review", "what's wrong with this screen").
---

# /ux-audit

Skill root: resolve via this file's location (referred to as `$SKILL` below).
All scripts: `$SKILL/.venv/bin/python $SKILL/scripts/<script>` — contracts in scripts/README.md.
If `$SKILL/.venv/bin/python` is missing, bootstrap it once first: `bash $SKILL/scripts/setup.sh`
(creates the venv, installs Pillow — the only dependency; everything after it runs offline).

## 1. Intake — ONE AskUserQuestion round, exactly these questions
1. **Goal** (free text): "What is the user trying to accomplish on these screens?" —
   drives the Blocker gate; if the user already stated it, skip the question.
2. **Persona**: first-time visitor (default) / returning user / expert user / other.
3. **Platform**: mobile touch / desktop / responsive. (Touch ⇒ 44px target minimum, else 24px.)
4. **Stage**: live product / hi-fi, real data / hi-fi, placeholder data / wireframe.
   Sets `meta.stage` AND `meta.data_fidelity` (live ⇒ real; wireframe ⇒ placeholder;
   "other" for representative/unknown). Calibration: wireframe ⇒ skip visual_layout
   color+contrast checks and content polish; data_fidelity ≠ real ⇒ never penalize the
   data itself, list what you excluded in `meta.calibration_exclusions`.

## 2. Mode detection
- 1 image → **single** mode. 2+ images → **flow** mode: confirm screen order with the user
  before analysis if not obvious from filenames.
- Prior findings.json supplied → **re-audit** mode (step 8).

## 3. Load context (progressive disclosure — load ONLY these)
- Always: `references/scoring.md`, `references/filter.md`, `references/report-spec.md`.
- Tier 1 (always): frameworks/ `gestalt.md`, `wcag.md`, `cognitive-laws.md`,
  `gerhardt-powals.md`, `content-design.md`, `cialdini.md`, `recurring-failures.md`.
- Flow mode adds Tier 2: `nielsen.md`, `norman.md`, `shneiderman.md`, `tognazzini.md`.
  (Single mode: still load `nielsen.md` + `norman.md` — their Tier-1 symptoms apply.)
- Never load files marked `status: informational` (e.g. `fogg.md`) — Tier 3 behavioral
  analysis is out of scope entirely; never claim effectiveness, timing, or conversion impact.

## 4. Measure (before any judgment)
Run the auto pass: `measure.py <images> --json tmp/measurements.json`. During analysis,
request region probes for any element you suspect of contrast/size failure:
`measure.py IMG --region y0,x0,y1,x1 --probe contrast|size`.
**Hard rule: no numeric contrast/size claim without `measured:` evidence. Unmeasured
suspicion ⇒ "appears low-contrast — verify", medium severity max.**

## 5. Analyze — one pass per category, every screen
Count every candidate you generate — the funnel feeds `meta.candidate_stats`.
View each screenshot carefully. For each category (usability, cognitive_load,
visual_layout, accessibility, content, trust_persuasion): scan against that category's
loaded symptom lists, generate candidate findings. Every candidate MUST cite ≥1 registry
principle ID and name its `element` in plain text. Localized ⇒ box_2d; whole-screen ⇒ null.
Flow mode additionally: transition pass — cross-screen consistency (NLS-04/SHN-01), action
acknowledgement (NLS-01/SHN-03), exits/undo (NLS-03/SHN-06), memory load (SHN-08/RF-12),
peak-end on the final screen (PEAK-01); populate the `flow` block.
Also record `clean_checks`: categories/principles examined that passed.

## 6. Filter, merge, score
Apply the four gates (filter.md) to every candidate; merge cross-framework duplicates;
cap 5/category by importance; record the drop/merge/cap counts in `meta.candidate_stats`.
Then score per scoring.md: state each category's band in one sentence
(`score_rationales`), then the number; fill `score_evidence` (band, drivers, passes,
limitations — traceability rules in scoring.md); compute weighted overall; band wins
over math. Write the One Big Thing per report-spec rules. Then `path_to_excellent`:
the verification backlog (everything not observable statically — wcag.md rule 4,
missing states, real data provenance) and the post-fix projection (≤89 while the
backlog is non-empty).

## 7. Validate & emit
Output dir: `audits/<slug>-<YYYY-MM-DD>/` (slug from goal/screens).
Write `findings.json`, then run `validate_findings.py findings.json` — fix every error it
reports and re-run until clean. Then:
- `annotate.py findings.json --images <originals> --out <dir>/annotated/`
- `build_report.py findings.json --images <originals> --template
  assets/report-template.html --out <dir>/report.html` (originals, not annotated —
  the report draws its own interactive markers)
- Write `summary.md` per the template in report-spec.md.

## 8. Re-audit mode (when prior findings.json given)
Audit the new screens normally (steps 4–7), then match prior findings to new ones by
principle overlap + same screen_index + box IoU>0.3 (text similarity fallback). Populate
`delta` {fixed, regressed, new, unchanged}. The report template renders the delta section.

## 9. Deliver
Serve the audit dir: `python3 -m http.server <port> --bind 0.0.0.0` (reuse a running
server if one already serves the path). Verify with curl (expect 200), then hand the user:
the Tailscale URL to report.html, the overall score + band, the post-fix projection
("fixing all k findings ⇒ ~lo–hi, not 100 — backlog explains the rest"), the One Big
Thing, and the top 3 findings inline. Honesty notes: the candidate funnel (why the
findings list is short), what was NOT auditable (wcag.md rule 4), any issue_overflow.
