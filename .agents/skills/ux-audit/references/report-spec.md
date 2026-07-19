# Report spec — findings.json schema, templates, validation

SINGLE SOURCE OF TRUTH for the output schema. Scripts validate against this; SKILL.md
links here and never restates it.

## findings.json
```json
{
  "meta": {
    "audit_id": "checkout-2026-06-12", "date": "2026-06-12", "mode": "single|flow",
    "screens": ["screen-0.png"], "goal": "...", "persona": "...",
    "platform": "mobile|desktop|responsive", "stage": "live|hifi|wireframe",
    "frameworks_applied": ["nielsen", "..."], "tiers_run": [1, 2],
    "issue_overflow": 0, "model": "claude-fable-5"
  },
  "scores": { "overall": 64, "usability": 58, "cognitive_load": 70, "visual_layout": 72,
              "accessibility": 55, "content": 68, "trust_persuasion": 75 },
  "score_rationales": { "usability": "one sentence naming the band and why", "...": "..." },
  "one_big_thing": "single falsifiable root-cause diagnosis",
  "findings": [ /* type:"observed" only — Finding objects below */ ],
  "hypotheses": [ /* reserved — Tier 3 is informational-only and never evaluated; stays empty */ ],
  "flow": { "transitions": [{"from": 0, "to": 1, "verdict": "ok|issue", "note": "..."}],
            "missing_states": ["..."], "peak_end": "..." },
  "measurements": { /* verbatim measure.py output */ },
  "clean_checks": [ "GST: grouping matches semantics across cards" ],
  "delta": { "fixed": ["F-03"], "regressed": [], "new": ["F-11"], "unchanged": ["F-01"] }
}
```
`flow` only in flow mode · `delta` only in re-audit mode · `measurements` may be `{}`.

## Finding object
```json
{
  "id": "F-07",
  "category": "usability|cognitive_load|visual_layout|accessibility|content|trust_persuasion",
  "type": "observed|hypothesis",
  "severity": "critical|high|medium|low",
  "reach": 2, "importance": 4.5,
  "principles": ["NLS-01", "WCAG-1.4.3"],
  "screen_index": 1,
  "box_2d": [120, 640, 210, 980],
  "element": "primary checkout button, right column",
  "issue": "≤20 words, ONE sentence, states what is wrong",
  "why_it_matters": "≤2 sentences: what I see → user impact → business loss",
  "recommendation": "ONE sentence, action verb first, ≤25 words",
  "evidence": "measured: contrast 2.8:1 (#8a8f98 on #6b7280)",
  "validation": "hypotheses only: how to verify"
}
```
`element` is a required plain-text locator so humans can spot box mismatches instantly.
`box_2d` is `[ymin, xmin, ymax, xmax]` on 0–1000; `null` for screen-level findings.
`screen_index` 0-based; `null` = cross-screen (flow mode), which implies reach ≥ screen count.

**ID assignment order (enforced by validate_findings.py):** findings with a box_2d get
the lowest numbers (prefer reading order: by screen_index, then top-to-bottom), then
screen-level findings (box null, screen_index set), then cross-screen findings
(screen_index null). Report markers show only boxed findings, so this keeps marker
numbers contiguous from #1 with the unanchored findings appended after.

## Conciseness contract (verbatim from Qualia)
Total ≤60 words across issue + why_it_matters + recommendation. issue ONE sentence ≤20
words. recommendation action-verb-first ≤25 words. NO filler ("It's important to note…").
NO restating the principle in why_it_matters. NO coordinates in user-facing text.

## Validation checklist (run before emitting; validate_findings.py automates it)
1. Schema: required keys present, enums valid, scores 0–100 integers.
2. Citations: every `principles` entry resolves in `references/registry.json`.
3. Words: issue ≤20, recommendation ≤25, total ≤60.
4. Boxes: ymin<ymax, xmin<xmax, within 0–1000; localized finding ↔ box required;
   screen-level ↔ null; box area ≤80% of screen (else it's screen-level).
5. Numeric a11y claims (ratio/px in text or evidence) require `measured:` evidence.
6. Hypotheses: type=hypothesis ↔ has validation ↔ lives in `hypotheses` array; Tier-3-only
   principles (FOGG-*) never appear in `findings`.
7. ≤5 findings per category; overflow count recorded in meta.issue_overflow.
8. importance = severityWeight × reachBand (recompute, don't trust).

## summary.md template (≤60 lines, for Linear/GitHub)
```markdown
# UX audit — <title> — <date>
**Overall: <n>/100** (<band>) · mode: <single|flow> · <k> findings, <h> hypotheses
**One big thing:** <obt>
| Category | Score | Top issue |
|---|---|---|
(6 rows)
## Top findings
1. **[<severity>] <issue>** — <recommendation> (<principle names>)
(top 5 by importance)
Full report: <link to report.html> · machine-readable: findings.json
```

## One Big Thing rules (verbatim)
1. Diagnose the system, not the symptom. 2. Do not over-attribute (a bad last step in a
9-step flow is a symptom of flow length). 3. Do not mirror the user's persona/mission
language. 4. Be falsifiable ("too many decision points for a first-time user" is a finding;
"tension between promise and delivery" is a reflection).
