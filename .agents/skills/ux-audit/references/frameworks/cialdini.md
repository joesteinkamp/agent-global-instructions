---
prefix: CLD, DARK
framework: "Cialdini's Principles of Influence + dark-pattern checks"
source: https://fs.blog/influence-psychology-persuasion/
tier: [1]
category: trust_persuasion
---
## Principles
| ID | Name | Definition |
|---|---|---|
| CLD-01 | Reciprocation | People feel obliged to return favors. |
| CLD-02 | Commitment & consistency | People act consistently with prior commitments. |
| CLD-03 | Social proof | Under uncertainty, people copy others' behavior. |
| CLD-04 | Liking | People are persuaded by those they like or relate to. |
| CLD-05 | Authority | Credible expertise and symbols persuade. |
| CLD-06 | Scarcity | Rarity and deadlines increase desire. |

Dark-pattern checks — unethical applications, visible as artifacts (Tier 1):
| ID | Name | Definition |
|---|---|---|
| DARK-01 | Fake scarcity/urgency | Countdown timers or stock counts implausible for the product (e.g. "2 left" of a digital good). |
| DARK-02 | Manufactured social proof | Unverifiable activity feeds, suspiciously round or unsourced popularity claims. |
| DARK-03 | Pre-checked commitment | Opt-ins, add-ons, or renewals pre-selected against user interest. |
| DARK-04 | Confirmshaming | Decline option worded to shame ("No thanks, I hate saving money"). |
| DARK-05 | Forced continuity / hidden exit | Easy entry, buried or absent cancellation path. |
| DARK-06 | Hidden costs | Fees revealed late, asterisked, or visually minimized at decision points. |

## Screenshot-observable symptoms
**DARK-01**: countdowns with no stated basis; "limited stock" on digital/unlimited goods; urgency styling (red, pulsing) on routine actions.
**DARK-02**: "12,438 people bought this today" with no source; testimonial walls without attribution.
**DARK-03**: any pre-ticked checkbox that adds cost or grants data/marketing consent.
**DARK-04**: asymmetric choice styling plus shaming decline copy.
**DARK-05** (tier 2): subscription signup screens with no visible mention of how to cancel.
**DARK-06**: total at CTA differs from advertised price; fees in fine print only; strikethrough anchor prices with implausible discounts.
Positive CLD checks: missing trust signals at high-commitment moments (no security cue at payment,
no social proof on an unknown brand's signup) — flag as trust-signal gap citing CLD-03/CLD-05 + RF-09.

## Scope note (informational)
Whether persuasion elements WORK (lift conversion, backfire via reactance) is an A/B
question and is NOT evaluated by this skill — never claim effectiveness. The PRESENCE
of dark patterns (DARK-01…06) is an observed Tier-1 finding and scores normally.

## Worked example
```json
{ "principles": ["DARK-03"], "severity": "high",
  "issue": "The $14/mo 'Priority support' add-on is pre-checked at checkout.",
  "why_it_matters": "Users who miss it pay for an unrequested service, driving chargebacks and trust collapse.",
  "recommendation": "Make the add-on opt-in, unchecked by default." }
```
