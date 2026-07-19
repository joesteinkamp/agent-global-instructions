#!/usr/bin/env python3
"""Synthetic tests for measure.py — known contrast pairs and sizes."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from PIL import Image, ImageDraw

SCRIPTS = Path(__file__).resolve().parent.parent
PY = sys.executable


def run(args):
    out = subprocess.run([PY, str(SCRIPTS / "measure.py")] + args,
                         capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def main():
    tmp = Path(tempfile.mkdtemp())
    failures = []

    # 1) #767676 on #ffffff = 4.54:1 (known WCAG reference pair)
    img = Image.new("RGB", (400, 300), "#ffffff")
    d = ImageDraw.Draw(img)
    d.rectangle([50, 100, 250, 130], fill="#767676")  # 201x31 px block
    p1 = tmp / "contrast.png"
    img.save(p1)
    # region: rows 80-150, cols 30-280 -> 0-1000 scale on 300h x 400w
    r = run([str(p1), "--region", "266,75,500,700", "--probe", "contrast"])
    reg = r["screens"][0]["regions"][0]
    if reg["kind"] == "unmeasurable":
        failures.append(f"contrast probe unmeasurable: {reg}")
    else:
        if abs(reg["contrast"] - 4.54) > 0.1:
            failures.append(f"contrast {reg['contrast']} != 4.54±0.1")
        if abs(reg.get("height_px", 0) - 31) > 2:
            failures.append(f"height_px {reg.get('height_px')} != 31±2")

    # 2) size probe: 60x24 button-like block
    img2 = Image.new("RGB", (400, 300), "#f0f0f0")
    ImageDraw.Draw(img2).rectangle([100, 200, 159, 223], fill="#2255cc")
    p2 = tmp / "size.png"
    img2.save(p2)
    r2 = run([str(p2), "--region", "633,225,780,425", "--probe", "size"])
    reg2 = r2["screens"][0]["regions"][0]
    if reg2["kind"] == "unmeasurable":
        failures.append(f"size probe unmeasurable: {reg2}")
    else:
        if abs(reg2.get("height_px", 0) - 24) > 2:
            failures.append(f"size height {reg2.get('height_px')} != 24±2")
        if abs(reg2.get("width_px", 0) - 60) > 2:
            failures.append(f"size width {reg2.get('width_px')} != 60±2")

    # 3) auto pass smoke: runs, returns dims, doesn't crash
    r3 = run([str(p1)])
    s = r3["screens"][0]
    if s["width"] != 400 or s["height"] != 300:
        failures.append(f"auto pass dims wrong: {s['width']}x{s['height']}")

    # 4) gradient -> unmeasurable (honesty check)
    img4 = Image.new("RGB", (200, 200))
    for y in range(200):
        ImageDraw.Draw(img4).line([(0, y), (200, y)], fill=(y, y, 255 - y))
    p4 = tmp / "gradient.png"
    img4.save(p4)
    r4 = run([str(p4), "--region", "100,100,900,900", "--probe", "contrast"])
    k = r4["screens"][0]["regions"][0]["kind"]
    # gradient may quantize into a bimodal pair; only fail if it reports an
    # implausibly confident extreme ratio
    if k != "unmeasurable":
        c = r4["screens"][0]["regions"][0]["contrast"]
        if c > 15:
            failures.append(f"gradient produced overconfident contrast {c}")

    if failures:
        print("FAIL")
        for f in failures:
            print(f"  - {f}")
        sys.exit(1)
    print("PASS: 4/4 measure.py tests")


if __name__ == "__main__":
    main()
