#!/usr/bin/env bash
# render-roles.sh — generate the Codex dialect of the team roles from the
# canonical Claude-dialect definitions in roles/*.md, so there is ONE source of
# truth per role and the two tools can't drift.
#
#   ./render-roles.sh            # regenerate roles/codex/*.toml
#
# Why two dialects at all: Claude Code reads subagent definitions as markdown
# with YAML frontmatter (~/.claude/agents/<name>.md); Codex reads custom agents
# as standalone TOML (~/.codex/agents/<name>.toml). Same role, same
# instructions, different file format — so we write it once and render.
#
# Field mapping (canonical -> Codex):
#   name            -> name
#   description     -> description
#   body            -> developer_instructions   (''' literal string, no escaping)
#   sandbox         -> sandbox_mode             (omitted => inherits the parent turn)
#   effort          -> model_reasoning_effort   (omitted => inherits the parent)
#   reminder        -> NOT a TOML key. Codex has no reminder field and rejects
#                      nothing it doesn't document at our peril, so the reminder
#                      reaches Codex the only way it can have an effect: inside
#                      developer_instructions, as the line the body opens and
#                      closes with. This script does not inject it -- it VERIFIES
#                      the author wrote it, and fails the render if the
#                      frontmatter and the body have drifted apart. Same string,
#                      three places, one check.
#   tools           -> dropped. Codex has no per-agent tool allowlist; its tool
#                      surface is governed by sandbox_mode and mcp_servers.
#   model           -> deliberately never set on either side, so a role inherits
#                      whatever model the session is running. Pinning a model id
#                      here would rot every time a vendor ships a new one.
#
# The generated files are snapshots — NEVER hand-edit them (install-roles.sh
# re-renders on every install). Edit roles/<name>.md and re-render. The Codex
# port is gitignored, like the command ports.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/roles"
OUT="$SRC/codex"
[ -d "$SRC" ] || { echo "No roles/ dir at $SRC" >&2; exit 1; }

# --- frontmatter / body extractors (CR-stripped so CRLF files parse) ---------
fm_field() {  # $1 = file, $2 = key  -> prints the trimmed value (empty if absent)
  awk -v key="$2" '
    { sub(/\r$/,"") }
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && $0 ~ ("^" key ":") {
      v=$0; sub("^" key ":[[:space:]]*","",v); gsub(/[[:space:]]+$/,"",v)
      # tolerate a quoted scalar so a value needing quotes still compares equal
      if (v ~ /^".*"$/ || v ~ /^'"'"'.*'"'"'$/) v = substr(v, 2, length(v) - 2)
      print v; exit
    }
  ' "$1"
}

fm_body() {  # $1 = file -> body after the frontmatter (leading blanks trimmed)
  awk '
    { sub(/\r$/,"") }
    NR==1 && $0!="---" { plain=1 }
    plain { print; next }
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { infm=0; started=1; next }
    started && !body && $0 ~ /^[[:space:]]*$/ { next }
    started { body=1; print }
  ' "$1"
}

dq_escape() { sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }   # for TOML "..." values

mkdir -p "$OUT"
n=0
for f in "$SRC"/*.md; do
  [ -e "$f" ] || continue
  base="$(basename "$f" .md)"
  [ "$base" = "README" ] && continue
  name="$(fm_field "$f" name)";        [ -n "$name" ] || name="$base"
  desc="$(fm_field "$f" description)"
  sandbox="$(fm_field "$f" sandbox)"
  effort="$(fm_field "$f" effort)"
  reminder="$(fm_field "$f" reminder)"
  body="$(fm_body "$f")"

  # The reminder is the role's hard rules in one line. It exists three times on
  # purpose -- frontmatter, first body line, last body line -- because a role
  # definition is read once at spawn and never restated, and that is exactly
  # where a long agent run drifts. Three copies only help while they agree, so
  # disagreement is a render failure, not a warning.
  [ -n "$reminder" ] || { echo "render-roles: $base is missing a 'reminder:' frontmatter key" >&2; exit 1; }
  want="**Reminder:** $reminder"
  first="$(printf '%s\n' "$body" | grep -m1 -v '^[[:space:]]*$' || true)"
  last="$(printf '%s\n' "$body" | grep -v '^[[:space:]]*$' | tail -n1 || true)"
  [ "$first" = "$want" ] || { echo "render-roles: $base body must OPEN with the reminder line:" >&2; echo "  want: $want" >&2; echo "  got:  $first" >&2; exit 1; }
  [ "$last" = "$want" ]  || { echo "render-roles: $base body must CLOSE with the reminder line:" >&2; echo "  want: $want" >&2; echo "  got:  $last" >&2; exit 1; }

  # A ''' inside the body would close the literal string early. No role uses one;
  # fail loudly rather than emit a broken TOML file if that ever changes.
  case "$body" in *"'''"*) echo "render-roles: $base body contains ''' — cannot render as a TOML literal string" >&2; exit 1;; esac

  {
    echo "# Generated by render-roles.sh from roles/$base.md — do not hand-edit."
    echo "# Codex custom agent: ~/.codex/agents/$name.toml"
    echo "name = \"$(printf '%s' "$name" | dq_escape)\""
    [ -n "$desc" ] && echo "description = \"$(printf '%s' "$desc" | dq_escape)\""
    [ -n "$sandbox" ] && echo "sandbox_mode = \"$(printf '%s' "$sandbox" | dq_escape)\""
    [ -n "$effort" ] && echo "model_reasoning_effort = \"$(printf '%s' "$effort" | dq_escape)\""
    echo "developer_instructions = '''"
    printf '%s\n' "$body"
    echo "'''"
  } > "$OUT/$name.toml"
  n=$((n+1))
done
echo "render-roles: wrote $n Codex role file(s) to $OUT"
