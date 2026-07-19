---
prefix: NRM
framework: "Norman's Design Principles (The Design of Everyday Things)"
source: https://en.wikipedia.org/wiki/The_Design_of_Everyday_Things
tier: [1, 2]
category: usability
---
## Principles
| ID | Name | Definition |
|---|---|---|
| NRM-01 | Affordances | What interactions an element actually supports. |
| NRM-02 | Signifiers | Visible cues signaling what an element does and how to use it. |
| NRM-03 | Mapping | Relationship between controls and effects is spatially/logically evident. |
| NRM-04 | Feedback | Full, continuous feedback about the results of actions. |
| NRM-05 | Conceptual model | The design communicates a coherent model of how the system works. |
| NRM-06 | Visibility | By looking, users can tell the state and the available actions. |
| NRM-07 | Constraints | Limit possible actions to guide correct use. |
| NRM-GE | Gulf of execution | Gap between user intent and the actions the UI makes discoverable. |
| NRM-GV | Gulf of evaluation | Effort needed to interpret what state the system is in after acting. |

## Screenshot-observable symptoms
**NRM-02**: clickable element with no interactive styling (flat text that is a button); decorative element styled like a control (false affordance — cite RF-01 too); icon-only controls without labels for non-universal icons.
**NRM-03**: controls ordered/positioned unrelated to the things they affect; settings toggle far from the feature it governs; arrows/steppers whose direction contradicts the value change.
**NRM-04** (tier 2): state-changing action with no visible result on the following screen; toggle whose on/off states look near-identical.
**NRM-05**: screen mixes two metaphors for the same data (files as both list and unrelated cards); navigation that implies a hierarchy that contents contradict.
**NRM-06**: current selection/active state visually indistinguishable; disabled vs enabled controls look identical; no cue which step of a process the user is on.
**NRM-07**: free-form input where only constrained values are valid, with no mask/picker; deletable/editable affordances on read-only data.
**NRM-GE / NRM-GV** (tier 2): use as diagnosis labels when a multi-screen finding is fundamentally "user can't see how to do X" (GE) or "user can't tell what happened" (GV).

## Worked example
```json
{ "principles": ["NRM-06"], "severity": "medium",
  "issue": "The active tab is styled identically to inactive tabs.",
  "why_it_matters": "Users can't tell where they are, so they re-click and misread which data they're viewing.",
  "recommendation": "Differentiate the active tab with weight and an underline, not color alone." }
```
