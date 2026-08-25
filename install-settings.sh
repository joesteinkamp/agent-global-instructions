#!/usr/bin/env bash
# Install the client-enforced permissions layer into each tool's native config,
# mirroring the deny/ask intent of settings-permissions.snippet.json. Each tool's
# permission model differs, so fidelity varies — the guard hooks remain the
# common denominator. Idempotent, with timestamped backups; uninstall.sh reverses.
#
#   ./install-settings.sh                 # all tools
#   ./install-settings.sh claude          # just Claude Code
#   ./install-settings.sh codex cursor
#
# Per tool (and what it enforces natively vs. via the guard hooks):
#   claude  ~/.claude/settings.json       permissions.deny/ask (JSON union)    — hard-enforced
#                                         + env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1, which turns on
#                                           the agent-team construct the instructions default to
#                                           (seed-only: an existing value is never overwritten)
#   codex   ~/.codex/config.toml          approval/sandbox + quiet, actionable notifications
#   cursor  ~/.cursor/cli-config.json     permissions.deny (JSON union)        — CLI agent; GUI via hook
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }

TMPFILES=()
trap '[ ${#TMPFILES[@]} -gt 0 ] && rm -f "${TMPFILES[@]}" || true' EXIT

# Back up a file to a collision-free name, keeping only the 5 newest backups.
backup_file() {  # $1 = file to back up
  # Skip a file we just seeded empty this run (nothing to preserve) so first
  # installs don't litter a *.bak of `{}` / an empty config.toml.
  case "$(tr -d ' \n\t' < "$1" 2>/dev/null)" in ''|'{}'|'{"version":1}') return 0;; esac
  cp "$1" "$(mktemp "$1.bak.XXXXXX")"
  local n=0 b
  while IFS= read -r b; do n=$((n+1)); if [ "$n" -gt 5 ]; then rm -f -- "$b"; fi; done \
    < <(ls -1t -- "$1".bak.* 2>/dev/null)
  return 0
}

# Rules we used to install and have since retired. Dropping a rule from a snippet
# only stops NEW installs from getting it — an existing settings.json keeps the
# orphan forever, since uninstall.sh subtracts exactly what the snippet holds
# today. So the merge subtracts these first (same idea as remove_commands_dir's
# retired command names). Only ever list rules WE wrote; a rule the user added
# themselves must never appear here.
CLAUDE_RETIRED_PERMS='{
  "deny": [
    "Write(.env)", "Write(.env.*)", "Write(**/.env)", "Write(**/.env.*)",
    "Write(**/build/**)", "Write(**/dist/**)", "Write(**/.next/**)",
    "Write(**/out/**)", "Write(**/coverage/**)", "Write(**/node_modules/**)",
    "Write(**/.git/**)", "Write(**/package-lock.json)", "Write(**/pnpm-lock.yaml)",
    "Write(**/yarn.lock)", "Write(**/bun.lockb)",
    "Read(./.env)", "Read(./.env.*)"
  ]
}'

# Order-preserving union of each permission array from a JSON snippet (.permissions)
# into a JSON settings file, minus any retired rules ($4). Idempotent: a re-run
# never duplicates a rule.
# Turn on Claude Code's agent teams (experimental, off by default). Without this
# the resident "default to a team" instruction degrades to ordinary subagents:
# same parallelism and same roles, but teammates can't message each other and
# can't be opened or steered from the agent panel. Seed-only — an existing value
# is the user's explicit choice (including a deliberate "0"), so we never
# overwrite it, the same way the codex approval_policy merge behaves.
enable_agent_teams() {  # $1 = claude settings.json
  local sf="$1" cur tmp
  [ -f "$sf" ] || echo '{}' > "$sf"
  cur="$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS // empty' "$sf" 2>/dev/null)" || return 1
  if [ -n "$cur" ]; then
    echo "    agent teams left at your setting (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=$cur)"
    return 0
  fi
  tmp="$(mktemp "$(dirname "$sf")/.aigi.XXXXXX")"; TMPFILES+=("$tmp")
  jq '.env = ((.env // {}) + {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"})' "$sf" > "$tmp" \
    || { echo "    agent-teams merge failed for $sf (left unchanged)" >&2; return 1; }
  backup_file "$sf"; mv "$tmp" "$sf"
  echo "    agent teams enabled (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1) -> $sf"
  return 0
}

