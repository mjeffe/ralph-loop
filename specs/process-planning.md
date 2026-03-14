# Process Planning

## Purpose

Process planning enables Ralph to work from human-authored migration playbooks, rewrite
strategies, and other ordered process specs — documents that describe *how to get there*
rather than *what the system should be*.

Target-state specs define desired behavior. Process specs define phased, ordered work with
explicit sequencing constraints. Both are valid inputs to Ralph's planning system, but they
require different planning approaches.

## Concepts

| Term | Meaning | Location |
|------|---------|----------|
| **Specs** | Target-state behavior ("what it should be") | `${SPECS_DIR}/*.md` |
| **Process specs** | Ordered playbooks with phases and sequencing ("how to get there") | `${PROCESS_DIR}/*.md` |
| **Implementation plan** | Build-mode execution queue (derived from either source) | `implementation_plan.md` |

Process specs are not target-state specs. They describe:
- Migration phases and their ordering
- Dependencies between steps
- Rollout strategy and sequencing constraints
- Refactoring steps that must happen in a specific order

They do **not** describe what the system should look like when finished — that remains the
job of target-state specs in `${SPECS_DIR}`.

## Configuration

```bash
# In config
PROCESS_DIR=""    # Path to process specs directory (empty = not used)
```

`PROCESS_DIR` defaults to empty. When unset, `ralph plan --process` exits with an error:
"No PROCESS_DIR configured. Set PROCESS_DIR in config."

If `PROCESS_DIR` is set but the directory does not exist, exit with an error:
"PROCESS_DIR '${PROCESS_DIR}' not found."

If the directory exists but contains no top-level `*.md` files, exit with an error:
"No process specs found in '${PROCESS_DIR}/'."

A typical value is `specs/process`. The directory structure is up to the project:

```
specs/
├── README.md
├── feature-a.md          # target-state spec
├── feature-b.md          # target-state spec
└── process/
    ├── migration-plan.md  # process spec
    ├── phase-0-detail.md  # process spec
    └── archive/           # completed process specs (ignored by planner)
        └── old-spec.md
```

Only top-level `*.md` files in `PROCESS_DIR` are read as process specs. Subdirectories
are ignored. This lets projects use `archive/` for completed specs and other subdirectories
for supporting material (notes, reference docs) without the planner treating them as active
process specs.

## CLI Interface

```bash
ralph plan                  # Plan from target-state specs (existing behavior)
ralph plan --process        # Plan from process specs
ralph plan --force          # Overwrite plan regardless of type mismatch
ralph plan --process --force
```

The `--process` and `--force` flags are only valid with `ralph plan`. If used with
`build`, `prompt`, or other modes, ralph exits with an error:
"--process and --force are only valid with 'ralph plan'."

The `--process` flag selects the planning prompt and source directory. It does not change
how the loop runs — plan mode still iterates with fresh context, uses the same logging,
and exits on `<promise>COMPLETE</promise>`.

## Plan-Type Metadata

The implementation plan includes a visible metadata header that records how it was created:

```markdown
# Implementation Plan

**Plan Type:** spec
**Sources:** specs/overview.md, specs/loop-behavior.md
```

Or for process-derived plans:

```markdown
# Implementation Plan

**Plan Type:** process
**Sources:** specs/process/inertia-migration-plan.md, specs/process/phase-0-detail.md
```

| Field | Values | Purpose |
|-------|--------|---------|
| `Plan Type` | `spec` or `process` | How this plan was created |
| `Sources` | Comma-separated file paths | Which specs produced it |

The planning agent writes this metadata when creating or regenerating the plan.

### Type Guard

When `implementation_plan.md` exists and contains plan-type metadata, Ralph checks for
type mismatches before planning:

| Command | Existing plan type | Result |
|---|---|---|
| `ralph plan` | none or `spec` | ✅ proceeds |
| `ralph plan --process` | none or `process` | ✅ proceeds |
| `ralph plan` | `process` | ❌ refused |
| `ralph plan --process` | `spec` | ❌ refused |
| either + `--force` | any | ✅ proceeds |
| delete plan + either | N/A | ✅ fresh start |

Refusal message:
```
Current implementation plan is type '<type>'. Use --force to replace it,
or delete implementation_plan.md to start fresh.
```

The guard is implemented in the ralph script before invoking the agent. It parses the
`Plan Type:` line from the existing plan file.

## Planning Behavior

### Spec Planning (existing, unchanged)

`ralph plan` reads target-state specs, surveys the codebase, identifies gaps between
desired and current behavior, and generates an ordered task list. The agent decides task
ordering. See `specs/plan-mode.md` for full details.

### Process Planning

`ralph plan --process` reads process specs and target-state specs, surveys the codebase,
and decomposes process phases into build-iteration-sized tasks.

The key difference from spec planning:

