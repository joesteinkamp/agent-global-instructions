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
# Nobody answers prompts in a test run, even from a real terminal: the
# attended cases set AIGI_UNATTENDED=0 and AIGI_TTY to a file of answers.
export AIGI_UNATTENDED=1

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }

# Scratch files live in a per-run directory. They used to be fixed /tmp paths,
# which two overlapping runs silently share — a parallel agent on the same box,
# or two CI jobs on one host — and the loser sees another run's render, which
# surfaces as an unreproducible example-reproducibility failure. mktemp -d is
# given a template because a bare `mktemp -d` errors on BSD/macOS.
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/aigi_test.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
OUT="$TMPD/render.out"; ERR="$TMPD/render.err"
EXOUT="$TMPD/example.out"; PWNED="$TMPD/pwned"
# assert_has <desc> <needle> <<< text   |   assert_no <desc> <needle>
assert_has() { if grep -qF -- "$2" "$OUT"; then ok "$1"; else bad "$1"; fi; }
assert_no()  { if grep -qF -- "$2" "$OUT"; then bad "$1"; else ok "$1"; fi; }
render() { "$CUSTOMIZE" --print > "$OUT" 2>"$ERR"; }

echo "== render-engine tests =="

# 1. A full default render leaves no unresolved markers or placeholders.
render
assert_no "no {{ placeholders leak in a full render"  '{{'
assert_no "no SECTION: markers leak in a full render" 'SECTION:'
[ -s "$ERR" ] && bad "default render is silent (no stderr)" || ok "default render is silent (no stderr)"

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
assert_has "default render includes the local-models bullets" 'Local models are delegates'
assert_has "default render points at the local-model registry" '~/.ai/local-models'
assert_has "default render points at the orchestration playbook" '~/.ai/orchestration.md'
assert_has "default render points at the quality-workflows playbook" '~/.ai/quality-workflows.md'
assert_has "default render points at the web-preview playbook" '~/.ai/web-preview.md'

# Every documented codex delegate runs with a context dir as its workspace, which
# is never a git repo, so without --skip-git-repo-check codex refuses before
# doing anything ("Not inside a trusted directory"). Observed 2026-10-05.
codex_untrusted="$(grep -rnE 'codex exec[^`]*--cd' "$DIR/playbooks" "$DIR"/skills/*/SKILL.md 2>/dev/null \
  | grep -v -- '--skip-git-repo-check')"
[ -z "$codex_untrusted" ] \
  && ok "every documented codex exec --cd delegate passes --skip-git-repo-check" \
  || bad "every documented codex exec --cd delegate passes --skip-git-repo-check: $codex_untrusted"

INC_ORCHESTRATION=n render
assert_no "INC_ORCHESTRATION=n removes the orchestration-playbook pointer" '~/.ai/orchestration.md'
INC_IMPROVE=n render
assert_no "INC_IMPROVE=n removes the quality-workflows pointer" '~/.ai/quality-workflows.md'
assert_no "INC_IMPROVE=n leaves no marker leak" 'SECTION:'

render
assert_has "default render includes the proposals section" 'Proposals, asks, and decisions'
assert_has "default render distinguishes proposal from confirmation" 'Never dress a confirmation up as a proposal'
assert_has "default render puts the ask last" 'Put the ask last'
assert_has "default render forbids inventing a field a wrong guess breaks" 'leave blank the one field a wrong guess breaks'
INC_PROPOSALS=n render
assert_no "INC_PROPOSALS=n removes the proposals heading" 'Proposals, asks, and decisions'
assert_no "INC_PROPOSALS=n removes the ask-last rule" 'Put the ask last'
assert_no "INC_PROPOSALS=n leaves no marker leak" 'SECTION:'

render
assert_has "default render includes the prose section" 'How you write'
assert_has "default render makes claims name their evidence" 'says how you know it'
assert_has "default render sends you to the system, not a description" 'Check the system, not a description of it'
assert_has "default render bans inventing a specific" 'Never invent a specific to fill a slot you created'
# The two rules the roadmap requires survive this section, because each protects
# behaviour a naive concision rule would silently regress.
assert_has "default render exempts findings from brevity" 'Findings are never trimmed for brevity'
assert_has "default render keeps hedges that carry real uncertainty" 'Keep the hedges that carry real uncertainty'
assert_has "default render carries the three-lens plan question" 'Ask the three-lens question of every plan'
assert_has "three-lens question treats AX as a defect axis, not a courtesy" 'AX is not a courtesy here'
# The vendored `grilling` skill asks in frontier rounds; the render must not tell
# the agent the opposite. Both halves are asserted: the rule itself, and the
# absence of the superseded one-at-a-time wording anywhere in the plan section.
assert_has "default render asks questions in rounds" 'Ask in rounds, never one question at a time'
assert_no "default render drops the superseded one-at-a-time rule" "stated — one question at a time"
INC_PROSE=n render
assert_no "INC_PROSE=n removes the prose heading" 'How you write'
assert_no "INC_PROSE=n removes the findings-brevity rule" 'Findings are never trimmed for brevity'
assert_no "INC_PROSE=n leaves no marker leak" 'SECTION:'

render
assert_has "default render points at the agent-teams playbook" '~/.ai/agent-teams.md'
assert_has "default render defaults to a team" 'Default to a team'
assert_has "default render derives roles instead of asking" "Derive the roles from the task"
assert_has "default render names the role-definition files" '~/.codex/agents/<role>.toml'
assert_has "default render requires an adversarial lens" 'refuter'
# The palette must name every installed role, in the form agents reference them.
# It is derived from roles/*.md for exactly this reason — a hand-kept list drifts
# the moment a role is added, and did.
palette="$(grep -m1 'drawn from:' "$OUT" || true)"
for _r in "$DIR"/roles/*.md; do
  [ -e "$_r" ] || continue
  _rn="$(basename "$_r" .md)"
  [ "$_rn" = "README" ] && continue
  case "$palette" in
    *"$_rn"*) ok   "role palette includes $_rn";;
    *)        bad  "role palette includes $_rn";;
  esac
done
unset _r _rn palette
assert_no  "default render no longer tells the agent to ask for roles" 'Never assume roles'

# ---- PERSONA: the one role knob, and the one line it may change ------------
# PERSONA picks the lenses a team starts from ({{TEAM_DEFAULT}}) and nothing
# else. A second difference between persona renders is a per-role render, which
# the design-harness plan rules out (one harness for everyone).
echo ""
echo "== PERSONA team default =="
persona_line() {  # $1 = PERSONA value -> the rendered team-default line
  PERSONA="$1" "$CUSTOMIZE" --print 2>/dev/null | grep -m1 -A1 "Start from your role's lenses" | tail -n1
}
TD_DESIGNER='  `product-designer`, `ux-researcher`, `ui-designer`, plus a `refuter`.'
TD_ENGINEER='  `frontend-engineer`, `ui-designer`, plus a `refuter`.'
TD_MANAGER='  `design-manager`, `product-designer`, `ux-researcher`, plus a `refuter`.'
render
assert_has "default render starts a team from the role's lenses" "Start from your role's lenses"
assert_has "default render (no PERSONA) starts from the designer lenses" "$TD_DESIGNER"
p_bad=""
for pair in \
  "designer:$TD_DESIGNER" "DESIGNER:$TD_DESIGNER" "product-designer:$TD_DESIGNER" "prod:$TD_DESIGNER" \
  "pd:$TD_DESIGNER" "ux:$TD_DESIGNER" "ui:$TD_DESIGNER" "generic:$TD_DESIGNER" ":$TD_DESIGNER" \
  "design-engineer:$TD_ENGINEER" "Design-Engineer:$TD_ENGINEER" "engineer:$TD_ENGINEER" "eng:$TD_ENGINEER" \
  "dev:$TD_ENGINEER" "swe:$TD_ENGINEER" "frontend:$TD_ENGINEER" "backend:$TD_ENGINEER" \
  "design-manager:$TD_MANAGER" "manager:$TD_MANAGER" "mgr:$TD_MANAGER" "lead:$TD_MANAGER" "dm:$TD_MANAGER" \
  "Design Manager:$TD_MANAGER" "design_engineer:$TD_ENGINEER" "UX Designer:$TD_DESIGNER"; do
  p_in="${pair%%:*}"; p_want="${pair#*:}"
  [ "$(persona_line "$p_in")" = "$p_want" ] || p_bad="$p_bad '${p_in}'"
done
[ -z "$p_bad" ] && ok "PERSONA normalizes old and new values onto the three roles" \
                || bad "PERSONA mapped to the wrong team default for:$p_bad"
PERSONA=astronaut render
{ grep -qF "unknown PERSONA='astronaut'" "$ERR" && grep -qF "$TD_DESIGNER" "$OUT"; } \
  && ok "unknown PERSONA warns and falls back to designer" \
  || bad "unknown PERSONA warns and falls back to designer"
# Near-misses must warn, not silently match a prefix (product-manager is not a designer).
p_bad=""
for p_in in product-manager producer designated; do
  PERSONA="$p_in" render
  grep -qF "unknown PERSONA='$p_in'" "$ERR" || p_bad="$p_bad '$p_in'"
done
[ -z "$p_bad" ] && ok "PERSONA near-misses warn instead of matching a prefix" \
                || bad "PERSONA near-misses matched silently:$p_bad"

# The three renders differ in exactly one line, and it is the team-default line.
PRD="$TMPD/persona"; mkdir -p "$PRD"
for p in designer design-engineer design-manager; do
  PERSONA="$p" "$CUSTOMIZE" --print > "$PRD/$p.md" 2>/dev/null
done
p_only=1
for p in design-engineer design-manager; do
  d="$(diff "$PRD/designer.md" "$PRD/$p.md" | grep '^[<>]' || true)"
  [ "$(printf '%s\n' "$d" | grep -c '^[<>]')" = 2 ] || p_only=0
  printf '%s\n' "$d" | grep -v 'plus a `refuter`\.$' | grep -q . && p_only=0
done
[ "$p_only" = 1 ] && ok "persona renders differ only in the team-default line" \
                  || bad "persona renders differ outside the team-default line"
rm -rf "$PRD"

# TEAM_DEFAULT is derived, never read: an explicit value cannot disagree with
# PERSONA. TEAM_ROLES is the opposite — an explicit palette still wins, under
# any persona, and PERSONA never touches it.
TEAM_DEFAULT='`bogus-role`' PERSONA=design-engineer render
{ ! grep -qF 'bogus-role' "$OUT" && grep -qF "$TD_ENGINEER" "$OUT"; } \
  && ok "an explicit TEAM_DEFAULT is overwritten by the PERSONA-derived value" \
  || bad "an explicit TEAM_DEFAULT is overwritten by the PERSONA-derived value"
TEAM_ROLES='alpha-lens, beta-lens' PERSONA=design-manager render
{ grep -qF 'drawn from: alpha-lens, beta-lens.' "$OUT" && grep -qF "$TD_MANAGER" "$OUT"; } \
  && ok "an explicit TEAM_ROLES still wins under any PERSONA" \
  || bad "an explicit TEAM_ROLES still wins under any PERSONA"
PT="$(mktemp -d)"
cp "$CUSTOMIZE" "$DIR/template.md" "$PT/"
printf 'TEAM_ROLES="alpha-lens, beta-lens"\nPERSONA="design-engineer"\n' > "$PT/my-context.env"
pt_out="$(cd "$PT" && env -u AIGI_NO_USER_ENV bash ./customize.sh --print 2>/dev/null)"
case "$pt_out" in
  *'drawn from: alpha-lens, beta-lens.'*"$TD_ENGINEER"*) ok  "my-context.env sets PERSONA, and its TEAM_ROLES still wins";;
  *)                                                     bad "my-context.env sets PERSONA, and its TEAM_ROLES still wins";;
esac
rm -rf "$PT"
unset pair p_in p_want p_bad p_only p d pt_out
INC_TEAMS=n render
assert_no "INC_TEAMS=n removes the agent-teams heading" 'Agent teams & subagents'
assert_no "INC_TEAMS=n removes the agent-teams playbook pointer" '~/.ai/agent-teams.md'
assert_no "INC_TEAMS=n leaves no marker leak" 'SECTION:'

INC_LOCAL_MODELS=n render
assert_no "INC_LOCAL_MODELS=n removes the local-models bullets" 'Local models are delegates'
assert_no "INC_LOCAL_MODELS=n leaves no marker leak" 'SECTION:'
INC_ORCHESTRATION=n render
assert_no "INC_ORCHESTRATION=n drops the nested local-models block too" 'Local models are delegates'

# 2a-bis. The gates block is ungated: it must render under BOTH autonomy postures,
# because it is the only enumeration of what stops the agent. It used to live
# inside the aggressive variant, where a balanced render got a drifted copy.
render
assert_has "default render carries the canonical gates block" '### Gates — stop and ask'
assert_has "gates block states the invariant"                 'nothing about the shape of the work loosens a gate'
assert_has "gates block enumerates the money gate"            '**Spending money.**'
assert_has "gates block enumerates the bypass-flag gate"      '--dangerously-skip-permissions'
AUTONOMY=balanced render
assert_has "balanced render carries the gates block too"      '### Gates — stop and ask'
assert_has "balanced render keeps the gate invariant"         'nothing about the shape of the work loosens a gate'

# 2b. Autonomy posture gates the long-running-work (loops/goals) section.
render
assert_has "default (aggressive) render includes Long-running work" '## Long-running work'
assert_has "aggressive render names the goal primitive"             '/goal <condition>'
assert_has "aggressive render names the loop primitive"             '/loop [interval] <prompt>'
assert_has "aggressive render draws the goal-vs-loop line"          'stopping rule'
assert_has "aggressive render keeps gates inside goal turns"        'every goal turn'
assert_has "aggressive render offers the goal at kickoff"           'Offer the goal at kickoff, not at handoff'
assert_has "aggressive render checks hook policy before a goal"    'Check that the goal can run before you offer it'
AUTONOMY=balanced render
assert_no "AUTONOMY=balanced omits the Long-running work section" 'Long-running work'
assert_no "AUTONOMY=balanced leaves no marker leak" 'SECTION:'

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
[ -s "$ERR" ] && bad "special-char value renders without error" || ok "special-char value renders without error"
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
  grep -qF -- "$v" "$OUT" && leaks="$leaks $v"
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
  ( set -a; . "$ex"; set +a; AIGI_NO_USER_ENV=1 "$CUSTOMIZE" --print ) > "$EXOUT" 2>/dev/null
  if [ -f "$md" ] && diff -q "$EXOUT" "$md" >/dev/null; then
    ok "example $base reproduces from $base.env"
  else
    bad "example $base reproduces from $base.env"
  fi
done
rm -f "$EXOUT"

# ---- refuter rubric + artifact policy --------------------------------------
render
assert_has "artifacts section states a diagram policy" 'A diagram has to earn its place'
assert_has "diagram policy requires selectable labels, not a picture" 'never a raster image'
assert_has "diagram policy forbids inventing shapes" "don't add a box, an arrow"

# The rubric lives inline in the role because the Codex dialect is one TOML
# string with no way to reference another file — so assert both dialects carry it.
grep -qF 'score the claim, not your effort' "$DIR/roles/refuter.md" \
  && ok "refuter role carries the rubric" \
  || bad "refuter role carries the rubric"
# roles/codex/ is GENERATED and gitignored, so it does not exist in a fresh
# checkout — which is exactly what CI has. Render before asserting rather than
# depending on another test having run first: a test whose result depends on
# suite order passes locally and fails in CI, which is how this one hid.
"$DIR/render-roles.sh" >/dev/null 2>&1
grep -qF 'Scope match' "$DIR/roles/codex/refuter.toml" 2>/dev/null \
  && ok "refuter rubric renders into the Codex dialect" \
  || bad "refuter rubric renders into the Codex dialect"
# The threshold has to be an action, not a note.
grep -qF 'Scope match is 2' "$DIR/roles/refuter.md" \
  && ok "refuter rubric gates 'holds' on scope match" \
  || bad "refuter rubric gates 'holds' on scope match"
grep -qF 'pre-emit' "$DIR/playbooks/quality-workflows.md" \
  && ok "quality-workflows places the refuter pre-emit" \
  || bad "quality-workflows places the refuter pre-emit"

# evals: an entry may point at a role or playbook surface, and a bad path must
# fail loudly rather than silently checking the render instead.
EVF="$(mktemp -d)"; mkdir -p "$EVF/evals"
cp "$DIR/evals/run.sh" "$EVF/evals/"; cp -R "$DIR/customize.sh" "$DIR/template.md" "$DIR/extras.local.md" "$EVF/" 2>/dev/null
printf '## BEH-99 — bad path\nanchor: anything\norigin: test\nfile: roles/does-not-exist.md\n' > "$EVF/evals/behaviours.md"
# Capture, then match. Piping run.sh into grep would report the PIPELINE status
# under `set -o pipefail`, which is run.sh's deliberate exit 1 — so a passing
# assertion would read as a failure for a reason that has nothing to do with it.
ev_bad_out="$( cd "$EVF" && ./evals/run.sh 2>&1 )" || true
case "$ev_bad_out" in
  *"BAD FILE"*) ok  "evals fails loudly on a file: path that does not exist";;
  *)            bad "evals fails loudly on a file: path that does not exist";;
esac
rm -rf "$EVF"

# ---- vendored skill integrity ----------------------------------------------
echo ""
echo "== vendored skills (import integrity) =="

"$DIR/verify-skills.sh" >/dev/null 2>&1 \
  && ok "verify-skills passes against the recorded manifest" \
  || bad "verify-skills passes against the recorded manifest"

# Every vendored tree must be recorded, or an import lands unpinned and silent.
vs_disk="$(find "$DIR/.agents/skills" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')"
vs_rec="$(jq -r '.skills | keys | length' "$DIR/skills-manifest.json" 2>/dev/null)"
[ "$vs_disk" = "$vs_rec" ] \
  && ok "every vendored skill is in the manifest ($vs_disk)" \
  || bad "every vendored skill is in the manifest (disk=$vs_disk recorded=$vs_rec)"

# The instrument has to be able to fail. A single byte, deep in the largest tree,
# must be caught — that is the case skills-lock.json misses entirely.
VSD="$(mktemp -d)"
cp -R "$DIR/.agents" "$DIR/verify-skills.sh" "$DIR/skills-manifest.json" "$VSD/" 2>/dev/null
vs_target="$(find "$VSD/.agents/skills/ux-audit" -type f -name '*.json' | head -1)"
if [ -n "$vs_target" ]; then
  printf ' ' >> "$vs_target"
  if ( cd "$VSD" && ./verify-skills.sh >/dev/null 2>&1 ); then
    bad "a one-byte change inside a vendored tree fails verification"
  else
    ok "a one-byte change inside a vendored tree fails verification"
  fi
else
  bad "a one-byte change inside a vendored tree fails verification (no target file found)"
fi
rm -rf "$VSD"

# ---- design policy is routed, not restated ---------------------------------
render
assert_has "design section routes to the project's guardrails" "cite it, don't restate it"
assert_has "design section names a ban ID to cite" 'DES-03'
assert_no  "design section no longer restates the scales rule" 'Stay on the scales'
# The a11y floor is kept ON PURPOSE despite partly duplicating DES-22 / UX-07:
# a project shipping no guardrails/ would otherwise get no accessibility rule.
assert_has "design section keeps the a11y floor for projects with no guardrails" 'the floor that holds when there are no guardrails'
assert_has "design section keeps axe-core as the automated check" 'axe-core'

# ---- evals: the behaviour anchors ------------------------------------------
echo ""
echo "== evals (instruction regressions) =="

"$DIR/evals/run.sh" >/dev/null 2>&1 \
  && ok "evals/run.sh passes against the default render" \
  || bad "evals/run.sh passes against the default render"

# Every entry must carry an anchor and an origin, or the run reports a behaviour
# it cannot actually check and a half-written entry passes as coverage.
ev_bad=0
ev_ids="$(grep -c '^## BEH-' "$DIR/evals/behaviours.md")"
ev_anchors="$(grep -c '^anchor: ' "$DIR/evals/behaviours.md")"
ev_origins="$(grep -c '^origin: ' "$DIR/evals/behaviours.md")"
[ "$ev_ids" = "$ev_anchors" ] && [ "$ev_ids" = "$ev_origins" ] || ev_bad=1
[ "$ev_bad" = 0 ] \
  && ok "every behaviour declares an anchor and an origin ($ev_ids)" \
  || bad "every behaviour declares an anchor and an origin (ids=$ev_ids anchors=$ev_anchors origins=$ev_origins)"

# Stable IDs are the contract: a duplicate makes a failure message ambiguous.
[ "$(grep -o '^## BEH-[0-9]*' "$DIR/evals/behaviours.md" | sort | uniq -d | wc -l)" -eq 0 ] \
  && ok "behaviour IDs are unique" \
  || bad "behaviour IDs are unique"

# The instrument has to be able to fail, or it is decoration. Break one anchor in
# a throwaway copy of the tree and require a named, non-zero failure.
EVD="$(mktemp -d)"
cp -R "$DIR/customize.sh" "$DIR/template.md" "$DIR/extras.local.md" "$EVD/" 2>/dev/null
mkdir -p "$EVD/evals"; cp "$DIR/evals/run.sh" "$DIR/evals/behaviours.md" "$EVD/evals/"
# Reword the protected findings rule the way a plausible concision edit would.
sed 's/\*\*Findings are never trimmed for brevity\.\*\*/**Keep findings brief.**/' \
  "$DIR/template.md" > "$EVD/template.md"
ev_out="$(cd "$EVD" && AIGI_NO_USER_ENV=1 ./evals/run.sh 2>&1)"; ev_rc=$?
if [ "$ev_rc" -ne 0 ] && printf '%s' "$ev_out" | grep -q 'BEH-04'; then
  ok "a plausible concision edit fails the eval, naming the behaviour"
else
  bad "a plausible concision edit fails the eval, naming the behaviour"
fi
rm -rf "$EVD"

# ---- load_env (the parser) — runs WITHOUT AIGI_NO_USER_ENV via a temp env ----
echo ""
echo "== load_env parser tests =="
ENVF="$(mktemp "${TMPDIR:-/tmp}/.aigi.XXXXXX")"   # template: bare mktemp errors on BSD/macOS
cat > "$ENVF" <<'EOF'
NAME="Quote Tester"
EOF
# Single-quoted format string: the $( ) must reach the file unexpanded, or the
# canary fires while writing the fixture instead of while parsing it.
printf 'EVIL="$(touch %s)"\n' "$PWNED" >> "$ENVF"
cat >> "$ENVF" <<'EOF'
ROLE='one'\''s job'
CARES="line one
line two"
EOF
unset AIGI_NO_USER_ENV
rm -f "$PWNED"
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
[ ! -e "$PWNED" ] && ok "value is NOT executed (no code injection)" || bad "value is NOT executed (no code injection)"
rm -f "$ENVF" "$PWNED"

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

# ---- role source contract — roles/*.md is the canonical source for BOTH
#      dialects, and nothing downstream reads it strictly: install-roles.sh
#      copies it, render-roles.sh renders it. A role with a typo'd tools: entry,
#      a name that disagrees with its filename, or a missing Return section
#      installs cleanly and then quietly behaves like a generic agent. Assert the
#      contract in the source, where a break is cheap to find.
echo ""
echo "== role source contract =="

# Extend deliberately: an unknown tool name in frontmatter is silently dropped by
# the host, which is exactly the failure this list exists to catch.
ROLE_TOOLS_OK=" Read Grep Glob Bash Edit Write WebFetch WebSearch "

role_fm() {  # $1 = file, $2 = key -> trimmed value, surrounding quotes stripped
  awk -v key="$2" '
    { sub(/\r$/,"") }
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && $0 ~ ("^" key ":") {
      v=$0; sub("^" key ":[[:space:]]*","",v); gsub(/[[:space:]]+$/,"",v)
      if (v ~ /^".*"$/) v = substr(v, 2, length(v) - 2)
      print v; exit
    }
  ' "$1"
}
role_body() {
  awk '
    { sub(/\r$/,"") }
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { infm=0; started=1; next }
    started
  ' "$1"
}

