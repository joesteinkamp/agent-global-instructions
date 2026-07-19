#!/usr/bin/env python3
"""Validate findings.json against references/report-spec.md. Exit 1 with errors."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEV_W = {"critical": 4, "high": 3, "medium": 2, "low": 1}
CATS = {"usability", "cognitive_load", "visual_layout", "accessibility",
        "content", "trust_persuasion"}


def reach_band(r):
    return 1.0 if r <= 1 else 1.5 if r <= 3 else 2.0 if r <= 9 else 3.0


def words(s):
    return len((s or "").split())


def check_finding(f, registry, errors, in_hypotheses):
    fid = f.get("id", "<no id>")
    e = errors.append
    for key in ("id", "category", "type", "severity", "principles", "issue",
                "why_it_matters", "recommendation", "element"):
        if key not in f:
            e(f"{fid}: missing key '{key}'")
    if f.get("category") not in CATS:
        e(f"{fid}: bad category {f.get('category')}")
    if f.get("severity") not in SEV_W:
        e(f"{fid}: bad severity {f.get('severity')}")
    for p in f.get("principles", []):
        if p not in registry:
            e(f"{fid}: unknown principle '{p}' (not in registry.json)")
        elif registry[p]["tier"] == [3] and not in_hypotheses:
            e(f"{fid}: Tier-3-only principle {p} must live in hypotheses[]")
    if words(f.get("issue")) > 20:
        e(f"{fid}: issue >20 words ({words(f.get('issue'))})")
    if words(f.get("recommendation")) > 25:
        e(f"{fid}: recommendation >25 words")
    total = sum(words(f.get(k)) for k in ("issue", "why_it_matters", "recommendation"))
    if total > 60:
        e(f"{fid}: total text {total} words >60")
    box = f.get("box_2d")
    if box is not None:
        if (not isinstance(box, list) or len(box) != 4
                or not (0 <= box[0] < box[2] <= 1000 and 0 <= box[1] < box[3] <= 1000)):
            e(f"{fid}: invalid box_2d {box}")
        elif (box[2] - box[0]) * (box[3] - box[1]) > 800_000:
            e(f"{fid}: box_2d >80% of screen — use null")
    # numeric a11y claims need measured evidence
    claim_text = " ".join(str(f.get(k, "")) for k in ("issue", "why_it_matters",
                                                      "recommendation"))
    if re.search(r"\d+(\.\d+)?\s*:\s*1|\d+\s*px", claim_text):
        if not str(f.get("evidence", "")).startswith("measured:"):
            e(f"{fid}: numeric ratio/px claim without 'measured:' evidence")
    if in_hypotheses:
        if f.get("type") != "hypothesis" or not f.get("validation"):
            e(f"{fid}: hypotheses[] entries need type=hypothesis and a validation method")
    elif f.get("type") != "observed":
        e(f"{fid}: findings[] entries must have type=observed")
    if "importance" in f and "reach" in f and f.get("severity") in SEV_W:
        want = SEV_W[f["severity"]] * reach_band(f["reach"])
        if abs(f["importance"] - want) > 0.01:
            e(f"{fid}: importance {f['importance']} != {want} (recompute)")


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "findings.json"
    data = json.load(open(path))
    registry = json.load(open(ROOT / "references" / "registry.json"))
    errors = []

    for key in ("meta", "scores", "one_big_thing", "findings"):
        if key not in data:
            errors.append(f"top-level: missing '{key}'")
    scores = data.get("scores", {})
    for c in CATS | {"overall"}:
        v = scores.get(c)
        if not isinstance(v, int) or not 0 <= v <= 100:
            errors.append(f"scores.{c}: missing or not an int 0-100 ({v!r})")

    per_cat = {}
    for f in data.get("findings", []):
        check_finding(f, registry, errors, in_hypotheses=False)
        per_cat[f.get("category")] = per_cat.get(f.get("category"), 0) + 1

    # ID ordering: boxed first, then screen-level, then cross-screen
    def grp(f):
        if f.get("box_2d") is not None:
            return 0
        return 1 if f.get("screen_index") is not None else 2
    seq = sorted(data.get("findings", []),
                 key=lambda f: int(re.search(r"\d+", f.get("id", "F-0")).group()))
    last = 0
    for f in seq:
        g = grp(f)
        if g < last:
            errors.append(f"{f['id']}: ID order — boxed findings get the lowest numbers, "
                          "then screen-level, then cross-screen (see report-spec.md)")
        last = max(last, g)
    for f in data.get("hypotheses", []):
        check_finding(f, registry, errors, in_hypotheses=True)
    for cat, n in per_cat.items():
        if n > 5:
            errors.append(f"category {cat}: {n} findings >5 cap")

    if errors:
        print(f"INVALID — {len(errors)} error(s):")
        for err in errors:
            print(f"  - {err}")
        sys.exit(1)
    print(f"VALID: {len(data.get('findings', []))} findings, "
          f"{len(data.get('hypotheses', []))} hypotheses, "
          f"overall {scores.get('overall')}")


if __name__ == "__main__":
    main()
