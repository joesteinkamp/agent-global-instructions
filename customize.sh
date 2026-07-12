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
#                              (~/.claude, ~/AGENTS.md, ~/.codex, ~/.gemini).
#                              Prompts to confirm; add --yes (or -y) to skip the
#                              prompt for scripted / zero-prompt re-runs.
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

if [ "${BASH_VERSINFO[0]:-0}" -lt 3 ] \
   || { [ "${BASH_VERSINFO[0]:-0}" -eq 3 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 2 ]; }; then
  echo "customize.sh needs bash 3.2+ (found ${BASH_VERSION:-unknown})." >&2
  exit 1
fi

# Lowercase helper — bash 3.2 (macOS' system bash) lacks the ${var,,} expansion.
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$DIR/template.md"
[ -f "$TEMPLATE" ] || { echo "Missing template: $TEMPLATE" >&2; exit 1; }

# ---- single source of truth for variable names ------------------------------
# Adding a template {{VAR}} is a one-line change here: SUBST_VARS drives both the
# values handed to awk and the substitution loop, and all three lists drive the
# load_env allowlist — nothing to keep in sync by hand.
SUBST_VARS=(NAME CALL_ME PRONOUNS ROLE TIMEZONE CARES ENVIRONMENT TEAM_ROLES TS_HOST)  # {{VAR}} <-> $VAR
CTRL_VARS=(PREVIEW AUTONOMY PERSONA MEM_BLOCK MEM_KIND MEM_PATH MEM_TOOL)                     # control render, not substituted
INC_VARS=(INC_MEMORY INC_TEAMS INC_WORKTREES INC_IMPROVE INC_TOOLS INC_ARTIFACTS INC_DESIGN INC_PROJECT INC_DOCS INC_CORRECTIONS INC_CHANGELOG)

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
: "${AUTONOMY:=aggressive}"    # aggressive | balanced
: "${PERSONA:=generic}"        # product-designer | engineer | generic — seeds design-leaning defaults
: "${TEAM_ROLES:=front-end engineer, back-end engineer, technical architect, product designer, UI designer, UX researcher}"
: "${MCP_RULES:=}"             # per-server "when to use" bullets; usually filled by --scan-mcp
: "${INC_MEMORY:=y}"; : "${INC_TEAMS:=y}"; : "${INC_WORKTREES:=y}"; : "${INC_IMPROVE:=y}"; : "${INC_TOOLS:=y}"
: "${INC_ARTIFACTS:=y}"; : "${INC_PROJECT:=y}"; : "${INC_DOCS:=y}"; : "${INC_CORRECTIONS:=y}"; : "${INC_CHANGELOG:=y}"
# INC_DESIGN starts UNSET (empty) on purpose: the PERSONA preset seeds it in
# normalize_inputs() so "product-designer" turns the Design section on by default,
# while an explicit y/n from the environment or my-context.env always wins.
: "${INC_DESIGN:=}"            # y | n | "" (unset → seeded from PERSONA)

# Where the user's memory / notes actually live. MEM_KIND drives which bullets
# the memory-os section renders ({{MEMORY_PATHS}}); MEM_PATH / MEM_TOOL fill in
# the specifics. Default stays GENERIC so the shared template names no one store.
: "${MEM_KIND:=generic}"        # generic | local | mcp | both
: "${MEM_PATH:=}"               # local store path (e.g. ~/.hermes/) when local/both
: "${MEM_TOOL:=}"               # notes app via MCP (e.g. Notion, Obsidian) when mcp/both

