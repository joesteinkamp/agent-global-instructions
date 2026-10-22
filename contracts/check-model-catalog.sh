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
# With a routing markdown file, every catalog model must also appear in its
# "## Model tiers" table, under the same tier. The table's tier cell may carry a
# note ("T2 (pinned by user)", "T3 at most"); its first word is the tier.
#
# Exit: 0 valid, 1 invalid (every problem is printed to stderr), 2 bad usage.
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

errors="$(jq -r --argjson tiers "$(jq -c '."$defs".tier.enum' "$SCHEMA")" \
              --argjson styles "$(jq -c '."$defs".effortStyle.enum' "$SCHEMA")" '
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
  def tierrank: {"T1": 1, "T2": 2, "T3": 3}[.] // 9;

  . as $c
  | if ($c | type) != "object" then "catalog: expected an object, got \($c | tname)"
    else
      # schemaVersion: only the one major this validator knows.
      (if ($c | has("schemaVersion") | not) then "schemaVersion: required, missing"
       elif $c.schemaVersion != 1 then "schemaVersion: expected 1, got \($c.schemaVersion | tojson)"
       else empty end),
      datef($c; "generatedAt"; "catalog"),
      arr($c; "accounts"; "catalog"), arr($c; "models"; "catalog"), arr($c; "unreachable"; "catalog"),
      arr($c; "notRouted"; "catalog"), arr($c; "vendorByTask"; "catalog"), arr($c; "sources"; "catalog"),
      (if ($c.accounts | type) == "array" then
         ($c.accounts | to_entries[] | "accounts[\(.key)]" as $p | .value as $a
          | (if ($a | type) != "object" then "\($p): expected an object" else
               str($a; "cli"; $p), nonempty($a; "cli"; $p), str($a; "note"; $p) end))
       else empty end),
      (if ($c.models | type) == "array" then
         ($c.models | to_entries[] | "models[\(.key)]" as $p | .value as $m
          | (if ($m | type) != "object" then "\($p): expected an object" else
               str($m; "name"; $p), nonempty($m; "name"; $p),
               str($m; "family"; $p), nonempty($m; "family"; $p),
               str($m; "tier"; $p), enumf($m; "tier"; $p; $tiers),
               field($m; "pinned"; $p; ["boolean"]),
               field($m; "pinReason"; $p; ["string", "null"]),
               field($m; "routable"; $p; ["boolean"]),
               field($m; "priceIn"; $p; ["number", "null"]),
               field($m; "priceOut"; $p; ["number", "null"]),
               (if ($m.priceIn | type) == "number" and $m.priceIn < 0 then "\($p).priceIn: must not be negative" else empty end),
               (if ($m.priceOut | type) == "number" and $m.priceOut < 0 then "\($p).priceOut: must not be negative" else empty end),
               str($m; "evidence"; $p),
               arr($m; "reach"; $p),
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
                        str($r; "model"; $rp), nonempty($r; "model"; $rp),
                        str($r; "effortStyle"; $rp), enumf($r; "effortStyle"; $rp; $styles),
                        field($r; "efforts"; $rp; ["array"]),
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

# The markdown table, when given: name and tier must agree.
if [ -n "$ROUTING" ]; then
  # Rows of the "## Model tiers" table as "name<TAB>tier". Backticks around a
  # name are formatting, not part of it.
  table="$(awk -F'|' '
    /^## /          { in_tiers = ($0 ~ /^## Model tiers[[:space:]]*$/); next }
    in_tiers && /^\|/ {
      name = $2; tier = $4
      gsub(/`/, "", name); gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", tier); sub(/[[:space:]].*$/, "", tier)
      if (name == "Model" || name ~ /^-+$/ || name == "") next
      printf "%s\t%s\n", name, tier
    }' "$ROUTING")"
  if [ -z "$table" ]; then
    printf 'error: %s has no rows under "## Model tiers"\n' "$ROUTING" >&2; exit 1
  fi
  merrors=""
  while IFS="$(printf '\t')" read -r name tier; do
    row_tier="$(printf '%s\n' "$table" | awk -F'\t' -v n="$name" '$1 == n { print $2; exit }')"
    if [ -z "$row_tier" ]; then
      merrors="$merrors  $name: in the catalog but not in the \"## Model tiers\" table of $ROUTING
"
    elif [ "$row_tier" != "$tier" ]; then
      merrors="$merrors  $name: catalog says $tier, the table says $row_tier
"
    fi
  done <<EOF2
$(jq -r '.models[] | [(.name | gsub("`"; "")), .tier] | @tsv' "$CATALOG")
EOF2
  if [ -n "$merrors" ]; then
    printf 'error: %s disagrees with %s\n%s' "$CATALOG" "$ROUTING" "$merrors" >&2
    exit 1
  fi
fi

echo "ok: $CATALOG ($(jq '.models | length' "$CATALOG") models)$([ -n "$ROUTING" ] && echo ", matches $ROUTING")"
