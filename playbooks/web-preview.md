# Web preview & browser-testing playbook

On-demand how-to, installed to `~/.ai/web-preview.md` by `customize.sh
--global`. The resident instructions (`~/AGENTS.md`) keep the policy — what to
serve, where, and the handoff URL — and point here for the mechanics. **Read
this before driving a browser or serving a route for preview.**

## Browser testing & verification — `playwright-cli`

After serving a route, drive it with `playwright-cli` (`open`/`goto`, `screenshot`, `console`, and the network log; `run-code` when you need Playwright APIs like axe-core or `emulateMedia`). Read `playwright-cli --help` before inventing flows; don't use curl-only smoke checks for UI work.

**Scope:** this applies to product UI and interactive work. Simple internal HTML reports, comparisons, and other read-only artifacts don't need Playwright or axe — a lightweight structural check (it renders, links resolve) is enough, unless the user asks or the artifact has real interaction complexity.

## Always close the browser when you're done

**End every browser task with `playwright-cli close` (or `close-all`).** Sessions outlive the turn — they are not reaped when your turn ends, when the CLI exits, or by any daemon. Closing is your job, not the harness's. Leaked sessions have been found alive days later.

**Why it's severe on macOS:** `playwright-cli` drives the real `/Applications/Google Chrome.app` binary, and its headless instance registers with LaunchServices under `bundleID="com.google.Chrome"`. macOS permits one app instance per bundle ID, so while that headless process lives, clicking Chrome in the Dock *activates the headless process* instead of launching a browser — and it was started with `--no-startup-window`, so no window ever appears. **The user's Chrome looks broken until the process is force-quit.** On Linux/Windows the same leak is quieter (no bundle-ID collision), but it still strands processes and disk.

- **Diagnose (macOS):** `lsappinfo list | grep -A5 'bundleID="com.google.Chrome"'` — a `pid` you didn't launch, especially `type="Foreground"`, is the culprit. Cross-check with `ps -eo pid,command | grep cliDaemon`.
- **Diagnose (Linux):** `pgrep -af 'playwright|chrome|chromium'`.
- **Not a profile lock.** Playwright uses a throwaway `--user-data-dir` (under `/var/folders/` on macOS, `$TMPDIR` elsewhere), so the real profile has no `SingletonLock` — deleting lock files fixes nothing.
- **`playwright-cli list` is not proof.** It reports `(no browsers)` while orphaned processes are still alive and registered. Verify with the process check above, never with `list` alone.
- **`kill-all` is not enough.** `playwright-cli kill-all` reaps the node daemons but leaves the browser processes behind. After `close`/`close-all`/`kill-all`, re-run the diagnosis and kill any surviving PIDs directly.
- **Sweep the leaks.** Orphaned runs strand `playwright_chromium*_profile-*` and `playwright-artifacts-*` directories in `$TMPDIR` (`/tmp` on Linux); they accumulate for months. Clear them once no playwright process is running.

## Serving gotchas

- **Vite/Astro 403 behind a proxy or tailnet hostname:** binding `0.0.0.0` isn't enough — they reject an unknown Host (e.g. `*.ts.net`). For `astro dev`/Vite add `vite.server.allowedHosts: ['.ts.net']`; for `astro preview` (a separate check `allowedHosts` doesn't fix) serve the build statically: `python3 -m http.server PORT --bind 0.0.0.0 --directory dist`.
- **Verify before handoff:** curl the exact URL you're about to hand over and require a 200 (not 403/000). If a port is unreachable through a firewall, allow it on the relevant interface rather than switching to localhost.
