#!/usr/bin/env bash
# Customize this AI instruction set for YOUR context by answering a few
# questions, then write finalized file(s). Source of truth is template.md.
#
#   ./customize.sh             interactive — asks questions, then writes output
#   ./customize.sh --print     non-interactive — render to stdout (uses defaults
#                              + my-context.env if present)
#   ./customize.sh --project   non-interactive — write AGENTS/CLAUDE/GEMINI.md
#                              into this directory (uses defaults + my-context.env)
#   ./customize.sh --global    non-interactive — write the machine-wide files
#                              (~/.claude, ~/AGENTS.md, ~/.codex, ~/.gemini)
#   ./customize.sh --scan-mcp  detect MCP servers and write mcp-rules.local
#
# Defaults are GENERIC on purpose (this is a shareable template). To keep your
# own answers without editing this script or committing them, copy
# my-context.env.example -> my-context.env (gitignored) and set your values.
#
# Env knobs: set any variable below in the environment to override a default
# (e.g. PREVIEW=tailscale ./customize.sh --print). Set AIGI_NO_USER_ENV=1 to
# ignore my-context.env / mcp-rules.local (used by the examples and test.sh).
set -euo pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 3 ] || { [ "${BASH_VERSINFO[0]:-0}" -eq 3 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 2 ]; }; then
  echo "customize.sh needs bash 3.2+ (found ${BASH_VERSION:-unknown})." >&2
  exit 1
fi

DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$DIR/template.md"
[ -f "$TEMPLATE" ] || { echo "Missing template: $TEMPLATE" >&2; exit 1; }

# ---- single source of truth for variable names ------------------------------
# Adding a template {{VAR}} is a one-line change here: SUBST_VARS drives both the
# values handed to awk and the substitution loop, and all three lists drive the
# load_env allowlist — nothing to keep in sync by hand.
SUBST_VARS=(NAME CALL_ME PRONOUNS ROLE TIMEZONE CARES ENVIRONMENT TEAM_ROLES TS_HOST TS_IP)  # {{VAR}} <-> $VAR
CTRL_VARS=(PREVIEW AUTONOMY MEM_BLOCK)                                                        # control render, not substituted
INC_VARS=(INC_MEMORY INC_TEAMS INC_VALIDATE INC_TOOLS INC_ARTIFACTS INC_PROJECT INC_DOCS INC_CORRECTIONS)

