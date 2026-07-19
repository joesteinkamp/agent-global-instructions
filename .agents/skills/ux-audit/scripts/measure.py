#!/usr/bin/env python3
"""Deterministic visual measurements (contrast, sizes) for the ux-audit skill.

Honest by design: reports "unmeasurable" rather than guessing. Auto pass is
best-effort seeding; the --region probe is the primary interface.
Coordinates: [ymin, xmin, ymax, xmax] on a 0-1000 normalized scale.
"""
import argparse
import json
import sys
from PIL import Image

CELL = 64           # auto-pass grid cell size, px
MAX_AUTO_REGIONS = 15
MIN_FG_SHARE = 0.02
MAX_FG_SHARE = 0.45


def srgb_lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    r, g, b = (srgb_lin(c) for c in rgb[:3])
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def hexc(rgb):
    return "#{:02x}{:02x}{:02x}".format(*rgb[:3])


def dominant_pair(img):
    """Return (bg, fg, fg_share) for a crop, or None if not bimodal enough."""
    q = img.convert("RGB").quantize(colors=6)
    palette = q.getpalette()
    counts = sorted(q.getcolors(maxcolors=256) or [], reverse=True)
    if not counts:
        return None
    total = sum(n for n, _ in counts)
    colors = [(n / total, tuple(palette[i * 3:i * 3 + 3])) for n, i in counts]
    bg = colors[0][1]
    # fg = highest-contrast color among the rest with a meaningful share
    best = None
    for share, rgb in colors[1:]:
        if share < MIN_FG_SHARE:
            continue
        c = contrast(bg, rgb)
        if best is None or c > best[0]:
            best = (c, rgb, share)
    if best is None or colors[0][0] > 0.98:
        return None
    return bg, best[1], best[2]


def fg_extent(img, fg, tol=60):
    """Bounding rows/cols of pixels near fg color. Returns (h, w) in px or None."""
    rgb = img.convert("RGB")
    px = rgb.load()
    w, h = rgb.size
    rows, cols = [], []
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            if sum(abs(p[i] - fg[i]) for i in range(3)) <= tol:
                rows.append(y)
                cols.append(x)
    if not rows:
        return None
    return max(rows) - min(rows) + 1, max(cols) - min(cols) + 1


def box_to_px(box, w, h):
    y0, x0, y1, x1 = box
    return (round(y0 / 1000 * h), round(x0 / 1000 * w),
            round(y1 / 1000 * h), round(x1 / 1000 * w))


def probe(path, box, kind):
    img = Image.open(path)
    w, h = img.size
    py0, px0, py1, px1 = box_to_px(box, w, h)
    if not (0 <= py0 < py1 <= h and 0 <= px0 < px1 <= w):
        return {"box_2d": box, "kind": "unmeasurable", "note": "region out of bounds"}
    crop = img.crop((px0, py0, px1, py1))
    pair = dominant_pair(crop)
    if pair is None:
        return {"box_2d": box, "kind": "unmeasurable",
                "note": "no clear foreground/background pair (gradient or imagery?)"}
    bg, fg, _ = pair
    extent = fg_extent(crop, fg)
    out = {"box_2d": box, "kind": "text" if kind == "contrast" else "element",
           "fg": hexc(fg), "bg": hexc(bg),
           "contrast": round(contrast(fg, bg), 2)}
    if extent:
        out["height_px"], out["width_px"] = extent
    return out


def auto_pass(path):
    img = Image.open(path).convert("RGB")
    w, h = img.size
    regions = []
    for cy in range(0, h - CELL + 1, CELL):
        for cx in range(0, w - CELL + 1, CELL):
            crop = img.crop((cx, cy, cx + CELL, cy + CELL))
            pair = dominant_pair(crop)
            if pair is None:
                continue
            bg, fg, share = pair
            if not (MIN_FG_SHARE <= share <= MAX_FG_SHARE):
                continue
            box = [round(cy / h * 1000), round(cx / w * 1000),
                   round((cy + CELL) / h * 1000), round((cx + CELL) / w * 1000)]
            regions.append({"box_2d": box, "kind": "text", "fg": hexc(fg),
                            "bg": hexc(bg), "contrast": round(contrast(fg, bg), 2)})
    # keep the lowest-contrast regions — those are the ones worth a closer probe
    regions.sort(key=lambda r: r["contrast"])
    return {"file": path, "width": w, "height": h,
            "regions": regions[:MAX_AUTO_REGIONS]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("images", nargs="+")
    ap.add_argument("--region", help="ymin,xmin,ymax,xmax on 0-1000 scale")
    ap.add_argument("--probe", choices=["contrast", "size"], default="contrast")
    ap.add_argument("--json", help="write output to file")
    args = ap.parse_args()

    if args.region:
        box = [int(v) for v in args.region.split(",")]
        if len(box) != 4:
            sys.exit("ERROR: --region needs ymin,xmin,ymax,xmax")
        result = {"screens": [{"file": args.images[0],
                               **dict(zip(("width", "height"),
                                          Image.open(args.images[0]).size[::1])),
                               "regions": [probe(args.images[0], box, args.probe)]}]}
        result["screens"][0]["width"], result["screens"][0]["height"] = \
            Image.open(args.images[0]).size
    else:
        result = {"screens": [auto_pass(p) for p in args.images]}

    text = json.dumps(result, indent=1)
    if args.json:
        with open(args.json, "w") as f:
            f.write(text)
        print(f"wrote {args.json}")
    else:
        print(text)


if __name__ == "__main__":
    main()
