# UX audit — Mobile player (small targets) — 2026-06-11
**Overall: 75/100** (functional, standard design) · mode: single · 2 findings, 0 hypotheses
**One big thing:** Hit areas were sized for a desktop cursor, not a thumb: every interactive element measures under half the 44px touch minimum while all static text passes its checks.

| Category | Score | Top issue |
|---|---|---|
| usability | 75 | Transport controls invite mis-taps |
| cognitive_load | 88 | — clean |
| visual_layout | 86 | — clean |
| accessibility | 30 | 19px playback controls on a touch screen |
| content | 85 | — clean |
| trust_persuasion | 90 | — clean |

## Top findings
1. **[high] All five playback controls are 19px squares, far below the 44px touch minimum.** — Enlarge each control to at least 44x44px and add spacing between them. (WCAG Target Size Minimum, Fitts's Law)
2. **[medium] The four secondary links are 10px-tall tap targets packed into a single row.** — Give each link a 44px-tall tap area with wider separation. (WCAG Target Size Minimum, Fitts's Law)

Not auditable from a static screenshot: focus order, ARIA, keyboard access, real timing.

Full report: report.html · machine-readable: findings.json
