# Prompts

This directory contains the prompt templates ralph uses for its built-in modes
(`plan.md`, `build.md`, `plan-process.md`, `build-process.md`, `align-specs.md`,
`sandbox-*.md`) and a small set of shipped **ad-hoc prompts** designed to be run
via `ralph prompt <file>`.

For end-user guidance on writing your own ad-hoc prompts, run:

```
ralph help prompt
```

That is the canonical reference. This README is a contributor-facing index of
what's in this directory and the patterns each shipped ad-hoc prompt
demonstrates.

## Shipped Ad-Hoc Prompts

The four `adhoc-*.md` prompts are intentionally not uniform — they demonstrate
**different durable-state mechanisms** so users have multiple working examples
to study. Pick the pattern that fits your work product.

| Prompt | Purpose | Durable-state pattern |
|--------|---------|------------------------|
| [adhoc-retro-analyze.md](adhoc-retro-analyze.md) | Produce a retro report from the most recent plan+build cycle | **Transient analysis report** — the report itself is durable state; `<!-- TODO -->` markers drive resumption |
| [adhoc-retro-feedback.md](adhoc-retro-feedback.md) | Sanitize a retro report for public sharing | **Pre-flight gate (single-shot)** — validates inputs and exits cleanly if prerequisites aren't met |
| [adhoc-test-analysis.md](adhoc-test-analysis.md) | Study a test suite and enhance specs with rules tests verify | **Explicit progress file** — a small inventory checklist tracks which test areas are done |
| [adhoc-process-spec-review.md](adhoc-process-spec-review.md) | Find gaps and ordering problems in process specs before `ralph plan --process` | **Explicit progress file** — a phase checklist tracks which phases are reviewed |

A fourth pattern, **deliverable-as-state** (no separate progress file; the work
product itself encodes "what's done"), is described in `ralph help prompt` but
not currently demonstrated by a shipped prompt.

## Shared Conventions

All four shipped ad-hoc prompts follow the same top-level structure, derived
from the battle-tested `plan.md` / `build.md` patterns:

- `## Goal` — what the prompt produces
- `## Operating Contract` — autonomy and posture (positive framing)
- `## Context` — input files and reference paths
- `## Iteration Strategy` (multi-iteration prompts) or `## Pre-flight Checks` (single-shot)
- `## Workflow` — numbered steps, referencing other sections
- Domain-specific top-level sections — `## Analysis Dimensions`, `## Phase Review Guidelines`, `## Scannable Markers`, etc.
- `## Rules` — prohibitions only
- `## Exit Signal` — single source of truth for the completion signal

A structural test in `tests/test_core.sh` enforces that each `adhoc-*.md`
prompt has exactly one `<promise>COMPLETE</promise>` mention and exactly one
`## Exit Signal` heading.

## Adding a New Built-In or Shipped Ad-Hoc Prompt

1. Add the file under `prompts/`.
2. Add it to `MANAGED_FILES` in both `install.sh` and `update.sh` so it ships
   to user projects.
3. If it's a shipped ad-hoc prompt, add a row to the table above and update
   the `ralph help prompt` content in `lib/help/prompt.txt`.
4. If structural conventions change, update the structural test in
   `tests/test_core.sh`.
