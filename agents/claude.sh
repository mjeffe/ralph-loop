#!/bin/bash
# Agent script for Claude Code (https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)

AGENT_CLI="claude"
AGENT_ARGS="--output-format stream-json -p"

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
            if .type == "text" then .text
            elif .type == "tool_use" then "[tool] " + .name
            else empty end' 2>/dev/null || true
    done
}
