# UX audit — flow-signup — 2026-06-11
**Overall: 68/100** (functional, unremarkable) · mode: flow (4 screens) · 7 findings, 0 hypotheses

**One big thing:** No step in this flow ever acknowledges that the previous step worked:
the CTA rename, the unmarked plan selection, and the silent landing on an empty dashboard
are three symptoms of the same missing-acknowledgement spine.

| Category | Score | Top issue |
|---|---|---|
| Usability | 54 | CTA renames mid-flow; signup never confirmed; dashboard dead-ends |
| Cognitive load | 58 | Four undifferentiated plans, no default |
| Visual & layout | 85 | Each screen individually clean |
| Accessibility | 86 | Labeled inputs; measured contrast passes (5.17:1, 5.47:1) |
| Content | 70 | The flow's key verb changes name mid-journey |
| Trust & persuasion | 72 | Paid commitment with no cancel/change reassurance |

## Top findings
1. **[high] The flow's primary action renames itself from 'Create account' to 'Register now' mid-journey.**
   — Use one verb for one commitment across all steps. (NLS-04, SHN-01, CNT-04)
2. **[high] The flow ends with no confirmation that the account or plan was created.**
   — Acknowledge the created account and chosen plan before or on the dashboard. (SHN-04, NLS-01, RF-05)
3. **[medium] The multi-step signup shows no progress indication anywhere.**
   — Add a step indicator to the form and plan screens. (NLS-01, TOG-19)
4. **[high] Four equally weighted plans offer no default or recommendation at the commitment point.**
   — Mark one plan as recommended and preselect it. (RF-08, HICK-01)
5. **[high] The dashboard greets new users with a large empty box and no next action.**
   — Add a first-run state with a "Plan your first trip" action. (RF-06, RF-02)

Flow: 0→1 ok · 1→2 issue (rename, no acknowledgement) · 2→3 issue (silent landing).
Missing states: signup confirmation, plan selected-state, first-run dashboard, form errors.
Peak–end: the journey ends at its weakest moment.

Full report: report.html · machine-readable: findings.json
