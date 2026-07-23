#!/usr/bin/env bash
# Install the portable commands into each tool's command/prompt directory so they
# work as /ship, /sync, /improve, /ux-audit everywhere.
#
#   ./install-commands.sh                     # all tools, global
#   ./install-commands.sh --project           # all tools, into ./ (this repo)
#   ./install-commands.sh claude cursor       # just these tools, global
#   ./install-commands.sh --project cursor gemini
#   ./install-commands.sh --design            # also install the design command group
#   ./install-commands.sh --no-design         # core commands only
#
# Command groups: a canonical command opts into a group with `group: <name>` in
# its frontmatter (absent => "core", always installed). The "design" group
# (/ux-audit) installs when --design is passed, or automatically when
# INC_DESIGN wants it (asked of customize.sh; on by default for everyone);
# --no-design forces it off. Ports are always generated for every command; the
# group only decides what gets INSTALLED, and an unwanted command already present
# is pruned so flipping your persona self-heals.
#
# Skill-backed commands: a canonical command opts in with `skill-backed: true`
# in its frontmatter, promising a vendored skill of the same name at
# .agents/skills/<name> (pinned in skills-lock.json). Skill-capable tools
# (claude, codex, cursor) then get a SYMLINK to the real skill instead of the thin
# command wrapper — one /<name>, the full engine, no duplicate menu entry.
# Gemini keeps the wrapper (no skill support). Opt-in, not name-matched: a same-named
# vendored skill may be a stub
# that depends on other project-scoped skills (e.g. grill-me -> grilling),
# while the command wrapper is the deliberately self-contained global version.
# Currently: /ux-audit -> .agents/skills/ux-audit.
#
# Per-tool source + destination:
#   claude  commands/*.md          -> ~/.claude/commands/   (project: ./.claude/commands/)
#           skill-backed           -> ~/.claude/skills/<name> (symlink into .agents/skills/)
#   codex   commands/codex/*/SKILL.md -> ~/.codex/skills/   (global only; invoke $<name>)
#           skill-backed           -> ~/.codex/skills/<name>  (symlink into .agents/skills/;
#                                     like all codex skills this is global even under
#                                     --project — codex has no project-scoped install)
#   cursor  commands/cursor/*.md   -> ~/.cursor/commands/   (project: ./.cursor/commands/)
#           skill-backed           -> ~/.cursor/skills/<name> (symlink into .agents/skills/)
#   gemini  commands/gemini/*.toml -> ~/.gemini/commands/   (project: ./.gemini/commands/)
#   antigravity                    -> skipped (separate tool; hooks-only, see install-hooks.sh)
#
# commands/*.md (top level) is the canonical Claude-dialect source of truth; the
# commands/<tool>/ files are GENERATED from it by render-commands.sh (run here
# automatically) — never hand-edit them, edit the canonical file and re-render.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/commands"
[ -d "$SRC" ] || { echo "No commands/ dir at $SRC" >&2; exit 1; }

PROJECT=0
DESIGN_FLAG=auto   # auto | on | off
targets=()
for a in "$@"; do
  case "$a" in
    --project) PROJECT=1;;
    --design) DESIGN_FLAG=on;;
    --no-design) DESIGN_FLAG=off;;
    claude|codex|cursor|gemini|antigravity) targets+=("$a");;
    *) echo "unknown arg: $a (use: --project | --design | --no-design | claude codex cursor gemini antigravity)" >&2; exit 1;;
  esac
done
[ ${#targets[@]} -eq 0 ] && targets=(claude codex cursor antigravity)

# Decide whether the "design" command group installs. Explicit flag wins; on
# "auto" ask customize.sh, which applies the same INC_DESIGN precedence (on by
# default for everyone; so we never re-parse my-context.env here). A resolver
# "n" fails closed (don't install), but a resolver ERROR is not an answer:
# treating it as "off" would silently prune an installed pack on a transient
# customize.sh failure — so warn and leave existing design commands untouched.
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
        echo "         leaving any installed design commands in place (none added). Pass --design or --no-design to force." >&2
      fi
    fi;;
esac

# Read a canonical command's `group:` frontmatter (empty => core). Mirrors
# render-commands.sh's fm_field, pinned to the group key.
fm_group() {  # $1 = canonical commands/<name>.md
  [ -f "$1" ] || return 0
  awk '
    { sub(/\r$/,"") }
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && $0 ~ /^group:/ { v=$0; sub(/^group:[[:space:]]*/,"",v); gsub(/[[:space:]]+$/,"",v); print v; exit }
  ' "$1"
}

# Should command <name> install, given the requested groups? core always; design
# only when wanted; an unknown group installs (fail-open — never hide a command).
# Returns 0 = install, 1 = skip and prune an installed copy, 2 = skip but leave
# an installed copy alone (design when the persona resolver failed).
cmd_wanted() {  # $1 = command basename without extension
  case "$(fm_group "$SRC/$1.md")" in
    design)
      case "$want_design" in
        1)    return 0;;
        keep) return 2;;
        *)    return 1;;
      esac;;
    *) return 0;;
  esac
}

