#!/usr/bin/env python3
"""Build references/registry.json from references/frameworks/*.md.

Parses YAML-ish frontmatter and `| ID | Name | Definition |` table rows.
Fails loudly on duplicate IDs or unparseable files.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FRAMEWORKS = ROOT / "references" / "frameworks"
OUT = ROOT / "references" / "registry.json"

ID_RE = re.compile(r"^(?:[A-Z]+-[A-Z0-9]+|WCAG-\d+\.\d+\.\d+)$")
VALID_CATEGORIES = {"usability", "cognitive_load", "visual_layout",
                    "accessibility", "content", "trust_persuasion"}


def parse_frontmatter(text, path):
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        sys.exit(f"ERROR {path.name}: missing frontmatter")
    fm = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            fm[k.strip()] = v.strip().strip('"')
    for key in ("framework", "tier", "category"):
        if key not in fm:
            sys.exit(f"ERROR {path.name}: frontmatter missing '{key}'")
    if fm["category"] not in VALID_CATEGORIES:
        sys.exit(f"ERROR {path.name}: invalid category '{fm['category']}'")
    fm["tier"] = [int(t) for t in re.findall(r"\d", fm["tier"])]
    return fm


def parse_principles(text, path):
    rows = []
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 3 and ID_RE.match(cells[0]):
            rows.append((cells[0], cells[1], cells[2]))
    if not rows:
        sys.exit(f"ERROR {path.name}: no principle rows found")
    return rows


def main():
    registry = {}
    files = sorted(p for p in FRAMEWORKS.glob("*.md") if not p.name.startswith("_"))
    if not files:
        sys.exit("ERROR: no framework files found")
    for path in files:
        text = path.read_text()
        if re.search(r"^status:\s*informational\s*$", text, re.M):
            print(f"  (skipping {path.name}: informational only)")
            continue
        fm = parse_frontmatter(text, path)
        for pid, name, definition in parse_principles(text, path):
            if pid in registry:
                sys.exit(f"ERROR: duplicate ID {pid} in {path.name} "
                         f"(already in {registry[pid]['file']})")
            registry[pid] = {
                "name": name,
                "framework": fm["framework"],
                "tier": fm["tier"],
                "category": fm["category"],
                "file": path.name,
            }
    OUT.write_text(json.dumps(registry, indent=1))
    counts = {}
    for v in registry.values():
        counts[v["file"]] = counts.get(v["file"], 0) + 1
    print(f"registry.json: {len(registry)} principles from {len(counts)} files")
    for f, n in sorted(counts.items()):
        print(f"  {f}: {n}")


if __name__ == "__main__":
    main()