r_fm=""; r_name=""; r_tools=""; r_sandbox=""; r_body=""; r_rem=""; r_sect=""; r_floor=""; r_unatt=""
n_roles=0
for f in "$DIR"/roles/*.md; do
  [ -e "$f" ] || continue
  base="$(basename "$f" .md)"
  [ "$base" = "README" ] && continue
  n_roles=$((n_roles+1))

  head -n1 "$f" | grep -q '^---$' || r_fm="$r_fm $base(no-frontmatter)"
  for k in name description tools effort reminder; do
    [ -n "$(role_fm "$f" "$k")" ] || r_fm="$r_fm $base:$k"
  done

  # The agent is addressed by filename; a disagreeing name: is a role nobody can
  # spawn under the name they typed.
  [ "$(role_fm "$f" name)" = "$base" ] || r_name="$r_name $base"

  for t in $(role_fm "$f" tools | tr ',' ' '); do
    case "$ROLE_TOOLS_OK" in *" $t "*) ;; *) r_tools="$r_tools $base:$t";; esac
  done

  sb="$(role_fm "$f" sandbox)"
  case "$sb" in ""|read-only) ;; *) r_sandbox="$r_sandbox $base:$sb";; esac

  body="$(role_body "$f")"
  [ -n "$(printf '%s' "$body" | tr -d '[:space:]')" ] || r_body="$r_body $base"

  # Same string in three places (frontmatter, first body line, last body line)
  # only helps while the three agree.
  want="**Reminder:** $(role_fm "$f" reminder)"
  first="$(printf '%s\n' "$body" | grep -m1 -v '^[[:space:]]*$' || true)"
  last="$(printf '%s\n' "$body" | grep -v '^[[:space:]]*$' | tail -n1 || true)"
  { [ "$first" = "$want" ] && [ "$last" = "$want" ]; } || r_rem="$r_rem $base"

  { grep -q '^## Hard rules$' "$f" && grep -q '^## Return$' "$f"; } || r_sect="$r_sect $base"

  # A role spawned by cron or a headless one-shot has no lead to ask and no
  # reader but a script: it needs the unattended rule, and its Return has to
  # open with a Status line a wrapper can grep.
  { grep -q '^- \*\*Unattended runs\*\*' "$f" \
    && [ "$(awk '/^## Return$/{r=1;next} r&&/^- /{print;exit}' "$f" | cut -c1-12)" = '- **Status**' ]; } \
    || r_unatt="$r_unatt $base"

  # A read-only role is a reporting role, and a reporting role with no stated
  # floor reports everything it notices.
  if [ "$sb" = "read-only" ]; then
    { grep -q '^## Do not report$' "$f" && grep -qi 'confidence floor' "$f"; } || r_floor="$r_floor $base"
  fi
done

[ "$n_roles" -gt 0 ] && ok "roles/ holds canonical role definitions ($n_roles)" \
                     || bad "roles/ holds canonical role definitions (found none)"
[ -z "$r_fm" ]      && ok "every role declares name/description/tools/effort/reminder" \
                     || bad "role frontmatter keys missing:$r_fm"
[ -z "$r_name" ]    && ok "every role's name matches its filename" \
                     || bad "role name disagrees with filename:$r_name"
[ -z "$r_tools" ]   && ok "every declared tool is a known tool name" \
                     || bad "unknown tool in role frontmatter:$r_tools"
[ -z "$r_sandbox" ] && ok "every declared sandbox value is in-enum" \
                     || bad "unknown sandbox value:$r_sandbox"
[ -z "$r_body" ]    && ok "no role ships an empty body" \
                     || bad "role body is empty:$r_body"
[ -z "$r_rem" ]     && ok "every role body opens and closes with its reminder" \
                     || bad "reminder drifted from the body:$r_rem"
[ -z "$r_sect" ]    && ok "every role states Hard rules and a Return contract" \
                     || bad "role missing Hard rules or Return:$r_sect"
[ -z "$r_unatt" ]   && ok "every role handles unattended runs and its Return opens with Status" \
                     || bad "role missing Unattended runs rule or a leading Status:$r_unatt"
[ -z "$r_floor" ]   && ok "every read-only role states what not to report and a confidence floor" \
                     || bad "read-only role missing Do not report / confidence floor:$r_floor"

# The render must FAIL on a drifted or missing reminder rather than shipping a
# Codex dialect whose instructions disagree with the Claude one.
RTMP="$(mktemp -d)"
mkdir -p "$RTMP/roles"
cp "$DIR"/roles/*.md "$RTMP/roles/"
cp "$DIR/render-roles.sh" "$RTMP/"
bash "$RTMP/render-roles.sh" >/dev/null 2>&1 \
  && ok "render-roles renders the unmodified sources" \
  || bad "render-roles renders the unmodified sources"
sed -i.bak '1,/^\*\*Reminder:\*\*/s/^\*\*Reminder:\*\*/**Reminder:** drifted/' "$RTMP/roles/refuter.md"
bash "$RTMP/render-roles.sh" >/dev/null 2>&1 \
  && bad "render-roles fails loudly when the reminder and the body drift apart" \
  || ok "render-roles fails loudly when the reminder and the body drift apart"
cp "$DIR/roles/refuter.md" "$RTMP/roles/refuter.md"
sed -i.bak '/^reminder:/d' "$RTMP/roles/refuter.md"
bash "$RTMP/render-roles.sh" >/dev/null 2>&1 \
  && bad "render-roles fails loudly when a role has no reminder" \
  || ok "render-roles fails loudly when a role has no reminder"
cp "$DIR/roles/refuter.md" "$RTMP/roles/refuter.md"

# Ports: read-only must survive into each tool's own switch, and an unmapped
# Antigravity tool must fail the render — its docs warn a bad name hangs agy.
bash "$RTMP/render-roles.sh" >/dev/null 2>&1
p_ro=""; p_agy=""
for f in "$DIR"/roles/*.md; do
  base="$(basename "$f" .md)"; [ "$base" = README ] && continue
  if [ "$(role_fm "$f" sandbox)" = read-only ]; then
    grep -qx 'readonly: true' "$RTMP/roles/cursor/$base.md" 2>/dev/null || p_ro="$p_ro $base"
    grep -qE '^  - (write_to_file|replace_file_content|multi_replace_file_content)$' "$RTMP/roles/antigravity/$base.md" && p_agy="$p_agy $base"
  else
    grep -qx 'readonly: true' "$RTMP/roles/cursor/$base.md" 2>/dev/null && p_ro="$p_ro $base(writer)"
  fi
done
[ -z "$p_ro" ]  && ok "Cursor port marks exactly the read-only roles readonly" \
                || bad "Cursor readonly flag wrong for:$p_ro"
[ -z "$p_agy" ] && ok "Antigravity port gives read-only roles no write tools" \
                || bad "Antigravity read-only role has a write tool:$p_agy"
sed -i.bak 's/^tools: Read,/tools: Read, Bogus,/' "$RTMP/roles/refuter.md"
bash "$RTMP/render-roles.sh" >/dev/null 2>&1 \
  && bad "render-roles fails on a tool with no Antigravity mapping" \
  || ok "render-roles fails on a tool with no Antigravity mapping"
rm -rf "$RTMP"

# ---- design-team layer: the manager role and the six design skills ---------
echo ""
echo "== design-team layer =="
[ -f "$DIR/roles/design-manager.md" ] \
  && ok "the design-manager role ships in roles/" \
  || bad "the design-manager role ships in roles/"
grep -q '^| `design-manager` |' "$DIR/playbooks/agent-teams.md" \
  && ok "the agent-teams playbook routes to design-manager" \
  || bad "the agent-teams playbook routes to design-manager"
# The playbook states how many roles ship; it has to track roles/*.md.
n_role_files="$(find "$DIR/roles" -maxdepth 1 -name '*.md' ! -name README.md | wc -l | tr -d ' ')"
n_role_rows="$(grep -cE '^\| `[a-z-]+` \| .* \| (yes|no|documents only|tests only) \|$' "$DIR/playbooks/agent-teams.md")"
[ "$n_role_files" = "$n_role_rows" ] \
  && ok "the playbook role table has one row per role ($n_role_files)" \
  || bad "the playbook role table has one row per role (files=$n_role_files rows=$n_role_rows)"
grep -qF 'All eleven in the table above ship by default' "$DIR/playbooks/agent-teams.md" \
  && [ "$n_role_files" = 11 ] \
  && ok "the playbook's role count matches roles/ (eleven)" \
  || bad "the playbook's role count matches roles/ (says eleven, found $n_role_files)"

# The six skills are portable (one dialect for every tool) and CORE: they live
# in skills/, which installs for everyone, and never in the design group that
# INC_DESIGN can switch off.
DESIGN_TEAM_SKILLS="critique figma-parity handoff research-synthesis one-on-one team-digest"
ds_bad=""
for sn in $DESIGN_TEAM_SKILLS; do
  sf="$DIR/skills/$sn/SKILL.md"
  [ -f "$sf" ] || { ds_bad="$ds_bad $sn:missing"; continue; }
  fm_keys="$(awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f&&/^[A-Za-z_-]+:/{sub(/:.*/,"");print}' "$sf" | sort | tr '\n' ' ')"
  [ "$fm_keys" = "description name " ] || ds_bad="$ds_bad $sn:frontmatter($fm_keys)"
  [ "$(sed -n 2p "$sf")" = "name: $sn" ] || ds_bad="$ds_bad $sn:name"
  grep -qF '!`' "$sf"          && ds_bad="$ds_bad $sn:injection"
  grep -qF '$ARGUMENTS' "$sf"  && ds_bad="$ds_bad $sn:ARGUMENTS"
  grep -q 'allowed-tools' "$sf" && ds_bad="$ds_bad $sn:allowed-tools"
done
[ -z "$ds_bad" ] && ok "the six design-team skills exist in the portable dialect (name + description only)" \
                 || bad "design-team skill format:$ds_bad"
ds_group="$(sed -n 's/^DESIGN_SKILLS="\(.*\)"$/\1/p' "$DIR/install-skills.sh")"
ds_gated=""
for sn in $DESIGN_TEAM_SKILLS; do
  case " $ds_group " in *" $sn "*) ds_gated="$ds_gated $sn";; esac
  [ -e "$DIR/.agents/skills/$sn" ] && ds_gated="$ds_gated $sn(vendored)"
done
{ [ -n "$ds_group" ] && [ -z "$ds_gated" ]; } \
  && ok "the design-team skills are core, not behind the design group" \
  || bad "design-team skills gated behind INC_DESIGN:${ds_gated:- (no DESIGN_SKILLS line found)}"
unset n_role_files n_role_rows DESIGN_TEAM_SKILLS ds_bad sn sf fm_keys ds_group ds_gated


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
  # Every SessionEnd hook must declare a timeout. Claude Code aborts the whole
  # SessionEnd batch after max(1500ms, largest declared timeout), and an abort
  # is user-visible ("Hook cancelled") — undeclared means a 1.5s shutdown race.
  se_total="$(jq '[.hooks.SessionEnd[].hooks[]] | length' "$SMOKE/.claude/settings.json" 2>/dev/null)"
  se_timed="$(jq '[.hooks.SessionEnd[].hooks[] | select((.timeout // 0) >= 5)] | length' "$SMOKE/.claude/settings.json" 2>/dev/null)"
  { [ -n "$se_total" ] && [ "$se_total" -gt 0 ] && [ "$se_total" = "$se_timed" ]; } \
    && ok "claude SessionEnd hooks declare a timeout (no 1.5s shutdown race)" \
    || bad "claude SessionEnd hooks declare a timeout (total=$se_total timed=$se_timed)"
  if HOME="$SMOKE" bash "$DIR/install-skills.sh" >/dev/null 2>&1 \
     && [ -L "$SMOKE/.claude/skills/ship" ]; then
    ok "install-skills links the skills"
  else
    bad "install-skills links the skills"
  fi

  # ---- team roles: one canonical definition per role, rendered to both tools.
  # Codex CANNOT improvise a role — an unknown agent name silently falls back to
  # its generic built-in — so the .toml files existing and parsing is the whole
  # point of this layer, not a nicety. Own throwaway HOME: this block runs a full
  # uninstall, which would strip $SMOKE's hooks/commands out from under the
  # assertions that follow.
  ROLESH="$(mktemp -d)"
  if HOME="$ROLESH" bash "$DIR/install-roles.sh" claude codex >/dev/null 2>&1 \
     && [ -f "$ROLESH/.claude/agents/refuter.md" ] \
     && [ -f "$ROLESH/.codex/agents/refuter.toml" ]; then
    ok "install-roles installs role files for claude and codex"
  else
    bad "install-roles installs role files for claude and codex"
  fi
  # Every canonical role reaches BOTH tools — a role that renders for one and
  # not the other is exactly the drift the single source is meant to prevent.
  n_src="$(find "$DIR/roles" -maxdepth 1 -name '*.md' ! -name 'README.md' | wc -l | tr -d ' ')"
  n_cl="$(find "$ROLESH/.claude/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  n_cx="$(find "$ROLESH/.codex/agents" -name '*.toml' 2>/dev/null | wc -l | tr -d ' ')"
  { [ "$n_src" -gt 0 ] && [ "$n_src" = "$n_cl" ] && [ "$n_src" = "$n_cx" ]; } \
    && ok "every canonical role renders to both dialects ($n_src)" \
    || bad "every canonical role renders to both dialects (src=$n_src claude=$n_cl codex=$n_cx)"
  # The Codex port must be parseable TOML carrying the three required keys.
  if command -v python3 >/dev/null 2>&1; then
    if python3 - "$ROLESH/.codex/agents" <<'PYEOF' >/dev/null 2>&1
import sys, glob, tomllib
bad = 0
for f in glob.glob(sys.argv[1] + "/*.toml"):
    with open(f, "rb") as fh:
        d = tomllib.load(fh)
    if not (d.get("name") and d.get("description") and d.get("developer_instructions", "").strip()):
        bad += 1
sys.exit(1 if bad else 0)
PYEOF
    then ok "codex role files are valid TOML with name/description/instructions"
    else bad "codex role files are valid TOML with name/description/instructions"
    fi
  fi
  # Re-running must not duplicate or churn, and uninstall must take them back out.
  HOME="$ROLESH" bash "$DIR/install-roles.sh" claude codex >/dev/null 2>&1
  n_cl2="$(find "$ROLESH/.claude/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$n_cl" = "$n_cl2" ] && ok "install-roles is idempotent" || bad "install-roles is idempotent"
  HOME="$ROLESH" bash "$DIR/uninstall.sh" claude codex >/dev/null 2>&1
  { [ ! -e "$ROLESH/.claude/agents/refuter.md" ] && [ ! -e "$ROLESH/.codex/agents/refuter.toml" ]; } \
    && ok "uninstall removes the installed role files" \
    || bad "uninstall removes the installed role files"
  rm -rf "$ROLESH"

  # A renamed command (validate -> improve) is pruned on reinstall so an old
  # machine doesn't keep /validate alongside /improve.
  mkdir -p "$SMOKE/.claude/commands"; printf 'stale\n' > "$SMOKE/.claude/commands/validate.md"
  HOME="$SMOKE" bash "$DIR/install-skills.sh" >/dev/null 2>&1
  [ ! -e "$SMOKE/.claude/commands/validate.md" ] \
    && [ -L "$SMOKE/.claude/skills/improve" ] \
    && ok "install-skills prunes retired command names" \
    || bad "install-skills prunes retired command names"

  # The permissions snippet is valid JSON with deny rules.
  if jq -e '.permissions.deny | length > 0' "$DIR/settings-permissions.snippet.json" >/dev/null 2>&1; then
    ok "settings-permissions.snippet.json is valid with deny rules"
  else
    bad "settings-permissions.snippet.json is valid with deny rules"
  fi

  # Agent teams: the instructions default to a team, so the installer turns the
  # construct on. Seed-only — an explicit value the user set is never overwritten
  # — and uninstall takes back only the "1" we wrote.
  TEAMSH="$(mktemp -d)"
  HOME="$TEAMSH" bash "$DIR/install-settings.sh" claude >/dev/null 2>&1
  [ "$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' "$TEAMSH/.claude/settings.json" 2>/dev/null)" = "1" ] \
    && ok "install-settings enables agent teams" || bad "install-settings enables agent teams"
  jq '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="0"' "$TEAMSH/.claude/settings.json" > "$TEAMSH/t" \
    && mv "$TEAMSH/t" "$TEAMSH/.claude/settings.json"
  HOME="$TEAMSH" bash "$DIR/install-settings.sh" claude >/dev/null 2>&1
  [ "$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' "$TEAMSH/.claude/settings.json" 2>/dev/null)" = "0" ] \
    && ok "install-settings respects an explicit agent-teams setting" \
    || bad "install-settings respects an explicit agent-teams setting"
  HOME="$TEAMSH" bash "$DIR/uninstall.sh" claude >/dev/null 2>&1
  [ "$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' "$TEAMSH/.claude/settings.json" 2>/dev/null)" = "0" ] \
    && ok "uninstall keeps an agent-teams value it did not write" \
    || bad "uninstall keeps an agent-teams value it did not write"
  rm -rf "$TEAMSH"; TEAMSH="$(mktemp -d)"
  HOME="$TEAMSH" bash "$DIR/install-settings.sh" claude >/dev/null 2>&1
  HOME="$TEAMSH" bash "$DIR/uninstall.sh" claude >/dev/null 2>&1
  [ -z "$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS // empty' "$TEAMSH/.claude/settings.json" 2>/dev/null)" ] \
    && ok "uninstall removes the agent-teams flag it wrote" \
    || bad "uninstall removes the agent-teams flag it wrote"
  rm -rf "$TEAMSH"

  # Advisor: seeded to opus so a sub-T1 lead can escalate; same seed-only rules.
  ADVH="$(mktemp -d)"
  HOME="$ADVH" bash "$DIR/install-settings.sh" claude >/dev/null 2>&1
  [ "$(jq -r '.advisorModel' "$ADVH/.claude/settings.json" 2>/dev/null)" = "opus" ] \
    && ok "install-settings seeds the advisor model" || bad "install-settings seeds the advisor model"
  HOME="$ADVH" bash "$DIR/uninstall.sh" claude >/dev/null 2>&1
  [ -z "$(jq -r '.advisorModel // empty' "$ADVH/.claude/settings.json" 2>/dev/null)" ] \
    && ok "uninstall removes the advisor model it wrote" \
    || bad "uninstall removes the advisor model it wrote"
  echo '{"advisorModel":"fable"}' > "$ADVH/.claude/settings.json"
  HOME="$ADVH" bash "$DIR/install-settings.sh" claude >/dev/null 2>&1
  HOME="$ADVH" bash "$DIR/uninstall.sh" claude >/dev/null 2>&1
  [ "$(jq -r '.advisorModel' "$ADVH/.claude/settings.json" 2>/dev/null)" = "fable" ] \
    && ok "install and uninstall keep an advisor model the user set" \
    || bad "install and uninstall keep an advisor model the user set"
  rm -rf "$ADVH"


  # install-settings merges the Claude-only permissions layer, idempotently.
  if HOME="$SMOKE" bash "$DIR/install-settings.sh" >/dev/null 2>&1 \
     && jq -e '.permissions.deny | index("Read(**/.env)")' "$SMOKE/.claude/settings.json" >/dev/null 2>&1; then
    ok "install-settings merges the permissions deny layer"
  else
    bad "install-settings merges the permissions deny layer"
  fi

  # Only Read(...)/Edit(...) file rules ship: Claude Code parses Write/NotebookEdit/
  # Glob path rules but never matches them, and warns about each at startup.
  # Edit(...) already covers Edit + Write + NotebookEdit.
  if jq -e '[.permissions[]?[]? | select(test("^(Write|NotebookEdit|Glob)\\("))] | length == 0' \
       "$DIR/settings-permissions.snippet.json" >/dev/null 2>&1; then
    ok "claude snippet has no dead Write/NotebookEdit/Glob permission rules"
  else
    bad "claude snippet has no dead Write/NotebookEdit/Glob permission rules"
  fi

  # Bare filenames match at any depth, so a ./x rule paired with a **/x one is a dupe.
  if jq -e '[.permissions[]?[]? | select(test("\\(\\./"))] | length == 0' \
       "$DIR/settings-permissions.snippet.json" >/dev/null 2>&1; then
    ok "claude snippet has no redundant ./ + **/ rule pairs"
  else
    bad "claude snippet has no redundant ./ + **/ rule pairs"
  fi

  # Retired rules are pruned from an existing settings.json, not left orphaned.
  rm -f "$SMOKE/.ai/install-state/settings.tsv"   # pre-ledger: orphans of an old install (R13)
  jq '.permissions.deny += ["Write(**/build/**)","Read(./.env)"]' \
     "$SMOKE/.claude/settings.json" > "$SMOKE/.claude/settings.json.t" \
    && mv "$SMOKE/.claude/settings.json.t" "$SMOKE/.claude/settings.json"
  HOME="$SMOKE" bash "$DIR/install-settings.sh" claude >/dev/null 2>&1
  if jq -e '[.permissions.deny[] | select(. == "Write(**/build/**)" or . == "Read(./.env)")] | length == 0' \
       "$SMOKE/.claude/settings.json" >/dev/null 2>&1; then
    ok "install-settings prunes retired permission rules from an existing file"
  else
    bad "install-settings prunes retired permission rules from an existing file"
  fi
  p1="$(jq '.permissions.deny | length' "$SMOKE/.claude/settings.json" 2>/dev/null)"
  HOME="$SMOKE" bash "$DIR/install-settings.sh" >/dev/null 2>&1
  p2="$(jq '.permissions.deny | length' "$SMOKE/.claude/settings.json" 2>/dev/null)"
  [ -n "$p1" ] && [ "$p1" = "$p2" ] && ok "install-settings is idempotent (no duplication)" \
                                    || bad "install-settings is idempotent (no duplication)"

  # Settings provenance (lib/settings-ledger.sh, PLAN §9 G4, §16 A3, §15 R13):
  # install-state/settings.tsv records each permission rule we added, so a
  # rule the user deleted stays out, a user's own copy of a retired rule
  # survives, and uninstall removes only ours. Every case uses a throwaway HOME,
  # so the ledger lives at $H/.ai/install-state/settings.tsv.
  slrow() {  # $1 = HOME  $2 = settings file  $3 = key  $4 = value  → prints the status, or nothing
    awk -F'\t' -v f="$2" -v k="$3" -v v="$4" '$1 == f && $2 == k && $3 == v { print $4 }' \
      "$1/.ai/install-state/settings.tsv" 2>/dev/null
  }
  slbaks() { set -- "$1".bak.*; if [ -e "$1" ]; then echo "$#"; else echo 0; fi; }
  slset() {  # $1 = settings file  $2 = jq program — edit it the way a person would
    jq "$2" "$1" > "$1.t" && mv "$1.t" "$1"
  }
  # A copy of the installer whose Claude snippet ships one extra rule, standing
  # in for a future upstream release.
  SLNEXT="$(mktemp -d)"
  cp "$DIR"/install-settings.sh "$DIR"/*.snippet.json "$DIR"/*.snippet.toml "$SLNEXT"/
  cp -R "$DIR/lib" "$SLNEXT/lib"
  slset "$SLNEXT/settings-permissions.snippet.json" '.permissions.ask += ["Bash(fakenew:*)"]'

  # Fresh install: every shipped rule is recorded as added.
  SLH="$(mktemp -d)"; SLF="$SLH/.claude/settings.json"
  HOME="$SLH" bash "$DIR/install-settings.sh" claude >/dev/null 2>&1
  sl_n="$(jq '[.permissions[] | length] | add' "$DIR/settings-permissions.snippet.json")"
  sl_got="$(awk -F'\t' -v f="$SLF" '$1 == f && $4 == "added"' "$SLH/.ai/install-state/settings.tsv" 2>/dev/null | wc -l | tr -d ' ')"
  [ -n "$sl_n" ] && [ "$sl_got" = "$sl_n" ] && [ "$(slrow "$SLH" "$SLF" deny 'Edit(**/dist/**)')" = added ] \
    && ok "settings ledger records every rule a fresh install adds" \
    || bad "settings ledger records every rule a fresh install adds (want $sl_n rows, got $sl_got)"

  # Idempotence: a second run changes neither file and makes no backup.
  sl_a="$(cksum < "$SLF")$(cksum < "$SLH/.ai/install-state/settings.tsv")"
  sl_baks="$(slbaks "$SLF")"
  HOME="$SLH" bash "$DIR/install-settings.sh" claude >/dev/null 2>&1
  [ "$sl_a" = "$(cksum < "$SLF")$(cksum < "$SLH/.ai/install-state/settings.tsv")" ] \
    && [ "$sl_baks" = "$(slbaks "$SLF")" ] \
    && ok "settings ledger: a second run changes no file" \
    || bad "settings ledger: a second run changes no file"

  # A3: a rule we added that the user deleted is marked declined and stays out,
  # on this run and every later one.
  slset "$SLF" '.permissions.deny -= ["Edit(**/dist/**)"]'
  sl_out="$(HOME="$SLH" bash "$DIR/install-settings.sh" claude 2>&1)"
  HOME="$SLH" bash "$DIR/install-settings.sh" claude >/dev/null 2>&1
  if ! jq -e '.permissions.deny | index("Edit(**/dist/**)")' "$SLF" >/dev/null 2>&1 \
     && [ "$(slrow "$SLH" "$SLF" deny 'Edit(**/dist/**)')" = declined ] \
     && printf '%s' "$sl_out" | grep -q 'you removed stay out'; then
    ok "install-settings never re-adds a rule the user deleted (declined)"
  else
    bad "install-settings never re-adds a rule the user deleted (declined)"
  fi

  # G4: once the file has rows, the user's own copy of a retired rule survives
  # the retired-rule subtraction, and is never recorded as ours.
  slset "$SLF" '.permissions.deny += ["Write(**/build/**)"]'
  HOME="$SLH" bash "$DIR/install-settings.sh" claude >/dev/null 2>&1
  jq -e '.permissions.deny | index("Write(**/build/**)")' "$SLF" >/dev/null 2>&1 \
    && [ -z "$(slrow "$SLH" "$SLF" deny 'Write(**/build/**)')" ] \
    && ok "install-settings keeps a user's own copy of a retired rule" \
    || bad "install-settings keeps a user's own copy of a retired rule"

  # ...while a retired rule we recorded as added is still removed, row and all.
  slset "$SLF" '.permissions.deny += ["Write(**/dist/**)"]'
  printf '%s\tdeny\tWrite(**/dist/**)\tadded\t2026-01-01T00:00:00Z\n' "$SLF" >> "$SLH/.ai/install-state/settings.tsv"
  HOME="$SLH" bash "$DIR/install-settings.sh" claude >/dev/null 2>&1
  ! jq -e '.permissions.deny | index("Write(**/dist/**)")' "$SLF" >/dev/null 2>&1 \
    && [ -z "$(slrow "$SLH" "$SLF" deny 'Write(**/dist/**)')" ] \
    && ok "install-settings removes a retired rule it added, and forgets it" \
    || bad "install-settings removes a retired rule it added, and forgets it"

  # A new upstream rule is still added (and recorded) on a file with rows; a
  # declined one stays out under the new release too.
  HOME="$SLH" bash "$SLNEXT/install-settings.sh" claude >/dev/null 2>&1
  jq -e '.permissions.ask | index("Bash(fakenew:*)")' "$SLF" >/dev/null 2>&1 \
    && [ "$(slrow "$SLH" "$SLF" ask 'Bash(fakenew:*)')" = added ] \
    && ! jq -e '.permissions.deny | index("Edit(**/dist/**)")' "$SLF" >/dev/null 2>&1 \
    && ok "install-settings still adds a new upstream rule" \
    || bad "install-settings still adds a new upstream rule"

  # Deleting the whole settings file starts it over: every rule comes back.
  rm -f "$SLF"
  HOME="$SLH" bash "$DIR/install-settings.sh" claude >/dev/null 2>&1
  jq -e '.permissions.deny | index("Edit(**/dist/**)")' "$SLF" >/dev/null 2>&1 \
    && [ "$(slrow "$SLH" "$SLF" deny 'Edit(**/dist/**)')" = added ] \
    && ok "a deleted settings file is reinstalled whole (stale declined rows dropped)" \
    || bad "a deleted settings file is reinstalled whole (stale declined rows dropped)"
  rm -rf "$SLH"

  # R13: a pre-ledger file (no rows) adopts the shipped rules already in it as
  # ours, keeps the user's unrelated rule unrecorded, and still prunes retired
  # rules the old way.
  SLH="$(mktemp -d)"; SLF="$SLH/.claude/settings.json"; mkdir -p "$SLH/.claude"
  printf '%s\n' '{"permissions":{"deny":["Read(**/.env)","Read(./.env)"],"allow":["Bash(make:*)"]}}' > "$SLF"
  HOME="$SLH" bash "$DIR/install-settings.sh" claude >/dev/null 2>&1
  [ "$(slrow "$SLH" "$SLF" deny 'Read(**/.env)')" = added ] \
    && [ -z "$(slrow "$SLH" "$SLF" allow 'Bash(make:*)')" ] \
    && jq -e '.permissions.allow | index("Bash(make:*)")' "$SLF" >/dev/null 2>&1 \
    && ! jq -e '.permissions.deny | index("Read(./.env)")' "$SLF" >/dev/null 2>&1 \
    && ok "settings ledger adopts shipped rules on a pre-ledger file (R13)" \
    || bad "settings ledger adopts shipped rules on a pre-ledger file (R13)"
  rm -rf "$SLH"

  # sl_strip_perms (uninstall): removes only rules recorded as added. The user's
  # own rule, and their own copy of a rule that shipped later, both stay; a
  # declined row survives for the next install.
  SLH="$(mktemp -d)"; SLF="$SLH/.claude/settings.json"
  HOME="$SLH" bash "$DIR/install-settings.sh" claude >/dev/null 2>&1
  slset "$SLF" '.permissions.allow += ["Bash(make:*)"] | .permissions.ask += ["Bash(fakenew:*)"] | .permissions.deny -= ["Edit(**/dist/**)"]'
  HOME="$SLH" bash "$SLNEXT/install-settings.sh" claude >/dev/null 2>&1
  # shellcheck disable=SC2030,SC2031
  ( export HOME="$SLH"; unset AIGI_STATE_DIR
    # shellcheck source=lib/settings-ledger.sh
    . "$DIR/lib/settings-ledger.sh" && sl_strip_perms "$SLF" "$SLNEXT/settings-permissions.snippet.json" ) >/dev/null 2>&1
  jq -e '.permissions.allow == ["Bash(make:*)"] and .permissions.ask == ["Bash(fakenew:*)"] and (.permissions.deny == null)' \
       "$SLF" >/dev/null 2>&1 \
    && [ -z "$(slrow "$SLH" "$SLF" ask 'Bash(sudo:*)')" ] \
    && [ "$(slrow "$SLH" "$SLF" deny 'Edit(**/dist/**)')" = declined ] \
    && ok "sl_strip_perms removes only the rules we added" \
    || bad "sl_strip_perms removes only the rules we added"
  rm -rf "$SLH"

  # sl_strip_perms on a pre-ledger file falls back to subtracting the snippet.
  SLH="$(mktemp -d)"; SLF="$SLH/.claude/settings.json"; mkdir -p "$SLH/.claude"
  printf '%s\n' '{"permissions":{"deny":["Read(**/.env)"],"allow":["Bash(make:*)","Bash(lm:*)"]}}' > "$SLF"
  # shellcheck disable=SC2030,SC2031
  ( export HOME="$SLH"; unset AIGI_STATE_DIR
    # shellcheck source=lib/settings-ledger.sh
    . "$DIR/lib/settings-ledger.sh" && sl_strip_perms "$SLF" "$DIR/settings-permissions.snippet.json" ) >/dev/null 2>&1
  jq -e '.permissions == {"allow":["Bash(make:*)"]}' "$SLF" >/dev/null 2>&1 \
    && ok "sl_strip_perms subtracts the snippet from a pre-ledger file" \
    || bad "sl_strip_perms subtracts the snippet from a pre-ledger file"
  rm -rf "$SLH" "$SLNEXT"

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

  # Codex takes Claude's SessionStart wire shape; antigravity has no such event.
  lm_cx="$(printf '{"cwd":"%s","source":"startup"}' "$MEMPROJ" | HOOK_PLATFORM=codex bash "$DIR/hooks/load-memory.sh" 2>/dev/null)"
  lm_ag="$(printf '{"cwd":"%s","source":"startup"}' "$MEMPROJ" | HOOK_PLATFORM=antigravity bash "$DIR/hooks/load-memory.sh" 2>/dev/null)"
  { printf '%s' "$lm_cx" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | length > 0)' >/dev/null 2>&1 \
      && [ -z "$lm_ag" ]; } \
    && ok "load-memory emits codex SessionStart context, silent for antigravity" \
    || bad "load-memory emits codex SessionStart context, silent for antigravity"
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

  # The session rating survey was removed (22 of 23 dismissed over six weeks).
  # Assert it stays removed: nothing may wire a survey hook back in.
  if grep -q "scorecard" "$SMOKE/.claude/settings.json" 2>/dev/null; then
    bad "install-hooks wires no session-survey hook"
  else
    ok "install-hooks wires no session-survey hook"
  fi

  # setup-memory-os --yes writes the registry (markdown fallback in a bare HOME).
  HOME="$SMOKE" bash "$DIR/setup-memory-os.sh" --yes >/dev/null 2>&1
  grep -q '^MEMORYOS_TYPE=markdown' "$SMOKE/.ai/memory-os" 2>/dev/null \
    && ok "setup-memory-os writes a markdown registry when nothing is detected" \
    || bad "setup-memory-os writes a markdown registry when nothing is detected"

  # The memoryOS lesson store outlived the survey that used to write it — lessons
  # now come from corrections made in-session. The store's read contract is
  # unchanged, so seed it directly and assert load-memory still closes the loop.
  SC="$(mktemp -d)"; SCCFG="$SC/memcfg"; SCMEM="$SC/mem"; mkdir -p "$SCMEM"
  printf 'MEMORYOS_TYPE=markdown\nMEMORYOS_PATH=%s\n' "$SCMEM" > "$SCCFG"
  printf '# Session lessons\n\n- 2026-01-01 — always bind 0.0.0.0\n' > "$SCMEM/LESSONS.md"

  # load-memory closes the loop: recorded lessons are injected next session.
  LMPROJ="$(mktemp -d)"
  lm_lessons="$(printf '{"cwd":"%s","source":"startup"}' "$LMPROJ" | HOME="$LMPROJ" AI_MEMORYOS_CONFIG="$SCCFG" HOOK_PLATFORM=claude bash "$DIR/hooks/load-memory.sh" 2>/dev/null)"
  printf '%s' "$lm_lessons" | jq -e '.hookSpecificOutput.additionalContext | test("always bind 0.0.0.0")' >/dev/null 2>&1 \
    && ok "load-memory injects recent session lessons at SessionStart" \
    || bad "load-memory injects recent session lessons at SessionStart"
  rm -rf "$SC" "$LMPROJ"

  # Two advisories replace the three blocking Stop hooks: the quality nudge and
  # the worktree reaper. Neither may block, and none of the retired ones return.
  if jq -e '[.hooks.Stop[].hooks[].command] as $c
            | ($c|length)==2 and ($c[0]|test("quality-nudge")) and ($c[1]|test("worktree-reap"))
              and ([$c[]|select(test("verify-nudge|improve-nudge|changelog-nudge"))]|length)==0' \
      "$SMOKE/.claude/settings.json" >/dev/null 2>&1; then
    ok "install-hooks wires Stop to the two advisories (quality + worktree-reap)"
  else
    bad "install-hooks wires Stop to the two advisories (quality + worktree-reap)"
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
     && [ ! -e "$SMOKE/.claude/skills/ship" ]; then
    ok "uninstall strips hooks, permissions, and skill links"
  else
    bad "uninstall strips hooks, permissions, and skill links"
  fi
  rm -rf "$SMOKE"

  # install.sh orchestrates every layer into a throwaway HOME — and forwards
  # --no-design to install-skills.sh (the empty-array idiom on bash 3.2), so
  # core skills land while the design group stays out.
  SMOKE2="$(mktemp -d)"
  # Pre-seed a legacy roster so the install proves it migrates it to ~/.ai/.
  mkdir -p "$SMOKE2/.ai-logs"; echo "stale" > "$SMOKE2/.ai-logs/ai-clis"
  if HOME="$SMOKE2" bash "$DIR/install.sh" --yes --no-design claude >/dev/null 2>&1 </dev/null \
     && jq -e '.permissions.deny and .hooks.SessionStart' "$SMOKE2/.claude/settings.json" >/dev/null 2>&1 \
     && [ -L "$SMOKE2/.claude/skills/ship" ] \
     && [ ! -e "$SMOKE2/.claude/skills/ux-audit" ] \
     && [ -f "$SMOKE2/AGENTS.md" ] \
     && [ ! -L "$SMOKE2/.claude/CLAUDE.md" ] && grep -qF '@~/AGENTS.md' "$SMOKE2/.claude/CLAUDE.md" \
     && [ -L "$SMOKE2/.codex/AGENTS.md" ] \
     && [ -f "$SMOKE2/.claude/CHANGELOG.md" ] \
     && [ -f "$SMOKE2/.claude/loop.md" ] \
     && [ -f "$SMOKE2/.ai/clis" ] && [ ! -e "$SMOKE2/.ai-logs/ai-clis" ] \
     && cmp -s "$DIR/MODEL-ROUTING.md" "$SMOKE2/.ai/model-routing.md"; then
    ok "install.sh orchestrates every layer and forwards --no-design"
  else
    bad "install.sh orchestrates every layer and forwards --no-design"
  fi

  # --global installs the on-demand playbooks next to the other ~/.ai files,
  # and a section toggled off removes its playbook instead of leaving it stale.
  if [ -f "$SMOKE2/.ai/orchestration.md" ] \
     && [ -f "$SMOKE2/.ai/quality-workflows.md" ] \
     && [ -f "$SMOKE2/.ai/web-preview.md" ] \
     && cmp -s "$DIR/playbooks/orchestration.md" "$SMOKE2/.ai/orchestration.md"; then
    ok "install.sh installs the on-demand playbooks to ~/.ai/"
  else
    bad "install.sh installs the on-demand playbooks to ~/.ai/"
  fi
  HOME="$SMOKE2" AIGI_NO_USER_ENV=1 INC_ORCHESTRATION=n bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
  { [ ! -e "$SMOKE2/.ai/orchestration.md" ] && [ -f "$SMOKE2/.ai/quality-workflows.md" ]; } \
    && ok "INC_ORCHESTRATION=n --global removes only the orchestration playbook" \
    || bad "INC_ORCHESTRATION=n --global removes only the orchestration playbook"
  HOME="$SMOKE2" AIGI_NO_USER_ENV=1 bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1

  # Model routing: a re-install refreshes the repo's stable method but keeps
  # this machine's generated block (written by /update-model-routing), and a
  # stale stable section on the machine is overwritten, not preserved.
  MR="$SMOKE2/.ai/model-routing.md"
  python3 - "$MR" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'(<!-- generated:begin[^\n]*\n).*?(<!-- generated:end)',
           r'\1MACHINE-DATA-SENTINEL\n\2', s, flags=re.S)
