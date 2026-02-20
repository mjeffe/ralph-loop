# Agent Configuration

## Overview

This document provides agent-specific configuration and instructions for the Ralph Wiggum Loop. It serves as a reference for both the Ralph loop script and the agents themselves.

## Supported Agents

### Cline

**CLI Command:** `cline`

**Installation:**
- Install Cline VSCode extension
- Ensure Cline CLI is available in PATH

**Invocation:**
```bash
cline --prompt-file <prompt_file>
```

**Output Parsing:**
- Stdout contains agent responses
- Completion signal: `<promise>COMPLETE</promise>` in stdout

**Statistics:**
- Token usage: Available in Cline output (if enabled)
- Cost: Available in Cline output (if enabled)
- Model: Available in Cline output (if enabled)

### Future Agents

Additional agents can be added by:
1. Documenting CLI invocation method
2. Specifying output format
3. Defining completion signal format
4. Documenting statistics availability

## Test Configuration

### Purpose

Tests ensure that code changes don't break existing functionality. All tests must pass before committing in build mode.

### Test Command

Define the test command in `ralph/config`:

```bash
TEST_COMMAND="npm test"
```

Examples for different project types:

**Node.js:**
```bash
TEST_COMMAND="npm test"
```

**Python:**
```bash
TEST_COMMAND="pytest"
```

**Go:**
```bash
TEST_COMMAND="go test ./..."
```

**PHP:**
```bash
TEST_COMMAND="./vendor/bin/phpunit"
```

**Ruby:**
```bash
TEST_COMMAND="bundle exec rspec"
```

**No tests:**
```bash
TEST_COMMAND=""  # Empty string disables test requirement
```

### Test Execution

In build mode, after the agent completes implementation:

1. Ralph runs the test command
2. If exit code is 0: tests passed, proceed to commit
3. If exit code is non-zero: tests failed, retry iteration

### Test Failures

If tests fail:
- Agent should fix the failing tests
- All tests must pass before iteration completes
- If tests still fail after 3 retries, loop exits with code 3

### Test Best Practices

**For Agents:**
- Run tests frequently during implementation
- Fix tests as you go
- Don't accumulate test failures
- If you break unrelated tests, fix them

**For Humans:**
- Keep test suite fast (faster feedback)
- Ensure tests are reliable (no flaky tests)
- Document test requirements in specs
- Keep TEST_COMMAND up to date

## Agent Invocation

### Environment

Agents are invoked with:
- Working directory: Project root
- Fresh context (no conversation history)
- Prompt file with template variables substituted

### Template Variables

Available in prompts:
- `${PROJECT_ROOT}` - Project root directory
- `${SRC_DIR}` - Source code directory
- `${SPECS_DIR}` - Specifications directory
- `${RALPH_DIR}` - Ralph installation directory
- `${PLAN_PATH}` - Path to implementation_plan.md
- `${ITERATION}` - Current iteration number
- `${MODE}` - Current mode (plan/build/prompt)

### Prompt Files

**Plan mode:** `ralph/prompts/plan.md`
**Build mode:** `ralph/prompts/build.md`
**Ad-hoc mode:** User-specified file

### Output Handling

Agent output is:
- Streamed to stderr (human sees real-time progress)
- Written to session log
- Scanned for completion signal

### Completion Signal

Agents signal completion by outputting:
```
<promise>COMPLETE</promise>
```

This must be an exact match in stdout.

## Agent Responsibilities

### Plan Mode

1. Read all specs in `${SPECS_DIR}`
2. Analyze source code in `${SRC_DIR}`
3. Identify gaps between specs and code
4. Create/update `${PLAN_PATH}` with ordered tasks
5. Document dependencies and learnings
6. Output completion signal when done

### Build Mode

1. Read `${PLAN_PATH}`
2. Select ONE task to implement
3. Update task status to `in-progress`
4. Implement the task
5. Run tests (via TEST_COMMAND)
6. Fix any broken tests
7. Update task status to `complete`
8. Add any new tasks discovered
9. Output completion signal if no tasks remain

### Ad-hoc Prompt Mode

1. Execute the custom prompt
2. Make changes as directed
3. No completion signal required
4. No test requirement

## Agent Guidelines

### Context Management

- Each iteration starts fresh (no history)
- Read persistent state from files
- Write state back to files
- Trust the loop to maintain continuity

### Cost Consciousness

- Be thorough but efficient
- Don't over-analyze
- Focus on the task at hand
- Use context wisely

### Error Handling

If you encounter errors:
- Document them in the plan
- Mark tasks as blocked if needed
- Don't fail silently
- Provide clear error messages

### Communication

- Update the plan as you work
- Document discoveries and learnings
- Add notes for future iterations
- Be explicit about blockers

## Troubleshooting

### Agent Not Found

If Ralph can't find the agent CLI:
- Verify agent is installed
- Check PATH includes agent location
- Update AGENT_CLI in ralph/config

### Tests Not Running

If tests aren't executing:
- Verify TEST_COMMAND in ralph/config
- Test the command manually
- Check test dependencies are installed

### Completion Signal Not Detected

If loop doesn't exit when complete:
- Verify exact string: `<promise>COMPLETE</promise>`
- Check it's in stdout (not stderr)
- Ensure no extra whitespace or formatting

### Agent Failures

If agent repeatedly fails:
- Check agent logs for errors
- Verify prompt file is valid
- Ensure project is in valid state
- Check for resource constraints (memory, disk)

## Statistics Collection

Ralph attempts to collect these statistics per iteration:
- Start time (always available)
- End time (always available)
- Duration (always available)
- API requests (agent-dependent)
- Model used (agent-dependent)
- Message count (agent-dependent)
- Total cost (agent-dependent)

Statistics are logged in iteration footers when available.

## Future Enhancements

Potential future additions:
- Support for more agents
- Agent-specific configuration
- Custom completion signals per agent
- Enhanced statistics collection
- Agent health checks
- Timeout configuration