# The safety predicate before every rm/replace of a skills-dir entry: is this
# path a symlink WE created — one resolving into this repo's .agents/skills
# tree? Anything else there (real dir, foreign symlink) is the user's own and
# is never touched. Prefix match, so it also covers links whose skill has since
# been renamed/dropped upstream (dangling but ours). Keep in sync with
# uninstall.sh's copy.
is_our_skill_link() {  # $1 = path
  [ -L "$1" ] || return 1
  case "$(readlink "$1")" in "$DIR/.agents/skills/"*) return 0;; *) return 1;; esac
}

# A canonical command with `skill-backed: true` frontmatter AND a same-named
# vendored skill is "skill-backed": skill-capable tools get the real skill
# (see install_skill_link), not the wrapper command.
skill_backed() {  # $1 = command basename without extension
  [ -d "$DIR/.agents/skills/$1" ] || return 1
  [ -f "$SRC/$1.md" ] || return 1
  awk '
    { sub(/\r$/,"") }
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && $0 ~ /^skill-backed:[[:space:]]*true[[:space:]]*$/ { found=1; exit }
    END { exit !found }
  ' "$SRC/$1.md"
}

# Symlink each skill-backed command's vendored skill into a tool's global skills
# dir, honoring the same group gating as the command it replaces: wanted ->
# symlink, replacing any prior SYMLINK (no data loss — the migration path from
# a hand-made standalone-clone link) but never a real directory (the user's own
# skill; a note is printed). Unwanted -> prune, but only a link that is ours
# (is_our_skill_link). rc=2 (persona resolver failed) leaves things exactly as
# they are. Ends with an orphan prune for dangling links of ours.
install_skill_link() {  # $1 = destination skills dir (~/.claude/skills, ~/.codex/skills, ~/.cursor/skills)
  local dest="$1" src name rc link
  for src in "$DIR/.agents/skills"/*/; do
    [ -d "$src" ] || continue
    name="$(basename "$src")"
    if ! skill_backed "$name"; then
      # Not (or no longer) skill-backed — remove a link WE created earlier so
      # flipping the frontmatter self-heals; never touch anything else.
      if is_our_skill_link "$dest/$name"; then
        rm -f "$dest/$name"; echo "  removed skill link $name (no longer skill-backed)"
      fi
      continue
    fi
    rc=0; cmd_wanted "$name" || rc=$?
    case "$rc" in
      0)
        # A real dir/file here is the user's own skill — never clobbered. Any
        # SYMLINK is replaced (no data loss: only the link changes) — that's
        # the migration path from a hand-made standalone-clone link.
        if [ -e "$dest/$name" ] && [ ! -L "$dest/$name" ]; then
          echo "  note: $dest/$name exists and is not a symlink — leaving it (remove it to let this repo manage the skill)"
        else
          mkdir -p "$dest"
          ln -sfn "${src%/}" "$dest/$name"
          echo "  skill $name -> $dest/$name (symlink)"
        fi;;
      1)
        if is_our_skill_link "$dest/$name"; then
          rm -f "$dest/$name"; echo "  removed skill $name (not in requested groups)"
        fi;;
    esac
  done
  # Orphan prune: the loop above only visits skills that still exist under
  # .agents/skills, so a link we created for a skill later renamed/dropped
  # upstream would dangle forever — the skills-side analog of RETIRED.
  [ -d "$dest" ] || return 0
  for link in "$dest"/*; do
    is_our_skill_link "$link" || continue
    if [ ! -e "$link" ]; then
      rm -f "$link"; echo "  removed dangling skill link $(basename "$link") (vendored skill gone)"
    fi
  done
  return 0
}

# Regenerate the per-tool ports from the canonical commands/*.md first, so what
# gets installed always reflects the current canonical (hand-edits to a generated
# port are overwritten here — edit commands/<name>.md instead). Abort on failure
# rather than installing from a half-rendered port dir (a swallowed render error
# is how codex/cursor/gemini once silently got zero commands).
if [ -x "$DIR/render-commands.sh" ]; then
  "$DIR/render-commands.sh" >/dev/null \
    || { echo "render-commands.sh failed — aborting before install (ports may be stale)" >&2; exit 1; }
fi

# Command basenames we've renamed/dropped. Pruned on every install (per tool, in
# that tool's extension) so a rename self-heals across `git pull && install`.
RETIRED="validate handoff flow tidy critique audit"

# Back up to a collision-free name (mktemp), keeping only the 5 newest backups.
# Sets BACKUP_PATH to the created backup so callers can point the user at it.
backup_file() {  # $1 = file to back up
  BACKUP_PATH="$(mktemp "$1.bak.XXXXXX")"
  cp "$1" "$BACKUP_PATH"
  local n=0 b
  while IFS= read -r b; do n=$((n+1)); if [ "$n" -gt 5 ]; then rm -f -- "$b"; fi; done \
    < <(ls -1t -- "$1".bak.* 2>/dev/null)
  return 0   # prune's last test is usually false; don't let the fn return 1 under set -e
}

# Copy every <src>/*.<ext> into <dest>, backing up a differing prior copy first,
# skipping README and pruning retired names.
install_dir() {  # $1=label  $2=src dir  $3=ext  $4=dest dir  $5=1 to skip skill-backed names
  local label="$1" src="$2" ext="$3" dest="$4" f base dst n=0 old rc prior
  if [ ! -d "$src" ]; then echo "  $label: no $src (skipped)"; return 0; fi
  mkdir -p "$dest"
  for old in $RETIRED; do
    # Backed up before removal: a retired name is generic enough (e.g. "audit")
    # that the file could be the user's own, not our stale install.
    if [ -f "$dest/$old.$ext" ]; then
      backup_file "$dest/$old.$ext"; rm -f "$dest/$old.$ext"
      echo "  removed retired /$old (backup: $BACKUP_PATH)"
    fi
  done
  for f in "$src"/*."$ext"; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    [ "$base" = "README.$ext" ] && continue
    dst="$dest/$base"
    # Skill-backed: this tool gets the real skill (install_skill_link), not the
    # wrapper command — skip it, pruning an installed copy (backed up if edited).
    if [ "${5:-0}" = 1 ] && skill_backed "${base%.*}"; then
      if [ -f "$dst" ]; then
        if cmp -s "$f" "$dst"; then
          rm -f "$dst"; echo "  removed $base (the vendored skill installs instead)"
        else
          backup_file "$dst"; rm -f "$dst"
          echo "  removed $base (the vendored skill installs instead; your edited copy: $BACKUP_PATH)"
        fi
      fi
      continue
    fi
    # Group filter: a command not in the requested groups is skipped, and pruned
    # from the destination if present (so turning a group off self-heals). rc=2
    # (persona resolver failed) skips the install but leaves an existing copy.
    rc=0; cmd_wanted "${base%.*}" || rc=$?
    if [ "$rc" != 0 ]; then
      if [ "$rc" = 1 ] && [ -f "$dst" ]; then
        if cmp -s "$f" "$dst"; then
          rm -f "$dst"; echo "  removed $base (not in requested groups)"
        else
          backup_file "$dst"; rm -f "$dst"   # preserve the hand-edited copy before pruning
          echo "  removed $base (not in requested groups; your edited copy: $BACKUP_PATH)"
        fi
      fi
      continue
    fi
    if [ ! -f "$dst" ]; then
      # A prior prune may have archived a hand-edited copy — point at it rather
      # than silently installing canonical over the user's customizations.
      # shellcheck disable=SC2012  # need newest-first (mtime); names are mktemp-safe
      prior="$(ls -1t -- "$dst".bak.* 2>/dev/null | head -n 1 || true)"
      if [ -n "$prior" ] && ! cmp -s "$f" "$prior"; then
        echo "  note: $base installed from canonical; your earlier edited copy is at $prior"
      fi
    fi
    if [ -f "$dst" ] && ! cmp -s "$f" "$dst"; then backup_file "$dst"; echo "  backed up your edited $base"; fi
    cp "$f" "$dst"; n=$((n+1))
  done
  echo "  $label -> $dest ($n command(s))"
}

install_codex_skills() {
  local src="$SRC/codex" dest="$HOME/.codex/skills" skill source target rc n=0 gen=" "
  mkdir -p "$dest"
  for source in "$src"/*/SKILL.md; do
    [ -f "$source" ] || continue
    skill="$(basename "$(dirname "$source")")"
    # Skill-backed: the real skill is symlinked in by install_skill_link; by not
    # marking the generated port as ours here, the GENERATED-marker prune below
    # removes a previously installed wrapper (a symlinked real skill has no
    # marker, so it is never touched by that prune).
    skill_backed "$skill" && continue
    gen="$gen$skill "
    target="$dest/$skill/SKILL.md"
    # Never write through a symlinked skill dir (cp would clobber the vendored
    # source in the repo). A link WE created (a formerly skill-backed name)
    # is removed so the wrapper installs fresh; a foreign link is left alone.
    if [ -L "$dest/$skill" ]; then
      if is_our_skill_link "$dest/$skill"; then
        rm -f "$dest/$skill"
      else
        echo "  note: $dest/$skill is a symlink not managed by this repo; skipped"
        continue
      fi
    fi
    rc=0; cmd_wanted "$skill" || rc=$?
    if [ "$rc" != 0 ]; then
      if [ "$rc" = 1 ] && [ -f "$target" ]; then
        rm -f "$target"; rmdir "$dest/$skill" 2>/dev/null || true
      fi
      continue
    fi
    mkdir -p "$(dirname "$target")"
    if [ -f "$target" ] && ! cmp -s "$source" "$target"; then backup_file "$target"; echo "  backed up your edited $skill skill"; fi
    cp "$source" "$target"; n=$((n+1))
  done
  # Prune an installed skill whose canonical command was renamed/removed (self-heal
  # across `git pull && install`, same intent as install_dir's RETIRED list) — only
  # ever remove one we generated (GENERATED marker), never a hand-authored skill.
  for target in "$dest"/*/SKILL.md; do
    [ -f "$target" ] || continue
    skill="$(basename "$(dirname "$target")")"
    case "$gen" in *" $skill "*) continue;; esac
    grep -q '^<!-- GENERATED from commands/' "$target" 2>/dev/null || continue
    rm -f "$target"; rmdir "$dest/$skill" 2>/dev/null || true
    echo "  removed retired \$$skill skill"
  done
  for source in "$HOME/.codex/prompts"/*.md; do
    [ -f "$source" ] || continue
    if grep -q '^# GENERATED from commands/' "$source"; then rm -f "$source"; fi
  done
  echo "  codex -> $dest ($n skill(s); invoke \$<name>)"
}

for t in "${targets[@]}"; do
  case "$t" in
    claude)
      if [ "$PROJECT" = 1 ]; then d="$DIR/.claude/commands"; else d="$HOME/.claude/commands"; fi
      install_dir claude "$SRC" md "$d" 1
      # --project: the repo's own .claude/skills/ symlinks already cover it.
      [ "$PROJECT" = 1 ] || install_skill_link "$HOME/.claude/skills";;
    codex)
      install_codex_skills
      install_skill_link "$HOME/.codex/skills"
      [ "$PROJECT" = 1 ] && echo "  (Codex skills are global; --project has no effect for codex)";;
    cursor)
      if [ "$PROJECT" = 1 ]; then d="$DIR/.cursor/commands"; else d="$HOME/.cursor/commands"; fi
      install_dir cursor "$SRC/cursor" md "$d" 1
      # --project: the repo's own .cursor/skills/ symlinks already cover it.
      [ "$PROJECT" = 1 ] || install_skill_link "$HOME/.cursor/skills";;
    gemini)
      if [ "$PROJECT" = 1 ]; then d="$DIR/.gemini/commands"; else d="$HOME/.gemini/commands"; fi
      install_dir gemini "$SRC/gemini" toml "$d";;
    antigravity)
      echo "  antigravity: command install not supported here (Antigravity CLI is a separate tool); skipped — its hooks are wired by install-hooks.sh";;
  esac
done
echo "Done. Type / in each tool to see the commands (Codex: use \$<name>)."
