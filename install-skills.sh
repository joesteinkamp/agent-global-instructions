#!/usr/bin/env bash
# Install the portable workflow skills into every skill-capable tool so they run
# as /ship, /sync, /improve, /ux-audit (Codex: $ship …) everywhere.
#
#   ./install-skills.sh                     # all tools
#   ./install-skills.sh claude cursor       # just these tools
#   ./install-skills.sh --design            # also install the design group
#   ./install-skills.sh --no-design         # core skills only
#
# Sources, one directory per skill, each symlinked (never copied) into
# ~/.claude/skills, ~/.codex/skills and ~/.cursor/skills:
#   skills/<name>/          core — always installed
#   .agents/skills/ux-audit design group — vendored upstream, never edited here
#
# Every tool reads the SAME files, so nothing can drift between them, and Cursor
# (which also scans ~/.claude/skills and ~/.codex/skills) sees one definition.
# Because they are symlinks, a skill change is live once it lands in the
# checkout this ran from — never run this from a temporary worktree.
#
# The design group installs when --design is passed, or when customize.sh
# --design-group says y (INC_DESIGN, on by default); --no-design forces it off
# and prunes an installed link. A resolver ERROR is not an answer: existing
# design links are left in place.
#
# Migration: the slash-command files and copied Codex skills that earlier
# versions installed are removed, together with their *.bak.* backups, so no
# tool lists a name twice.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/preserve.sh
. "$DIR/lib/preserve.sh"
SRC="$DIR/skills"
VENDORED="$DIR/.agents/skills"
DESIGN_SKILLS="ux-audit"
[ -d "$SRC" ] || { echo "No skills/ dir at $SRC" >&2; exit 1; }

DESIGN_FLAG=auto
targets=()
for a in "$@"; do
  case "$a" in
    --design) DESIGN_FLAG=on;;
    --no-design) DESIGN_FLAG=off;;
    --project) echo "  note: skills install globally; --project has no effect" >&2;;
    claude|codex|cursor|antigravity) targets+=("$a");;
    *) echo "unknown arg: $a (use: --design | --no-design | claude codex cursor antigravity)" >&2; exit 1;;
  esac
done
[ ${#targets[@]} -eq 0 ] && targets=(claude codex cursor antigravity)

want_design=0   # 1 = install; 0 = skip + prune; keep = skip but don't prune
case "$DESIGN_FLAG" in
  on)  want_design=1;;
  off) want_design=0;;
  *)
    if [ -x "$DIR/customize.sh" ]; then
      if dg="$("$DIR/customize.sh" --design-group 2>/dev/null)"; then
        [ "$dg" = y ] && want_design=1
      else
        want_design=keep
        echo "warning: could not resolve the design group (customize.sh --design-group failed);" >&2
        echo "         leaving any installed design skills in place (none added). Pass --design or --no-design to force." >&2
      fi
    fi;;
esac

# Names earlier versions installed as commands and no longer ship. A generic
# name could be the user's own file, so it is backed up before removal.
RETIRED="validate handoff flow tidy critique audit"

# Skill names become path components under $HOME; only plain slugs qualify.
valid_name() { case "$1" in ''|*[!a-z0-9-]*|-*) return 1;; *) return 0;; esac; }

