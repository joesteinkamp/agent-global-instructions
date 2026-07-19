---
prefix: CNT
framework: "10 Content Design Heuristics"
source: https://uxcontent.com/10-content-design-heuristics/
tier: [1, 2]
category: content
---
## Principles
| ID | Name | Definition |
|---|---|---|
| CNT-01 | Visibility of system status (copy) | Copy tells users what's happening; no unexplained interactions. |
| CNT-02 | Match the real world (copy) | User's language, not org jargon. |
| CNT-03 | User control and freedom (copy) | Exits, undo, and reversal are clearly labeled and explained. |
| CNT-04 | Consistency and standards (copy) | Uniform terminology; copy matches one voice and style. |
| CNT-05 | Error prevention (copy) | Communicate consequences of destructive actions before commitment. |
| CNT-06 | Recognition over recall (copy) | Present needed info in the moment; don't reference unseen content. |
| CNT-07 | Flexibility and efficiency (copy) | Copy serves both novices and experts. |
| CNT-08 | Minimalist copy | Focused pages; cut extraneous words. |
| CNT-09 | Error recovery (copy) | Plain-language error messages with an actionable fix. |
| CNT-10 | Help and documentation (copy) | Timely, scannable helper text where tasks need it. |

## Screenshot-observable symptoms
**CNT-01**: buttons that don't name their outcome ("Submit", "Continue", "OK" on consequential actions); link text that hides destination ("click here").
**CNT-02**: internal jargon, abbreviations, or legalese in user-facing copy; error codes as primary message.
**CNT-03** (tier 2): cancel/close affordances with ambiguous labels ("Cancel" on a cancel-subscription dialog — cancel what?).
**CNT-04**: one concept, multiple names within visible screens ("workspace" vs "project"); inconsistent capitalization/tone between adjacent elements.
**CNT-05**: destructive button with no consequence statement nearby ("Delete" with no "this removes X permanently").
**CNT-06**: copy referencing controls or info not visible ("as described above" when it isn't); instructions naming UI that isn't on screen.
**CNT-08**: redundant filler ("Please note that…"); marketing copy inside task flows; three sentences where a label would do.
**CNT-09** (tier 2): error text that blames or dead-ends ("Something went wrong") with no next step.
**CNT-10**: complex/constrained field with no inline hint or example format.

## Worked example
```json
{ "principles": ["CNT-01"], "severity": "medium",
  "issue": "The payment button is labeled 'Submit' rather than naming the outcome.",
  "why_it_matters": "Users hesitate at the highest-stakes click because the label doesn't say what happens or what they'll be charged.",
  "recommendation": "Rename to 'Pay $48.00 now'." }
```
