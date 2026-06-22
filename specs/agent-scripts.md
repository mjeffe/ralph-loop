# Agent Scripts

## Overview

Agent scripts encapsulate all agent-specific logic — CLI invocation, output parsing, display
formatting, and optional cost tracking — behind a small set of known functions. This keeps the
ralph controller agent-agnostic and makes adding or swapping agents a matter of writing one
shell script.

## Location and Naming

Agent scripts live in the `agents/` directory (relative to the ralph script directory) and are
named `{agent_name}.sh`:

```
agents/
  amp.sh
  claude.sh
  cline.sh
  codex.sh
  pi.sh
```

The active agent is selected by the `AGENT` variable in `config`:

```bash
AGENT="amp"
```

Ralph sources the agent script at startup:

```bash
source "$RALPH_DIR/agents/${AGENT}.sh"
```

If the script does not exist, ralph exits with an error.

## Function Contract

### Required Functions

Agent scripts **must** define these functions:

#### `agent_invoke <prompt_file>`

Invokes the agent CLI with the given prompt file. Structured output (typically NDJSON) must be
written to stdout. Ralph captures stdout for signal detection and display filtering.

Agent stderr is **not redirected by ralph** — it flows directly to the user's terminal. This
ensures that CLI errors (authentication failures, network errors, crashes) are immediately
visible to the human operator. Agent scripts should not suppress stderr unless they have a
specific reason to filter it (e.g., removing known cosmetic noise while preserving real errors).

```bash
agent_invoke() {
    local prompt_file="$1"
    cat "$prompt_file" | $AGENT_CLI $AGENT_ARGS
}
```

#### `agent_extract_response <output_file>`

Extracts the agent's response text from the raw output file. This is used for completion and
replan signal detection. It must output only the agent's own response text (not echoed prompts
or tool calls) to stdout.

This function **must process the file line by line** rather than passing the entire file to jq.
Agent output may contain malformed lines (stderr leakage, partial writes, etc.), and whole-file
jq will abort on the first bad line, potentially missing the completion signal. Per-line
processing skips bad lines and continues.

```bash
agent_extract_response() {
    local output_file="$1"
    while IFS= read -r line; do
        echo "$line" | jq -r 'select(.type=="assistant") | .message.content[] | select(.type=="text") | .text' 2>/dev/null || true
    done < "$output_file"
}
```

#### `agent_format_display`

A streaming filter that reads raw agent output from stdin and writes human-readable text to
stdout. This runs as part of the output pipeline, so it **must process input line by line**
using a `while read` loop rather than streaming jq on the full input.

Per-line processing is required for two reasons:
1. **Robustness** — a malformed line won't kill jq mid-stream, which would send SIGPIPE back
   through the pipeline and terminate the agent process.
2. **Buffering** — the `while read` loop is inherently line-buffered, ensuring output appears
   on the terminal in real time without needing `jq --unbuffered` or `stdbuf`.

```bash
agent_format_display() {
    while IFS= read -r line; do
        echo "$line" | jq -r 'select(.type=="assistant") | .message.content[] |
            if .type == "text" then .text
            elif .type == "tool_use" then "[tool] " + .name
            else empty end' 2>/dev/null || true
    done
}
```

### Required Variables

Agent scripts **must** set:

| Variable | Purpose | Example |
|----------|---------|---------|
| `AGENT_CLI` | The CLI command name | `amp` |
| `AGENT_INSTALL` | Command to install the agent CLI in the sandbox base image | `npm install -g @sourcegraph/amp` |
| `AGENT_ENV_KEYS` | API-credential env var(s) ralph forwards into the sandbox (space-separated; may be empty) | `AMP_API_KEY` |

Ralph uses `AGENT_CLI` to validate that the agent is installed (via `command -v`).

`AGENT_INSTALL` is injected as the `AGENT_INSTALL` Docker build arg when building
the sandbox base image (see `sandbox_build_base()` in the sandbox spec). This
makes the base image agent-configurable: switching `AGENT` and rebuilding installs
the matching CLI. If an agent script omits `AGENT_INSTALL`, the base image falls
back to its Dockerfile default (Amp).

`AGENT_ENV_KEYS` lists the environment variable(s) holding the agent's API
credentials. Installing an agent's CLI is only half of running it in the sandbox —
it must also authenticate. Ralph exports `AGENT_ENV_KEYS` when rendering the
sandbox so the generated `docker-compose.yml` forwards (pass-through) the right
key(s) into the container and `.env.example` documents them. This makes
authentication agent-configurable the same way `AGENT_INSTALL` makes installation
configurable. The value may be:
- a single var (`AMP_API_KEY` for amp, `ANTHROPIC_API_KEY` for claude),
- derived dynamically (pi derives `<PROVIDER>_API_KEY` from `PI_MODEL`, e.g.
  `OPENROUTER_API_KEY`), or
