# contracts

Published file formats other tools may read. This directory holds the schema,
its validator and fictional fixtures, and nothing else (`test.sh` pins the file
list).

| File | What it is |
|---|---|
| `model-catalog-v1.schema.json` | JSON Schema for `~/.ai/model-catalog.json`, which `/update-model-routing` writes beside `~/.ai/model-routing.md`. |
| `check-model-catalog.sh` | bash + jq validator. `check-model-catalog.sh <catalog.json> [routing.md]`. Checks fields, types, enums and the size limits below; with the markdown it also checks the table and the catalog agree (see below). Exit 0 valid, 1 invalid, 2 bad usage. |
| `fixtures/` | Made-up data (models named "Example …", "Sample …"): a valid catalog and its matching table, plus deliberately broken ones. `test.sh` pins the exact entry list, hidden entries included, and rejects anything that is not a regular file (a symlink publishes its target path); then it runs a tripwire over every string in them (home paths, real-looking hosts, emails, opaque tokens, non-fictional names); it catches careless pastes and cannot prove a fixture holds no private data, so read every field of a new fixture before adding it. |

The catalog lives only on the machine, at `~/.ai/model-catalog.json` (staged as
`~/.ai/model-catalog.next.json` until you approve it). It is never written into
a checkout.

Size limits, published in the schema and enforced by the validator, so a reader
that applies the same caps never silently drops part of a valid catalog: model
name and reach `model` slug up to 200 characters, `family` up to 80, up to 500
models, 50 `reach` entries per model, 20 `efforts` per reach entry.

With a routing markdown file the validator requires the `## Model tiers` table
and the catalog to describe the same models: every row in the catalog and every
catalog model in the table, in the same order, with the same tier, family and
`routable`/`pinned` flags (`routable` is false when the tier cell says "at most"
or the family is "varies"; `pinned` is true when the tier cell says "pinned"),
and each `reach` entry equal to what the row's backticked commands encode: `cli`
is the first word, `model` the word after `--model` or `-m` (without a trailing
`-<low|medium|high>` placeholder), and `effortStyle`/`efforts` come from
`--effort` (flag), `-c model_reasoning_effort=` (codex-config), a `-<…>` slug
ending (suffix, with those levels), or nothing (none). The commands are read,
never run.

Rules for a reader of the catalog:

- Ignore fields you don't know. Reject a different `schemaVersion`.
- `models[]` is in preference order: T1 first, then T2, then T3, and within a
  tier the preferred model first. `reach[]` is ordered the same way.
- `reach[].command` is for people. Never execute it or build an argument list
  from it; use `cli`, `model`, `effortStyle` and `efforts`.
- `cli` is an open string. Known values: `claude`, `codex`, `agent` (Cursor CLI),
  `agy` (Antigravity), `lm` (local models).
- `routable: false` marks auto-style models whose backend varies; don't route
  tiered work to them. `pinned: true` means the user fixed the tier.
- The markdown table stays the source for people and agents that read prose; the
  catalog carries the same facts in a form a program can read.
