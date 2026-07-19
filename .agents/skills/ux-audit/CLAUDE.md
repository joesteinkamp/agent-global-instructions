# ux-audit-skill — conventions

This repo IS the `/ux-audit` skill package (SKILL.md at root). Installed for use via
symlink: `~/.claude/skills/ux-audit -> ~/projects/ux-audit-skill`.

## Sources of truth
- `references/report-spec.md` owns the findings.json schema. Scripts validate against it;
  SKILL.md links to it and must never restate it.
- `references/registry.json` (generated — never hand-edit) is the controlled citation
  vocabulary. Regenerate after any framework file change:
  `.venv/bin/python scripts/build_registry.py`
- Design plan: `plan.html` · Execution plan: `execution-plan.html` (milestones M0–M7).

## Hard rules
- **Qualia-verbatim rule:** the filter gates (filter.md), severity definitions, calibration
  bands, and conciseness contract (scoring.md, report-spec.md) are copied from
  `~/projects/qualia` rubrics. Do NOT paraphrase them — Qualia's docs warn paraphrasing
  breaks calibration. Files note provenance in a comment.
- **No invented numbers:** numeric WCAG/contrast/size claims require `measure.py` evidence.
- Framework files ≤120 lines each; SKILL.md ≤150 lines (progressive disclosure keeps
  per-audit context small).
- Scripts: Python stdlib + Pillow only, must run offline. CLI contracts live in
  `scripts/README.md` and execution-plan.html Appendix A — change both in the same commit
  or don't change them.

## Workflows
- Run scripts with `.venv/bin/python` (Pillow lives in `.venv`).
- After any prompt/reference change: regenerate registry, then run the fixture check:
  `.venv/bin/python scripts/check_fixtures.py fixtures/`
- Script unit tests: `.venv/bin/python scripts/tests/test_measure.py`
- Maintenance loop: when a real-world failure pattern recurs, promote it into
  `references/frameworks/recurring-failures.md` with a new RF-ID and ≥2 observable
  symptoms, then regenerate the registry.