# ---- safe loader: parse KEY=VALUE (NO sourcing => no code execution) ---------
# Only allow-listed keys are honored; values may be single/double quoted and may
# span multiple lines while inside quotes. Assignment is via printf -v, never eval.
# A value's closing quote must end its line (the natural shell style); the
# continuation loop reads further lines only while the quote is still open.
load_env() {
  local file="$1" line key val rest
  local sq="'" bs='\'   # single chars; used to build the '\'' idiom literally
  # Allowlist as a space-delimited set (keys are identifiers, never contain
  # spaces) — bash 3.2 has no associative arrays. Leading/trailing spaces let
  # the membership test below match whole tokens only.
  local allowed=" ${SUBST_VARS[*]} ${CTRL_VARS[*]} ${INC_VARS[*]} "
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"                       # tolerate CRLF (Windows) files
    case "$line" in ''|'#'*) continue;; esac
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"; key="${key//[[:space:]]/}"
    [[ "$allowed" == *" $key "* ]] || continue
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
           # POSIX single-quote idiom '\'' -> ' . Build the 4-char pattern from
           # single-char vars and quote it in the substitution so the match is
           # literal — bash 3.2 mishandles backslashes in an inline ${//} pattern.
           val="${val//"$sq$bs$sq$sq"/$sq}";;
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

# Record whether MEM_BLOCK was supplied verbatim (env or my-context.env) BEFORE
# we ever build one — build_mem_block honors that as a power-user escape hatch.
MEM_BLOCK_EXPLICIT=""; [ -n "${MEM_BLOCK:-}" ] && MEM_BLOCK_EXPLICIT=1

# Record whether INC_DESIGN was set explicitly (env or my-context.env) BEFORE the
# first normalize_inputs seeds it from PERSONA — so the interactive prompt can
# honor an explicit y/n instead of re-seeding from the persona (explicit wins).
INC_DESIGN_EXPLICIT=""; [ -n "${INC_DESIGN:-}" ] && INC_DESIGN_EXPLICIT=1

# Build the {{MEMORY_PATHS}} bullets from MEM_KIND/MEM_PATH/MEM_TOOL. Re-runnable:
# it only short-circuits on an explicit MEM_BLOCK, so calling it after the
# interactive prompts rebuilds from the freshly chosen backend.
build_mem_block() {
  [ -n "$MEM_BLOCK_EXPLICIT" ] && return 0
  local proj='  - Any `MEMORY.md` / `memory/` directory, or `AGENTS.md` / `CLAUDE.md`, shipped by the project or tool you'\''re running under.'
  local localb mcpb
  if [ -n "$MEM_PATH" ]; then
    localb="  - A local memory store at \`$MEM_PATH\` — read its identity/values files, curated user facts, and any per-agent memory directories before anything personal."
  else
    localb='  - A local memory store on this machine — an agent "memory OS" with identity/values files, curated user facts, and per-agent memory directories.'
  fi
  if [ -n "$MEM_TOOL" ]; then
    mcpb="  - My notes live in **$MEM_TOOL** — reach it through its MCP server and search there for relevant context before asking me."
  else
    mcpb='  - My notes live in a connected notes app — reach it through its MCP server and search there before asking me.'
  fi
  case "$MEM_KIND" in
    local) MEM_BLOCK="$localb"$'\n'"$proj";;
    mcp)   MEM_BLOCK="$mcpb"$'\n'"$proj";;
    both)  MEM_BLOCK="$localb"$'\n'"$mcpb"$'\n'"$proj";;
    *)     MEM_BLOCK='  - A dedicated memory store on this machine — e.g. an agent "memory OS" with identity/values files, curated user facts, and per-agent memory directories.'$'\n'"$proj";;
  esac
}