core_names() {
  local d n
  for d in "$SRC"/*/; do
    n="$(basename "$d")"
    valid_name "$n" && [ -f "$d/SKILL.md" ] && printf '%s\n' "$n"
  done
  return 0
}

# The safety predicate before every rm/replace in a skills dir: a symlink WE
# created resolves into this checkout's skills/ or .agents/skills/ tree. Prefix
# match, so it also covers dangling links to a skill since removed. Anything
# else (a real dir, a foreign link) is the user's own and is never touched.
# Keep in sync with uninstall.sh's copy.
is_our_skill_link() {  # $1 = path
  [ -L "$1" ] || return 1
  case "$(readlink "$1")" in "$SRC/"*|"$VENDORED/"*) return 0;; *) return 1;; esac
}

# A real skill dir an earlier install COPIED in (the old Codex port): it carries
# the render marker, so replacing it with the link loses nothing of the user's.
is_legacy_port() {  # $1 = dir
  [ -d "$1" ] && [ ! -L "$1" ] && grep -q '^<!-- GENERATED from commands/' "$1/SKILL.md" 2>/dev/null
}

link_skill() {  # $1 = source dir  $2 = destination skills dir
  local src="${1%/}" dest="$2" name; name="$(basename "$src")"
  valid_name "$name" || return 0
  mkdir -p "$dest"
  if is_legacy_port "$dest/$name"; then
    rm -rf "${dest:?}/$name"; echo "  replaced copied $name skill with a link"
  elif [ -L "$dest/$name" ] && ! is_our_skill_link "$dest/$name"; then
    echo "  note: $dest/$name is a symlink not managed by this repo — leaving it"; return 0
  elif [ -e "$dest/$name" ] && [ ! -L "$dest/$name" ]; then
    echo "  note: $dest/$name exists and is not a symlink — leaving it (remove it to let this repo manage the skill)"; return 0
  fi
  ln -sfn "$src" "$dest/$name"
}

install_skills() {  # $1 = destination skills dir
  local dest="$1" name n=0 link
  for name in $(core_names); do link_skill "$SRC/$name" "$dest"; n=$((n+1)); done
  for name in $DESIGN_SKILLS; do
    [ -d "$VENDORED/$name" ] || continue
    case "$want_design" in
      1) link_skill "$VENDORED/$name" "$dest"; n=$((n+1));;
      0) if is_our_skill_link "$dest/$name"; then rm -f "$dest/$name"; echo "  removed $name (design group off)"; fi;;
    esac
  done
  for link in "$dest"/*; do
    is_our_skill_link "$link" || continue
    [ -e "$link" ] && continue
    rm -f "$link"; echo "  removed dangling skill link $(basename "$link")"
  done
  echo "  $dest ($n skill(s), symlinked)"
}

# Remove the command files earlier versions installed under these names, plus
# their backups, so the skill is the only entry in the tool's menu.
remove_legacy_commands() {  # $1 = commands dir
  local dir="$1" name f n=0
  [ -d "$dir" ] || return 0
  for name in $(core_names) $DESIGN_SKILLS; do
    if [ "$want_design" = keep ]; then
      case " $DESIGN_SKILLS " in *" $name "*) continue;; esac
    fi
    for f in "$dir/$name.md" "$dir/$name.md".bak.*; do
      [ -f "$f" ] || continue
      rm -f "$f"; n=$((n+1))
    done
  done
  for name in $RETIRED; do
    f="$dir/$name.md"; [ -f "$f" ] || continue
    # A retired name is generic enough ("audit") that the file could be the
    # user's own, so it goes through the ledger: one we never shipped is
    # saved to install-state/preserved/ before it's removed.
    pv_delete "$f" "retired command" "commands/$name.md" command || continue
    [ "$PV_ACTION" = removed ] && echo "  removed retired /$name"
  done
  [ "$n" -gt 0 ] && echo "  removed $n legacy command file(s) from $dir"
  return 0
}

# Sweep copied Codex ports for names this repo no longer ships (link_skill
# already replaced the ones it does), and the long-gone flat prompt files.
remove_legacy_codex() {
  local d f
  for d in "$HOME/.codex/skills"/*/; do
    d="${d%/}"
    if is_legacy_port "$d"; then rm -rf "$d"; echo "  removed retired \$$(basename "$d") skill"; fi
  done
  for f in "$HOME/.codex/prompts"/*.md; do
    [ -f "$f" ] || continue
    if grep -q '^# GENERATED from commands/' "$f"; then rm -f "$f"; fi
  done
  return 0
}

for t in "${targets[@]}"; do
  case "$t" in
    claude)
      install_skills "$HOME/.claude/skills"
      remove_legacy_commands "$HOME/.claude/commands";;
    codex)
      install_skills "$HOME/.codex/skills"
      remove_legacy_codex;;
    cursor)
      install_skills "$HOME/.cursor/skills"
      remove_legacy_commands "$HOME/.cursor/commands";;
    antigravity)
      echo "  antigravity: skill install not supported here; skipped — its hooks are wired by install-hooks.sh";;
  esac
done
# Run on its own (not under install.sh): report what the ledger did.
pv_finish
echo "Done. Type / in each tool to see the skills (Codex: use \$<name>)."