s = s.replace('## Tiers', '## Tiers STALE-STABLE-SENTINEL', 1)
open(p, 'w').write(s)
PY
  HOME="$SMOKE2" AIGI_NO_USER_ENV=1 bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
  { grep -qF 'MACHINE-DATA-SENTINEL' "$MR" \
    && ! grep -qF 'STALE-STABLE-SENTINEL' "$MR" \
    && ! grep -qF 'seed stub' "$MR" \
    && diff <(sed '/^<!-- generated:begin/,$d' "$DIR/MODEL-ROUTING.md") <(sed '/^<!-- generated:begin/,$d' "$MR") >/dev/null \
    && [ "$(grep -c '^<!-- generated:' "$MR")" = 2 ]; } \
    && ok "re-install refreshes model-routing's stable method and keeps the machine's generated data" \
    || bad "re-install refreshes model-routing's stable method and keeps the machine's generated data"

  # A marker quoted mid-line inside the generated block (an agent writing about
  # the format) must not end the block early.
  python3 - "$MR" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace('MACHINE-DATA-SENTINEL', 'MACHINE-DATA-SENTINEL\nsee `<!-- generated:end -->` above\nAFTER-QUOTED-MARKER', 1)
open(p, 'w').write(s)
PY
  HOME="$SMOKE2" AIGI_NO_USER_ENV=1 bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
  grep -qF 'AFTER-QUOTED-MARKER' "$MR" && [ "$(grep -c '^<!-- generated:' "$MR")" = 2 ] \
    && ok "model-routing splice ignores a marker quoted mid-line" \
    || bad "model-routing splice ignores a marker quoted mid-line"

  # A pre-marker copy (or a damaged block) is replaced by the seed stub, and the
  # old content is saved to the ledger's preserved/ rather than silently lost.
  printf '# old routing table\nLEGACY-ROUTING-DATA\n' > "$MR"
  HOME="$SMOKE2" AIGI_NO_USER_ENV=1 bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
  { cmp -s "$DIR/MODEL-ROUTING.md" "$MR" \
    && grep -lqF 'LEGACY-ROUTING-DATA' "$SMOKE2/.ai/install-state/preserved/"* 2>/dev/null; } \
    && ok "a pre-marker model-routing copy is backed up, then replaced by the seed" \
    || bad "a pre-marker model-routing copy is backed up, then replaced by the seed"

  # Claude pointer: hand additions below the @import survive a re-render;
  # the codex pointer stays a symlink.
  echo "- my claude-only note" >> "$SMOKE2/.claude/CLAUDE.md"
  HOME="$SMOKE2" AIGI_NO_USER_ENV=1 bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
  { grep -qF -- "- my claude-only note" "$SMOKE2/.claude/CLAUDE.md" \
    && grep -qF '@~/AGENTS.md' "$SMOKE2/.claude/CLAUDE.md" \
    && [ -L "$SMOKE2/.codex/AGENTS.md" ]; } \
    && ok "claude pointer preserves hand additions across re-renders" \
    || bad "claude pointer preserves hand additions across re-renders"

  # loop.md is seed-only: a tuned copy survives re-renders untouched.
  echo "- my tuned loop rule" >> "$SMOKE2/.claude/loop.md"
  HOME="$SMOKE2" AIGI_NO_USER_ENV=1 bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
  grep -qF -- "- my tuned loop rule" "$SMOKE2/.claude/loop.md" \
    && ok "loop.md seed never overwrites a tuned copy" \
    || bad "loop.md seed never overwrites a tuned copy"

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

  # ---- skills: one portable SKILL.md per workflow, read by every tool ----
  # The same file serves Claude Code, Codex and Cursor, so it must carry no
  # Claude-only dialect: an unrun !`cmd` or a literal $ARGUMENTS reaches the
  # other two tools as raw text.
  sk_ok=1; sk_bad=""; sk_n=0
  for sf in "$DIR"/skills/*/SKILL.md; do
    sn="$(basename "$(dirname "$sf")")"; sk_n=$((sk_n+1))
    sed -n 2p "$sf" | grep -qx "name: $sn"     || { sk_ok=0; sk_bad="$sk_bad $sn:name"; }
    grep -q '^description: ' "$sf"             || { sk_ok=0; sk_bad="$sk_bad $sn:description"; }
    grep -qF '!`' "$sf"                         && { sk_ok=0; sk_bad="$sk_bad $sn:injection"; }
    grep -qF '$ARGUMENTS' "$sf"                 && { sk_ok=0; sk_bad="$sk_bad $sn:ARGUMENTS"; }
    grep -q '^allowed-tools' "$sf"              && { sk_ok=0; sk_bad="$sk_bad $sn:allowed-tools"; }
  done
  { [ "$sk_ok" = 1 ] && [ "$sk_n" -gt 0 ]; } \
    && ok "every skill is portable: name matches dir, description, no Claude-only dialect ($sk_n)" \
    || bad "skill format:$sk_bad"
  [ ! -e "$DIR/commands" ] && [ ! -e "$DIR/render-commands.sh" ] \
    && ok "no command sources remain (skills are the only workflow surface)" \
    || bad "no command sources remain (commands/ or render-commands.sh is back)"

  # Every skill reaches every skill-capable tool, as a link to this checkout,
  # and the install is idempotent.
  SK="$(mktemp -d)"
  HOME="$SK" "$DIR/install-skills.sh" --no-design claude codex cursor >/dev/null 2>&1
  HOME="$SK" "$DIR/install-skills.sh" --no-design claude codex cursor >/dev/null 2>&1
  miss=""
  for sf in "$DIR"/skills/*/SKILL.md; do
    sn="$(basename "$(dirname "$sf")")"
    for t in claude codex cursor; do
      { [ -L "$SK/.$t/skills/$sn" ] && [ "$(readlink "$SK/.$t/skills/$sn")" = "$DIR/skills/$sn" ]; } \
        || miss="$miss $t/$sn"
    done
  done
  [ -z "$miss" ] && ok "every skill is linked into claude, codex and cursor" \
                 || bad "missing skill links:$miss"
  { [ ! -e "$SK/.claude/commands" ] && [ ! -e "$SK/.cursor/commands" ]; } \
    && ok "install-skills writes no command files" \
    || bad "install-skills writes no command files"
  rm -rf "$SK"

  # Migration: what earlier versions installed is cleared so no tool lists a
  # name twice — command files and their backups, copied Codex ports — while
  # the user's own command and a hand-made Codex skill survive.
  SK="$(mktemp -d)"
  mkdir -p "$SK/.claude/commands" "$SK/.cursor/commands" "$SK/.codex/skills/ship" "$SK/.codex/skills/tidy" "$SK/.codex/skills/mine"
  for d in claude cursor; do
    echo old > "$SK/.$d/commands/ship.md"; echo old > "$SK/.$d/commands/ship.md.bak.Ab12Cd"
    echo old > "$SK/.$d/commands/ux-audit.md"; echo mine > "$SK/.$d/commands/mycustom.md"
  done
  printf -- '---\nname: "ship"\n---\n\n<!-- GENERATED from commands/ship.md by render-commands.sh — do not edit. -->\n' > "$SK/.codex/skills/ship/SKILL.md"
  echo old > "$SK/.codex/skills/ship/SKILL.md.bak.Ab12Cd"
  printf -- '<!-- GENERATED from commands/tidy.md by render-commands.sh -->\n' > "$SK/.codex/skills/tidy/SKILL.md"
  echo MINE > "$SK/.codex/skills/mine/SKILL.md"
  HOME="$SK" "$DIR/install-skills.sh" --design claude codex cursor >/dev/null 2>&1
  mg_ok=1
  for d in claude cursor; do
    [ -e "$SK/.$d/commands/ship.md" ]          && mg_ok=0
    [ -e "$SK/.$d/commands/ship.md.bak.Ab12Cd" ] && mg_ok=0
    [ -e "$SK/.$d/commands/ux-audit.md" ]      && mg_ok=0
    [ -f "$SK/.$d/commands/mycustom.md" ]      || mg_ok=0
  done
  [ -L "$SK/.codex/skills/ship" ]              || mg_ok=0
  [ -e "$SK/.codex/skills/tidy" ]              && mg_ok=0
  grep -q MINE "$SK/.codex/skills/mine/SKILL.md" 2>/dev/null || mg_ok=0
  [ "$mg_ok" = 1 ] \
    && ok "migration clears legacy commands, backups and copied Codex ports; user files survive" \
    || bad "migration of legacy command installs"
  rm -rf "$SK"

  # ---- multi-tool: hooks, settings ----

  # ---- command groups: the design group is INC_DESIGN-gated at install time ----
  # Design is on by default for everyone; an explicit INC_DESIGN=n opts out.
  dg_def="$(AIGI_NO_USER_ENV=1 "$CUSTOMIZE" --design-group 2>/dev/null)"
  dg_off="$(AIGI_NO_USER_ENV=1 INC_DESIGN=n "$CUSTOMIZE" --design-group 2>/dev/null)"
  { [ "$dg_def" = y ] && [ "$dg_off" = n ]; } \
    && ok "customize --design-group defaults on, honors explicit INC_DESIGN=n" \
    || bad "customize --design-group (got default=$dg_def explicit-n=$dg_off)"

  # --autonomy resolves the posture the same way (env var outranks context files).
  au_def="$(AIGI_NO_USER_ENV=1 "$CUSTOMIZE" --autonomy 2>/dev/null)"
  au_bal="$(AIGI_NO_USER_ENV=1 AUTONOMY=balanced "$CUSTOMIZE" --autonomy 2>/dev/null)"
  { [ "$au_def" = aggressive ] && [ "$au_bal" = balanced ]; } \
    && ok "customize --autonomy resolves the posture (default aggressive, env wins)" \
    || bad "customize --autonomy (got default=$au_def balanced=$au_bal)"

  # autonomy-reminder wires on aggressive installs only (claude + codex +
  # cursor — every tool with SessionStart context injection), and a posture
  # flipped to balanced prunes an already-wired reminder on re-install.
  AR="$(mktemp -d)"
  HOME="$AR" AUTONOMY=aggressive bash "$DIR/install-hooks.sh" claude codex cursor >/dev/null 2>&1
  ar_cl="$(jq -r '[.hooks.SessionStart[].hooks[].command] | any(test("autonomy-reminder"))' "$AR/.claude/settings.json" 2>/dev/null)"
  ar_cx="$(jq -r '[.hooks.SessionStart[].hooks[].command] | any(test("autonomy-reminder"))' "$AR/.codex/hooks.json" 2>/dev/null)"
  ar_cu="$(jq -r '[.hooks.sessionStart[].command] | any(test("autonomy-reminder"))' "$AR/.cursor/hooks.json" 2>/dev/null)"
  HOME="$AR" AUTONOMY=balanced bash "$DIR/install-hooks.sh" claude codex cursor >/dev/null 2>&1
  ar_cl2="$(jq -r '[.hooks.SessionStart[].hooks[].command] | any(test("autonomy-reminder"))' "$AR/.claude/settings.json" 2>/dev/null)"
  ar_cx2="$(jq -r '[.hooks.SessionStart[]?.hooks[]?.command] | any(test("autonomy-reminder"))' "$AR/.codex/hooks.json" 2>/dev/null)"
  ar_cu2="$(jq -r '[.hooks.sessionStart[]?.command] | any(test("autonomy-reminder"))' "$AR/.cursor/hooks.json" 2>/dev/null)"
  { [ "$ar_cl" = true ] && [ "$ar_cx" = true ] && [ "$ar_cu" = true ] \
      && [ "$ar_cl2" = false ] && [ "$ar_cx2" = false ] && [ "$ar_cu2" = false ]; } \
    && ok "autonomy-reminder wires on aggressive, prunes on balanced (claude+codex+cursor)" \
    || bad "autonomy-reminder wiring (agg cl=$ar_cl cx=$ar_cx cu=$ar_cu / bal cl=$ar_cl2 cx=$ar_cx2 cu=$ar_cu2)"
  rm -rf "$AR"

  # The hook emits the right SessionStart shape per platform, silent elsewhere.
  arh_c="$(printf '{"source":"startup"}' | HOOK_PLATFORM=claude bash "$DIR/hooks/autonomy-reminder.sh" 2>/dev/null)"
  arh_u="$(printf '{}' | HOOK_PLATFORM=cursor bash "$DIR/hooks/autonomy-reminder.sh" 2>/dev/null)"
  arh_x="$(printf '{}' | HOOK_PLATFORM=codex bash "$DIR/hooks/autonomy-reminder.sh" 2>/dev/null)"
  arh_g="$(printf '{}' | HOOK_PLATFORM=antigravity bash "$DIR/hooks/autonomy-reminder.sh" 2>/dev/null)"
  if printf '%s' "$arh_c" | jq -e '.hookSpecificOutput.additionalContext | test("/loop") and test("/goal") and test("done-condition")' >/dev/null 2>&1 \
     && printf '%s' "$arh_x" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | test("/goal"))' >/dev/null 2>&1 \
     && printf '%s' "$arh_u" | jq -e '.additional_context | test("/loop") and test("/goal")' >/dev/null 2>&1 \
     && [ -z "$arh_g" ]; then
    ok "autonomy-reminder emits per-platform context and stays silent for antigravity"
  else
    bad "autonomy-reminder emits per-platform context and stays silent for antigravity"
  fi

  # A managed policy that restricts hooks makes the Claude wiring dead (and
  # /goal refuse to start); the installer says so, and stays quiet otherwise.
  PH="$(mktemp -d)"; PD="$(mktemp -d)"; mkdir -p "$PD/managed-settings.d"
  ph_quiet="$(HOME="$PH" AIGI_CLAUDE_POLICY_DIR="$PD" bash "$DIR/install-hooks.sh" claude 2>&1 >/dev/null)"
  printf '{"allowManagedHooksOnly":true}' > "$PD/managed-settings.d/40-hooks.json"
  ph_warn="$(HOME="$PH" AIGI_CLAUDE_POLICY_DIR="$PD" bash "$DIR/install-hooks.sh" claude 2>&1 >/dev/null)"
  { ! printf '%s' "$ph_quiet" | grep -q 'WARNING' && printf '%s' "$ph_warn" | grep -q 'allowManagedHooksOnly'; } \
    && ok "install-hooks warns when Claude Code policy restricts hooks" \
    || bad "install-hooks policy warning (quiet='$ph_quiet' warn='$ph_warn')"
  rm -rf "$PH" "$PD"

  # Explicit flags gate the design skill and prune it when turned off.
  count_design() {  # $1 = HOME root -> 1 if the claude design skill link is present
    [ -L "$1/.claude/skills/ux-audit" ] && printf 1 || printf 0
  }
  GT="$(mktemp -d)"; GS="$GT/.claude/skills"; CS="$GT/.cursor/skills"
  HOME="$GT" "$DIR/install-skills.sh" --no-design claude cursor >/dev/null 2>&1
  core_ok=1; [ -L "$GS/ship" ] || core_ok=0
  off_ok=1; if [ -e "$GS/ux-audit" ] || [ -e "$CS/ux-audit" ]; then off_ok=0; fi
  HOME="$GT" "$DIR/install-skills.sh" --design claude cursor >/dev/null 2>&1
  on_ok=1
  [ -L "$GS/ux-audit" ] && [ -f "$GS/ux-audit/SKILL.md" ] || on_ok=0
  [ -L "$CS/ux-audit" ] && [ -f "$CS/ux-audit/SKILL.md" ] || on_ok=0
  HOME="$GT" "$DIR/install-skills.sh" --no-design claude cursor >/dev/null 2>&1
  pr_ok=1; if [ -e "$GS/ux-audit" ] || [ -e "$CS/ux-audit" ]; then pr_ok=0; fi
  [ -L "$GS/ship" ] || pr_ok=0
  { [ "$core_ok" = 1 ] && [ "$off_ok" = 1 ] && [ "$on_ok" = 1 ] && [ "$pr_ok" = 1 ]; } \
    && ok "design group: skill link on claude/cursor, --no-design prunes it, core stays" \
    || bad "design group gating (core=$core_ok off=$off_ok on=$on_ok pruned=$pr_ok)"
  rm -rf "$GT"

  # The auto path end-to-end (the real-world default): no explicit flag — the
  # INC_DESIGN default resolves through customize.sh --design-group.
  GT="$(mktemp -d)"
  HOME="$GT" AIGI_NO_USER_ENV=1 "$DIR/install-skills.sh" claude >/dev/null 2>&1
  auto_def=$(count_design "$GT")
  HOME="$GT" AIGI_NO_USER_ENV=1 INC_DESIGN=n "$DIR/install-skills.sh" claude >/dev/null 2>&1
  auto_off=$(count_design "$GT")
  { [ "$auto_def" = 1 ] && [ "$auto_off" = 0 ]; } \
    && ok "design group auto path (default installs 1, INC_DESIGN=n prunes)" \
    || bad "design group auto path (default=$auto_def explicit-n=$auto_off)"
  rm -rf "$GT"

  # A resolver ERROR is not "off": when customize.sh fails on the auto path, an
  # already-installed design skill must be left in place (warn, don't prune).
  GT="$(mktemp -d)"
  cp -R "$DIR/skills" "$GT/skills"
  mkdir -p "$GT/.agents" && cp -R "$DIR/.agents/skills" "$GT/.agents/skills"
  cp "$DIR/install-skills.sh" "$GT/"; cp -R "$DIR/lib" "$GT/lib"
  printf '#!/bin/sh\nexit 1\n' > "$GT/customize.sh"; chmod +x "$GT/customize.sh"
  HOME="$GT/home" "$GT/install-skills.sh" --design claude >/dev/null 2>&1
  HOME="$GT/home" "$GT/install-skills.sh" claude >/dev/null 2>&1   # auto + broken resolver
  fail_kept=$(count_design "$GT/home")
  [ "$fail_kept" = 1 ] \
    && ok "design group survives a resolver failure (no silent prune on customize.sh error)" \
    || bad "resolver failure pruned the design skill link (kept=$fail_kept of 1)"
  rm -rf "$GT"

  # Data safety — each is a silent-data-loss regression if a refactor drops the
  # guard: (a) a user's own REAL skill dir at one of our names is never
  # clobbered; (b) a dangling link WE own is pruned while a foreign dangling link
  # is kept; (c) a foreign symlink at one of our names is neither replaced nor
  # written through.
  GT="$(mktemp -d)"; GS="$GT/.claude/skills"; DS="$GT/.codex/skills"
  mkdir -p "$GS/ux-audit" "$DS"
  echo "MINE" > "$GS/ux-audit/SKILL.md"
  ln -s "$DIR/skills/oldskill-gone" "$GS/oldskill-gone"           # dangling, ours
  ln -s /somewhere/else "$GS/foreign"                             # dangling, foreign
  ln -s /nonexistent/elsewhere "$DS/ship"                         # foreign, collides with a skill name
  HOME="$GT" "$DIR/install-skills.sh" --design claude codex >/dev/null 2>&1
  ds_ok=1
  { [ ! -L "$GS/ux-audit" ] && grep -q MINE "$GS/ux-audit/SKILL.md"; } || ds_ok=0
  [ -L "$GS/oldskill-gone" ] && ds_ok=0
  [ -L "$GS/foreign" ] || ds_ok=0
  { [ -L "$DS/ship" ] && [ "$(readlink "$DS/ship")" = /nonexistent/elsewhere ]; } || ds_ok=0
  [ "$ds_ok" = 1 ] \
    && ok "skill data safety: user dirs/foreign links untouched, our dangling links pruned" \
    || bad "skill data safety (user-dir=$([ -d "$GS/ux-audit" ] && [ ! -L "$GS/ux-audit" ] && echo kept || echo LOST) ours-dangling=$([ -L "$GS/oldskill-gone" ] && echo LEFT || echo pruned) foreign=$([ -L "$GS/foreign" ] && echo kept || echo LOST))"
  rm -rf "$GT"

  # Retired names (renamed/removed commands, e.g. the /audit -> /ux-audit rename)
  # prune on reinstall — saved to the ledger's preserved/ first, since a generic
  # name like "audit" could be the user's own command rather than our stale install.
  GT="$(mktemp -d)"; GC="$GT/.claude/commands"
  mkdir -p "$GC"
  echo "the user's own audit notes" > "$GC/audit.md"
  echo "stale critique" > "$GC/critique.md"
  HOME="$GT" "$DIR/install-skills.sh" --no-design claude >/dev/null 2>&1
  ret_ok=1
  if [ -f "$GC/audit.md" ] || [ -f "$GC/critique.md" ]; then ret_ok=0; fi
  grep -lq "the user's own audit notes" "$GT/.ai/install-state/preserved/"* 2>/dev/null || ret_ok=0
  [ "$ret_ok" = 1 ] \
    && ok "retired /audit + /critique prune with a backup of the prior copy" \
    || bad "retired prune (audit=$([ -f "$GC/audit.md" ] && echo present || echo gone) preserved=$(grep -lq "the user's own audit notes" "$GT/.ai/install-state/preserved/"* 2>/dev/null && echo yes || echo MISSING))"
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
  HOME="$MT" bash "$DIR/install-skills.sh" claude codex cursor >/dev/null 2>&1
  if [ -L "$MT/.codex/skills/ship" ] && [ -L "$MT/.cursor/skills/ship" ] \
     && [ -L "$MT/.codex/skills/ux-audit" ] && [ -f "$MT/.codex/skills/ux-audit/SKILL.md" ] \
     && [ -L "$MT/.cursor/skills/ux-audit" ] && [ -f "$MT/.cursor/skills/ux-audit/SKILL.md" ]; then
    ok "install-skills links codex/cursor skills (+ the design skill)"
  else
    bad "install-skills links codex/cursor skills (+ the design skill)"
  fi

  # Cursor hooks: top-level version:1, flat entries, idempotent through merge.
  HOME="$MT" bash "$DIR/install-hooks.sh" cursor >/dev/null 2>&1
  c1="$(jq '[.hooks[]|length]|add' "$MT/.cursor/hooks.json" 2>/dev/null)"
  HOME="$MT" bash "$DIR/install-hooks.sh" cursor >/dev/null 2>&1
  c2="$(jq '[.hooks[]|length]|add' "$MT/.cursor/hooks.json" 2>/dev/null)"
  if [ "$(jq '.version' "$MT/.cursor/hooks.json" 2>/dev/null)" = "1" ] \
     && [ -n "$c1" ] && [ "$c1" = "$c2" ] \
     && jq -e '[.hooks.stop[].command] | length==2 and (.[0]|test("quality-nudge")) and (.[1]|test("worktree-reap"))' "$MT/.cursor/hooks.json" >/dev/null 2>&1 \
     && jq -e '[.hooks.stop[].loop_limit] | all(. == 1)' "$MT/.cursor/hooks.json" >/dev/null 2>&1; then
    ok "install-hooks cursor is idempotent and wires both advisory stop hooks"
  else
    bad "install-hooks cursor is idempotent and wires both advisory stop hooks"
  fi

  # Codex hooks: file edits wired via the apply_patch matcher (path-guard + format).
  HOME="$MT" bash "$DIR/install-hooks.sh" codex >/dev/null 2>&1
  if jq -e '[.hooks.PreToolUse[].matcher]  | any(test("apply_patch"))' "$MT/.codex/hooks.json" >/dev/null 2>&1 \
     && jq -e '[.hooks.PostToolUse[].matcher] | any(test("apply_patch"))' "$MT/.codex/hooks.json" >/dev/null 2>&1 \
     && jq -e '[.hooks.Stop[].hooks[].command] | length==2 and (.[0]|test("quality-nudge")) and (.[1]|test("worktree-reap"))' "$MT/.codex/hooks.json" >/dev/null 2>&1; then
    ok "install-hooks codex wires edit guards and both Stop advisories"
  else
    bad "install-hooks codex wires edit guards and both Stop advisories"
  fi

  # Reinstall replaces only our nested handler, retaining mixed-group metadata
  # and independently managed handlers. This models managed metrics sharing a
  # Stop group with quality-nudge; neither foreign command is executed here.
  jq --arg hd "$MT/.codex/hooks" '
    .hooks.Stop[0] |= (
      .matcher = "mixed-stop" | .custom = {owner:"managed"}
      | .hooks += [{type:"command",command:"/tmp/managed-metrics.sh",timeout:10,async:false}]
    )
    | .hooks.PreToolUse += [{matcher:".*",custom:"foreign",hooks:[
        {type:"command",command:"/tmp/user-hook.sh",timeout:7,async:true},
        {type:"command",command:"/opt/foreign/log-tool.sh",timeout:9,async:false},
        {type:"command",command:("/opt/mirror" + $hd + "/log-tool.sh"),timeout:9,async:false},
        {type:"command",command:($hd + "/log-tool.sh-wrapper"),timeout:9,async:false}
      ]},
      {matcher:"empty-foreign",custom:"foreign",hooks:[]},
      {matcher:"null-foreign",custom:"foreign",hooks:null}
    ]
  ' "$MT/.codex/hooks.json" > "$MT/codex-mixed.json"
  mv "$MT/codex-mixed.json" "$MT/.codex/hooks.json"
  codex_foreign_before="$(jq -c '[.hooks.PreToolUse[] | select(.custom == "foreign")]' "$MT/.codex/hooks.json")"
  HOME="$MT" bash "$DIR/install-hooks.sh" codex >/dev/null 2>&1
  codex_mixed_count="$(jq '[.hooks[]|length]|add' "$MT/.codex/hooks.json")"
  HOME="$MT" bash "$DIR/install-hooks.sh" codex >/dev/null 2>&1
  codex_foreign_after="$(jq -c '[.hooks.PreToolUse[] | select(.custom == "foreign")]' "$MT/.codex/hooks.json")"
  if [ "$codex_foreign_before" = "$codex_foreign_after" ] \
     && [ "$codex_mixed_count" = "$(jq '[.hooks[]|length]|add' "$MT/.codex/hooks.json")" ] \
     && jq -e '
       ([.hooks.Stop[] | select(.matcher == "mixed-stop")] == [{
         matcher:"mixed-stop",custom:{owner:"managed"},hooks:[
           {type:"command",command:"/tmp/managed-metrics.sh",timeout:10,async:false}
         ]
       }])
       and ([.hooks.Stop[].hooks[].command | select(test("/quality-nudge\\.sh"))] | length == 1)
       and ([.hooks.Stop[].hooks[].command | select(test("/worktree-reap\\.sh"))] | length == 1)
     ' "$MT/.codex/hooks.json" >/dev/null 2>&1; then
    ok "install-hooks codex preserves mixed-group foreign handlers and metadata without duplicates"
  else
    bad "install-hooks codex preserves mixed-group foreign handlers and metadata without duplicates"
  fi
  if jq -e \
      --arg lg "env HOOK_PLATFORM=codex \"$MT/.codex/hooks/log-tool.sh\"" \
      --arg gp "env HOOK_PLATFORM=codex \"$MT/.codex/hooks/guard-paths.sh\"" \
      --arg gb "env HOOK_PLATFORM=codex \"$MT/.codex/hooks/guard-bash.sh\"" \
      --arg fm "env HOOK_PLATFORM=codex \"$MT/.codex/hooks/format-edited.sh\"" '
      [.hooks.PreToolUse[].hooks[]?,.hooks.PostToolUse[].hooks[]?]
      | ([.[] | select(.command == $lg)] | length == 2 and all(.async == true))
        and ([.[] | select(.command == $gp or .command == $gb or .command == $fm)]
             | length == 3 and all((.async // false) == false))
    ' "$MT/.codex/hooks.json" >/dev/null 2>&1; then
    ok "install-hooks codex backgrounds both audit loggers while guards and formatter stay synchronous"
  else
    bad "install-hooks codex backgrounds both audit loggers while guards and formatter stay synchronous"
  fi

  # Flat Cursor entries retain the entire foreign object, including platform
  # fields, while our owned entries remain idempotent through reinstall.
  jq '.hooks.stop += [{command:"/tmp/user-stop.sh",loop_limit:3,custom:"keep"}]' \
    "$MT/.cursor/hooks.json" > "$MT/cursor-foreign.json"
  mv "$MT/cursor-foreign.json" "$MT/.cursor/hooks.json"
  cursor_foreign_before="$(jq -c '[.hooks.stop[] | select(.custom == "keep")]' "$MT/.cursor/hooks.json")"
  HOME="$MT" bash "$DIR/install-hooks.sh" cursor >/dev/null 2>&1
  cursor_mixed_count="$(jq '[.hooks[]|length]|add' "$MT/.cursor/hooks.json")"
  HOME="$MT" bash "$DIR/install-hooks.sh" cursor >/dev/null 2>&1
  cursor_foreign_after="$(jq -c '[.hooks.stop[] | select(.custom == "keep")]' "$MT/.cursor/hooks.json")"
  if [ "$cursor_foreign_before" = "$cursor_foreign_after" ] \
     && [ "$cursor_mixed_count" = "$(jq '[.hooks[]|length]|add' "$MT/.cursor/hooks.json")" ] \
     && jq -e '[.hooks.stop[].command | select(test("/(quality-nudge|worktree-reap)\\.sh"))] | length == 2' \
          "$MT/.cursor/hooks.json" >/dev/null 2>&1; then
    ok "install-hooks cursor preserves foreign flat entries without duplicates"
  else
    bad "install-hooks cursor preserves foreign flat entries without duplicates"
  fi

  # Claude uses the same nested merge contract. A separate fixture makes
  # foreign empty/null preservation independent of the Codex fixture, and its
  # home path exercises spaces plus regex metacharacters literally.
  HCBASE="$(mktemp -d)"; HC="$HCBASE/"'a + ( [ { $ |'
  mkdir -p "$HC"
  HOME="$HC" bash "$DIR/install-hooks.sh" claude >/dev/null 2>&1
  jq '
    .hooks.Stop[0] |= (
      .matcher = "claude-mixed" | .custom = {owner:"managed"}
      | .hooks += [{type:"command",command:"/tmp/managed-claude-metrics.sh",timeout:9}]
    )
    | .hooks.Stop += [
      {matcher:"claude-empty",custom:"foreign",hooks:[]},
      {matcher:"claude-null",custom:"foreign",hooks:null}
    ]
  ' "$HC/.claude/settings.json" > "$HC/claude-mixed.json"
  mv "$HC/claude-mixed.json" "$HC/.claude/settings.json"
  claude_foreign_expected='[
    {"matcher":"claude-mixed","custom":{"owner":"managed"},"hooks":[
      {"type":"command","command":"/tmp/managed-claude-metrics.sh","timeout":9}
    ]},
    {"matcher":"claude-empty","custom":"foreign","hooks":[]},
    {"matcher":"claude-null","custom":"foreign","hooks":null}
  ]'
  HOME="$HC" bash "$DIR/install-hooks.sh" claude >/dev/null 2>&1
  claude_count="$(jq '[.hooks[]|length]|add' "$HC/.claude/settings.json")"
  HOME="$HC" bash "$DIR/install-hooks.sh" claude >/dev/null 2>&1
  hc_ok=1
  [ "$claude_count" = "$(jq '[.hooks[]|length]|add' "$HC/.claude/settings.json")" ] || hc_ok=0
  jq -e --argjson expected "$claude_foreign_expected" '
    [.hooks.Stop[] | select(.matcher == "claude-mixed" or .custom == "foreign")] == $expected
  ' "$HC/.claude/settings.json" >/dev/null 2>&1 || hc_ok=0
  # Reseed an owned handler before uninstall so both operations face a mixed
  # group rather than relying on where reinstall appends the owned groups.
  jq --arg own "env HOOK_PLATFORM=claude \"$HC/.claude/hooks/quality-nudge.sh\"" '
    .hooks.Stop |= map(if .matcher == "claude-mixed" then
      .hooks += [{type:"command",command:$own,timeout:30}] else . end)
  ' "$HC/.claude/settings.json" > "$HC/claude-uninstall.json"
  mv "$HC/claude-uninstall.json" "$HC/.claude/settings.json"
  HOME="$HC" bash "$DIR/uninstall.sh" claude >/dev/null 2>&1
  jq -e --argjson expected "$claude_foreign_expected" '
    .hooks == {Stop:$expected}
  ' "$HC/.claude/settings.json" >/dev/null 2>&1 || hc_ok=0
  [ "$hc_ok" = 1 ] \
    && ok "install/uninstall preserve Claude mixed and empty/null foreign groups in a literal metacharacter home" \
    || bad "install/uninstall preserve Claude mixed and empty/null foreign groups in a literal metacharacter home"
  rm -rf "$HCBASE"

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

  # Antigravity: headless `agy -p` auto-denies any command without an allow rule,
  # so a reviewer delegate needs a read-only allowlist. The user's own rules and
  # unrelated settings survive install, and uninstall takes back only ours.
  AG="$(mktemp -d)"; mkdir -p "$AG/.gemini/antigravity-cli"
  printf '%s\n' '{"verbosity":"medium","permissions":{"allow":["command(npm test)"],"ask":["command(*)"]}}' \
    > "$AG/.gemini/antigravity-cli/settings.json"
  HOME="$AG" bash "$DIR/install-settings.sh" antigravity >/dev/null 2>&1
  HOME="$AG" bash "$DIR/install-settings.sh" antigravity >/dev/null 2>&1
  ag_ok=1; ags="$AG/.gemini/antigravity-cli/settings.json"
  jq -e '.permissions.allow | index("command(git log)") and index("command(npm test)")' "$ags" >/dev/null 2>&1 || ag_ok=0
  jq -e '.permissions.ask == ["command(*)"] and .verbosity == "medium"' "$ags" >/dev/null 2>&1 || ag_ok=0
  jq -e '[.permissions.allow[] | select(. == "command(git log)")] | length == 1' "$ags" >/dev/null 2>&1 || ag_ok=0
  # The one write rule lands with the real $HOME (no placeholder left behind) and
  # is the only write rule: the repo must stay unwritable to a reviewer.
  jq -e --arg r "write_file($AG/.ai-context)" '.permissions.allow | index($r)' "$ags" >/dev/null 2>&1 || ag_ok=0
  jq -e '[.permissions.allow[] | select(test("@HOME@"))] | length == 0' "$ags" >/dev/null 2>&1 || ag_ok=0
  jq -e '[.permissions.allow[] | select(startswith("write_file("))] == ["write_file(@HOME@/.ai-context)"]' \
    "$DIR/settings-permissions.antigravity.snippet.json" >/dev/null 2>&1 || ag_ok=0
  # Nothing that writes or runs a program may ride in on the reviewer allowlist.
  jq -e '[.permissions.allow[] | select(test("^command\\((git (push|commit|reset|checkout|clean)|rm|sed|find|rg|bash|sh)\\b"))] | length == 0' \
    "$DIR/settings-permissions.antigravity.snippet.json" >/dev/null 2>&1 || ag_ok=0
  HOME="$AG" bash "$DIR/uninstall.sh" antigravity >/dev/null 2>&1
  jq -e '.permissions.allow == ["command(npm test)"] and .permissions.ask == ["command(*)"] and (.permissions.deny == null)' \
    "$ags" >/dev/null 2>&1 || ag_ok=0
  rm -rf "$AG"
  [ "$ag_ok" = 1 ] && ok "install-settings unions a read-only agy allowlist; uninstall removes only ours" \
                   || bad "install-settings unions a read-only agy allowlist; uninstall removes only ours"

  # Codex notification routing: preserve Warp itself and all sibling hook state,
  # disable only its premature PermissionRequest notifier, and use native TUI
  # events for approvals that actually reach the user.
  NT="$(mktemp -d)"; mkdir -p "$NT/.codex"
  cat > "$NT/.codex/config.toml" <<'TOML'
approval_policy = "never"

[plugins."warp@codex-warp"]
enabled = true

[tui.model_availability_nux]
"gpt-test" = 1

[hooks.state."warp@codex-warp:hooks/hooks.json:permission_request:1:1"]
trusted_hash = "keep-me"

[hooks.state."warp@codex-warp:hooks/hooks.json:stop:0:0"]
trusted_hash = "keep-stop"
TOML
  mkdir -p "$NT/.codex/.tmp/marketplaces/codex-warp/plugins/warp/hooks"
  cat > "$NT/.codex/.tmp/marketplaces/codex-warp/plugins/warp/hooks/hooks.json" <<'JSON'
{"hooks":{"PermissionRequest":[{"hooks":[{"type":"command","command":"${PLUGIN_ROOT}/scripts/other.sh"}]},{"hooks":[{"type":"command","command":"${PLUGIN_ROOT}/scripts/other.sh"},{"type":"command","command":"${PLUGIN_ROOT}/scripts/on-permission-request.sh"}]}]}}
JSON
  HOME="$NT" bash "$DIR/install-settings.sh" codex >/dev/null 2>&1
  n1="$(cksum < "$NT/.codex/config.toml")"
  HOME="$NT" bash "$DIR/install-settings.sh" codex >/dev/null 2>&1
  n2="$(cksum < "$NT/.codex/config.toml")"
  nt_ok=1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$NT/.codex/config.toml" <<'PY' 2>/dev/null || nt_ok=0
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
assert d["approval_policy"] == "never"
assert d["plugins"]["warp@codex-warp"]["enabled"] is True
assert d["tui"]["notifications"] == ["approval-requested"]
assert d["tui"]["notification_method"] == "osc9"
assert d["tui"]["notification_condition"] == "unfocused"
assert d["tui"]["model_availability_nux"]["gpt-test"] == 1
states = d["hooks"]["state"]
permission = states["warp@codex-warp:hooks/hooks.json:permission_request:1:1"]
assert permission["enabled"] is False and permission["trusted_hash"] == "keep-me"
assert states["warp@codex-warp:hooks/hooks.json:stop:0:0"]["trusted_hash"] == "keep-stop"
PY
  fi
  [ "$n1" = "$n2" ] || nt_ok=0
  [ "$nt_ok" = 1 ] && ok "codex notifications are actionable, scoped, and idempotent" \
                       || bad "codex notification routing"
  HOME="$NT" bash "$DIR/uninstall.sh" codex >/dev/null 2>&1
  if ! grep -qF 'agent-global-instructions: codex notification defaults' "$NT/.codex/config.toml" \
     && grep -q 'enabled = true' "$NT/.codex/config.toml" \
     && grep -q 'trusted_hash = "keep-stop"' "$NT/.codex/config.toml"; then
    ok "uninstall removes only owned codex notification defaults"
  else
    bad "uninstall preserves user codex notification/plugin state"
  fi
  rm -rf "$NT"

  # No phantom Warp state or notification defaults on machines where Warp is
  # absent/disabled; the harness does not install or take ownership of plugins.
  NW="$(mktemp -d)"; mkdir -p "$NW/.codex"
  printf '[plugins."warp@codex-warp"]\nenabled = false\n' > "$NW/.codex/config.toml"
  HOME="$NW" bash "$DIR/install-settings.sh" codex >/dev/null 2>&1
  if ! grep -q 'codex notification defaults' "$NW/.codex/config.toml" \
     && ! grep -q 'permission_request' "$NW/.codex/config.toml"; then
    ok "install-settings skips Warp routing when the plugin is disabled"
  else
    bad "install-settings synthesized state for disabled Warp plugin"
  fi
  rm -rf "$NW"

  # Explicit user choices win, quoted keys are recognized, and an array-of-tables
  # boundary cannot absorb newly seeded keys into the wrong TOML scope.
  UX="$(mktemp -d)"; mkdir -p "$UX/.codex/.tmp/marketplaces/codex-warp/plugins/warp/hooks"
  cat > "$UX/.codex/config.toml" <<'TOML'
[plugins."warp@codex-warp"]
enabled = true

[tui]
"notifications" = false
notification_method = "bel"

[[some_array]]
name = "keep"

[hooks.state.'warp@codex-warp:hooks/hooks.json:permission_request:0:0']
enabled = true
trusted_hash = "user-choice"
TOML
  cat > "$UX/.codex/.tmp/marketplaces/codex-warp/plugins/warp/hooks/hooks.json" <<'JSON'
{"hooks":{"PermissionRequest":[{"hooks":[{"type":"command","command":"${PLUGIN_ROOT}/scripts/on-permission-request.sh"}]}]}}
JSON
  HOME="$UX" bash "$DIR/install-settings.sh" codex >/dev/null 2>&1
  ux_ok=1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$UX/.codex/config.toml" <<'PY' 2>/dev/null || ux_ok=0
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
assert d["tui"]["notifications"] is False
assert d["tui"]["notification_method"] == "bel"
assert "notification_condition" not in d["tui"]
assert d["some_array"] == [{"name": "keep"}]
permission = d["hooks"]["state"]["warp@codex-warp:hooks/hooks.json:permission_request:0:0"]
assert permission["enabled"] is True and permission["trusted_hash"] == "user-choice"
PY
  fi
  [ "$ux_ok" = 1 ] && ok "codex notification merge preserves explicit values and TOML scopes" \
                       || bad "codex notification merge overwrote user TOML"
  rm -rf "$UX"

  # Never silence Warp approval alerts when an explicit native event filter does
  # not include approval-requested. A noisy alert is safer than an invisible
  # genuine approval wait.
  FC="$(mktemp -d)"; mkdir -p "$FC/.codex/.tmp/marketplaces/codex-warp/plugins/warp/hooks"
  cat > "$FC/.codex/config.toml" <<'TOML'
[plugins."warp@codex-warp"]
enabled = true
[tui]
notifications = [ "agent-turn-complete" ]
TOML
  cat > "$FC/.codex/.tmp/marketplaces/codex-warp/plugins/warp/hooks/hooks.json" <<'JSON'
{"hooks":{"PermissionRequest":[{"hooks":[{"type":"command","command":"${PLUGIN_ROOT}/scripts/on-permission-request.sh"}]}]}}
JSON
  HOME="$FC" bash "$DIR/install-settings.sh" codex >/dev/null 2>&1
  if grep -q 'notifications = \[ "agent-turn-complete" \]' "$FC/.codex/config.toml" \
     && ! grep -q 'permission_request' "$FC/.codex/config.toml"; then
    ok "codex routing keeps Warp approval alerts when native coverage is absent"
  else
    bad "codex routing could hide a genuine approval wait"
  fi
  rm -rf "$FC"

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
  # Reseed an owned command into the managed group to reproduce uninstall's
  # ownership boundary independently of the reinstall regression above.
  jq --arg own "env HOOK_PLATFORM=codex \"$MT/.codex/hooks/quality-nudge.sh\"" '
    .hooks.Stop |= map(
      if .matcher == "mixed-stop" then
        .hooks += [{type:"command",command:$own,timeout:30}]
      else . end
    )
  ' "$MT/.codex/hooks.json" > "$MT/codex-uninstall-mixed.json"
  mv "$MT/codex-uninstall-mixed.json" "$MT/.codex/hooks.json"
  HOME="$MT" bash "$DIR/uninstall.sh" claude codex cursor >/dev/null 2>&1
  u_ok=1
  [ -L "$MT/.codex/skills/foo" ]            || u_ok=0   # foreign link spared
  [ -f "$MT/.codex/skills/myown/SKILL.md" ] || u_ok=0   # user's real skill spared
  [ -L "$MT/.claude/skills/ghost" ]         && u_ok=0   # dangling link of ours removed
  [ -L "$MT/.cursor/skills/ghost" ]         && u_ok=0   # dangling link of ours removed
  [ -f "$MT/.codex/skills/ship/SKILL.md" ]   && u_ok=0
  [ -d "$MT/.codex/skills/ship" ]            && u_ok=0   # no orphaned empty skill dir
  [ -e "$MT/.codex/skills/ux-audit" ]        && u_ok=0   # design skill link removed
  [ -e "$MT/.claude/skills/ux-audit" ]       && u_ok=0
  [ -e "$MT/.cursor/skills/ux-audit" ]      && u_ok=0
  [ -f "$MT/.cursor/commands/ship.md" ]     && u_ok=0
  # Our fixtures intentionally contain user hooks, so uninstall must leave
  # these intact while removing every handler in the installed hook directory.
  [ "$cursor_foreign_before" = "$(jq -c '[.hooks.stop[] | select(.custom == "keep")]' "$MT/.cursor/hooks.json")" ] || u_ok=0
  [ "$codex_foreign_before" = "$(jq -c '[.hooks.PreToolUse[] | select(.custom == "foreign")]' "$MT/.codex/hooks.json")" ] || u_ok=0
  jq -e '
    ([.hooks.Stop[] | select(.matcher == "mixed-stop")] == [{
      matcher:"mixed-stop",custom:{owner:"managed"},hooks:[
        {type:"command",command:"/tmp/managed-metrics.sh",timeout:10,async:false}
      ]
    }])
  ' "$MT/.codex/hooks.json" >/dev/null 2>&1 || u_ok=0
  jq -e --arg foreign "$codex_foreign_before" '
    .hooks == {
      PreToolUse:($foreign | fromjson),
      Stop:[{matcher:"mixed-stop",custom:{owner:"managed"},hooks:[
        {type:"command",command:"/tmp/managed-metrics.sh",timeout:10,async:false}
      ]}]
    }
  ' "$MT/.codex/hooks.json" >/dev/null 2>&1 || u_ok=0
  jq -e --arg foreign "$cursor_foreign_before" '
    .hooks == {stop:($foreign | fromjson)}
  ' "$MT/.cursor/hooks.json" >/dev/null 2>&1 || u_ok=0
  [ "$u_ok" = 1 ] && ok "uninstall reverses commands/hooks/settings for all tools" \
                  || bad "uninstall reverses commands/hooks/settings for all tools"
  rm -rf "$MT"

  # Legacy gemini cleanup: `uninstall.sh gemini` strips whatever a
  # pre-retirement install left behind, without needing the retired renderer's
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

# ---- local-models layer: detection dry-run + the lm shim --------------------
echo ""
echo "== local-models layer (detection + lm shim) =="
# Hand-registered LOCAL_MODELS lines pass through verbatim; malformed lines are
# dropped with a warning. AIGI_NO_PROBE keeps the run hermetic (no network).
lm_out="$(LOCAL_MODELS='mac|mlx|http://mac.ts.net:8080|q3-30b|strong
not-a-registry-line' AIGI_NO_PROBE=1 "$CUSTOMIZE" --local-models 2>/dev/null)"
[ "$lm_out" = "mac|mlx|http://mac.ts.net:8080|q3-30b|strong" ] \
  && ok "--local-models passes registered lines through, drops malformed ones" \
  || bad "--local-models passes registered lines through, drops malformed ones (got: $lm_out)"
lm_off="$(INC_LOCAL_MODELS=n LOCAL_MODELS='mac|mlx|http://u|m|light' AIGI_NO_PROBE=1 "$CUSTOMIZE" --local-models 2>/dev/null)"
[ -z "$lm_off" ] && ok "INC_LOCAL_MODELS=n silences detection" \
                 || bad "INC_LOCAL_MODELS=n silences detection"

# The shim, hermetically: a stub `curl` on PATH answers the health check and the
# completion, so no server (and no network) is needed.
if command -v jq >/dev/null 2>&1; then
  LMT="$(mktemp -d)"
  mkdir -p "$LMT/bin"
  cat > "$LMT/bin/curl" <<'CURLEOF'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in
  */v1/models) echo '{"data":[{"id":"stub"}]}'; exit 0;;
  */v1/chat/completions) echo '{"choices":[{"message":{"content":"REPLY-FROM-STUB"}}],"usage":{"completion_tokens":10}}'; exit 0;;
