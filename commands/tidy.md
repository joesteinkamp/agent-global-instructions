---
description: Run the project's formatter, linter, and tests; fix what's safe
allowed-tools: Bash, Read, Edit, Glob, Grep
---

Tidy up the code in this project.

Steps:
1. Detect the project's tooling — check `package.json` scripts, and for configs
   like `prettier`, `eslint`, `ruff`, `black`, `gofmt`, `rubocop`, a `Makefile`,
   etc. Prefer the project's own scripts (e.g. `npm run lint`, `npm test`).
2. Run, in order: formatter → linter → tests.
3. Auto-fix what's safe (formatting, lint autofixes, obvious mistakes). Leave
   anything ambiguous or behavior-changing for me — list those instead.
4. Do NOT commit — leave the changes staged-or-unstaged for me to review (use
   `/ship` or `/save` after).
5. Report: what you ran, what you fixed, and anything still failing.
