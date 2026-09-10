#!/usr/bin/env bash
# verify-skills.sh — prove the vendored skill trees haven't drifted.
#
#   ./verify-skills.sh            # verify every tree against skills-manifest.json
#   ./verify-skills.sh --update   # re-record after a deliberate import
#   ./verify-skills.sh --list     # show what is vendored and how big each tree is
#
# Why this exists. Skills are developed in their own repositories and imported
# here when ready, so an import is the moment integrity matters — and nothing
# checked it. `skills-lock.json` belongs to `npx skills` (skills.sh), not to this
# repo; no script here reads it; and it records ONE `skillPath` plus one hash per
# skill. For `ux-audit` that path is `SKILL.md` while the tree is 66 files, so 65
# of them were pinned by nothing and a change to any was invisible.
#
# This does not replace or edit that lockfile — it is the upstream tool's file and
# stays its business. This records a manifest hash the harness computes and checks
# itself, over the whole tree, so drift is caught regardless of what the upstream
# tool does or doesn't support.
#
# The hash covers each file's path and content, so a renamed file, a deleted file,
# an added file and an edited byte all change it. Mode bits are deliberately not
# covered: git records only the executable bit and checkouts vary by umask, which
# would make the manifest fail for reasons that are not drift.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS="$DIR/.agents/skills"
MANIFEST="$DIR/skills-manifest.json"

# macOS ships `shasum`, most Linux `sha256sum`. Fail loudly rather than silently
# skipping verification if neither is present.
if command -v sha256sum >/dev/null 2>&1; then sha() { sha256sum | cut -d' ' -f1; }
elif command -v shasum   >/dev/null 2>&1; then sha() { shasum -a 256 | cut -d' ' -f1; }
else echo "verify-skills: need sha256sum or shasum" >&2; exit 2; fi

command -v jq >/dev/null 2>&1 || { echo "verify-skills: jq is required." >&2; exit 2; }
[ -d "$SKILLS" ] || { echo "verify-skills: no $SKILLS" >&2; exit 2; }

# Manifest hash for one tree: every file's path and content, in a stable order.
# LC_ALL=C so the sort is byte-order and not locale-dependent across machines.
tree_hash() {  # $1 = skill dir
  ( cd "$1" || exit 1
    find . -type f ! -name '.DS_Store' -print0 \
      | LC_ALL=C sort -z \
      | while IFS= read -r -d '' f; do
          printf '%s  %s\n' "$(sha < "$f")" "${f#./}"
        done | sha
  )
}

tree_count() { find "$1" -type f ! -name '.DS_Store' | wc -l | tr -d ' '; }

names=()
for d in "$SKILLS"/*/; do [ -d "$d" ] || continue; names+=("$(basename "$d")"); done
[ ${#names[@]} -gt 0 ] || { echo "verify-skills: no vendored skills"; exit 0; }

case "${1:-}" in
  --list)
    printf '%-18s %6s  %s\n' SKILL FILES TREE-HASH
    for n in "${names[@]}"; do
      printf '%-18s %6s  %s\n' "$n" "$(tree_count "$SKILLS/$n")" "$(tree_hash "$SKILLS/$n")"
    done
    exit 0;;
  --update)
    tmp="$(mktemp)"; : > "$tmp"
    for n in "${names[@]}"; do
      jq -nc --arg n "$n" --arg h "$(tree_hash "$SKILLS/$n")" --arg c "$(tree_count "$SKILLS/$n")" \
        '{name:$n, files:($c|tonumber), treeHash:$h}' >> "$tmp"
    done
    jq -s --arg d "$(date -u +%Y-%m-%d)" \
      '{version:1, recorded:$d, note:"Computed by verify-skills.sh over each .agents/skills/<name>/ tree. Independent of skills-lock.json, which belongs to npx skills.", skills:(map({(.name): {files:.files, treeHash:.treeHash}}) | add)}' \
      "$tmp" > "$MANIFEST"
    rm -f "$tmp"
    echo "verify-skills: recorded ${#names[@]} tree(s) -> ${MANIFEST#"$DIR"/}"
    exit 0;;
  ""|--verify) ;;
  *) echo "usage: verify-skills.sh [--verify|--update|--list]" >&2; exit 2;;
esac

[ -f "$MANIFEST" ] || { echo "verify-skills: no manifest yet — run --update" >&2; exit 2; }

fail=0; pass=0
for n in "${names[@]}"; do
  want="$(jq -r --arg n "$n" '.skills[$n].treeHash // empty' "$MANIFEST")"
  got="$(tree_hash "$SKILLS/$n")"
  if [ -z "$want" ]; then
    echo "  UNRECORDED $n — vendored but not in the manifest; --update after an import"; fail=$((fail+1))
  elif [ "$want" = "$got" ]; then
    pass=$((pass+1))
  else
    echo "  DRIFTED    $n — $(tree_count "$SKILLS/$n") file(s)"
    echo "             recorded $want"
    echo "             actual   $got"
    echo "             The vendored copy is never edited in place: re-import upstream, or --update if the change is deliberate."
    fail=$((fail+1))
  fi
done

# A manifest entry with no tree is drift too: a skill was removed and the record
# kept, which would otherwise pass silently.
while IFS= read -r n; do
  [ -d "$SKILLS/$n" ] || { echo "  MISSING    $n — in the manifest, not on disk"; fail=$((fail+1)); }
done < <(jq -r '.skills | keys[]' "$MANIFEST")

echo ""
echo "$pass tree(s) verified, $fail problem(s)"
[ "$fail" -eq 0 ] || exit 1
