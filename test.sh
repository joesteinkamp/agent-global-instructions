#!/usr/bin/env bash
# Smoke tests for the render engine in customize.sh. Runs hermetically
# (AIGI_NO_USER_ENV=1, so your personal my-context.env is ignored) and asserts
# the invariants that matter: no marker/placeholder leakage, section toggles
# work, nesting is honored, and values with special characters render literally.
#
#   ./test.sh
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CUSTOMIZE="$DIR/customize.sh"
export AIGI_NO_USER_ENV=1

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }
# assert_has <desc> <needle> <<< text   |   assert_no <desc> <needle>
assert_has() { if grep -qF -- "$2" /tmp/aigi_test.out; then ok "$1"; else bad "$1"; fi; }
assert_no()  { if grep -qF -- "$2" /tmp/aigi_test.out; then bad "$1"; else ok "$1"; fi; }
render() { "$CUSTOMIZE" --print > /tmp/aigi_test.out 2>/tmp/aigi_test.err; }

echo "== render-engine tests =="

# 1. A full default render leaves no unresolved markers or placeholders.
render
assert_no "no {{ placeholders leak in a full render"  '{{'
assert_no "no SECTION: markers leak in a full render" 'SECTION:'
[ -s /tmp/aigi_test.err ] && bad "default render is silent (no stderr)" || ok "default render is silent (no stderr)"

# 2. Section toggle removes the block and leaves no marker behind.
INC_DOCS=n render
assert_no "INC_DOCS=n removes the Documentation-first heading" 'Documentation first'
assert_no "INC_DOCS=n leaves no marker leak" 'SECTION:'

# 3. Nested sections: artifacts off removes the nested preview-* blocks too.
INC_ARTIFACTS=n render
assert_no "INC_ARTIFACTS=n removes Output artifacts" 'Output artifacts'
assert_no "INC_ARTIFACTS=n removes nested preview block" 'serve over Tailscale'
assert_no "INC_ARTIFACTS=n leaves no marker leak" 'SECTION:'

# 4. Mutually-exclusive nested choice: tailscale shows the tailscale block, not local.
PREVIEW=tailscale render
assert_has "PREVIEW=tailscale renders the Tailscale block" 'serve over Tailscale'
assert_no  "PREVIEW=tailscale omits the local-serve block"  'Serve/open artifacts locally'
PREVIEW=local render
assert_has "PREVIEW=local renders the local block"   'Serve/open artifacts locally'
assert_no  "PREVIEW=local omits the Tailscale block"  'serve over Tailscale'

# 5. Optional Environment line: omitted when empty, present when set.
ENVIRONMENT="" render
assert_no  "empty ENVIRONMENT omits the Environment line" '**Environment:**'
ENVIRONMENT="a custom box" render
assert_has "set ENVIRONMENT includes the Environment line" 'a custom box'

# 6. Values with sed-special chars and a newline render literally (no abort).
CARES=$'speed & scale | <x>\nsecond \\ line' render
[ -s /tmp/aigi_test.err ] && bad "special-char value renders without error" || ok "special-char value renders without error"
assert_has "ampersand/pipe/angle chars render literally" 'speed & scale | <x>'
assert_has "newline in a value is preserved"             'second \ line'

# 6b. Memory backend: MEM_KIND tailors the {{MEMORY_PATHS}} bullets.
MEM_KIND=local MEM_PATH='~/.hermes/' render
assert_has "MEM_KIND=local names the local store path" 'local memory store at `~/.hermes/`'
MEM_KIND=mcp MEM_TOOL='Obsidian' render
assert_has "MEM_KIND=mcp names the notes app"      'notes live in **Obsidian**'
assert_no  "MEM_KIND=mcp omits the local-store bullet" 'local memory store at'
MEM_KIND=both MEM_PATH='~/.hermes/' MEM_TOOL='Notion' render
assert_has "MEM_KIND=both names the local store" 'local memory store at `~/.hermes/`'
assert_has "MEM_KIND=both names the notes app"   'notes live in **Notion**'
MEM_BLOCK='  - Hand-written bullet.' MEM_KIND=local render
assert_has "explicit MEM_BLOCK overrides MEM_KIND" 'Hand-written bullet.'

# 7. Every {{VAR}} placeholder in the template is substituted in a full render.
#    (for-loop, not a while|grep pipeline — the latter exits after the first
#    match and silently can't fail.)
render
leaks=""
for v in $(grep -oE '\{\{[A-Z_]+\}\}' "$DIR/template.md" | sort -u); do
  grep -qF -- "$v" /tmp/aigi_test.out && leaks="$leaks $v"
done
[ -z "$leaks" ] && ok "all template placeholders are handled" \
                || bad "template placeholders leaked:$leaks"

