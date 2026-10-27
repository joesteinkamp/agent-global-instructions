#!/usr/bin/env bash
# Validate a model catalog (schema version 1) with bash + jq only.
#
#   contracts/check-model-catalog.sh <catalog.json> [routing.md]
#
# Checks the required fields, their types, and the enums against
# contracts/model-catalog-v1.schema.json (the enums are read from it, so there
# is one list). It also checks what a schema cannot say: models are in
# preference order (T1, then T2, then T3), names are unique, a pinned model
# carries a reason and an unpinned one does not, and a routable model has at
# least one way to reach it.
#
# It enforces the size limits the schema publishes (name and model slug 200
# characters, family 80, 50 reach entries per model, 20 efforts per reach, 500
# models), read from the schema, so a catalog it accepts is never silently cut
# short by a reader that applies the same limits.
#
# With a routing markdown file, the "## Model tiers" table and the catalog must
# describe the same models: every table row is in the catalog and every catalog
# model is in the table, in the same order, with the same tier, family,
# routable/pinned flags and prices, and each structured reach equals what the
# row's "Reachable via" commands encode. The table's tier cell may carry a note
# ("T2 (pinned by user)", "T3 at most"); its first word is the tier. The rules
# for reading a row (commands are never executed, only read):
#   price    a "$/Mtok in/out" cell starting "<in> / <out>" (numbers, an
#            optional $, anything after them ignored, such as a billing pool)
#            -> priceIn, priceOut. Any other cell ("—", a pool name) -> null, null.
#   cli      the first word.
#   model    the word after --model or -m, quotes stripped; when it ends in a
#            -<a|b|c> or -<lvl> placeholder, the slug without that ending.
#   effort   --effort            -> effortStyle flag, efforts []
#            -c model_reasoning_effort=  -> codex-config (levels not in the row)
#            slug ending -<a|b|c> -> suffix, efforts [a,b,c] (-<lvl>: not in the row)
#            otherwise            -> none, efforts []
#   routable false when the tier cell says "at most" or the family is "varies".
#   pinned   true when the tier cell says "pinned".
# A command with no --model or -m cannot be checked and is an error.
#
# Efforts the row leaves to a placeholder (codex-config, a -<lvl> suffix) can't
# be compared. They are not claimed as matching: each is printed on an
# "unchecked:" line after the ok line, with the variants it would launch, for a
# person to review in the catalog.
#
# Exit: 0 valid (stdout: the ok line, then any unchecked: lines), 1 invalid
# (every problem is printed to stderr), 2 bad usage.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCHEMA="$HERE/model-catalog-v1.schema.json"
CATALOG="${1:-}"; ROUTING="${2:-}"
if [ -z "$CATALOG" ] || [ $# -gt 2 ]; then
  echo "usage: check-model-catalog.sh <catalog.json> [routing.md]" >&2; exit 2
fi
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 2; }
[ -f "$CATALOG" ] || { echo "no such file: $CATALOG" >&2; exit 2; }
[ -f "$SCHEMA" ] || { echo "schema not found next to this script: $SCHEMA" >&2; exit 2; }
[ -z "$ROUTING" ] || [ -f "$ROUTING" ] || { echo "no such file: $ROUTING" >&2; exit 2; }

if ! jq -e . "$CATALOG" >/dev/null 2>&1; then
  echo "error: $CATALOG is not valid JSON" >&2; exit 1
fi

lim="$(jq -c '{nameMax: ."$defs".model.properties.name.maxLength, slugMax: ."$defs".reach.properties.model.maxLength,
  familyMax: ."$defs".model.properties.family.maxLength, reachMax: ."$defs".model.properties.reach.maxItems,
  effMax: ."$defs".reach.properties.efforts.maxItems, modelsMax: .properties.models.maxItems}' "$SCHEMA")"
for k in nameMax slugMax familyMax reachMax effMax modelsMax; do
  [ "$(printf '%s' "$lim" | jq ".$k | type")" = '"number"' ] || { echo "schema is missing the published limit $k: $SCHEMA" >&2; exit 2; }
done