# ---- normalize & validate enum/toggle inputs --------------------------------
# Canonicalize toggles (accept y/Y/yes/YES/true/1/on) and the enums (any case)
# from ANY source — environment, my-context.env, or interactive answers — so
# render()'s exact-match comparisons can never silently drop a section on a
# capital "Y" or a typo'd enum. Unknown enum values warn (instead of silently
# dropping the block) and fall back to the documented default. Called once for
# the non-interactive paths below, and again after the interactive prompts.
normalize_inputs() {
  local _v
  case "$(lc "$PERSONA")" in
    prod*|design*|pd|ux|ui) PERSONA=product-designer;;
    eng*|dev*|swe|backend|frontend) PERSONA=engineer;;
    gen*|'') PERSONA=generic;;
    *) echo "customize.sh: unknown PERSONA='$PERSONA' (expected product-designer/engineer/generic); using generic." >&2; PERSONA=generic;;
  esac
  # Seed the Design section from the persona ONLY when the user left INC_DESIGN
  # unset — an explicit y/n (env or my-context.env) always wins. Runs before the
  # toggle loop below so the seeded value gets canonicalized like the rest.
  if [ -z "$INC_DESIGN" ]; then
    case "$PERSONA" in product-designer) INC_DESIGN=y;; *) INC_DESIGN=n;; esac
  fi
  for _v in "${INC_VARS[@]}"; do
    case "$(lc "${!_v}")" in y*|true|1|on) printf -v "$_v" y;; *) printf -v "$_v" n;; esac
  done
  case "$(lc "$AUTONOMY")" in
    agg*) AUTONOMY=aggressive;;
    bal*) AUTONOMY=balanced;;
    *) echo "customize.sh: unknown AUTONOMY='$AUTONOMY' (expected aggressive/balanced); using aggressive." >&2; AUTONOMY=aggressive;;
  esac
  case "$(lc "$PREVIEW")" in
    tail*) PREVIEW=tailscale;;
    loc*)  PREVIEW=local;;
    non*)  PREVIEW=none;;
    *) echo "customize.sh: unknown PREVIEW='$PREVIEW' (expected tailscale/local/none); using local." >&2; PREVIEW=local;;
  esac
  case "$(lc "$MEM_KIND")" in
    loc*)        MEM_KIND=local;;
    both)        MEM_KIND=both;;
    mcp|note*|notion*|obsid*) MEM_KIND=mcp;;
    gen*|'')     MEM_KIND=generic;;
    *) echo "customize.sh: unknown MEM_KIND='$MEM_KIND' (expected generic/local/mcp/both); using generic." >&2; MEM_KIND=generic;;
  esac
  build_mem_block
}
normalize_inputs

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
  [ "$INC_WORKTREES" = "y" ]     && keep="${keep}parallel-worktrees:"
  [ "$INC_IMPROVE" = "y" ]      && keep="${keep}improve:"
  [ "$INC_TOOLS" = "y" ]         && keep="${keep}tools-mcp:"
  [ "$INC_ARTIFACTS" = "y" ]     && keep="${keep}artifacts:"
  case "$PREVIEW" in
    tailscale) keep="${keep}preview-tailscale:";;
    local)     keep="${keep}preview-local:";;
  esac
  [ "$INC_DESIGN" = "y" ]        && keep="${keep}design:"
  [ "$INC_PROJECT" = "y" ]       && keep="${keep}project-instructions:"
  [ "$INC_DOCS" = "y" ]          && keep="${keep}docs-first:"
  [ "$INC_CORRECTIONS" = "y" ]   && keep="${keep}corrections:"
  [ "$INC_CHANGELOG" = "y" ]     && keep="${keep}changelog:"

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
  # mktmp's own TMPFILES+= ran in a command-substitution subshell and was lost, so
  # register the temp here (the real shell) — otherwise the cleanup trap never
  # sees it and a signal mid-render leaks a hidden .aigi.XXXXXX in the dest dir.
  TMPFILES+=("$tmp")
  if ! render > "$tmp"; then rm -f "$tmp"; echo "Render failed; $dest left unchanged." >&2; return 1; fi
  # Identical content — don't churn the inode/mtime (and skip the backup below).
  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then rm -f "$tmp"; return 0; fi
  if [ "${2:-}" = "backup" ] && [ -f "$dest" ]; then
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
  # Seed a Change Log into the global instruction folder so AI-made changes have a
  # machine-wide place to be logged. Seed-only: never overwrite an existing global
  # CHANGELOG.md, so accumulated entries survive re-installs.
  if [ -f "$DIR/CHANGELOG.md" ] && [ ! -f "$HOME/.claude/CHANGELOG.md" ]; then
    cp "$DIR/CHANGELOG.md" "$HOME/.claude/CHANGELOG.md" && echo "  seeded ~/.claude/CHANGELOG.md"
  fi
}

