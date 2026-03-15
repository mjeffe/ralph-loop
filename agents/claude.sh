#!/bin/bash
# Agent script for Claude Code (https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)

AGENT_CLI="claude"
# --output-format stream-json: emit one JSON object per line (same schema as amp)
# -p: read prompt from stdin (piped mode)
AGENT_ARGS="--output-format stream-json -p"

# Pipes the prompt file to the claude CLI and streams JSON output to stdout.
agent_invoke() {
    local prompt_file="$1"
    cat "$prompt_file" | $AGENT_CLI $AGENT_ARGS
}

# Extracts only the plain text responses from claude's streaming JSON output,
# filtering for assistant messages and selecting text content blocks.
# Called by check_signals() to scan the response for loop-control signals
# (<promise>COMPLETE</promise> and <promise>REPLAN</promise>).
# Processes line-by-line so malformed lines (stderr leakage, partial writes)
# are skipped rather than aborting the entire parse.
agent_extract_response() {
    local output_file="$1"
    while IFS= read -r line; do
        echo "$line" | jq -r 'select(.type=="assistant") | .message.content[] | select(.type=="text") | .text' 2>/dev/null || true
    done < "$output_file"
}

# Formats claude's streaming JSON into human-readable output for the live display.
# Reads from stdin (piped from agent_invoke via tee in run_iteration).
# Extracts two content types from assistant messages:
#   - text blocks:      displayed as-is
#   - tool_use blocks:  prefixed with [tool], showing just the tool name
#                        (unlike amp.sh, tool inputs are not displayed)
agent_format_display() {
    while IFS= read -r line; do
        echo "$line" | jq -r 'select(.type=="assistant") | .message.content[] |
            if .type == "text" then .text
            elif .type == "tool_use" then "[tool] " + .name
            else empty end' 2>/dev/null || true
    done
}
