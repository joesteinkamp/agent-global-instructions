# UX audit — flawed-checkout — 2026-06-11
**Overall: 51/100** (broken flows) · mode: single · 9 findings, 0 hypotheses

**One big thing:** The commitment moment is undecidable: three identical, washed-out,
mechanism-named buttons with no visible order total mean a first-time buyer cannot tell
which action takes their money or how much it will take.

| Category | Score | Top issue |
|---|---|---|
| Usability | 52 | Three identical primary buttons compete at the commitment point |
| Cognitive load | 55 | Order summary has no total |
| Visual & layout | 72 | CTA row is the only focal-point conflict |
| Accessibility | 28 | CTA text 1.78:1; four placeholder-only inputs |
| Content | 50 | Paying action labeled "Submit" |
| Trust & persuasion | 50 | Card entry with no security cues |

## Top findings
1. **[high] All four payment inputs rely on placeholder text as their only label.** —
   Add persistent visible labels above each input. (WCAG-3.3.2, NRM-06)
2. **[high] Button text contrast is 1.78:1, far below the 4.5:1 minimum.** —
   Darken the button fill to reach at least 4.5:1 against white text. (WCAG-1.4.3, TOG-16)
3. **[high] Three identically styled primary buttons compete at the single commitment point.** —
   Keep one primary payment button; demote the others to secondary styles. (RF-08, NRM-06, GST-02)
4. **[medium] Remove links render at 1.85:1 contrast and roughly 8px text height.** —
   Restyle remove links to at least 4.5:1 contrast and 13px. (WCAG-1.4.3)
5. **[medium] The paying action is labeled 'Submit' instead of naming its outcome.** —
   Rename to "Pay $242.00" once the total is computed. (RF-04, CNT-01)

Full report: report.html · machine-readable: findings.json
