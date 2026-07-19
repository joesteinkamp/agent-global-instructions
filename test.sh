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

# 6c. {{EXTRAS}} splice: personal sections appear verbatim; empty leaves no
#     leak (test 1 covers the leak half). EXTRAS is file-fed normally; the env
#     var reaches render() directly under AIGI_NO_USER_ENV.
EXTRAS=$'## My extra section\n\n- A machine-specific rule.' render
assert_has "EXTRAS content is spliced into the render" '## My extra section'
assert_has "EXTRAS bullets survive verbatim"           '- A machine-specific rule.'

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

# 7b. The inverse: every name in SUBST_VARS is actually referenced as {{NAME}} in
#     the template — catches a var that's prompted/saved but renders nowhere (a
#     silently-discarded answer, as a stale TS_IP once was).
subst="$(sed -n 's/^SUBST_VARS=(\([^)]*\)).*/\1/p' "$CUSTOMIZE")"
unused=""
for v in $subst; do
  grep -qF "{{$v}}" "$DIR/template.md" || unused="$unused $v"
done
[ -z "$unused" ] && ok "every SUBST_VAR is used in the template" \
                 || bad "SUBST_VARS not referenced in template.md:$unused"

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
ENVF="$(mktemp "${TMPDIR:-/tmp}/.aigi.XXXXXX")"   # template: bare mktemp errors on BSD/macOS
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

# Shell env outranks the context files: run a copy of the engine beside a
# my-context.env, once plain (file wins) and once with an explicit env var.
PT="$(mktemp -d)"
cp "$CUSTOMIZE" "$DIR/template.md" "$PT/"
printf 'INC_DOCS="n"\n' > "$PT/my-context.env"
pt_file="$(cd "$PT" && bash ./customize.sh --print 2>/dev/null | grep -cF 'Documentation first' || true)"
pt_env="$(cd "$PT" && INC_DOCS=y bash ./customize.sh --print 2>/dev/null | grep -cF 'Documentation first' || true)"
{ [ "$pt_file" = 0 ] && [ "$pt_env" != 0 ]; } \
  && ok "explicit shell env var outranks my-context.env" \
  || bad "explicit shell env var outranks my-context.env (file=$pt_file env=$pt_env)"