# ---- prompt helpers (used by both the --global confirm and the interactive flow)
# ask:     free-text with a [default] shown; Enter returns the default.
# ask_one: a choice; pass the menu to display AND the real default separately,
#          so Enter returns the default (not the menu string). Reads from /dev/tty,
#          so with no terminal it returns the default (here "N" => safe abort).
ask()    { local v; read -r -p "$1 [$2]: " v </dev/tty || true; printf '%s' "${v:-$2}"; }
ask_one(){ local v; read -r -p "$1 [$3] ($2): " v </dev/tty || true; printf '%s' "${v:-$3}"; }

# ---- non-interactive paths --------------------------------------------------
# --yes/-y (any position) skips the --global confirmation, for scripted/zero-prompt re-runs.
ASSUME_YES=""
for _a in "$@"; do case "$_a" in -y|--yes) ASSUME_YES=1;; esac; done

case "${1:-}" in
  --print)    render; exit 0;;
  # Resolve whether the design command group is wanted, reusing the same
  # precedence as everything else (explicit INC_DESIGN wins, else PERSONA seeds
  # it — both already applied by normalize_inputs above). install-commands.sh
  # queries this so it never has to re-parse my-context.env itself. Prints y|n.
  --design-group) printf '%s\n' "$INC_DESIGN"; exit 0;;
  --project)  write_project; exit 0;;
  --global)
    echo "This OVERWRITES your machine-wide instruction files (each is backed up first):"
    echo "  ~/.claude/CLAUDE.md  ~/AGENTS.md  ~/.codex/AGENTS.md  ~/.gemini/GEMINI.md"
    if [ -z "$ASSUME_YES" ]; then
      CONFIRM="$(ask_one 'Proceed?' "y/N" "N")"
      case "$CONFIRM" in [Yy]*) ;; *) echo "Aborted (pass --yes to skip this prompt)."; exit 0;; esac
    fi
    write_global; exit 0;;
  --scan-mcp) scan_mcp; exit 0;;
esac

# ---- prompts ----------------------------------------------------------------
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
fi

echo ""
echo "-- How you like work done --"
PERSONA="$(ask_one 'Primary focus (seeds sensible defaults)' "product-designer/engineer/generic" "$PERSONA")"
case "$(lc "$PERSONA")" in prod*|design*|pd|ux|ui) PERSONA="product-designer";; eng*|dev*|swe|backend|frontend) PERSONA="engineer";; *) PERSONA="generic";; esac
AUTONOMY="$(ask_one 'Autonomy posture' "aggressive/balanced" "$AUTONOMY")"
case "$AUTONOMY" in bal*) AUTONOMY="balanced";; *) AUTONOMY="aggressive";; esac

INC_TEAMS="$(ask_one 'Include "agent teams & subagents" section?' "y/n" "$INC_TEAMS")"; INC_TEAMS="${INC_TEAMS:0:1}"
if [ "$INC_TEAMS" = "y" ]; then
  TEAM_ROLES="$(ask 'Roles you draw from (comma-separated)' "$TEAM_ROLES")"
fi

INC_WORKTREES="$(ask_one 'Include "parallel AI models on one repo" (worktrees) section?' "y/n" "$INC_WORKTREES")"; INC_WORKTREES="${INC_WORKTREES:0:1}"

