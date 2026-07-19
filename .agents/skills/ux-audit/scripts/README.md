# Script CLI contracts (frozen — see execution-plan.html Appendix A)

All scripts: Python stdlib + Pillow only, offline, run via `.venv/bin/python`.
Coordinates are always `[ymin, xmin, ymax, xmax]` on a 0–1000 normalized scale.

## measure.py — deterministic visual measurements
```
measure.py IMG [IMG...] [--json out.json]            # auto pass (best-effort seeding)
measure.py IMG --region 120,640,210,980 --probe contrast|size
```
Output:
```
{"screens":[{"file","width","height","regions":[
  {"box_2d":[...],"kind":"text","fg":"#8a8f98","bg":"#6b7280","contrast":2.8,"height_px":14}
  | {"box_2d":[...],"kind":"unmeasurable"}]}]}
```
Rules: report "unmeasurable" rather than guess. Auto pass may degrade to dims-only.

## annotate.py — draw findings onto screenshots
```
annotate.py findings.json --images s0.png [s1.png...] --out annotated/
```
Writes `annotated/screen-N.png`. Severity colors: critical #ff6b6b, high #ffa94d,
medium #ffd43b, low #74c0fc. Invalid boxes (ymin>=ymax, out of range, area >80%)
are logged to stderr and skipped — never guessed.

## build_report.py — single-file HTML report
```
build_report.py findings.json --images s0.png [s1.png...] \
    --template assets/report-template.html --out report.html
```
Pass ORIGINAL screenshots in screen_index order — finding markers render as
interactive HTML overlays (hover popovers), so annotated PNGs would double-draw.
(`--annotated dir/` remains as a legacy fallback.) Base64-embeds images; zero
network requests in output. The annotated PNGs from annotate.py are still the
standalone shareable artifacts.

## build_registry.py — citation vocabulary
```
build_registry.py        # references/frameworks/*.md -> references/registry.json
```

## validate_findings.py — schema + citation + contract checks
```
validate_findings.py findings.json      # exit 1 with itemized errors on failure
```

## check_fixtures.py — golden fixture diff
```
check_fixtures.py fixtures/ [--only NAME]
```
Diffs `fixtures/<name>/audit/findings.json` against `fixtures/<name>/expected.json`:
must-finds matched by principle ID + screen (+ box IoU>0.3 when given), forbidden hits,
score deltas vs baseline (±10).

## gen_fixtures.py — regenerate fixture screenshots (deterministic)
```
gen_fixtures.py [--only NAME]
```
