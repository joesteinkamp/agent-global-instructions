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

# 7. Every {{VAR}} placeholder in the template is substituted in a full render.
render
if grep -oE '\{\{[A-Z_]+\}\}' "$DIR/template.md" | sort -u | while read -r v; do
     grep -qF "$v" /tmp/aigi_test.out && echo "$v"; done | grep -q .; then
  bad "all template placeholders are handled"
else
  ok "all template placeholders are handled"
fi

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

echo ""
echo "$pass passed, $fail failed"
rm -f /tmp/aigi_test.out /tmp/aigi_test.err
[ "$fail" -eq 0 ]
