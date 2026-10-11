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

- `plan [max_iterations]` - Run gap-driven plan mode iterations (from target-state specs)
- `plan --process [max_iterations]` - Run sequence-constrained plan mode iterations (from process specs). Requires `PROCESS_DIR` in config. See `specs/process-planning.md`.
- `build [max_iterations]` - Run build mode iterations
- `prompt <file> [max_iterations]` - Run an ad-hoc prompt in the loop
- `help [topic]` - Show operational guidance (overview, specs, plan, build, prompt, sandbox, align-specs, retro)
- `version` (or `--version`) - Print the installed version: the upstream commit recorded in
  `.version` by `install.sh`/`update.sh`, the checkout's `HEAD` when run from a ralph-loop
  source checkout, or "unknown version". Runs before config loading and prerequisite checks.

The `--process` flag is only valid with `plan`. If used with `build`, `prompt`, or other
modes, ralph exits with an error: "--process is only valid with 'ralph plan'."

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
   - The agent script sets `AGENT_OUTPUT_FORMAT` (otherwise: error naming the agent script
     and saying its output parser is not implemented yet; this is how cline and codex are
     reported as unsupported, see `tech-debt.md` item 7)
   - `python3` is available (runs `lib/format_output.py`)
   - Agent CLI is available
   - Required directories exist
3. Validate mode-specific prerequisites (e.g., implementation plan exists for build mode)
4. Create session log file: `logs/session-YYYYMMDD-HHMMSS-MODE.log` (relative to ralph script directory). The log file is created **after** all validation passes, immediately before entering the loop. This prevents empty log files from early-exit validation failures. Modes that do not use the loop (`update`, `sandbox`, `help`) do not create log files.
5. Initialize iteration counter

### Iteration Flow

Each iteration follows this sequence:

```
1. Pre-iteration checks
2. Write iteration header to log
3. Substitute template variables into prompt
4. Invoke agent with prompt
5. Stream formatted agent output to terminal and log simultaneously
6. Read the processor's summary: failure checks, signal, context, cost
7. Write iteration footer to log (including post-iteration hook output)
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
| `${RALPH_HOME}` | runtime | Relative path from project root to Ralph's directory (e.g., `.ralph` or `.`) |

Custom variables can be added to `config` and will be available automatically via `envsubst`.

### Agent Invocation

Ralph delegates all agent-specific logic to pluggable agent scripts (see `specs/agent-scripts.md`).
The active agent is selected by the `AGENT` variable in `config`, and ralph sources the
corresponding script from `agents/${AGENT}.sh` at startup.

The loop invokes the agent and routes output through a linear pipeline:

```bash
agent_invoke "$tmp_prompt" \
    | tee "$RALPH_DIR/last_agent_output" \
    | python3 "$RALPH_DIR/lib/format_output.py" --format "$AGENT_OUTPUT_FORMAT" \
        --summary "$summary_file" --log "$SESSION_LOG"
