#!/usr/bin/env bash
# One-shot installer — render the instructions and install every layer in one
# go. Wraps the focused scripts so you don't have to remember the sequence.
#
#   ./install.sh                 # all tools: instructions + skills + roles + hooks + settings
#   ./install.sh --yes           # same, but don't prompt to confirm the global render
#   ./install.sh claude          # just Claude Code
#   ./install.sh codex cursor    # instructions + skills + roles + hooks + settings for those
#   ./install.sh --design        # force the design command group on (auto: on unless INC_DESIGN=n)
#   ./install.sh --unlock        # clear a stuck install-state lock (only when no install is running)
#   ./install.sh --plan          # show what each installed file would get; writes nothing
#   ./install.sh --resolve [path…] [--replace|--append|--keep|--pin]
#                                # re-decide a file an earlier run replaced (no flag: ask)
#   ./install.sh --pin <path>    # never write this file again; --unpin <path> undoes it
#   ./install.sh --on-conflict=replace|append|keep
#                                # what an unattended run does with a file you edited
#
# Files you edited: an attended run leaves them alone while it installs, then
# asks about all of them at once at the end (Enter replaces, after saving
# yours). An unattended run (--yes, no terminal, or AIGI_UNATTENDED=1) replaces
# them after saving yours, unless INSTALL_ON_CONFLICT / --on-conflict says
# otherwise. Either way the run's last lines name every replaced file with its
# recovery command, and ~/.ai/install-state/last-run.json records the same.
#
# Layers (each applied to whichever targets you name):
#   - instructions (customize.sh --global): all tools, always — the portable core.
#   - skills (install-skills.sh):           symlinked into ~/.claude/skills, ~/.codex/skills, ~/.cursor/skills.
#   - roles (install-roles.sh):             per tool (~/.claude, ~/.codex, ~/.cursor agents; ~/.gemini/config/agents) —
#     the team-role definitions the instructions spawn agents by name from.
#   - hooks (install-hooks.sh):             per tool.
#   - memory OS registry (setup-memory-os.sh): machine-wide — where session-survey
#     lessons land (~/.ai/memory-os; detects Hermes, falls back to markdown).
#   - settings/permissions (install-settings.sh): per tool (native model differs; see that script).
#
# Reverse it all with ./uninstall.sh.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

# Split args into flags and tool targets.
yes_flag=""
design_flag=()   # forwarded to install-skills.sh: --design | --no-design
targets=()
plan=""; resolve=""; resolve_mode=ask; resolve_paths=(); pin_op=""; pin_path=""; on_conflict=""
want_path=""
for a in "$@"; do
  if [ -n "$want_path" ]; then pin_path="$a"; want_path=""; continue; fi
  case "$a" in
    --yes|-y) yes_flag="--yes";;
    --design) design_flag=(--design);;
    --no-design) design_flag=(--no-design);;
    --unlock)
      st="${AIGI_STATE_DIR:-$HOME/.ai/install-state}"
      rm -rf "$st/lock" "$st/lock.reap"
      echo "Cleared the install-state lock in $st."; exit 0;;
    --plan) plan=1;;
    --resolve) resolve=1;;
    --replace|--append|--keep) resolve_mode="${a#--}";;
    --pin|--unpin) pin_op="${a#--}"; want_path=1;;
    --on-conflict=*) on_conflict="${a#--on-conflict=}";;
    claude|codex|cursor|antigravity) targets+=("$a");;
    *) if [ -n "$resolve" ]; then resolve_paths+=("$a")
       else echo "unknown arg: $a (use: --yes | --plan | --resolve | --pin | --unpin | --on-conflict= | --design | --no-design | --unlock | claude | codex | cursor | antigravity)" >&2; exit 1; fi;;
  esac
