---
prefix: WCAG
framework: "WCAG 2.1 — screenshot-auditable subset"
source: https://www.w3.org/WAI/WCAG21/quickref/
tier: [1]
category: accessibility
---
## Principles
| ID | Name | Definition |
|---|---|---|
| WCAG-1.1.1 | Non-text Content (A) | Non-text content has a text alternative. |
| WCAG-1.3.1 | Info and Relationships (A) | Visually conveyed structure is programmatically determinable. |
| WCAG-1.4.1 | Use of Color (A) | Color is not the only means of conveying information. |
| WCAG-1.4.3 | Contrast Minimum (AA) | Text contrast ≥4.5:1 (≥3:1 for large text ≥24px or 19px bold). |
| WCAG-1.4.4 | Resize Text (AA) | Text resizable to 200% without loss of content or function. |
| WCAG-1.4.11 | Non-text Contrast (AA) | UI components and graphics ≥3:1 against adjacent colors. |
| WCAG-2.5.8 | Target Size Minimum (AA, 2.2) | Pointer targets ≥24x24 CSS px (44x44 best practice on touch). |
| WCAG-3.3.2 | Labels or Instructions (A) | Labels or instructions wherever content requires input. |

## Hard rules (verbatim policy from the Qualia rubric)
1. Accessibility findings live ONLY in the accessibility category — never duplicated in
   other categories (a finding may co-cite, e.g. FITTS-01 + WCAG-2.5.8, but is filed once).
2. Numeric claims (ratios, px) REQUIRE measure.py evidence. Without a measurement, phrase
   as "appears low-contrast — verify" at medium severity max.
3. Only flag visually unambiguous violations:
   - form inputs with NO visible label text (placeholder-only counts as unlabeled)
   - status/category communicated ONLY by color, no text or icon
   - measured contrast below threshold
   - measured interactive targets below 24px (44px on declared-touch platform)
4. Do NOT infer focus indicators, alt text, ARIA, keyboard order, or anything invisible
   in a static image. Those need code or live interaction — out of scope, say so in the
   report's methodology note.

## Screenshot-observable symptoms
**WCAG-1.1.1**: informational chart/image with no visible caption or text equivalent.
**WCAG-1.3.1**: visual heading hierarchy that skips/contradicts itself (judgment, low severity).
**WCAG-1.4.1**: required fields marked only by color; chart series distinguished only by hue; error state shown only by red border.
**WCAG-1.4.3 / 1.4.11**: measured ratio below threshold for text / for control boundaries and icons.
**WCAG-2.5.8**: measured target below minimum; dense icon rows with sub-24px hit areas.
**WCAG-3.3.2**: placeholder-only inputs; unlabeled selects; format requirements not stated for constrained fields.

## Worked example
```json
{ "principles": ["WCAG-3.3.2"], "severity": "high", "category": "accessibility",
  "issue": "All four checkout inputs use placeholder text as their only label.",
  "why_it_matters": "Labels vanish on focus, so users (and screen readers) lose field identity mid-entry.",
  "recommendation": "Add persistent visible labels above each input." }
```
