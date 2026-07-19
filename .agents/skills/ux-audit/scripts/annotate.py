#!/usr/bin/env python3
"""Draw findings.json bounding boxes onto screenshots.

Invalid boxes are logged to stderr and skipped — never guessed.
"""
import argparse
import json
import os
import re
import sys
from PIL import Image, ImageDraw, ImageFont

SEVERITY_COLORS = {"critical": "#ff6b6b", "high": "#ffa94d",
                   "medium": "#ffd43b", "low": "#74c0fc"}
SEVERITY_ORDER = {"low": 0, "medium": 1, "high": 2, "critical": 3}
FONT_PATHS = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]


def load_font(size):
    for p in FONT_PATHS:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def valid_box(box, fid):
    if (not isinstance(box, list) or len(box) != 4
            or any(not isinstance(v, (int, float)) for v in box)):
        return f"{fid}: box_2d malformed"
    y0, x0, y1, x1 = box
    if not (0 <= y0 < y1 <= 1000 and 0 <= x0 < x1 <= 1000):
        return f"{fid}: box_2d coordinates invalid ({box})"
    if (y1 - y0) * (x1 - x0) > 800_000:  # >80% of screen
        return f"{fid}: box_2d covers >80% of screen — should be screen-level (null)"
    return None


def annotate_image(img_path, findings, out_path):
    img = Image.open(img_path).convert("RGBA")
    w, h = img.size
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    badge_r = max(14, w // 90)
    font = load_font(int(badge_r * 1.1))
    placed = []

    findings = sorted(findings, key=lambda f: SEVERITY_ORDER.get(f["severity"], 0))
    for f in findings:
        y0, x0, y1, x1 = f["box_2d"]
        px = (round(x0 / 1000 * w), round(y0 / 1000 * h),
              round(x1 / 1000 * w), round(y1 / 1000 * h))
        color = SEVERITY_COLORS.get(f["severity"], "#74c0fc")
        # dark halo then colored outline, for legibility on any background
        draw.rounded_rectangle(px, radius=6, outline=(0, 0, 0, 140), width=7)
        draw.rounded_rectangle(px, radius=6, outline=color, width=3)
        # numbered badge at top-left corner, staggered if overlapping
        m = re.search(r"\d+", f["id"])
        label = m.group(0) if m else f["id"][-2:]
        bx, by = px[0], max(badge_r, px[1])
        while any(abs(bx - ox) < badge_r * 2.2 and abs(by - oy) < badge_r * 2.2
                  for ox, oy in placed):
            bx += int(badge_r * 2.4)
        placed.append((bx, by))
        draw.ellipse([bx - badge_r, by - badge_r, bx + badge_r, by + badge_r],
                     fill=color, outline=(0, 0, 0, 200), width=2)
        tb = draw.textbbox((0, 0), label, font=font)
        draw.text((bx - (tb[2] - tb[0]) / 2, by - (tb[3] - tb[1]) / 2 - tb[1]),
                  label, fill="#111", font=font)

    Image.alpha_composite(img, overlay).convert("RGB").save(out_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("findings")
    ap.add_argument("--images", nargs="+", required=True,
                    help="originals in screen_index order")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    data = json.load(open(args.findings))
    os.makedirs(args.out, exist_ok=True)
    all_findings = data.get("findings", []) + data.get("hypotheses", [])

    by_screen = {}
    for f in all_findings:
        if f.get("box_2d") is None:
            continue
        err = valid_box(f["box_2d"], f["id"])
        if err:
            print(f"SKIP {err}", file=sys.stderr)
            continue
        idx = f.get("screen_index") or 0
        by_screen.setdefault(idx, []).append(f)

    for i, img_path in enumerate(args.images):
        out_path = os.path.join(args.out, f"screen-{i}.png")
        annotate_image(img_path, by_screen.get(i, []), out_path)
        print(f"wrote {out_path} ({len(by_screen.get(i, []))} boxes)")


if __name__ == "__main__":
    main()