done
[ ${#targets[@]} -eq 0 ] && targets=(claude codex cursor antigravity)
if [ "$resolve_mode" != ask ] && [ -z "$resolve" ]; then
  echo "--$resolve_mode only goes with --resolve (e.g. ./install.sh --resolve <path> --$resolve_mode)" >&2; exit 1
fi
# --pin doubles as --resolve's "put mine back and pin it" mode.
if [ -n "$resolve" ] && [ "$pin_op" = pin ]; then
  resolve_mode=pin; [ -n "$pin_path" ] && resolve_paths+=("$pin_path"); pin_op=""
fi

# The install ledger (lib/preserve.sh) is shared by every layer below.
# shellcheck source=lib/preserve.sh
. "$DIR/lib/preserve.sh"

# Expand a leading ~ and make a path absolute, the form the ledger records.
abs_path() {
  local p="$1"
  case "$p" in "~") p="$HOME";; "~/"*) p="$HOME/${p#\~/}";; esac
  case "$p" in /*) ;; *) p="$PWD/$p";; esac
  printf '%s\n' "$p"
}

if [ -n "$pin_op" ]; then
  [ -n "$pin_path" ] || { echo "--$pin_op needs a path" >&2; exit 1; }
  pin_path="$(abs_path "$pin_path")"
  pv_lock || exit 1
  if [ "$pin_op" = pin ]; then
    pv_do_pin "$pin_path" 2>&1
  elif [ -f "$PV_STATE/pins" ] && grep -qxF -- "$pin_path" "$PV_STATE/pins"; then
    grep -vxF -- "$pin_path" "$PV_STATE/pins" > "$PV_STATE/.pins.tmp" || true
    mv "$PV_STATE/.pins.tmp" "$PV_STATE/pins"
    echo "  unpinned $pin_path — the next install will offer the current version"
  else
    echo "  $pin_path wasn't pinned"
  fi
  exit 0
fi

if [ -n "$resolve" ]; then
  rp=(); for a in ${resolve_paths[@]+"${resolve_paths[@]}"}; do rp+=("$(abs_path "$a")"); done
  pv_resolve_cmd "$resolve_mode" ${rp[@]+"${rp[@]}"} 2>&1
  exit $?
fi

# One decision about who's answering, made here and exported, so every layer
# behaves the same (G5): --yes, AIGI_UNATTENDED=1, or no terminal to open.
if [ -n "$yes_flag" ] || pv_unattended; then AIGI_UNATTENDED=1; else AIGI_UNATTENDED=0; fi
export AIGI_UNATTENDED
# Read the conflict policy and the AI check from my-context.env through
# customize.sh, which already owns parsing it; a flag beats the file.
AIGI_ON_CONFLICT="${on_conflict:-$("$DIR/customize.sh" --on-conflict)}"
AIGI_AI_CHECK="$("$DIR/customize.sh" --ai-check)"
AIGI_AI_CHECK_CMD="$("$DIR/customize.sh" --ai-check-cmd)"
case "$AIGI_ON_CONFLICT" in replace|append|keep) ;; *) echo "unknown --on-conflict value: $AIGI_ON_CONFLICT (use replace, append or keep)" >&2; exit 1;; esac
export AIGI_ON_CONFLICT AIGI_AI_CHECK AIGI_AI_CHECK_CMD
[ -n "$plan" ] && { AIGI_PHASE=plan; export AIGI_PHASE; }
pv_run_init || exit 1
PV_OWN_RUN=""   # this script closes the run itself, below — not the first layer to finish

if [ -n "$plan" ]; then
  # Only the layers that write ledgered files run; the skills, settings and
  # memory-OS layers link, key-merge or seed, and hold nothing the ledger decides.
  echo "== plan: what each installed file would get (nothing is written) =="
  "$DIR/customize.sh" --global --yes >/dev/null
  "$DIR/install-roles.sh" "${targets[@]}" >/dev/null
  "$DIR/install-hooks.sh" "${targets[@]}" >/dev/null
  awk -F'\t' '!($1 in last) { order[++n] = $1 } { last[$1] = $0 } END { for (i = 1; i <= n; i++) print last[order[i]] }' \
    "$AIGI_RUN_DIR/actions.tsv" 2>/dev/null \
    | awk -F'\t' '{ printf "  %-8s %-14s %s\n", $3, $4, $1; c[$4]++ } END { printf "\n"; for (k in c) printf "  %d %s\n", c[k], k }'
  rm -rf "$AIGI_RUN_DIR"
  exit 0
fi

echo "== instructions =="
# Portable core — renders every tool's instruction file from template.md.
if [ -n "$yes_flag" ]; then "$DIR/customize.sh" --global --yes; else "$DIR/customize.sh" --global; fi

echo "== skills =="
"$DIR/install-skills.sh" ${design_flag[@]+"${design_flag[@]}"} "${targets[@]}"

echo "== roles (reusable agent/teammate definitions) =="
"$DIR/install-roles.sh" "${targets[@]}"

echo "== hooks =="
"$DIR/install-hooks.sh" "${targets[@]}"

echo "== memory OS (lesson store for session surveys) =="
if [ -n "$yes_flag" ]; then "$DIR/setup-memory-os.sh" --yes; else "$DIR/setup-memory-os.sh"; fi

echo "== settings (per-tool permissions) =="
"$DIR/install-settings.sh" "${targets[@]}"

# Every file a layer parked (you'd edited it, and someone can answer) gets
# its question now, in one pass; then the report.
pv_resolve_parked || true
pv_write_last_run || true
pv_summary
rm -rf "$AIGI_RUN_DIR"

echo "Done. Reverse with ./uninstall.sh."
