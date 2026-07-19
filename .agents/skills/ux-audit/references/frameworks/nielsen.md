---
prefix: NLS
framework: "Nielsen's 10 Usability Heuristics"
source: https://www.nngroup.com/articles/ten-usability-heuristics/
tier: [1, 2]
category: usability
---
## Principles
| ID | Name | Definition |
|---|---|---|
| NLS-01 | Visibility of system status | Keep users informed about what is going on through timely, appropriate feedback. |
| NLS-02 | Match between system and real world | Speak the user's language; familiar words and concepts, not internal jargon. |
| NLS-03 | User control and freedom | Provide a clearly marked emergency exit; support undo and redo. |
| NLS-04 | Consistency and standards | Same words/actions mean the same thing; follow platform and industry conventions. |
| NLS-05 | Error prevention | Prevent problems before they occur; confirm before error-prone or destructive actions. |
| NLS-06 | Recognition rather than recall | Minimize memory load; keep options, actions, and needed info visible. |
| NLS-07 | Flexibility and efficiency of use | Shortcuts and accelerators for experts without burdening novices. |
| NLS-08 | Aesthetic and minimalist design | No information that is irrelevant or rarely needed competing for attention. |
| NLS-09 | Help users recognize, diagnose, recover from errors | Plain-language error messages that state the problem and a solution. |
| NLS-10 | Help and documentation | Ideally none needed; if present, contextual, concise, task-focused. |

## Screenshot-observable symptoms
**NLS-01** (tier 2 — needs flow): action on screen N gets no acknowledgement on screen N+1; multi-step process with no progress indicator; single screen: async-looking action (upload, pay) with no visible loading/disabled affordance.
**NLS-02**: internal jargon in labels ("SKU sync delta"); system codes shown to users; icons with unconventional meanings and no text.
**NLS-03** (tier 2): no visible cancel/back on a multi-step or modal flow; destructive action with no undo path mentioned; exit hidden below the fold.
**NLS-04** (tier 2): same action labeled differently across screens; primary-button style switches color/position between screens; mixed terminology for one concept.
**NLS-05** (tier 2): destructive button (delete, revoke) with no confirmation affordance visible; irreversible step not marked; free-text input where a constrained picker is conventional.
**NLS-06**: form asks for information shown on a previous screen; user must remember a code/value between steps; options hidden behind unlabeled icons.
**NLS-07**: none reliably visible in static screens — flag only with flow evidence (e.g., forced wizard for a trivially short task).
**NLS-08**: promotional or secondary content visually competing with the primary task; >2 sidebars/banners adjacent to a focused task like checkout.
**NLS-09** (tier 2): error state shows codes ("Error 400") or blames the user without a fix; validation message far from the offending field.
**NLS-10**: dense form with zero helper text where domain knowledge is required; help link absent on a screen asking for unusual input.

## Worked example
```json
{ "principles": ["NLS-06"], "severity": "medium",
  "issue": "Payment step asks users to re-enter the shipping address shown two steps earlier.",
  "why_it_matters": "Recall and retyping add friction and typos exactly where abandonment is most expensive.",
  "recommendation": "Pre-fill the address from step 1 with an 'edit' affordance." }
```