- empty when the agent authenticates out-of-band (cline, configured via
  `cline auth`); ralph then forwards no agent key.

### Agent-Specific Configuration

Ralph sources `config` **before** the agent script, so agent scripts may read
agent-specific variables defined in `config`. For example, `pi.sh` reads `PI_MODEL`
to select the model passed to the `pi` CLI (e.g. `openrouter/anthropic/claude-3.5-haiku`),
falling back to a built-in default when unset. This keeps model selection in `config`
(versioned with the project and preserved across `ralph update`) rather than
hard-coded in the managed agent script. (A future enhancement could select a
different model per task by keying off the exported `MODE`; the current contract is a
single model per agent.)

**Convention.** Agent-specific config keys are named `<AGENT>_<SETTING>` (e.g.
`PI_MODEL`) and are **shipped commented-out** in `config`, with the real default
living in the agent script's fallback (`PI_MODEL="${PI_MODEL:-...}"`). This keeps
the shared `config` uncluttered for projects that use a different agent, while the
commented line documents the key and makes overriding a one-line edit. Each agent
script owns reading its own keys — no central registry or per-agent config files.
(If a future agent needs several settings, or 3+ agents each carry their own keys,
revisit with a per-agent config section or file; the flat convention is sufficient
until then.)

### Optional Functions

Agent scripts **may** define these functions. Ralph checks for their existence at runtime
(via `type -t`) and calls them if present. If not defined, they are silently skipped.

#### `agent_pre_iteration`

Called before each agent invocation. Useful for capturing pre-iteration state such as account
balance for cost tracking.

```bash
agent_pre_iteration() {
    _BALANCE_BEFORE=$(amp usage 2>/dev/null | grep -o '\$[0-9.]*' | head -1 | tr -d '$')
}
```

#### `agent_post_iteration`