| Concern | Spec planning | Process planning |
|---|---|---|
| **Primary source** | `${SPECS_DIR}` | `${PROCESS_DIR}` |
| **Codebase survey** | Full | Full |
| **Task discovery** | Infer from spec-vs-code gaps | Decompose within human-defined phases |
| **Ordering authority** | Agent decides | Human's phase structure is authoritative |
| **Target-state specs** | Primary input | Read-only context |
| **Adding work** | Expected | Only within or between existing phases |

Process specs define the strategy, phases, and sequencing constraints. The agent surveys
the codebase to understand the actual scope of each phase and step, then decomposes them
into tasks that can each be completed in a single build iteration. The agent has full
autonomy in *how* it breaks down each step, but the phase ordering from the process spec
is authoritative.

When multiple process specs cover the same phase or step at different levels of detail,
the most detailed spec is authoritative for decomposition. Higher-level specs provide
context and define phases not covered elsewhere.

Target-state specs from `${SPECS_DIR}` are available as context — they help the agent
understand what each process step is trying to achieve and how to size tasks — but they
do not drive task creation.

### Process Spec Lifecycle

Only top-level `*.md` files in `PROCESS_DIR` are active process specs. Subdirectories
are ignored, which enables an `archive/` convention for completed specs.

When the planning agent's codebase survey reveals that all work described by a process
spec is already complete, it skips task generation for that spec and notes it in the plan
as a candidate for archiving. This catches the case where a human forgets to move a
completed spec out of the active directory.

### Regeneration

When `ralph plan --process` finds an existing process plan with completed tasks, it:
- Keeps completed tasks as-is
- Re-decomposes remaining phases from the source process specs
- Preserves the phase ordering

This differs from spec planning, which rebuilds the entire task list from scratch.

## Build Mode Behavior

Build mode works the same regardless of plan type, with one difference in how the agent
treats task ordering:

- **`spec` plans:** Agent may reorder tasks if there's good reason (existing behavior)
- **`process` plans:** Agent preserves source ordering — tasks derived from Phase 0 come
  before Phase 1 tasks, 0a before 0b, etc.

When a build agent discovers new work during a process plan:
- Add discovered tasks in a clearly labeled section (e.g., "Discovered during Task X")
- Note suggested placement relative to existing phases
- Do not insert discovered tasks into the middle of the phase sequence

The REPLAN signal semantics change based on plan type:
- **`spec` plan:** "Run 'ralph plan' to regenerate the implementation plan."
- **`process` plan:** "Review your process specs and run 'ralph plan --process' to
  regenerate the implementation plan."

## Prompt Template

The process planning prompt lives at `prompts/plan-process.md`. It is a separate file
from `prompts/plan.md` because the planning job is fundamentally different — decomposition
within a human-defined framework rather than open-ended gap analysis.

```markdown
You are an expert software architect working in Ralph process-planning mode.

Each iteration starts with **fresh context** — you have no memory of prior iterations. Treat repo files as the sole source of truth: `${PROCESS_DIR}/`, `${SPECS_DIR}/`, `AGENTS.md`, git history, and any existing `${RALPH_HOME}/implementation_plan.md`.

## Operating Contract

- Process specs define the strategy, phases, and sequencing. Their phase ordering is **authoritative** — you must not reorder phases.
- You have full autonomy in how you decompose each phase into build-iteration-sized tasks.
- Target-state specs in `${SPECS_DIR}/` are **read-only context** — they help you understand what each step achieves, but they do not drive task creation.
- When multiple process specs cover the same phase or step at different levels of detail, the most detailed spec is authoritative for decomposition. Higher-level specs provide context and define phases not covered elsewhere.
- **Do not implement product code** — process planning produces only the implementation plan, and commits.
- Commit your plan updates at the end of each iteration with a descriptive commit message.

## Context

- **Process Specifications:** ${PROCESS_DIR}
- **Target-State Specifications:** ${SPECS_DIR}
- **Specs Index:** ${SPECS_DIR}/README.md
- **Implementation Plan:** ${RALPH_HOME}/implementation_plan.md
- **Project instructions:** AGENTS.md

## Workflow

1. **Read inputs** — Study `AGENTS.md`, `${SPECS_DIR}/README.md`, all top-level `*.md` files in `${PROCESS_DIR}/` (not subdirectories), and target-state specs in `${SPECS_DIR}/` for context. If `${RALPH_HOME}/implementation_plan.md` exists, read it to understand prior progress.
2. **Survey the codebase** — Understand the current state of the project, focusing on areas touched by the process specs. This is a full survey, not a cursory glance — you need to accurately size each phase.
3. **Check for completed specs** — If your survey reveals that all work described by a process spec is already complete, do not generate tasks for it. Instead, note it at the top of the plan: "Process spec `<file>` appears complete — consider moving it to `${PROCESS_DIR}/archive/`."
4. **Decompose phases** — For each active process spec, determine whether each phase and step fits in a single build iteration or needs splitting. Split based on independently testable concerns, but keep child tasks adjacent within their parent phase.
5. **Write the plan** — Create or update `${RALPH_HOME}/implementation_plan.md`. Include the metadata header (see Plan Format below). If the plan already contains tasks marked `complete`, preserve them and re-decompose only the remaining phases.
6. **Commit** all changes with a descriptive commit message.
7. **If planning is complete**, output the completion signal (see Exit Signal).
8. **If planning is not yet complete**, stop without a signal — the loop will start another iteration.

## Exit Signal

When planning is complete, output exactly `<promise>COMPLETE</promise>` — the loop cannot exit without it.

## Plan Format

The plan must begin with:

```
# Implementation Plan

