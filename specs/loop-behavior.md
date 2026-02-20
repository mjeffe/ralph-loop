# Loop Behavior

## Overview

The Ralph loop orchestrates iterative agent execution with fresh context per iteration while maintaining persistent state between runs.

## CLI Interface

```bash
# In the ralph-loop project (ralph at root)
ralph <mode> [max_iterations] [options]

# In a parent project (ralph installed in .ralph/)
.ralph/ralph <mode> [max_iterations] [options]

# In a parent project with symlink (ln -s .ralph/ralph ralph)
ralph <mode> [max_iterations] [options]
```

### Modes

- `plan [max_iterations]` - Run plan mode iterations
- `build [max_iterations]` - Run build mode iterations  
- `prompt <file>` - Run a single ad-hoc prompt from file

### Options

- `--max-iterations N` - Maximum iterations (default: 10)
- `--config PATH` - Path to config file (default: config, relative to ralph script directory)

### Examples

```bash
# Run plan mode (single or multiple iterations until complete)
./ralph plan

# Run up to 20 build iterations
./ralph build 20

# Run a custom one-off prompt
./ralph prompt prompts/refactor-analysis.md
```

## Loop Execution

### Initialization

1. Load configuration from `config` (relative to ralph script directory)
2. Validate prerequisites:
   - Git repository exists
   - Agent CLI is available
   - Required directories exist
3. Create session log file: `logs/session-YYYYMMDD-HHMMSS.log` (relative to ralph script directory)
4. Initialize iteration counter

### Iteration Flow

Each iteration follows this sequence:

```
1. Pre-iteration checks
2. Write iteration header to log
3. Invoke agent with appropriate prompt
4. Stream agent output (tee to stderr and log)
5. Check for completion signal
6. Run tests (build mode only)
7. Git commit
8. Write iteration footer to log
9. Check exit conditions
```

### Pre-iteration Checks

**Build mode only:**
- Verify `implementation_plan.md` exists
- If missing: exit with code 2 and message "Implementation plan not found. Run 'ralph plan' first."

### Agent Invocation

The loop invokes the agent CLI with:
- The appropriate prompt (with template variables substituted)
- Fresh context (no conversation history)
- Project directory as working directory

Agent output is captured and:
- Streamed to stderr (human sees real-time progress)
- Written to session log
- Scanned for completion signal

### Completion Detection

The loop scans agent stdout for the exact string:
```
<promise>COMPLETE</promise>
```

When detected:
- Current iteration completes normally
- Loop exits with success code 0
- Final summary is written to log

### Test Execution (Build Mode)

After agent completes but before git commit:

1. Run test command from `AGENTS.md`
2. If tests fail:
   - Mark iteration as failed
   - Increment retry counter
   - If retries < max retries (3): retry iteration
   - If retries >= max retries: exit with code 3
3. If tests pass: proceed to commit

### Git Commit

Last step of each successful iteration:

```bash
git add -A
git commit -m "<mode>: iteration ${ITERATION} - ${TASK_DESCRIPTION}"
```

Commit message includes:
- Mode (plan/build/prompt)
- Iteration number
- Short task description (from plan or prompt)

If commit fails:
- Log error
- Mark iteration as failed
- Retry iteration (up to max retries)

### Exit Conditions

Loop exits when any of these occur:

1. **Completion signal detected** - Exit code 0
2. **Max iterations reached** - Exit code 0 (success, but incomplete)
3. **Plan missing (build mode)** - Exit code 2
4. **Test failures exceed retries** - Exit code 3
5. **Agent failure exceeds retries** - Exit code 4
6. **Git operation failure** - Exit code 5

## Iteration Logging

### Iteration Header

Written at start of each iteration:

```
================================================================================
ITERATION ${ITERATION}
================================================================================
Mode: ${MODE}
Task: ${TASK_DESCRIPTION}
Spec: ${ASSOCIATED_SPEC}
Start Time: ${TIMESTAMP}
--------------------------------------------------------------------------------
```

### Iteration Footer

Written at end of each iteration:

```
--------------------------------------------------------------------------------
ITERATION ${ITERATION} COMPLETE
End Time: ${TIMESTAMP}
Duration: ${DURATION}
API Requests: ${API_REQUESTS} (if available)
Model: ${MODEL} (if available)
Messages: ${MESSAGE_COUNT} (if available)
Cost: ${COST} (if available)
Status: ${STATUS}
================================================================================

```

### Session Summary

Written when loop exits:

```
================================================================================
SESSION SUMMARY
================================================================================
Total Iterations: ${TOTAL}
Successful: ${SUCCESS_COUNT}
Failed: ${FAIL_COUNT}
Total Duration: ${TOTAL_DURATION}
Exit Reason: ${EXIT_REASON}
Exit Code: ${EXIT_CODE}
================================================================================
```

## Error Handling

### Agent Failures

If agent crashes, times out, or returns malformed output:
1. Log the failure
2. Increment retry counter for this iteration
3. If retries < 3: retry the same iteration
4. If retries >= 3: exit with code 4

### No Changes Detected

If agent completes but `git status` shows no changes:
1. Treat as failure
2. Log "No changes detected"
3. Retry iteration (up to max retries)

### Retry Strategy

- Each iteration can be retried up to 3 times
- Retry counter resets on successful iteration
- Retries use the same prompt/task
- Retry count is logged in iteration footer

## State Management

### Persistent State (Between Iterations)

- `implementation_plan.md` - Updated by agents
- `specs/*.md` - Source of truth (human-edited)
- Source code - Modified by agents
- Git history - Audit trail
- Session log - Complete record

### Transient State (Within Session)

- Iteration counter
- Retry counters
- Session start time
- Current task description
- Agent statistics (if available)

## Ad-hoc Prompt Mode

Special mode for one-off agent invocations:

```bash
ralph prompt path/to/custom-prompt.md
```

Behavior:
- Runs agent once with the specified prompt
- Uses same logging and environment as loop modes
- Does NOT iterate
- Does NOT check for completion signal
- Does NOT enforce test requirements
- DOES commit changes if any
- Useful for exploration, analysis, or custom tasks

Exit codes:
- 0: Success
- 4: Agent failure
- 5: Git failure