esac; done
exit 0
CURLEOF
  chmod +x "$LMT/bin/curl"
  # No trailing newline on the last line on purpose — the shim must still see it.
  printf 'small|ollama|http://127.0.0.1:11434|tiny:3b|light\nbig|mlx|http://mac.ts.net:8080|q3-30b|strong' > "$LMT/reg"
  out="$(PATH="$LMT/bin:$PATH" LM_REGISTRY="$LMT/reg" bash "$DIR/lm" -p "hi" 2>/dev/null)"
  [ "$out" = "REPLY-FROM-STUB" ] && ok "lm -p returns the completion content" \
                                 || bad "lm -p returns the completion content (got: $out)"
  out="$(PATH="$LMT/bin:$PATH" LM_REGISTRY="$LMT/reg" bash "$DIR/lm" list 2>/dev/null)"
  printf '%s\n' "$out" | grep -Eq '^big[[:space:]]+mlx[[:space:]]+strong[[:space:]]+up' \
    && ok "lm list reports backend, tier, and health" \
    || bad "lm list reports backend, tier, and health"
  PATH="$LMT/bin:$PATH" LM_REGISTRY="$LMT/does-not-exist" bash "$DIR/lm" -p hi >/dev/null 2>&1
  [ $? -eq 3 ] && ok "lm exits 3 when no registry exists" \
               || bad "lm exits 3 when no registry exists"
  PATH="$LMT/bin:$PATH" LM_REGISTRY="$LMT/reg" bash "$DIR/lm" -p hi --tier nope >/dev/null 2>&1
  [ $? -eq 2 ] && ok "lm exits 2 when no endpoint matches the filters" \
               || bad "lm exits 2 when no endpoint matches the filters"
  rm -rf "$LMT"
