#!/usr/bin/env python3
"""Diff fixture audits against expected.json. Exit 1 on any failure.

expected.json:
{
  "must_find":    [{"any_principles": ["WCAG-3.3.2"], "screen_index": 0, "note": "..."}],
  "must_not_find":[{"any_principles": ["DARK-01"], "note": "..."}],
  "max_severity": "medium",          // optional: no observed finding above this
  "max_findings": 4,                  // optional
  "min_overall": 80, "max_overall": 70,  // optional
  "baseline_scores": {"overall": 62, ...} or null  // ±10 tolerance; null = not recorded
}
"""
import json
import sys
from pathlib import Path

SEV_ORDER = {"low": 0, "medium": 1, "high": 2, "critical": 3}


def match(exp, findings):
    for f in findings:
        if not set(exp["any_principles"]) & set(f.get("principles", [])):
            continue
        if "screen_index" in exp and f.get("screen_index") != exp["screen_index"]:
            continue
        return f
    return None


def check(fdir):
    expected = json.load(open(fdir / "expected.json"))
    audit_path = fdir / "audit" / "findings.json"
    if not audit_path.exists():
        return None, [f"{fdir.name}: no audit yet (skipped)"]
    data = json.load(open(audit_path))
    findings = data.get("findings", [])
    fails, notes = [], []

    for exp in expected.get("must_find", []):
        hit = match(exp, findings)
        if hit:
            notes.append(f"  found: {exp['note']} -> {hit['id']}")
        else:
            fails.append(f"MISSED must-find: {exp['note']} "
                         f"(any of {exp['any_principles']})")
    for exp in expected.get("must_not_find", []):
        hit = match(exp, findings)
        if hit:
            fails.append(f"FORBIDDEN hit: {exp['note']} -> {hit['id']} ({hit['issue']})")
    if "max_severity" in expected:
        cap = SEV_ORDER[expected["max_severity"]]
        for f in findings:
            if SEV_ORDER.get(f["severity"], 0) > cap:
                fails.append(f"SEVERITY over cap: {f['id']} is {f['severity']} "
                             f"(cap {expected['max_severity']})")
    if "max_findings" in expected and len(findings) > expected["max_findings"]:
        fails.append(f"TOO MANY findings: {len(findings)} > {expected['max_findings']}")
    overall = data.get("scores", {}).get("overall")
    if "min_overall" in expected and overall < expected["min_overall"]:
        fails.append(f"SCORE low: overall {overall} < {expected['min_overall']}")
    if "max_overall" in expected and overall > expected["max_overall"]:
        fails.append(f"SCORE high: overall {overall} > {expected['max_overall']}")
    base = expected.get("baseline_scores")
    if base:
        for k, v in base.items():
            got = data.get("scores", {}).get(k)
            if got is None or abs(got - v) > 10:
                fails.append(f"DRIFT: scores.{k} {got} vs baseline {v} (±10)")
    elif base is None and "baseline_scores" in expected:
        notes.append("  baseline not recorded yet — drift check skipped")
    return fails, notes


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "fixtures")
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    total_fails = 0
    for fdir in sorted(p for p in root.iterdir() if (p / "expected.json").exists()):
        if only and fdir.name != only:
            continue
        fails, notes = check(fdir)
        if fails is None:
            print(f"SKIP {notes[0]}")
            continue
        status = "FAIL" if fails else "PASS"
        print(f"{status} {fdir.name}")
        for n in notes:
            print(n)
        for f in fails:
            print(f"  !! {f}")
        total_fails += len(fails)
    if total_fails:
        print(f"\n{total_fails} failure(s)")
        sys.exit(1)
    print("\nall fixture checks passed")


if __name__ == "__main__":
    main()
