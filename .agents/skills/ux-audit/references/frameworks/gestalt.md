---
prefix: GST
framework: "Gestalt Principles of Grouping"
source: https://en.wikipedia.org/wiki/Principles_of_grouping
tier: [1]
category: visual_layout
---
## Principles
| ID | Name | Definition |
|---|---|---|
| GST-01 | Proximity | Elements close together are perceived as a group. |
| GST-02 | Similarity | Elements that look alike are perceived as related. |
| GST-03 | Closure | The mind completes incomplete figures. |
| GST-04 | Continuity | Aligned elements are read as a continuous unit or path. |
| GST-05 | Common fate | Elements moving/changing together are perceived as a group. |
| GST-06 | Prägnanz (good form) | Perception resolves to the simplest stable interpretation. |
| GST-07 | Common region | Elements inside a shared boundary are perceived as a group. |

## Screenshot-observable symptoms
**GST-01**: label closer to the wrong field than to its own; unrelated controls tighter together than related ones; CTA visually attached to the wrong card by spacing.
**GST-02**: links, buttons, and plain text sharing identical styling; same-styled cards with categorically different behaviors; one interactive element styled unlike its siblings for no semantic reason.
**GST-03**: truncated content with no visual cue that more exists (no fade/ellipsis/scroll affordance); carousel with no partial-item peek.
**GST-04**: form fields misaligned so the completion path zigzags; ragged column edges breaking table scanability.
**GST-05**: rarely judgeable from stills — only flag with multi-screen evidence (elements that change together across screens despite being unrelated).
**GST-06**: layout readable in multiple conflicting ways (is this one card or two?); ambiguous ownership of a shared divider.
**GST-07**: a border/background grouping items that don't belong together (price of plan A enclosed with plan B); related field cluster split across two visual containers.

## Worked example
```json
{ "principles": ["GST-07", "GST-01"], "severity": "high",
  "issue": "The 'Continue' button sits inside the promo banner's container, not the order form's.",
  "why_it_matters": "Users scanning the form container miss the primary action, reading it as part of the ad.",
  "recommendation": "Move the button inside the form card, below the final field." }
```
