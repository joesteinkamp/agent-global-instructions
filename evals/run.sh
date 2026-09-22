#!/usr/bin/env bash
# run.sh — check that every behaviour in behaviours.md is still instructed.
#
#   ./evals/run.sh            # check against the default render
#   ./evals/run.sh --verbose  # also list the behaviours that passed
#
# What this is. test.sh checks that the harness INSTALLS correctly — files
# render, hooks wire up, permissions merge. It says nothing about whether the
# ~20 KB of instructions in template.md still causes anything. This closes the
# near half of that gap: every behaviour the instructions exist to produce names
# the exact text it depends on, so deleting or rewording that rule fails here by
# behaviour, with the reason the behaviour exists, rather than as a bare missing
# string somewhere in a 200-assertion suite.
#
# Where an anchor is looked for. By default, in the rendered instructions — that
# is where most rules live. An entry may add `file: <path>` to point at a role
# definition or a playbook instead, because those are separate surfaces that the
# render never contains. The path is relative to the repo root and must exist, so
# a typo fails loudly rather than silently checking the wrong thing.
#
# What this is NOT. It does not run a model. A behaviour whose anchor renders is
# instructed, not demonstrated — the far half of the gap needs a live model, and
# the fork that decides how is written up in PLAN.md. Do not read a pass here as
# evidence the agent behaves this way.
set -uo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$DIR/evals/behaviours.md"
[ -f "$SRC" ] || { echo "no behaviours.md at $SRC" >&2; exit 2; }

VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

# Render once, with the user's own context ignored so this is reproducible on
# any machine — the same hermetic flag test.sh uses.
RENDER="$(AIGI_NO_USER_ENV=1 "$DIR/customize.sh" --print 2>/dev/null)"
[ -n "$RENDER" ] || { echo "render produced nothing" >&2; exit 2; }

pass=0; fail=0
id=""; anchor=""; origin=""; where=""

check() {   # $1=id $2=anchor $3=origin $4=file (empty = the render)
  [ -n "$1" ] || return 0
  if [ -z "$2" ]; then
    printf '  MISSING ANCHOR  %s — entry declares no anchor: to check\n' "$1"; fail=$((fail+1)); return 0
  fi
  local hay
  if [ -n "$4" ]; then
    if [ ! -f "$DIR/$4" ]; then
      printf '  BAD FILE  %s — declares file: %s, which does not exist\n' "$1" "$4"; fail=$((fail+1)); return 0
    fi
    hay="$(cat "$DIR/$4")"
  else
    hay="$RENDER"
  fi
  # Herestring, not a pipe: `grep -q` exits on the first match, which lands
  # SIGPIPE on a `printf` still writing the 33KB render, and `pipefail` then
  # reports a successful match as a failed pipeline. That surfaced as a flaky
  # eval naming a different behaviour each run, depending on where its anchor
  # sat in the render.
  if grep -qF -- "$2" <<<"$hay"; then
    pass=$((pass+1)); [ "$VERBOSE" = 1 ] && printf '  ok   %s\n' "$1"
  else
    fail=$((fail+1))
    printf '  FAIL %s — no longer instructed\n' "$1"
    printf '       anchor: %s\n' "$2"
    printf '       looked in: %s\n' "${4:-the rendered instructions}"
    printf '       why it exists: %s\n' "$origin"
  fi
  return 0
}

while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  case "$line" in
    '## BEH-'*)
      check "$id" "$anchor" "$origin" "$where"
      id="${line##\#\# }"; anchor=""; origin=""; where="" ;;
    'anchor: '*) anchor="${line#anchor: }" ;;
    'origin: '*) origin="${line#origin: }" ;;
    'file: '*)   where="${line#file: }" ;;
  esac
done < "$SRC"
check "$id" "$anchor" "$origin" "$where"

echo ""
echo "$pass behaviour(s) still instructed, $fail broken"
[ "$fail" -eq 0 ] || exit 1
