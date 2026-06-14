#!/usr/bin/env bash
# Customize this AI instruction set for YOUR context by answering a few
# questions, then write finalized file(s). Source of truth is template.md.
#
#   ./customize.sh             interactive — asks questions, then writes output
#   ./customize.sh --print     non-interactive — render to stdout (uses defaults
#                              + my-context.env if present)
#   ./customize.sh --project   non-interactive — write AGENTS/CLAUDE/GEMINI.md
#                              into this directory (uses defaults + my-context.env)
#
# Defaults are GENERIC on purpose (this is a shareable template). To keep your
# own answers without editing this script or committing them, copy
# my-context.env.example -> my-context.env (gitignored) and set your values.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$DIR/template.md"
[ -f "$TEMPLATE" ] || { echo "Missing template: $TEMPLATE" >&2; exit 1; }

# ---- generic defaults (overridable by my-context.env) -----------------------
NAME="Your full name"
CALL_ME="your name"
PRONOUNS="they/them"
ROLE="your role"
TIMEZONE="your timezone & city"
CARES="quality work and shipping fast"
ENVIRONMENT=""                 # optional; if empty, the Environment line is omitted
PREVIEW="local"                # tailscale | local | none
TS_HOST="your-host.ts.net"
TS_IP=""
AUTONOMY="aggressive"          # aggressive | balanced
TEAM_ROLES="front-end engineer, back-end engineer, technical architect, product designer, UI designer, UX researcher"
MCP_RULES=""                   # per-server "when to use" bullets; usually filled by --scan-mcp
INC_MEMORY="y"; INC_TEAMS="y"; INC_VALIDATE="y"; INC_TOOLS="y"; INC_ARTIFACTS="y"; INC_PROJECT="y"; INC_DOCS="y"; INC_CORRECTIONS="y"

MEM_BLOCK='  - A dedicated memory store on this machine — e.g. an agent "memory OS" with identity/values files, curated user facts, and per-agent memory directories.
  - Any `MEMORY.md` / `memory/` directory, or `AGENTS.md` / `CLAUDE.md`, shipped by the project or tool you'\''re running under.'

# Local, gitignored overrides (your personal answers live here, not in git):
[ -f "$DIR/my-context.env" ] && . "$DIR/my-context.env"
# Scanned MCP rules live in their own gitignored file (see --scan-mcp):
[ -f "$DIR/mcp-rules.local" ] && MCP_RULES="$(cat "$DIR/mcp-rules.local")"

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

# Escape a value for safe use on the right-hand side of sed s|...|...| .
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# ---- render(): filter sections + substitute vars, print to stdout -----------
render() {
  local keep=":"
  [ -n "$ENVIRONMENT" ]        && keep="${keep}env-desc:"
  [ "$INC_MEMORY" = "y" ]      && keep="${keep}memory-os:"
  [ "$AUTONOMY" = "aggressive" ] && keep="${keep}autonomy-aggressive:" || keep="${keep}autonomy-balanced:"
  [ "$INC_TEAMS" = "y" ]       && keep="${keep}agent-teams:"
  [ "$INC_VALIDATE" = "y" ]    && keep="${keep}validate:"
  [ "$INC_TOOLS" = "y" ]       && keep="${keep}tools-mcp:"
  [ "$INC_ARTIFACTS" = "y" ]   && keep="${keep}artifacts:"
  case "$PREVIEW" in
    tailscale) keep="${keep}preview-tailscale:";;
    local)     keep="${keep}preview-local:";;
  esac
  [ "$INC_PROJECT" = "y" ]     && keep="${keep}project-instructions:"
  [ "$INC_DOCS" = "y" ]        && keep="${keep}docs-first:"
  [ "$INC_CORRECTIONS" = "y" ] && keep="${keep}corrections:"

  local memfile; memfile="$(mktemp)"; printf '%s\n' "$MEM_BLOCK" > "$memfile"
  local mcpfile; mcpfile="$(mktemp)"; printf '%s' "$MCP_RULES" > "$mcpfile"

  awk -v keep="$keep" '
    BEGIN { drop=0 }
    {
      line=$0
      if (line ~ /<!--SECTION:[a-z-]+-->/) {
        n=line; sub(/^.*<!--SECTION:/,"",n); sub(/-->.*$/,"",n)
        if (drop) next
        if (index(keep, ":" n ":")>0) next
        drop=1; dropname=n; next
      }
      if (line ~ /<!--\/SECTION:[a-z-]+-->/) {
        n=line; sub(/^.*<!--\/SECTION:/,"",n); sub(/-->.*$/,"",n)
        if (drop && n==dropname) drop=0
        next
      }
      if (!drop) print line
    }
  ' "$TEMPLATE" \
  | awk -v f="$memfile" '/{{MEMORY_PATHS}}/{while((getline l < f)>0) print l; next} {print}' \
  | awk -v f="$mcpfile" '/{{MCP_RULES}}/{while((getline l < f)>0) print l; next} {print}' \
  | sed -e "s|{{NAME}}|$(esc "$NAME")|g" \
        -e "s|{{CALL_ME}}|$(esc "$CALL_ME")|g" \
        -e "s|{{PRONOUNS}}|$(esc "$PRONOUNS")|g" \
        -e "s|{{ROLE}}|$(esc "$ROLE")|g" \
        -e "s|{{TIMEZONE}}|$(esc "$TIMEZONE")|g" \
        -e "s|{{CARES}}|$(esc "$CARES")|g" \
        -e "s|{{ENVIRONMENT}}|$(esc "$ENVIRONMENT")|g" \
        -e "s|{{TEAM_ROLES}}|$(esc "$TEAM_ROLES")|g" \
        -e "s|{{TS_HOST}}|$(esc "$TS_HOST")|g" \
        -e "s|{{TS_IP}}|$(esc "$TS_IP")|g"

  rm -f "$memfile" "$mcpfile"
}

