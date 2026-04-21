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
2. **Spec Alignment** - For each spec requirement, assess whether the repo satisfies it in all material ways — checking both implementation and directly affected descriptive artifacts (help text, README, prompts, error strings). Cite evidence for "Already Satisfied" determinations; structural existence alone is insufficient.
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

Below the metadata and summary, the plan includes a `## Cross-cutting constraints` section.
This section starts empty or with spec-derived constraints and accumulates build-agent
discoveries over time — reusable patterns, naming conventions, or non-obvious constraints
that would affect correctness or verification of future tasks. Without a dedicated section,
agents recorded these findings in individual task notes where they were effectively invisible
to subsequent iterations. By placing this section in the plan header — which is injected into
every build iteration via `${PLAN_HEADER}` — it is always visible without agents needing to
search for it. See `specs/build-mode.md` for the infrastructure-managed plan context that
makes this work.

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

The canonical prompt template lives at `prompts/plan.md`. It is the source of truth for
the exact prompt wording and is used by the ralph loop to invoke the agent. Refer to that
file directly rather than duplicating it here.

## Iterative Planning

For large projects, the agent may need multiple iterations. The plan file itself is the durable progress marker — each iteration commits its work, and the next iteration reads the plan to determine what phases have been completed. For example:

- **Iteration 1:** Inventory the codebase, begin spec alignment, write findings to the plan file
- **Iteration 2:** Continue spec alignment, begin task decomposition
- **Iteration 3:** Complete task decomposition, order by dependencies, output `<promise>COMPLETE</promise>`

The agent uses its judgment on how to break up the work across iterations.

## Task Sizing Heuristic

When decomposing work into tasks, group by **logical cohesion** rather than maximizing granularity:

- **Group related changes** that produce one coherent outcome or share one acceptance criterion
  into one task — including small adjacent help/docs/prompt updates triggered by the main change
- **Reserve separate tasks** for things that are independently testable or have distinct complexity
- **Ask: "Would I commit these together?"** — if yes, they belong in one task

A task that is "create file X" where X is a simple template copy is too small on its own — combine
it with related setup work. A task that is "implement the full ralph script" is appropriately sized
because it's a single coherent deliverable even if it's complex.

Do not create build tasks whose sole purpose is to verify whether an apparently implemented
requirement is already done when planning can answer that from repo evidence. If the evidence
is insufficient, create a focused investigation task and note the uncertainty.

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
