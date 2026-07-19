#!/usr/bin/env python3
"""Build a self-contained HTML report from findings.json + annotated screenshots."""
import argparse
import base64
import json
import re
import sys
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("findings")
    ap.add_argument("--images", nargs="+",
                    help="ORIGINAL screenshots in screen_index order (markers are "
                         "drawn as interactive HTML overlays, not baked pixels)")
    ap.add_argument("--annotated", help="legacy: dir with annotated screen-N.png")
    ap.add_argument("--template", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    data = json.load(open(args.findings))
    if args.images:
        paths = [Path(p) for p in args.images]
    elif args.annotated:
        adir = Path(args.annotated)
        paths = sorted(adir.glob("screen-*.png"),
                       key=lambda p: int(re.search(r"\d+", p.stem).group()))
    else:
        sys.exit("ERROR: pass --images (preferred) or --annotated")
    images = [f"data:image/png;base64,{base64.b64encode(p.read_bytes()).decode()}"
              for p in paths]
    if not images:
        sys.exit("ERROR: no screenshots found")

    def safe(obj):
        # keep inline <script type=application/json> blocks unterminated
        return json.dumps(obj).replace("</", "<\\/")

    registry_path = Path(__file__).resolve().parent.parent / "references" / "registry.json"
    registry = json.load(open(registry_path)) if registry_path.exists() else {}

    html = Path(args.template).read_text()
    html = (html.replace("{{TITLE}}",
                         f"UX audit — {data.get('meta', {}).get('audit_id', 'report')}")
                .replace("{{FINDINGS_JSON}}", safe(data))
                .replace("{{IMAGES_JSON}}", safe(images))
                .replace("{{REGISTRY_JSON}}", safe(registry)))
    Path(args.out).write_text(html)
    print(f"wrote {args.out} ({len(html) // 1024} KB, {len(images)} screens)")


if __name__ == "__main__":
    main()