write_project() {
  render > "$DIR/AGENTS.md";  echo "  wrote $DIR/AGENTS.md"
  cp "$DIR/AGENTS.md" "$DIR/CLAUDE.md"; echo "  wrote $DIR/CLAUDE.md"
  cp "$DIR/AGENTS.md" "$DIR/GEMINI.md"; echo "  wrote $DIR/GEMINI.md"
}

# ---- non-interactive paths --------------------------------------------------
case "${1:-}" in
  --print)    render; exit 0;;
  --project)  write_project; exit 0;;
  --scan-mcp) scan_mcp; exit 0;;
esac

# ---- prompts ----------------------------------------------------------------
ask()    { local v; read -r -p "$1 [$2]: " v </dev/tty || true; printf '%s' "${v:-$2}"; }
ask_one(){ local v; read -r -p "$1 ($2): " v </dev/tty || true; printf '%s' "${v:-$2}"; }

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
PREVIEW="$(ask_one 'Preview method' "tailscale/local/none")"
case "$PREVIEW" in tail*) PREVIEW="tailscale";; non*) PREVIEW="none";; *) PREVIEW="local";; esac
if [ "$PREVIEW" = "tailscale" ]; then
  TS_HOST="$(ask 'Tailscale MagicDNS hostname' "$TS_HOST")"
  TS_IP="$(ask 'Tailscale IP' "$TS_IP")"
fi

echo ""
echo "-- How you like work done --"
AUTONOMY="$(ask_one 'Autonomy posture' "aggressive/balanced")"
case "$AUTONOMY" in bal*) AUTONOMY="balanced";; *) AUTONOMY="aggressive";; esac

INC_TEAMS="$(ask_one 'Include "agent teams & subagents" section?' "y/n")"; INC_TEAMS="${INC_TEAMS:0:1}"
if [ "$INC_TEAMS" = "y" ]; then
  TEAM_ROLES="$(ask 'Roles you draw from (comma-separated)' "$TEAM_ROLES")"
fi

INC_VALIDATE="$(ask_one 'Include "validate after larger changes" section?' "y/n")"; INC_VALIDATE="${INC_VALIDATE:0:1}"
INC_TOOLS="$(ask_one 'Include "tools & MCP servers" section?' "y/n")"; INC_TOOLS="${INC_TOOLS:0:1}"
if [ "$INC_TOOLS" = "y" ]; then
  DO_SCAN="$(ask_one 'Scan this machine'\''s MCP servers and add usage rules?' "y/n")"
  [ "${DO_SCAN:0:1}" = "y" ] && scan_mcp interactive
fi

echo ""
echo "-- Optional sections --"
INC_MEMORY="$(ask_one 'Include "look for a memory OS" section?' "y/n")";       INC_MEMORY="${INC_MEMORY:0:1}"
INC_ARTIFACTS="$(ask_one 'Include "output artifacts" (HTML default) section?' "y/n")"; INC_ARTIFACTS="${INC_ARTIFACTS:0:1}"
INC_PROJECT="$(ask_one 'Include "encourage project-specific instructions" section?' "y/n")"; INC_PROJECT="${INC_PROJECT:0:1}"
INC_DOCS="$(ask_one 'Include "documentation first" section?' "y/n")";          INC_DOCS="${INC_DOCS:0:1}"
INC_CORRECTIONS="$(ask_one 'Include "when I say you did wrong" section?' "y/n")"; INC_CORRECTIONS="${INC_CORRECTIONS:0:1}"

# ---- output target ----------------------------------------------------------
echo ""
echo "Where should the finalized instructions be written?"
echo "  1) This project dir (AGENTS.md + CLAUDE.md + GEMINI.md)            [default]"
echo "  2) Global config on this machine (~/.claude, ~/AGENTS.md, ~/.codex, ~/.gemini)"
echo "  3) A custom file path"
echo "  4) Print to screen only"
TARGET="$(ask_one 'Choose' "1/2/3/4")"; TARGET="${TARGET:-1}"

case "$TARGET" in
  2)
    echo ""; echo "This OVERWRITES your machine-wide instructions:"
    echo "  ~/.claude/CLAUDE.md  ~/AGENTS.md  ~/.codex/AGENTS.md  ~/.gemini/GEMINI.md"
    CONFIRM="$(ask_one 'Proceed?' "y/N")"
    case "$CONFIRM" in [Yy]*) ;; *) echo "Aborted."; exit 0;; esac
    mkdir -p "$HOME/.codex" "$HOME/.gemini"
    render > "$HOME/.claude/CLAUDE.md";  echo "  wrote ~/.claude/CLAUDE.md"
    render > "$HOME/AGENTS.md";          echo "  wrote ~/AGENTS.md"
    render > "$HOME/.codex/AGENTS.md";   echo "  wrote ~/.codex/AGENTS.md"
    render > "$HOME/.gemini/GEMINI.md";  echo "  wrote ~/.gemini/GEMINI.md"
    ;;
  3)
    OUT="$(ask 'Output file path' "$DIR/AGENTS.md")"; render > "$OUT"; echo "  wrote $OUT";;
  4)
    echo ""; render;;
  *)
    write_project;;
esac

echo "Done."