Called after each agent invocation (regardless of success or failure). Useful for computing
and logging per-iteration cost and context window usage. The raw agent output is available
in `$RALPH_DIR/last_agent_output` for extracting usage metadata (e.g., token counts from
the agent's NDJSON stream).

To enable session-level context aggregation, set `_ITER_CONTEXT_PCT` (integer percentage),
`_ITER_CONTEXT_USED` (tokens used), and `_ITER_CONTEXT_MAX` (context window size). The loop
reads these after each iteration to compute min/avg/max for the session summary.

If context usage meets or exceeds `CONTEXT_WARN_PCT` (default: 80), log a warning.

```bash
agent_post_iteration() {
    local balance_after
    balance_after=$(amp usage 2>/dev/null | grep -o '\$[0-9.]*' | head -1 | tr -d '$')
    if [[ -n "${_BALANCE_BEFORE:-}" && -n "$balance_after" ]]; then
        local cost
        cost=$(awk "BEGIN {printf \"%.2f\", $_BALANCE_BEFORE - $balance_after}" 2>/dev/null || true)
        log "Iteration Cost: \$${cost}  Balance: \$${balance_after}"
    fi

    # Extract context window usage from the last assistant message's usage object
    local usage_line
    usage_line=$(grep -o '"usage":{[^}]*}' "$RALPH_DIR/last_agent_output" 2>/dev/null | tail -1)
    if [[ -n "$usage_line" ]]; then
        local input cache_create cache_read output_tok total max_tok pct
        input=$(echo "$usage_line" | grep -o '"input_tokens":[0-9]*' | grep -o '[0-9]*')
        cache_create=$(echo "$usage_line" | grep -o '"cache_creation_input_tokens":[0-9]*' | grep -o '[0-9]*')
        cache_read=$(echo "$usage_line" | grep -o '"cache_read_input_tokens":[0-9]*' | grep -o '[0-9]*')
        output_tok=$(echo "$usage_line" | grep -o '"output_tokens":[0-9]*' | grep -o '[0-9]*')
        max_tok=$(echo "$usage_line" | grep -o '"max_tokens":[0-9]*' | grep -o '[0-9]*')
        total=$(( ${input:-0} + ${cache_create:-0} + ${cache_read:-0} + ${output_tok:-0} ))
        if [[ "${max_tok:-0}" -gt 0 ]]; then
            pct=$(awk "BEGIN {printf \"%.0f\", ($total / $max_tok) * 100}" 2>/dev/null || true)
            log "Context: ${total}/${max_tok} tokens (${pct}%)"
            if [[ "${pct:-0}" -ge "${CONTEXT_WARN_PCT:-80}" ]]; then
                log "⚠ Context usage high — agent quality may degrade"
            fi
            _ITER_CONTEXT_USED=$total
            _ITER_CONTEXT_MAX=$max_tok
            _ITER_CONTEXT_PCT=$pct
        fi
    fi
}
```

Note: Optional hook functions may call `log` (defined by ralph) to write to the session log.

## Adding a New Agent

To add support for a new agent:

1. Create `agents/{name}.sh`
2. Set `AGENT_CLI` to the CLI command name
3. Set `AGENT_INSTALL` to the command that installs the CLI (for sandbox builds)
4. Set `AGENT_ENV_KEYS` to the agent's API-credential env var(s), or `""` if the
   agent authenticates out-of-band (so the sandbox forwards the right key)
5. Implement `agent_invoke`, `agent_extract_response`, and `agent_format_display`
6. Optionally implement `agent_pre_iteration` and `agent_post_iteration`
7. Set `AGENT="{name}"` in config
8. Test with `ralph plan`

The agent CLI must:
- Accept a prompt via stdin
- Produce structured output (typically NDJSON) on stdout
- Run in a non-interactive, auto-approve mode (no human confirmation prompts)

## Example: amp.sh

```bash
AGENT_CLI="amp"
AGENT_ARGS="-x --dangerously-allow-all --stream-json-thinking"

agent_invoke() {
    local prompt_file="$1"
    cat "$prompt_file" | $AGENT_CLI $AGENT_ARGS
}

agent_extract_response() {
    local output_file="$1"
    while IFS= read -r line; do
        echo "$line" | jq -r 'select(.type=="assistant") | .message.content[] | select(.type=="text") | .text' 2>/dev/null || true
    done < "$output_file"
}

agent_format_display() {
    while IFS= read -r line; do
        echo "$line" | jq -r 'select(.type=="assistant") | .message.content[] |
            if .type == "thinking" then "[thinking] " + .thinking
            elif .type == "text" then .text
            elif .type == "tool_use" then "[tool] " + .name + ": " +
                ((.input | (.path // .cmd // .filePattern // .pattern // .query // .url //
                .description // .prompt // (tostring)) | tostring | .[0:200]))
            else empty end' 2>/dev/null || true
    done
}

agent_pre_iteration() {
    _BALANCE_BEFORE=$(amp usage 2>/dev/null | grep -o '\$[0-9.]*' | head -1 | tr -d '$')
}

agent_post_iteration() {
    local balance_after
    balance_after=$(amp usage 2>/dev/null | grep -o '\$[0-9.]*' | head -1 | tr -d '$')
    if [[ -n "${_BALANCE_BEFORE:-}" && -n "$balance_after" ]]; then
        local cost
        cost=$(awk "BEGIN {printf \"%.2f\", $_BALANCE_BEFORE - $balance_after}" 2>/dev/null || true)
        log "Iteration Cost: \$${cost}  Balance: \$${balance_after}"
    fi

    local usage_line
    usage_line=$(grep -o '"usage":{[^}]*}' "$RALPH_DIR/last_agent_output" 2>/dev/null | tail -1)
    if [[ -n "$usage_line" ]]; then
        local input cache_create cache_read output_tok total max_tok pct
        input=$(echo "$usage_line" | grep -o '"input_tokens":[0-9]*' | grep -o '[0-9]*')
        cache_create=$(echo "$usage_line" | grep -o '"cache_creation_input_tokens":[0-9]*' | grep -o '[0-9]*')
        cache_read=$(echo "$usage_line" | grep -o '"cache_read_input_tokens":[0-9]*' | grep -o '[0-9]*')
        output_tok=$(echo "$usage_line" | grep -o '"output_tokens":[0-9]*' | grep -o '[0-9]*')
        max_tok=$(echo "$usage_line" | grep -o '"max_tokens":[0-9]*' | grep -o '[0-9]*')
        total=$(( ${input:-0} + ${cache_create:-0} + ${cache_read:-0} + ${output_tok:-0} ))
        if [[ "${max_tok:-0}" -gt 0 ]]; then
            pct=$(awk "BEGIN {printf \"%.0f\", ($total / $max_tok) * 100}" 2>/dev/null || true)
            log "Context: ${total}/${max_tok} tokens (${pct}%)"
            if [[ "${pct:-0}" -ge "${CONTEXT_WARN_PCT:-80}" ]]; then
                log "⚠ Context usage high — agent quality may degrade"
            fi
            _ITER_CONTEXT_USED=$total
            _ITER_CONTEXT_MAX=$max_tok
            _ITER_CONTEXT_PCT=$pct
        fi
    fi
}
```
