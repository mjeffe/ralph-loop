# Loop Behavior

## Overview

The Ralph loop orchestrates iterative agent execution with fresh context per iteration while maintaining persistent state between runs.

## CLI Interface

```bash
# In the ralph-loop project (ralph at root)
ralph <mode> [max_iterations]

# In a parent project (ralph installed in .ralph/)
.ralph/ralph <mode> [max_iterations]

# In a parent project with symlink (ln -s .ralph/ralph ralph)
ralph <mode> [max_iterations]
```

### Modes

- `plan [max_iterations]` - Run plan mode iterations
- `build [max_iterations]` - Run build mode iterations
- `prompt <file> [max_iterations]` - Run an ad-hoc prompt in the loop

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

Ralph delegates all agent-specific logic to pluggable agent scripts (see `specs/agent-scripts.md`).
The active agent is selected by the `AGENT` variable in `config`, and ralph sources the
corresponding script from `agents/${AGENT}.sh` at startup.

The loop invokes the agent and routes output through a linear pipeline:

```bash
agent_invoke "$prompt" \
    | tee "$RALPH_DIR/last_agent_output" \
    | agent_format_display \
    | tee -a "$SESSION_LOG"
```

This pattern:
- Invokes the agent via `agent_invoke` (defined in the agent script), which pipes the prompt to the agent CLI via stdin
- Captures the raw output to `last_agent_output` for post-iteration signal detection
- Streams the output through `agent_format_display` (defined in the agent script), which converts the raw output to human-readable text in real time using per-line processing
- Writes the filtered, human-readable output to both the terminal and the session log

The session log contains exactly what the human sees on the terminal — filtered, readable output
rather than raw NDJSON. The raw output is available in `last_agent_output` (overwritten each
iteration) for signal detection and debugging.

#### Stderr Handling

Ralph does not redirect agent stderr. It flows directly to the user's terminal, ensuring that
CLI errors (authentication failures, network errors, agent crashes) are immediately visible.
Agent scripts control stderr handling in their `agent_invoke` function if needed. Since stderr
is not part of the stdout pipeline, it cannot interfere with output capture or display filtering.

#### Pipeline Robustness

Both `agent_format_display` and `agent_extract_response` must process output line by line
(using `while IFS= read -r line` loops) rather than passing the full stream or file to jq.
This is critical because:
- A malformed line in whole-file jq mode causes jq to abort, sending SIGPIPE back through the
  pipeline and potentially terminating the agent mid-run
- Per-line processing skips bad lines and continues, keeping the pipeline intact
- The `while read` loop is inherently line-buffered, ensuring real-time terminal display

See `specs/agent-scripts.md` for the full function contract and examples.

#### Optional Hooks

Agent scripts may define `agent_pre_iteration` and `agent_post_iteration` hook functions for
tasks like cost tracking. Ralph checks for their existence at runtime and calls them if present.
See `specs/agent-scripts.md` for details.

The agent is invoked with the **project root as its working directory**. This is always `.` from the perspective of the agent, regardless of where the `ralph` script physically lives.

### Completion Detection

The loop scans agent output for the exact string:
```
<promise>COMPLETE</promise>
```

After the agent finishes, the loop extracts the agent's response text from the raw output file (`last_agent_output`) using `agent_extract_response` (defined in the agent script), then checks the extracted text for the completion signal. This avoids false positives from agents that echo the prompt back in their output (e.g., `amp` includes the prompt as a `user` type message in its JSON stream — the prompt itself contains the completion signal as an instruction to the agent). The response extraction function only selects agent response messages, so echoed prompts are excluded.

When detected:
- Current iteration completes normally
- Loop exits with success code 0
- Final summary is written to log

The loop also scans for:
```
<promise>REPLAN</promise>
```

When detected:
- Current iteration completes normally
- Loop exits with code 3
- Message displayed: "Agent requested re-planning. Run 'ralph plan' to regenerate the implementation plan."

### Git Operations

The **agent** is responsible for all git operations (add, commit, push) as part of completing its task. The loop does not commit on behalf of the agent.

### Exit Conditions

Loop exits when any of these occur:

1. **Completion signal detected** - Exit code 0
2. **Max iterations reached** - Exit code 0 (success, but incomplete)
3. **Replan signal detected** - Exit code 3
4. **Plan missing (build mode)** - Exit code 2
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
Iteration Cost: ${ITER_COST} (if usage tracking configured)
Balance: ${BALANCE} (if usage tracking configured)
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

## Usage Tracking

Agent scripts may optionally define `agent_pre_iteration` and `agent_post_iteration` hook
functions to enable per-iteration cost tracking. Ralph checks for these functions at runtime
and calls them if present. See `specs/agent-scripts.md` for the hook contract and examples.

When hooks are defined, they can query the agent's account balance before and after each
iteration, compute the cost, and log it using the `log` function provided by ralph. When
hooks are not defined, no usage information is displayed.

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
