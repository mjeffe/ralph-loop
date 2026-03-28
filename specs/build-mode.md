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
1. Read `implementation_plan.md`, including the `Plan Type:` header
2. Review tasks and their status/dependencies
3. Select the next task according to the plan type

**Plan-type-aware selection:**
- `Plan Type: gap-driven` — treat the plan as a priority list. Prefer the highest-priority
  `planned` task with no blocking dependencies. May choose out of order if there's a clear
  reason (document why).
- `Plan Type: process` — treat phase headings as authoritative ordering constraints. Select
  a ready `planned` task from the earliest incomplete phase. Do not skip to a later phase
  while an earlier phase has ready work. Within a phase, obey explicit sequencing and any
  `Depends on:` fields.
- If `Plan Type:` is absent, treat the plan as gap-driven (backward compatibility).

### Single Task Focus

Each build iteration should complete **one task only**. The agent is trusted to honor this without enforcement.

If during implementation the agent discovers:
- **A bug** - Document it as a new task in the plan
- **Missing supporting feature** - Document it as a new task
- **Need for new spec** - Create the spec and document the task

### Implementation Process

1. **Select task** from plan
2. **Implement the task** following the steps
3. **Run tests** - All tests must pass (see `AGENTS.md` for project test instructions)
4. **Fix any broken tests** - Even unrelated ones
5. **Update task status** to `complete` in plan
6. **Review remaining tasks** - Update any that are obsolete, incorrect, or mis-ordered
7. **Commit all changes** with a descriptive commit message
8. **Output completion signal** if no tasks remain

### Test Requirements

**All tests must pass before the iteration completes.**

The agent is responsible for running tests and fixing failures. The test process is described in `AGENTS.md` for the project.

If implementation breaks existing tests:
- Fix the broken tests
- Ensure all tests pass
- Do not commit broken code

### Git Commit

The agent is responsible for committing its own work at the end of each successful iteration. The commit message should describe what was implemented, not just the task number. Do not use `git add -A` or `git add .` — stage files explicitly. The agent should not commit until all tests pass.

### Plan Updates

The agent must update `implementation_plan.md` during the iteration:

**Required updates:**
- Change task status to `complete` when done
- Add any new tasks discovered during implementation

**Optional updates:**
- Add notes/learnings to the task
- Update dependencies if discovered
- Refine steps for future tasks

### Mid-Implementation Discoveries

During implementation, agents encounter situations not fully covered by the specs or plan. The
guiding principle is: **agents should always be making forward progress or explicitly stopping.**
Never silently expanding scope, never stuck on a decision they can't make.

#### Spec Gaps (Tactical Ambiguity)

When the spec is silent on a detail the agent needs to resolve now to finish the task:

1. Resolve using this precedence: spec → existing code/tests → repo conventions → framework conventions
2. If still unresolved, choose the simplest reasonable option that is consistent with existing
   patterns, local to the current task, and easy to change later
3. When in doubt, prefer validation errors over silent behavior, deny over allow for permissions,
   and preserve data over destructive changes
4. Add or update a test if the choice affects observable behavior
5. Document the choice in the task notes labeled `Assumption / Spec gap:`

If no safe default exists, or the choice affects a public/shared interface, signal a replan
(see Replan Signal below) instead of guessing.

These assumptions are provisional — humans should later accept them into the spec or correct
them via replanning.

#### Emerging Architecture

Agents may refine implementation details within the current task's scope. Signal a replan if
the discovery would:
- Change shared/public interfaces or core data models
- Require foundational work the plan missed, affecting multiple tasks (for a single missing
  prerequisite, mark the current task `blocked` and add the prerequisite to the plan)
- Force reworking or redefining multiple remaining tasks
- Make completed work wrong or likely throwaway

Otherwise, make the call, keep the change local, and document it in the plan.

#### Conflicting Sources of Truth

If the spec, code, tests, or plan disagree and correct intent cannot be safely inferred from
precedence rules, signal a replan.

#### New Work

**For small bugs or issues:**
1. Create a task in `implementation_plan.md`
2. Add a note that it was discovered during Task N implementation
3. If the fix is trivial (isolated, low-risk, ≤ ~5 lines) and directly adjacent to the current
   work, fix it now. Otherwise, leave it for a future iteration.

