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

Ralph uses `AGENT_CLI` to validate that the agent is installed (via `command -v`).

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
and logging per-iteration cost.

```bash
agent_post_iteration() {
    local balance_after
    balance_after=$(amp usage 2>/dev/null | grep -o '\$[0-9.]*' | head -1 | tr -d '$')
    if [[ -n "${_BALANCE_BEFORE:-}" && -n "$balance_after" ]]; then
        local cost
        cost=$(awk "BEGIN {printf \"%.2f\", $_BALANCE_BEFORE - $balance_after}" 2>/dev/null || true)
        log "Iteration Cost: \$${cost}  Balance: \$${balance_after}"
    fi
}
```

Note: Optional hook functions may call `log` (defined by ralph) to write to the session log.

## Adding a New Agent

To add support for a new agent:

1. Create `agents/{name}.sh`
2. Set `AGENT_CLI` to the CLI command name
3. Implement `agent_invoke`, `agent_extract_response`, and `agent_format_display`
4. Optionally implement `agent_pre_iteration` and `agent_post_iteration`
5. Set `AGENT="{name}"` in config
6. Test with `ralph plan`

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
}
```