# ---- temp-file cleanup (no leaks on error paths) ----------------------------
TMPFILES=()
cleanup() { [ ${#TMPFILES[@]} -gt 0 ] && rm -f "${TMPFILES[@]}" || true; }
trap cleanup EXIT
# mktmp [dir]: temp file in $dir (default $TMPDIR). render_to passes the
# destination's dir so the later mv is a same-filesystem (atomic) rename.
mktmp() {
  local d="${1:-${TMPDIR:-/tmp}}" t
  t="$(mktemp "$d/.aigi.XXXXXX" 2>/dev/null)" || { echo "mktemp failed in $d" >&2; return 1; }
  TMPFILES+=("$t"); printf '%s' "$t"
}

# ---- generic defaults (override via env or my-context.env) -------------------
# `: "${VAR:=default}"` keeps an inherited environment value if one is set.
: "${NAME:=Your full name}"
: "${CALL_ME:=your name}"
: "${PRONOUNS:=they/them}"
: "${ROLE:=your role}"
: "${TIMEZONE:=your timezone & city}"
: "${CARES:=quality work and shipping fast}"
: "${ENVIRONMENT:=}"            # optional; if empty, the Environment line is omitted
: "${PREVIEW:=local}"          # tailscale | local | none
: "${TS_HOST:=your-host.ts.net}"
: "${TS_IP:=}"
: "${AUTONOMY:=aggressive}"    # aggressive | balanced
: "${TEAM_ROLES:=front-end engineer, back-end engineer, technical architect, product designer, UI designer, UX researcher}"
: "${MCP_RULES:=}"             # per-server "when to use" bullets; usually filled by --scan-mcp
: "${INC_MEMORY:=y}"; : "${INC_TEAMS:=y}"; : "${INC_VALIDATE:=y}"; : "${INC_TOOLS:=y}"
: "${INC_ARTIFACTS:=y}"; : "${INC_PROJECT:=y}"; : "${INC_DOCS:=y}"; : "${INC_CORRECTIONS:=y}"

if [ -z "${MEM_BLOCK:-}" ]; then
  MEM_BLOCK='  - A dedicated memory store on this machine — e.g. an agent "memory OS" with identity/values files, curated user facts, and per-agent memory directories.
  - Any `MEMORY.md` / `memory/` directory, or `AGENTS.md` / `CLAUDE.md`, shipped by the project or tool you'\''re running under.'
fi

# ---- safe loader: parse KEY=VALUE (NO sourcing => no code execution) ---------
# Only allow-listed keys are honored; values may be single/double quoted and may
# span multiple lines while inside quotes. Assignment is via printf -v, never eval.
# A value's closing quote must end its line (the natural shell style); the
# continuation loop reads further lines only while the quote is still open.
load_env() {
  local file="$1" line key val rest
  # POSIX single-quote idiom '\'' and its replacement ', built into vars so the
  # //-substitution below takes both operands literally. bash 3.2 (macOS) keeps
  # backslashes in an inline pattern/replacement, so inline forms misbehave.
  local sq_idiom sq_repl; printf -v sq_idiom "%s" "'\\''"; printf -v sq_repl "%s" "'"
  # Space-delimited allowlist (bash 3.2 has no associative arrays). Keys are
  # plain identifiers, so a padded substring test is exact and safe.
  local ALLOWED=" ${SUBST_VARS[*]} ${CTRL_VARS[*]} ${INC_VARS[*]} "
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"                       # tolerate CRLF (Windows) files
    case "$line" in ''|'#'*) continue;; esac
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"; key="${key//[[:space:]]/}"
    [[ "$ALLOWED" == *" $key "* ]] || continue
    val="${line#*=}"
    case "$val" in
      \"*) val="${val#\"}"
           while [[ "$val" != *\" ]]; do
             IFS= read -r rest || { echo "load_env: unterminated \" for $key in ${file##*/} — ignoring" >&2; continue 2; }
             val="$val"$'\n'"${rest%$'\r'}"
           done
           val="${val%\"}";;
      \'*) val="${val#\'}"
           while [[ "$val" != *\' ]]; do
             IFS= read -r rest || { echo "load_env: unterminated ' for $key in ${file##*/} — ignoring" >&2; continue 2; }
             val="$val"$'\n'"${rest%$'\r'}"
           done
           val="${val%\'}"
           val="${val//"$sq_idiom"/$sq_repl}";;   # POSIX '\'' -> '
      *)   val="${val#"${val%%[![:space:]]*}"}" # unquoted: trim surrounding whitespace
           val="${val%"${val##*[![:space:]]}"}";;
    esac
    printf -v "$key" '%s' "$val"
  done < "$file"
}

if [ -z "${AIGI_NO_USER_ENV:-}" ]; then
  [ -f "$DIR/my-context.env" ] && load_env "$DIR/my-context.env"
  [ -f "$DIR/mcp-rules.local" ] && MCP_RULES="$(cat "$DIR/mcp-rules.local")"
fi

# ---- MCP detection ----------------------------------------------------------
# Print the names of MCP servers configured for Claude Code on this machine.
detect_mcps() {
  command -v claude >/dev/null 2>&1 || return 0
  claude mcp list 2>/dev/null \
    | grep -E ': https?://' \
    | sed -E 's/: https?:\/\/.*$//; s/[[:space:]]+$//' \
    | awk 'NF && !seen[$0]++'
}

# Suggest a default "when to use" rule for a server, by name.
suggest_rule() {
  local n; n="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$n" in
    *notion*work*)     echo "**Notion (work)** — work notes, projects, and docs; keep separate from personal.";;
    *notion*personal*) echo "**Notion (personal)** — personal notes only; keep separate from work.";;
    *notion*)          echo "**Notion** — notes and docs.";;
    *gmail*)           echo "**Gmail** — read/search freely; draft replies but never send without my confirmation.";;
    *calendar*)        echo "**Calendar** — read/check freely; never create, change, or RSVP to events without my confirmation.";;
    *drive*)           echo "**Google Drive** — read/search freely; ask before creating or overwriting files.";;
    *figma*)           echo "**Figma** — pull designs and specs for reference.";;
    *robinhood*)       echo "**Robinhood** — read positions/quotes only; NEVER place, cancel, or modify orders without my explicit confirmation.";;
    *)                 echo "**$1** — (describe when to use this).";;
  esac
}

