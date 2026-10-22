# contracts

Published file formats other tools may read. This directory holds the schema,
its validator and fictional fixtures, and nothing else (`test.sh` enforces
that).

| File | What it is |
|---|---|
| `model-catalog-v1.schema.json` | JSON Schema for `~/.ai/model-catalog.json`, which `/update-model-routing` writes beside `~/.ai/model-routing.md`. |
| `check-model-catalog.sh` | bash + jq validator. `check-model-catalog.sh <catalog.json> [routing.md]`; with the markdown it also checks every catalog model is in the `## Model tiers` table under the same tier. Exit 0 valid, 1 invalid, 2 bad usage. |
| `fixtures/` | Made-up data only (models named "Example …", "Sample …"). A valid catalog and its matching table, plus deliberately broken ones. |

The catalog lives only on the machine, at `~/.ai/model-catalog.json` (staged as
`~/.ai/model-catalog.next.json` until you approve it). It is never written into
a checkout.

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
