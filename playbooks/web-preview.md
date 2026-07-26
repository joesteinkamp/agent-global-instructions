# Web preview & browser-testing playbook

On-demand how-to, installed to `~/.ai/web-preview.md` by `customize.sh
--global`. The resident instructions (`~/AGENTS.md`) keep the policy — what to
serve, where, and the handoff URL — and point here for the mechanics. **Read
this before driving a browser or serving a route for preview.**

## Browser testing & verification — `playwright-cli`

After serving a route, drive it with `playwright-cli` (`open`/`goto`, `screenshot`, `console`, and the network log; `run-code` when you need Playwright APIs like axe-core or `emulateMedia`). Read `playwright-cli --help` before inventing flows; don't use curl-only smoke checks for UI work.

## Serving gotchas

- **Vite/Astro 403 behind a proxy or tailnet hostname:** binding `0.0.0.0` isn't enough — they reject an unknown Host (e.g. `*.ts.net`). For `astro dev`/Vite add `vite.server.allowedHosts: ['.ts.net']`; for `astro preview` (a separate check `allowedHosts` doesn't fix) serve the build statically: `python3 -m http.server PORT --bind 0.0.0.0 --directory dist`.
- **Verify before handoff:** curl the exact URL you're about to hand over and require a 200 (not 403/000). If a port is unreachable through a firewall, allow it on the relevant interface rather than switching to localhost.
