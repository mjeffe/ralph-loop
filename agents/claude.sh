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

# Extracts context window usage from the raw NDJSON output. Claude Code's
# stream-json uses the same schema as amp (usage object in assistant messages).
agent_post_iteration() {
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
