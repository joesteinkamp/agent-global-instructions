# The four-gate filter

<!-- Gates verbatim from Qualia's ALISSA prime directive (analyze-prompts.ts). -->
Apply to EVERY candidate finding before it enters findings.json. A candidate that fails
any gate is dropped silently — it does not appear as a low-severity finding instead.

1. **BLOCKER CHECK** — Does this specifically impede the user's stated goal? If it has no
   plausible path to harming goal completion, confidence, or trust, ignore it.
2. **STANDARD CHECK** — Is this a standard, conventional pattern? Do NOT flag conventional
   patterns (standard form layouts, breadcrumbs, hamburger on mobile, footer link walls).
3. **CLUTTER CHECK** — Does the suggestion add a new button/modal/element when existing UI
   already provides a path? Prefer fixing what exists. Do not suggest new elements unless
   nothing serves the need.
4. **STEELMAN CHECK** — State internally why a reasonable designer might have made this
   choice intentionally. Only flag if the steelman is weak or the tradeoff clearly harms
   the user goal.

## Worked drop examples (one per gate)
- **Blocker drop:** "The footer copyright text is small." Goal: complete checkout. No path
  to harm. Dropped.
- **Standard drop:** "Consider adding breadcrumbs to this single-step settings page."
  Standard pattern is fine without them; flat pages don't need wayfinding. Dropped.
- **Clutter drop:** "Add a 'Back to cart' button to the payment step." A cart link already
  exists in the header summary. Dropped — or refile as "make the existing cart link more
  visible" only if it also passes Blocker.
- **Steelman drop:** "The plan comparison hides enterprise pricing behind 'Contact us'."
  Steelman: enterprise pricing is negotiated; a number would mislead. Strong steelman,
  no clear user harm. Dropped.

## Additional output rules
- Cross-framework duplicates merge into ONE finding with multiple citations
  (low-contrast unlabeled button = one finding citing WCAG-1.4.3 + NRM-02, filed in the
  accessibility category if any WCAG ID is cited, else the first principle's category).
- Cap: ≤5 findings per category, kept by importance. Log overflow count in the report's
  methodology note (no silent truncation).
- A clean screen is a valid result. Never manufacture findings to look thorough; record
  what passed in `clean_checks` instead.
