---
prefix: GP
framework: "Gerhardt-Powals' Cognitive Engineering Principles"
source: https://en.wikipedia.org/wiki/Heuristic_evaluation
tier: [1]
category: cognitive_load
---
## Principles
| ID | Name | Definition |
|---|---|---|
| GP-01 | Automate unwanted workload | Eliminate mental calculations, estimations, and comparisons the system could do. |
| GP-02 | Reduce uncertainty | Display data clearly and obviously to cut decision time and error. |
| GP-03 | Fuse data | Combine lower-level data into higher-level summations. |
| GP-04 | Meaningful aids to interpretation | Present new information within familiar frameworks, schemas, metaphors. |
| GP-05 | Names conceptually related to function | Context-dependent labels that aid recognition. |
| GP-06 | Group data in consistently meaningful ways | Logical grouping within a screen; consistent grouping across screens. |
| GP-07 | Limit data-driven tasks | Use color and graphics to reduce time assimilating raw data. |
| GP-08 | Only information needed at a given time | Exclude extraneous information not relevant to current tasks. |
| GP-09 | Multiple coding of data | Offer data in varying formats and levels of detail where appropriate. |
| GP-10 | Judicious redundancy | Allow redundancy where it resolves conflicts between other principles. |

## Screenshot-observable symptoms
**GP-01**: user must mentally total prices/quantities the UI could sum; raw timestamps where relative time is the task; unit conversion left to the user.
**GP-02**: key value buried in a paragraph; status communicated only by subtle shade differences; truncated critical data.
**GP-03**: dashboard shows raw rows where the decision needs a single aggregate; no totals/rollups on data-dense tables.
**GP-04**: novel chart type with no legend; bespoke iconography for standard concepts; numbers without comparative baseline.
**GP-05**: generic labels ("Item 1", "Option A", "Data") on functional controls; buttons named after mechanism not outcome.
**GP-06**: related fields scattered across the layout; group boundaries that disagree with semantic relationships.
**GP-07**: wall of undifferentiated numbers/text where color or sparkline encoding is conventional.
**GP-08**: admin/meta detail (IDs, internal flags) shown on an end-user task screen; rarely needed settings inline with a primary task.
**GP-09**: percentage-only display where absolute values matter (or vice versa) for the stated goal.
**GP-10**: status communicated by exactly one weak channel when the cost of misreading is high (overlaps WCAG-1.4.1 — cite both).

## Worked example
```json
{ "principles": ["GP-01"], "severity": "medium",
  "issue": "The cart shows per-item prices but no order total before checkout.",
  "why_it_matters": "Users must mentally sum costs to decide, which slows commitment and causes sticker-shock abandons later.",
  "recommendation": "Add a running total adjacent to the checkout CTA." }
```