# Build MCP_RULES from detected servers + suggested defaults, save to
# mcp-rules.local (gitignored). $1=interactive lets you edit each rule.
scan_mcp() {
  local names out="" n def rule
  names="$(detect_mcps)"
  if [ -z "$names" ]; then
    echo "No MCP servers detected (needs the 'claude' CLI with servers configured)."; return 0
  fi
  echo "Detected MCP servers:"; printf '%s\n' "$names" | sed 's/^/  - /'; echo ""
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    def="$(suggest_rule "$n")"
    if [ "${1:-}" = "interactive" ]; then rule="$(ask "Rule for '$n'" "$def")"; else rule="$def"; fi
    out="${out}${out:+
}- ${rule}"
  done <<< "$names"
  printf '%s\n' "$out" > "$DIR/mcp-rules.local"
  MCP_RULES="$out"
  echo ""; echo "Saved $DIR/mcp-rules.local"
}

# ---- render(): filter sections + substitute vars, print to stdout -----------
# One awk pass. Variable values are passed through the environment (ENVIRON[],
# which performs NO escape processing), and substituted literally — so newlines,
# backslashes, ampersands, pipes, and braces in any value are safe. Section
# nesting is handled with a depth counter, so blocks can nest arbitrarily.
render() {
  local keep=":"
  [ -n "$ENVIRONMENT" ]          && keep="${keep}env-desc:"
  [ "$INC_MEMORY" = "y" ]        && keep="${keep}memory-os:"
  [ "$AUTONOMY" = "aggressive" ] && keep="${keep}autonomy-aggressive:" || keep="${keep}autonomy-balanced:"
  [ "$INC_TEAMS" = "y" ]         && keep="${keep}agent-teams:"
  [ "$INC_VALIDATE" = "y" ]      && keep="${keep}validate:"
  [ "$INC_TOOLS" = "y" ]         && keep="${keep}tools-mcp:"
  [ "$INC_ARTIFACTS" = "y" ]     && keep="${keep}artifacts:"
  case "$PREVIEW" in
    tailscale) keep="${keep}preview-tailscale:";;
    local)     keep="${keep}preview-local:";;
  esac
  [ "$INC_PROJECT" = "y" ]       && keep="${keep}project-instructions:"
  [ "$INC_DOCS" = "y" ]          && keep="${keep}docs-first:"
  [ "$INC_CORRECTIONS" = "y" ]   && keep="${keep}corrections:"

  # Pass values via the environment (ENVIRON[] does NO escape processing) using
  # `env`, so nothing leaks into the calling shell. SUBST_VARS drives both the
  # passthrough and the awk substitution loop.
  local v envargs=(AIGI_KEEP="$keep" AIGI_MEMORY_PATHS="$MEM_BLOCK" AIGI_MCP_RULES="$MCP_RULES" "AIGI_SUBST_VARS=${SUBST_VARS[*]}")
  for v in "${SUBST_VARS[@]}"; do envargs+=("AIGI_$v=${!v}"); done

  env "${envargs[@]}" awk '
    # Single left-to-right pass: copy literal text, and on each {{KEY}} emit the
    # mapped value WITHOUT re-scanning it — so a value that itself contains
    # "{{OTHER}}" is never re-expanded (order-independent, values stay literal).
    function render_line(s,   out, i, j, key) {
      out = ""
      while ((i = index(s, "{{")) > 0) {
        j = index(substr(s, i + 2), "}}")
        if (j == 0) break                              # no closing braces: rest is literal
        key = substr(s, i + 2, j - 1)
        out = out substr(s, 1, i - 1)
        out = out (key in val ? val[key] : "{{" key "}}")   # unknown placeholder: leave literal
        s = substr(s, i + j + 3)
      }
      return out s
    }
    BEGIN {
      keep = ENVIRON["AIGI_KEEP"]; drop = 0
      nv = split(ENVIRON["AIGI_SUBST_VARS"], vars, " ")
      for (k = 1; k <= nv; k++) val[vars[k]] = ENVIRON["AIGI_" vars[k]]
    }
    {
      line = $0
      if (line ~ /<!--SECTION:[A-Za-z0-9_-]+-->/) {
        if (drop > 0) { drop++; next }                 # nested inside a dropped block
        n = line; sub(/^.*<!--SECTION:/, "", n); sub(/-->.*$/, "", n)
        if (index(keep, ":" n ":") > 0) next           # keep: strip marker line only
        drop = 1; next                                 # start dropping this block
      }
      if (line ~ /<!--\/SECTION:[A-Za-z0-9_-]+-->/) {
        if (drop > 0) { drop--; next }                 # close of a dropped (possibly nested) block
        next                                           # close of a kept block: strip marker
      }
      if (drop > 0) next

      if (line == "{{MEMORY_PATHS}}") { if (ENVIRON["AIGI_MEMORY_PATHS"] != "") printf "%s\n", ENVIRON["AIGI_MEMORY_PATHS"]; next }
      if (line == "{{MCP_RULES}}")    { if (ENVIRON["AIGI_MCP_RULES"]    != "") printf "%s\n", ENVIRON["AIGI_MCP_RULES"];    next }

      print render_line(line)
    }
  ' "$TEMPLATE"
}