rm -rf "$PT"

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

  # A renamed command (validate -> improve) is pruned on reinstall so an old
  # machine doesn't keep /validate alongside /improve.
  printf 'stale\n' > "$SMOKE/.claude/commands/validate.md"
  HOME="$SMOKE" bash "$DIR/install-commands.sh" >/dev/null 2>&1
  [ ! -e "$SMOKE/.claude/commands/validate.md" ] \
    && [ -f "$SMOKE/.claude/commands/improve.md" ] \
    && ok "install-commands prunes retired command names" \
    || bad "install-commands prunes retired command names"

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

  # install-hooks wired the PreCompact + SessionEnd lifecycle hooks (Claude).
  if jq -e '.hooks.PreCompact[0].hooks[0].command | test("precompact-archive")' "$SMOKE/.claude/settings.json" >/dev/null 2>&1 \
     && jq -e '.hooks.SessionEnd[0].hooks[0].command | test("log-session-end")' "$SMOKE/.claude/settings.json" >/dev/null 2>&1; then
    ok "install-hooks wires the PreCompact and SessionEnd hooks"
  else
    bad "install-hooks wires the PreCompact and SessionEnd hooks"
  fi

  # precompact-archive copies the transcript and logs a PreCompact audit record.
  PCDIR="$(mktemp -d)"; PCLOG="$PCDIR/log/tool-calls.jsonl"; PCTRANS="$PCDIR/t.jsonl"; printf '{"x":1}\n' > "$PCTRANS"
  printf '{"session_id":"s1","transcript_path":"%s","cwd":"/w","trigger":"auto"}' "$PCTRANS" \
    | AI_TOOL_LOG="$PCLOG" HOOK_PLATFORM=claude bash "$DIR/hooks/precompact-archive.sh" 2>/dev/null
  if [ -n "$(ls -1 "$PCDIR/log/transcripts/" 2>/dev/null)" ] \
     && jq -e 'select(.event=="PreCompact")' "$PCLOG" >/dev/null 2>&1; then
    ok "precompact-archive saves the transcript and logs a PreCompact record"
  else
    bad "precompact-archive saves the transcript and logs a PreCompact record"
  fi
  # ...and is graceful when no transcript path is supplied.
  printf '{"session_id":"s2","cwd":"/w"}' | AI_TOOL_LOG="$PCLOG" HOOK_PLATFORM=claude bash "$DIR/hooks/precompact-archive.sh" 2>/dev/null
  pc_rc=$?
  [ "$pc_rc" = 0 ] && ok "precompact-archive exits 0 with no transcript path" \
                   || bad "precompact-archive exits 0 with no transcript path"

  # log-session-end appends a SessionEnd record carrying the reason.
  printf '{"session_id":"s1","cwd":"/w","reason":"clear"}' | AI_TOOL_LOG="$PCLOG" HOOK_PLATFORM=claude bash "$DIR/hooks/log-session-end.sh" 2>/dev/null
  if jq -e 'select(.event=="SessionEnd" and .tool_name=="clear")' "$PCLOG" >/dev/null 2>&1; then
    ok "log-session-end records a SessionEnd with its reason"
  else
    bad "log-session-end records a SessionEnd with its reason"
  fi
  rm -rf "$PCDIR"

  # install-hooks wires the changelog-nudge Stop hook.
  if jq -e '[.hooks.Stop[].hooks[].command] | any(test("changelog-nudge"))' "$SMOKE/.claude/settings.json" >/dev/null 2>&1; then
    ok "install-hooks wires the changelog-nudge Stop hook"
  else
    bad "install-hooks wires the changelog-nudge Stop hook"
  fi

  # changelog-nudge prompts for an entry once per diff, then stays quiet (state
  # dir kept OUTSIDE the work tree so it doesn't perturb the diff fingerprint).
  CG="$(mktemp -d)"; CST="$(mktemp -d)"
  ( cd "$CG" && git init -q && git config user.email t@t && git config user.name t \
      && echo a > f && git add -A && git commit -qm init && echo b >> f ) >/dev/null 2>&1
  cg1="$(printf '{"cwd":"%s","stop_hook_active":false}' "$CG" | AI_NUDGE_STATE="$CST" HOOK_PLATFORM=claude bash "$DIR/hooks/changelog-nudge.sh" 2>/dev/null)"
  cg2="$(printf '{"cwd":"%s","stop_hook_active":false}' "$CG" | AI_NUDGE_STATE="$CST" HOOK_PLATFORM=claude bash "$DIR/hooks/changelog-nudge.sh" 2>/dev/null)"
  if printf '%s' "$cg1" | jq -e '.decision=="block" and (.reason|test("Change Log"))' >/dev/null 2>&1 && [ -z "$cg2" ]; then
    ok "changelog-nudge prompts for an entry once per diff, then stays quiet"
  else
    bad "changelog-nudge prompts for an entry once per diff, then stays quiet"
  fi
  rm -rf "$CG" "$CST"

  # Stop hooks wire verify-nudge BEFORE improve-nudge (verify-first ordering).
  if jq -e '.hooks.Stop[0].hooks[0].command | test("verify-nudge")' "$SMOKE/.claude/settings.json" >/dev/null 2>&1 \
     && jq -e '.hooks.Stop[0].hooks[1].command | test("improve-nudge")' "$SMOKE/.claude/settings.json" >/dev/null 2>&1; then
    ok "install-hooks wires verify-nudge before improve-nudge on Stop"
  else
    bad "install-hooks wires verify-nudge before improve-nudge on Stop"
  fi

  # verify-nudge: fires on an unverified UI change; quiet once verified or for non-UI diffs.
  if command -v git >/dev/null 2>&1; then
    VN="$(mktemp -d)"
    ( cd "$VN" && git init -q && git config user.email t@t.t && git config user.name t \
      && echo base > README.md && git add -A && git commit -qm init ) >/dev/null 2>&1
    mkdir -p "$VN/src/components"; echo ".x{}" > "$VN/src/components/Button.css"
    vn_ui="$(printf '{"cwd":"%s"}' "$VN" | AI_NUDGE_STATE="$VN/s1" HOOK_PLATFORM=claude bash "$DIR/hooks/verify-nudge.sh" 2>/dev/null)"
    printf '%s' "$vn_ui" | jq -e '.decision=="block"' >/dev/null 2>&1 \
      && ok "verify-nudge fires on an unverified UI change" \
      || bad "verify-nudge fires on an unverified UI change"
    # A verify report newer than the change silences it.
    mkdir -p "$VN/verify/run"; touch "$VN/verify/run/report.html"
    vn_fresh="$(printf '{"cwd":"%s"}' "$VN" | AI_NUDGE_STATE="$VN/s2" HOOK_PLATFORM=claude bash "$DIR/hooks/verify-nudge.sh" 2>/dev/null)"
    [ -z "$vn_fresh" ] && ok "verify-nudge stays quiet once a fresh verify report exists" \
                       || bad "verify-nudge stays quiet once a fresh verify report exists"
    # A non-UI-only diff does not fire (README/docs no longer match the UI gate).
    VN2="$(mktemp -d)"
    ( cd "$VN2" && git init -q && git config user.email t@t.t && git config user.name t \
      && echo base > notes.txt && git add -A && git commit -qm init && echo more >> notes.txt ) >/dev/null 2>&1
    vn_none="$(printf '{"cwd":"%s"}' "$VN2" | AI_NUDGE_STATE="$VN2/s" HOOK_PLATFORM=claude bash "$DIR/hooks/verify-nudge.sh" 2>/dev/null)"
    [ -z "$vn_none" ] && ok "verify-nudge stays quiet for a non-UI change" \
                      || bad "verify-nudge stays quiet for a non-UI change"

    # Skip marker: applying changes I already approved suppresses the backstop
    # nudge (consume-once, per-hook), then the next turn nudges normally again.
    VN3="$(mktemp -d)"; VN3S="$(mktemp -d)"
    ( cd "$VN3" && git init -q && git config user.email t@t.t && git config user.name t \
      && echo base > README.md && git add -A && git commit -qm init ) >/dev/null 2>&1
    mkdir -p "$VN3/src/components"; echo ".x{}" > "$VN3/src/components/Button.css"
    vk="$(printf '%s' "$VN3" | cksum | cut -d' ' -f1)"; touch "$VN3S/.nudge-skip-verify.$vk"
    vn_skip="$(printf '{"cwd":"%s"}' "$VN3" | AI_NUDGE_STATE="$VN3S" HOOK_PLATFORM=claude bash "$DIR/hooks/verify-nudge.sh" 2>/dev/null)"
    if [ -z "$vn_skip" ] && [ ! -f "$VN3S/.nudge-skip-verify.$vk" ]; then
      ok "verify-nudge honors + consumes the skip marker"
    else
      bad "verify-nudge honors + consumes the skip marker"
    fi
    vn_after="$(printf '{"cwd":"%s"}' "$VN3" | AI_NUDGE_STATE="$VN3S" HOOK_PLATFORM=claude bash "$DIR/hooks/verify-nudge.sh" 2>/dev/null)"
    printf '%s' "$vn_after" | jq -e '.decision=="block"' >/dev/null 2>&1 \
      && ok "verify-nudge nudges again after the skip marker is consumed" \
      || bad "verify-nudge nudges again after the skip marker is consumed"

    IN="$(mktemp -d)"; INS="$(mktemp -d)"
    ( cd "$IN" && git init -q && git config user.email t@t.t && git config user.name t \
      && echo base > README.md && git add -A && git commit -qm init \
      && for i in 1 2 3 4 5 6 7 8; do echo "x" > "f$i.txt"; done ) >/dev/null 2>&1
    ik="$(printf '%s' "$IN" | cksum | cut -d' ' -f1)"; touch "$INS/.nudge-skip-improve.$ik"
    in_skip="$(printf '{"cwd":"%s"}' "$IN" | AI_NUDGE_STATE="$INS" HOOK_PLATFORM=claude bash "$DIR/hooks/improve-nudge.sh" 2>/dev/null)"
    if [ -z "$in_skip" ] && [ ! -f "$INS/.nudge-skip-improve.$ik" ]; then
      ok "improve-nudge honors + consumes the skip marker"
    else
      bad "improve-nudge honors + consumes the skip marker"
    fi
    rm -rf "$VN" "$VN2" "$VN3" "$VN3S" "$IN" "$INS"
  fi

  # uninstall reverses hooks, permissions, and commands cleanly.
  HOME="$SMOKE" bash "$DIR/uninstall.sh" claude >/dev/null 2>&1
  if ! jq -e '(.hooks // {}) | (has("SessionStart") or has("PreCompact") or has("SessionEnd"))' "$SMOKE/.claude/settings.json" >/dev/null 2>&1 \
     && ! jq -e '(.permissions // {}) | has("deny")' "$SMOKE/.claude/settings.json" >/dev/null 2>&1 \
     && [ ! -f "$SMOKE/.claude/commands/ship.md" ]; then
    ok "uninstall strips hooks, permissions, and command files"
  else
    bad "uninstall strips hooks, permissions, and command files"
  fi
  rm -rf "$SMOKE"

  # install.sh orchestrates every layer into a throwaway HOME — and forwards
  # --no-design to install-commands.sh (the empty-array idiom on bash 3.2), so
  # core commands land while the design group stays out.
  SMOKE2="$(mktemp -d)"
  if HOME="$SMOKE2" bash "$DIR/install.sh" --yes --no-design claude >/dev/null 2>&1 </dev/null \
     && jq -e '.permissions.deny and .hooks.SessionStart' "$SMOKE2/.claude/settings.json" >/dev/null 2>&1 \
     && [ -f "$SMOKE2/.claude/commands/ship.md" ] \
     && [ ! -f "$SMOKE2/.claude/commands/ux-audit.md" ] \
     && [ -f "$SMOKE2/AGENTS.md" ] \
     && [ ! -L "$SMOKE2/.claude/CLAUDE.md" ] && grep -qF '@~/AGENTS.md' "$SMOKE2/.claude/CLAUDE.md" \
     && [ -L "$SMOKE2/.codex/AGENTS.md" ] && [ -L "$SMOKE2/.gemini/GEMINI.md" ] \
     && [ -f "$SMOKE2/.claude/CHANGELOG.md" ]; then
    ok "install.sh orchestrates every layer and forwards --no-design"
  else
    bad "install.sh orchestrates every layer and forwards --no-design"
  fi

  # Claude pointer: hand additions below the @import survive a re-render;
  # codex/gemini pointers stay symlinks.
  echo "- my claude-only note" >> "$SMOKE2/.claude/CLAUDE.md"
  HOME="$SMOKE2" AIGI_NO_USER_ENV=1 bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
  { grep -qF -- "- my claude-only note" "$SMOKE2/.claude/CLAUDE.md" \
    && grep -qF '@~/AGENTS.md' "$SMOKE2/.claude/CLAUDE.md" \
    && [ -L "$SMOKE2/.codex/AGENTS.md" ]; } \
    && ok "claude pointer preserves hand additions across re-renders" \
    || bad "claude pointer preserves hand additions across re-renders"

  # uninstall reverses the pointers: with no pre-existing backup they are
  # removed; ~/AGENTS.md itself stays.
  HOME="$SMOKE2" bash "$DIR/uninstall.sh" claude codex gemini >/dev/null 2>&1
  { [ ! -e "$SMOKE2/.claude/CLAUDE.md" ] && [ ! -e "$SMOKE2/.codex/AGENTS.md" ] \
    && [ ! -e "$SMOKE2/.gemini/GEMINI.md" ] && [ -f "$SMOKE2/AGENTS.md" ]; } \
    && ok "uninstall removes our pointers (no backups) and keeps ~/AGENTS.md" \
    || bad "uninstall removes our pointers (no backups) and keeps ~/AGENTS.md"
  rm -rf "$SMOKE2"

  # ...and when the pointer replaced a real file, uninstall restores it.
  SMK4="$(mktemp -d)"; mkdir -p "$SMK4/.claude"
  echo "original claude rules" > "$SMK4/.claude/CLAUDE.md"
  HOME="$SMK4" AIGI_NO_USER_ENV=1 bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
  HOME="$SMK4" bash "$DIR/uninstall.sh" claude >/dev/null 2>&1
  { [ -f "$SMK4/.claude/CLAUDE.md" ] && grep -qF "original claude rules" "$SMK4/.claude/CLAUDE.md"; } \
    && ok "uninstall restores a pre-existing claude file from its backup" \
    || bad "uninstall restores a pre-existing claude file from its backup"
  rm -rf "$SMK4"

  # write_global must NOT create the per-tool pointers when the ~/AGENTS.md
  # render fails — otherwise every tool dangles on a missing/stale target.
  # (Skipped as root, where an unwritable $HOME doesn't fail the render.)
  if [ "$(id -u)" != 0 ]; then
    SMK3="$(mktemp -d)"; mkdir -p "$SMK3/.claude" "$SMK3/.codex" "$SMK3/.gemini"
    chmod 555 "$SMK3"    # $HOME unwritable => the ~/AGENTS.md render fails
    HOME="$SMK3" AIGI_NO_USER_ENV=1 bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
    if [ ! -e "$SMK3/.claude/CLAUDE.md" ] && [ ! -L "$SMK3/.claude/CLAUDE.md" ]; then
      ok "write_global leaves pointers untouched when the render fails"
    else
      bad "write_global leaves pointers untouched when the render fails"
    fi
    chmod 755 "$SMK3"; rm -rf "$SMK3"
  fi

  # ---- render-commands: ports are generated from the canonical commands ----
  bash "$DIR/render-commands.sh" >/dev/null 2>&1 \
    && ok "render-commands.sh runs" || bad "render-commands.sh runs"
  # Idempotent: a second render produces byte-identical output (snapshot model).
  RC1="$(mktemp -d)"; cp -r "$DIR/commands/gemini" "$RC1/g" 2>/dev/null
  bash "$DIR/render-commands.sh" >/dev/null 2>&1
  diff -rq "$DIR/commands/gemini" "$RC1/g" >/dev/null 2>&1 \
    && ok "render-commands is idempotent" || bad "render-commands is idempotent"
  rm -rf "$RC1"
  # Faithful dialect transforms — ship-specific positives plus invariants across
  # ALL ports (so a regression on sync/verify/... is caught, not just ship).
  ft=1
  grep -q '^name: "ship"'  "$DIR/commands/codex/ship/SKILL.md" || ft=0 # Codex skill metadata
  grep -q 'run `git branch' "$DIR/commands/codex/ship/SKILL.md" || ft=0 # !`cmd` -> run `cmd`
  grep -q '{{args}}'        "$DIR/commands/gemini/ship.toml"  || ft=0   # gemini $ARGUMENTS -> {{args}}
  grep -q '!{git branch'    "$DIR/commands/gemini/ship.toml"  || ft=0   # gemini !`cmd` -> !{cmd}
  head -1 "$DIR/commands/cursor/ship.md" | grep -q '^<!--'    || ft=0   # cursor: no frontmatter
  for cf in "$DIR"/commands/codex/*/SKILL.md; do
    grep -q '^allowed-tools' "$cf" && ft=0                              # allowed-tools dropped everywhere
    grep -qF '!`' "$cf" && ft=0                                          # no leftover !`cmd` injection
    grep -q '^<!-- GENERATED' "$cf" || ft=0                               # marker is in the skill body
  done
  for gf in "$DIR"/commands/gemini/*.toml; do
    grep -q '\$ARGUMENTS' "$gf" && ft=0                                  # every $ARGUMENTS -> {{args}}
    grep -qF '!`' "$gf" && ft=0
  done
  # The cursor argument note appears IFF the canonical command uses $ARGUMENTS.
  for md in "$DIR"/commands/*.md; do
    b="$(basename "$md")"; [ "$b" = "README.md" ] && continue
    if grep -q '\$ARGUMENTS' "$md"; then
      grep -q 'no argument placeholder' "$DIR/commands/cursor/$b" || ft=0
    else
      grep -q 'no argument placeholder' "$DIR/commands/cursor/$b" && ft=0
    fi
  done
  [ "$ft" = 1 ] && ok "render-commands applies the per-tool dialect transforms (all ports)" \
                || bad "render-commands applies the per-tool dialect transforms (all ports)"

  # ---- multi-tool: codex / cursor / gemini command ports, hooks, settings ----
  # Every canonical command has a port in each tool dir (a missing port = a
  # command silently absent in that tool).
  miss=""
  for c in "$DIR"/commands/*.md; do
    [ "$(basename "$c")" = "README.md" ] && continue
    cn="$(basename "$c" .md)"
    [ -f "$DIR/commands/codex/$cn/SKILL.md" ] || miss="$miss codex/$cn"
    [ -f "$DIR/commands/cursor/$cn.md" ]   || miss="$miss cursor/$cn"
    [ -f "$DIR/commands/gemini/$cn.toml" ] || miss="$miss gemini/$cn"
  done
  [ -z "$miss" ] && ok "every canonical command has a codex/cursor/gemini port" \
                 || bad "missing command ports:$miss"

  # ---- command groups: the design group is INC_DESIGN-gated at install time ----
  # Design is on by default for everyone; an explicit INC_DESIGN=n opts out.
  dg_def="$(AIGI_NO_USER_ENV=1 "$CUSTOMIZE" --design-group 2>/dev/null)"
  dg_off="$(AIGI_NO_USER_ENV=1 INC_DESIGN=n "$CUSTOMIZE" --design-group 2>/dev/null)"
  { [ "$dg_def" = y ] && [ "$dg_off" = n ]; } \
    && ok "customize --design-group defaults on, honors explicit INC_DESIGN=n" \
    || bad "customize --design-group (got default=$dg_def explicit-n=$dg_off)"

  # Explicit flags gate the design commands and prune them when turned off.
  count_design() {  # $1 = commands dir -> number of design commands present
    local d="$1" f n=0
    for f in ux-audit; do [ -f "$d/$f.md" ] && n=$((n+1)); done
    printf '%s' "$n"
  }
  GT="$(mktemp -d)"; GC="$GT/.claude/commands"
  HOME="$GT" "$DIR/install-commands.sh" --no-design claude >/dev/null 2>&1
  core_ok=1; [ -f "$GC/ship.md" ] || core_ok=0
  des_off=$(count_design "$GC")
  HOME="$GT" "$DIR/install-commands.sh" --design claude >/dev/null 2>&1
  des_on=$(count_design "$GC")
  HOME="$GT" "$DIR/install-commands.sh" --no-design claude >/dev/null 2>&1
  des_pruned=$(count_design "$GC")
  { [ "$core_ok" = 1 ] && [ "$des_off" = 0 ] && [ "$des_on" = 1 ] && [ "$des_pruned" = 0 ]; } \
    && ok "design group: core installs, --design adds 1, --no-design prunes it" \
    || bad "design group gating (core=$core_ok off=$des_off on=$des_on pruned=$des_pruned)"
  rm -rf "$GT"

  # Prune-safety invariants (the destructive branch of install_dir): a user's
  # OWN command in the destination is never a prune candidate, and a hand-edited
  # design command is backed up (*.bak.*) before removal — counts alone don't
  # lock these in, so a prune-branch refactor could regress them silently.
  GT="$(mktemp -d)"; GC="$GT/.claude/commands"
  HOME="$GT" "$DIR/install-commands.sh" --design claude >/dev/null 2>&1
  echo "my own command" > "$GC/mycustom.md"
  echo "hand-edited" >> "$GC/ux-audit.md"
  HOME="$GT" "$DIR/install-commands.sh" --no-design claude >/dev/null 2>&1
  # shellcheck disable=SC2012  # counting mktemp-named backups; no exotic filenames
  bak_n=$(ls -1 "$GC"/ux-audit.md.bak.* 2>/dev/null | wc -l | tr -d ' ')
  { [ -f "$GC/mycustom.md" ] && [ ! -f "$GC/ux-audit.md" ] && [ "$bak_n" = 1 ] \
    && grep -q "hand-edited" "$GC"/ux-audit.md.bak.*; } \
    && ok "prune safety: user's own command survives, edited design command backed up" \
    || bad "prune safety (mycustom=$([ -f "$GC/mycustom.md" ] && echo kept || echo LOST) ux-audit-baks=$bak_n)"
  rm -rf "$GT"

  # The auto path end-to-end (the real-world default): no explicit flag — the
  # INC_DESIGN default resolves through customize.sh --design-group, exercising
  # the install-commands→customize seam integrated.
  GT="$(mktemp -d)"; GC="$GT/.claude/commands"
  HOME="$GT" AIGI_NO_USER_ENV=1 "$DIR/install-commands.sh" claude >/dev/null 2>&1
  auto_def=$(count_design "$GC")
  HOME="$GT" AIGI_NO_USER_ENV=1 INC_DESIGN=n "$DIR/install-commands.sh" claude >/dev/null 2>&1
  auto_off=$(count_design "$GC")
  { [ "$auto_def" = 1 ] && [ "$auto_off" = 0 ]; } \
    && ok "design group auto path (default installs 1, INC_DESIGN=n prunes)" \
    || bad "design group auto path (default=$auto_def explicit-n=$auto_off)"
  rm -rf "$GT"

  # A resolver ERROR is not "off": when customize.sh fails on the auto path, an
  # already-installed design pack must be left in place (warn, don't prune) —
  # a transient failure must never silently delete the designer's commands.
  GT="$(mktemp -d)"
  cp -R "$DIR/commands" "$GT/commands"
  cp "$DIR/install-commands.sh" "$GT/"
  printf '#!/bin/sh\nexit 1\n' > "$GT/customize.sh"; chmod +x "$GT/customize.sh"
  GC="$GT/home/.claude/commands"
  HOME="$GT/home" "$GT/install-commands.sh" --design claude >/dev/null 2>&1
  HOME="$GT/home" "$GT/install-commands.sh" claude >/dev/null 2>&1   # auto + broken resolver
  fail_kept=$(count_design "$GC")
  [ "$fail_kept" = 1 ] \
    && ok "design group survives a resolver failure (no silent prune on customize.sh error)" \
    || bad "resolver failure pruned design commands (kept=$fail_kept of 1)"
  rm -rf "$GT"

  # Group gating isn't claude-only: the gemini port maps <name>.toml back to the
  # canonical commands/<name>.md group (${base%.*} across a different extension).
  GT="$(mktemp -d)"; GG="$GT/.gemini/commands"
  count_design_toml() { local f2 n2=0; for f2 in ux-audit; do [ -f "$GG/$f2.toml" ] && n2=$((n2+1)); done; printf '%s' "$n2"; }
  HOME="$GT" "$DIR/install-commands.sh" --no-design gemini >/dev/null 2>&1
  g_off=$(count_design_toml)
  HOME="$GT" "$DIR/install-commands.sh" --design gemini >/dev/null 2>&1
  g_on=$(count_design_toml)
  { [ "$g_off" = 0 ] && [ "$g_on" = 1 ]; } \
    && ok "design group gating works for the gemini .toml dialect" \
    || bad "gemini design gating (off=$g_off on=$g_on)"
  rm -rf "$GT"

  # Gemini command TOML + the TOML permission snippets parse.
  if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import tomllib,glob; [tomllib.load(open(f,'rb')) for f in glob.glob('$DIR/commands/gemini/*.toml')+['$DIR/policies/gemini-guardrails.toml','$DIR/codex-permissions.snippet.toml']]" 2>/dev/null; then
      ok "gemini command TOML + TOML snippets parse"
    else
      bad "gemini command TOML + TOML snippets parse"
    fi
  fi
  jq -e '.permissions.deny | length > 0' "$DIR/settings-permissions.cursor.snippet.json" >/dev/null 2>&1 \
    && ok "cursor permissions snippet is valid with deny rules" \
    || bad "cursor permissions snippet is valid with deny rules"

  # Gemini argsPattern must fire against the JSON-serialized tool args (the form
  # the Policy Engine matches) — guards the anchor bug where .env / root-relative
  # build dirs silently never match (leaving only the best-effort hook).
  if command -v python3 >/dev/null 2>&1; then
    if python3 - "$DIR/policies/gemini-guardrails.toml" <<'PY' 2>/dev/null
import sys, re, tomllib
rules = tomllib.load(open(sys.argv[1], "rb"))["rule"]
def names(r): return r["toolName"] if isinstance(r["toolName"], list) else [r["toolName"]]
pat = next(r["argsPattern"] for r in rules if "write_file" in names(r))
rx = re.compile(pat)
must = ['{"content":"x","file_path":"/home/u/proj/.env"}',
        '{"content":"x","file_path":".env.local"}',
        '{"file_path":"build/app.js"}',
        '{"file_path":"node_modules/x/i.js"}',
        '{"file_path":"/p/package-lock.json"}']
mustnot = ['{"file_path":"src/app.js"}', '{"file_path":"README.md"}']
assert all(rx.search(s) for s in must), "a protected arg did not match"
assert not any(rx.search(s) for s in mustnot), "a benign arg matched"
PY
    then ok "gemini argsPattern matches JSON-serialized protected args"
    else bad "gemini argsPattern matches JSON-serialized protected args"
    fi
  fi

  # Vendored skills: every .claude/skills entry must be a SYMLINK resolving into
  # the canonical .agents/skills tree — parity by construction, not by copy.
  # The diff (which follows links) additionally catches a broken link.
  par_ok=1
  for sk in "$DIR"/.claude/skills/*; do
    [ -e "$sk" ] || continue
    [ -L "$sk" ] || par_ok=0
    case "$(readlink "$sk")" in ../../.agents/skills/*) ;; *) par_ok=0;; esac
  done
  diff -rq "$DIR/.claude/skills" "$DIR/.agents/skills" >/dev/null 2>&1 || par_ok=0
  [ "$par_ok" = 1 ] && ok ".claude/skills symlinks into .agents/skills (canonical tree)" \
                    || bad ".claude/skills symlinks into .agents/skills (canonical tree)"

  MT="$(mktemp -d)"
  HOME="$MT" bash "$DIR/install-commands.sh" >/dev/null 2>&1
  if [ -f "$MT/.codex/skills/ship/SKILL.md" ] && [ -f "$MT/.cursor/commands/ship.md" ] \
     && [ -f "$MT/.gemini/commands/ship.toml" ]; then
    ok "install-commands installs codex/cursor/gemini ports"
  else
    bad "install-commands installs codex/cursor/gemini ports"
  fi

  # Cursor hooks: top-level version:1, flat entries, idempotent through merge.
  HOME="$MT" bash "$DIR/install-hooks.sh" cursor >/dev/null 2>&1
  c1="$(jq '[.hooks[]|length]|add' "$MT/.cursor/hooks.json" 2>/dev/null)"
  HOME="$MT" bash "$DIR/install-hooks.sh" cursor >/dev/null 2>&1
  c2="$(jq '[.hooks[]|length]|add' "$MT/.cursor/hooks.json" 2>/dev/null)"
  if [ "$(jq '.version' "$MT/.cursor/hooks.json" 2>/dev/null)" = "1" ] \
     && [ -n "$c1" ] && [ "$c1" = "$c2" ]; then
    ok "install-hooks cursor sets version:1 and is idempotent"
  else
    bad "install-hooks cursor sets version:1 and is idempotent"
  fi

  # Codex hooks: file edits wired via the apply_patch matcher (path-guard + format).
  HOME="$MT" bash "$DIR/install-hooks.sh" codex >/dev/null 2>&1
  if jq -e '[.hooks.PreToolUse[].matcher]  | any(test("apply_patch"))' "$MT/.codex/hooks.json" >/dev/null 2>&1 \
     && jq -e '[.hooks.PostToolUse[].matcher] | any(test("apply_patch"))' "$MT/.codex/hooks.json" >/dev/null 2>&1; then
    ok "install-hooks codex wires apply_patch edit hooks"
  else
    bad "install-hooks codex wires apply_patch edit hooks"
  fi

  # Hook dialects: cursor blocks a secret read via {permission:deny}; codex
  # extracts the path from an apply_patch envelope and blocks the write (exit 2).
  cur_out="$(printf '{"file_path":".env","cwd":"/tmp"}' | HOOK_PLATFORM=cursor bash "$DIR/hooks/guard-paths.sh" 2>/dev/null)"
  printf '%s' "$cur_out" | jq -e '.permission == "deny"' >/dev/null 2>&1 \
    && ok "guard-paths emits the cursor permission:deny dialect" \
    || bad "guard-paths emits the cursor permission:deny dialect"
  printf '%s' '{"tool_input":{"command":"*** Update File: app/.env\n+X=1"},"cwd":"/tmp"}' \
    | HOOK_PLATFORM=codex bash "$DIR/hooks/guard-paths.sh" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && ok "guard-paths blocks a codex apply_patch write to .env" \
                  || bad "guard-paths blocks a codex apply_patch write to .env"

  # Cursor beforeReadFile (GUARD_SECRETS_ONLY): blocks reading .env, but NOT
  # node_modules/dist — which agents legitimately read (cursor block() exits 0
  # either way, so distinguish allow vs deny by whether it emitted JSON).
  so_env="$(printf '%s' '{"file_path":".env","cwd":"/tmp"}' | HOOK_PLATFORM=cursor GUARD_SECRETS_ONLY=1 bash "$DIR/hooks/guard-paths.sh" 2>/dev/null)"
  printf '%s' "$so_env" | jq -e '.permission == "deny"' >/dev/null 2>&1 \
    && ok "secrets-only read mode blocks reading .env" \
    || bad "secrets-only read mode blocks reading .env"
  so_nm="$(printf '%s' '{"file_path":"node_modules/react/index.js","cwd":"/tmp"}' | HOOK_PLATFORM=cursor GUARD_SECRETS_ONLY=1 bash "$DIR/hooks/guard-paths.sh" 2>/dev/null)"
  [ -z "$so_nm" ] && ok "secrets-only read mode allows reading node_modules" \
                  || bad "secrets-only read mode allows reading node_modules"

  # guard-bash: catastrophic-rm + force-push detection, per command SEGMENT.
  # `gb '<cmd>'` returns the hook's exit code (2 = blocked, 0 = allowed). Built
  # from a var so a wrapped catastrophic path is matched even though `rm` isn't
  # the first word (the regression a first-word-anchored match introduced).
  D=$'\x72\x6d'                                   # the delete cmd, kept out of grep-able literals
  gb() { printf '{"tool_input":{"command":"%s"}}' "$1" | HOOK_PLATFORM=claude bash "$DIR/hooks/guard-bash.sh" >/dev/null 2>&1; echo $?; }
  gb_block=1
  for c in "$D -rf /" "sudo $D -rf /" "/usr/bin/$D -rf /" "$D -rf ~" "$D -rf .."; do
    [ "$(gb "$c")" = 2 ] || gb_block=0
  done
  [ "$gb_block" = 1 ] && ok "guard-bash blocks catastrophic rm incl. sudo/path-prefixed" \
                      || bad "guard-bash blocks catastrophic rm incl. sudo/path-prefixed"
  gb_allow=1
  for c in "$D -rf dist && cd /" "$D -rf node_modules" "git push origin x && tar -xf a.tar"; do
    [ "$(gb "$c")" = 0 ] || gb_allow=0
  done
  [ "$gb_allow" = 1 ] && ok "guard-bash allows benign chained rm/tar segments" \
                      || bad "guard-bash allows benign chained rm/tar segments"
  fp_b="$(gb 'git push --force origin main')$(gb 'git push --force-with-lease origin +main')"
  fp_ok="$(gb 'git push --force-with-lease origin main')"
  { [ "$fp_b" = 22 ] && [ "$fp_ok" = 0 ]; } \
    && ok "guard-bash blocks --force/+refspec but allows safe --force-with-lease" \
    || bad "guard-bash blocks --force/+refspec but allows safe --force-with-lease"

  # Antigravity dialect: input under toolCall.args, deny is {"allow_tool":false,
  # "deny_reason":…} on stdout with exit 0 (non-zero would be a hook failure).
  R=$'\x72\x6d'
  ag_bash="$(printf '{"toolCall":{"args":{"CommandLine":"sudo %s -rf /"}}}' "$R" | HOOK_PLATFORM=antigravity bash "$DIR/hooks/guard-bash.sh" 2>/dev/null)"
  agb_rc="$(printf '{"toolCall":{"args":{"CommandLine":"sudo %s -rf /"}}}' "$R" | HOOK_PLATFORM=antigravity bash "$DIR/hooks/guard-bash.sh" >/dev/null 2>&1; echo $?)"
  { printf '%s' "$ag_bash" | jq -e '.allow_tool == false and (.deny_reason|type=="string")' >/dev/null 2>&1 && [ "$agb_rc" = 0 ]; } \
    && ok "guard-bash antigravity: {allow_tool:false, deny_reason} + exit 0" \
    || bad "guard-bash antigravity: {allow_tool:false, deny_reason} + exit 0"
  ag_env="$(printf '{"cwd":"/p","toolCall":{"args":{"TargetFile":"/p/.env"}}}' | HOOK_PLATFORM=antigravity bash "$DIR/hooks/guard-paths.sh" 2>/dev/null)"
  ag_ex="$(printf '{"cwd":"/p","toolCall":{"args":{"TargetFile":"/p/.env.example"}}}' | HOOK_PLATFORM=antigravity bash "$DIR/hooks/guard-paths.sh" 2>/dev/null)"
  { printf '%s' "$ag_env" | jq -e '.allow_tool == false' >/dev/null 2>&1 && [ -z "$ag_ex" ]; } \
    && ok "guard-paths antigravity: blocks .env (TargetFile), allows .env.example" \
    || bad "guard-paths antigravity: blocks .env (TargetFile), allows .env.example"
  # Antigravity delivers args as JSON-encoded strings, so TargetFile/CommandLine can
  # arrive wrapped in a literal quote pair — the guard must strip it or fail open.
  agq_p="$(jq -nc '{cwd:"/p",toolCall:{args:{TargetFile:"\"/p/.env\""}}}' | HOOK_PLATFORM=antigravity bash "$DIR/hooks/guard-paths.sh" 2>/dev/null)"
  agq_b="$(jq -nc --arg c "\"$R -rf /\"" '{toolCall:{args:{CommandLine:$c}}}' | HOOK_PLATFORM=antigravity bash "$DIR/hooks/guard-bash.sh" 2>/dev/null)"
  { printf '%s' "$agq_p" | jq -e '.allow_tool == false' >/dev/null 2>&1 && printf '%s' "$agq_b" | jq -e '.allow_tool == false' >/dev/null 2>&1; } \
    && ok "guard antigravity: strips quote-wrapped args (no fail-open)" \
    || bad "guard antigravity: strips quote-wrapped args (no fail-open)"

  # install/uninstall antigravity hooks.json (opt-in target) in a throwaway HOME.
  AGH="$(mktemp -d)"; mkdir -p "$AGH/.gemini/antigravity-cli"
  echo '{"my-own":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"/x.sh"}]}]}}' > "$AGH/.gemini/antigravity-cli/hooks.json"
  HOME="$AGH" bash "$DIR/install-hooks.sh" antigravity >/dev/null 2>&1
  if jq -e '."aigi-guard-bash".PreToolUse[0].matcher == "run_command"
            and ."aigi-guard-paths".PreToolUse[0].matcher == "write_to_file|replace_file_content|multi_replace_file_content"
            and (."aigi-log".PreToolUse and ."aigi-format".PostToolUse)
            and ."my-own"' "$AGH/.gemini/antigravity-cli/hooks.json" >/dev/null 2>&1 \
     && [ -x "$AGH/.gemini/antigravity-cli/hooks/guard-bash.ag.sh" ]; then
    ok "install-hooks antigravity writes hooks.json + wrappers, preserves user hooks"
  else
    bad "install-hooks antigravity writes hooks.json + wrappers, preserves user hooks"
  fi
  HOME="$AGH" bash "$DIR/uninstall.sh" antigravity >/dev/null 2>&1
  if jq -e 'has("my-own") and ([keys[]|select(startswith("aigi-"))]|length==0)' "$AGH/.gemini/antigravity-cli/hooks.json" >/dev/null 2>&1; then
    ok "uninstall antigravity strips aigi-* hooks, keeps user hooks"
  else
    bad "uninstall antigravity strips aigi-* hooks, keeps user hooks"
  fi
  rm -rf "$AGH"

  # Opt-in safety: with no ~/.gemini/antigravity-cli, install exits 0 and writes nothing.
  AGN="$(mktemp -d)"    # bare HOME, no .gemini at all
  HOME="$AGN" bash "$DIR/install-hooks.sh" antigravity >/dev/null 2>&1; agn_rc=$?
  if [ "$agn_rc" = 0 ] && [ ! -e "$AGN/.gemini/antigravity-cli/hooks.json" ]; then
    ok "install-hooks antigravity skips gracefully when agy is not installed"
  else
    bad "install-hooks antigravity skips gracefully when agy is not installed"
  fi
  rm -rf "$AGN"

  # Codex permissions block prepends ABOVE any existing [table], so top-level keys
  # stay top-level instead of being folded into the table (inert + corrupting).
  if command -v python3 >/dev/null 2>&1; then
    CT="$(mktemp -d)"; mkdir -p "$CT/.codex"
    printf '[mcp_servers.foo]\ncommand = "x"\n' > "$CT/.codex/config.toml"
    HOME="$CT" bash "$DIR/install-settings.sh" codex >/dev/null 2>&1
    if python3 - "$CT/.codex/config.toml" <<'PY' 2>/dev/null
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
assert d.get("approval_policy") == "on-request", "approval_policy not top-level"
assert d.get("sandbox_mode") == "workspace-write", "sandbox_mode not top-level"
assert d["mcp_servers"]["foo"]["command"] == "x", "user table corrupted"
PY
    then ok "codex permissions prepend keeps top-level keys + user table intact"
    else bad "codex permissions prepend keeps top-level keys + user table intact"
    fi
    rm -rf "$CT"
  fi

  # Settings: cursor deny merge + codex managed block + gemini policy, idempotent.
  HOME="$MT" bash "$DIR/install-settings.sh" cursor codex gemini >/dev/null 2>&1
  HOME="$MT" bash "$DIR/install-settings.sh" cursor codex gemini >/dev/null 2>&1
  s_ok=1
  jq -e '.permissions.deny | length > 0' "$MT/.cursor/cli-config.json" >/dev/null 2>&1 || s_ok=0
  [ "$(grep -c 'agent-global-instructions (codex permissions)' "$MT/.codex/config.toml" 2>/dev/null)" = "2" ] || s_ok=0
  [ -f "$MT/.gemini/policies/gemini-guardrails.toml" ] || s_ok=0
  [ "$s_ok" = 1 ] && ok "install-settings wires cursor/codex/gemini permissions (idempotent)" \
                  || bad "install-settings wires cursor/codex/gemini permissions (idempotent)"

  # Codex duplicate-key guard: never append when the user already set the keys.
  printf 'approval_policy = "never"\n' > "$MT/.codex/config.toml"
  HOME="$MT" bash "$DIR/install-settings.sh" codex >/dev/null 2>&1
  [ "$(grep -c 'approval_policy' "$MT/.codex/config.toml")" = "1" ] \
    && ok "install-settings respects an existing codex approval_policy" \
    || bad "install-settings respects an existing codex approval_policy"

  # uninstall reverses commands/hooks/policy for all four tools.
  HOME="$MT" bash "$DIR/uninstall.sh" >/dev/null 2>&1
  u_ok=1
  [ -f "$MT/.codex/skills/ship/SKILL.md" ]   && u_ok=0
  [ -d "$MT/.codex/skills/ship" ]            && u_ok=0   # no orphaned empty skill dir
  [ -f "$MT/.cursor/commands/ship.md" ]     && u_ok=0
  [ -f "$MT/.gemini/commands/ship.toml" ]   && u_ok=0
  jq -e '(.hooks // {}) | length > 0' "$MT/.cursor/hooks.json" >/dev/null 2>&1 && u_ok=0
  [ -f "$MT/.gemini/policies/gemini-guardrails.toml" ] && u_ok=0
  [ "$u_ok" = 1 ] && ok "uninstall reverses commands/hooks/settings for all tools" \
                  || bad "uninstall reverses commands/hooks/settings for all tools"
  rm -rf "$MT"
else
  echo "  (skipped — jq not installed)"
fi

echo ""
echo "$pass passed, $fail failed"
rm -f /tmp/aigi_test.out /tmp/aigi_test.err
[ "$fail" -eq 0 ]