```

This pattern:
- Invokes the agent via `agent_invoke` (defined in the agent script), which pipes the prompt to the agent CLI via stdin
- Captures the raw output to `last_agent_output` (overwritten each iteration) as the debug
  record and the source of test fixtures
- Streams the output through `lib/format_output.py` (see `output-pipeline.md`) using the
  stream schema the agent script declares in `AGENT_OUTPUT_FORMAT`. In one pass it writes the
  screen display to stdout, appends the session log itself, and writes a summary JSON
  (signal, response size, error state, context usage, cost) to a temp file that ralph reads
  after the agent exits

The screen shows thinking, assistant text, tool calls, and tool errors. The session log
gets the same lines plus successful tool results (one line each) and the detail of failed
tool results, so the log is a superset of the screen, not identical to it. ralph's own `log`
lines (iteration headers and footers) are appended to the same file, before and after the
processor runs. Full tool output is in neither: see "Screen vs. Log" in `output-pipeline.md`.

#### Stderr Handling

Ralph does not redirect agent stderr. It flows directly to the user's terminal, ensuring that
CLI errors (authentication failures, network errors, agent crashes) are immediately visible.
Agent scripts control stderr handling in their `agent_invoke` function if needed. Since stderr
is not part of the stdout pipeline, it cannot interfere with output capture or display filtering.
The processor's own diagnostics also go to stderr and are not copied to the session log.

#### Pipeline Robustness

`lib/format_output.py` guarantees (see "Robustness" in `output-pipeline.md`):
- Malformed lines (stderr leakage, partial writes, invalid UTF-8) never stop processing: a
  non-JSON line is shown raw and counted, and a line whose handling raises is skipped with
  one stderr line
- It flushes stdout and the log after every write, so the display and `tail -f` on the
  session log stay live
- If stdout breaks, it keeps reading stdin to EOF so the agent CLI is not killed by
  SIGPIPE, keeps writing the log, and still writes the summary
- The summary is written in a `finally` block, so it exists even after an unexpected
  exception. If the processor crashes outright and writes no summary, ralph reads an empty
  `response_chars` and treats the iteration as an empty response (retried)

#### Optional Hooks

Every shipped agent script defines `agent_pre_iteration` and `agent_post_iteration` (a no-op
when there is nothing to do), so the extension point is visible to anyone copying a script.
Ralph still checks for their existence at runtime and calls them if present, so user-written
agents without hooks keep working. `agent_pre_iteration` runs before `agent_invoke`.
`agent_post_iteration` runs after ralph logs the stream's context and cost, with
`RALPH_ITER_SUMMARY` pointing at the summary JSON. See `specs/agent-scripts.md` for details.

The agent is invoked with the **project root as its working directory**. This is always `.` from the perspective of the agent, regardless of where the `ralph` script physically lives.

### Completion Detection

The loop looks for the exact string:
```
<promise>COMPLETE</promise>
```

The signal is decided by `lib/format_output.py`, which scans **only assistant-authored,
top-level response text** and reports the result in the summary's `signal` field. Echoed
prompts, tool results, thinking, subagent output, and final `result` lines are never
scanned. Every ralph prompt contains the signal string as an instruction, agents echo the
prompt (amp emits it as a `user` message, pi as a `message_end` with `role: "user"`), and
agents routinely read prompt and spec files, so tool results contain it too. Scanning
anything wider produces false completions. See "Signal Detection Constraint" in
`output-pipeline.md`.

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
- Ralph reads the `Plan Command:` line from `${RALPH_HOME}/implementation_plan.md` if present
- Message displayed: "Agent requested re-planning. Run '`<Plan Command>`' to regenerate the implementation plan."
- If no `Plan Command:` line is found, fall back to: "Agent requested re-planning. Run 'ralph plan' to regenerate the implementation plan."

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
7. **Process build: no eligible task** - Checked before each iteration (see `build-mode.md`).
   All tasks complete → exit code 0; blocked or unready tasks remain → exit code 3 (with the
   same re-planning message as the replan signal)
8. **Process build: no progress** - The same task is selected in two consecutive iterations
   (the previous iteration neither completed nor blocked it) - Exit code 6
9. **Invalid plan** - The plan fails validation at the start of build/align-specs, before a
   build iteration, or after a plan session emits the completion signal - Exit code 1, with
   each problem listed (see "Plan Parsing and Validation" in `build-mode.md`)

## Iteration Logging

### Iteration Header

Written at start of each iteration:

```
================================================================================
ITERATION ${ITERATION}  ${TIMESTAMP}
mode: ${MODE}  prompt: ${PROMPT_TEMPLATE}
================================================================================
```

### Iteration Footer

Written at end of each iteration:

```
================================================================================
ITERATION ${ITERATION} DONE in ${DURATION}s ----
Context: ${TOKENS_USED}/${MAX_TOKENS} tokens (${PCT}%)   (or "Context: ${TOKENS_USED} tokens")
Iteration Cost: $${COST}  (4 decimals)                  (when the stream reports cost)
<agent_post_iteration output, e.g. amp: Iteration Cost: $X  Balance: $Y; pi: Model: ...>
⚠ Context usage high — agent quality may degrade         (when PCT >= CONTEXT_WARN_PCT)
================================================================================
```

The Context and Iteration Cost lines come from the processor summary and appear only when
the stream exposes the values. The context warning is checked after the hook, so a hook
that overrides `_ITER_CONTEXT_PCT` is honored.

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
Context: min ${MIN}% / avg ${AVG}% / max ${MAX}%  (window: ${WINDOW} tokens) (if context tracking available)
Exit Reason: ${EXIT_REASON}
Exit Code: ${EXIT_CODE}
================================================================================
```

## Usage Tracking

Context usage and cost come from the agent's stream, parsed by `lib/format_output.py`, and
ralph logs whatever the summary reports (see "Iteration Footer"). Per format:
- `stream-json`: context used. claude also reports the window and cost in its `result`
  line. amp reports no window since its 2026-10-11 release, so it gets no percentage
  (`tech-debt.md` item 8)
- `pi-json`: context used and cost; no window (`tech-debt.md` item 5), so no percentage
- `text`: nothing

Out-of-band usage stays in the agent's hooks. amp's stream carries no cost, so
`agents/amp.sh` captures the account balance in `agent_pre_iteration` and logs the delta in
`agent_post_iteration`. See `specs/agent-scripts.md` for the hook contract.

### Context Tracking

After each iteration, ralph sets `_ITER_CONTEXT_USED`, `_ITER_CONTEXT_MAX`, and
`_ITER_CONTEXT_PCT` from the summary (`context_used`, `context_max`, `context_pct`; empty when
unavailable). `agent_post_iteration` may override them. When `_ITER_CONTEXT_PCT` is set, the
loop aggregates it across iterations and includes min/avg/max percentages in the session
summary.

If context usage meets or exceeds `CONTEXT_WARN_PCT` (default: 80), ralph logs a warning.
High context usage correlates with degraded agent quality — the fresh-context-
per-iteration design mitigates this, but large tasks can still push a single iteration high.

## Error Handling

### Agent Failures

An iteration fails only when the agent CLI (or the pipeline) exits non-zero, the summary
reports `is_error: true` (logged as "Agent reported an error: <error>"), or the agent
produced no response. A missing signal is normal and counts as a successful iteration.

On failure:
1. Log the failure
2. Increment retry counter for this iteration
3. If retries < 3: retry the same iteration
4. If retries >= 3: exit with code 4

### Empty Response Detection

After each agent invocation, the loop reads `response_chars` from the processor summary. If
the agent exited successfully (code 0) but `response_chars` is 0 or missing, the iteration is
treated as a failure and enters the retry path. This catches budget exhaustion,
authentication expiry, and transient errors where the agent CLI exits cleanly but does no
work. A missing value means the processor wrote no summary (for example, it crashed), which
is retried the same way. If retries are also exhausted, the loop exits with code 4.

### Retry Strategy

- Each iteration can be retried up to 3 times (configurable via `MAX_RETRIES` in config)
- Retry counter is per-iteration (resets to zero for each new iteration)
- Retries use the same prompt/task

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
