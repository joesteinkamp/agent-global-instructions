---
prefix: RF
framework: "Recurring failures (custom named checks, seeded from Qualia's controlled list)"
source: ~/projects/qualia scripts/ux-audit/prompts (controlled principle list)
tier: [1, 2]
category: usability
---
Named categories for issues seen failing repeatedly, so the same issue gets flagged the
same way every time. Promote new entries from real audits (see CLAUDE.md maintenance loop).

## Principles
| ID | Name | Definition |
|---|---|---|
| RF-01 | False affordance | Looks interactive but isn't (or vice versa). |
| RF-02 | Dead-end state | A state with no path to a useful next action. |
| RF-03 | Unguarded destructive action | Delete/revoke/disconnect without confirmation or undo. |
| RF-04 | Vague CTA label | Button names the mechanism ("Submit") not the outcome ("Save changes"). |
| RF-05 | Silent success | Action completes with no acknowledgement. |
| RF-06 | Missing empty state | Blank region where first-run/empty content needs guidance. |
| RF-07 | Breadcrumb gap | No way to tell where you are in the structure. |
| RF-08 | Choice paralysis | Equal-weight options with no default or recommendation at a commitment point. |
| RF-09 | Trust-signal gap | High-stakes ask (payment, personal data) with no credibility cues. |
| RF-10 | Feedback latency | Long operation with no progress communication. |
| RF-11 | Confirmation trap | Dialog whose options are ambiguous about what is being confirmed. |
| RF-12 | Recall trap | User must remember information across screens that the UI could carry. |

## Screenshot-observable symptoms
**RF-01**: underlined/colored text that is plain copy; card with hover-style shadow but no action; ghost button that is a label.
**RF-02** (tier 2): error/empty screen with no CTA; final flow screen with no onward navigation.
**RF-03**: destructive verb with default/primary styling and no consequence copy or confirm affordance visible.
**RF-04**: "Submit/Continue/OK/Go" on consequential or paid actions.
**RF-05** (tier 2): screen after a save/send shows no acknowledgement of it.
**RF-06**: zero-data table/list rendered as bare emptiness, no explanation or starter action.
**RF-07**: deep content screen with no breadcrumb, title, or nav highlighting.
**RF-08**: 3+ plans/options visually identical in weight with no "recommended" or default.
**RF-09**: payment/identity form with no security cue, brand trust marks, or policy link.
**RF-10** (tier 2): heavy operation (export, processing) implied with no spinner/progress anywhere in sequence.
**RF-11**: confirm dialog with Yes/No on a negated question; both buttons styled equally on destructive confirm.
**RF-12**: code/value shown on one screen, required input on a later screen.

## Worked example
```json
{ "principles": ["RF-04", "CNT-01"], "severity": "medium",
  "issue": "The final checkout button reads 'Continue' although it places the order.",
  "why_it_matters": "Users expecting another review step get charged unexpectedly, creating disputes.",
  "recommendation": "Rename to 'Place order — $48.00'." }
```
