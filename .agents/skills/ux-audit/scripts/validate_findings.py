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
WEIGHTS = {"usability": .30, "cognitive_load": .15, "visual_layout": .15,
           "accessibility": .15, "content": .15, "trust_persuasion": .10}
BANDS = {"0-49": (0, 49), "50-65": (50, 65), "66-79": (66, 79),
         "80-89": (80, 89), "90+": (90, 100)}
FIDELITY = {"real", "representative", "placeholder", "unknown"}
STATS_KEYS = ("generated", "gate_dropped", "merged_away", "capped", "reported")


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


def check_traceability(data, errors):
    """report-spec.md checklist items 9-12: scores must be explainable."""
    e = errors.append
    scores, meta = data.get("scores", {}), data.get("meta", {})
    findings = data.get("findings", [])
    fids = {f.get("id") for f in findings}
    overall = scores.get("overall")
    ints = all(isinstance(scores.get(c), int) for c in CATS)

    # 9a: overall == weighted average of sub-scores (±1)
    if ints and isinstance(overall, int):
        wavg = sum(scores[c] * w for c, w in WEIGHTS.items())
        if abs(overall - wavg) > 1.0:
            e(f"scores.overall {overall} != weighted average {wavg:.1f} (±1) — "
              "revisit sub-scores; never hand-adjust overall (scoring.md)")

    # 9b: score_evidence per category
    se = data.get("score_evidence")
    if not isinstance(se, dict):
        e("top-level: missing 'score_evidence' (see scoring.md)")
        se = {}
    for c in sorted(CATS):
        ev = se.get(c)
        if not isinstance(ev, dict):
            e(f"score_evidence.{c}: missing")
            continue
        sc = scores.get(c)
        band = ev.get("band")
        if band not in BANDS:
            e(f"score_evidence.{c}: band {band!r} not one of {sorted(BANDS)}")
        elif isinstance(sc, int) and not BANDS[band][0] <= sc <= BANDS[band][1]:
            e(f"score_evidence.{c}: band {band} doesn't contain score {sc}")
        drivers = ev.get("drivers", [])
        for d in drivers:
            if d not in fids:
                e(f"score_evidence.{c}: driver {d!r} is not a finding ID")
        if isinstance(sc, int) and sc < 90 and not (drivers or ev.get("limitations")):
            e(f"score_evidence.{c}: score {sc} <90 needs ≥1 driver or limitation")
        if isinstance(sc, int) and sc >= 90 and not ev.get("passes"):
            e(f"score_evidence.{c}: score {sc} ≥90 needs ≥1 documented pass")

    # 10: band <-> severity consistency (consequences of the verbatim bands)
    sevs = [f.get("severity") for f in findings]
    if isinstance(overall, int):
        if overall <= 49 and "critical" not in sevs:
            e(f"overall {overall} is the 'fundamentally broken' band but no critical "
              "finding exists — file the blocker or rescore")
        if overall > 65 and "critical" in sevs:
            e(f"overall {overall} >65 with a critical finding — a goal-blocking "
              "defect contradicts a 'functional' band")
        if overall >= 90 and ("critical" in sevs or "high" in sevs):
            e(f"overall {overall} ≥90 requires zero critical/high findings")
    dark = sum(1 for f in findings
               if any(str(p).startswith("DARK-") for p in f.get("principles", [])))
    if dark >= 2 and isinstance(scores.get("trust_persuasion"), int) \
            and scores["trust_persuasion"] > 35:
        e(f"{dark} DARK-* findings cap trust_persuasion at 35 "
          f"(got {scores['trust_persuasion']})")

    # 11: path_to_excellent
    pte = data.get("path_to_excellent")
    if not isinstance(pte, dict):
        e("top-level: missing 'path_to_excellent' (see scoring.md)")
    else:
        backlog = pte.get("verification_backlog")
        if not backlog or not isinstance(backlog, list):
            e("path_to_excellent.verification_backlog: must be a non-empty list "
              "(a static audit always leaves one)")
        pj = pte.get("post_fix_projection", {})
        rng = pj.get("range")
        if (not isinstance(rng, list) or len(rng) != 2
                or not all(isinstance(x, int) for x in rng)):
            e("post_fix_projection.range: must be [lo, hi] ints")
        else:
            lo, hi = rng
            if not (0 <= lo <= hi <= 100):
                e(f"post_fix_projection.range {rng}: need 0 <= lo <= hi <= 100")
            if isinstance(overall, int) and lo < overall:
                e(f"post_fix_projection low {lo} < overall {overall} — "
                  "fixing findings can't project below the current score")
            if backlog and hi > 89:
                e(f"post_fix_projection high {hi} >89 with a non-empty backlog — "
                  "a static audit can never certify 90+")
        if not pj.get("assumptions"):
            e("post_fix_projection.assumptions: must be a non-empty list")

    # 12: meta fidelity + candidate funnel arithmetic
    if meta.get("data_fidelity") not in FIDELITY:
        e(f"meta.data_fidelity: {meta.get('data_fidelity')!r} not in "
          f"{sorted(FIDELITY)}")
    if "candidate_stats" not in meta:
        e("meta.candidate_stats: missing (object, or null only for pre-v2 audits)")
    elif meta["candidate_stats"] is not None:
        cs = meta["candidate_stats"]
        bad = [k for k in STATS_KEYS
               if not isinstance(cs.get(k), int) or cs.get(k, -1) < 0]
        if bad:
            e(f"meta.candidate_stats: missing/invalid counts {bad}")
        else:
            if cs["reported"] != len(findings):
                e(f"candidate_stats.reported {cs['reported']} != "
                  f"{len(findings)} findings")
            want = cs["gate_dropped"] + cs["merged_away"] + cs["capped"] + cs["reported"]
            if cs["generated"] != want:
                e(f"candidate_stats.generated {cs['generated']} != "
                  f"dropped+merged+capped+reported ({want})")
            if cs["capped"] != meta.get("issue_overflow"):
                e(f"candidate_stats.capped {cs['capped']} != "
                  f"meta.issue_overflow {meta.get('issue_overflow')!r}")


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "findings.json"
    data = json.load(open(path))
    registry = json.load(open(ROOT / "references" / "registry.json"))
    errors = []

    for key in ("meta", "scores", "score_rationales", "one_big_thing", "findings"):
        if key not in data:
            errors.append(f"top-level: missing '{key}'")
    scores = data.get("scores", {})
    for c in CATS | {"overall"}:
        v = scores.get(c)
        if not isinstance(v, int) or not 0 <= v <= 100:
            errors.append(f"scores.{c}: missing or not an int 0-100 ({v!r})")
    check_traceability(data, errors)

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