# Render to a file atomically: temp file in the SAME dir as the destination, so
# the mv is a same-filesystem rename. A failed render never touches the dest and
# leaves no temp behind. Pass a second arg to back up an existing dest first.
render_to() {  # $1 = destination path, $2 = "backup" to save dest.bak.XXXXXX if it exists
  local dest="$1" tmp; tmp="$(mktmp "$(dirname "$dest")")" || return 1
  if ! render > "$tmp"; then rm -f "$tmp"; echo "Render failed; $dest left unchanged." >&2; return 1; fi
  if [ "${2:-}" = "backup" ] && [ -f "$dest" ] && ! cmp -s "$tmp" "$dest"; then
    cp "$dest" "$(mktemp "$dest.bak.XXXXXX")" && echo "  backed up existing $dest"
    local n=0 b
    while IFS= read -r b; do n=$((n+1)); if [ "$n" -gt 5 ]; then rm -f -- "$b"; fi; done \
      < <(ls -1t -- "$dest".bak.* 2>/dev/null)
  fi
  mv "$tmp" "$dest"
}

write_project() {
  render_to "$DIR/AGENTS.md" || return 1
  echo "  wrote $DIR/AGENTS.md"
  cp "$DIR/AGENTS.md" "$DIR/CLAUDE.md"; echo "  wrote $DIR/CLAUDE.md"
  cp "$DIR/AGENTS.md" "$DIR/GEMINI.md"; echo "  wrote $DIR/GEMINI.md"
}

# Machine-wide files are precious (you may have hand-curated them), so back up
# any existing copy before overwriting — mirroring install-commands/-hooks.sh.
write_global() {
  mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.gemini"
  render_to "$HOME/.claude/CLAUDE.md" backup && echo "  wrote ~/.claude/CLAUDE.md"
  render_to "$HOME/AGENTS.md"         backup && echo "  wrote ~/AGENTS.md"
  render_to "$HOME/.codex/AGENTS.md"  backup && echo "  wrote ~/.codex/AGENTS.md"
  render_to "$HOME/.gemini/GEMINI.md" backup && echo "  wrote ~/.gemini/GEMINI.md"
}

# ---- non-interactive paths --------------------------------------------------
case "${1:-}" in
  --print)    render; exit 0;;
  --project)  write_project; exit 0;;
  --global)
    echo "Writing machine-wide instruction files (overwrites them if present):"
    echo "  ~/.claude/CLAUDE.md  ~/AGENTS.md  ~/.codex/AGENTS.md  ~/.gemini/GEMINI.md"
    write_global; exit 0;;
  --scan-mcp) scan_mcp; exit 0;;
esac

# ---- prompts ----------------------------------------------------------------
# ask:     free-text with a [default] shown; Enter returns the default.
# ask_one: a choice; pass the menu to display AND the real default separately,
#          so Enter returns the default (not the menu string).
ask()    { local v; read -r -p "$1 [$2]: " v </dev/tty || true; printf '%s' "${v:-$2}"; }
ask_one(){ local v; read -r -p "$1 [$3] ($2): " v </dev/tty || true; printf '%s' "${v:-$3}"; }

echo "== Customize AI instructions =="
echo "(press Enter to accept the [default] in brackets)"
echo ""
echo "-- Who you are --"
NAME="$(ask 'Full name' "$NAME")"
CALL_ME="$(ask 'What to call you' "$CALL_ME")"
PRONOUNS="$(ask 'Pronouns' "$PRONOUNS")"
ROLE="$(ask 'Role / title' "$ROLE")"
TIMEZONE="$(ask 'Timezone & location' "$TIMEZONE")"
CARES="$(ask 'What you care about (one line)' "$CARES")"