else
  echo "  (skipped — jq not installed)"
fi

# ---- portable timeout shim: GNU-compatible subset + install-only-if-missing --
echo ""
echo "== portable timeout shim =="
PT="$DIR/portable-timeout"
"$PT" 1 sleep 5 >/dev/null 2>&1;          rc=$?
[ "$rc" -eq 124 ] && ok "timeout shim exits 124 on expiry" || bad "timeout shim exits 124 on expiry (got $rc)"
"$PT" 5 sh -c 'exit 7' >/dev/null 2>&1;   rc=$?
[ "$rc" -eq 7 ] && ok "timeout shim passes the command's exit status through" \
                || bad "timeout shim passes the command's exit status through (got $rc)"
out="$(printf 'in' | "$PT" 5 cat 2>/dev/null)"
[ "$out" = "in" ] && ok "timeout shim gives the command its stdin" || bad "timeout shim gives the command its stdin"
"$PT" 5 aigi-no-such-cmd >/dev/null 2>&1; rc=$?
[ "$rc" -eq 127 ] && ok "timeout shim exits 127 for a missing command" || bad "timeout shim exits 127 for a missing command (got $rc)"
"$PT" -k 5 true >/dev/null 2>&1;          rc=$?
[ "$rc" -eq 125 ] && ok "timeout shim rejects options it doesn't implement (125)" \
                  || bad "timeout shim rejects options it doesn't implement (got $rc)"
# Install only where no real `timeout` is on PATH. Both directions are forced
# with PATH, so the result is the same on Linux CI (has one) and macOS (doesn't):
# "none" is a PATH of symlinks to everything except timeout/gtimeout, "real"
# puts a stub `timeout` in front.
PTH="$(mktemp -d)"; mkdir -p "$PTH/none" "$PTH/real"
IFS=: read -r -a _pdirs <<< "$PATH"
for _d in "${_pdirs[@]}"; do
  for _f in "$_d"/*; do
    _n="${_f##*/}"
    case "$_n" in timeout|gtimeout) continue;; esac
    [ -x "$_f" ] && [ ! -e "$PTH/none/$_n" ] && ln -s "$_f" "$PTH/none/$_n" 2>/dev/null
  done
done
printf '#!/bin/sh\nexit 0\n' > "$PTH/real/timeout"; chmod +x "$PTH/real/timeout"
pt_global() { HOME="$1" PATH="$2" AIGI_NO_USER_ENV=1 AIGI_NO_PROBE=1 bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1; }
pt_global "$PTH/h1" "$PTH/none"
cmp -s "$PT" "$PTH/h1/.local/bin/timeout" \
  && ok "--global installs the timeout shim where none exists" \
  || bad "--global installs the timeout shim where none exists"
pt_global "$PTH/h1" "$PTH/real:$PTH/none"
[ ! -e "$PTH/h1/.local/bin/timeout" ] \
  && ok "--global removes its timeout shim once a real timeout is on PATH" \
  || bad "--global removes its timeout shim once a real timeout is on PATH"
mkdir -p "$PTH/h3/.local/bin" && printf '#!/bin/sh\necho mine\n' > "$PTH/h3/.local/bin/timeout"
pt_global "$PTH/h3" "$PTH/none"
grep -q mine "$PTH/h3/.local/bin/timeout" 2>/dev/null \
  && ok "--global never touches a foreign ~/.local/bin/timeout" \
  || bad "--global never touches a foreign ~/.local/bin/timeout"
rm -rf "$PTH"

# ---- worktree reaper: proof-of-merge, and everything that is not proof ------
# A hook that deletes directories earns fixtures, not assertions about prose.
# Every refusal gets a real repo. The falsifier is tested in both directions —
# nothing unproven is ever removed, AND a squash merge (which is NOT an ancestor
# of the default branch, so an ancestry-only check would reap nothing in Joe's
# /ship flow) is still reapable when the forge proves it with a matching SHA.
# Fixtures are seconds old, so the tests that expect a removal waive the cooling
# window explicitly with WORKTREE_REAP_MIN_AGE=0; one test asserts the window.
echo ""
echo "== worktree reaper (proof-of-merge safety model) =="
WRS="$DIR/hooks/worktree-reap.sh"
if command -v git >/dev/null 2>&1; then
  WR="$TMPD/wtreap"; mkdir -p "$WR"
  WRR="$WR/repo"
  (
    set -e
    git init -q "$WRR"
    cd "$WRR"
    git symbolic-ref HEAD refs/heads/main
    git config user.email t@t.t; git config user.name t
    printf '.env\n*.sqlite\nmy-context.env\nnode_modules/\n' > .gitignore
    echo base > f.txt; git add -A; git commit -qm init
    # provably merged (fast-forward) — the one thing that may be removed
    git worktree add -q ../wt-merged -b feat-merged
    ( cd ../wt-merged && echo m > m.txt && git add -A && git commit -qm m )
    git merge -q --no-edit feat-merged
    # merged too, but it is the tree the caller will be standing in
    git worktree add -q ../wt-current -b feat-current
    ( cd ../wt-current && echo c > c.txt && git add -A && git commit -qm c )
    git merge -q --no-edit feat-current
    # never merged
    git worktree add -q ../wt-unmerged -b feat-unmerged
    ( cd ../wt-unmerged && echo u > u.txt && git add -A && git commit -qm u )
    # merged, but carrying work that is not committed
    git worktree add -q ../wt-dirty -b feat-dirty
    ( cd ../wt-dirty && echo d > d.txt && git add -A && git commit -qm d )
    git merge -q --no-edit feat-dirty
    echo scratch > ../wt-dirty/untracked.txt
    # merged and clean to `git status`, but holding IGNORED files nobody can
    # regenerate — the class both `status --porcelain` and `worktree remove`
    # are blind to, and the class this repo's own .env/my-context.env fall in
    git worktree add -q ../wt-ignored -b feat-ignored
    ( cd ../wt-ignored && echo i > i.txt && git add -A && git commit -qm i )
    git merge -q --no-edit feat-ignored
    printf 'SECRET=1\n' > ../wt-ignored/.env
    : > ../wt-ignored/dev.sqlite
    mkdir -p ../wt-ignored/node_modules/p; echo x > ../wt-ignored/node_modules/p/i.js
    # merged, clean, and holding ONLY regenerable ignored files
    git worktree add -q ../wt-regen -b feat-regen
    ( cd ../wt-regen && echo r > r.txt && git add -A && git commit -qm r )
    git merge -q --no-edit feat-regen
    mkdir -p ../wt-regen/node_modules/p; echo x > ../wt-regen/node_modules/p/i.js
    # brand new, exactly as `/worktrees` creates one: branched AT the default
    # tip, nothing committed. Ancestry is reflexive, so this is "merged" from
    # birth — and deleting it eats a tree the same turn created.
    git worktree add -q ../wt-fresh -b ai/fresh
    mkdir -p ../wt-fresh/node_modules/p; echo x > ../wt-fresh/node_modules/p/i.js
    # merged, but locked by another session
    git worktree add -q ../wt-locked -b feat-locked
    ( cd ../wt-locked && echo l > l.txt && git add -A && git commit -qm l )
    git merge -q --no-edit feat-locked
    git worktree lock ../wt-locked
    # registration whose directory is already gone
    git worktree add -q ../wt-gone -b feat-gone
    rm -rf ../wt-gone
    # squash-merged: `merge-base --is-ancestor` is FALSE for this one
    git worktree add -q ../wt-squash -b feat-squash
    ( cd ../wt-squash && echo s > s.txt && git add -A && git commit -qm s )
    git merge -q --squash feat-squash; git commit -qm "squash: feat-squash"
  ) >/dev/null 2>&1

  wr_before="$(find "$WR" -maxdepth 1 | sort | tr '\n' ' ')"
  wr_rep="$( cd "$WRR" && WORKTREE_REAP_MIN_AGE=0 bash "$WRS" --sweep 2>/dev/null )"
  wr_after="$(find "$WR" -maxdepth 1 | sort | tr '\n' ' ')"

  wr_ok=1
  printf '%s\n' "$wr_rep" | grep -Eq 'REAPABLE +.*/wt-merged .*proof: ancestor'   || wr_ok=0
  printf '%s\n' "$wr_rep" | grep -Eq 'REAPABLE +.*/wt-regen .*proof: ancestor'    || wr_ok=0
  printf '%s\n' "$wr_rep" | grep -Eq 'UNMERGED +.*/wt-unmerged'                   || wr_ok=0
  printf '%s\n' "$wr_rep" | grep -Eq 'DIRTY +.*/wt-dirty'                         || wr_ok=0
  printf '%s\n' "$wr_rep" | grep -Eq 'LOCKED +.*/wt-locked'                       || wr_ok=0
  printf '%s\n' "$wr_rep" | grep -Eq 'PRUNABLE +.*/wt-gone'                       || wr_ok=0
  printf '%s\n' "$wr_rep" | grep -Eq 'MAIN +.*/repo'                              || wr_ok=0
  [ "$wr_ok" = 1 ] && ok "worktree-reap classifies main, dirty, locked, unmerged, prunable and reapable trees" \
                   || bad "worktree-reap classifies main, dirty, locked, unmerged, prunable and reapable trees"

  # Half one of the falsifier: an ancestry-only check must NOT call a squash
  # merge merged, and with no forge to ask, the tree survives untouched.
  printf '%s\n' "$wr_rep" | grep -Eq 'UNMERGED +.*/wt-squash' \
    && ok "worktree-reap treats a squash merge as unproven without a forge to ask" \
    || bad "worktree-reap treats a squash merge as unproven without a forge to ask"

  # `git status --porcelain` is empty for a tree full of .env and *.sqlite, and
  # `git worktree remove` deletes it without complaint. The ignored-file gate is
  # the only thing standing between a merged branch and someone's credentials.
  if printf '%s\n' "$wr_rep" | grep -Eq 'DIRTY +.*/wt-ignored .*ignored files' \
     && printf '%s\n' "$wr_rep" | grep -Eq 'DIRTY +.*/wt-ignored .*\.env'; then
    ok "worktree-reap refuses a merged tree holding ignored files it cannot regenerate"
  else
    bad "worktree-reap refuses a merged tree holding ignored files it cannot regenerate"
  fi

  # Ancestry is reflexive: a branch created at the default tip is already an
  # ancestor of it. Only reflog evidence separates "finished" from "never began".
  printf '%s\n' "$wr_rep" | grep -Eq 'UNSTARTED +.*/wt-fresh' \
    && ok "worktree-reap never reaps a brand-new branch that was born at the default tip" \
    || bad "worktree-reap never reaps a brand-new branch that was born at the default tip"

  # A dry run is a report: no directory appears or disappears, no branch dies,
  # and the stale registration is still registered (pruning is an --apply act).
  if [ "$wr_before" = "$wr_after" ] \
     && [ -d "$WR/wt-merged" ] \
     && git -C "$WRR" show-ref --verify --quiet refs/heads/feat-merged \
     && git -C "$WRR" worktree list --porcelain 2>/dev/null | grep -q 'prunable'; then
    ok "worktree-reap --sweep without --apply writes nothing"
  else
    bad "worktree-reap --sweep without --apply writes nothing"
  fi

  # The cooling window: everything above is minutes old, so with the default
  # WORKTREE_REAP_MIN_AGE nothing is reapable at all — a sibling tree another
  # agent just committed WIP into looks exactly like a finished one.
  wr_cool="$( cd "$WRR" && bash "$WRS" --sweep --apply 2>/dev/null )"
  if printf '%s\n' "$wr_cool" | grep -Eq 'COOLING +.*/wt-merged' \
     && [ -d "$WR/wt-merged" ] \
     && ! printf '%s\n' "$wr_cool" | grep -Eq 'REAPABLE'; then
    ok "worktree-reap holds a freshly-merged tree inside the cooling window"
  else
    bad "worktree-reap holds a freshly-merged tree inside the cooling window"
  fi

  # A malformed keep-list must fail CLOSED. `grep -E` exits 2 on a bad pattern,
  # which a naive caller reads as "no match" — and then protects nothing.
  ( cd "$WRR" && WORKTREE_REAP_KEEP_RE='[' WORKTREE_REAP_MIN_AGE=0 bash "$WRS" --sweep --apply ) >/dev/null 2>&1
  wr_rc=$?
  if [ "$wr_rc" = 2 ] && [ -d "$WR/wt-merged" ] && [ -d "$WR/wt-regen" ]; then
    ok "worktree-reap refuses to sweep at all on a malformed WORKTREE_REAP_KEEP_RE"
  else
    bad "worktree-reap refuses to sweep at all on a malformed WORKTREE_REAP_KEEP_RE"
  fi

  # A valid keep-list is honored.
  wr_rep="$( cd "$WRR" && WORKTREE_REAP_KEEP_RE='wt-merged$' WORKTREE_REAP_MIN_AGE=0 bash "$WRS" --sweep 2>/dev/null )"
  printf '%s\n' "$wr_rep" | grep -Eq 'KEEP +.*/wt-merged .*KEEP_RE' \
    && ok "worktree-reap honors a valid WORKTREE_REAP_KEEP_RE" \
    || bad "worktree-reap honors a valid WORKTREE_REAP_KEEP_RE"

  # --apply from INSIDE a merged worktree: it removes the other proven ones and
  # prunes the stale registration, but never the tree it is standing in, never
  # the main worktree, and nothing that is dirty, ignored-precious, locked,
  # unmerged or unstarted.
  ( cd "$WR/wt-current" && WORKTREE_REAP_MIN_AGE=0 bash "$WRS" --sweep --apply ) >/dev/null 2>&1
  wr_ok=1
  [ -d "$WR/wt-merged" ]   && wr_ok=0        # proven merged -> removed
  [ -d "$WR/wt-regen" ]    && wr_ok=0        # only regenerable ignored files -> removed
  git -C "$WRR" show-ref --verify --quiet refs/heads/feat-merged && wr_ok=0
  [ -d "$WR/wt-current" ]  || wr_ok=0        # the caller's own tree survives
  [ -d "$WRR" ]            || wr_ok=0        # the main worktree survives
  [ -d "$WR/wt-dirty" ]    || wr_ok=0
  [ -d "$WR/wt-ignored" ]  || wr_ok=0
  [ -f "$WR/wt-ignored/.env" ] || wr_ok=0
  [ -d "$WR/wt-locked" ]   || wr_ok=0
  [ -d "$WR/wt-unmerged" ] || wr_ok=0
  [ -d "$WR/wt-fresh" ]    || wr_ok=0
  [ -d "$WR/wt-squash" ]   || wr_ok=0
  git -C "$WRR" worktree list --porcelain 2>/dev/null | grep -q 'prunable' && wr_ok=0
  [ "$wr_ok" = 1 ] && ok "worktree-reap --apply reaps only proven trees, prunes the stale one, spares the rest" \
                   || bad "worktree-reap --apply reaps only proven trees, prunes the stale one, spares the rest"

  # Standing elsewhere, the formerly-CURRENT tree becomes reapable — proving the
  # refusal above was about the caller's position, not about that tree.
  ( cd "$WRR" && WORKTREE_REAP_MIN_AGE=0 bash "$WRS" --sweep --apply ) >/dev/null 2>&1
  if [ ! -d "$WR/wt-current" ] && [ -d "$WR/wt-unmerged" ] && [ -d "$WR/wt-dirty" ] && [ -d "$WRR" ]; then
    ok "worktree-reap reaps a merged tree once the caller is no longer standing in it"
  else
    bad "worktree-reap reaps a merged tree once the caller is no longer standing in it"
  fi

  # Half two of the falsifier, and the trap inside it. The forge arm is what
  # makes a squash-merge flow reapable at all — but a branch NAME proves
  # nothing: `ai/<agent>` is recreated every run and trails merged PRs forever.
  # The stub answers with a head SHA, exactly as `gh --json headRefOid` does:
  # the real tip for feat-squash, a stranger's SHA for anything else.
  mkdir -p "$WR/bin"
  wr_tip="$(git -C "$WRR" rev-parse refs/heads/feat-squash 2>/dev/null)"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'head=""; prev=""\n'
    printf 'for a in "$@"; do [ "$prev" = "--head" ] && head="$a"; prev="$a"; done\n'
    printf 'if [ "$head" = "feat-squash" ]; then echo "%s"; else echo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"; fi\n' "$wr_tip"
    printf 'exit 0\n'
  } > "$WR/bin/gh"
  chmod +x "$WR/bin/gh"
  # The forge arm needs a `timeout`. Stock macOS has none, which is what the
  # installer's portable shim is for, so the shim stands in for it here.
  command -v timeout >/dev/null 2>&1 || ln -s "$DIR/portable-timeout" "$WR/bin/timeout"
  git -C "$WRR" remote add origin https://github.com/acme/demo.git 2>/dev/null
  wr_rep="$( cd "$WRR" && PATH="$WR/bin:$PATH" WORKTREE_REAP_MIN_AGE=0 bash "$WRS" --sweep --apply 2>/dev/null )"
  wr_ok=1
  printf '%s\n' "$wr_rep" | grep -Eq 'REAPABLE +.*/wt-squash .*proof: forge' || wr_ok=0
  [ -d "$WR/wt-squash" ] && wr_ok=0
  git -C "$WRR" show-ref --verify --quiet refs/heads/feat-squash && wr_ok=0
  [ "$wr_ok" = 1 ] && ok "worktree-reap reaps a squash merge whose forge head SHA matches this tip" \
                   || bad "worktree-reap reaps a squash merge whose forge head SHA matches this tip"

  # The same forge answer for a branch whose SHA does NOT match is not evidence
  # about this tree — and `git branch -d` refusing is a veto, never a trigger
  # to escalate to -D.
  wr_ok=1
  printf '%s\n' "$wr_rep" | grep -Eq 'UNMERGED +.*/wt-unmerged' || wr_ok=0
  [ -d "$WR/wt-unmerged" ] || wr_ok=0
  git -C "$WRR" show-ref --verify --quiet refs/heads/feat-unmerged || wr_ok=0
  [ "$wr_ok" = 1 ] && ok "worktree-reap ignores a merged PR that shares the branch name but not the SHA" \
                   || bad "worktree-reap ignores a merged PR that shares the branch name but not the SHA"

  # ADVISE-ONLY arm: a `gone` upstream is a likelihood. It is reported with the
  # exact command and never acted on, even under --apply.
  WRG="$TMPD/wtgone"; mkdir -p "$WRG"
  (
    set -e
    git init -q --bare "$WRG/remote.git"
    git init -q "$WRG/repo"
    cd "$WRG/repo"
    git symbolic-ref HEAD refs/heads/main
    git config user.email t@t.t; git config user.name t
    echo base > f.txt; git add -A; git commit -qm init
    git remote add origin "$WRG/remote.git"; git push -q -u origin main
    git worktree add -q ../wt-shipped -b feat-shipped
    ( cd ../wt-shipped && echo x > x.txt && git add -A && git commit -qm x && git push -q -u origin feat-shipped )
    git push -q origin --delete feat-shipped
    git fetch -q --prune
  ) >/dev/null 2>&1
  wr_rep="$( cd "$WRG/repo" && WORKTREE_REAP_MIN_AGE=0 bash "$WRS" --sweep --apply 2>/dev/null )"
  wr_ok=1
  printf '%s\n' "$wr_rep" | grep -Eq 'LIKELY-MERGED +.*/wt-shipped' || wr_ok=0
  printf '%s\n' "$wr_rep" | grep -q "worktree remove"               || wr_ok=0
  [ -d "$WRG/wt-shipped" ]                                          || wr_ok=0
  git -C "$WRG/repo" show-ref --verify --quiet refs/heads/feat-shipped || wr_ok=0
  [ "$wr_ok" = 1 ] && ok "worktree-reap only advises on a gone upstream — never removes it" \
                   || bad "worktree-reap only advises on a gone upstream — never removes it"

  # A default branch that had to be guessed may report, but may never delete.
  WRA="$TMPD/wtambig"; mkdir -p "$WRA"
  (
    set -e
    git init -q "$WRA/repo"
    cd "$WRA/repo"
    git symbolic-ref HEAD refs/heads/integration
    git config user.email t@t.t; git config user.name t
    echo base > f.txt; git add -A; git commit -qm init
    git branch main; git branch master
    git worktree add -q ../wt-x -b feat-x
    ( cd ../wt-x && echo x > x.txt && git add -A && git commit -qm x )
    git merge -q --no-edit feat-x
  ) >/dev/null 2>&1
  wr_rep="$( cd "$WRA/repo" && WORKTREE_REAP_MIN_AGE=0 bash "$WRS" --sweep --apply 2>/dev/null )"
  if printf '%s\n' "$wr_rep" | grep -q 'could not be resolved confidently' && [ -d "$WRA/wt-x" ]; then
    ok "worktree-reap will not delete when the default branch had to be guessed"
  else
    bad "worktree-reap will not delete when the default branch had to be guessed"
  fi

  if command -v jq >/dev/null 2>&1; then
    wr_json="$( cd "$WRG/repo" && bash "$WRS" --sweep --json 2>/dev/null )"
    printf '%s' "$wr_json" | jq -e 'map(.status) | index("LIKELY-MERGED") != null and (index("MAIN") != null)' >/dev/null 2>&1 \
      && ok "worktree-reap --json emits the status vocabulary" \
      || bad "worktree-reap --json emits the status vocabulary"

    # Hook mode: advisory JSON, auto-delete of the proven tree only, rate limit,
    # stop_hook_active, the off switch, and the Cursor dialect.
    WRH="$TMPD/wtreap-hook"; mkdir -p "$WRH"
    (
      set -e
      git init -q "$WRH/repo"
      cd "$WRH/repo"
      git symbolic-ref HEAD refs/heads/main
      git config user.email t@t.t; git config user.name t
      echo base > f.txt; git add -A; git commit -qm init
      git worktree add -q ../wt-m -b feat-m
      ( cd ../wt-m && echo m > m.txt && git add -A && git commit -qm m )
      git merge -q --no-edit feat-m
      git worktree add -q ../wt-u -b feat-u
      ( cd ../wt-u && echo u > u.txt && git add -A && git commit -qm u )
    ) >/dev/null 2>&1
    WRST="$TMPD/wtreap-state"; mkdir -p "$WRST"

    h_off="$(printf '{"cwd":"%s"}' "$WRH/repo" | WORKTREE_REAP=off WORKTREE_REAP_MIN_AGE=0 AI_NUDGE_STATE="$WRST" HOOK_PLATFORM=claude bash "$WRS" 2>/dev/null)"
    h_act="$(printf '{"cwd":"%s","stop_hook_active":true}' "$WRH/repo" | WORKTREE_REAP_MIN_AGE=0 AI_NUDGE_STATE="$WRST" HOOK_PLATFORM=claude bash "$WRS" 2>/dev/null)"
    h_adv="$(printf '{"cwd":"%s"}' "$WRH/repo" | WORKTREE_REAP=advise WORKTREE_REAP_MIN_AGE=0 AI_NUDGE_STATE="$TMPD/wtreap-state2" HOOK_PLATFORM=claude bash "$WRS" 2>/dev/null)"
    h_bad="$(printf '{"cwd":"%s"}' "$WRH/repo" | WORKTREE_REAP_KEEP_RE='[' WORKTREE_REAP_MIN_AGE=0 AI_NUDGE_STATE="$TMPD/wtreap-state5" HOOK_PLATFORM=claude bash "$WRS" 2>/dev/null)"
    if [ -z "$h_off" ] && [ -z "$h_act" ] && [ -d "$WRH/wt-m" ] \
       && printf '%s' "$h_adv" | jq -e '.continue==true and (.systemMessage|test("provably merged")) and (has("decision")|not)' >/dev/null 2>&1 \
       && printf '%s' "$h_bad" | jq -e '.systemMessage|test("not a valid extended regular expression")' >/dev/null 2>&1 \
       && [ -d "$WRH/wt-m" ]; then
      ok "worktree-reap hook honors off, stop_hook_active, advise, and a bad keep-list (deletes nothing)"
    else
      bad "worktree-reap hook honors off, stop_hook_active, advise, and a bad keep-list (deletes nothing)"
    fi

    h1="$(printf '{"cwd":"%s"}' "$WRH/repo" | WORKTREE_REAP_MIN_AGE=0 AI_NUDGE_STATE="$WRST" HOOK_PLATFORM=claude bash "$WRS" 2>/dev/null)"; h1rc=$?
    h2="$(printf '{"cwd":"%s"}' "$WRH/repo" | WORKTREE_REAP_MIN_AGE=0 AI_NUDGE_STATE="$WRST" HOOK_PLATFORM=claude bash "$WRS" 2>/dev/null)"
    if [ "$h1rc" = 0 ] \
       && printf '%s' "$h1" | jq -e '.continue==true and (.systemMessage|test("Removed 1 provably-merged")) and (.systemMessage|test("Advisory only")) and (has("decision")|not)' >/dev/null 2>&1 \
       && [ ! -d "$WRH/wt-m" ] && [ -d "$WRH/wt-u" ] \
       && git -C "$WRH/repo" show-ref --verify --quiet refs/heads/feat-u \
       && [ -z "$h2" ]; then
      ok "worktree-reap hook is advisory, non-blocking, reaps only the proven tree, and rate-limits"
    else
      bad "worktree-reap hook is advisory, non-blocking, reaps only the proven tree, and rate-limits"
    fi

    hc="$(printf '{"cwd":"%s","loop_count":0}' "$WRG/repo" | WORKTREE_REAP_MIN_AGE=0 AI_NUDGE_STATE="$TMPD/wtreap-state3" HOOK_PLATFORM=cursor bash "$WRS" 2>/dev/null)"
    hc2="$(printf '{"cwd":"%s","loop_count":1}' "$WRG/repo" | WORKTREE_REAP_MIN_AGE=0 AI_NUDGE_STATE="$TMPD/wtreap-state4" HOOK_PLATFORM=cursor bash "$WRS" 2>/dev/null)"
    if printf '%s' "$hc" | jq -e '.followup_message | test("Worktree reap")' >/dev/null 2>&1 && [ -z "$hc2" ]; then
      ok "worktree-reap emits the cursor followup_message dialect and honors loop_count"
    else
      bad "worktree-reap emits the cursor followup_message dialect and honors loop_count"
    fi

    # The dual-mode script is also installed as the tool-agnostic sweep CLI, and
    # uninstall takes it back off the machine.
    WRHOME="$TMPD/wtreap-home"; mkdir -p "$WRHOME"
    HOME="$WRHOME" bash "$DIR/install-hooks.sh" claude >/dev/null 2>&1
    wr_ok=1
    [ -x "$WRHOME/.ai/worktree-sweep.sh" ] || wr_ok=0
    cmp -s "$DIR/hooks/worktree-reap.sh" "$WRHOME/.ai/worktree-sweep.sh" || wr_ok=0
    HOME="$WRHOME" bash "$DIR/uninstall.sh" claude >/dev/null 2>&1
    [ -e "$WRHOME/.ai/worktree-sweep.sh" ] && wr_ok=0
    jq -e '[(.hooks.Stop // [])[].hooks[].command] | any(test("worktree-reap"))' \
      "$WRHOME/.claude/settings.json" >/dev/null 2>&1 && wr_ok=0
    [ "$wr_ok" = 1 ] && ok "install-hooks installs ~/.ai/worktree-sweep.sh and uninstall removes it" \
                     || bad "install-hooks installs ~/.ai/worktree-sweep.sh and uninstall removes it"
  else
    echo "  (hook-mode tests skipped — jq not installed)"
  fi
