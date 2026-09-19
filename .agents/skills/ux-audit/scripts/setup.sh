#!/usr/bin/env bash
# One-time bootstrap for the ux-audit skill: create .venv and install Pillow
# (the only dependency). Safe to re-run; everything after this works offline.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -x .venv/bin/python ]; then
    python3 -m venv .venv
fi
.venv/bin/python -c "import PIL" 2>/dev/null || .venv/bin/pip install --quiet pillow
.venv/bin/python -c "import PIL; print('ux-audit ready: Python venv ok, Pillow', PIL.__version__)"