# 8. Every <!--SECTION:x--> in the template is referenced by render()'s keep
#    builder — catches a section added to the template with no toggle (which
#    would otherwise be silently dropped or always-kept forever).
missing=""
for s in $(grep -oE '<!--SECTION:[A-Za-z0-9_-]+-->' "$DIR/template.md" | sed -E 's/<!--SECTION:(.*)-->/\1/' | sort -u); do
  grep -qF "{keep}${s}:" "$CUSTOMIZE" || missing="$missing $s"
done
[ -z "$missing" ] && ok "every template section is wired into render()" \
                  || bad "template sections not wired into render():$missing"

# 9. No template line carries more than one SECTION marker (the depth counter
#    assumes one per line).
if [ "$(grep -cE '<!--/?SECTION:[A-Za-z0-9_-]+-->.*<!--/?SECTION:' "$DIR/template.md")" -eq 0 ]; then
  ok "no template line has two SECTION markers"
else
  bad "a template line has two SECTION markers (breaks the depth counter)"
fi

# 10. The committed examples are reproducible from their .env inputs (so they
#     can't silently drift from the template).
for ex in "$DIR"/examples/*.env; do
  [ -e "$ex" ] || continue
  base="$(basename "$ex" .env)"; md="$DIR/examples/$base.md"
  ( set -a; . "$ex"; set +a; AIGI_NO_USER_ENV=1 "$CUSTOMIZE" --print ) > /tmp/aigi_ex.out 2>/dev/null
  if [ -f "$md" ] && diff -q /tmp/aigi_ex.out "$md" >/dev/null; then
    ok "example $base reproduces from $base.env"
  else
    bad "example $base reproduces from $base.env"
  fi
done
rm -f /tmp/aigi_ex.out

# ---- load_env (the parser) — runs WITHOUT AIGI_NO_USER_ENV via a temp env ----
echo ""
echo "== load_env parser tests =="
ENVF="$(mktemp)"
cat > "$ENVF" <<'EOF'
NAME="Quote Tester"
EVIL="$(touch /tmp/aigi_pwned)"
ROLE='one'\''s job'
CARES="line one
line two"
EOF
unset AIGI_NO_USER_ENV
rm -f /tmp/aigi_pwned
# Render with a project that loads this env by copying it into place is invasive;
# instead source the loader in a sub-bash that defines the lists + load_env.
out="$(
  AIGI_NO_USER_ENV="" bash -c '
    set -euo pipefail
    '"$(sed -n '/^SUBST_VARS=/p;/^CTRL_VARS=/p;/^INC_VARS=/p' "$CUSTOMIZE")"'
    NAME=""; ROLE=""; CARES=""; EVIL=""
    '"$(sed -n '/^load_env() {/,/^}/p' "$CUSTOMIZE")"'
    load_env "$1"
    printf "NAME=[%s]\nROLE=[%s]\nCARES=[%s]\nEVIL=[%s]\n" "$NAME" "$ROLE" "$CARES" "${EVIL:-<unset>}"
  ' _ "$ENVF"
)"
echo "$out" | grep -qF 'NAME=[Quote Tester]' && ok "quoted scalar parsed" || bad "quoted scalar parsed"
echo "$out" | grep -qF "ROLE=[one's job]"     && ok "single-quote idiom un-escaped" || bad "single-quote idiom un-escaped"
echo "$out" | grep -qF 'line two'             && ok "multi-line quoted value preserved" || bad "multi-line quoted value preserved"
echo "$out" | grep -qF 'EVIL=[<unset>]'       && ok "non-allowlisted key ignored" || bad "non-allowlisted key ignored"
[ ! -e /tmp/aigi_pwned ] && ok "value is NOT executed (no code injection)" || bad "value is NOT executed (no code injection)"
rm -f "$ENVF" /tmp/aigi_pwned

# ---- installer smoke tests — run the installers into a throwaway HOME so a
#      regression like "backup_file returns 1 and set -e aborts before merge"
#      is caught. Needs jq (the installers do too).
echo ""
echo "== installer smoke tests =="
if command -v jq >/dev/null 2>&1; then
  SMOKE="$(mktemp -d)"
  if HOME="$SMOKE" bash "$DIR/install-hooks.sh" claude >/dev/null 2>&1 \
     && grep -q 'guard-bash' "$SMOKE/.claude/settings.json" 2>/dev/null; then
    ok "install-hooks merges hooks on a fresh install"
  else
    bad "install-hooks merges hooks on a fresh install"
  fi
  n1="$(jq '.hooks.PreToolUse | length' "$SMOKE/.claude/settings.json" 2>/dev/null)"
  HOME="$SMOKE" bash "$DIR/install-hooks.sh" claude >/dev/null 2>&1
  n2="$(jq '.hooks.PreToolUse | length' "$SMOKE/.claude/settings.json" 2>/dev/null)"
  [ -n "$n1" ] && [ "$n1" = "$n2" ] && ok "install-hooks is idempotent (no duplication)" \
                                    || bad "install-hooks is idempotent (no duplication)"
  if HOME="$SMOKE" bash "$DIR/install-commands.sh" >/dev/null 2>&1 \
     && [ -f "$SMOKE/.claude/commands/ship.md" ]; then
    ok "install-commands installs command files"
  else
    bad "install-commands installs command files"
  fi

  # The permissions snippet is valid JSON with deny rules.
  if jq -e '.permissions.deny | length > 0' "$DIR/settings-permissions.snippet.json" >/dev/null 2>&1; then
    ok "settings-permissions.snippet.json is valid with deny rules"
  else
    bad "settings-permissions.snippet.json is valid with deny rules"
  fi

  # install-settings merges the Claude-only permissions layer, idempotently.
  if HOME="$SMOKE" bash "$DIR/install-settings.sh" >/dev/null 2>&1 \
     && jq -e '.permissions.deny | index("Read(./.env)")' "$SMOKE/.claude/settings.json" >/dev/null 2>&1; then
    ok "install-settings merges the permissions deny layer"
  else
    bad "install-settings merges the permissions deny layer"
  fi
  p1="$(jq '.permissions.deny | length' "$SMOKE/.claude/settings.json" 2>/dev/null)"
  HOME="$SMOKE" bash "$DIR/install-settings.sh" >/dev/null 2>&1
  p2="$(jq '.permissions.deny | length' "$SMOKE/.claude/settings.json" 2>/dev/null)"
  [ -n "$p1" ] && [ "$p1" = "$p2" ] && ok "install-settings is idempotent (no duplication)" \
                                    || bad "install-settings is idempotent (no duplication)"

  # install-hooks wired the SessionStart memory loader (Claude).
  if jq -e '.hooks.SessionStart[0].hooks[0].command | test("load-memory")' "$SMOKE/.claude/settings.json" >/dev/null 2>&1; then
    ok "install-hooks wires the SessionStart load-memory hook"
  else
    bad "install-hooks wires the SessionStart load-memory hook"
  fi

  # load-memory emits valid SessionStart context for a found store, silent otherwise.
  MEMPROJ="$(mktemp -d)"; : > "$MEMPROJ/MEMORY.md"
  lm_out="$(printf '{"cwd":"%s","source":"startup"}' "$MEMPROJ" | HOOK_PLATFORM=claude bash "$DIR/hooks/load-memory.sh" 2>/dev/null)"
  if printf '%s' "$lm_out" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null 2>&1; then
    ok "load-memory emits SessionStart additionalContext for a found store"
  else
    bad "load-memory emits SessionStart additionalContext for a found store"
  fi
  EMPTYPROJ="$(mktemp -d)"
  lm_empty="$(printf '{"cwd":"%s","source":"startup"}' "$EMPTYPROJ" | HOME="$EMPTYPROJ" HOOK_PLATFORM=claude bash "$DIR/hooks/load-memory.sh" 2>/dev/null)"
  [ -z "$lm_empty" ] && ok "load-memory stays silent when no store exists" \
                     || bad "load-memory stays silent when no store exists"
  rm -rf "$MEMPROJ" "$EMPTYPROJ"

  # uninstall reverses hooks, permissions, and commands cleanly.
  HOME="$SMOKE" bash "$DIR/uninstall.sh" claude >/dev/null 2>&1
  if ! jq -e '(.hooks // {}) | has("SessionStart")' "$SMOKE/.claude/settings.json" >/dev/null 2>&1 \
     && ! jq -e '(.permissions // {}) | has("deny")' "$SMOKE/.claude/settings.json" >/dev/null 2>&1 \
     && [ ! -f "$SMOKE/.claude/commands/ship.md" ]; then
    ok "uninstall strips hooks, permissions, and command files"
  else
    bad "uninstall strips hooks, permissions, and command files"
  fi
  rm -rf "$SMOKE"

  # install.sh orchestrates every layer into a throwaway HOME.
  SMOKE2="$(mktemp -d)"
  if HOME="$SMOKE2" bash "$DIR/install.sh" --yes claude >/dev/null 2>&1 </dev/null \
     && jq -e '.permissions.deny and .hooks.SessionStart' "$SMOKE2/.claude/settings.json" >/dev/null 2>&1 \
     && [ -f "$SMOKE2/.claude/commands/ship.md" ] \
     && [ -f "$SMOKE2/.claude/CLAUDE.md" ]; then
    ok "install.sh orchestrates instructions + commands + hooks + settings"
  else
    bad "install.sh orchestrates instructions + commands + hooks + settings"
  fi
  rm -rf "$SMOKE2"
else
  echo "  (skipped — jq not installed)"
fi

echo ""
echo "$pass passed, $fail failed"
rm -f /tmp/aigi_test.out /tmp/aigi_test.err
[ "$fail" -eq 0 ]