errors="$(jq -r --argjson lim "$lim" --argjson tiers "$(jq -c '."$defs".tier.enum' "$SCHEMA")" \
              --argjson styles "$(jq -c '."$defs".effortStyle.enum' "$SCHEMA")" \
              --argjson plans "$(jq -c '."$defs".account.properties.plan.enum' "$SCHEMA")" '
  def tname: if . == null then "null" else type end;
  # field($obj; $key; $path; [types]): present, and one of the types.
  def field($o; $k; $path; $types):
    if ($o | type) != "object" then empty
    elif ($o | has($k) | not) then "\($path).\($k): required, missing"
    elif ($types | index($o[$k] | tname)) == null
      then "\($path).\($k): expected \($types | join(" or ")), got \($o[$k] | tname)"
    else empty end;
  def str($o; $k; $path): field($o; $k; $path; ["string"]);
  def nonempty($o; $k; $path):
    if ($o | type) == "object" and (($o[$k] | type) == "string") and ($o[$k] == "")
    then "\($path).\($k): must not be empty" else empty end;
  def isdate: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$");
  def datef($o; $k; $path):
    field($o; $k; $path; ["string"]),
    (if ($o | type) == "object" and ($o[$k] | type) == "string" and ($o[$k] | isdate | not)
     then "\($path).\($k): expected YYYY-MM-DD, got \($o[$k] | tojson)" else empty end);
  def enumf($o; $k; $path; $allowed):
    if ($o | type) == "object" and ($o[$k] | type) == "string" and ($allowed | index($o[$k])) == null
    then "\($path).\($k): \($o[$k] | tojson) is not one of \($allowed | join("|"))" else empty end;
  def arr($o; $k; $path): field($o; $k; $path; ["array"]);
  def maxlen($o; $k; $path; $n):
    if ($o | type) == "object" and ($o[$k] | type) == "string" and ($o[$k] | length) > $n
    then "\($path).\($k): \($o[$k] | length) characters, the limit is \($n)" else empty end;
  def maxitems($o; $k; $path; $n):
    if ($o | type) == "object" and ($o[$k] | type) == "array" and ($o[$k] | length) > $n
    then "\($path).\($k): \($o[$k] | length) entries, the limit is \($n)" else empty end;
  def tierrank: {"T1": 1, "T2": 2, "T3": 3}[.] // 9;

  . as $c
  | if ($c | type) != "object" then "catalog: expected an object, got \($c | tname)"
    else
      # schemaVersion: only the one major this validator knows.
      (if ($c | has("schemaVersion") | not) then "schemaVersion: required, missing"
       elif $c.schemaVersion != 1 then "schemaVersion: expected 1, got \($c.schemaVersion | tojson)"
       else empty end),
      datef($c; "generatedAt"; "catalog"),
      maxitems($c; "models"; "catalog"; $lim.modelsMax),
      arr($c; "accounts"; "catalog"), arr($c; "models"; "catalog"), arr($c; "unreachable"; "catalog"),
      arr($c; "notRouted"; "catalog"), arr($c; "vendorByTask"; "catalog"), arr($c; "sources"; "catalog"),
      (if ($c.accounts | type) == "array" then
         ($c.accounts | to_entries[] | "accounts[\(.key)]" as $p | .value as $a
          | (if ($a | type) != "object" then "\($p): expected an object" else
               str($a; "cli"; $p), nonempty($a; "cli"; $p), str($a; "note"; $p),
               # plan and lockedUntil are optional: checked only when present.
               (if $a | has("plan") then str($a; "plan"; $p), enumf($a; "plan"; $p; $plans) else empty end),
               (if $a | has("lockedUntil") then datef($a; "lockedUntil"; $p) else empty end) end))
       else empty end),
      (if ($c.models | type) == "array" then
         ($c.models | to_entries[] | "models[\(.key)]" as $p | .value as $m
          | (if ($m | type) != "object" then "\($p): expected an object" else
               str($m; "name"; $p), nonempty($m; "name"; $p), maxlen($m; "name"; $p; $lim.nameMax),
               str($m; "family"; $p), nonempty($m; "family"; $p), maxlen($m; "family"; $p; $lim.familyMax),
               str($m; "tier"; $p), enumf($m; "tier"; $p; $tiers),
               field($m; "pinned"; $p; ["boolean"]),
               field($m; "pinReason"; $p; ["string", "null"]),
               field($m; "routable"; $p; ["boolean"]),
               field($m; "priceIn"; $p; ["number", "null"]),
               field($m; "priceOut"; $p; ["number", "null"]),
               (if ($m.priceIn | type) == "number" and $m.priceIn < 0 then "\($p).priceIn: must not be negative" else empty end),
               (if ($m.priceOut | type) == "number" and $m.priceOut < 0 then "\($p).priceOut: must not be negative" else empty end),
               str($m; "evidence"; $p),
               arr($m; "reach"; $p), maxitems($m; "reach"; $p; $lim.reachMax),
               (if $m.pinned == true and (($m.pinReason | type) != "string" or $m.pinReason == "")
                then "\($p).pinReason: a pinned model needs a reason string" else empty end),
               (if $m.pinned == false and $m.pinReason != null
                then "\($p).pinReason: must be null when pinned is false" else empty end),
               (if $m.routable == true and ($m.reach | type) == "array" and ($m.reach | length) == 0
                then "\($p).reach: a routable model needs at least one way to reach it" else empty end),
               (if ($m.reach | type) == "array" then
                  ($m.reach | to_entries[] | "\($p).reach[\(.key)]" as $rp | .value as $r
                   | (if ($r | type) != "object" then "\($rp): expected an object" else
                        str($r; "cli"; $rp), nonempty($r; "cli"; $rp),
                        str($r; "model"; $rp), nonempty($r; "model"; $rp), maxlen($r; "model"; $rp; $lim.slugMax),
                        str($r; "effortStyle"; $rp), enumf($r; "effortStyle"; $rp; $styles),
                        field($r; "efforts"; $rp; ["array"]), maxitems($r; "efforts"; $rp; $lim.effMax),
                        (if ($r.efforts | type) == "array" and ($r.efforts | any(type != "string" or . == ""))
                         then "\($rp).efforts: every entry must be a non-empty string" else empty end),
                        str($r; "command"; $rp)
                      end))
                else empty end)
             end))
       else empty end),
      # Preference order and unique names, only once each entry is well-formed enough to compare.
      (if ($c.models | type) == "array" and ($c.models | all(type == "object" and (.tier | type) == "string" and (.name | type) == "string")) then
         ([range(1; $c.models | length)] | map(select(($c.models[.].tier | tierrank) < ($c.models[. - 1].tier | tierrank)))
          | map("models[\(.)] (\($c.models[.].name)): \($c.models[.].tier) listed after \($c.models[. - 1].tier); models[] must run T1, then T2, then T3") | .[]),
         ($c.models | group_by(.name) | map(select(length > 1) | "models: name \(.[0].name | tojson) appears \(length) times") | .[])
       else empty end),
      (["unreachable", "notRouted"][] as $k
       | if ($c[$k] | type) == "array" then
           ($c[$k] | to_entries[] | "\($k)[\(.key)]" as $p | .value as $e
            | (if ($e | type) != "object" then "\($p): expected an object" else
                 str($e; "name"; $p), nonempty($e; "name"; $p), str($e; "reason"; $p) end))
         else empty end),
      (if ($c.vendorByTask | type) == "array" then
         ($c.vendorByTask | to_entries[] | "vendorByTask[\(.key)]" as $p | .value as $v
          | (if ($v | type) != "object" then "\($p): expected an object" else
               str($v; "category"; $p), nonempty($v; "category"; $p),
               str($v; "tier"; $p), enumf($v; "tier"; $p; $tiers),
               str($v; "primary"; $p), str($v; "fallback"; $p), str($v; "evidence"; $p) end))
       else empty end),
      (if ($c.sources | type) == "array" then
         ($c.sources | to_entries[] | "sources[\(.key)]" as $p | .value as $s
          | (if ($s | type) != "object" then "\($p): expected an object" else
               str($s; "name"; $p), nonempty($s; "name"; $p),
               str($s; "url"; $p), nonempty($s; "url"; $p), datef($s; "retrieved"; $p) end))
       else empty end)
    end
