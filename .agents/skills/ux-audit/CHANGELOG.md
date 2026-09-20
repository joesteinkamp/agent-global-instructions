# Change Log

AI-made changes, recorded as decisions: what changed, the ask that prompted it, why
this approach, and what was considered and rejected.

## 2026-07-23 — v2 traceability schema: scores must cite their evidence

**What changed.** findings.json gained four blocks: `score_evidence` per category
(band + drivers + passes + limitations), `path_to_excellent` (post-fix projection
capped at 89 while anything is unverifiable + verification backlog),
`meta.candidate_stats` (the generated → gate-dropped → merged → capped → reported
funnel), and `meta.data_fidelity` (split from stage; folded into the Stage intake
question). validate_findings.py enforces all of it as hard failures: overall =
weighted average ±1; score <90 needs a driver or limitation; ≥90 needs documented
passes; funnel arithmetic must add up; plus band↔severity consistency derived from
the verbatim band text (overall ≤49 requires a critical finding; any critical caps
overall at 65; ≥90 requires zero critical/high; 2+ DARK findings cap trust at 35).
The report template shows score drivers as visible links beside each bar, a "Path to
excellent" panel, a "why this list is short" funnel line, and coverage counted as
"principles with a recorded outcome" instead of treating every un-cited principle as
examined. All five fixture audits retrofitted (`candidate_stats: null` — their
funnels were never recorded and counts are not invented).

**The ask.** A real audit scored 48/100 but reported only 5 findings — fixing five
things clearly wouldn't reach 100, and nothing in the output explained the gap.
Cross-checked against an external (Codex) review brief whose P0 items this adopts.

**Why this approach.** The gap is structural: scores come from holistic calibration
bands (whole-design quality) while findings pass four filter gates plus a
5-per-category cap (top defects only). So the fix is evidence plumbing — make the
score traceable and the remainder explicit — not more output. A 48 with zero
critical findings is now a validation error ("file the blocker or rescore"), which
is exactly the audit that prompted this.

**Considered and rejected.**
- *More frameworks / more heuristics* — 110 principles was never the bottleneck.
- *Loosening the filter gates or the cap to emit more findings* — would break the
  Qualia-verbatim calibration; the gates are copied, not paraphrased, by design.
- *A `band_override` field* (per the Codex brief) — contradicts Qualia's verbatim
  rule that when band and math disagree you revisit sub-scores, never hand-adjust
  the overall.
- Deferred, not rejected: template axe-core hardening, measurement provenance
  (auto vs targeted probes), persona split (familiarity × domain expertise),
  task-archetype anchors, and schema-v2 regression fixtures (write those after the
  first live audit on this schema).
