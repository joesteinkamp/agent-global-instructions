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

INC_ORCHESTRATION=n render
assert_no "INC_ORCHESTRATION=n removes the cross-tool orchestration heading" 'Orchestrating other AI CLIs'
assert_no "INC_ORCHESTRATION=n removes the model-routing pointer" 'model-routing'
assert_no "INC_ORCHESTRATION=n leaves no marker leak" 'SECTION:'
render
assert_has "default render includes cross-tool orchestration" 'Orchestrating other AI CLIs'
assert_has "default render points at the CLI roster" '~/.ai/clis'
assert_has "default render points at the model-routing table" '~/.ai/model-routing.md'

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

  # install-hooks wired the scorecard survey pair (SessionEnd queue + SessionStart offer).
  if jq -e '[.hooks.SessionEnd[].hooks[].command] | any(test("scorecard-enqueue"))' "$SMOKE/.claude/settings.json" >/dev/null 2>&1 \
     && jq -e '[.hooks.SessionStart[].hooks[].command] | any(test("scorecard-survey"))' "$SMOKE/.claude/settings.json" >/dev/null 2>&1; then
    ok "install-hooks wires the scorecard enqueue and survey hooks"
  else
    bad "install-hooks wires the scorecard enqueue and survey hooks"
  fi

  # setup-memory-os --yes writes the registry (markdown fallback in a bare HOME).
  HOME="$SMOKE" bash "$DIR/setup-memory-os.sh" --yes >/dev/null 2>&1
  grep -q '^MEMORYOS_TYPE=markdown' "$SMOKE/.ai/memory-os" 2>/dev/null \
    && ok "setup-memory-os writes a markdown registry when nothing is detected" \
    || bad "setup-memory-os writes a markdown registry when nothing is detected"

  # Scorecard lifecycle: queue -> offer (cwd-scoped, TTL-pruned) -> record -> lesson -> re-injected.
  SC="$(mktemp -d)"; SCLOG="$SC/log/tool-calls.jsonl"; SCD="$SC/log/scorecards"
  SCCFG="$SC/memcfg"; SCMEM="$SC/mem"; mkdir -p "$SC/log"
  printf 'MEMORYOS_TYPE=markdown\nMEMORYOS_PATH=%s\n' "$SCMEM" > "$SCCFG"
  i=0; while [ "$i" -lt 25 ]; do printf '{"ts":"t","tool":"claude","session":"sc1","cwd":"/w","event":"PreToolUse","tool_name":"Bash"}\n'; i=$((i+1)); done > "$SCLOG"
  printf '{"session_id":"sc1","cwd":"/w","reason":"clear"}' | AI_TOOL_LOG="$SCLOG" HOOK_PLATFORM=claude bash "$DIR/hooks/scorecard-enqueue.sh" 2>/dev/null
  printf '{"session_id":"sc2","cwd":"/w","reason":"clear"}' | AI_TOOL_LOG="$SCLOG" HOOK_PLATFORM=claude bash "$DIR/hooks/scorecard-enqueue.sh" 2>/dev/null
  [ -f "$SCD/pending/sc1.json" ] && [ ! -e "$SCD/pending/sc2.json" ] \
    && ok "scorecard-enqueue queues material sessions and skips trivial ones" \
    || bad "scorecard-enqueue queues material sessions and skips trivial ones"

  # A stale (>TTL) marker is pruned, a matching fresh one is offered — but never
  # for another cwd, and the offer text keeps dismissal explicit.
  jq -nc --arg e "$(( $(date +%s) - 8000 ))" '{session:"old1",cwd:"/w",reason:"clear",ended_epoch:($e|tonumber),ended:"t",records:30,offered:0}' > "$SCD/pending/old1.json"
  sv_other="$(printf '{"cwd":"/other","source":"startup"}' | AI_TOOL_LOG="$SCLOG" HOOK_PLATFORM=claude bash "$DIR/hooks/scorecard-survey.sh" 2>/dev/null)"
  sv="$(printf '{"cwd":"/w","session_id":"new1","source":"startup"}' | AI_TOOL_LOG="$SCLOG" HOOK_PLATFORM=claude bash "$DIR/hooks/scorecard-survey.sh" 2>/dev/null)"
  if printf '%s' "$sv" | jq -e '.hookSpecificOutput.additionalContext | test("sc1") and test("dismiss") and test("Rate that session")' >/dev/null 2>&1 \
     && [ -z "$sv_other" ] && [ ! -e "$SCD/pending/old1.json" ]; then
    ok "scorecard-survey offers a fresh matching survey and prunes expired markers"
  else
    bad "scorecard-survey offers a fresh matching survey and prunes expired markers"
  fi

  # Recording stores the rating, clears the marker, appends the lesson to the
  # memoryOS, and blocks re-queueing of the same session.
  AI_TOOL_LOG="$SCLOG" AI_MEMORYOS_CONFIG="$SCCFG" bash "$DIR/hooks/scorecard.sh" record \
    --session sc1 --rating 4 --why "solid work" --lesson "always bind 0.0.0.0" >/dev/null 2>&1
  printf '{"session_id":"sc1","cwd":"/w","reason":"clear"}' | AI_TOOL_LOG="$SCLOG" HOOK_PLATFORM=claude bash "$DIR/hooks/scorecard-enqueue.sh" 2>/dev/null
  if jq -e 'select(.session=="sc1" and .rating==4)' "$SCD/scorecards.jsonl" >/dev/null 2>&1 \
     && [ ! -e "$SCD/pending/sc1.json" ] \
     && grep -q 'always bind 0.0.0.0' "$SCMEM/LESSONS.md" 2>/dev/null \
     && jq -e 'select(.event=="Scorecard" and .tool_name=="record")' "$SCLOG" >/dev/null 2>&1; then
    ok "scorecard record stores the rating, the lesson, and is not re-queued"
  else
    bad "scorecard record stores the rating, the lesson, and is not re-queued"
  fi

  # Dismissal is one command: marker gone, dismissal remembered.
  jq -nc --arg e "$(date +%s)" '{session:"sc3",cwd:"/w",reason:"clear",ended_epoch:($e|tonumber),ended:"t",records:30,offered:0}' > "$SCD/pending/sc3.json"
  AI_TOOL_LOG="$SCLOG" bash "$DIR/hooks/scorecard.sh" dismiss --session sc3 >/dev/null 2>&1
  [ ! -e "$SCD/pending/sc3.json" ] \
    && jq -e 'select(.session=="sc3" and .dismissed==true)' "$SCD/scorecards.jsonl" >/dev/null 2>&1 \
    && ok "scorecard dismiss clears the marker and records the skip" \
    || bad "scorecard dismiss clears the marker and records the skip"

  # An ignored survey stops being offered after AI_SCORECARD_MAX_OFFERS.
  jq -nc --arg e "$(date +%s)" '{session:"sc4",cwd:"/w",reason:"clear",ended_epoch:($e|tonumber),ended:"t",records:30,offered:0}' > "$SCD/pending/sc4.json"
  m1="$(printf '{"cwd":"/w","source":"startup"}' | AI_TOOL_LOG="$SCLOG" AI_SCORECARD_MAX_OFFERS=1 HOOK_PLATFORM=claude bash "$DIR/hooks/scorecard-survey.sh" 2>/dev/null)"
  m2="$(printf '{"cwd":"/w","source":"startup"}' | AI_TOOL_LOG="$SCLOG" AI_SCORECARD_MAX_OFFERS=1 HOOK_PLATFORM=claude bash "$DIR/hooks/scorecard-survey.sh" 2>/dev/null)"
  [ -n "$m1" ] && [ -z "$m2" ] && [ ! -e "$SCD/pending/sc4.json" ] \
    && ok "scorecard-survey stops offering after max offers" \
    || bad "scorecard-survey stops offering after max offers"

  # load-memory closes the loop: recorded lessons are injected next session.
  LMPROJ="$(mktemp -d)"
  lm_lessons="$(printf '{"cwd":"%s","source":"startup"}' "$LMPROJ" | HOME="$LMPROJ" AI_MEMORYOS_CONFIG="$SCCFG" HOOK_PLATFORM=claude bash "$DIR/hooks/load-memory.sh" 2>/dev/null)"
  printf '%s' "$lm_lessons" | jq -e '.hookSpecificOutput.additionalContext | test("always bind 0.0.0.0")' >/dev/null 2>&1 \
    && ok "load-memory injects recent session lessons at SessionStart" \
    || bad "load-memory injects recent session lessons at SessionStart"
  rm -rf "$SC" "$LMPROJ"

  # One conservative advisory replaces the three blocking Stop hooks.
  if jq -e '[.hooks.Stop[].hooks[].command] as $c
            | ($c|length)==1 and ($c[0]|test("quality-nudge"))
              and ([$c[]|select(test("verify-nudge|improve-nudge|changelog-nudge"))]|length)==0' \
      "$SMOKE/.claude/settings.json" >/dev/null 2>&1; then
    ok "install-hooks consolidates Stop into one quality advisory"
  else
    bad "install-hooks consolidates Stop into one quality advisory"
  fi

  if command -v git >/dev/null 2>&1; then
    # Material UI diff: non-blocking JSON, optional verify mention, de-duped.
    QN="$(mktemp -d)"; QNS="$(mktemp -d)"
    ( cd "$QN" && git init -q && git config user.email t@t.t && git config user.name t \
      && printf 'base\n' > base.js && git add -A && git commit -qm init ) >/dev/null 2>&1
    mkdir -p "$QN/src/components"
    for i in 1 2 3 4; do
      j=0; while [ "$j" -lt 35 ]; do printf '.c%s-%s { color: green; }\n' "$i" "$j"; j=$((j+1)); done > "$QN/src/components/C$i.css"
    done
    q1="$(printf '{"cwd":"%s"}' "$QN" | AI_NUDGE_STATE="$QNS" HOOK_PLATFORM=claude bash "$DIR/hooks/quality-nudge.sh" 2>/dev/null)"; q1rc=$?
    q2="$(printf '{"cwd":"%s"}' "$QN" | AI_NUDGE_STATE="$QNS" HOOK_PLATFORM=claude bash "$DIR/hooks/quality-nudge.sh" 2>/dev/null)"
    if [ "$q1rc" = 0 ] \
       && printf '%s' "$q1" | jq -e '.continue==true and (.systemMessage|test("Advisory only")) and (.systemMessage|test("verification pass")) and (.systemMessage|test("Do not auto-run")) and (has("decision")|not)' >/dev/null 2>&1 \
       && [ -z "$q2" ]; then
      ok "quality-nudge is advisory, non-blocking, and once per diff"
    else
      bad "quality-nudge is advisory, non-blocking, and once per diff"
    fi

    # A verify report newer than all UI files removes only the verify suggestion;
    # the material-change advisory can still mention the Change Log gate.
    QNF="$(mktemp -d)"; mkdir -p "$QN/verify/run"; touch "$QN/verify/run/report.html"
    qfresh="$(printf '{"cwd":"%s"}' "$QN" | AI_NUDGE_STATE="$QNF" HOOK_PLATFORM=codex bash "$DIR/hooks/quality-nudge.sh" 2>/dev/null)"
    if printf '%s' "$qfresh" | jq -e '.continue==true and (.systemMessage|contains("verification pass")|not)' >/dev/null 2>&1; then
      ok "quality-nudge respects fresh verify evidence"
    else
      bad "quality-nudge respects fresh verify evidence"
    fi

    QNC="$(mktemp -d)"; QNCS="$(mktemp -d)"
    ( cd "$QNC" && git init -q && git config user.email t@t.t && git config user.name t \
      && printf 'base\n' > base.js && git add -A && git commit -qm init ) >/dev/null 2>&1
    mkdir -p "$QNC/src/components"
    for i in 1 2 3 4; do
      j=0; while [ "$j" -lt 35 ]; do printf '.c%s-%s { color: green; }\n' "$i" "$j"; j=$((j+1)); done > "$QNC/src/components/C$i.css"
    done
    qcur="$(printf '{"cwd":"%s","loop_count":0}' "$QNC" | AI_NUDGE_STATE="$QNCS" HOOK_PLATFORM=cursor bash "$DIR/hooks/quality-nudge.sh" 2>/dev/null)"
    qcur2="$(printf '{"cwd":"%s","loop_count":0}' "$QNC" | AI_NUDGE_STATE="$QNCS" HOOK_PLATFORM=cursor bash "$DIR/hooks/quality-nudge.sh" 2>/dev/null)"
    qcur_chain="$(printf '{"cwd":"%s","loop_count":1}' "$QNC" | AI_NUDGE_STATE="$QNCS" HOOK_PLATFORM=cursor bash "$DIR/hooks/quality-nudge.sh" 2>/dev/null)"
    if printf '%s' "$qcur" | jq -e '.followup_message|test("Advisory only") and test("Do not auto-run")' >/dev/null 2>&1 \
       && [ -z "$qcur2" ] \
       && [ -z "$qcur_chain" ]; then
      ok "quality-nudge emits cursor followup_message once and honors loop_count"
    else
      bad "quality-nudge emits cursor followup_message once and honors loop_count"
    fi

    # Small UI, documentation-only, and artifact-only work should stay silent.
    QS="$(mktemp -d)"; QSS="$(mktemp -d)"
    ( cd "$QS" && git init -q && git config user.email t@t.t && git config user.name t \
      && printf 'base\n' > base.js && git add -A && git commit -qm init \
      && mkdir -p src && printf '.x{}\n' > src/x.css ) >/dev/null 2>&1
    qsmall="$(printf '{"cwd":"%s"}' "$QS" | AI_NUDGE_STATE="$QSS" HOOK_PLATFORM=claude bash "$DIR/hooks/quality-nudge.sh" 2>/dev/null)"

    QD="$(mktemp -d)"; QDS="$(mktemp -d)"
    ( cd "$QD" && git init -q && git config user.email t@t.t && git config user.name t \
      && printf 'base\n' > base.js && git add -A && git commit -qm init \
      && mkdir -p docs && j=0; while [ "$j" -lt 200 ]; do printf 'documentation\n'; j=$((j+1)); done > docs/guide.md ) >/dev/null 2>&1
    qdocs="$(printf '{"cwd":"%s"}' "$QD" | AI_NUDGE_STATE="$QDS" HOOK_PLATFORM=claude bash "$DIR/hooks/quality-nudge.sh" 2>/dev/null)"

    QA="$(mktemp -d)"; QAS="$(mktemp -d)"
    ( cd "$QA" && git init -q && git config user.email t@t.t && git config user.name t \
      && printf 'base\n' > base.js && git add -A && git commit -qm init \
      && mkdir -p audits/run && j=0; while [ "$j" -lt 200 ]; do printf '<p>evidence</p>\n'; j=$((j+1)); done > audits/run/report.html ) >/dev/null 2>&1
    qart="$(printf '{"cwd":"%s"}' "$QA" | AI_NUDGE_STATE="$QAS" HOOK_PLATFORM=claude bash "$DIR/hooks/quality-nudge.sh" 2>/dev/null)"
    [ -z "$qsmall$qdocs$qart" ] \
      && ok "quality-nudge ignores small, docs-only, and artifact-only diffs" \
      || bad "quality-nudge ignores small, docs-only, and artifact-only diffs"

    # Consume-once suppression for applying previously approved review fixes.
    QNK="$(mktemp -d)"; qkey="$(printf '%s' "$QN" | cksum | cut -d' ' -f1)"; touch "$QNK/.nudge-skip-quality.$qkey"
    qskip="$(printf '{"cwd":"%s"}' "$QN" | AI_NUDGE_STATE="$QNK" HOOK_PLATFORM=claude bash "$DIR/hooks/quality-nudge.sh" 2>/dev/null)"
    if [ -z "$qskip" ] && [ ! -f "$QNK/.nudge-skip-quality.$qkey" ]; then
      ok "quality-nudge honors and consumes its skip marker"
    else
      bad "quality-nudge honors and consumes its skip marker"
    fi

    rm -rf "$QN" "$QNS" "$QNF" "$QNC" "$QNCS" "$QS" "$QSS" "$QD" "$QDS" "$QA" "$QAS" "$QNK"
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
  # Pre-seed a legacy roster so the install proves it migrates it to ~/.ai/.
  mkdir -p "$SMOKE2/.ai-logs"; echo "stale" > "$SMOKE2/.ai-logs/ai-clis"
  if HOME="$SMOKE2" bash "$DIR/install.sh" --yes --no-design claude >/dev/null 2>&1 </dev/null \
     && jq -e '.permissions.deny and .hooks.SessionStart' "$SMOKE2/.claude/settings.json" >/dev/null 2>&1 \
     && [ -f "$SMOKE2/.claude/commands/ship.md" ] \
     && [ ! -f "$SMOKE2/.claude/commands/ux-audit.md" ] \
     && [ ! -e "$SMOKE2/.claude/skills/ux-audit" ] \
     && [ -f "$SMOKE2/AGENTS.md" ] \
     && [ ! -L "$SMOKE2/.claude/CLAUDE.md" ] && grep -qF '@~/AGENTS.md' "$SMOKE2/.claude/CLAUDE.md" \
     && [ -L "$SMOKE2/.codex/AGENTS.md" ] \
     && [ -f "$SMOKE2/.claude/CHANGELOG.md" ] \
     && [ -f "$SMOKE2/.ai/clis" ] && [ ! -e "$SMOKE2/.ai-logs/ai-clis" ] \
     && cmp -s "$DIR/MODEL-ROUTING.md" "$SMOKE2/.ai/model-routing.md"; then
    ok "install.sh orchestrates every layer and forwards --no-design"
  else
    bad "install.sh orchestrates every layer and forwards --no-design"
  fi

  # Claude pointer: hand additions below the @import survive a re-render;
  # the codex pointer stays a symlink.
  echo "- my claude-only note" >> "$SMOKE2/.claude/CLAUDE.md"
  HOME="$SMOKE2" AIGI_NO_USER_ENV=1 bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
  { grep -qF -- "- my claude-only note" "$SMOKE2/.claude/CLAUDE.md" \
    && grep -qF '@~/AGENTS.md' "$SMOKE2/.claude/CLAUDE.md" \
    && [ -L "$SMOKE2/.codex/AGENTS.md" ]; } \
    && ok "claude pointer preserves hand additions across re-renders" \
    || bad "claude pointer preserves hand additions across re-renders"

  # uninstall reverses the pointers: with no pre-existing backup they are
  # removed; ~/AGENTS.md itself stays.
  HOME="$SMOKE2" bash "$DIR/uninstall.sh" claude codex >/dev/null 2>&1
  { [ ! -e "$SMOKE2/.claude/CLAUDE.md" ] && [ ! -e "$SMOKE2/.codex/AGENTS.md" ] \
    && [ -f "$SMOKE2/AGENTS.md" ]; } \
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
    SMK3="$(mktemp -d)"; mkdir -p "$SMK3/.claude" "$SMK3/.codex"
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
  RC1="$(mktemp -d)"; cp -r "$DIR/commands/codex" "$RC1/c" 2>/dev/null
  bash "$DIR/render-commands.sh" >/dev/null 2>&1
  diff -rq "$DIR/commands/codex" "$RC1/c" >/dev/null 2>&1 \
    && ok "render-commands is idempotent" || bad "render-commands is idempotent"
  rm -rf "$RC1"
  # Faithful dialect transforms — ship-specific positives plus invariants across
  # ALL ports (so a regression on sync/verify/... is caught, not just ship).
  ft=1
  grep -q '^name: "ship"'  "$DIR/commands/codex/ship/SKILL.md" || ft=0 # Codex skill metadata
  grep -q 'run `git branch' "$DIR/commands/codex/ship/SKILL.md" || ft=0 # !`cmd` -> run `cmd`
  head -1 "$DIR/commands/cursor/ship.md" | grep -q '^<!--'    || ft=0   # cursor: no frontmatter
  for cf in "$DIR"/commands/codex/*/SKILL.md; do
    grep -q '^allowed-tools' "$cf" && ft=0                              # allowed-tools dropped everywhere
    grep -qF '!`' "$cf" && ft=0                                          # no leftover !`cmd` injection
    grep -q '^<!-- GENERATED' "$cf" || ft=0                               # marker is in the skill body
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

  # ---- multi-tool: codex / cursor command ports, hooks, settings ----
  # Every canonical command has a port in each tool dir (a missing port = a
  # command silently absent in that tool).
  miss=""
  for c in "$DIR"/commands/*.md; do
    [ "$(basename "$c")" = "README.md" ] && continue
    cn="$(basename "$c" .md)"
    [ -f "$DIR/commands/codex/$cn/SKILL.md" ] || miss="$miss codex/$cn"
    [ -f "$DIR/commands/cursor/$cn.md" ]   || miss="$miss cursor/$cn"
  done
  [ -z "$miss" ] && ok "every canonical command has a codex/cursor port" \
                 || bad "missing command ports:$miss"

  # ---- command groups: the design group is INC_DESIGN-gated at install time ----
  # Design is on by default for everyone; an explicit INC_DESIGN=n opts out.
  dg_def="$(AIGI_NO_USER_ENV=1 "$CUSTOMIZE" --design-group 2>/dev/null)"
  dg_off="$(AIGI_NO_USER_ENV=1 INC_DESIGN=n "$CUSTOMIZE" --design-group 2>/dev/null)"
  { [ "$dg_def" = y ] && [ "$dg_off" = n ]; } \
    && ok "customize --design-group defaults on, honors explicit INC_DESIGN=n" \
    || bad "customize --design-group (got default=$dg_def explicit-n=$dg_off)"

  # Explicit flags gate the design pack and prune it when turned off. The design
  # command (/ux-audit) is skill-backed: on claude/cursor the vendored skill
  # symlinks in and the wrapper command must NOT install (no duplicate menu entry).
  count_design() {  # $1 = HOME root -> 1 if the claude design skill link is present
    [ -L "$1/.claude/skills/ux-audit" ] && printf 1 || printf 0
  }
  GT="$(mktemp -d)"; GC="$GT/.claude/commands"; GS="$GT/.claude/skills"; CC="$GT/.cursor/commands"; CS="$GT/.cursor/skills"
  HOME="$GT" "$DIR/install-commands.sh" --no-design claude cursor >/dev/null 2>&1
  core_ok=1; [ -f "$GC/ship.md" ] || core_ok=0
  off_ok=1; if [ -e "$GS/ux-audit" ] || [ -f "$GC/ux-audit.md" ] || [ -e "$CS/ux-audit" ] || [ -f "$CC/ux-audit.md" ]; then off_ok=0; fi
  HOME="$GT" "$DIR/install-commands.sh" --design claude cursor >/dev/null 2>&1
  on_ok=1
  [ -L "$GS/ux-audit" ] || on_ok=0
  [ -f "$GS/ux-audit/SKILL.md" ] || on_ok=0   # the link resolves to the vendored skill
  [ -f "$GC/ux-audit.md" ] && on_ok=0         # no duplicate wrapper beside the skill
  [ -L "$CS/ux-audit" ] || on_ok=0
  [ -f "$CS/ux-audit/SKILL.md" ] || on_ok=0
  [ -f "$CC/ux-audit.md" ] && on_ok=0         # cursor gets the skill, not the wrapper
  HOME="$GT" "$DIR/install-commands.sh" --no-design claude cursor >/dev/null 2>&1
  pr_ok=1; if [ -e "$GS/ux-audit" ] || [ -e "$CS/ux-audit" ] || [ -f "$CC/ux-audit.md" ]; then pr_ok=0; fi
  { [ "$core_ok" = 1 ] && [ "$off_ok" = 1 ] && [ "$on_ok" = 1 ] && [ "$pr_ok" = 1 ]; } \
    && ok "design group: skill symlink on claude/cursor, --no-design prunes both" \
    || bad "design group gating (core=$core_ok off=$off_ok on=$on_ok pruned=$pr_ok)"
  rm -rf "$GT"

  # Prune-safety invariants (the destructive branch of install_dir): a user's
  # OWN command in the destination is never a prune candidate, and a hand-edited
  # design command is backed up (*.bak.*) before removal — counts alone don't
  # lock these in, so a prune-branch refactor could regress them silently.
  GT="$(mktemp -d)"; CC="$GT/.cursor/commands"
  HOME="$GT" "$DIR/install-commands.sh" --design cursor >/dev/null 2>&1
  echo "my own command" > "$CC/mycustom.md"
  echo "hand-edited" >> "$CC/ux-audit.md"
  HOME="$GT" "$DIR/install-commands.sh" --no-design cursor >/dev/null 2>&1
  # shellcheck disable=SC2012  # counting mktemp-named backups; no exotic filenames
  bak_n=$(ls -1 "$CC"/ux-audit.md.bak.* 2>/dev/null | wc -l | tr -d ' ')
  { [ -f "$CC/mycustom.md" ] && [ ! -f "$CC/ux-audit.md" ] && [ "$bak_n" = 1 ] \
    && grep -q "hand-edited" "$CC"/ux-audit.md.bak.*; } \
    && ok "prune safety: user's own command survives, edited design command backed up" \
    || bad "prune safety (mycustom=$([ -f "$CC/mycustom.md" ] && echo kept || echo LOST) ux-audit-baks=$bak_n)"
  rm -rf "$GT"

  # Skill-backed migration safety: a pre-existing (hand-edited) wrapper command
  # on claude is backed up — never silently lost — when the vendored skill takes
  # over its name, and the skill symlink lands in its place.
  GT="$(mktemp -d)"; GC="$GT/.claude/commands"; GS="$GT/.claude/skills"
  mkdir -p "$GC"
  { cat "$DIR/commands/ux-audit.md"; echo "hand-edited"; } > "$GC/ux-audit.md"
  HOME="$GT" "$DIR/install-commands.sh" --design claude >/dev/null 2>&1
  # shellcheck disable=SC2012  # counting mktemp-named backups; no exotic filenames
  mig_bak=$(ls -1 "$GC"/ux-audit.md.bak.* 2>/dev/null | wc -l | tr -d ' ')
  { [ ! -f "$GC/ux-audit.md" ] && [ "$mig_bak" = 1 ] && [ -L "$GS/ux-audit" ]; } \
    && ok "skill-backed migration: edited claude wrapper backed up, skill link installed" \
    || bad "skill-backed migration (wrapper=$([ -f "$GC/ux-audit.md" ] && echo present || echo gone) baks=$mig_bak link=$([ -L "$GS/ux-audit" ] && echo yes || echo no))"
  rm -rf "$GT"

  # The auto path end-to-end (the real-world default): no explicit flag — the
  # INC_DESIGN default resolves through customize.sh --design-group, exercising
  # the install-commands→customize seam integrated.
  GT="$(mktemp -d)"
  HOME="$GT" AIGI_NO_USER_ENV=1 "$DIR/install-commands.sh" claude >/dev/null 2>&1
  auto_def=$(count_design "$GT")
  HOME="$GT" AIGI_NO_USER_ENV=1 INC_DESIGN=n "$DIR/install-commands.sh" claude >/dev/null 2>&1
  auto_off=$(count_design "$GT")
  { [ "$auto_def" = 1 ] && [ "$auto_off" = 0 ]; } \
    && ok "design group auto path (default installs 1, INC_DESIGN=n prunes)" \
    || bad "design group auto path (default=$auto_def explicit-n=$auto_off)"
  rm -rf "$GT"

  # A resolver ERROR is not "off": when customize.sh fails on the auto path, an
  # already-installed design pack must be left in place (warn, don't prune) —
  # a transient failure must never silently delete the designer's commands.
  GT="$(mktemp -d)"
  cp -R "$DIR/commands" "$GT/commands"
  mkdir -p "$GT/.agents" && cp -R "$DIR/.agents/skills" "$GT/.agents/skills"
  cp "$DIR/install-commands.sh" "$GT/"
  printf '#!/bin/sh\nexit 1\n' > "$GT/customize.sh"; chmod +x "$GT/customize.sh"
  HOME="$GT/home" "$GT/install-commands.sh" --design claude >/dev/null 2>&1
  HOME="$GT/home" "$GT/install-commands.sh" claude >/dev/null 2>&1   # auto + broken resolver
  fail_kept=$(count_design "$GT/home")
  [ "$fail_kept" = 1 ] \
    && ok "design group survives a resolver failure (no silent prune on customize.sh error)" \
    || bad "resolver failure pruned the design skill link (kept=$fail_kept of 1)"
  rm -rf "$GT"

  # Flipping skill-backed OFF must never clobber the vendored source: with the
  # symlink still in place from the previous install, the codex wrapper install
  # once wrote THROUGH it into .agents/skills/<name>/SKILL.md. The guard removes
  # our link first and installs the wrapper fresh; the vendored file stays pristine.
  GT="$(mktemp -d)"
  cp -R "$DIR/commands" "$GT/commands"
  mkdir -p "$GT/.agents" && cp -R "$DIR/.agents/skills" "$GT/.agents/skills"
  cp "$DIR/install-commands.sh" "$GT/"
  HOME="$GT/home" "$GT/install-commands.sh" --design claude codex >/dev/null 2>&1
  grep -v '^skill-backed: true$' "$GT/commands/ux-audit.md" > "$GT/commands/ux-audit.md.tmp" \
    && mv "$GT/commands/ux-audit.md.tmp" "$GT/commands/ux-audit.md"
  HOME="$GT/home" "$GT/install-commands.sh" --design claude codex >/dev/null 2>&1
  flip_ok=1
  cmp -s "$GT/.agents/skills/ux-audit/SKILL.md" "$DIR/.agents/skills/ux-audit/SKILL.md" || flip_ok=0
  [ -L "$GT/home/.codex/skills/ux-audit" ]           && flip_ok=0   # link gone
  [ -f "$GT/home/.codex/skills/ux-audit/SKILL.md" ]  || flip_ok=0   # wrapper installed fresh
  [ -f "$GT/home/.claude/commands/ux-audit.md" ]     || flip_ok=0   # claude wrapper back
  [ -e "$GT/home/.claude/skills/ux-audit" ]          && flip_ok=0   # claude link cleaned up
  [ "$flip_ok" = 1 ] \
    && ok "skill-backed flip-off installs wrappers without clobbering the vendored skill" \
    || bad "skill-backed flip-off (vendored-intact=$(cmp -s "$GT/.agents/skills/ux-audit/SKILL.md" "$DIR/.agents/skills/ux-audit/SKILL.md" && echo yes || echo NO))"
  rm -rf "$GT"

  # Data-safety branches of the skill-backed install — each is a silent-data-loss
  # regression if a refactor drops the guard: (a) a user's own REAL skill dir at
  # the skill-backed name is never clobbered; (b) a dangling link WE own (skill
  # renamed/dropped upstream) is pruned while a foreign dangling link is kept;
  # (c) codex install neither replaces nor writes through a foreign skill symlink.
  GT="$(mktemp -d)"; GS="$GT/.claude/skills"; DS="$GT/.codex/skills"
  mkdir -p "$GS/ux-audit" "$DS"
  echo "MINE" > "$GS/ux-audit/SKILL.md"
  ln -s "$DIR/.agents/skills/oldskill-gone" "$GS/oldskill-gone"   # dangling, ours
  ln -s /somewhere/else "$GS/foreign"                             # dangling, foreign
  ln -s /nonexistent/elsewhere "$DS/ship"                         # foreign, collides with a port name
  HOME="$GT" "$DIR/install-commands.sh" --design claude codex >/dev/null 2>&1
  ds_ok=1
  { [ ! -L "$GS/ux-audit" ] && grep -q MINE "$GS/ux-audit/SKILL.md"; } || ds_ok=0
  [ -L "$GS/oldskill-gone" ] && ds_ok=0
  [ -L "$GS/foreign" ] || ds_ok=0
  { [ -L "$DS/ship" ] && [ "$(readlink "$DS/ship")" = /nonexistent/elsewhere ]; } || ds_ok=0
  [ "$ds_ok" = 1 ] \
    && ok "skill-backed data safety: user dirs/foreign links untouched, our dangling links pruned" \
    || bad "skill-backed data safety (user-dir=$([ -d "$GS/ux-audit" ] && [ ! -L "$GS/ux-audit" ] && echo kept || echo LOST) ours-dangling=$([ -L "$GS/oldskill-gone" ] && echo LEFT || echo pruned) foreign=$([ -L "$GS/foreign" ] && echo kept || echo LOST))"
  rm -rf "$GT"

  # Retired names (renamed/removed commands, e.g. the /audit -> /ux-audit rename)
  # prune on reinstall — WITH a backup, since a generic name like "audit" could
  # be the user's own command rather than our stale install.
  GT="$(mktemp -d)"; GC="$GT/.claude/commands"
  mkdir -p "$GC"
  echo "the user's own audit notes" > "$GC/audit.md"
  echo "stale critique" > "$GC/critique.md"
  HOME="$GT" "$DIR/install-commands.sh" --no-design claude >/dev/null 2>&1
  ret_ok=1
  if [ -f "$GC/audit.md" ] || [ -f "$GC/critique.md" ]; then ret_ok=0; fi
  grep -q "the user's own audit notes" "$GC"/audit.md.bak.* 2>/dev/null || ret_ok=0
  [ "$ret_ok" = 1 ] \
    && ok "retired /audit + /critique prune with a backup of the prior copy" \
    || bad "retired prune (audit=$([ -f "$GC/audit.md" ] && echo present || echo gone) backup=$(grep -q "the user's own audit notes" "$GC"/audit.md.bak.* 2>/dev/null && echo yes || echo MISSING))"
  rm -rf "$GT"

  # Codex permissions TOML snippet parses.
  if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import tomllib; tomllib.load(open('$DIR/codex-permissions.snippet.toml','rb'))" 2>/dev/null; then
      ok "codex permissions TOML snippet parses"
    else
      bad "codex permissions TOML snippet parses"
    fi
  fi
  jq -e '.permissions.deny | length > 0' "$DIR/settings-permissions.cursor.snippet.json" >/dev/null 2>&1 \
    && ok "cursor permissions snippet is valid with deny rules" \
    || bad "cursor permissions snippet is valid with deny rules"

  # Vendored skills: every .claude/skills and .cursor/skills entry must be a
  # SYMLINK resolving into the canonical .agents/skills tree — parity by
  # construction, not by copy.
  par_ok=1
  for sk in "$DIR"/.claude/skills/* "$DIR"/.cursor/skills/*; do
    [ -e "$sk" ] || continue
    [ -L "$sk" ] || par_ok=0
    case "$(readlink "$sk")" in ../../.agents/skills/*) ;; *) par_ok=0;; esac
  done
  diff -rq "$DIR/.claude/skills" "$DIR/.agents/skills" >/dev/null 2>&1 || par_ok=0
  diff -rq "$DIR/.cursor/skills" "$DIR/.agents/skills" >/dev/null 2>&1 || par_ok=0
  [ "$par_ok" = 1 ] && ok ".claude/.cursor skills symlinks into .agents/skills (canonical tree)" \
                    || bad ".claude/.cursor skills symlinks into .agents/skills (canonical tree)"

  MT="$(mktemp -d)"
  HOME="$MT" bash "$DIR/install-commands.sh" claude codex cursor >/dev/null 2>&1
  if [ -f "$MT/.codex/skills/ship/SKILL.md" ] && [ -f "$MT/.cursor/commands/ship.md" ] \
     && [ -L "$MT/.codex/skills/ux-audit" ] && [ -f "$MT/.codex/skills/ux-audit/SKILL.md" ] \
     && [ -L "$MT/.cursor/skills/ux-audit" ] && [ -f "$MT/.cursor/skills/ux-audit/SKILL.md" ]; then
    ok "install-commands installs codex/cursor ports (+ skill-backed symlinks)"
  else
    bad "install-commands installs codex/cursor ports (+ skill-backed symlinks)"
  fi

  # Cursor hooks: top-level version:1, flat entries, idempotent through merge.
  HOME="$MT" bash "$DIR/install-hooks.sh" cursor >/dev/null 2>&1
  c1="$(jq '[.hooks[]|length]|add' "$MT/.cursor/hooks.json" 2>/dev/null)"
  HOME="$MT" bash "$DIR/install-hooks.sh" cursor >/dev/null 2>&1
  c2="$(jq '[.hooks[]|length]|add' "$MT/.cursor/hooks.json" 2>/dev/null)"
  if [ "$(jq '.version' "$MT/.cursor/hooks.json" 2>/dev/null)" = "1" ] \
     && [ -n "$c1" ] && [ "$c1" = "$c2" ] \
     && jq -e '[.hooks.stop[].command] | length==1 and (.[0]|test("quality-nudge"))' "$MT/.cursor/hooks.json" >/dev/null 2>&1 \
     && jq -e '.hooks.stop[0].loop_limit == 1' "$MT/.cursor/hooks.json" >/dev/null 2>&1; then
    ok "install-hooks cursor is idempotent and wires one advisory quality-nudge stop hook"
  else
    bad "install-hooks cursor is idempotent and wires one advisory quality-nudge stop hook"
  fi

  # Codex hooks: file edits wired via the apply_patch matcher (path-guard + format).
  HOME="$MT" bash "$DIR/install-hooks.sh" codex >/dev/null 2>&1
  if jq -e '[.hooks.PreToolUse[].matcher]  | any(test("apply_patch"))' "$MT/.codex/hooks.json" >/dev/null 2>&1 \
     && jq -e '[.hooks.PostToolUse[].matcher] | any(test("apply_patch"))' "$MT/.codex/hooks.json" >/dev/null 2>&1 \
     && jq -e '[.hooks.Stop[].hooks[].command] | length==1 and (.[0]|test("quality-nudge"))' "$MT/.codex/hooks.json" >/dev/null 2>&1; then
    ok "install-hooks codex wires edit guards and one quality advisory"
  else
    bad "install-hooks codex wires edit guards and one quality advisory"
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

  # Settings: cursor deny merge + codex managed block, idempotent.
  HOME="$MT" bash "$DIR/install-settings.sh" cursor codex >/dev/null 2>&1
  HOME="$MT" bash "$DIR/install-settings.sh" cursor codex >/dev/null 2>&1
  s_ok=1
  jq -e '.permissions.deny | length > 0' "$MT/.cursor/cli-config.json" >/dev/null 2>&1 || s_ok=0
  [ "$(grep -c 'agent-global-instructions (codex permissions)' "$MT/.codex/config.toml" 2>/dev/null)" = "2" ] || s_ok=0
  [ "$s_ok" = 1 ] && ok "install-settings wires cursor/codex permissions (idempotent)" \
                  || bad "install-settings wires cursor/codex permissions (idempotent)"

  # Codex duplicate-key guard: never append when the user already set the keys.
  printf 'approval_policy = "never"\n' > "$MT/.codex/config.toml"
  HOME="$MT" bash "$DIR/install-settings.sh" codex >/dev/null 2>&1
  [ "$(grep -c 'approval_policy' "$MT/.codex/config.toml")" = "1" ] \
    && ok "install-settings respects an existing codex approval_policy" \
    || bad "install-settings respects an existing codex approval_policy"

  # uninstall reverses commands/hooks/policy for these tools — removing only
  # what we installed. Plant user-owned skills entries plus one dangling link of
  # ours to lock in remove_skill_links' ownership boundary.
  ln -s /external/foo "$MT/.codex/skills/foo"
  mkdir -p "$MT/.codex/skills/myown" && echo mine > "$MT/.codex/skills/myown/SKILL.md"
  ln -s "$DIR/.agents/skills/ghost" "$MT/.claude/skills/ghost"
  ln -s "$DIR/.agents/skills/ghost" "$MT/.cursor/skills/ghost"
  HOME="$MT" bash "$DIR/uninstall.sh" claude codex cursor >/dev/null 2>&1
  u_ok=1
  [ -L "$MT/.codex/skills/foo" ]            || u_ok=0   # foreign link spared
  [ -f "$MT/.codex/skills/myown/SKILL.md" ] || u_ok=0   # user's real skill spared
  [ -L "$MT/.claude/skills/ghost" ]         && u_ok=0   # dangling link of ours removed
  [ -L "$MT/.cursor/skills/ghost" ]         && u_ok=0   # dangling link of ours removed
  [ -f "$MT/.codex/skills/ship/SKILL.md" ]   && u_ok=0
  [ -d "$MT/.codex/skills/ship" ]            && u_ok=0   # no orphaned empty skill dir
  [ -e "$MT/.codex/skills/ux-audit" ]        && u_ok=0   # skill-backed symlink removed
  [ -e "$MT/.claude/skills/ux-audit" ]       && u_ok=0
  [ -e "$MT/.cursor/skills/ux-audit" ]      && u_ok=0
  [ -f "$MT/.cursor/commands/ship.md" ]     && u_ok=0
  jq -e '(.hooks // {}) | length > 0' "$MT/.cursor/hooks.json" >/dev/null 2>&1 && u_ok=0
  [ "$u_ok" = 1 ] && ok "uninstall reverses commands/hooks/settings for all tools" \
                  || bad "uninstall reverses commands/hooks/settings for all tools"
  rm -rf "$MT"

  # Legacy gemini cleanup: `uninstall.sh gemini` strips whatever a
  # pre-retirement install left behind, without needing render-commands.sh's
  # (now-removed) gemini port as a comparison source.
  GL="$(mktemp -d)"
  mkdir -p "$GL/.gemini/commands" "$GL/.gemini/policies" "$GL/.gemini/hooks"
  printf '# GENERATED from commands/ship.md by render-commands.sh — do not edit.\ndescription = "x"\n\nprompt = ..."\n' \
    > "$GL/.gemini/commands/ship.toml"
  echo "not ours" > "$GL/.gemini/commands/my-own.toml"
  jq -n --arg cmd "env HOOK_PLATFORM=gemini \"$GL/.gemini/hooks/guard-bash.sh\"" \
    '{hooks:{BeforeTool:[{matcher:"run_shell_command",hooks:[{type:"command",command:$cmd}]}]}}' \
    > "$GL/.gemini/settings.json"
  echo "policy rules" > "$GL/.gemini/policies/gemini-guardrails.toml"
  echo "agents" > "$GL/AGENTS.md"; ln -s "$GL/AGENTS.md" "$GL/.gemini/GEMINI.md"
  HOME="$GL" bash "$DIR/uninstall.sh" gemini >/dev/null 2>&1
  gl_ok=1
  [ -f "$GL/.gemini/commands/ship.toml" ]     && gl_ok=0   # our generated port removed
  [ -f "$GL/.gemini/commands/my-own.toml" ]   || gl_ok=0   # the user's own file spared
  jq -e '(.hooks // {}) | length > 0' "$GL/.gemini/settings.json" >/dev/null 2>&1 && gl_ok=0
  [ -f "$GL/.gemini/policies/gemini-guardrails.toml" ] && gl_ok=0
  [ -e "$GL/.gemini/GEMINI.md" ]              && gl_ok=0   # our pointer removed
  [ "$gl_ok" = 1 ] && ok "uninstall.sh gemini cleans up a pre-retirement legacy install" \
                    || bad "uninstall.sh gemini cleans up a pre-retirement legacy install"
  rm -rf "$GL"
else
  echo "  (skipped — jq not installed)"
fi

echo ""
echo "$pass passed, $fail failed"
rm -f /tmp/aigi_test.out /tmp/aigi_test.err
[ "$fail" -eq 0 ]