' "$CATALOG")"

if [ -n "$errors" ]; then
  printf 'error: %s\n' "$CATALOG" >&2
  printf '%s\n' "$errors" | sed 's/^/  /' >&2
  exit 1
fi

# The markdown table, when given: the same models, in the same order, with the
# same fields wherever the table spells them out; the rest are listed as unchecked.
if [ -n "$ROUTING" ]; then
  # Rows of the "## Model tiers" table as name<TAB>family<TAB>tier cell<TAB>
  # price cell<TAB>reachable-via cell. An escaped pipe (\|) inside a cell is text, not a column
  # break, so it is protected while the row is split and restored after.
  table="$(awk '
    /^## /          { in_tiers = ($0 ~ /^## Model tiers[[:space:]]*$/); next }
    in_tiers && /^\|/ {
      line = $0; gsub(/\\\|/, "\001", line)
      n = split(line, f, "|")
      name = f[2]; fam = f[3]; tier = f[4]; price = f[5]; reach = f[6]
      gsub(/`/, "", name)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name); gsub(/^[[:space:]]+|[[:space:]]+$/, "", fam)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", tier); gsub(/^[[:space:]]+|[[:space:]]+$/, "", price)
      gsub(/\001/, "|", price); gsub(/\001/, "|", reach)
      if (name == "Model" || name ~ /^-+$/ || name == "") next
      printf "%s\t%s\t%s\t%s\t%s\n", name, fam, tier, price, reach
    }' "$ROUTING")"
  if [ -z "$table" ]; then
    printf 'error: %s has no rows under "## Model tiers"\n' "$ROUTING" >&2; exit 1
  fi
  # Each finding is one line: "E:" an error, "U:" a field the table cannot check.
  mout="$(printf '%s\n' "$table" | jq -R -s -r --slurpfile cat "$CATALOG" '
    def trim: sub("^\\s+"; "") | sub("\\s+$"; "");
    # A "$/Mtok in/out" cell -> [in, out]: numbers when it starts "<in> / <out>", else nulls.
    def prices:
      (trim | capture("^\\$?(?<i>[0-9]+(\\.[0-9]+)?)\\s*/\\s*\\$?(?<o>[0-9]+(\\.[0-9]+)?)") // null) as $p
      | if $p == null then [null, null] else [($p.i | tonumber), ($p.o | tonumber)] end;
    # One backticked command prefix -> what it encodes. Read, never run.
    def parse:
      (gsub("\\s+"; " ") | split(" ") | map(select(length > 0))) as $t
      | ([range(0; $t | length)] | map(select($t[.] == "--model" or $t[.] == "-m")) | .[0]) as $mi
      | (if $mi == null then null else ($t[$mi + 1] // null) end) as $raw
      | (if $raw == null then null else ($raw | gsub("^\""; "") | gsub("\"$"; "")) end) as $slug
      | (. as $cmd | {cli: $t[0]}
         + (if $slug == null then {model: null, style: null, efforts: null}
            elif ($cmd | test("--effort")) then {model: $slug, style: "flag", efforts: []}
            elif ($cmd | test("model_reasoning_effort=")) then {model: $slug, style: "codex-config", efforts: null}
            elif ($slug | test("-<[^>]*>$")) then
              ($slug | capture("^(?<b>.*)-<(?<a>[^>]*)>$")) as $m
              | {model: $m.b, style: "suffix", efforts: (if $m.a == "lvl" then null else ($m.a | split("|")) end)}
            else {model: $slug, style: "none", efforts: []} end));
    ($cat[0].models) as $models
    | [split("\n")[] | select(length > 0) | split("\t")
       | {name: .[0], family: .[1], tier: ((.[2] // "") | split(" ")[0]), tiercell: (.[2] // ""),
          price: (.[3] // ""), prices: ((.[3] // "") | prices),
          cmds: [(.[4] // "") | match("`([^`]*)`"; "g") | .captures[0].string]}] as $rows
    | ($models | map(.name | gsub("`"; ""))) as $cn
    | ($rows | map(.name)) as $rn
    | (($cn | map(select(. as $n | $rn | index($n) | not))
       | map("\(.): in the catalog but not in the \"## Model tiers\" table") | .[]),
      ($rn | map(select(. as $n | $cn | index($n) | not))
       | map("\(.): in the \"## Model tiers\" table but not in the catalog") | .[]),
      (($cn | map(select(. as $n | $rn | index($n)))) as $ca | ($rn | map(select(. as $n | $cn | index($n)))) as $ra
       | if $ca != $ra then "order differs: the catalog lists \($ca | join(", ")) but the table lists \($ra | join(", "))" else empty end)
      | "E:" + .),
      ($models[] | . as $m | ($m.name | gsub("`"; "")) as $n
       | ($rows | map(select(.name == $n)) | .[0]) as $r
       | if $r == null then empty else
           ((if $m.tier != $r.tier then "\($n): catalog says \($m.tier), the table says \($r.tier)" else empty end),
           (if $m.family != $r.family then "\($n): catalog says family \($m.family | tojson), the table says \($r.family | tojson)" else empty end),
           ((($r.tiercell | test("at most")) or $r.family == "varies") as $nr
            | if $m.routable != ($nr | not) then "\($n): catalog says routable \($m.routable), the table implies \($nr | not)" else empty end),
           (($r.tiercell | test("pinned")) as $pn
            | if $m.pinned != $pn then "\($n): catalog says pinned \($m.pinned), the table says \($pn)" else empty end),
           (if [$m.priceIn, $m.priceOut] != $r.prices
            then "\($n): catalog says price in/out \([$m.priceIn, $m.priceOut] | tojson), the table says \($r.price | tojson) (read as \($r.prices | tojson))" else empty end),
           (($r.cmds | map(parse)) as $want
            | if ($r.cmds | length) == 0 then "\($n): the table row has no backticked command"
              elif ($m.reach | length) != ($want | length)
              then "\($n): catalog has \($m.reach | length) reach entries, the table row has \($want | length) commands"
              else
                ([range(0; $want | length)][] | . as $i | $want[$i] as $w | $m.reach[$i] as $g
                 | "\($n) reach[\($i)]" as $rp
                 | (if $w.model == null then "\($rp): the table command has no --model or -m, so its slug cannot be checked"
                    else empty end),
                   (if $g.cli != $w.cli then "\($rp).cli: catalog says \($g.cli | tojson), the table command says \($w.cli | tojson)" else empty end),
                   (if $w.model != null and $g.model != $w.model then "\($rp).model: catalog says \($g.model | tojson), the table command says \($w.model | tojson)" else empty end),
                   (if $w.style != null and $g.effortStyle != $w.style then "\($rp).effortStyle: catalog says \($g.effortStyle | tojson), the table command says \($w.style | tojson)" else empty end),
                   (if $w.efforts != null and $g.efforts != $w.efforts then "\($rp).efforts: catalog says \($g.efforts | tojson), the table command says \($w.efforts | tojson)" else empty end))
              end) | "E:" + .),
           # Efforts the row leaves to a placeholder: listed, never claimed as matching.
           (($r.cmds | map(parse)) as $want
            | if ($m.reach | length) != ($want | length) then empty else
                ([range(0; $want | length)][] | . as $i | $want[$i] as $w | $m.reach[$i] as $g
                 | select($w.model != null and $w.efforts == null)
                 | (if $w.style == "codex-config" then "model_reasoning_effort=<lvl>" else "-<lvl>" end) as $ph
                 | (if ($g.efforts | length) == 0 then "no listed effort"
                    elif $g.effortStyle == "suffix" then ($g.efforts | map($g.model + "-" + .) | join(", "))
                    else $g.model + " at " + ($g.efforts | join(", ")) end) as $launch
                 | "U:\($n) reach[\($i)] (\($g.cli), \($ph) in the table): efforts \($g.efforts | tojson), launches \($launch)")
              end)
         end)
  ')"
  merrors="$(printf '%s\n' "$mout" | sed -n 's/^E://p')"
  unchecked="$(printf '%s\n' "$mout" | sed -n 's/^U:/unchecked: /p')"
  if [ -n "$merrors" ]; then
    printf 'error: %s disagrees with %s\n' "$CATALOG" "$ROUTING" >&2
    printf '%s\n' "$merrors" | sed 's/^/  /' >&2
    exit 1
  fi
fi

summary="ok: $CATALOG ($(jq '.models | length' "$CATALOG") models)"
if [ -n "$ROUTING" ]; then
  summary="$summary, matches $ROUTING"
  n="$(printf '%s' "$unchecked" | grep -c '^unchecked: ' || true)"
  if [ "$n" = 1 ]; then
    summary="$summary, except 1 effort list the table leaves to a placeholder (the unchecked: line below; review it in the catalog)"
  elif [ "$n" -gt 1 ]; then
    summary="$summary, except $n effort lists the table leaves to a placeholder (the unchecked: lines below; review them in the catalog)"
  fi
fi
echo "$summary"
[ -z "${unchecked:-}" ] || printf '%s\n' "$unchecked"
