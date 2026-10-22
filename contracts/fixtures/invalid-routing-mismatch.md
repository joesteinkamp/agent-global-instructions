# Example routing file (fictional, for the catalog validator's tests)

<!-- generated:begin -->

## This machine

- **Last updated:** 2030-01-15

## Model tiers

| Model | Family | Tier | $/Mtok in/out | Reachable via (exact command prefix) | Evidence |
|---|---|---|---|---|---|
| Example Large 1 | ExampleLab | T1 | 4 / 20 | `claude -p --model large --effort <lvl>` · `agent -p --trust --model example-large-1-<low\|medium\|high>` | Board A 58 (#1) |
| Sample Reasoner 2 | SampleWorks | T1 | 10 / 50 | `codex exec -m sample-reasoner-2 -c model_reasoning_effort=<lvl>` | Board A 53 |
| Example Medium 1 | ExampleLab | T1 | 2 / 10 | `claude -p --model medium --effort <lvl>` | pinned |
| Example Local 7B | ExampleOpen | T3 | local | `lm -p "<prompt>" --model example-local-7b` | Board C 30 |
| Example `Auto` | varies | T3 at most | pool | `agent -p --trust --model auto` | cannot be tiered |

- **Pinned tiers:** Example Medium 1 → T2.

## Vendor by task

**Hard coding & refactoring** — T2
