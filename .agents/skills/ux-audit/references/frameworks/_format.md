# Framework file format

Every file in this directory follows this structure. `build_registry.py` parses it;
violations fail registry generation.

```markdown
---
prefix: NLS                  # or comma-list for multi-prefix files (HICK, FITTS, ...)
framework: "Nielsen's 10 Usability Heuristics"
source: https://...
tier: [1, 2]                 # 1 static-screenshot · 2 flow · 3 behavioral(hypothesis-only)
category: usability          # usability | cognitive_load | visual_layout | accessibility
                             #   | content | trust_persuasion
---
## Principles
| ID | Name | Definition |
|---|---|---|
| NLS-01 | Visibility of system status | one-line definition |

## Screenshot-observable symptoms
**NLS-01** (tier 2 — needs flow): symptom; symptom; symptom
**NLS-06**: symptom; symptom

## Worked example
```json
{ "principles": ["NLS-06"], "severity": "medium", ... }
```
```

Rules:
- Files with `status: informational` in frontmatter are excluded from the registry and
  from evaluation entirely — they are background reading only (e.g. fogg.md).
- IDs are immutable once published (findings and fixtures cite them).
- Every Tier-1 principle needs ≥2 observable symptoms. Symptoms are concrete visual
  cues ("submit button with no pressed/disabled variant visible"), not restated theory.
- Tier-3 principles must say what data would validate a finding.
- ≤120 lines per file.
