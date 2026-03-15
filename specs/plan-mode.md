# Plan Mode

## Purpose

Plan mode analyzes specifications and source code to create or regenerate an ordered implementation plan. It reconciles the desired state (specs) with the current state (code) and produces a task list for build mode.

This spec covers **gap-driven planning** — comparing target-state specs to the current codebase to infer what work remains. For **sequence-constrained planning** from human-authored process specs (migrations, phased refactors, ordered rollouts), see `specs/process-planning.md`.

## Behavior

### Single or Multiple Iterations

Plan mode can complete in a single iteration for small projects, or span multiple iterations for large projects. The agent decides based on project size and complexity.

### Planning Phases

The plan prompt describes these phases as guidance:

1. **Inventory** - Identify key modules, components, and areas of the codebase
2. **Spec Alignment** - For each spec, identify gaps between desired and current behavior
3. **Task Decomposition** - Break gaps into discrete, ordered tasks with clear steps
4. **Dependency Ordering** - Order tasks based on dependencies and logical sequence

The agent may:
- Complete all phases in one iteration (small projects)
- Complete one phase per iteration (large projects)
- Use its own judgment on how to break up the work

### Plan Regeneration

When the agent finds an existing plan with tasks marked `complete` (from prior build iterations), it regenerates the task list from scratch by comparing specs to current code. It may carry forward useful notes/learnings, but the task list and ordering are rebuilt fresh. This ensures the plan stays aligned with current reality.

When the plan contains only planning-phase progress (inventory, gap notes, partial task list with no `complete` tasks), the agent continues from where it left off rather than rebuilding.

### Completion

Plan mode completes when the agent outputs:
```
<promise>COMPLETE</promise>
```

This signals that the plan is comprehensive and ready for build mode.

## Implementation Plan Format

The `implementation_plan.md` file lives at the root of the ralph script directory (e.g.,
`.ralph/implementation_plan.md` in a parent project, or `implementation_plan.md` in the
ralph-loop repo itself).

The plan begins with a metadata header:
- `Plan Type: gap-driven`
- `Plan Command: ralph plan`

The rest is a prioritized list of work to be done. At minimum, each task needs:
- A short title
- A brief description of what needs to be done
- The **spec** that drives it (e.g., `specs/feature.md`)
- A **status**: `planned` | `blocked` | `complete`
- Enough context for build mode to start work without re-surveying the entire project

Tasks should be ordered by priority. Structure and format beyond that are up to the agent.

### Task Status Values

- `planned` - Ready to be worked on
- `blocked` - Cannot proceed (dependency or issue)
- `complete` - Finished and committed

## Agent Responsibilities

During plan mode, the agent should:

1. **Study `specs/README.md`** for an overview of all specs
2. **Study all specs** in `specs/` directory
3. **Analyze the project** to understand current state
4. **Identify gaps** between specs and code
5. **Create ordered tasks** that will close the gaps
6. **Document dependencies** between tasks
7. **Update plan status** to track progress through phases
8. **Keep `specs/README.md` current** — update it if specs are added or removed
9. Commit all changes with a descriptive commit message
10. **Output completion signal** when planning is done

## Prompt Template

The following is the canonical prompt template for plan mode. It lives at `prompts/plan.md` and is used by the ralph loop to invoke the agent.

