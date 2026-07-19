---
prefix: TOG
framework: "Tognazzini's First Principles of Interaction Design"
source: https://asktog.com/atc/principles-of-interaction-design/
tier: [1, 2]
category: usability
---
## Principles
| ID | Name | Definition |
|---|---|---|
| TOG-01 | Aesthetics | Visual design enhances, never compromises, usability. |
| TOG-02 | Anticipation | Bring all needed info and tools to each step. |
| TOG-03 | Autonomy | Users control their environment within helpful guardrails. |
| TOG-04 | Color | Color as a vital cue — always with a secondary cue. |
| TOG-05 | Consistency | Strict consistency where it matters most. |
| TOG-06 | Defaults | Intelligent, easily overridable, clearly named defaults. |
| TOG-07 | Discoverability | Controls visible; no fake simplicity by hiding capability. |
| TOG-08 | Efficiency of the user | Optimize human productivity, not machine efficiency. |
| TOG-09 | Explorable interfaces | Clear paths, reversible actions, obvious exits. |
| TOG-10 | Fitts's Law | Minimize target acquisition time (see FITTS-01). |
| TOG-11 | Human-interface objects | Standard behaviors and consistent meanings. |
| TOG-12 | Latency reduction | Acknowledge actions instantly; inform users of waits. |
| TOG-13 | Learnability | Balance learning curve against frequency of use. |
| TOG-14 | Metaphors | Real-world connections without literalism. |
| TOG-15 | Protect users' work | Users never lose work to error or design oversight. |
| TOG-16 | Readability | High contrast, sufficient type size, scannable hierarchy. |
| TOG-17 | Simplicity | No false simplicity that hides needed capability. |
| TOG-18 | State | Track history, location, preferences across sessions. |
| TOG-19 | Visible navigation | Show navigational structure to prevent disorientation. |

## Screenshot-observable symptoms
**TOG-01**: decorative treatment obscuring content (text over busy imagery); style flourishes reducing control legibility.
**TOG-02** (tier 2): step requires data/tools shown only on another screen; no inline summary at a decision point.
**TOG-04**: status/category encoded by color alone (cite WCAG-1.4.1 together).
**TOG-06**: consequential defaults pre-selected against user interest; defaults named vaguely ("Standard").
**TOG-07**: primary capability hidden behind unlabeled overflow menus on desktop.
**TOG-09** (tier 2): modal/flow with no visible exit; irreversible-looking step without reassurance.
**TOG-12** (tier 2): heavy operation implied with no progress affordance anywhere in sequence.
**TOG-14**: metaphor that contradicts behavior (trash icon that permanently deletes — needs flow/copy evidence).
**TOG-15** (tier 2): long form with no save-draft cue; warning that leaving loses work, with no alternative.
**TOG-16**: body text under ~14px or low contrast (cite measured values with WCAG-1.4.3); centered long-form paragraphs; hierarchy invisible when squinting.
**TOG-19**: no cue of current location within the product; sections with identical headers and no breadcrumb on deep content.
Scope note: TOG-08 efficiency and TOG-13 learnability need timed studies — only flag
visible symptoms (e.g. forced wizard for a trivial task), never timing/learning claims.

## Worked example
```json
{ "principles": ["TOG-16", "WCAG-1.4.3"], "severity": "high",
  "issue": "Body copy is #9aa3ae on white at a measured 2.6:1 contrast.",
  "why_it_matters": "Most users strain to read core content; low-vision users cannot read it at all.",
  "recommendation": "Darken body text to reach at least 4.5:1.",
  "evidence": "measured: contrast 2.6:1 (#9aa3ae on #ffffff)" }
```
