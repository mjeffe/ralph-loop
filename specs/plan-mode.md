# Plan Mode

## Purpose

Plan mode analyzes specifications and source code to create or regenerate an ordered implementation plan. It reconciles the desired state (specs) with the current state (code) and produces a task list for build mode.

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

Plan mode **always regenerates** `implementation_plan.md` from scratch by comparing specs to code. This ensures the plan stays aligned with current reality.

The agent may:
- Carry forward useful notes/learnings from a previous plan if one exists
- But the task list and ordering are rebuilt fresh

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

The plan is a prioritized list of work to be done. At minimum, each task needs:
- A short title
- A brief description of what needs to be done
- The **spec** that drives it (e.g., `specs/feature.md`)
- A **status**: `planned` | `in-progress` | `blocked` | `complete`
- Enough detail for build mode to implement it without re-analyzing the project

Tasks should be ordered by priority. Structure and format beyond that are up to the agent.

### Task Status Values

- `planned` - Ready to be worked on
- `in-progress` - Currently being implemented (build mode)
- `blocked` - Cannot proceed (dependency or issue)
- `complete` - Finished and committed

## Agent Responsibilities

During plan mode, the agent should:

1. **Read `specs/README.md`** for an overview of all specs
2. **Read all specs** in `specs/` directory
3. **Analyze the project** to understand current state
4. **Identify gaps** between specs and code
5. **Create ordered tasks** that will close the gaps
6. **Document dependencies** between tasks
7. **Update plan status** to track progress through phases
8. **Keep `specs/README.md` current** — update it if specs are added or removed
9. **Output completion signal** when planning is done

## Prompt Template

The following is the canonical prompt template for plan mode. It lives at `prompts/plan.md` and is used by the ralph loop to invoke the agent.

```markdown
You are an expert software architect and planner working in Ralph plan mode.

## Your Mission

Analyze the project specifications and source code to create a comprehensive implementation plan.

## Context

- **Specifications:** ${SPECS_DIR}
- **Specs Index:** ${SPECS_DIR}/README.md
- **Implementation Plan:** implementation_plan.md

## Planning Phases

Work through these phases systematically:

1. **Inventory** - Survey the codebase and identify key modules/components
2. **Spec Alignment** - For each spec, identify gaps between desired and current behavior
3. **Task Decomposition** - Break gaps into discrete, ordered tasks with clear steps
4. **Dependency Ordering** - Order tasks based on dependencies and logical sequence

For small projects, you may complete all phases in one iteration.
For large projects, complete what you can and update the plan status to indicate progress.

## Your Responsibilities

1. Read ${SPECS_DIR}/README.md for an overview of all specs
2. Read all specifications in ${SPECS_DIR}
3. Analyze the project codebase to understand current state
4. Identify gaps between specs and code
5. Create ordered tasks in implementation_plan.md
6. Document dependencies between tasks
7. Update plan status to track your progress
8. Keep ${SPECS_DIR}/README.md current — update it if you add or remove specs
9. When planning is complete, output: <promise>COMPLETE</promise>

## Implementation Plan

Create or update `implementation_plan.md` — a prioritized list of work to be done. Keep it
concise and actionable. At minimum, each task needs:
- A short title
- A brief description of what needs to be done
- The **spec** that drives it (e.g., `specs/feature.md`)
- A **status**: `planned` | `in-progress` | `blocked` | `complete`
- Enough detail for build mode to implement it without re-analyzing the project

Order tasks by priority. Structure and format beyond that are up to you.

## Important

- Be thorough but cost-conscious
- Break large work into manageable tasks
- Order tasks logically by dependencies
- Document your learnings and gotchas
- **OUTPUT THE COMPLETION SIGNAL** when finished planning — this is mandatory, not optional

Begin planning now.
```

## Iterative Planning

For large projects, the agent may need multiple iterations:

### Iteration 1: Inventory
- Survey the codebase
- List major modules/components
- Create high-level plan outline
- Update plan status: "Inventory complete"

### Iteration 2: Spec Alignment
- For each spec, identify what exists vs. what's needed
- Document gaps
- Update plan status: "Spec alignment complete"

### Iteration 3: Task Decomposition
- Break gaps into specific tasks
- Write steps for each task
- Update plan status: "Task decomposition complete"

### Iteration 4: Ordering
- Order tasks by dependencies
- Mark any blocked tasks
- Update plan status: "Complete"
- Output `<promise>COMPLETE</promise>`

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

The plan is always regenerated from scratch, ensuring it reflects current specs and code state.

## Example Plan

```markdown
# Implementation Plan

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