**Plan Type:** process
**Sources:** <comma-separated list of process spec files read>
```

Each task needs at minimum:
- A short title
- A brief description of what needs to be done
- The **process spec and phase/step** it traces to (e.g., `specs/process/migration-plan.md — Phase 0a, Step 1`)
- A **status**: `planned` | `blocked` | `complete`
- Enough context for a build agent to start work without re-reading the full process spec

Order tasks to match the phase ordering from the process specs.

## Task Sizing

- If a process spec step is completable in one build iteration, make it one task.
- If a step is too large (touches multiple independently testable concerns), split it into child tasks. Keep child tasks adjacent and ordered within their parent phase.
- If a step is too small, combine it with adjacent steps in the same phase — but only if they would logically be committed together.
- Each task should be completable in one build iteration and committable as a single logical unit.

## Discovered Work

If you discover work not covered by the process specs:
- Note it in a clearly labeled section at the end of the plan
- Suggest where it fits relative to existing phases
- Do not insert it into the phase sequence

## Task Status Values

- `planned` — ready to work on
- `blocked` — cannot proceed (document why in the task)
- `complete` — finished and committed

Begin planning now.
```

## Changes to Existing Specs and Files

### `ralph` script

1. Add `--process` and `--force` flag parsing for plan mode
2. Add plan-type guard logic before invoking the agent
3. Select `prompts/plan-process.md` when `--process` is set
4. Export `PROCESS_DIR` as a template variable when set

### `config`

Add `PROCESS_DIR=""` with a comment explaining it is optional.

### `prompts/plan.md`

Add to the metadata section of generated plans:
```
**Plan Type:** spec
**Sources:** <list of spec files>
```

No other changes to the existing plan prompt.

### `prompts/build.md`

> **TBD — single prompt vs. separate `build-process.md`**
>
> The build-mode behavioral differences for process plans are small:
> 1. Preserve source ordering — do not reorder tasks across phases
> 2. Append discovered work in a separate section — do not insert into the phase sequence
> 3. Adjust REPLAN message to reference process specs instead of target-state specs
>
> **Option A: Conditional sections in `build.md`.** Three sentences of conditional
> guidance added to the existing prompt. Avoids duplication, one file to maintain.
> Risk: the build prompt has been carefully tuned — adding conditional branches may
> introduce noise or confusion that degrades agent performance on the common (spec) path.
>
> **Option B: Separate `build-process.md`.** Duplicates ~95% of `build.md` but keeps
> each prompt clean and single-purpose (matching the plan/plan-process split). Downside:
> two files to maintain; behavioral improvements to one must be mirrored in the other.
>
> Decision deferred — revisit after evaluating how the conditional guidance affects
> agent output quality on the existing build prompt.

### `specs/project-structure.md`

Add `PROCESS_DIR` to the configuration table. Add `specs/process/` as an optional
directory in the layout examples.

### `specs/plan-mode.md`

Add a note that plan mode handles target-state specs only. Reference this spec for
process planning.

### `specs/spec-lifecycle.md`

✅ Done — added "Target-State Specs vs. Process Specs" section with decision table for
choosing the right planning mode.

### `specs/loop-behavior.md`

Add `--process` and `--force` flags to the CLI interface section.

### Installer and Updater

Add `prompts/plan-process.md` to managed files. No other changes — `PROCESS_DIR` defaults
to empty, so process planning is opt-in.

## Example Workflow

```bash
# Human creates process specs
mkdir -p specs/process
vim specs/process/migration-plan.md
vim specs/process/phase-0-detail.md

# Configure ralph to find them
echo 'PROCESS_DIR="specs/process"' >> .ralph/config

# Run process planning
.ralph/ralph plan --process

# Review the generated plan
cat .ralph/implementation_plan.md

# Run build iterations
.ralph/ralph build 20

# If process specs change, regenerate
.ralph/ralph plan --process

# To switch to spec-based planning instead
rm .ralph/implementation_plan.md
.ralph/ralph plan
```
