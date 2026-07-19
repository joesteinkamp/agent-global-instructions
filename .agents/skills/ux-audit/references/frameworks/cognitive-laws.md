---
prefix: HICK, FITTS, MILL, JAKOB, PEAK
framework: "Cognitive laws (Hick, Fitts, Miller, Jakob, Peak-End)"
source: https://lawsofux.com/
tier: [1, 2]
category: cognitive_load
---
## Principles
| ID | Name | Definition |
|---|---|---|
| HICK-01 | Hick's Law | Decision time grows with the number and complexity of choices. |
| FITTS-01 | Fitts's Law | Target acquisition time is a function of distance to and size of the target. |
| MILL-01 | Miller's Law | Working memory holds ~7±2 items; chunk content to aid processing. |
| JAKOB-01 | Jakob's Law | Users expect your product to work like the products they already know. |
| PEAK-01 | Peak-End Rule | Experiences are judged by their most intense moment and their ending. |

## Screenshot-observable symptoms
**HICK-01**: >7 equally weighted choices at a single decision point with no recommended/default option; flat menus mixing frequent and rare actions; multiple plans/options with no comparison guidance.
**FITTS-01**: small targets (<~24px desktop, <~44px touch) — cite measured size from measure.py, with WCAG-2.5.8; tappable items packed without spacing; primary action far from the workflow's locus while a destructive action sits adjacent to a frequent one.
**MILL-01**: unchunked long codes/numbers displayed for transcription; >7 unrelated items in one undifferentiated list the user must compare. Misapplication warning: do NOT flag "more than 7 menu items" as a violation per se — chunking, not count, is the issue.
**JAKOB-01**: standard controls in unconventional locations (cart top-left, close button bottom); novel interaction metaphors for solved problems (custom-drawn non-standard form controls); link styling on non-links.
**PEAK-01** (tier 2): flow's final screen is a dead end or form rather than confirmation/accomplishment; the likely emotional peak (payment, error) has the weakest design investment in the sequence.

## Scope note (informational)
Timing claims ("this menu slows users by X") require analytics or timed studies and are
NOT evaluated — never assert them. Visible symptoms above are fair Tier-1/2 findings.

## Worked example
```json
{ "principles": ["FITTS-01", "WCAG-2.5.8"], "severity": "high",
  "issue": "Player control icons are 18px and 4px apart on a touch screen.",
  "why_it_matters": "Mis-taps on adjacent controls cause errors at the product's most-used moment.",
  "recommendation": "Enlarge targets to 44px minimum and add 8px spacing.",
  "evidence": "measured: targets 18x18px, gap 4px" }
```