merge_perms_json() {  # $1 = settings file  $2 = snippet file  $3 = label  [$4 = retired JSON]
  # `${4:-{\}}` would keep the backslash literally ({\}), which jq --argjson
  # rejects — so default the retired-rules JSON on its own line instead.
  local sf="$1" snippet="$2" label="$3" retired="${4:-}" perms tmp
  [ -n "$retired" ] || retired='{}'
  [ -f "$snippet" ] || { echo "    no snippet at $snippet" >&2; return 1; }
  mkdir -p "$(dirname "$sf")"
  [ -f "$sf" ] || echo '{}' > "$sf"
  perms="$(jq '.permissions' "$snippet")"
  tmp="$(mktemp "$(dirname "$sf")/.aigi.XXXXXX")"; TMPFILES+=("$tmp")  # same-dir: atomic mv + valid BSD template
  # Subtract retired rules BEFORE the union, so a rule that is both retired and
  # currently shipped (shouldn't happen, but) ends up present rather than dropped.
  jq --argjson add "$perms" --argjson gone "$retired" '
    .permissions = (.permissions // {})
    | reduce ($gone | to_entries[]) as $e (.;
        if (.permissions[$e.key] | type) == "array"
        then .permissions[$e.key] -= $e.value else . end)
    | reduce ($add | to_entries[]) as $e (.;
        .permissions[$e.key] =
          ((.permissions[$e.key] // []) as $cur | $cur + ($e.value - $cur)))
    | .permissions |= with_entries(select((.value | type) != "array" or (.value | length) > 0))
  ' "$sf" > "$tmp" || { echo "    merge failed for $sf (left unchanged)" >&2; return 1; }
  if cmp -s "$tmp" "$sf"; then
    echo "    $sf (permissions already current, no change)"
  else
    backup_file "$sf"; mv "$tmp" "$sf"; echo "    $label deny/ask merged -> $sf"
  fi
}

install_claude_settings() {
  echo "  claude:"
  merge_perms_json "$HOME/.claude/settings.json" "$DIR/settings-permissions.snippet.json" claude "$CLAUDE_RETIRED_PERMS"
}

install_cursor_settings() {
  echo "  cursor:"
  merge_perms_json "$HOME/.cursor/cli-config.json" "$DIR/settings-permissions.cursor.snippet.json" cursor
}

# Seed one key inside an exact TOML table without rewriting or reformatting the
# rest of the user's config. Existing values are explicit user choices and win.
# Newly added keys carry an ownership marker so uninstall.sh can remove only
# what this installer wrote. The table header itself is harmless if left empty.
seed_toml_table_key() {  # $1 = file  $2 = table  $3 = key  $4 = TOML value
  local f="$1" table="$2" key="$3" value="$4" marker="# agent-global-instructions: codex notification defaults"
  local tmp; tmp="$(mktemp "$(dirname "$f")/.aigi.XXXXXX")"; TMPFILES+=("$tmp")
  awk -v table="$table" -v key="$key" -v value="$value" -v marker="$marker" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function unquote(s, q) {
      q = substr(s, 1, 1)
      if ((q == "\"" || q == sprintf("%c", 39)) && substr(s, length(s), 1) == q) return substr(s, 2, length(s) - 2)
      return s
    }
    function table_name(s) {
      sub(/^[[:space:]]*\[\[?/, "", s)
      sub(/\]\]?[[:space:]]*(#.*)?$/, "", s)
      s = trim(s); gsub(sprintf("%c", 39), "\"", s)
      return unquote(s)
    }
    function key_name(s, p) {
      sub(/[[:space:]]*#.*/, "", s)
      p = index(s, "=")
      return p ? unquote(trim(substr(s, 1, p - 1))) : ""
    }
    /^[[:space:]]*\[\[?[^]]+\]\]?[[:space:]]*(#.*)?$/ {
      if (inside && !key_seen) print key " = " value " " marker
      is_array = ($0 ~ /^[[:space:]]*\[\[/)
      inside = (!is_array && table_name($0) == table)
      if (inside) { table_seen = 1; key_seen = 0 }
      print
      next
    }
    {
      if (inside && key_name($0) == key) key_seen = 1
      print
    }
    END {
      if (inside && !key_seen) print key " = " value " " marker
      if (!table_seen) {
        if (NR > 0) print ""
        print "[" table "]"
        print key " = " value " " marker
      }
    }
  ' "$f" > "$tmp"
  mv "$tmp" "$f"
}

toml_table_key_is() {  # $1 = file  $2 = table  $3 = key  $4 = normalized value
  awk -v table="$2" -v key="$3" -v wanted="$4" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function unquote(s, q) {
      q = substr(s, 1, 1)
      if ((q == "\"" || q == sprintf("%c", 39)) && substr(s, length(s), 1) == q) return substr(s, 2, length(s) - 2)
      return s
    }
    function table_name(s) {
      sub(/^[[:space:]]*\[/, "", s); sub(/\][[:space:]]*(#.*)?$/, "", s)
      s = trim(s); gsub(sprintf("%c", 39), "\"", s); return unquote(s)
    }
    /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/ { inside = (table_name($0) == table); next }
    inside {
      line = $0; sub(/[[:space:]]*#.*/, "", line)
      p = index(line, "=")
      if (p && unquote(trim(substr(line, 1, p - 1))) == key && trim(substr(line, p + 1)) == wanted) found = 1
    }
    END { exit found ? 0 : 1 }
  ' "$1"
}

# True when native TUI notifications already cover approval waits. `true`
# enables every native event; an explicit list must name approval-requested.
# False, unsupported/multiline forms, and lists that omit it fail closed.
codex_tui_approval_is_covered() {  # $1 = config.toml
  awk '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function unquote(s, q) {
      q = substr(s, 1, 1)
      if ((q == "\"" || q == sprintf("%c", 39)) && substr(s, length(s), 1) == q) return substr(s, 2, length(s) - 2)
      return s
    }
    function table_name(s) {
      sub(/^[[:space:]]*\[/, "", s); sub(/\][[:space:]]*(#.*)?$/, "", s); return unquote(trim(s))
    }
    /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/ { inside = (table_name($0) == "tui"); next }
    inside {
      line = $0; sub(/[[:space:]]*#.*/, "", line)
      p = index(line, "="); if (!p) next
      lhs = unquote(trim(substr(line, 1, p - 1))); rhs = trim(substr(line, p + 1))
      if (lhs == "notifications" && (rhs == "true" || rhs ~ /["\047]approval-requested["\047]/)) covered = 1
    }
    END { exit covered ? 0 : 1 }
  ' "$1"
}

# Resolve the current Warp PermissionRequest handler instead of hard-coding its
# matcher-group/handler indices. Hook state is an internal persistence key; only
# seed it when Warp is explicitly enabled and the installed manifest proves the
# exact handler exists. A future plugin reorder therefore produces the right key
# rather than silently disabling a different hook.
codex_warp_permission_hook_table() {  # $1 = config.toml
  local cf="$1" manifest="$HOME/.codex/.tmp/marketplaces/codex-warp/plugins/warp/hooks/hooks.json" matches coords count
  toml_table_key_is "$cf" 'plugins."warp@codex-warp"' "enabled" "true" || return 1
  [ -f "$manifest" ] || return 1
  matches="$(jq -r '
    (.hooks.PermissionRequest // []) | to_entries[] as $group
    | ($group.value.hooks // []) | to_entries[]
    | select(.value.type == "command")
    | select((.value.command // "") | endswith("/on-permission-request.sh"))
    | "\($group.key):\(.key)"
  ' "$manifest" 2>/dev/null)"
  count="$(printf '%s\n' "$matches" | grep -c . || true)"
  [ "$count" = 1 ] || return 1
  coords="$matches"
  printf 'hooks.state."warp@codex-warp:hooks/hooks.json:permission_request:%s"\n' "$coords"
}

install_codex_settings() {
  local cf="$HOME/.codex/config.toml" snip="$DIR/codex-permissions.snippet.toml"
  local begin="# >>> agent-global-instructions (codex permissions) >>>"
  local end="# <<< agent-global-instructions (codex permissions) <<<"
  echo "  codex:"
  [ -f "$snip" ] || { echo "    no snippet at $snip" >&2; return 1; }
  mkdir -p "$(dirname "$cf")"; [ -f "$cf" ] || : > "$cf"
  # Strip any prior managed block first so we operate on the user's own content.
  # Also drop any leading blank lines the previous block-separator left behind, so
  # a re-run reproduces a byte-identical file instead of growing one blank line
  # (and a fresh backup) every time.
  local body; body="$(mktemp "$(dirname "$cf")/.aigi.XXXXXX")"; TMPFILES+=("$body")
  awk -v b="$begin" -v e="$end" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$cf" \
    | awk 'NF||p{print; p=1}' > "$body"
  # TOML forbids duplicate keys (a parse error would break Codex startup), and our
  # keys are TOP-LEVEL. Only treat them as "already set" when they appear before
  # the first [table] header — an approval_policy under [profiles.x] is a
  # different key and is no conflict.
  local toplevel
  toplevel="$(awk '/^[[:space:]]*\[/{exit} {print}' "$body")"
  local tmp; tmp="$(mktemp "$(dirname "$cf")/.aigi.XXXXXX")"; TMPFILES+=("$tmp")
  if printf '%s\n' "$toplevel" | grep -Eq '^[[:space:]]*(approval_policy|sandbox_mode)[[:space:]]*='; then
    echo "    config.toml already sets approval_policy/sandbox_mode at top level — leaving yours untouched."
    echo "    (recommended: approval_policy=\"on-request\", sandbox_mode=\"workspace-write\";"
    echo "     fine-grained path-deny is enforced by the guard-paths hook.)"
    cp "$body" "$tmp"
  else
    # PREPEND the block: top-level keys must precede any [table], or TOML would fold
    # them into the last table (inert guardrail + corrupted user table).
    cat "$snip" > "$tmp"
    if [ -s "$body" ]; then printf '\n' >> "$tmp"; cat "$body" >> "$tmp"; fi
  fi

  # Warp's PermissionRequest lifecycle hook fires before approval routing, so it
  # also toasts for requests that Codex auto-review immediately approves. Keep
  # Warp's Stop notifier for completed turns and every other Warp hook untouched;
  # native TUI approval notifications cover requests that actually reach the
  # user. Existing values remain explicit user choices. Only touch this routing
  # when the enabled plugin's installed manifest confirms the exact hook ID.
  local warp_permission_table=""
  if warp_permission_table="$(codex_warp_permission_hook_table "$tmp")"; then
    seed_toml_table_key "$tmp" "tui" "notifications" '[ "approval-requested" ]'
    if codex_tui_approval_is_covered "$tmp"; then
      seed_toml_table_key "$tmp" "tui" "notification_method" '"osc9"'
      seed_toml_table_key "$tmp" "tui" "notification_condition" '"unfocused"'
      seed_toml_table_key "$tmp" "$warp_permission_table" "enabled" "false"
    else
      echo "    Existing TUI notifications omit approval-requested — Warp permission notifier left enabled."
    fi
  else
    echo "    Warp plugin not enabled/discoverable — notification routing left untouched."
  fi

  if cmp -s "$tmp" "$cf"; then
    echo "    $cf (already current, no change)"
  else
    backup_file "$cf"; mv "$tmp" "$cf"; echo "    permissions + notification defaults merged -> $cf"
  fi
}

targets=("$@"); [ ${#targets[@]} -eq 0 ] && targets=(claude codex cursor antigravity)
# Guard each install so one tool's merge failure doesn't abort the rest under
# `set -e` (the merge_* helpers return 1 on bad jq / missing snippet).
for t in "${targets[@]}"; do
  case "$t" in
    claude)             if install_claude_settings; then enable_agent_teams "$HOME/.claude/settings.json"; else echo "  claude: skipped (error above)" >&2; fi;;
    codex)              install_codex_settings  || echo "  codex: skipped (error above)" >&2;;
    cursor)             install_cursor_settings || echo "  cursor: skipped (error above)" >&2;;
    antigravity)        echo "  antigravity: uses its own permission model (~/.gemini/antigravity-cli/settings.json); not wired here — guardrails come from its hooks (install-hooks.sh antigravity)";;
    *) echo "  unknown target: $t (use: claude codex cursor antigravity)" >&2;;
  esac
done
echo "Done. Backups saved next to each file."