```markdown
You are an expert software architect and planner working in Ralph plan mode.

Each iteration starts with **fresh context** — you have no memory of prior iterations. Treat repo files as the sole source of truth: `${SPECS_DIR}/`, `AGENTS.md`, git history, and any existing `${RALPH_HOME}/implementation_plan.md`.

## Operating Contract

- You have full autonomy in how you decompose, order, and describe tasks. Specs define *what* to build; you decide how to break it into buildable units.
- **Do not implement product code** — plan mode produces only the implementation plan, spec index updates, and commits.
- Do not invent requirements. If a spec is silent on a detail that affects task scope, surface it as a planning note — do not encode assumptions about product behavior into tasks.
- When in doubt, prefer conservative framing: validation over silent behavior, deny over allow, preserve data over destructive changes.
- Commit your plan updates at the end of each iteration with a descriptive commit message.

## Context

- **Specifications:** ${SPECS_DIR}
- **Specs Index:** ${SPECS_DIR}/README.md
- **Implementation Plan:** ${RALPH_HOME}/implementation_plan.md
- **Project instructions:** AGENTS.md

## Workflow

Work through these phases in order. For small projects, complete all phases in one iteration. For large projects, complete what you can — the plan file is your durable progress marker across fresh-context iterations.

1. **Read inputs** — Study `AGENTS.md`, `${SPECS_DIR}/README.md`, and all specs. If `${RALPH_HOME}/implementation_plan.md` exists, read it to understand prior progress.
2. **Inventory** — Survey the codebase and identify key modules, components, and areas.
3. **Spec alignment** — For each spec, identify gaps between desired behavior and current state.
4. **Task decomposition** — Break gaps into discrete, ordered tasks (see Task Format below).
5. **Dependency ordering** — Order tasks by dependencies, then by logical sequence. Use a stable heuristic: foundational/infrastructure first, then core features, then refinements.
6. **Write the plan** — Create or update `${RALPH_HOME}/implementation_plan.md`. If the plan already contains tasks marked `complete` (from prior build iterations), rebuild the task list from scratch — you may carry forward useful notes but the task list and ordering are rebuilt fresh. If the plan contains only planning-phase progress (inventory, gap notes, partial task list with no `complete` tasks), continue from where it left off.
7. **Commit** all changes with a descriptive commit message.
8. **If planning is complete**, output the completion signal (see Exit Signal). Planning is complete when: every spec has been reviewed, every gap is tasked or noted as already satisfied, dependencies are coherent, and tasks are build-iteration-sized.
9. **If planning is not yet complete**, stop without outputting a signal — the loop will start another iteration automatically and your plan file will carry your progress forward.

## Exit Signal

When planning is complete, output exactly `<promise>COMPLETE</promise>` — the loop cannot exit without it.

## Task Format

At the top of `${RALPH_HOME}/implementation_plan.md`, include:
- `Plan Type: gap-driven`
- `Plan Command: ralph plan`

Each task needs at minimum:
- A short title
- A brief description of what needs to be done
- The **spec** that drives it (e.g., `specs/feature.md`)
- A **status**: `planned` | `blocked` | `complete`
- Enough context for a build agent to start work without re-surveying the entire project

Order tasks by priority. Structure and format beyond that are up to you.

## Task Sizing

Group by **logical cohesion** rather than maximizing granularity:
- **Group related changes** that serve a single purpose into one task
- **Reserve separate tasks** for things that are independently testable or have distinct complexity
- **Ask: "Would I commit these together?"** — if yes, they belong in one task
- Each task should be completable in one build iteration and committable as a single logical unit

## Planning Discoveries

### Spec gaps
When a spec is silent on a detail that affects how you decompose or order tasks:
1. Resolve using this order: **spec → existing code/tests → repo conventions → framework conventions**.
2. If the gap is purely about task breakdown (not product behavior), make a reasonable choice and note it in the task.
3. If the gap affects product behavior, public interfaces, or security/data semantics, do **not** decide it — add a planning note labeled `Spec gap:` describing the ambiguity so the human can address it.

### Conflicting sources of truth
If specs, code, or tests disagree on intended behavior, note the conflict in the affected task(s) labeled `Conflict:` rather than silently choosing a side.

## Task Status Values

- `planned` — ready to work on
- `blocked` — cannot proceed (document why in the task)
- `complete` — finished and committed

## Secondary Maintenance

- Keep `${SPECS_DIR}/README.md` current if you add or remove specs.

Begin planning now.
```

## Iterative Planning

For large projects, the agent may need multiple iterations. The plan file itself is the durable progress marker — each iteration commits its work, and the next iteration reads the plan to determine what phases have been completed. For example:

- **Iteration 1:** Inventory the codebase, begin spec alignment, write findings to the plan file
- **Iteration 2:** Continue spec alignment, begin task decomposition
- **Iteration 3:** Complete task decomposition, order by dependencies, output `<promise>COMPLETE</promise>`

The agent uses its judgment on how to break up the work across iterations.

## Task Sizing Heuristic

When decomposing work into tasks, group by **logical cohesion** rather than maximizing granularity:

- **Group related file creation/edits** that serve a single purpose into one task (e.g., creating
  a directory, its files, and verifying a `.gitignore` entry are all "set up supporting files")
- **Reserve separate tasks** for things that are independently testable or have distinct complexity
- **Ask: "Would I commit these together?"** — if yes, they belong in one task

A task that is "create file X" where X is a simple template copy is too small on its own — combine
it with related setup work. A task that is "implement the full ralph script" is appropriately sized
because it's a single coherent deliverable even if it's complex.

Each task should be:
- Completable in one build iteration
- Independently verifiable (clear "done" state)
- Committable as a single logical unit

## Human Interaction

Humans can:
- **Delete** `implementation_plan.md` to force re-planning
- **Edit** specs to change desired behavior
- **Run** `ralph plan` at any time to regenerate the plan

When the existing plan contains completed tasks from prior build iterations, it is regenerated from scratch, ensuring it reflects current specs and code state.

## Example Plan

```markdown
# Implementation Plan

Plan Type: gap-driven
Plan Command: ralph plan

### Task 1: Set up Express server
**Status:** complete
**Spec:** specs/api-design.md
Create an Express server with middleware and a health check endpoint.

### Task 2: Implement user model
**Status:** complete
**Spec:** specs/user-management.md
Define the user schema, create the User model with validation, and write unit tests.

### Task 3: Add authentication endpoints
**Status:** planned
**Spec:** specs/authentication.md
Implement /login and /register endpoints using JWT strategy via passport.js.
Token expiry 24 hours per spec. Requires Task 2.
```

## Exit Criteria

Plan mode exits when:
1. Agent outputs `<promise>COMPLETE</promise>` (success)
2. Max iterations reached (incomplete but valid)
3. Agent failure exceeds retries (error)

After successful plan mode, build mode can begin.
