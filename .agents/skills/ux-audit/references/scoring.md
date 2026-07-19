# Scoring rubric

<!-- Severity definitions, weights, reach bands, importance formula, overall bands, and the
anti-compression rule are VERBATIM from Qualia (~/projects/qualia, scripts/ux-audit +
analyze-prompts.ts). Do not paraphrase. Category anchors are original to this skill. -->

## Severity (per finding)
| Level | Definition | Weight |
|---|---|---|
| critical | Prevents user goal completion | 4 |
| high | Significant friction on the critical path | 3 |
| medium | Reduces confidence or adds friction | 2 |
| low | Polish or edge case | 1 |

## Importance (sort key)
`importance = severityWeight × reachBand`
reach = screens/elements the issue touches: ≤1 → 1.0 · ≤3 → 1.5 · ≤9 → 2.0 · >9 → 3.0

## Category sub-scores (0–100) and overall
| Category | Weight |
|---|---|
| usability | 30% |
| cognitive_load | 15% |
| visual_layout | 15% |
| accessibility | 15% |
| content | 15% |
| trust_persuasion | 10% |

overall = weighted average, then sanity-checked against the band definitions below —
if the band description contradicts the math (e.g. a critical blocker exists but math says 82),
the band wins and sub-scores must be revisited.

## Overall bands (verbatim)
- **0–49** fundamentally broken; primary action missing/unreachable/non-functional
- **50–65** broken flows; invisible primary actions; users likely abandon without external guidance
- **66–79** functional, standard design; usable but unremarkable
- **80–89** strong, well-considered with minor gaps
- **90+** exceptional; no blockers, no friction on critical path, clear hierarchy

**Calibration rule (verbatim):** Score compression (clustering 70–89) is a calibration
failure. The full 0–100 range must be used. Mediocre designs score 50–65; strong designs 88–94.

**Procedure:** for each category, first STATE the band and why in one sentence, then pick
the number. Hypotheses (Tier 3) never move any score.

## Per-category anchors (90 / 50 / 20)
**usability** — 90: conventions followed, every destructive action guarded, no dead ends,
labels name outcomes. 50: ≥1 unguarded destructive action or dead end on the main path;
several vague labels. 20: primary action undiscoverable or false-affordance-ridden;
flow contradicts itself.
**cognitive_load** — 90: one decision per moment, totals/summaries computed for the user,
chunked data. 50: 6–9 equally weighted decision points; user does mental math the UI could do.
20: decision overload at commitment points; raw data dumps where decisions are needed.
**visual_layout** — 90: grouping matches semantics at a glance; single visual hierarchy;
squint test passes. 50: 2 competing focal points; ≥1 grouping that misleads. 20: flat
hierarchy; containers group unrelated things; layout readable multiple conflicting ways.
**accessibility** — 90: no measured contrast failures, all inputs visibly labeled, targets
≥ platform minimum, nothing color-only. 50: 1–2 measured AA failures or placeholder-only
labels on a primary form. 20: body text or primary CTA fails contrast badly; multiple
unlabeled inputs; sub-20px touch targets on main actions.
**content** — 90: outcome-named CTAs, user-language copy, consequences stated, one voice.
50: several mechanism labels ("Submit"); jargon at decision points. 20: labels mislead about
what actions do; critical info missing at the ask.
**trust_persuasion** — 90: trust signals present at high-stakes moments; zero dark patterns.
50: trust-signal gap at payment/data asks, or 1 minor dark pattern. 20: multiple dark
patterns (pre-checked costs, fake urgency, hidden fees) — this is a floor: any 2+ DARK
findings cap the category at 35.
