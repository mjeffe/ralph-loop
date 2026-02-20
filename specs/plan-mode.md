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

The `implementation_plan.md` file should contain:

### Required Sections

#### 1. Plan Status
Current state of the planning process:
```markdown
## Plan Status

Status: Complete
Last Updated: 2026-02-20 12:00:00
Phases Completed: Inventory, Spec Alignment, Task Decomposition, Ordering
```

#### 2. Project Overview
High-level understanding of the project:
```markdown
## Project Overview

Brief description of what this project does, key technologies, architecture notes.
```

#### 3. Spec Coverage
Which specs have been analyzed:
```markdown
## Spec Coverage

- [x] specs/feature-1.md - Analyzed
- [x] specs/feature-2.md - Analyzed
- [ ] specs/feature-3.md - Not yet analyzed
```

#### 4. Tasks
Ordered list of implementation tasks:
```markdown
## Tasks

### Task 1: [Short Description]
**Status:** planned | in-progress | blocked | complete
**Spec:** specs/feature-1.md
**Dependencies:** None
**Estimated Complexity:** low | medium | high

**Steps:**
1. Step one
2. Step two
3. Step three

**Notes:**
Any relevant context, gotchas, or learnings.

---

### Task 2: [Short Description]
...
```

#### 5. Notes & Learnings (Optional)
```markdown
## Notes & Learnings

- Important constraint discovered during analysis
- Gotcha about X module
- Dependency on external service Y
```

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

## Human Interaction

Humans can:
- **Delete** `implementation_plan.md` to force re-planning
- **Edit** specs to change desired behavior
- **Run** `ralph plan` at any time to regenerate the plan

The plan is always regenerated from scratch, ensuring it reflects current specs and code state.

## Example Plan

```markdown
# Implementation Plan

## Plan Status

Status: Complete
Last Updated: 2026-02-20 12:00:00
Phases Completed: All

## Project Overview

This is a web application built with Node.js and Express. It provides a REST API
for managing user accounts and authentication.

## Spec Coverage

- [x] specs/authentication.md
- [x] specs/user-management.md
- [x] specs/api-design.md

## Tasks

### Task 1: Set up Express server
**Status:** complete
**Spec:** specs/api-design.md
**Dependencies:** None
**Estimated Complexity:** low

**Steps:**
1. Install Express
2. Create server.js
3. Configure middleware
4. Add health check endpoint

**Notes:**
Using Express 4.x as specified.

---

### Task 2: Implement user model
**Status:** complete
**Spec:** specs/user-management.md
**Dependencies:** Task 1
**Estimated Complexity:** medium

**Steps:**
1. Define user schema
2. Create User model
3. Add validation
4. Write unit tests

---

### Task 3: Add authentication endpoints
**Status:** planned
**Spec:** specs/authentication.md
**Dependencies:** Task 2
**Estimated Complexity:** high

**Steps:**
1. Install passport.js
2. Configure JWT strategy
3. Create /login endpoint
4. Create /register endpoint
5. Add authentication middleware
6. Write integration tests

**Notes:**
Must use JWT tokens as specified. Token expiry set to 24 hours.

## Notes & Learnings

- Using bcrypt for password hashing (cost factor 10)
- JWT secret should be in environment variable
- Database connection string in .env file
```

## Exit Criteria

Plan mode exits when:
1. Agent outputs `<promise>COMPLETE</promise>` (success)
2. Max iterations reached (incomplete but valid)
3. Agent failure exceeds retries (error)

After successful plan mode, build mode can begin.
