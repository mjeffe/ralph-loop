# Build Mode

## Purpose

Build mode implements one task from the implementation plan per iteration. It focuses on incremental progress with fresh context, ensuring all tests pass before committing.

## Prerequisites

Build mode requires `implementation_plan.md` to exist. If missing, it exits with code 2 and message:
```
Implementation plan not found. Run 'ralph plan' first.
```

## Behavior

### Task Selection

The agent should:
1. Read `implementation_plan.md`
2. Review tasks and their status/dependencies
3. Select the most important task to work on

**Guidance:**
- Tasks are ordered by the plan, but agent has freedom to choose
- Prefer tasks with status `planned` and no blocking dependencies
- May choose out of order if there's good reason (document why)

### Single Task Focus

Each build iteration should complete **one task only**. The agent is trusted to honor this without enforcement.

If during implementation the agent discovers:
- **A bug** - Document it as a new task in the plan
- **Missing supporting feature** - Document it as a new task
- **Need for new spec** - Create the spec and document the task

### Implementation Process

1. **Select task** from plan
2. **Update task status** to `in-progress` in plan
3. **Implement the task** following the steps
4. **Run tests** - All tests must pass (see `AGENTS.md` for project test instructions)
5. **Fix any broken tests** - Even unrelated ones
6. **Update task status** to `complete` in plan
7. **Review remaining tasks** - Update any that are obsolete, incorrect, or mis-ordered
8. **Commit all changes** with a descriptive commit message
9. **Output completion signal** if no tasks remain

### Test Requirements

**All tests must pass before the iteration completes.**

The agent is responsible for running tests and fixing failures. The test process is described in `AGENTS.md` for the project.

If implementation breaks existing tests:
- Fix the broken tests
- Ensure all tests pass
- Do not commit broken code

### Git Commit

The agent is responsible for committing its own work at the end of each successful iteration:

```bash
git add -A
git commit -m "build: <short description of what was implemented>"
```

The commit message should describe what was implemented, not just the task number. The agent should not commit until all tests pass.

### Plan Updates

The agent must update `implementation_plan.md` during the iteration:

**Required updates:**
- Change task status from `planned` to `in-progress` at start
- Change task status to `complete` when done
- Add any new tasks discovered during implementation

**Optional updates:**
- Add notes/learnings to the task
- Update dependencies if discovered
- Refine steps for future tasks

### Discovering New Work

If the agent discovers additional work needed:

**For small bugs or issues:**
1. Create a task in @implementation_plan.md
2. Add a note that it was discovered during Task N implementation
3. If the fix is trivial (isolated, low-risk, ≤ ~5 lines), fix it now and include it in this iteration's commit. Otherwise, leave it for a future iteration.

**For complex features:**
1. Create a new spec in `specs/`
2. Add task to plan referencing the new spec
3. Continue with current task

### Blocked Tasks

If a task cannot be completed:
1. Update task status to `blocked`
2. Document the blocking issue in task notes
3. End the iteration (do not select another task)
4. Exit normally

The next iteration can select a different task or address the blocker.

### Completion Signal

When the agent determines all tasks are complete:
```
<promise>COMPLETE</promise>
```

This signals the loop to exit successfully.

### Replan Signal

When the agent determines the implementation plan needs significant restructuring:
```
<promise>REPLAN</promise>
```

This signals the loop to exit build mode so the user can re-run `ralph plan`. The agent should use this when:
- Multiple remaining tasks are obsolete or incorrect due to implementation changes
- Task dependencies have shifted fundamentally
- The plan's structure no longer reflects the project's actual needs

## Agent Responsibilities

During build mode, the agent should:

1. **Study `specs/README.md`** for an overview of all specs
2. **Study the implementation plan**
3. **Select one task** to implement
4. **Study the spec** referenced by the selected task
5. **Update task status** to `in-progress`
6. **Implement the task** following its steps
7. **Run all tests** and ensure they pass (per `AGENTS.md`)
8. **Fix any broken tests** (even unrelated ones)
9. **Update task status** to `complete`
10. **Review remaining planned tasks** — update any that are obsolete, incorrect, or mis-ordered
11. **Update the plan** with any new tasks discovered
12. **Keep `specs/README.md` current** — update it if specs are added or removed
13. **Commit all changes** with a descriptive message
14. **Output completion signal** if no tasks remain
15. **Output replan signal** if the plan needs significant restructuring

## Prompt Template

The following is the canonical prompt template for build mode. It lives at `prompts/build.md` and is used by the ralph loop to invoke the agent.