INC_IMPROVE="$(ask_one 'Include "auto run improve command after larger changes" section?' "y/n" "$INC_IMPROVE")"; INC_IMPROVE="${INC_IMPROVE:0:1}"
INC_TOOLS="$(ask_one 'Include "tools & MCP servers" section?' "y/n" "$INC_TOOLS")"; INC_TOOLS="${INC_TOOLS:0:1}"
if [ "$INC_TOOLS" = "y" ]; then
  DO_SCAN="$(ask_one 'Scan this machine'\''s MCP servers and add usage rules?' "y/n" "n")"
  [ "${DO_SCAN:0:1}" = "y" ] && scan_mcp interactive
fi

echo ""
echo "-- Optional sections --"
INC_MEMORY="$(ask_one 'Include "look for a memory OS" section?' "y/n" "$INC_MEMORY")";       INC_MEMORY="${INC_MEMORY:0:1}"
if [ "$INC_MEMORY" = "y" ]; then
  echo "  Where does your memory / notes live? This tailors what the agent looks for."
  echo "    1) Local files or a memory OS on this machine (e.g. Hermes at ~/.hermes)"
  echo "    2) A notes app via its MCP server (e.g. Notion, Obsidian)"
  echo "    3) Both a local store and a notes app"
  echo "    4) Generic — don't name a specific store"
  case "$(ask_one 'Memory backend' "1/2/3/4" "4")" in
    1) MEM_KIND=local; MEM_PATH="$(ask 'Path to your local memory store' "${MEM_PATH:-~/.hermes/}")";;
    2) MEM_KIND=mcp;   MEM_TOOL="$(ask 'Notes app name (as exposed by its MCP server)' "${MEM_TOOL:-Notion}")";;
    3) MEM_KIND=both;  MEM_PATH="$(ask 'Path to your local memory store' "${MEM_PATH:-~/.hermes/}")"
                       MEM_TOOL="$(ask 'Notes app name (as exposed by its MCP server)' "${MEM_TOOL:-Notion}")";;
    *) MEM_KIND=generic;;
  esac
fi
INC_ARTIFACTS="$(ask_one 'Include "output artifacts" (HTML default) section?' "y/n" "$INC_ARTIFACTS")"; INC_ARTIFACTS="${INC_ARTIFACTS:0:1}"
# Design-section prompt default: honor an explicit env/my-context.env value;
# otherwise follow the (possibly just-changed) persona. The typed answer wins.
if [ -n "$INC_DESIGN_EXPLICIT" ]; then _dz="$INC_DESIGN"
else case "$PERSONA" in product-designer) _dz=y;; *) _dz=n;; esac; fi
INC_DESIGN="$(ask_one 'Include "design system & UI" section (build to design tokens, stay on scales, design accessibly)?' "y/n" "$_dz")"; INC_DESIGN="${INC_DESIGN:0:1}"
INC_PROJECT="$(ask_one 'Include "project-specific instructions" section (encourages keeping/updating per-project AGENTS.md/CLAUDE.md)?' "y/n" "$INC_PROJECT")"; INC_PROJECT="${INC_PROJECT:0:1}"
INC_DOCS="$(ask_one 'Include "documentation first" section (read official docs before using libraries; custom hacks as last resort)?' "y/n" "$INC_DOCS")";          INC_DOCS="${INC_DOCS:0:1}"
INC_CORRECTIONS="$(ask_one 'Include "when I say you did wrong" section (rules for capturing corrections/memories to prevent repeating mistakes)?' "y/n" "$INC_CORRECTIONS")"; INC_CORRECTIONS="${INC_CORRECTIONS:0:1}"
INC_CHANGELOG="$(ask_one 'Include "change log" section (tracks AI changes, proposes draft entry, requires approval before writing)?' "y/n" "$INC_CHANGELOG")"; INC_CHANGELOG="${INC_CHANGELOG:0:1}"

# Canonicalize the answers just typed (so "Y", "Balanced", "Tailscale" all work).
normalize_inputs

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