echo ""
echo "-- Your environment --"
ENVIRONMENT="$(ask 'Describe your environment (optional; e.g. headless Linux server, or MacBook with browser)' "$ENVIRONMENT")"

echo ""
echo "-- How you preview / test web & HTML work --"
PREVIEW="$(ask_one 'Preview method' "tailscale/local/none" "$PREVIEW")"
case "$PREVIEW" in tail*) PREVIEW="tailscale";; non*) PREVIEW="none";; *) PREVIEW="local";; esac
if [ "$PREVIEW" = "tailscale" ]; then
  TS_HOST="$(ask 'Tailscale MagicDNS hostname' "$TS_HOST")"
  TS_IP="$(ask 'Tailscale IP' "$TS_IP")"
fi

echo ""
echo "-- How you like work done --"
AUTONOMY="$(ask_one 'Autonomy posture' "aggressive/balanced" "$AUTONOMY")"
case "$AUTONOMY" in bal*) AUTONOMY="balanced";; *) AUTONOMY="aggressive";; esac

INC_TEAMS="$(ask_one 'Include "agent teams & subagents" section?' "y/n" "$INC_TEAMS")"; INC_TEAMS="${INC_TEAMS:0:1}"
if [ "$INC_TEAMS" = "y" ]; then
  TEAM_ROLES="$(ask 'Roles you draw from (comma-separated)' "$TEAM_ROLES")"
fi

INC_VALIDATE="$(ask_one 'Include "validate after larger changes" section?' "y/n" "$INC_VALIDATE")"; INC_VALIDATE="${INC_VALIDATE:0:1}"
INC_TOOLS="$(ask_one 'Include "tools & MCP servers" section?' "y/n" "$INC_TOOLS")"; INC_TOOLS="${INC_TOOLS:0:1}"
if [ "$INC_TOOLS" = "y" ]; then
  DO_SCAN="$(ask_one 'Scan this machine'\''s MCP servers and add usage rules?' "y/n" "n")"
  [ "${DO_SCAN:0:1}" = "y" ] && scan_mcp interactive
fi

echo ""
echo "-- Optional sections --"
INC_MEMORY="$(ask_one 'Include "look for a memory OS" section?' "y/n" "$INC_MEMORY")";       INC_MEMORY="${INC_MEMORY:0:1}"
INC_ARTIFACTS="$(ask_one 'Include "output artifacts" (HTML default) section?' "y/n" "$INC_ARTIFACTS")"; INC_ARTIFACTS="${INC_ARTIFACTS:0:1}"
INC_PROJECT="$(ask_one 'Include "encourage project-specific instructions" section?' "y/n" "$INC_PROJECT")"; INC_PROJECT="${INC_PROJECT:0:1}"
INC_DOCS="$(ask_one 'Include "documentation first" section?' "y/n" "$INC_DOCS")";          INC_DOCS="${INC_DOCS:0:1}"
INC_CORRECTIONS="$(ask_one 'Include "when I say you did wrong" section?' "y/n" "$INC_CORRECTIONS")"; INC_CORRECTIONS="${INC_CORRECTIONS:0:1}"

# ---- output target ----------------------------------------------------------
echo ""
echo "Where should the finalized instructions be written?"
echo "  1) This project dir (AGENTS.md + CLAUDE.md + GEMINI.md)            [default]"
echo "  2) Global config on this machine (~/.claude, ~/AGENTS.md, ~/.codex, ~/.gemini)"
echo "  3) A custom file path"
echo "  4) Print to screen only"
TARGET="$(ask_one 'Choose' "1/2/3/4" "1")"

case "$TARGET" in
  2)
    echo ""; echo "This OVERWRITES your machine-wide instructions:"
    echo "  ~/.claude/CLAUDE.md  ~/AGENTS.md  ~/.codex/AGENTS.md  ~/.gemini/GEMINI.md"
    CONFIRM="$(ask_one 'Proceed?' "y/N" "N")"
    case "$CONFIRM" in [Yy]*) ;; *) echo "Aborted."; exit 0;; esac
    write_global
    ;;
  3)
    OUT="$(ask 'Output file path' "$DIR/AGENTS.md")"; render_to "$OUT" && echo "  wrote $OUT";;
  4)
    echo ""; render;;
  *)
    write_project;;
esac

echo "Done."