```markdown
You are an expert software developer working in Ralph build mode.

## Your Mission

Your task is to implement functionality per the specifications using parallel subagents. Follow ${RALPH_HOME}/implementation_plan.md and choose the most important item to address. Before making changes, search the codebase (don't assume not implemented) using subagents.

## Context

- **Specifications:** ${SPECS_DIR}
- **Specs Index:** ${SPECS_DIR}/README.md
- **Implementation Plan:** ${RALPH_HOME}/implementation_plan.md

## Your Responsibilities

1. Study ${SPECS_DIR}/README.md for an overview of all specs
2. Study ${RALPH_HOME}/implementation_plan.md
3. Select ONE task to implement (prefer tasks with status "planned" and no blockers)
4. Study the spec referenced by the task to understand full requirements and constraints
5. Update task status to "in-progress"
6. Implement the task following its steps
7. Run all tests (see AGENTS.md for test instructions)
8. Fix any broken tests (even unrelated ones)
9. Update task status to "complete"
10. Review remaining planned tasks — if your changes made any obsolete, incorrect, or mis-ordered, update them
11. Add any new tasks discovered during implementation
12. Keep ${SPECS_DIR}/README.md current — update it if you add or remove specs
13. Commit all changes with a descriptive commit message
14. If no tasks remain, output: <promise>COMPLETE</promise>
15. If the plan needs significant restructuring, output: <promise>REPLAN</promise>

## Discovering New Work

If you discover additional work needed:

**For small bugs or issues:**
1. Create a task in ${RALPH_HOME}/implementation_plan.md
2. Add a note that it was discovered during Task N implementation
3. If the fix is trivial (isolated, low-risk, ≤ ~5 lines), fix it now and include it in this iteration's commit. Otherwise, leave it for a future iteration.

**For complex features:**
1. Create a new spec in `specs/`
2. Add task to plan referencing the new spec
3. Continue with current task

## Critical Rules

- **ONE TASK ONLY** per iteration
- **ALL TESTS MUST PASS** before you commit
- **DO NOT COMMIT BROKEN CODE**
- If you discover new work, add it to the plan but don't do it now
- If a task is blocked, mark it "blocked" and end iteration
- If the plan needs significant restructuring, output `<promise>REPLAN</promise>` to trigger re-planning
- **OUTPUT THE COMPLETION SIGNAL** when all tasks are done — this is mandatory, not optional

## Task Status Values

- `planned` - Ready to work on
- `in-progress` - Currently implementing
- `blocked` - Cannot proceed
- `complete` - Finished and committed

## Important

- Focus on one task
- Keep tests passing
- Update the plan as you work
- Document your progress
- For any bugs you notice, resolve them or document them in ${RALPH_HOME}/implementation_plan.md using a subagent even if it is unrelated to the current piece of work.
- Implement functionality completely. Placeholders and stubs waste efforts and time redoing the same work.
- When you learn something new about how to run the application, update AGENTS.md using a subagent but keep it brief. For example if you run commands multiple times before learning the correct command then that file should be updated.
- Keep AGENTS.md operational only — status updates and progress notes belong in implementation_plan.md. A bloated AGENTS.md pollutes every future loop's context.
- **When all tasks are done, you MUST output `<promise>COMPLETE</promise>` — the loop cannot
  exit without it. Do not skip this step.**

Begin implementation now.
```

## Example Iteration

### Before
```markdown
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
```

### After
```markdown
### Task 3: Add authentication endpoints
**Status:** complete
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
Completed in iteration 5. All tests passing. JWT secret configured via
JWT_SECRET environment variable. Token expiry set to 24 hours as specified.

---

### Task 4: Add password reset flow
**Status:** planned
**Spec:** specs/authentication.md
**Dependencies:** Task 3
**Estimated Complexity:** medium

**Steps:**
1. Create /forgot-password endpoint
2. Generate reset tokens
3. Send reset email
4. Create /reset-password endpoint
5. Add tests

**Notes:**
Discovered during Task 3 - password reset was mentioned in spec but not
originally broken out as separate task.
```

## Iteration Outcomes

### Success
- Task completed
- Tests passing
- Plan updated
- Changes committed by agent
- Continue to next iteration

### Blocked
- Task cannot proceed
- Status updated to `blocked`
- Reason documented
- Changes committed (if any)
- Continue to next iteration (different task)

### Complete
- All tasks done
- `<promise>COMPLETE</promise>` output
- Loop exits with code 0

### Replan
- Agent determines plan needs restructuring
- `<promise>REPLAN</promise>` output
- Loop exits with code 3
- Human runs `ralph plan` to regenerate

### Failure
- Agent crashes or times out after retries
- Loop exits with code 4
- Human intervention needed

## Best Practices

### Task Sizing
Tasks should be:
- Completable in one iteration
- Testable
- Independently committable
- Clearly defined

If a task is too large, break it into subtasks in the plan.

### Test-Driven
- Run tests frequently during implementation
- Fix tests as you go
- Don't accumulate test failures
- All tests must pass before commit

### Documentation
- Update plan as you work
- Document discoveries
- Add notes for future tasks
- Keep plan current

### Focus
- One task per iteration
- Don't scope creep
- Document new work, don't do it now
- Trust the loop to handle it later

## Exit Criteria

Build mode iteration exits when:
1. Task completed, tests pass, and changes committed (success)
2. Task blocked (success, but no progress)
3. Replan signal output (plan needs restructuring)
4. Agent failure after retries (failure)

Build mode session exits when:
1. `<promise>COMPLETE</promise>` detected (success)
2. `<promise>REPLAN</promise>` detected (replan needed, exit code 3)
3. Max iterations reached (success, incomplete)
4. Agent failure exit from iteration (failure)