else
  echo "  (skipped — git not installed)"
fi


# ---- project mode never renders the globals into this checkout --------------
# The repo used to carry an untracked AGENTS.md/CLAUDE.md render at its root, so
# a session here loaded the whole instruction set twice: once via ~/AGENTS.md and
# again as project instructions. write_project now targets $PWD and refuses the
# harness checkout, and the project files are committed instead.
echo ""
echo "== project mode =="

PROJ="$TMPD/a-project"; mkdir -p "$PROJ"
if ( cd "$PROJ" && "$CUSTOMIZE" --project >/dev/null 2>&1 ) && [ -f "$PROJ/AGENTS.md" ] && [ -f "$PROJ/CLAUDE.md" ]; then
  ok "--project writes AGENTS.md/CLAUDE.md into the current directory"
else
  bad "--project writes AGENTS.md/CLAUDE.md into the current directory"
fi

# A directory holding both template.md and customize.sh is a harness checkout.
FAKE="$TMPD/fake-harness"; mkdir -p "$FAKE"
cp "$DIR/customize.sh" "$DIR/template.md" "$FAKE/" 2>/dev/null
: > "$FAKE/AGENTS.md"
if ( cd "$FAKE" && "$FAKE/customize.sh" --project >/dev/null 2>&1 ); then
  bad "--project refuses to render into a harness checkout"
else
  ok "--project refuses to render into a harness checkout"
fi
if [ -s "$FAKE/AGENTS.md" ]; then
  bad "--project leaves a refused checkout's AGENTS.md untouched"
else
  ok "--project leaves a refused checkout's AGENTS.md untouched"
fi

# The committed project instructions are instructions, not a render of the globals.
if [ -f "$DIR/AGENTS.md" ] && ! grep -qF 'GENERATED FILE' "$DIR/AGENTS.md"; then
  ok "repo AGENTS.md is committed project instructions, not a global render"
else
  bad "repo AGENTS.md is committed project instructions, not a global render"
fi
if grep -qF '@AGENTS.md' "$DIR/CLAUDE.md" && [ "$(wc -l < "$DIR/CLAUDE.md")" -lt 12 ]; then
  ok "repo CLAUDE.md is a pointer at AGENTS.md, not a second copy"
else
  bad "repo CLAUDE.md is a pointer at AGENTS.md, not a second copy"
fi

# Claude Code's SessionStart matchers include fork; without it a forked session
# starts with neither the memory context nor the autonomy reminder.
if grep -qF 'startup|resume|clear|compact|fork' "$DIR/install-hooks.sh"; then
  ok "install-hooks wires SessionStart for forked sessions too"
else
  bad "install-hooks wires SessionStart for forked sessions too"
fi


# ---- install ledger (lib/preserve.sh) — PLAN-install-preservation.md phase 1 --
# The ledger exists to tell "a version this installer wrote" from "someone's
# edit", which a plain `cmp new dest` can't. Each case runs in a subshell with
# its own HOME, state dir, and a fixture git repo whose history holds v1 and v2
# of one file, so SHIPPED is testable without depending on this checkout's depth.
echo "== install ledger =="
LT="$(mktemp -d "${TMPDIR:-/tmp}/aigi_ledger.XXXXXX")"
FX="$LT/repo"; mkdir -p "$FX/roles"
git -C "$FX" init -q
printf 'v1\n' > "$FX/roles/r.md"; git -C "$FX" add -A; git -C "$FX" -c user.name=t -c user.email=t@t commit -qm v1
printf 'v2\n' > "$FX/roles/r.md"; git -C "$FX" -c user.name=t -c user.email=t@t commit -qam v2
# lt <case-name> <snippet>: run the snippet with the library loaded against the fixture.
lt() {
  local h="$LT/$1"; rm -rf "$h"; mkdir -p "$h"
  # Each case's HOME/state/repo is deliberately local to its subshell.
  # shellcheck disable=SC2030,SC2031
  ( export HOME="$h" AIGI_STATE_DIR="$h/state" PV_REPO="$FX"
    # shellcheck source=lib/preserve.sh
    . "$LEDGER_LIB"
    eval "$2" ) >"$h/out" 2>&1
}
LEDGER_LIB="$DIR/lib/preserve.sh"
st() { printf '%s' "$LT/$1/state"; }

lt created 'pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; echo "A=$PV_ACTION"'
{ grep -q 'A=created' "$LT/created/out" && [ "$(cut -f2 "$(st created)/manifest.tsv")" = "$LT/created/d.md" ] \
  && cmp -s "$FX/roles/r.md" "$(st created)/base/$(cut -f1 "$(st created)/manifest.tsv")"; } \
  && ok "ledger: a new file is created, recorded, and its bytes kept in base/" \
  || bad "ledger: a new file is created, recorded, and its bytes kept in base/"

lt adopt 'cp "$PV_REPO/roles/r.md" "$HOME/d.md"; pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; echo "A=$PV_ACTION"'
{ grep -q 'A=current' "$LT/adopt/out" && [ "$(wc -l < "$(st adopt)/manifest.tsv")" -eq 1 ]; } \
  && ok "ledger: an identical pre-ledger file is adopted without a write" \
  || bad "ledger: an identical pre-ledger file is adopted without a write"

lt ours 'printf "old\n" > "$HOME/s"; pv_write role "$HOME/s" "$HOME/d.md"; pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md"; echo "A=$PV_ACTION"'
{ grep -q 'A=updated' "$LT/ours/out" && [ ! -e "$(st ours)/preserved.tsv" ] && cmp -s "$FX/roles/r.md" "$LT/ours/d.md"; } \
  && ok "ledger: a file still holding what we wrote is updated quietly, nothing preserved" \
  || bad "ledger: a file still holding what we wrote is updated quietly, nothing preserved"

lt custom 'pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; printf "my edit\n" > "$HOME/d.md"; pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; echo "A=$PV_ACTION S=$PV_SAVED"'
csaved="$(sed -n 's/.* S=//p' "$LT/custom/out")"
{ grep -q 'A=replaced-custom' "$LT/custom/out" && grep -q 'replaced your edited' "$LT/custom/out" \
  && [ "$(cat "$csaved" 2>/dev/null)" = "my edit" ] && cmp -s "$FX/roles/r.md" "$LT/custom/d.md" \
  && [ "$(wc -l < "$(st custom)/preserved.tsv")" -eq 1 ]; } \
  && ok "ledger: an edited file is saved to preserved/ before it's replaced, and the run says so" \
  || bad "ledger: an edited file is saved to preserved/ before it's replaced, and the run says so"

# R2: with a ledger row, matching an OLD shipped version is not "safe" — the
# user put it there after our write (a deliberate revert).
lt revert 'pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; printf "v1\n" > "$HOME/d.md"; echo "V=$(pv_classify "$HOME/d.md" roles/r.md)"; pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; echo "A=$PV_ACTION S=$PV_SAVED"'
rsaved="$(sed -n 's/.* S=//p' "$LT/revert/out")"
{ grep -q 'V=CUSTOM' "$LT/revert/out" && grep -q 'A=replaced-custom' "$LT/revert/out" && [ "$(cat "$rsaved" 2>/dev/null)" = "v1" ]; } \
  && ok "ledger: a deliberate revert to an older shipped version is CUSTOM, not SHIPPED" \
  || bad "ledger: a deliberate revert to an older shipped version is CUSTOM, not SHIPPED"

# SHIPPED could be a stale install or a deliberate revert; with no ledger row
# nothing can tell, so it's kept once (quietly) — and the next run is OURS.
lt shipped 'printf "v1\n" > "$HOME/d.md"; pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; echo "A=$PV_ACTION"; printf "v3\n" > "$HOME/s"; pv_write role "$HOME/s" "$HOME/d.md" roles/r.md; echo "B=$PV_ACTION"'
{ grep -q 'A=updated' "$LT/shipped/out" && grep -q 'B=updated' "$LT/shipped/out" \
  && ! grep -q 'replaced your edited' "$LT/shipped/out" && [ "$(wc -l < "$(st shipped)/preserved.tsv")" -eq 1 ]; } \
  && ok "ledger: a pre-ledger shipped version updates quietly, kept once, then is OURS" \
  || bad "ledger: a pre-ledger shipped version updates quietly, kept once, then is OURS"

lt bootcustom 'printf "hand-made\n" > "$HOME/d.md"; pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; echo "A=$PV_ACTION"'
{ grep -q 'A=replaced-custom' "$LT/bootcustom/out" && [ -s "$(st bootcustom)/preserved.tsv" ]; } \
  && ok "ledger: a pre-ledger file in no shipped version is preserved before replacement" \
  || bad "ledger: a pre-ledger file in no shipped version is preserved before replacement"

lt generated 'printf "hand-made\n" > "$HOME/d.sh"; pv_write gen "$PV_REPO/roles/r.md" "$HOME/d.sh"; echo "A=$PV_ACTION"'
grep -q "couldn't prove it was unedited" "$LT/generated/out" \
  && ok "ledger: a generated file with no history is preserved and reported honestly" \
  || bad "ledger: a generated file with no history is preserved and reported honestly"

lt symlink 'printf "dotfile\n" > "$HOME/target"; ln -s "$HOME/target" "$HOME/d.md"; pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; echo "A=$PV_ACTION"'
{ grep -q 'A=skipped-symlink' "$LT/symlink/out" && [ "$(cat "$LT/symlink/target")" = "dotfile" ] && [ -L "$LT/symlink/d.md" ]; } \
  && ok "ledger: a symlinked destination is never written through" \
  || bad "ledger: a symlinked destination is never written through"

lt delours 'pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; pv_delete "$HOME/d.md" toggled roles/r.md; echo "A=$PV_ACTION"'
{ grep -q 'A=removed' "$LT/delours/out" && [ ! -e "$LT/delours/d.md" ] && [ ! -e "$(st delours)/preserved.tsv" ] \
  && [ ! -s "$(st delours)/manifest.tsv" ]; } \
  && ok "ledger: deleting a file we wrote removes it and its ledger row, nothing preserved" \
  || bad "ledger: deleting a file we wrote removes it and its ledger row, nothing preserved"

lt delcustom 'pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; printf "mine\n" > "$HOME/d.md"; pv_delete "$HOME/d.md" toggled roles/r.md; echo "S=$PV_SAVED"'
dsaved="$(sed -n 's/^S=//p' "$LT/delcustom/out")"
{ [ ! -e "$LT/delcustom/d.md" ] && [ "$(cat "$dsaved" 2>/dev/null)" = "mine" ]; } \
  && ok "ledger: deleting an edited file saves it to preserved/ first" \
  || bad "ledger: deleting an edited file saves it to preserved/ first"

# Lock: a live holder refuses a second writer; a dead holder is taken over.
lt lockdead 'mkdir -p "$AIGI_STATE_DIR/lock"; printf "999999\nnot-a-start\n%s\n%s\n" "$(pv_host)" "$(date +%s)" > "$AIGI_STATE_DIR/lock/owner"; pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; echo "A=$PV_ACTION"'
grep -q 'A=created' "$LT/lockdead/out" \
  && ok "ledger: a lock left by a dead process is taken over" \
  || bad "ledger: a lock left by a dead process is taken over"
lt locklive 'mkdir -p "$AIGI_STATE_DIR/lock"; printf "%s\n%s\n%s\n%s\n" "$PPID" "$(pv_proc_start "$PPID")" "$(pv_host)" "$(date +%s)" > "$AIGI_STATE_DIR/lock/owner"; if pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; then echo WROTE; else echo REFUSED; fi'
{ grep -q REFUSED "$LT/locklive/out" && [ ! -e "$LT/locklive/d.md" ]; } \
  && ok "ledger: a lock held by a live process refuses a second writer" \
  || bad "ledger: a lock held by a live process refuses a second writer"

# ps that can't report start times: a live holder must still refuse (fail closed).
lt nops 'mkdir -p "$HOME/bin"; printf "#!/bin/sh\nexit 1\n" > "$HOME/bin/ps"; chmod +x "$HOME/bin/ps"; PATH="$HOME/bin:$PATH"; mkdir -p "$AIGI_STATE_DIR/lock"; printf "%s\n\n%s\n%s\n" "$PPID" "$(pv_host)" "$(date +%s)" > "$AIGI_STATE_DIR/lock/owner"; if pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; then echo WROTE; else echo REFUSED; fi'
grep -q REFUSED "$LT/nops/out" \
  && ok "ledger: with no usable ps, a live holder still refuses (fails closed)" \
  || bad "ledger: with no usable ps, a live holder still refuses (fails closed)"

# Killed mid-acquire: a lock dir with no owner file, over a minute old, is reclaimed.
lt noowner 'mkdir -p "$AIGI_STATE_DIR/lock"; touch -t 200001010000 "$AIGI_STATE_DIR/lock"; pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; echo "A=$PV_ACTION"'
grep -q 'A=created' "$LT/noowner/out" \
  && ok "ledger: a lock left with no owner (killed mid-acquire) is reclaimed" \
  || bad "ledger: a lock left with no owner (killed mid-acquire) is reclaimed"

# The takeover race: two writers start against one stale lock. Each logs when
# it holds the lock and when it lets go; held periods must never overlap.
race_ok=1
for i in 1 2 3 4 5; do
  rh="$LT/race$i"; mkdir -p "$rh/state/lock"
  printf '999999\nx\n%s\n%s\n' "$(hostname 2>/dev/null | cut -d. -f1 | tr '[:upper:]' '[:lower:]')" "$(date +%s)" > "$rh/state/lock/owner"
  for w in a b; do
    # shellcheck disable=SC2030,SC2031
    ( export AIGI_STATE_DIR="$rh/state"
      # shellcheck source=lib/preserve.sh
      . "$LEDGER_LIB"
      if pv_lock 2>/dev/null; then echo "in $w" >> "$rh/log"; sleep 1; echo "out $w" >> "$rh/log"; rm -rf "$rh/state/lock"; fi ) &
  done
  wait
  # Valid: in X, out X, (in Y, out Y). Invalid: two "in" lines in a row.
  awk '/^in/ { if (held) bad = 1; held = 1 } /^out/ { held = 0 } END { exit bad }' "$rh/log" 2>/dev/null || race_ok=0
  [ "$(grep -c '^in' "$rh/log" 2>/dev/null)" -ge 1 ] || race_ok=0
