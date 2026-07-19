# UX audit — Pro plan pricing page (dark patterns) — 2026-06-11
**Overall: 57/100** (broken flows; users likely abandon) · mode: single · 8 findings, 0 hypotheses
**One big thing:** The screen withholds its one decision-critical fact — the actual charge ($108 today plus a $14/mo add-on) appears nowhere readable — while urgency devices push commitment before that fact can be found.

| Category | Score | Top issue |
|---|---|---|
| usability | 76 | — clean |
| cognitive_load | 52 | True first charge never computed for the user |
| visual_layout | 85 | — clean |
| accessibility | 42 | 10px, 1.77:1 footnote hides the real price |
| content | 35 | CTA omits the actual charge |
| trust_persuasion | 20 | Four dark patterns (urgency, pre-check, confirmshaming, hidden fees) |

## Top findings
1. **[high] A countdown timer and 'Only 2 licenses left!' manufacture urgency for an unlimited digital license.** — Remove the countdown and license counter, or state a verifiable basis for each. (Fake scarcity/urgency, Scarcity)
2. **[high] The footnote contradicting the '$9/mo' headline is 10px text at 1.77:1 contrast.** — State 'billed annually at $108' beside the price at body size and AA contrast. (Hidden costs, WCAG Contrast Minimum)
3. **[high] The $14/mo Priority Support add-on is pre-checked.** — Default the add-on to unchecked. (Pre-checked commitment)
4. **[medium] The true first charge is never computed; users must assemble headline, footnote, and add-on themselves.** — Show a computed total due today directly above the CTA. (Automate unwanted workload, Reduce uncertainty)
5. **[medium] 'Upgrade now' commits the user without stating the charge: $108 today plus the add-on.** — State the real total on the button, e.g. 'Upgrade — $108/year'. (Error prevention copy, Visibility of system status copy)

Not auditable from a static screenshot: focus order, ARIA, keyboard access, whether the countdown resets on reload.

Full report: report.html · machine-readable: findings.json
