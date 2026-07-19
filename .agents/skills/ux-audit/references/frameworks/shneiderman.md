---
prefix: SHN
framework: "Shneiderman's 8 Golden Rules of Interface Design"
source: https://www.cs.umd.edu/~ben/goldenrules.html
tier: [2]
category: usability
---
## Principles
| ID | Name | Definition |
|---|---|---|
| SHN-01 | Strive for consistency | Consistent action sequences, terminology, and layout in similar situations. |
| SHN-02 | Seek universal usability | Serve diverse users: novices, experts, ages, disabilities, devices. |
| SHN-03 | Offer informative feedback | Every user action gets proportionate interface feedback. |
| SHN-04 | Design dialogs to yield closure | Action sequences have a clear beginning, middle, and end with a sense of completion. |
| SHN-05 | Prevent errors | Block serious errors; give simple, constructive, specific recovery instructions. |
| SHN-06 | Permit easy reversal of actions | Reversibility relieves anxiety; errors can be undone. |
| SHN-07 | Keep users in control | Predictable responses; no surprises or unwanted automation. |
| SHN-08 | Reduce short-term memory load | Don't require remembering information from one display to use on another. |

## Screenshot-observable symptoms
**SHN-01**: same operation styled or labeled differently across screens; navigation items reordered between screens.
**SHN-02**: tiny touch targets or text on a mobile artifact; expert-only density with no novice path (single screen ok).
**SHN-03**: form submit with no visible success/progress treatment on the next screen; state-changing toggle with no confirmation cue.
**SHN-04**: flow ends without a confirmation/summary screen ("did it work?"); checkout with no order-confirmation step in the sequence.
**SHN-05**: irreversible step with no review screen before commit; ambiguous defaults pre-selected on consequential choices.
**SHN-06**: destructive action confirmed but no undo anywhere in the sequence; "this cannot be undone" with no draft/save path.
**SHN-07**: auto-advancing or auto-selecting behavior implied by UI (auto-applied coupon, auto-renew preselected) without user initiation.
**SHN-08**: code/value displayed on screen N that must be typed on screen N+1; comparison task split across screens with no summary.

## Worked example
```json
{ "principles": ["SHN-04"], "severity": "high", "screen_index": null,
  "issue": "The signup flow ends on the dashboard with no confirmation that the account was created.",
  "why_it_matters": "Users can't tell whether signup succeeded, driving support contacts and duplicate accounts.",
  "recommendation": "Add a confirmation state naming the created account before landing on the dashboard." }
```