done
[ "$race_ok" = 1 ] \
  && ok "ledger: two writers racing for one stale lock never hold it at once (5 runs)" \
  || bad "ledger: two writers racing for one stale lock never hold it at once (5 runs)"

# A symlink that appears between the check and the write is replaced, never written through.
lt putlink 'printf "dotfile\n" > "$HOME/target"; ln -s "$HOME/target" "$HOME/d.md"; pv_put "$PV_REPO/roles/r.md" "$HOME/d.md"; echo done'
{ [ "$(cat "$LT/putlink/target")" = "dotfile" ] && [ ! -L "$LT/putlink/d.md" ]; } \
  && ok "ledger: the write itself (rename) never writes through a symlink" \
  || bad "ledger: the write itself (rename) never writes through a symlink"

lt pathid 'id="$(pv_pathid "/a/very/deep/$(printf "x%.0s" $(seq 1 300))/file.md")"; echo "ID=$id"'
grep -Eq '^ID=[0-9a-f]{16}$' "$LT/pathid/out" \
  && ok "ledger: path-ids are 16 hex chars however deep the path (NAME_MAX-safe)" \
  || bad "ledger: path-ids are 16 hex chars however deep the path (NAME_MAX-safe)"

# Role ports are generated, never committed: a stale-but-pristine port is
# recognized by re-rendering at historical commits, not flagged as an edit.
PFX="$LT/portrepo"; mkdir -p "$PFX/roles"
printf '#!/usr/bin/env bash\nmkdir -p roles/codex\ncp roles/r.md roles/codex/r.toml\n' > "$PFX/render-roles.sh"; chmod +x "$PFX/render-roles.sh"
printf 'p1\n' > "$PFX/roles/r.md"; git -C "$PFX" init -q; git -C "$PFX" add -A; git -C "$PFX" -c user.name=t -c user.email=t@t commit -qm p1
printf 'p2\n' > "$PFX/roles/r.md"; git -C "$PFX" -c user.name=t -c user.email=t@t commit -qam p2
lt ports 'export PV_REPO="'"$PFX"'"; printf "p1\n" > "$HOME/old.toml"; printf "hand\n" > "$HOME/mine.toml"; printf "p2\n" > "$HOME/new"
  pv_write role "$HOME/new" "$HOME/old.toml" render:roles; echo "A=$PV_ACTION"; pv_write role "$HOME/new" "$HOME/mine.toml" render:roles; echo "B=$PV_ACTION"'
{ grep -q 'A=updated' "$LT/ports/out" && grep -q 'B=replaced-custom' "$LT/ports/out"; } \
  && ok "ledger: a stale role port is recognized from re-rendered history; an edited one isn't" \
  || bad "ledger: a stale role port is recognized from re-rendered history; an edited one isn't"

# Real writers, end to end, in a throwaway HOME. Roles used to be overwritten
# with no backup at all (install-roles.sh); now the edit survives in preserved/.
RH="$LT/roles-home"; mkdir -p "$RH"
HOME="$RH" bash "$DIR/install-roles.sh" claude >/dev/null 2>&1
printf '\nmy local rule\n' >> "$RH/.claude/agents/refuter.md"
HOME="$RH" bash "$DIR/install-roles.sh" claude > "$LT/roles.out" 2>&1
{ cmp -s "$DIR/roles/refuter.md" "$RH/.claude/agents/refuter.md" \
  && grep -lq 'my local rule' "$RH/.ai/install-state/preserved/"* 2>/dev/null \
  && grep -q 'replaced your edited' "$LT/roles.out"; } \
  && ok "install-roles: an edited role is preserved, then reinstalled (no more silent overwrite)" \
  || bad "install-roles: an edited role is preserved, then reinstalled (no more silent overwrite)"
HOME="$RH" bash "$DIR/install-roles.sh" claude > "$LT/roles2.out" 2>&1
grep -q 'roles already current' "$LT/roles2.out" \
  && ok "install-roles: a second run changes nothing" \
  || bad "install-roles: a second run changes nothing"

# Playbooks: an edited playbook in a toggled-off section is saved, not just deleted.
PH="$LT/pb-home"; mkdir -p "$PH"
HOME="$PH" AIGI_NO_USER_ENV=1 bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
printf '\nmy playbook note\n' >> "$PH/.ai/orchestration.md"
HOME="$PH" AIGI_NO_USER_ENV=1 INC_ORCHESTRATION=n bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
{ [ ! -e "$PH/.ai/orchestration.md" ] && grep -lq 'my playbook note' "$PH/.ai/install-state/preserved/"* 2>/dev/null; } \
  && ok "customize --global: an edited playbook is preserved when its section is toggled off" \
  || bad "customize --global: an edited playbook is preserved when its section is toggled off"

# lm: another tool's `lm` binary is never replaced.
LH="$LT/lm-home"; mkdir -p "$LH/.local/bin"
printf '#!/bin/sh\necho someone-elses-lm\n' > "$LH/.local/bin/lm"
HOME="$LH" AIGI_NO_USER_ENV=1 INC_LOCAL_MODELS=y AIGI_NO_PROBE=1 bash "$CUSTOMIZE" --global --yes > "$LT/lm.out" 2>&1
{ grep -q 'someone-elses-lm' "$LH/.local/bin/lm" && grep -q 'is not ours' "$LT/lm.out"; } \
  && ok "customize --global: a foreign lm binary is left alone" \
  || bad "customize --global: a foreign lm binary is left alone"
HOME="$RH" bash "$DIR/install-roles.sh" codex >/dev/null 2>&1
printf '\n# my codex tweak\n' >> "$RH/.codex/agents/refuter.toml"
HOME="$RH" bash "$DIR/install-roles.sh" codex > "$LT/codex.out" 2>&1
{ cmp -s "$DIR/roles/codex/refuter.toml" "$RH/.codex/agents/refuter.toml" \
  && grep -lq 'my codex tweak' "$RH/.ai/install-state/preserved/"* 2>/dev/null; } \
  && ok "install-roles: an edited Codex port is preserved, then reinstalled" \
  || bad "install-roles: an edited Codex port is preserved, then reinstalled"

# Playbook edited while its section stays on: preserved, then replaced.
printf '\nmy web note\n' >> "$PH/.ai/web-preview.md"
HOME="$PH" AIGI_NO_USER_ENV=1 bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
{ cmp -s "$DIR/playbooks/web-preview.md" "$PH/.ai/web-preview.md" \
  && grep -lq 'my web note' "$PH/.ai/install-state/preserved/"* 2>/dev/null; } \
  && ok "customize --global: an edited playbook is preserved, then reinstalled" \
  || bad "customize --global: an edited playbook is preserved, then reinstalled"

# Our own lm, edited: preserved, then reinstalled executable.
LO="$LT/lm-own"; mkdir -p "$LO"
HOME="$LO" AIGI_NO_USER_ENV=1 INC_LOCAL_MODELS=y AIGI_NO_PROBE=1 bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
printf '\n# my lm tweak\n' >> "$LO/.local/bin/lm"
HOME="$LO" AIGI_NO_USER_ENV=1 INC_LOCAL_MODELS=y AIGI_NO_PROBE=1 bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
{ cmp -s "$DIR/lm" "$LO/.local/bin/lm" && [ -x "$LO/.local/bin/lm" ] \
  && grep -lq 'my lm tweak' "$LO/.ai/install-state/preserved/"* 2>/dev/null; } \
  && ok "customize --global: our own edited lm is preserved, then reinstalled executable" \
  || bad "customize --global: our own edited lm is preserved, then reinstalled executable"

# Antigravity hook wrappers (generated by install-hooks.sh).
AH="$LT/ag-home"; mkdir -p "$AH/.gemini/antigravity-cli"
HOME="$AH" bash "$DIR/install-hooks.sh" antigravity >/dev/null 2>&1
printf '\n# my wrapper tweak\n' >> "$AH/.gemini/antigravity-cli/hooks/guard-bash.ag.sh"
HOME="$AH" bash "$DIR/install-hooks.sh" antigravity >/dev/null 2>&1
{ ! grep -q 'my wrapper tweak' "$AH/.gemini/antigravity-cli/hooks/guard-bash.ag.sh" \
  && [ -x "$AH/.gemini/antigravity-cli/hooks/guard-bash.ag.sh" ] \
  && grep -lq 'my wrapper tweak' "$AH/.ai/install-state/preserved/"* 2>/dev/null; } \
  && ok "install-hooks: an edited Antigravity wrapper is preserved, then regenerated" \
  || bad "install-hooks: an edited Antigravity wrapper is preserved, then regenerated"

# install.sh --unlock clears a stuck lock.
UH="$LT/unlock"; mkdir -p "$UH/.ai/install-state/lock"
HOME="$UH" bash "$DIR/install.sh" --unlock >/dev/null 2>&1
[ ! -e "$UH/.ai/install-state/lock" ] \
  && ok "install.sh --unlock clears a stuck install-state lock" \
  || bad "install.sh --unlock clears a stuck install-state lock"

# The sweep CLI (install-hooks.sh) was copied over with no backup.
SH="$LT/sweep-home"; mkdir -p "$SH/.claude"
HOME="$SH" bash "$DIR/install-hooks.sh" claude >/dev/null 2>&1
printf '\n# my tweak\n' >> "$SH/.ai/worktree-sweep.sh"
HOME="$SH" bash "$DIR/install-hooks.sh" claude >/dev/null 2>&1
{ cmp -s "$DIR/hooks/worktree-reap.sh" "$SH/.ai/worktree-sweep.sh" && [ -x "$SH/.ai/worktree-sweep.sh" ] \
  && grep -lq 'my tweak' "$SH/.ai/install-state/preserved/"* 2>/dev/null; } \
  && ok "install-hooks: an edited sweep CLI is preserved, then reinstalled executable" \
  || bad "install-hooks: an edited sweep CLI is preserved, then reinstalled executable"

# ---- install ledger, phases 2–3: decide, don't only save ----------------------
# Pins, [k] that sticks, the attended resolve pass, the append-merge and its
# canonical part, --plan/--resolve, last-run.json, ~/AGENTS.md's own rungs and
# routing, the AI check's advice, and the uninstall side (PLAN §18).
echo "== install ledger, phases 2–3 =="

lt pin 'pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; printf "mine\n" > "$HOME/d.md"; pv_do_pin "$HOME/d.md" 2>/dev/null; pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; echo "A=$PV_ACTION V=$PV_VERDICT"'
{ grep -q 'A=pinned V=PINNED' "$LT/pin/out" && grep -qx 'mine' "$LT/pin/d.md"; } \
  && ok "ledger: a pinned file is never written" \
  || bad "ledger: a pinned file is never written"

# [k] holds until upstream changes again; then it's a question again (A5).
lt kept 'printf "v3\n" > "$HOME/v3"
  pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; printf "mine\n" > "$HOME/d.md"
  AIGI_ON_CONFLICT=keep pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; echo "A=$PV_ACTION"
  pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; echo "B=$PV_ACTION $PV_VERDICT"
  pv_write role "$HOME/v3" "$HOME/d.md" roles/r.md; echo "C=$PV_ACTION $PV_VERDICT"'
{ grep -q 'A=kept-custom' "$LT/kept/out" && grep -q 'B=kept KEPT' "$LT/kept/out" \
  && grep -q 'C=replaced-custom CUSTOM' "$LT/kept/out" && grep -qx v3 "$LT/kept/d.md"; } \
  && ok "ledger: [k] keeps your file until upstream changes again, then it's CUSTOM" \
  || bad "ledger: [k] keeps your file until upstream changes again, then it's CUSTOM"

# Attended: the edited file is parked untouched, then asked about once.
lt park 'printf "r\n" > "$HOME/ans"; export AIGI_UNATTENDED=0 AIGI_TTY="$HOME/ans"
  pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; printf "mine\n" > "$HOME/d.md"
  pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; echo "A=$PV_ACTION"; echo "D=$(cat "$HOME/d.md")"
  pv_resolve_parked; echo "E=$(cat "$HOME/d.md")"'
{ grep -q 'A=parked' "$LT/park/out" && grep -q 'D=mine' "$LT/park/out" && grep -q 'E=v2' "$LT/park/out" \
  && grep -lq '^mine$' "$(st park)/preserved/"* 2>/dev/null; } \
  && ok "ledger: attended, an edited file is left alone until the end-of-run question" \
  || bad "ledger: attended, an edited file is left alone until the end-of-run question"

lt parkx 'printf "x\n" > "$HOME/ans"; export AIGI_UNATTENDED=0 AIGI_TTY="$HOME/ans"
  pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; printf "mine\n" > "$HOME/d.md"
  pv_write role "$PV_REPO/roles/r.md" "$HOME/d.md" roles/r.md; pv_resolve_parked; echo "E=$(cat "$HOME/d.md")"
  tail -n 1 "$AIGI_RUN_DIR/actions.tsv" | cut -f4'
{ grep -q 'E=mine' "$LT/parkx/out" && grep -qx 'left' "$LT/parkx/out"; } \
  && ok "ledger: [x] stops and leaves the edited file untouched" \
  || bad "ledger: [x] stops and leaves the edited file untouched"

# Append: your lines land in one preserved block, carried forward byte for
# byte, never nested; editing inside the block doesn't make the file yours.
lt append 'printf "v2\nb\nc\nd\n" > "$HOME/s"; printf "v3\nb\nc\nd\n" > "$HOME/v3"; export AIGI_ON_CONFLICT=append
  pv_write playbook "$HOME/s" "$HOME/p.md"; printf "my line\n" >> "$HOME/p.md"
  pv_write playbook "$HOME/s" "$HOME/p.md"; echo "A=$PV_ACTION"
  pv_write playbook "$HOME/s" "$HOME/p.md"; echo "B=$PV_ACTION"
  sed -i.x "s/my line/my edited line/" "$HOME/p.md"
  pv_write playbook "$HOME/v3" "$HOME/p.md"; echo "C=$PV_ACTION $PV_VERDICT"
  printf "another\n" >> "$HOME/v3"; pv_write playbook "$HOME/v3" "$HOME/p.md"; echo "D=$PV_ACTION"'
{ grep -q 'A=appended' "$LT/append/out" && grep -q 'B=current' "$LT/append/out" \
  && grep -q 'C=updated OURS' "$LT/append/out" && grep -q 'D=updated' "$LT/append/out" \
  && [ "$(grep -c 'aigi:preserved begin' "$LT/append/p.md")" = 1 ] \
  && grep -qx 'my edited line' "$LT/append/p.md" && [ "$(head -n 1 "$LT/append/p.md")" = v3 ]; } \
  && ok "ledger: [a] keeps your lines in one preserved block that later installs carry forward" \
  || bad "ledger: [a] keeps your lines in one preserved block that later installs carry forward"

lt damaged 'printf "v2\nb\nc\nd\n" > "$HOME/s"; export AIGI_ON_CONFLICT=append
  pv_write playbook "$HOME/s" "$HOME/p.md"; printf "my line\n" >> "$HOME/p.md"
  pv_write playbook "$HOME/s" "$HOME/p.md"; echo "A=$PV_ACTION"
  printf "<!-- aigi:preserved begin — stray\n" >> "$HOME/p.md"; echo "V=$(pv_classify "$HOME/p.md" "" playbook "$HOME/s")"'
{ grep -q 'A=appended' "$LT/damaged/out" && grep -q 'V=CUSTOM' "$LT/damaged/out"; } \
  && ok "ledger: a damaged preserved block is CUSTOM, never guessed at" \
  || bad "ledger: a damaged preserved block is CUSTOM, never guessed at"

lt roleappend 'printf "v2\nb\nc\nd\n" > "$HOME/s"; export AIGI_ON_CONFLICT=append
  pv_write role "$HOME/s" "$HOME/d.md"; printf "my line\n" >> "$HOME/d.md"
  pv_write role "$HOME/s" "$HOME/d.md"; echo "A=$PV_ACTION"'
{ grep -q 'A=replaced-custom' "$LT/roleappend/out" && grep -q "can't append" "$LT/roleappend/out"; } \
  && ok "ledger: a role file never takes an appended block (D6) — it's replaced, yours saved" \
  || bad "ledger: a role file never takes an appended block (D6) — it's replaced, yours saved"

# model-routing.md: the generated block is /update-model-routing's, so a
# changed block doesn't make the file look edited (E6).
lt routing 'printf "stable v1\n<!-- generated:begin -->\nmodels A\n<!-- generated:end -->\n" > "$HOME/new1"
  pv_write model-routing "$HOME/new1" "$HOME/mr.md"
  printf "stable v1\n<!-- generated:begin -->\nmodels B\n<!-- generated:end -->\n" > "$HOME/mr.md"
  printf "stable v2\n<!-- generated:begin -->\nmodels B\n<!-- generated:end -->\n" > "$HOME/new2"
  pv_write model-routing "$HOME/new2" "$HOME/mr.md"; echo "A=$PV_ACTION $PV_VERDICT"'
grep -q 'A=updated OURS' "$LT/routing/out" \
  && ok "ledger: model-routing.md is compared outside its generated block" \
  || bad "ledger: model-routing.md is compared outside its generated block"

# The AI check is advice: a stub says "not covered", the run still replaces
# unattended (D7), and the verdict is recorded. Malformed output is no verdict.
AISTUB="$LT/ai-stub.sh"
cat > "$AISTUB" <<'STUB'
cat >/dev/null
echo '{"covered": false, "reason": "stub says no"}'
STUB
lt aicheck 'export AIGI_AI_CHECK=command AIGI_AI_CHECK_CMD="sh '"$AISTUB"'"
  printf "v2\nb\nc\nd\n" > "$HOME/s"
  pv_write playbook "$HOME/s" "$HOME/p.md"; printf "my line\n" >> "$HOME/p.md"
  pv_write playbook "$HOME/s" "$HOME/p.md"; echo "A=$PV_ACTION AI=$PV_AI"
  AIGI_AI_CHECK_CMD="echo not json"; printf "again\n" >> "$HOME/p.md"
  pv_write playbook "$HOME/s" "$HOME/p.md"; echo "B=$PV_AI"'
{ grep -q 'A=replaced-custom AI=not covered: stub says no' "$LT/aicheck/out" \
  && grep -q 'B=skipped: no valid verdict' "$LT/aicheck/out"; } \
  && ok "ledger: the AI check only advises, and malformed output counts as no verdict" \
  || bad "ledger: the AI check only advises, and malformed output counts as no verdict"

lt contra 'export AIGI_ON_CONFLICT=append
  printf -- "# P\n\n- **Cite sources.** Always.\n- b\n" > "$HOME/new1"; printf -- "# P\n\n- **Cite sources.** Sometimes.\n- b\n" > "$HOME/new2"
  pv_write playbook "$HOME/new1" "$HOME/p.md"; printf -- "- **Cite sources.** With file:line.\n" >> "$HOME/p.md"
  pv_write playbook "$HOME/new2" "$HOME/p.md"; echo "A=$PV_ACTION"'
{ grep -q 'A=appended' "$LT/contra/out" && grep -q 'also appears in the new version' "$LT/contra/out"; } \
  && ok "ledger: a kept rule whose headline the new version rewords is flagged" \
  || bad "ledger: a kept rule whose headline the new version rewords is flagged"

# ~/AGENTS.md: SHIPPED means "a render of a recent commit with today's
# layers", and [a] routes your lines into extras.local.md, then re-renders.
RX="$LT/render-repo"; mkdir -p "$RX"; git -C "$RX" init -q
printf '#!/bin/sh\n[ "$1" = --print ] && { cat "$(dirname "$0")/template.md"; [ -f "$(dirname "$0")/extras.local.md" ] && cat "$(dirname "$0")/extras.local.md"; }\nexit 0\n' > "$RX/customize.sh"
chmod +x "$RX/customize.sh"
printf 'rules v1\nb\nc\nd\n' > "$RX/template.md"; git -C "$RX" add -A; git -C "$RX" -c user.name=t -c user.email=t@t commit -qm v1
printf 'rules v2\nb\nc\nd\n' > "$RX/template.md"; git -C "$RX" -c user.name=t -c user.email=t@t commit -qam v2
lt render 'export PV_REPO="'"$RX"'" DIR="'"$RX"'" PV_LAYERS_DIR="'"$RX"'"
  printf "rules v1\nb\nc\nd\n" > "$HOME/A.md"; (cd "$PV_REPO" && ./customize.sh --print) > "$HOME/new"
  pv_write render "$HOME/new" "$HOME/A.md" render:agents; echo "A=$PV_ACTION $PV_VERDICT"
  printf "my rule\n" >> "$HOME/A.md"; AIGI_ON_CONFLICT=append pv_write render "$HOME/new" "$HOME/A.md" render:agents
  echo "B=$PV_ACTION"; echo "X=$(grep -c "my rule" "$PV_REPO/extras.local.md")"; echo "R=$(grep -c "my rule" "$HOME/A.md")"'
{ grep -q 'A=updated SHIPPED' "$LT/render/out" && grep -q 'B=appended' "$LT/render/out" \
  && grep -q 'X=1' "$LT/render/out" && grep -q 'R=1' "$LT/render/out" \
  && grep -q '^## Preserved from ~/AGENTS.md' "$RX/extras.local.md"; } \
  && ok "ledger: ~/AGENTS.md recognizes an old render, and [a] moves your lines into extras.local.md" \
  || bad "ledger: ~/AGENTS.md recognizes an old render, and [a] moves your lines into extras.local.md"

# From a linked worktree, routed lines land in the primary checkout's extras,
# which that worktree's render can't see — so ~/AGENTS.md is left alone rather
# than recorded as carrying lines it doesn't.
git -C "$RX" worktree add -q "$LT/render-wt" 2>/dev/null
lt renderwt 'export PV_REPO="'"$LT/render-wt"'" DIR="'"$LT/render-wt"'" PV_LAYERS_DIR="'"$LT/render-wt"'"
  (cd "$DIR" && ./customize.sh --print) > "$HOME/new"; cp "$HOME/new" "$HOME/A.md"
  pv_write render "$HOME/new" "$HOME/A.md" render:agents; printf "wt rule\n" >> "$HOME/A.md"
  AIGI_ON_CONFLICT=append pv_write render "$HOME/new" "$HOME/A.md" render:agents; echo "B=$PV_ACTION"
  echo "R=$(grep -c "wt rule" "$HOME/A.md")"'
{ grep -q 'B=failed' "$LT/renderwt/out" && grep -q 'R=1' "$LT/renderwt/out" \
  && grep -qx 'wt rule' "$RX/extras.local.md" && grep -q 'renders without them' "$LT/renderwt/out"; } \
  && ok "ledger: routed lines a worktree's render can't see leave ~/AGENTS.md alone, and say why" \
  || bad "ledger: routed lines a worktree's render can't see leave ~/AGENTS.md alone, and say why"

# End to end, through install.sh: a second run changes nothing, --plan writes
# nothing, last-run.json is valid, and --resolve --append brings a replaced
# edit back.
EH="$LT/e2e"; mkdir -p "$EH/.gemini/antigravity-cli"   # as on a machine with agy installed
HOME="$EH" bash "$DIR/install.sh" --yes >/dev/null 2>&1
HOME="$EH" bash "$DIR/install.sh" --yes >/dev/null 2>&1
{ jq -e '.files | length > 0' "$EH/.ai/install-state/last-run.json" >/dev/null 2>&1 \
  && [ "$(jq '[.files[] | select(.action != "current")] | length' "$EH/.ai/install-state/last-run.json")" = 0 ]; } \
  && ok "install.sh: a second --yes changes no ledgered file, and last-run.json says so" \
  || bad "install.sh: a second --yes changes no ledgered file, and last-run.json says so"
find "$EH" -exec ls -ld {} + 2>/dev/null | sort > "$LT/e2e.before"
HOME="$EH" bash "$DIR/install.sh" --plan > "$LT/e2e.plan" 2>&1
find "$EH" -exec ls -ld {} + 2>/dev/null | sort > "$LT/e2e.after"
{ cmp -s "$LT/e2e.before" "$LT/e2e.after" && grep -q 'CURRENT  current' "$LT/e2e.plan"; } \
  && ok "install.sh --plan classifies every ledgered file and writes nothing" \
  || bad "install.sh --plan classifies every ledgered file and writes nothing"
printf '\n- **My playbook rule.** Mine.\n' >> "$EH/.ai/orchestration.md"
HOME="$EH" bash "$DIR/install.sh" --yes > "$LT/e2e.r3" 2>&1
{ ! grep -q 'My playbook rule' "$EH/.ai/orchestration.md" \
  && grep -q "recover: ./install.sh --resolve $EH/.ai/orchestration.md --append" "$LT/e2e.r3" \
  && jq -e --arg p "$EH/.ai/orchestration.md" '.files[] | select(.path == $p) | .action == "replaced-custom" and (.recover | test("--append"))' \
       "$EH/.ai/install-state/last-run.json" >/dev/null 2>&1; } \
  && ok "install.sh --yes: an edited playbook is replaced and its recovery command is reported" \
  || bad "install.sh --yes: an edited playbook is replaced and its recovery command is reported"
HOME="$EH" bash "$DIR/install.sh" --resolve "$EH/.ai/orchestration.md" --append >/dev/null 2>&1
HOME="$EH" bash "$DIR/install.sh" --resolve --append > "$LT/e2e.r4" 2>&1
{ grep -q 'My playbook rule' "$EH/.ai/orchestration.md" && grep -q 'aigi:preserved begin' "$EH/.ai/orchestration.md" \
  && grep -q 'Nothing to resolve' "$LT/e2e.r4"; } \
  && ok "install.sh --resolve --append adds a replaced edit back, once" \
  || bad "install.sh --resolve --append adds a replaced edit back, once"
