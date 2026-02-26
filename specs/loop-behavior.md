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
- `prompt <file> [max_iterations]` - Run an ad-hoc prompt in the loop

### Options

- `--config PATH` - Path to config file (default: `config` relative to ralph script directory)

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

1. Load configuration from `config` (relative to ralph script directory), or from `--config PATH` if provided
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
3. Substitute template variables into prompt
4. Invoke agent with prompt
5. Stream agent output to terminal and log simultaneously
6. Check for completion signal
7. Write iteration footer to log
8. Check exit conditions
```

### Pre-iteration Checks

**Build mode only:**
- Verify `implementation_plan.md` exists (relative to ralph script directory)
- If missing: exit with code 2 and message "Implementation plan not found. Run 'ralph plan' first."

### Template Variable Substitution

Before invoking the agent, the loop substitutes variables into the prompt template using `envsubst`. All variables defined in `config` are available, plus any runtime variables set by the loop.

Default variables available in prompts:

| Variable | Source | Value |
|----------|--------|-------|
| `${SPECS_DIR}` | config | e.g., `specs` |
| `${MODE}` | runtime | `plan`, `build`, or `prompt` |

Custom variables can be added to `config` and will be available automatically via `envsubst`.

### Agent Invocation

The loop invokes the agent CLI by piping the substituted prompt to stdin:

```bash
output=$(cat "$PROMPT_FILE" | $AGENT_CLI $AGENT_ARGS 2>&1 | tee /dev/stderr | tee -a "$SESSION_LOG")
```

This pattern:
- Pipes the prompt to the agent via stdin
- Merges agent stderr into stdout (`2>&1`)
- Streams output to the terminal in real-time (`tee /dev/stderr`)
- Appends output to the session log (`tee -a "$SESSION_LOG"`)
- Captures full output in `$output` for completion signal scanning

#### Display Filter

Some agents (e.g., `amp` with `--stream-json-thinking`) produce structured output that is not human-readable by default. The optional `AGENT_DISPLAY_FILTER` config variable specifies a command to pipe agent output through for terminal display.

When `AGENT_DISPLAY_FILTER` is set, the invocation becomes:

```bash
output=$(cat "$PROMPT_FILE" | $AGENT_CLI $AGENT_ARGS 2>&1 \
    | tee >(eval "$AGENT_DISPLAY_FILTER" >&2) \
    | tee -a "$SESSION_LOG")
```

This uses process substitution to fork the filtered output to stderr for real-time display, while the raw output still flows into `$output` and the session log for completion signal scanning.

When `AGENT_DISPLAY_FILTER` is empty or unset, the original `tee /dev/stderr` behavior is used, which is appropriate for agents that already produce readable output (e.g., `cline --verbose`).

The agent is invoked with the **project root as its working directory**. This is always `.` from the perspective of the agent, regardless of where the `ralph` script physically lives.

### Completion Detection

The loop scans agent output for the exact string:
```
<promise>COMPLETE</promise>
```

When detected:
- Current iteration completes normally
- Loop exits with success code 0
- Final summary is written to log

### Git Operations

The **agent** is responsible for all git operations (add, commit, push) as part of completing its task. The loop does not commit on behalf of the agent.

### Exit Conditions

Loop exits when any of these occur:

1. **Completion signal detected** - Exit code 0
2. **Max iterations reached** - Exit code 0 (success, but incomplete)
3. **Plan missing (build mode)** - Exit code 2
4. **Agent failure exceeds retries** - Exit code 4
5. **Git operation failure** - Exit code 5

## Iteration Logging

### Iteration Header

Written at start of each iteration:

```
================================================================================
ITERATION ${ITERATION}
================================================================================
Mode: ${MODE}
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

### Retry Strategy

- Each iteration can be retried up to 3 times (configurable via `MAX_RETRIES` in config)
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
- Agent statistics (if available)

## Ad-hoc Prompt Mode

Special mode for running a custom prompt in the loop:

```bash
ralph prompt path/to/custom-prompt.md [max_iterations]
```

Behavior:
- Reads the specified file as the prompt template
- Applies `envsubst` template variable substitution (same as plan/build modes)
- **Validates** that the prompt file contains `<promise>COMPLETE</promise>` before starting;
  exits with an error if the signal is absent (the loop cannot exit cleanly without it)
- Runs the same loop as plan/build modes: iterates up to `max_iterations`, retries on agent
  failure, and exits when the completion signal is detected
- Uses the same logging format as other modes
- The agent decides whether to commit based on the prompt's instructions
- Useful for exploration, analysis, refactoring, or any ad-hoc task

Exit codes:
- 0: Completion signal detected or max iterations reached
- 1: Prompt file missing completion signal (pre-flight check failure)
- 4: Agent failure exceeded retries