**For complex features:**
1. Create a new spec in `specs/`
2. Add task to plan referencing the new spec
3. Continue with current task

### Blocked Tasks

If a task cannot be completed:
1. Update task status to `blocked`
2. Document the blocking issue in task notes
3. Do not commit incomplete implementation — commit only safe changes (plan updates, docs) with
   passing validation, or revert
4. End the iteration (do not select another task)
5. Exit normally

The next iteration can select a different task or address the blocker.

### Completion Signal

When the agent determines all tasks are `complete` and none remain `planned` or `blocked`:
```
<promise>COMPLETE</promise>
```

This signals the loop to exit successfully.

Do not emit `COMPLETE` if any tasks remain `blocked` — blocked work means the plan is
incomplete, not done. If only `blocked` tasks remain, emit the replan signal instead.

### Replan Signal

When the agent determines the implementation plan is materially wrong (not just incomplete),
or when only `blocked` tasks remain and no forward progress is possible:
```
<promise>REPLAN</promise>
```

This signals the loop to exit build mode so the user can re-run the planning command
recorded in `Plan Command:` at the top of the plan. The agent should use this when:
- A discovery would change shared/public interfaces or core data models
- A discovery reveals foundational work the plan missed, affecting multiple tasks
- Multiple remaining tasks need reworking or redefining
- Completed work is wrong or likely throwaway due to changed assumptions
- The spec, code, tests, or plan conflict and correct intent is ambiguous
- The plan's structure no longer reflects the project's actual needs
- Only `blocked` tasks remain and no `planned` work is available

## Agent Responsibilities

During build mode, the agent should:

1. **Study `specs/README.md`** for an overview of all specs
2. **Study the implementation plan**
3. **Select one task** to implement
4. **Study the spec** referenced by the selected task
5. **Implement the task** following its steps
6. **Run all tests** and ensure they pass (per `AGENTS.md`)
7. **Fix any broken tests** (even unrelated ones)
8. **Update task status** to `complete`
9. **Review remaining planned tasks** — update any that are obsolete, incorrect, or mis-ordered
10. **Update the plan** with any new tasks discovered
11. **Keep `specs/README.md` current** — update it if specs are added or removed
12. **Commit all changes** with a descriptive message
13. **Output completion signal** if no tasks remain
14. **Output replan signal** if the plan needs significant restructuring

## Prompt Template

The following is the canonical prompt template for build mode. It lives at `prompts/build.md` and is used by the ralph loop to invoke the agent.