HOME="$EH" bash "$DIR/install.sh" --yes >/dev/null 2>&1
[ "$(jq -r --arg p "$EH/.ai/orchestration.md" '.files[] | select(.path == $p) | .action' "$EH/.ai/install-state/last-run.json")" = current ] \
  && ok "install.sh: a resolved append stays put on the next install" \
  || bad "install.sh: a resolved append stays put on the next install"

# Hook scripts are ledgered now: an edit is preserved, not a rotating .bak.*.
printf '\n# my hook tweak\n' >> "$EH/.claude/hooks/guard-bash.sh"
printf '#!/bin/sh\n# my own scorecard\n' > "$EH/.claude/hooks/scorecard.sh"
HOME="$EH" bash "$DIR/install-hooks.sh" claude >/dev/null 2>&1
{ cmp -s "$DIR/hooks/guard-bash.sh" "$EH/.claude/hooks/guard-bash.sh" && [ -x "$EH/.claude/hooks/guard-bash.sh" ] \
  && ! ls "$EH/.claude/hooks/"guard-bash.sh.bak.* >/dev/null 2>&1 && [ ! -e "$EH/.claude/hooks/scorecard.sh" ] \
  && grep -lq 'my hook tweak' "$EH/.ai/install-state/preserved/"* && grep -lq 'my own scorecard' "$EH/.ai/install-state/preserved/"*; } \
  && ok "install-hooks: edited and retired hook scripts go through the ledger" \
  || bad "install-hooks: edited and retired hook scripts go through the ledger"

# E1: no terminal and no --yes is unattended, and an unattended run renders.
NH="$LT/notty"; mkdir -p "$NH"
HOME="$NH" AIGI_UNATTENDED=1 bash "$CUSTOMIZE" --global > "$LT/notty.out" 2>&1
{ [ -s "$NH/AGENTS.md" ] && ! grep -q 'Aborted' "$LT/notty.out"; } \
  && ok "customize --global: an unattended run without --yes renders instead of aborting" \
  || bad "customize --global: an unattended run without --yes renders instead of aborting"

# Uninstall: an edited role is preserved before removal, and a pointer gets
# back the original we first displaced.
UH2="$LT/uninst"; mkdir -p "$UH2/.codex"; printf 'my own codex notes\n' > "$UH2/.codex/AGENTS.md"
HOME="$UH2" bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
HOME="$UH2" bash "$DIR/install-roles.sh" claude >/dev/null 2>&1
printf '\nmy role note\n' >> "$UH2/.claude/agents/refuter.md"
HOME="$UH2" bash "$DIR/uninstall.sh" claude codex > "$LT/uninst.out" 2>&1
{ [ ! -e "$UH2/.claude/agents/refuter.md" ] && grep -lq 'my role note' "$UH2/.ai/install-state/preserved/"* \
  && grep -qx 'my own codex notes' "$UH2/.codex/AGENTS.md" && grep -q 'original it had before the install' "$LT/uninst.out"; } \
  && ok "uninstall: edited roles are preserved, and a pointer path gets its first original back" \
  || bad "uninstall: edited roles are preserved, and a pointer path gets its first original back"

# Regressions from the in-tool refuter of phases 2–3 (2026-10-18), one per
# confirmed break.
# 1. A checkout with only some layers must not drop the others, or delete the
#    only saved copy of extras.local.md.
LA="$LT/layers-a"; LB="$LT/layers-b"; LHM="$LT/layers-home"; mkdir -p "$LA" "$LB" "$LHM"
(cd "$DIR" && git ls-files -z | xargs -0 tar -cf -) | tar -xf - -C "$LA"
cp -R "$LA/." "$LB/"
printf 'NAME="Layer Test"\n' > "$LA/my-context.env"; cp "$LA/my-context.env" "$LB/my-context.env"
printf '## Mine\n\nUNIQUE-EXTRAS-LINE-42\n' > "$LA/extras.local.md"
( unset AIGI_NO_USER_ENV; HOME="$LHM" bash "$LA/customize.sh" --global --yes ) >/dev/null 2>&1
rm -rf "$LA"
( unset AIGI_NO_USER_ENV; HOME="$LHM" bash "$LB/customize.sh" --global --yes ) > "$LT/layers.out" 2>&1
{ grep -q 'UNIQUE-EXTRAS-LINE-42' "$LHM/AGENTS.md" && grep -q 'UNIQUE-EXTRAS-LINE-42' "$LHM/.ai/install-state/layers/extras.local.md" \
  && grep -q 'has no extras.local.md' "$LT/layers.out"; } \
  && ok "customize --global: a checkout missing one layer uses its saved copy, never deletes it" \
  || bad "customize --global: a checkout missing one layer uses its saved copy, never deletes it"

# 2. --resolve --keep must not overwrite an edit made inside the preserved block.
lt keepblock 'printf "v2\nb\nc\nd\n" > "$HOME/s"
  pv_write playbook "$HOME/s" "$HOME/p.md"; printf "L1\n" >> "$HOME/p.md"
  AIGI_ON_CONFLICT=append pv_write playbook "$HOME/s" "$HOME/p.md"
  awk "NR == 1 { print; print \"OUTSIDE\"; next } { print }" "$HOME/p.md" > "$HOME/p.t" && mv "$HOME/p.t" "$HOME/p.md"
  pv_write playbook "$HOME/s" "$HOME/p.md"; echo "A=$PV_ACTION"
  awk "{ sub(/^L1$/, \"B2\"); print }" "$HOME/p.md" > "$HOME/p.t" && mv "$HOME/p.t" "$HOME/p.md"
  pv_resolve_cmd keep "$HOME/p.md"; echo "B=$(grep -c "^B2$" "$HOME/p.md")"'
{ grep -q 'A=replaced-custom' "$LT/keepblock/out" && grep -q 'B=1' "$LT/keepblock/out" \
  && grep -q 'changed since it was replaced' "$LT/keepblock/out"; } \
  && ok "ledger: --resolve --keep refuses to overwrite an edit inside the preserved block" \
  || bad "ledger: --resolve --keep refuses to overwrite an edit inside the preserved block"

# 3. Lines an install already appended aren't appended again by --resolve.
lt noduplicate 'printf "v2\nb\nc\nd\n" > "$HOME/s"
  pv_write playbook "$HOME/s" "$HOME/p.md"; printf "DOUBLE-ME\n" >> "$HOME/p.md"
  AIGI_ON_CONFLICT=append pv_write playbook "$HOME/s" "$HOME/p.md"
  pv_resolve_cmd append; echo "N=$(grep -c "^DOUBLE-ME$" "$HOME/p.md")"'
grep -q 'N=1' "$LT/noduplicate/out" \
  && ok "ledger: --resolve --append doesn't double lines an install already kept" \
  || bad "ledger: --resolve --append doesn't double lines an install already kept"

# 4. After an uninstall the settings file is still known, so a rule you add
#    yourself isn't adopted as ours by the reinstall and removed by the next uninstall.
SLH="$LT/sl-known"; mkdir -p "$SLH/.claude"
SLK="$(jq -r '.permissions | to_entries[0].key' "$DIR/settings-permissions.snippet.json")"
SLV="$(jq -r '.permissions | to_entries[0].value[0]' "$DIR/settings-permissions.snippet.json")"
HOME="$SLH" bash "$DIR/install-settings.sh" claude >/dev/null 2>&1
HOME="$SLH" bash "$DIR/uninstall.sh" claude >/dev/null 2>&1
jq --arg k "$SLK" --arg v "$SLV" '.permissions[$k] = [$v]' "$SLH/.claude/settings.json" > "$SLH/s.t" 2>/dev/null \
  || printf '{"permissions":{"%s":["%s"]}}\n' "$SLK" "$SLV" > "$SLH/s.t"
mv "$SLH/s.t" "$SLH/.claude/settings.json"
HOME="$SLH" bash "$DIR/install-settings.sh" claude >/dev/null 2>&1
HOME="$SLH" bash "$DIR/uninstall.sh" claude >/dev/null 2>&1
jq -e --arg k "$SLK" --arg v "$SLV" '.permissions[$k] | index($v) != null' "$SLH/.claude/settings.json" >/dev/null 2>&1 \
  && ok "settings ledger: a rule you add after an uninstall survives reinstall + uninstall" \
  || bad "settings ledger: a rule you add after an uninstall survives reinstall + uninstall"

# 5. An uninstall hands back the original you had before THAT install.
OH="$LT/orig-home"; mkdir -p "$OH/.claude"; printf 'ORIGINAL-A\n' > "$OH/.claude/CLAUDE.md"
HOME="$OH" bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1; HOME="$OH" bash "$DIR/uninstall.sh" claude >/dev/null 2>&1
o1="$(cat "$OH/.claude/CLAUDE.md" 2>/dev/null)"; printf 'NEWER-A2\n' > "$OH/.claude/CLAUDE.md"
HOME="$OH" bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1; HOME="$OH" bash "$DIR/uninstall.sh" claude >/dev/null 2>&1
{ [ "$o1" = ORIGINAL-A ] && grep -qx 'NEWER-A2' "$OH/.claude/CLAUDE.md"; } \
  && ok "uninstall: a pointer gets back the file it held before the latest install" \
  || bad "uninstall: a pointer gets back the file it held before the latest install"

# 6. A command file named like a skill is saved before install-skills removes it.
CH="$LT/cmd-home"; mkdir -p "$CH/.claude/commands"; printf 'my own ship notes\n' > "$CH/.claude/commands/ship.md"
HOME="$CH" bash "$DIR/install-skills.sh" claude >/dev/null 2>&1
{ [ ! -e "$CH/.claude/commands/ship.md" ] && grep -lq 'my own ship notes' "$CH/.ai/install-state/preserved/"* 2>/dev/null; } \
  && ok "install-skills: your command file with a skill's name is saved before it's removed" \
  || bad "install-skills: your command file with a skill's name is saved before it's removed"

# Regressions from the cross-family (agy) review of phases 2–3 (2026-10-18).
# a. last-run.json strings escape a backslash, so a path with one stays valid JSON.
lt jsonesc 'printf "\"%s\"\n" "$(pv_json_str "a\\b\"c")" > "$HOME/j"'
[ "$(jq -r . "$LT/jsonesc/j" 2>/dev/null)" = 'a\b"c' ] \
  && ok "ledger: JSON strings escape backslashes and quotes" \
  || bad "ledger: JSON strings escape backslashes and quotes ($(cat "$LT/jsonesc/j" 2>/dev/null))"

# b. --resolve --append on a playbook with a preserved block adds the edit made
#    outside it back, and the block (carried through the replace) stays once.
lt appendblock 'printf "v2\nb\nc\nd\n" > "$HOME/s"
  pv_write playbook "$HOME/s" "$HOME/p.md"; printf "BLOCKLINE\n" >> "$HOME/p.md"
  AIGI_ON_CONFLICT=append pv_write playbook "$HOME/s" "$HOME/p.md"
  awk "NR == 1 { print; print \"OUTSIDE-EDIT\"; next } { print }" "$HOME/p.md" > "$HOME/p.t" && mv "$HOME/p.t" "$HOME/p.md"
  pv_write playbook "$HOME/s" "$HOME/p.md"; echo "A=$PV_ACTION O=$(grep -c "^OUTSIDE-EDIT$" "$HOME/p.md")"
  pv_resolve_cmd append "$HOME/p.md"
  echo "O2=$(grep -c "^OUTSIDE-EDIT$" "$HOME/p.md") B=$(grep -c "^BLOCKLINE$" "$HOME/p.md")"'
{ grep -q 'A=replaced-custom O=0' "$LT/appendblock/out" && grep -q 'O2=1 B=1' "$LT/appendblock/out"; } \
  && ok "ledger: --resolve --append restores an edit outside a playbook's preserved block" \
  || bad "ledger: --resolve --append restores an edit outside a playbook's preserved block"

# c. The install-policy queries read the saved layers too, so a checkout
#    without my-context.env doesn't quietly drop your INSTALL_ON_CONFLICT.
QHM="$LT/query-home"; mkdir -p "$QHM"
printf 'INSTALL_ON_CONFLICT="keep"\n' > "$LB/my-context.env"
( unset AIGI_NO_USER_ENV; HOME="$QHM" bash "$LB/customize.sh" --global --yes ) >/dev/null 2>&1
rm -f "$LB/my-context.env"
qv="$( unset AIGI_NO_USER_ENV; HOME="$QHM" bash "$LB/customize.sh" --on-conflict 2>"$LT/query.err" )"
{ [ "$qv" = keep ] && [ ! -s "$LT/query.err" ]; } \
  && ok "customize --on-conflict answers from the saved layers, quietly" \
  || bad "customize --on-conflict answers from the saved layers, quietly (got '$qv')"

# d. Where symlinks fail, ~/.codex/AGENTS.md is a copy; uninstall still knows
#    it's ours and hands back the original.
CXH="$LT/codex-copy"; mkdir -p "$CXH/.codex"; printf 'codex original\n' > "$CXH/.codex/AGENTS.md"
HOME="$CXH" bash "$CUSTOMIZE" --global --yes >/dev/null 2>&1
rm -f "$CXH/.codex/AGENTS.md"; cp "$CXH/AGENTS.md" "$CXH/.codex/AGENTS.md"
HOME="$CXH" bash "$DIR/uninstall.sh" codex >/dev/null 2>&1
grep -qx 'codex original' "$CXH/.codex/AGENTS.md" \
  && ok "uninstall: a copied Codex pointer is recognised and its original restored" \
  || bad "uninstall: a copied Codex pointer is recognised and its original restored"

# A resolve mode without --resolve is an error, not a silent full install.
HOME="$LT/flag-home" bash "$DIR/install.sh" --keep > "$LT/flag.out" 2>&1 && fk=0 || fk=1
{ [ "$fk" = 1 ] && grep -q 'only goes with --resolve' "$LT/flag.out" && [ ! -e "$LT/flag-home/AGENTS.md" ]; } \
  && ok "install.sh: --keep without --resolve is refused, not ignored" \
  || bad "install.sh: --keep without --resolve is refused, not ignored"

# ---- entries the harness didn't write -------------------------------------------
# A hooks file belongs to its user: handlers and matcher groups this repo never
# wrote must survive an install, a re-install and an uninstall, unchanged.
# Fixtures use an arbitrary tool path; no installed software is involved.
FH="$LT/foreign-hooks"; rm -rf "$FH"; mkdir -p "$FH"
FOREIGN_CMD='/usr/local/bin/some-tool hook'
OURS_RE='/(guard-paths|guard-bash|format-edited|log-tool|quality-nudge|worktree-reap|load-memory|autonomy-reminder|precompact-archive|log-session-end)(\.ag)?\.sh'
# fh_ours_gone <file>: none of our scripts is left wired.
fh_ours_gone() { ! jq -e --arg re "$OURS_RE" '[.. | .command? // empty | select(type == "string" and test($re))] | length > 0' "$1" >/dev/null 2>&1; }

# Codex: nested {matcher, hooks:[...]} groups, plus an event name we never use.
FHC="$FH/codex"; mkdir -p "$FHC/.codex"
CXG1="$(jq -nc --arg c "$FOREIGN_CMD" '{matcher:"Bash|SomeTool",hooks:[{type:"command",command:$c,timeout:5}]}')"
CXG2="$(jq -nc --arg c "$FOREIGN_CMD" '{hooks:[{type:"command",command:$c}]}')"
jq -n --argjson a "$CXG1" --argjson b "$CXG2" '{toolSetting:{keep:true},hooks:{PreToolUse:[$a],Stop:[$b],SomeToolEvent:[$b]}}' > "$FHC/.codex/hooks.json"
HOME="$FHC" bash "$DIR/install-hooks.sh" codex >/dev/null 2>&1
fc1="$(jq -c . "$FHC/.codex/hooks.json")"
HOME="$FHC" bash "$DIR/install-hooks.sh" codex >/dev/null 2>&1
fc2="$(jq -c . "$FHC/.codex/hooks.json")"
{ jq -e --argjson a "$CXG1" --argjson b "$CXG2" '
    ([.hooks.PreToolUse[] | select(. == $a)] | length == 1)
    and ([.hooks.Stop[] | select(. == $b)] | length == 1)
    and (.hooks.SomeToolEvent == [$b]) and (.toolSetting == {keep:true})' "$FHC/.codex/hooks.json" >/dev/null 2>&1 \
  && [ "$fc1" = "$fc2" ] && ! fh_ours_gone "$FHC/.codex/hooks.json"; } \
  && ok "install-hooks codex: a foreign handler, matcher group, event and top-level key survive install and re-install" \
  || bad "install-hooks codex: a foreign handler, matcher group, event and top-level key survive install and re-install"
HOME="$FHC" bash "$DIR/uninstall.sh" codex >/dev/null 2>&1
{ jq -e --argjson a "$CXG1" --argjson b "$CXG2" '
    .hooks == {PreToolUse:[$a],Stop:[$b],SomeToolEvent:[$b]} and (.toolSetting == {keep:true})' "$FHC/.codex/hooks.json" >/dev/null 2>&1 \
  && fh_ours_gone "$FHC/.codex/hooks.json"; } \
  && ok "uninstall codex: only our hooks leave; the foreign handler and groups remain as written" \
  || bad "uninstall codex: only our hooks leave; the foreign handler and groups remain as written"

# Cursor: flat entries (one with a matcher), a custom event, top-level version.
FHU="$FH/cursor"; mkdir -p "$FHU/.cursor"
CUE1="$(jq -nc --arg c "$FOREIGN_CMD" '{command:$c,matcher:"Shell",loop_limit:2}')"
CUE2="$(jq -nc --arg c "$FOREIGN_CMD" '{command:$c}')"
jq -n --argjson a "$CUE1" --argjson b "$CUE2" '{version:1,toolSetting:"x",hooks:{stop:[$a],beforeShellExecution:[$b],someToolEvent:[$b]}}' > "$FHU/.cursor/hooks.json"
HOME="$FHU" bash "$DIR/install-hooks.sh" cursor >/dev/null 2>&1
fu1="$(jq -c . "$FHU/.cursor/hooks.json")"
HOME="$FHU" bash "$DIR/install-hooks.sh" cursor >/dev/null 2>&1
fu2="$(jq -c . "$FHU/.cursor/hooks.json")"
{ jq -e --argjson a "$CUE1" --argjson b "$CUE2" '
    ([.hooks.stop[] | select(. == $a)] | length == 1)
    and ([.hooks.beforeShellExecution[] | select(. == $b)] | length == 1)
    and (.hooks.someToolEvent == [$b]) and .version == 1 and .toolSetting == "x"' "$FHU/.cursor/hooks.json" >/dev/null 2>&1 \
  && [ "$fu1" = "$fu2" ] && ! fh_ours_gone "$FHU/.cursor/hooks.json"; } \
  && ok "install-hooks cursor: foreign flat entries (with and without a matcher) survive install and re-install" \
  || bad "install-hooks cursor: foreign flat entries (with and without a matcher) survive install and re-install"
HOME="$FHU" bash "$DIR/uninstall.sh" cursor >/dev/null 2>&1
{ jq -e --argjson a "$CUE1" --argjson b "$CUE2" '
    .hooks == {stop:[$a],beforeShellExecution:[$b],someToolEvent:[$b]} and .toolSetting == "x"' "$FHU/.cursor/hooks.json" >/dev/null 2>&1 \
  && fh_ours_gone "$FHU/.cursor/hooks.json"; } \
  && ok "uninstall cursor: only our hooks leave; the foreign entries remain as written" \
  || bad "uninstall cursor: only our hooks leave; the foreign entries remain as written"

# Antigravity: top-level named hooks; ours are the aigi-* keys.
FHA="$FH/agy"; mkdir -p "$FHA/.gemini/antigravity-cli"
AGH="$(jq -nc --arg c "$FOREIGN_CMD" '{PreToolUse:[{matcher:"run_command",hooks:[{type:"command",command:$c,timeout:5}]}],PostToolUse:[{matcher:"*",hooks:[{type:"command",command:$c}]}]}')"
jq -n --argjson h "$AGH" '{"some-tool":$h}' > "$FHA/.gemini/antigravity-cli/hooks.json"
HOME="$FHA" bash "$DIR/install-hooks.sh" antigravity >/dev/null 2>&1
fa1="$(jq -c . "$FHA/.gemini/antigravity-cli/hooks.json")"
HOME="$FHA" bash "$DIR/install-hooks.sh" antigravity >/dev/null 2>&1
fa2="$(jq -c . "$FHA/.gemini/antigravity-cli/hooks.json")"
{ jq -e --argjson h "$AGH" '.["some-tool"] == $h and ([keys[] | select(startswith("aigi-"))] | length) > 0' "$FHA/.gemini/antigravity-cli/hooks.json" >/dev/null 2>&1 \
  && [ "$fa1" = "$fa2" ]; } \
  && ok "install-hooks antigravity: a foreign named hook survives install and re-install" \
  || bad "install-hooks antigravity: a foreign named hook survives install and re-install"
HOME="$FHA" bash "$DIR/uninstall.sh" antigravity >/dev/null 2>&1
{ jq -e --argjson h "$AGH" '. == {"some-tool":$h}' "$FHA/.gemini/antigravity-cli/hooks.json" >/dev/null 2>&1; } \
  && ok "uninstall antigravity: only the aigi-* hooks leave; the foreign named hook remains as written" \
  || bad "uninstall antigravity: only the aigi-* hooks leave; the foreign named hook remains as written"

# ---- a skill name something else already holds ----------------------------------
# A real directory or a foreign symlink at a skill's name is the user's. It is
# reported as a conflict (its own line, and again in the closing summary), never
# overwritten or deleted, and the rest of the skills still install.
SC="$LT/skill-conflicts"; rm -rf "$SC"; mkdir -p "$SC/.claude/skills/ship" "$SC/.codex/skills" "$SC/foreign-target" "$SC/.cursor/skills"
printf 'my own ship skill\n' > "$SC/.claude/skills/ship/SKILL.md"
ln -s "$SC/foreign-target" "$SC/.codex/skills/sync"
ln -s "$SC/does-not-exist" "$SC/.cursor/skills/verify"
HOME="$SC" bash "$DIR/install-skills.sh" --no-design claude codex cursor > "$SC/out1" 2>&1; sc_rc=$?
HOME="$SC" bash "$DIR/install-skills.sh" --no-design claude codex cursor > "$SC/out2" 2>&1
{ [ "$sc_rc" = 0 ] \
  && grep -qF "  conflict: $SC/.claude/skills/ship " "$SC/out1" \
  && grep -qF "  conflict: $SC/.codex/skills/sync " "$SC/out1" \
  && grep -qF "  conflict: $SC/.cursor/skills/verify " "$SC/out1" \
  && ! grep -q 'note: ' "$SC/out1"; } \
  && ok "install-skills: a real directory or foreign symlink at a skill name prints a conflict: line" \
  || bad "install-skills: a real directory or foreign symlink at a skill name prints a conflict: line"
{ grep -q '^Skill name conflicts: 3 skill(s)' "$SC/out1" \
  && sed -n '/^Skill name conflicts/,$p' "$SC/out1" | grep -qF "  $SC/.claude/skills/ship" \
  && sed -n '/^Skill name conflicts/,$p' "$SC/out1" | grep -qF "  $SC/.codex/skills/sync" \
  && sed -n '/^Skill name conflicts/,$p' "$SC/out1" | grep -qF "  $SC/.cursor/skills/verify" \
  && grep -q '^Skill name conflicts: 3 skill(s)' "$SC/out2"; } \
  && ok "install-skills: conflicts are listed in the closing summary, on every run" \
  || bad "install-skills: conflicts are listed in the closing summary, on every run"
{ [ -d "$SC/.claude/skills/ship" ] && [ ! -L "$SC/.claude/skills/ship" ] \
  && [ "$(cat "$SC/.claude/skills/ship/SKILL.md")" = 'my own ship skill' ] \
  && [ "$(readlink "$SC/.codex/skills/sync")" = "$SC/foreign-target" ] \
  && [ "$(readlink "$SC/.cursor/skills/verify")" = "$SC/does-not-exist" ] \
  && [ -L "$SC/.claude/skills/sync" ] && [ -L "$SC/.codex/skills/ship" ]; } \
  && ok "install-skills: a conflicting name is never overwritten or deleted, and the other skills still install" \
  || bad "install-skills: a conflicting name is never overwritten or deleted, and the other skills still install"
jq -e '[.files[] | select(.action == "conflict")] | length == 3' "$SC/.ai/install-state/last-run.json" >/dev/null 2>&1 \
  && ok "install-skills: conflicts are recorded in last-run.json for agents" \
  || bad "install-skills: conflicts are recorded in last-run.json for agents"
HOME="$SC" bash "$DIR/uninstall.sh" claude codex cursor >/dev/null 2>&1
{ [ -f "$SC/.claude/skills/ship/SKILL.md" ] && [ -L "$SC/.codex/skills/sync" ] && [ -L "$SC/.cursor/skills/verify" ]; } \
  && ok "uninstall: a conflicting skill name is left exactly as it was" \
  || bad "uninstall: a conflicting skill name is left exactly as it was"
SCC="$LT/skill-clean"; rm -rf "$SCC"; mkdir -p "$SCC"
HOME="$SCC" bash "$DIR/install-skills.sh" --no-design claude > "$SCC/out" 2>&1
{ ! grep -q 'conflict' "$SCC/out"; } \
  && ok "install-skills: a clean install reports no conflicts" \
  || bad "install-skills: a clean install reports no conflicts"

rm -rf "$LT"

echo ""
echo "$pass passed, $fail failed"
rm -f "$OUT" "$ERR"
[ "$fail" -eq 0 ]
