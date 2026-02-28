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

All agent types produce NDJSON output. The loop invokes the agent CLI by piping the substituted prompt to stdin, routing agent stdout to three destinations simultaneously:

```bash
cat "$PROMPT_FILE" | $AGENT_CLI $AGENT_ARGS 2>>"$SESSION_LOG" \
    | tee -a "$SESSION_LOG" \
    | tee >(eval "$AGENT_DISPLAY_FILTER" 2>/dev/null >&2 || true; cat >/dev/null) \
    > "$RALPH_DIR/last_agent_output"
```

This pattern:
- Pipes the prompt to the agent via stdin
- Routes agent stderr directly to the session log (`2>>"$SESSION_LOG"`), keeping it out of the NDJSON stream (some agent CLIs write terminal escape sequences to stderr on exit)
- Appends raw NDJSON output to the session log (`tee -a "$SESSION_LOG"`)
- Streams filtered output to the terminal in real-time via process substitution
- Captures raw output to `last_agent_output` for completion signal scanning

#### Agent Types

Ralph uses `AGENT_TYPE` to select built-in presets for the agent CLI, output parsing, and terminal display. Supported types:

| Type | CLI | Description |
|------|-----|-------------|
| `amp` | `amp` | Amp CLI with `--stream-json` |
| `claude` | `claude` | Claude Code CLI with `--output-format stream-json` |
| `cline` | `cline` | Cline CLI with `--json` |
| `codex` | `codex` | OpenAI Codex CLI with `--json` |

Each type provides defaults for four variables: `AGENT_CLI`, `AGENT_ARGS`, `AGENT_RESPONSE_FILTER`, and `AGENT_DISPLAY_FILTER`. Additionally, agent types may define `AGENT_USAGE_CMD` and `AGENT_USAGE_PARSER` for per-iteration cost tracking (see [Usage Tracking](#usage-tracking)). Any of these can be overridden individually in the config file — explicit config values take precedence over built-in defaults.

The defaults are defined in the ralph script via a `load_agent_defaults` function, called after config is sourced. It uses the `${VAR:=default}` pattern so that config-supplied values are never overwritten.

#### Display Filter

The `AGENT_DISPLAY_FILTER` (a `jq` expression set per agent type) extracts human-readable text from the NDJSON stream for real-time terminal display. It runs inside a process substitution with a drain fallback:

```bash
>(eval "$AGENT_DISPLAY_FILTER" 2>/dev/null >&2 || true; cat >/dev/null)
```

If the display filter fails for any reason, `cat >/dev/null` takes over reading from the pipe to prevent `tee` from receiving SIGPIPE. This makes the display filter purely cosmetic — it can never crash the pipeline.

#### Raw Output File

The raw agent output is written to `$RALPH_DIR/last_agent_output`, overwritten each iteration. This file is used for completion signal detection and is available for debugging after a failed run.

The agent is invoked with the **project root as its working directory**. This is always `.` from the perspective of the agent, regardless of where the `ralph` script physically lives.

### Completion Detection

The loop scans agent output for the exact string:
```
<promise>COMPLETE</promise>
```

After the agent finishes, the loop extracts the agent's response text from the raw output file (`last_agent_output`) using `AGENT_RESPONSE_FILTER` (a jq expression), then checks the extracted text for the completion signal. This avoids false positives from agents that echo the prompt back in their output (e.g., `amp` includes the prompt as a `user` type message in its JSON stream — the prompt itself contains the completion signal as an instruction to the agent). The response filter only selects `assistant` type messages, so echoed prompts are excluded.

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

Agent types may optionally define `AGENT_USAGE_CMD` and `AGENT_USAGE_PARSER` to enable per-iteration cost tracking. When configured, the loop queries the agent's balance before and after each iteration, computes the cost, and displays both in the iteration footer.

| Variable | Purpose | Example (amp) |
|----------|---------|---------------|
| `AGENT_USAGE_CMD` | Command to query account balance | `amp usage` |
| `AGENT_USAGE_PARSER` | Pipeline to extract the numeric dollar amount from the command's output | `grep -o '$[0-9.]*' \| head -1 \| tr -d '$'` |

When both variables are set, the iteration footer includes `Iteration Cost` and `Balance` lines. When unset (the default for most agent types), no usage information is displayed.

Currently configured for: `amp`.

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
