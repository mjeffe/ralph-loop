# Shipped Ad-Hoc Prompts

## Purpose

Define what Ralph ships under `prompts/adhoc-*.md`, the design intent of the
shipped set, and the structural conventions every shipped ad-hoc prompt must
follow. Individual ad-hoc prompts are **not** spec'd the way `plan.md` and
`build.md` are — they are intentionally lighter-weight than Ralph's core modes.
This spec defines the contract for the ad-hoc prompt set as a whole.

## Design Intent

Shipped ad-hoc prompts serve two purposes simultaneously:

1. **Useful out of the box** — each one performs a real, valuable task users
   can run via `ralph prompt <file>`.
2. **Teaching set** — collectively they demonstrate the patterns we recommend
   for writing custom ad-hoc prompts. Users authoring their own
   `adhoc-*.md` files study the shipped ones as examples.

Because of the second purpose, the shipped set is curated to demonstrate
**different** durable-state mechanisms (see Durable-State Patterns below) so a
user has multiple working examples to choose from. We do not optimize the
shipped set for uniformity — coverage of patterns matters more.

## Catalog

The shipped ad-hoc prompts are listed in `specs/help-system.md` (under
`ralph help prompt`) for the user-facing CLI version of the catalog. That is
the single source of truth for the catalog content; this spec does not
duplicate it.

The end-user-facing description of each prompt and the durable-state pattern
it demonstrates lives in `lib/help/prompt.txt` (rendered by `ralph help
prompt`).

## Durable-State Patterns

Each shipped ad-hoc prompt demonstrates exactly one durable-state pattern.
The four documented patterns are:

- **Transient analysis report** — the deliverable file itself is durable
  state; resumption is driven by `<!-- TODO -->` markers in the report.
- **Pre-flight gate (single-shot)** — the prompt validates inputs and exits
  cleanly if prerequisites aren't met; no durable state across iterations.
- **Explicit progress file** — a small inventory or checklist file at
  `${RALPH_HOME}/<name>-progress.md` tracks completion across iterations.
- **Deliverable as state** — the work product itself encodes "what's done"
  cleanly enough that no separate progress file is needed.

The shipped set should aim to demonstrate at least three of these patterns at
any time. If a future shipped prompt would duplicate a pattern already
demonstrated, prefer extending the existing example instead.

## Structural Conventions

Every shipped ad-hoc prompt must include the following top-level sections, in
this order, where applicable to the prompt's nature:

1. `## Goal` — what the prompt produces.
2. `## Operating Contract` — agent autonomy, posture, and high-level positive
   obligations (positive framing).
3. `## Context` — input files, reference paths, environment variables.
4. `## Iteration Strategy` (multi-iteration prompts) **or** `## Pre-flight
   Checks` (single-shot prompts) — one of these, not both.
5. `## Workflow` — numbered steps, referencing other sections rather than
   restating their content.
6. Domain-specific top-level sections — e.g., `## Analysis Dimensions`,
   `## Phase Review Guidelines`, `## Scannable Markers`, `## Sanitization
   Principles`. These promote the prompt's analytical or structural concerns
   to first-class status.
7. `## Rules` — prohibitions only (negative framing). Positive obligations
   live in Operating Contract.
8. `## Exit Signal` — single source of truth for the completion signal.
   Workflow steps reference it as `(see Exit Signal)`; they do not restate
   the signal text inline.
9. Closing imperative line — e.g., `Begin analysis now.` — matching the
   convention in `plan.md` and `build.md`.

## Required Invariants

Every shipped ad-hoc prompt must satisfy:

- Exactly one `<promise>COMPLETE</promise>` mention in the file. Multiple
  scattered mentions defeat the single-source-of-truth pattern.
- Exactly one `## Exit Signal` (or `## Exit Signals`) heading.
- A "fresh context" reminder near the top stating that each iteration starts
  with no memory of prior iterations.

A structural test in `tests/test_core.sh` enforces the first two invariants.
The third is a content convention enforced by review.

## Out of Scope

This spec deliberately does **not**:

- Define a per-prompt canonical specification the way `specs/plan-mode.md` or
  `specs/build-mode.md` do for Ralph's core modes. Shipped ad-hoc prompts are
  examples, not load-bearing system components, and individual specs would
  be too heavy for the role they play.
- Define the patterns and writing guidance for **user-authored** ad-hoc
  prompts in detail. That guidance lives in `lib/help/prompt.txt` (rendered
  by `ralph help prompt`) and `specs/help-system.md`. This spec describes
  only what Ralph itself ships and the contract those shipped prompts must
  meet.

## Adding a New Shipped Ad-Hoc Prompt

Operational checklist for contributors lives in the project's `AGENTS.md`.
This spec defines the structural and design contract; `AGENTS.md` defines
the procedural steps (where to register the file, which help text to update,
which tests to verify).
