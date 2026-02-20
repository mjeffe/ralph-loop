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
4. **Run tests** - All tests must pass
5. **Fix any broken tests** - Even unrelated ones
6. **Update task status** to `complete` in plan
7. **Output completion** if no tasks remain

### Test Requirements

**All tests must pass before the iteration completes.**

If implementation breaks existing tests:
- Fix the broken tests
- Ensure all tests pass
- Do not commit broken code

If tests fail after fixes:
- Iteration is marked as failed
- Retry up to 3 times
- If still failing after retries, exit with code 3

Test command is defined in `AGENTS.md`.

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

**For bugs or small issues:**
```markdown
### Task N+1: Fix bug in X module
**Status:** planned
**Spec:** specs/existing-spec.md
**Dependencies:** Task N
**Estimated Complexity:** low

**Steps:**
1. Reproduce the bug
2. Fix the issue
3. Add test coverage

**Notes:**
Discovered during Task N implementation.
```

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

## Agent Responsibilities

During build mode, the agent should:

1. **Read the implementation plan**
2. **Select one task** to implement
3. **Update task status** to `in-progress`
4. **Implement the task** following its steps
5. **Run all tests** and ensure they pass
6. **Fix any broken tests** (even unrelated ones)
7. **Update task status** to `complete`
8. **Update the plan** with any new tasks discovered
9. **Output completion signal** if no tasks remain

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
- Changes committed
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

### Failure
- Tests fail after retries
- Loop exits with code 3
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
1. Task completed and tests pass (success)
2. Task blocked (success, but no progress)
3. Tests fail after retries (failure)
4. Agent failure after retries (failure)
5. No changes detected (failure)

Build mode session exits when:
1. `<promise>COMPLETE</promise>` detected (success)
2. Max iterations reached (success, incomplete)
3. Failure exit from iteration (failure)