```markdown
You are an expert software developer working in Ralph build mode.

Each iteration starts with **fresh context** — you have no memory of prior iterations. Treat repo files as the sole source of truth: `${RALPH_HOME}/implementation_plan.md`, `${SPECS_DIR}/`, `AGENTS.md`, and git history.

## Operating Contract

- You have full autonomy in implementation decisions unless the spec defines specific constraints, tooling, or architectural choices — those take precedence.
- Read the `Plan Type:` header from `${RALPH_HOME}/implementation_plan.md` before selecting work.
- If `Plan Type: process`, phase headings are authoritative. Do not select a task from a later phase while an earlier phase has a ready task. Within a phase, obey explicit sequencing and any `Depends on:` fields.
- If `Plan Type: gap-driven` (or absent), treat the plan as a priority list. You may choose a different ready task when there is a clear reason, but document why in the plan.
- Complete **exactly one task** this iteration.
- Before editing, inspect the current code and tests — do not assume the task is unimplemented.
- All project validation (tests, lint, build — see AGENTS.md) must pass before you commit.
- Do not commit broken or partial code.
- If blocked, mark the task `blocked`, document why in the plan, and stop. Do not commit incomplete implementation — commit only safe changes (plan updates, docs) with passing validation, or revert.
- Implement functionality completely. Placeholders and stubs waste time redoing the same work.

## Context

- **Specifications:** ${SPECS_DIR}
- **Specs Index:** ${SPECS_DIR}/README.md
- **Implementation Plan:** ${RALPH_HOME}/implementation_plan.md
- **Project instructions:** AGENTS.md

## Workflow

1. Read `AGENTS.md`, `${SPECS_DIR}/README.md`, and `${RALPH_HOME}/implementation_plan.md` (including the `Plan Type:` header).
2. Select the next task according to the plan type:
   - `gap-driven` (or absent): select the highest-priority ready `planned` task; only go out of order with a documented reason.
   - `process`: select a ready `planned` task from the earliest incomplete phase. Do not skip to a later phase while earlier ready work exists.
3. Read the referenced spec and inspect relevant code and tests.
4. Implement the task.
5. Add or update targeted tests when appropriate — especially for bug fixes and user-visible behavior changes. Use judgment: skip brittle or high-setup tests for pure refactors or trivial wiring; if you skip meaningful coverage, note it in the plan.
6. If the task includes a `Verify:` block, execute its checks after implementation. If verification fails, fix the issue before proceeding. If it cannot be fixed within the task's scope, mark the task `blocked`.
7. Run the project's required validation from AGENTS.md. Fix failures caused by your changes. If unrelated failures are quick, fix them too. If they are substantial, mark the task `blocked` and document the issue rather than expanding scope.
8. Update `${RALPH_HOME}/implementation_plan.md`:
   - Mark the task `complete`
   - Add a brief note on what changed
   - Add any newly discovered tasks (note which task surfaced them)
   - Adjust any remaining tasks that are now obsolete, incorrect, or mis-ordered
9. Commit all changes with a descriptive commit message.
10. If all tasks are `complete` (none `planned` or `blocked`), output the completion signal (see Exit Signals).
11. If only `blocked` tasks remain (no `planned` work available), output the replan signal (see Exit Signals).
12. If the plan needs major restructuring, output the replan signal (see Exit Signals).

## Exit Signals

- **All tasks done:** output exactly `<promise>COMPLETE</promise>` — the loop cannot exit without it. Do not emit this if any tasks remain `blocked`.
- **Plan needs restructuring or only blocked tasks remain:** output exactly `<promise>REPLAN</promise>` to trigger re-planning.

## Mid-Implementation Discoveries

### Spec gaps (tactical ambiguity)
When the spec is silent on a detail you need right now to finish the task:

1. Resolve using this order: **spec → existing code/tests → repo conventions → framework conventions**.
2. If still unresolved, choose the simplest reasonable option that is consistent with existing patterns, local to this task, and easy to change later.
3. When in doubt, prefer validation errors over silent behavior, deny over allow for permissions, and preserve data over destructive changes.
4. Add or update a test if the choice affects observable behavior.
5. Document the choice in the task notes labeled `Assumption / Spec gap:`.

If no safe default exists, or the choice affects a public/shared interface, output the replan signal instead of guessing.

### Emerging architecture
You may refine implementation details within the current task's scope. Output the replan signal if the discovery would:
- change shared/public interfaces or core data models
- require foundational work the plan missed, affecting multiple tasks (for a single missing prerequisite, mark the current task `blocked` and add the prerequisite to the plan)
- force reworking or redefining multiple remaining tasks
- make completed work wrong or likely throwaway

Otherwise, make the call, keep the change local, and document it in the plan.

### Conflicting sources of truth
If the spec, code, tests, or plan disagree and correct intent cannot be safely inferred, output the replan signal.

### New work
**Small bugs or issues:**
1. Create a task in the plan, noting it was discovered during Task N.
2. If the fix is trivial (isolated, low-risk, ≤ ~5 lines) and directly adjacent to your current work, fix it now. Otherwise, leave it for a future iteration.

**Complex features:**
1. Create a new spec in `${SPECS_DIR}/`.
2. Add a task to the plan referencing the new spec.
3. Continue with your current task.

## Task Status Values

- `planned` — ready to work on
- `blocked` — cannot proceed
- `complete` — finished and committed

## Secondary Maintenance

- Keep `${SPECS_DIR}/README.md` current if you add or remove specs.
- When you learn something new about running the project, update AGENTS.md — keep it brief and operational only. Status updates and progress notes belong in the plan.

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
- All tasks `complete`, none `planned` or `blocked`
- `<promise>COMPLETE</promise>` output
- Loop exits with code 0

### Replan
- Agent determines plan needs restructuring, or only `blocked` tasks remain
- `<promise>REPLAN</promise>` output
- Loop exits with code 3
- Human reruns the command recorded in `Plan Command:` at the top of the plan

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
